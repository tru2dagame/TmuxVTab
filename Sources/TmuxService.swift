import AppKit
import Foundation

@MainActor @Observable
final class TmuxService {
  var sessions: [TmuxSession] = []
  var isConnected = false
  var error: String?

  private var pollingTask: Task<Void, Never>?
  private let tmuxPath: String?

  init() {
    self.tmuxPath = Self.findTmux()
    if let tmuxPath {
      log("Found tmux at: \(tmuxPath)")
    } else {
      log("tmux not found in any known path")
    }
  }

  private func log(_ message: String) {
    fputs("[TmuxVTab] \(message)\n", stderr)
  }

  var totalWindows: Int {
    sessions.reduce(0) { $0 + $1.windows.count }
  }

  func startPolling() {
    stopPolling()
    pollingTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        await self.refresh()
        try? await Task.sleep(for: .seconds(3))
      }
    }
  }

  func stopPolling() {
    pollingTask?.cancel()
    pollingTask = nil
  }

  func refresh() async {
    guard let tmuxPath else {
      isConnected = false
      error = "tmux not found"
      sessions = []
      return
    }

    do {
      log("Refreshing sessions...")
      var newSessions = try await fetchSessions(tmuxPath: tmuxPath)
      log("Got \(newSessions.count) sessions")

      // Detect agents for windows with running tasks (one ps call for all)
      let allWindows = newSessions.flatMap(\.windows)
      let runningPids = allWindows.filter(\.isRunningTask).map(\.panePid).filter { $0 > 0 }

      if !runningPids.isEmpty {
        let agentMap = await detectAgents(for: runningPids)
        for i in newSessions.indices {
          for j in newSessions[i].windows.indices {
            let pid = newSessions[i].windows[j].panePid
            if let agent = agentMap[pid] {
              newSessions[i].windows[j].detectedAgent = agent
            }
          }
        }
      }

      // For panes that have hook-driven agent state, pull the latest prompt
      // out-of-band. We use show-options instead of the bulk list-windows
      // format because prompt text can contain newlines.
      let agentPaneIds = allWindows.compactMap { window in
        window.agentRuntime != nil && !window.paneId.isEmpty ? window.paneId : nil
      }
      if !agentPaneIds.isEmpty {
        let promptMap = await fetchPanePrompts(tmuxPath: tmuxPath, paneIds: agentPaneIds)
        for i in newSessions.indices {
          for j in newSessions[i].windows.indices {
            let paneId = newSessions[i].windows[j].paneId
            guard var runtime = newSessions[i].windows[j].agentRuntime,
                  let entry = promptMap[paneId] else { continue }
            runtime.prompt = entry.prompt
            runtime.promptSource = entry.source
            newSessions[i].windows[j].agentRuntime = runtime
          }
        }
      }

      sessions = newSessions
      isConnected = true
      error = nil
    } catch {
      log("Refresh error: \(error)")
      if "\(error)".contains("no server running") || "\(error)".contains("no current client") {
        sessions = []
        isConnected = true
        self.error = nil
      } else {
        isConnected = false
        self.error = error.localizedDescription
      }
    }
  }

  // MARK: - Pane Navigation

  /// Jumps the attached tmux client to the given window, then activates
  /// Ghostty so the user immediately sees the result. Mirrors
  /// `tmux-agent-sidebar::select_pane`: switch-client → select-window → select-pane.
  func jumpTo(window: TmuxWindow) async {
    guard let tmuxPath else { return }
    let target = "\(window.sessionName):\(window.windowIndex)"
    // switch-client without -c retargets the most recently attached client
    // — that's the Ghostty terminal the user is looking at.
    _ = try? await run(tmuxPath, arguments: ["switch-client", "-t", window.sessionName])
    _ = try? await run(tmuxPath, arguments: ["select-window", "-t", target])
    if !window.paneId.isEmpty {
      _ = try? await run(tmuxPath, arguments: ["select-pane", "-t", window.paneId])
    }
    activateGhostty()
    // Refresh once promptly so the active window indicator updates without
    // waiting for the next 3s poll tick.
    await refresh()
  }

  private func activateGhostty() {
    guard let app = NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.mitchellh.ghostty"
    ).first else { return }
    app.activate()
  }

  // MARK: - Tmux Fetching

  private func fetchSessions(tmuxPath: String) async throws -> [TmuxSession] {
    let sessionOutput = try await run(
      tmuxPath,
      arguments: ["list-sessions", "-F", "#{session_name}\t#{session_windows}\t#{session_attached}"]
    )
    let trimmed = sessionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    var results: [TmuxSession] = []
    for line in trimmed.split(whereSeparator: \.isNewline) {
      let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard let nameSubstring = parts.first else { continue }
      let name = String(nameSubstring)
      let windowCount = parts.count > 1 ? Int(String(parts[1])) ?? 0 : 0
      let isAttached = parts.count > 2 && String(parts[2]) != "0"

      let windows = try await fetchWindows(tmuxPath: tmuxPath, sessionName: name)
      results.append(TmuxSession(name: name, windows: windows, windowCount: windowCount, isAttached: isAttached))
    }
    return results
  }

  private func fetchWindows(tmuxPath: String, sessionName: String) async throws -> [TmuxWindow] {
    // Fields 6–13 are tmux-agent-sidebar hook-written pane options. They resolve
    // against the window's active pane and are empty strings when the plugin is
    // not installed or hasn't fired an event for that pane yet.
    let output = try await run(
      tmuxPath,
      arguments: [
        "list-windows", "-t", sessionName, "-F",
        "#{window_index}\t#{window_name}\t#{window_active}\t#{window_bell_flag}\t#{pane_current_command}\t#{pane_pid}\t#{pane_id}\t#{@pane_agent}\t#{@pane_status}\t#{@pane_permission_mode}\t#{@pane_attention}\t#{@pane_wait_reason}\t#{@pane_session_id}\t#{@pane_subagents}",
      ]
    )
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    return trimmed.split(whereSeparator: \.isNewline).compactMap { line in
      let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard parts.count >= 7, let windowIndex = Int(String(parts[0])) else { return nil }
      let panePid = Int(String(parts[5])) ?? 0
      let paneId = String(parts[6])

      let agentName = parts.count > 7 ? String(parts[7]) : ""
      let subagentsRaw = nonEmpty(parts, 13) ?? ""
      let subagents = subagentsRaw
        .split(separator: ",", omittingEmptySubsequences: true)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
      let runtime: AgentRuntime? = agentName.isEmpty
        ? nil
        : AgentRuntime(
            agent: agentName,
            status: PaneStatus(raw: parts.count > 8 ? String(parts[8]) : ""),
            permissionMode: nonEmpty(parts, 9),
            attention: nonEmpty(parts, 10),
            waitReason: nonEmpty(parts, 11),
            sessionId: nonEmpty(parts, 12),
            subagents: subagents
          )

      return TmuxWindow(
        sessionName: sessionName,
        windowIndex: windowIndex,
        windowName: String(parts[1]),
        isActive: String(parts[2]) == "1",
        hasBell: String(parts[3]) == "1",
        currentCommand: String(parts[4]),
        panePid: panePid,
        paneId: paneId,
        agentRuntime: runtime
      )
    }
  }

  // MARK: - Prompt Fetching

  /// Fetches `@pane_prompt` + `@pane_prompt_source` for the given panes
  /// concurrently. Each value comes from its own `tmux show-options -v`
  /// call so multi-line prompts round-trip safely.
  private func fetchPanePrompts(
    tmuxPath: String,
    paneIds: [String]
  ) async -> [String: (prompt: String?, source: PromptSource?)] {
    await withTaskGroup(of: (String, String?, PromptSource?).self) { group in
      for paneId in paneIds {
        group.addTask { [self] in
          async let promptRaw = self.readPaneOption(tmuxPath: tmuxPath, paneId: paneId, option: "@pane_prompt")
          async let sourceRaw = self.readPaneOption(tmuxPath: tmuxPath, paneId: paneId, option: "@pane_prompt_source")
          let prompt = await promptRaw
          let source = await sourceRaw.flatMap(PromptSource.init(rawValue:))
          return (paneId, prompt, source)
        }
      }
      var result: [String: (prompt: String?, source: PromptSource?)] = [:]
      for await (paneId, prompt, source) in group {
        result[paneId] = (prompt, source)
      }
      return result
    }
  }

  /// Returns the raw value of a per-pane tmux option, or nil when unset/missing.
  private func readPaneOption(tmuxPath: String, paneId: String, option: String) async -> String? {
    guard let raw = try? await run(tmuxPath, arguments: ["show-options", "-p", "-v", "-t", paneId, option]) else {
      return nil
    }
    // `show-options -v` always appends a trailing newline; strip exactly one
    // to preserve any newlines that are part of the value itself.
    var trimmed = raw
    if trimmed.hasSuffix("\n") { trimmed.removeLast() }
    if trimmed.hasSuffix("\r") { trimmed.removeLast() }
    return trimmed.isEmpty ? nil : trimmed
  }

  private func nonEmpty(_ parts: [Substring], _ index: Int) -> String? {
    guard index < parts.count else { return nil }
    let s = String(parts[index])
    return s.isEmpty ? nil : s
  }

  // MARK: - Agent Detection

  /// Detects known coding agents by walking the process tree from each pane PID.
  /// Does a single `ps` call and checks all PIDs at once.
  private func detectAgents(for panePids: [Int]) async -> [Int: DetectedAgent] {
    guard let psOutput = try? await run("/bin/ps", arguments: ["-eo", "pid,ppid,args"]) else {
      return [:]
    }

    // Parse ps output into (pid, ppid, args) tuples
    struct PSEntry {
      let pid: Int
      let ppid: Int
      let args: String
    }

    var entries: [PSEntry] = []
    var childrenOf: [Int: [Int]] = [:]

    for line in psOutput.split(whereSeparator: \.isNewline) {
      let cols = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
      guard cols.count >= 3,
        let pid = Int(cols[0]),
        let ppid = Int(cols[1])
      else { continue }
      let args = String(cols[2])
      entries.append(PSEntry(pid: pid, ppid: ppid, args: args))
      childrenOf[ppid, default: []].append(pid)
    }

    // Index args by PID for quick lookup
    let argsByPid = Dictionary(entries.map { ($0.pid, $0.args) }, uniquingKeysWith: { first, _ in first })

    // For each pane PID, walk descendants and check for known agents
    var result: [Int: DetectedAgent] = [:]

    for panePid in panePids {
      if let agent = findAgent(rootPid: panePid, childrenOf: childrenOf, argsByPid: argsByPid) {
        result[panePid] = agent
      }
    }

    return result
  }

  /// BFS through process tree looking for known agent patterns in args.
  private func findAgent(
    rootPid: Int,
    childrenOf: [Int: [Int]],
    argsByPid: [Int: String]
  ) -> DetectedAgent? {
    var queue = [rootPid]
    var visited: Set<Int> = []

    while !queue.isEmpty {
      let pid = queue.removeFirst()
      guard visited.insert(pid).inserted else { continue }

      if let args = argsByPid[pid] {
        let lower = args.lowercased()
        for (pattern, agent) in DetectedAgent.patterns {
          if lower.contains(pattern) {
            return agent
          }
        }
      }

      if let children = childrenOf[pid] {
        queue.append(contentsOf: children)
      }
    }
    return nil
  }

  // MARK: - Shell

  /// Runs a process on a background thread to avoid blocking the main actor.
  private func run(_ executable: String, arguments: [String]) async throws -> String {
    let env = {
      var env = ProcessInfo.processInfo.environment
      let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
      if let existing = env["PATH"] {
        env["PATH"] = "\(extraPaths):\(existing)"
      } else {
        env["PATH"] = extraPaths
      }
      return env
    }()

    return try await Task.detached {
      let process = Process()
      let pipe = Pipe()
      let errorPipe = Pipe()

      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      process.standardOutput = pipe
      process.standardError = errorPipe
      process.environment = env

      try process.run()

      // Read pipe data BEFORE waitUntilExit to prevent deadlock
      // when output exceeds the pipe buffer size (~64KB).
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()

      if process.terminationStatus == 0 {
        return String(data: data, encoding: .utf8) ?? ""
      } else {
        let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
        throw TmuxError(message: errorOutput)
      }
    }.value
  }

  private static func findTmux() -> String? {
    let paths = [
      "/opt/homebrew/bin/tmux",
      "/usr/local/bin/tmux",
      "/usr/bin/tmux",
      "/run/current-system/sw/bin/tmux",
    ]
    for path in paths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }
    return nil
  }
}

struct TmuxError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}
