import AppKit
import Foundation

@MainActor @Observable
final class TmuxService {
  var sessions: [TmuxSession] = []
  var isConnected = false
  var error: String?
  var previewLineLimit = PreviewLineLimit.defaultValue

  private var pollingTask: Task<Void, Never>?
  private let tmuxPath: String?
  private let agentStore: AgentStateStore

  init(agentStore: AgentStateStore) {
    self.agentStore = agentStore
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
      async let configuredPreviewLineLimit = fetchPreviewLineLimit(tmuxPath: tmuxPath)
      var newSessions = try await fetchSessions(tmuxPath: tmuxPath)
      let newPreviewLineLimit = await configuredPreviewLineLimit
      log("Got \(newSessions.count) sessions")

      // Merge structured local hook state from every pane in each window. The
      // displayed pane is the one needing attention or most recently updated.
      for i in newSessions.indices {
        for j in newSessions[i].windows.indices {
          let window = newSessions[i].windows[j]
          if let selected = agentStore.preferredRuntime(for: window.panes) {
            newSessions[i].windows[j] = window.selecting(
              pane: selected.pane,
              runtime: selected.runtime
            )
          }
        }
      }

      // Detect agents in every pane (one ps call for all), not only the active
      // pane represented by tmux's list-windows format.
      let allPanes = newSessions.flatMap(\.windows).flatMap(\.panes)
      let runningPids = allPanes.filter(\.isRunningTask).map(\.pid).filter { $0 > 0 }

      if !runningPids.isEmpty {
        let agentMap = await detectAgents(for: runningPids)
        for i in newSessions.indices {
          for j in newSessions[i].windows.indices {
            let window = newSessions[i].windows[j]
            guard window.agentRuntime == nil else { continue }
            let agentPanes = window.panes.filter { agentMap[$0.pid] != nil }
            if let pane = agentPanes.first(where: \.isActive) ?? agentPanes.first,
               let agent = agentMap[pane.pid] {
              newSessions[i].windows[j] = window.selecting(
                pane: pane,
                detectedAgent: agent
              )
            }
          }
        }
      }

      sessions = newSessions
      previewLineLimit = newPreviewLineLimit
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

  /// Jumps the attached tmux client to the given pane, then activates Ghostty.
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

  /// Applies a just-received hook update without waiting for the next tmux poll.
  func applyAgentRuntime(for paneID: String) {
    var updated = sessions
    var changed = false
    for i in updated.indices {
      for j in updated[i].windows.indices {
        let window = updated[i].windows[j]
        guard window.panes.contains(where: { $0.id == paneID }) else { continue }
        if let selected = agentStore.preferredRuntime(for: window.panes) {
          updated[i].windows[j] = window.selecting(
            pane: selected.pane,
            runtime: selected.runtime
          )
        } else if let activePane = window.panes.first(where: \.isActive) ?? window.panes.first {
          updated[i].windows[j] = window.selecting(pane: activePane)
        }
        changed = true
      }
    }
    if changed { sessions = updated }
  }

  private func activateGhostty() {
    guard let app = NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.mitchellh.ghostty"
    ).first else { return }
    app.activate()
  }

  // MARK: - Tmux Fetching

  private func fetchPreviewLineLimit(tmuxPath: String) async -> Int {
    let rawValue = try? await run(
      tmuxPath,
      arguments: ["show-option", "-gqv", "@tmuxvtab-preview-lines"]
    )
    return PreviewLineLimit.parse(rawValue)
  }

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
    let output = try await run(
      tmuxPath,
      arguments: [
        "list-panes", "-s", "-t", "\(sessionName):", "-F",
        "#{window_index}\t#{window_name}\t#{window_active}\t#{window_bell_flag}\t#{pane_active}\t#{pane_current_command}\t#{pane_pid}\t#{pane_id}",
      ]
    )
    return Self.parseWindows(output, sessionName: sessionName)
  }

  static func parseWindows(_ output: String, sessionName: String) -> [TmuxWindow] {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    struct WindowGroup {
      let windowName: String
      let isActive: Bool
      let hasBell: Bool
      var panes: [TmuxPane]
    }

    var groups: [Int: WindowGroup] = [:]
    for line in trimmed.split(whereSeparator: \.isNewline) {
      let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard parts.count >= 8, let windowIndex = Int(String(parts[0])) else { continue }
      let pane = TmuxPane(
        id: String(parts[7]),
        pid: Int(String(parts[6])) ?? 0,
        currentCommand: String(parts[5]),
        isActive: String(parts[4]) == "1"
      )

      if groups[windowIndex] == nil {
        groups[windowIndex] = WindowGroup(
          windowName: String(parts[1]),
          isActive: String(parts[2]) == "1",
          hasBell: String(parts[3]) == "1",
          panes: []
        )
      }
      groups[windowIndex]?.panes.append(pane)
    }

    return groups.keys.sorted().compactMap { windowIndex in
      guard let group = groups[windowIndex],
            let pane = group.panes.first(where: \.isActive) ?? group.panes.first
      else { return nil }
      return TmuxWindow(
        sessionName: sessionName,
        windowIndex: windowIndex,
        windowName: group.windowName,
        isActive: group.isActive,
        hasBell: group.hasBell,
        currentCommand: pane.currentCommand,
        panePid: pane.pid,
        paneId: pane.id,
        panes: group.panes
      )
    }
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
