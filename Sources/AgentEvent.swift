import Foundation

enum AgentSource: String, Codable, Hashable, Sendable {
  case claude
  case codex

  var detectedAgent: DetectedAgent {
    switch self {
    case .claude: .claudeCode
    case .codex: .codex
    }
  }
}

enum AgentEventKind: String, Codable, Hashable, Sendable {
  case sessionStarted
  case userPrompt
  case activity
  case approvalRequired
  case completed
  case idle
  case failed
  case notification
  case subagentStarted
  case subagentStopped
  case sessionEnded
}

/// Versioned, local-only event sent by the short-lived hook client to TmuxVTab.
/// Text fields are bounded by `AgentHookNormalizer` before they reach the socket.
struct AgentEvent: Codable, Hashable, Sendable {
  static let protocolVersion = 1

  let version: Int
  let hookVersion: String?
  let source: AgentSource
  let kind: AgentEventKind
  let sessionID: String
  let turnID: String?
  let paneID: String
  let transcriptPath: String?
  let cwd: String?
  let model: String?
  let permissionMode: String?
  let prompt: String?
  let response: String?
  let detail: String?
  let toolName: String?
  let subagentID: String?
  let subagentType: String?
  let timestamp: Date

  init(
    source: AgentSource,
    kind: AgentEventKind,
    sessionID: String,
    hookVersion: String? = nil,
    turnID: String? = nil,
    paneID: String,
    transcriptPath: String? = nil,
    cwd: String? = nil,
    model: String? = nil,
    permissionMode: String? = nil,
    prompt: String? = nil,
    response: String? = nil,
    detail: String? = nil,
    toolName: String? = nil,
    subagentID: String? = nil,
    subagentType: String? = nil,
    timestamp: Date = Date()
  ) {
    self.version = Self.protocolVersion
    self.hookVersion = hookVersion
    self.source = source
    self.kind = kind
    self.sessionID = sessionID
    self.turnID = turnID
    self.paneID = paneID
    self.transcriptPath = transcriptPath
    self.cwd = cwd
    self.model = model
    self.permissionMode = permissionMode
    self.prompt = prompt
    self.response = response
    self.detail = detail
    self.toolName = toolName
    self.subagentID = subagentID
    self.subagentType = subagentType
    self.timestamp = timestamp
  }
}

enum AgentHookNormalizer {
  static let maximumInputBytes = 1_048_576
  static let maximumPromptLength = 1_000
  static let maximumResponseLength = 1_000
  static let maximumDetailLength = 500
  static let maximumMetadataLength = 300

  static func normalize(
    agentHint: String,
    eventHint: String,
    input: Data,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    timestamp: Date = Date()
  ) -> AgentEvent? {
    guard input.count <= maximumInputBytes,
          let payload = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
          let source = source(agentHint: agentHint, payload: payload, environment: environment),
          let paneID = firstString(environment["TMUX_PANE"], payload["tmux_pane"] as? String),
          !paneID.isEmpty
    else { return nil }

    let rawEvent = (payload["hook_event_name"] as? String) ?? eventHint
    guard let baseKind = eventKind(rawEvent) else { return nil }
    let kind = refinedKind(baseKind, payload: payload)

    let sessionID = bounded(payload["session_id"] as? String, maximumMetadataLength) ?? "unknown"
    let toolInput = payload["tool_input"] as? [String: Any]
    let toolName = bounded(payload["tool_name"] as? String, maximumMetadataLength)

    let detail: String?
    switch kind {
    case .approvalRequired:
      detail = bounded(
        firstString(
          toolInput?["description"] as? String,
          toolInput?["command"] as? String,
          toolInput?["file_path"] as? String,
          payload["message"] as? String,
          toolName
        ),
        maximumDetailLength
      )
    case .activity:
      detail = bounded(
        firstString(toolInput?["description"] as? String, toolName),
        maximumDetailLength
      )
    case .failed:
      detail = bounded(
        firstString(
          payload["last_assistant_message"] as? String,
          payload["error_details"] as? String,
          payload["error"] as? String
        ),
        maximumDetailLength
      )
    case .notification, .idle:
      detail = bounded(payload["message"] as? String, maximumDetailLength)
    default:
      detail = nil
    }

    return AgentEvent(
      source: source,
      kind: kind,
      sessionID: sessionID,
      hookVersion: bounded(environment["TMUXVTAB_HOOK_VERSION"], maximumMetadataLength),
      turnID: bounded(payload["turn_id"] as? String, maximumMetadataLength),
      paneID: bounded(paneID, maximumMetadataLength) ?? paneID,
      transcriptPath: bounded(payload["transcript_path"] as? String, 4_096),
      cwd: bounded(payload["cwd"] as? String, maximumMetadataLength),
      model: bounded(payload["model"] as? String, maximumMetadataLength),
      permissionMode: bounded(payload["permission_mode"] as? String, maximumMetadataLength),
      prompt: kind == .userPrompt
        ? bounded(payload["prompt"] as? String, maximumPromptLength)
        : nil,
      response: kind == .completed
        ? bounded(payload["last_assistant_message"] as? String, maximumResponseLength)
        : nil,
      detail: detail,
      toolName: toolName,
      subagentID: bounded(payload["agent_id"] as? String, maximumMetadataLength),
      subagentType: bounded(payload["agent_type"] as? String, maximumMetadataLength),
      timestamp: timestamp
    )
  }

  static func eventKind(_ raw: String) -> AgentEventKind? {
    switch raw.replacingOccurrences(of: "-", with: "").lowercased() {
    case "sessionstart": .sessionStarted
    case "userpromptsubmit": .userPrompt
    case "posttooluse": .activity
    case "permissionrequest": .approvalRequired
    case "stop": .completed
    case "stopfailure": .failed
    case "notification": .notification
    case "subagentstart": .subagentStarted
    case "subagentstop": .subagentStopped
    case "sessionend": .sessionEnded
    default: nil
    }
  }

  private static func refinedKind(
    _ kind: AgentEventKind,
    payload: [String: Any]
  ) -> AgentEventKind {
    guard kind == .notification,
          let notificationType = payload["notification_type"] as? String
    else { return kind }

    switch notificationType.lowercased() {
    case "idle_prompt":
      return .idle
    case "permission_prompt", "agent_needs_input":
      return .approvalRequired
    default:
      return kind
    }
  }

  private static func source(
    agentHint: String,
    payload: [String: Any],
    environment: [String: String]
  ) -> AgentSource? {
    switch agentHint.lowercased() {
    case "claude": return .claude
    case "codex": return .codex
    case "auto":
      // Codex plugin hooks set PLUGIN_ROOT (and CLAUDE_PLUGIN_ROOT for
      // compatibility). Claude only sets CLAUDE_PLUGIN_ROOT. turn_id is a
      // second, payload-level Codex signal for direct test invocations.
      if environment["PLUGIN_ROOT"]?.isEmpty == false || payload["turn_id"] != nil {
        return .codex
      }
      return .claude
    default:
      return nil
    }
  }

  private static func firstString(_ values: String?...) -> String? {
    values.first { value in
      guard let value else { return false }
      return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    } ?? nil
  }

  private static func bounded(_ value: String?, _ limit: Int) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.count <= limit { return trimmed }
    return String(trimmed.prefix(limit)) + "…"
  }
}
