import Foundation

struct TmuxSession: Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  var windows: [TmuxWindow]
  let windowCount: Int

  init(name: String, windows: [TmuxWindow] = [], windowCount: Int = 0) {
    self.id = name
    self.name = name
    self.windows = windows
    self.windowCount = windowCount
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
  /// Detected coding agent running in this window (e.g., "Claude Code", "Codex").
  var detectedAgent: DetectedAgent?

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
    detectedAgent: DetectedAgent? = nil
  ) {
    self.id = "\(sessionName):\(windowIndex)"
    self.sessionName = sessionName
    self.windowIndex = windowIndex
    self.windowName = windowName
    self.isActive = isActive
    self.hasBell = hasBell
    self.currentCommand = currentCommand
    self.panePid = panePid
    self.detectedAgent = detectedAgent
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
