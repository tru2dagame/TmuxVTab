import Foundation

struct TmuxSession: Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  var windows: [TmuxWindow]
  let windowCount: Int
  let isAttached: Bool

  init(name: String, windows: [TmuxWindow] = [], windowCount: Int = 0, isAttached: Bool = false) {
    self.id = name
    self.name = name
    self.windows = windows
    self.windowCount = windowCount
    self.isAttached = isAttached
  }
}

struct TmuxWindow: Identifiable, Hashable, Sendable {
  let id: String
  let sessionName: String
  let windowIndex: Int
  let windowName: String
  let isActive: Bool
  let hasBell: Bool
  let currentCommand: String
  let panePid: Int
  let paneId: String
  /// Detected coding agent running in this window (e.g., "Claude Code", "Codex").
  var detectedAgent: DetectedAgent?
  /// Live agent runtime sourced from tmux-agent-sidebar hook-written pane options.
  /// `nil` when the hook plugin is absent or has not yet emitted an event for this pane.
  var agentRuntime: AgentRuntime?

  var target: String { "\(sessionName):\(windowIndex)" }

  var isRunningTask: Bool {
    let shells: Set<String> = ["zsh", "bash", "fish", "sh", "dash", "tcsh", "ksh", "nu", "elvish"]
    return !shells.contains(currentCommand)
  }

  /// Display label for the subtitle: agent name if detected, otherwise raw command.
  var displayCommand: String {
    detectedAgent?.label ?? currentCommand
  }

  init(
    sessionName: String,
    windowIndex: Int,
    windowName: String,
    isActive: Bool,
    hasBell: Bool = false,
    currentCommand: String = "",
    panePid: Int = 0,
    paneId: String = "",
    detectedAgent: DetectedAgent? = nil,
    agentRuntime: AgentRuntime? = nil
  ) {
    self.id = "\(sessionName):\(windowIndex)"
    self.sessionName = sessionName
    self.windowIndex = windowIndex
    self.windowName = windowName
    self.isActive = isActive
    self.hasBell = hasBell
    self.currentCommand = currentCommand
    self.panePid = panePid
    self.paneId = paneId
    self.detectedAgent = detectedAgent
    self.agentRuntime = agentRuntime
  }
}

// MARK: - Agent Runtime (hook-driven)

/// Per-pane status reported by the tmux-agent-sidebar hook plugin
/// (`@pane_status`). Mirrors hiroppy/tmux-agent-sidebar's `PaneStatus`.
enum PaneStatus: String, Hashable, Sendable {
  case running
  case background
  case waiting
  case idle
  case error
  case unknown

  init(raw: String) {
    self = PaneStatus(rawValue: raw) ?? .unknown
  }
}

/// Source of the most recent text stored in `@pane_prompt`.
enum PromptSource: String, Hashable, Sendable {
  case user      // user-submitted prompt (UserPromptSubmit hook)
  case response  // agent's last response preview (Stop hook)
}

/// Snapshot of agent state for a single pane, populated by
/// tmux-agent-sidebar hooks via `@pane_*` tmux options.
struct AgentRuntime: Hashable, Sendable {
  let agent: String         // "claude" / "codex" / "opencode"
  let status: PaneStatus
  let permissionMode: String?
  let attention: String?    // "notification" when the agent wants attention
  let waitReason: String?
  let sessionId: String?
  let subagents: [String]   // active subagent labels (already include "#N" suffix when set by hook)
  /// Latest prompt or response text the hook has captured. Fetched out-of-band
  /// because it can contain newlines that would break tab/pipe-delimited parsing.
  var prompt: String?
  var promptSource: PromptSource?

  init(
    agent: String,
    status: PaneStatus,
    permissionMode: String? = nil,
    attention: String? = nil,
    waitReason: String? = nil,
    sessionId: String? = nil,
    subagents: [String] = [],
    prompt: String? = nil,
    promptSource: PromptSource? = nil
  ) {
    self.agent = agent
    self.status = status
    self.permissionMode = permissionMode
    self.attention = attention
    self.waitReason = waitReason
    self.sessionId = sessionId
    self.subagents = subagents
    self.prompt = prompt
    self.promptSource = promptSource
  }

  var needsAttention: Bool { attention == "notification" }

  /// Single-line, collapsed prompt preview suitable for a sidebar row.
  var promptPreview: String? {
    guard let prompt, !prompt.isEmpty else { return nil }
    let collapsed = prompt
      .replacingOccurrences(of: "\r\n", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\t", with: " ")
    let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Maps the hook-reported agent name onto our `DetectedAgent` enum for icon reuse.
  var detectedAgent: DetectedAgent? {
    switch agent {
    case "claude": .claudeCode
    case "codex": .codex
    default: nil
    }
  }
}

// MARK: - Agent Detection

enum DetectedAgent: String, Hashable, Sendable {
  case claudeCode
  case codex
  case aider
  case copilot

  var label: String {
    switch self {
    case .claudeCode: "Claude Code"
    case .codex: "Codex"
    case .aider: "Aider"
    case .copilot: "Copilot"
    }
  }

  var icon: String {
    switch self {
    case .claudeCode: "sparkles"
    case .codex: "cpu"
    case .aider: "bubble.left.and.text.bubble.right"
    case .copilot: "airplane"
    }
  }

  /// Patterns matched against the full `ps` args of descendant processes.
  static let patterns: [(substring: String, agent: DetectedAgent)] = [
    ("claude", .claudeCode),
    ("@anthropic-ai/claude-code", .claudeCode),
    ("codex", .codex),
    ("@openai/codex", .codex),
    ("aider", .aider),
    ("github-copilot", .copilot),
  ]
}
