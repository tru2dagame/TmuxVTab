import Foundation
import SwiftUI

// MARK: - Agent preview theme
enum ThemeColor {
  // Agent labels
  static let agentClaude   = rgb(215, 135, 135) // 174 — soft coral
  static let agentCodex    = rgb(175, 135, 215) // 141 — soft purple
  static let agentOpenCode = rgb( 95, 215, 255) // 117 — soft cyan
  // Status
  static let statusRunning = rgb(135, 215, 135) // 114
  static let statusWaiting = rgb(255, 215,  95) // 221
  static let statusIdle    = rgb(135, 175, 215) // 110
  static let statusError   = rgb(215,  95,  95) // 167
  static let statusUnknown = rgb(128, 128, 128) // 244
  static let statusBg      = rgb(135, 175, 215) // 110
  // Text
  static let textActive    = rgb(238, 238, 238) // 255
  static let textMuted     = rgb(208, 208, 208) // 252
  static let textInactive  = rgb(128, 128, 128) // 244
  // Accents
  static let responseArrow = rgb( 95, 215, 255) // 81  — cyan
  static let waitReason    = rgb(255, 215,  95) // 221 — yellow
  static let subagent      = rgb( 95, 175, 175) // 73  — teal
  static let taskProgress  = rgb(255, 215, 175) // 223 — soft gold
  // Permission badges
  static let badgeDanger   = rgb(215,  95,  95) // 167
  static let badgeAuto     = rgb(255, 215,  95) // 221
  static let badgePlan     = rgb( 95, 215, 255) // 117

  private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
    Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
  }
}

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
  /// Live agent runtime sourced from TmuxVTab's local hook event socket.
  /// `nil` when no supported hook has emitted an event for this pane.
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

// MARK: - Agent Runtime (local hook socket)

enum AgentPhase: String, Codable, Hashable, Sendable {
  case running
  case waitingForApproval
  case complete
  case idle
  case error
  case unknown

  var label: String {
    switch self {
    case .running: "working"
    case .waitingForApproval: "needs approval"
    case .complete: "done"
    case .idle: "ready"
    case .error: "error"
    case .unknown: "unknown"
    }
  }
}

struct PermissionBadge: Hashable, Sendable {
  let label: String
  let kind: Kind

  enum Kind: Hashable, Sendable { case danger, auto, plan, muted }

  var color: Color {
    switch kind {
    case .danger: return ThemeColor.badgeDanger
    case .auto:   return ThemeColor.badgeAuto
    case .plan:   return ThemeColor.badgePlan
    case .muted:  return ThemeColor.textInactive
    }
  }
}

/// The reduced, display-safe state retained for one tmux pane. It deliberately
/// stores previews rather than complete transcripts.
struct AgentRuntime: Codable, Hashable, Sendable {
  let source: AgentSource
  var phase: AgentPhase
  var permissionMode: String?
  var sessionID: String
  var turnID: String?
  var cwd: String?
  var model: String?
  var question: String?
  var response: String?
  var activity: String?
  var approval: String?
  var subagents: [String]
  var needsAttention: Bool
  var updatedAt: Date

  init(
    source: AgentSource,
    phase: AgentPhase,
    permissionMode: String? = nil,
    sessionID: String,
    turnID: String? = nil,
    cwd: String? = nil,
    model: String? = nil,
    question: String? = nil,
    response: String? = nil,
    activity: String? = nil,
    approval: String? = nil,
    subagents: [String] = [],
    needsAttention: Bool = false,
    updatedAt: Date = Date()
  ) {
    self.source = source
    self.phase = phase
    self.permissionMode = permissionMode
    self.sessionID = sessionID
    self.turnID = turnID
    self.cwd = cwd
    self.model = model
    self.question = question
    self.response = response
    self.activity = activity
    self.approval = approval
    self.subagents = subagents
    self.needsAttention = needsAttention
    self.updatedAt = updatedAt
  }

  var permissionBadge: PermissionBadge? {
    guard let mode = permissionMode, !mode.isEmpty else { return nil }
    switch mode {
    case "bypassPermissions": return PermissionBadge(label: "!",       kind: .danger)
    case "plan":              return PermissionBadge(label: "plan",    kind: .plan)
    case "acceptEdits":       return PermissionBadge(label: "edit",    kind: .auto)
    case "auto":              return PermissionBadge(label: "auto",    kind: .auto)
    case "dontAsk":           return PermissionBadge(label: "dontAsk", kind: .auto)
    case "defer":             return PermissionBadge(label: "defer",   kind: .auto)
    case "default":           return nil
    default:                  return PermissionBadge(label: mode,      kind: .muted)
    }
  }

  var detectedAgent: DetectedAgent { source.detectedAgent }
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
