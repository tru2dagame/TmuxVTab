import Foundation
import Observation

@MainActor @Observable
final class AgentStateStore {
  private(set) var runtimesByPane: [String: AgentRuntime]

  private let persistenceURL: URL?
  private let staleInterval: TimeInterval

  init(
    persistenceURL: URL? = AgentIPC.defaultStateURL,
    staleInterval: TimeInterval = 24 * 60 * 60,
    now: Date = Date()
  ) {
    self.persistenceURL = persistenceURL
    self.staleInterval = staleInterval
    self.runtimesByPane = Self.load(from: persistenceURL, staleInterval: staleInterval, now: now)
  }

  func runtime(for paneID: String) -> AgentRuntime? {
    runtimesByPane[paneID]
  }

  func preferredRuntime(for panes: [TmuxPane]) -> (pane: TmuxPane, runtime: AgentRuntime)? {
    panes.compactMap { pane in
      runtime(for: pane.id).map { (pane: pane, runtime: $0) }
    }.max { lhs, rhs in
      if lhs.runtime.needsAttention != rhs.runtime.needsAttention {
        return !lhs.runtime.needsAttention
      }
      if lhs.runtime.updatedAt != rhs.runtime.updatedAt {
        return lhs.runtime.updatedAt < rhs.runtime.updatedAt
      }
      return !lhs.pane.isActive && rhs.pane.isActive
    }
  }

  func apply(_ event: AgentEvent) {
    guard event.version == AgentEvent.protocolVersion, !event.paneID.isEmpty else { return }

    if event.kind == .sessionEnded {
      if runtimesByPane[event.paneID]?.sessionID == event.sessionID {
        runtimesByPane.removeValue(forKey: event.paneID)
        persist()
      }
      return
    }

    var runtime: AgentRuntime
    if let existing = runtimesByPane[event.paneID],
       existing.source == event.source,
       existing.sessionID == event.sessionID {
      runtime = existing
    } else {
      runtime = AgentRuntime(
        source: event.source,
        phase: .unknown,
        hookVersion: event.hookVersion,
        permissionMode: event.permissionMode,
        sessionID: event.sessionID,
        turnID: event.turnID,
        transcriptPath: event.transcriptPath,
        cwd: event.cwd,
        model: event.model,
        updatedAt: event.timestamp
      )
    }

    runtime.permissionMode = event.permissionMode ?? runtime.permissionMode
    runtime.hookVersion = event.hookVersion ?? runtime.hookVersion
    runtime.turnID = event.turnID ?? runtime.turnID
    runtime.transcriptPath = event.transcriptPath ?? runtime.transcriptPath
    runtime.cwd = event.cwd ?? runtime.cwd
    runtime.model = event.model ?? runtime.model
    runtime.updatedAt = event.timestamp

    switch event.kind {
    case .sessionStarted:
      runtime.phase = .idle
      runtime.needsAttention = false
      runtime.activity = nil
      runtime.approval = nil
    case .userPrompt:
      runtime.phase = .running
      runtime.question = event.prompt
      runtime.response = nil
      runtime.activity = nil
      runtime.approval = nil
      runtime.needsAttention = false
    case .activity:
      runtime.phase = .running
      runtime.activity = event.detail ?? event.toolName.map { "Using \($0)" }
      runtime.approval = nil
      runtime.needsAttention = false
    case .approvalRequired:
      runtime.phase = .waitingForApproval
      runtime.approval = event.detail ?? event.toolName
      runtime.activity = nil
      runtime.needsAttention = true
    case .completed:
      runtime.phase = .complete
      runtime.response = event.response
      runtime.activity = nil
      runtime.approval = nil
      runtime.needsAttention = true
    case .idle:
      runtime.phase = .idle
      runtime.activity = nil
      runtime.approval = nil
      runtime.needsAttention = true
    case .failed:
      runtime.phase = .error
      runtime.activity = event.detail
      runtime.approval = nil
      runtime.needsAttention = true
    case .notification:
      runtime.activity = event.detail
      runtime.needsAttention = true
    case .subagentStarted:
      if let label = event.subagentType ?? event.subagentID,
         !runtime.subagents.contains(label) {
        runtime.subagents.append(label)
      }
      runtime.phase = .running
      runtime.needsAttention = false
    case .subagentStopped:
      if let label = event.subagentType ?? event.subagentID {
        runtime.subagents.removeAll { $0 == label }
      }
    case .sessionEnded:
      break
    }

    runtimesByPane[event.paneID] = runtime
    persist()
  }

  func runningCodexTurns(for panes: [TmuxPane]) -> [CodexTurnCompletionCandidate] {
    var seenPaneIDs: Set<String> = []
    return panes.compactMap { pane in
      guard seenPaneIDs.insert(pane.id).inserted,
            let runtime = runtime(for: pane.id),
            runtime.source == .codex,
            runtime.phase == .running,
            let turnID = runtime.turnID,
            let transcriptPath = runtime.transcriptPath
      else { return nil }

      return CodexTurnCompletionCandidate(
        paneID: pane.id,
        turnID: turnID,
        transcriptPath: transcriptPath
      )
    }
  }

  func markCodexTurnComplete(_ completion: CodexTurnCompletion) {
    guard var runtime = runtimesByPane[completion.paneID],
          runtime.source == .codex,
          runtime.phase == .running,
          runtime.turnID == completion.turnID
    else { return }

    runtime.phase = .complete
    runtime.activity = nil
    runtime.approval = nil
    runtime.needsAttention = true
    runtime.updatedAt = max(runtime.updatedAt, completion.timestamp)
    runtimesByPane[completion.paneID] = runtime
    persist()
  }

  private func persist() {
    guard let persistenceURL else { return }
    do {
      try AgentIPC.ensurePrivateDirectory(persistenceURL.deletingLastPathComponent())
      let data = try JSONEncoder.tmuxVTab.encode(runtimesByPane)
      try data.write(to: persistenceURL, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: persistenceURL.path
      )
    } catch {
      fputs("[TmuxVTab] Failed to persist agent state: \(error)\n", stderr)
    }
  }

  private static func load(
    from url: URL?,
    staleInterval: TimeInterval,
    now: Date
  ) -> [String: AgentRuntime] {
    guard let url,
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder.tmuxVTab.decode([String: AgentRuntime].self, from: data)
    else { return [:] }

    return decoded.filter { _, runtime in
      now.timeIntervalSince(runtime.updatedAt) <= staleInterval
    }
  }
}

extension JSONEncoder {
  fileprivate static var tmuxVTab: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}

extension JSONDecoder {
  fileprivate static var tmuxVTab: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
  }
}
