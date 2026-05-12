import Foundation
import SwiftUI

// MARK: - Theme (mirrors hiroppy/tmux-agent-sidebar 256-color palette)

/// SwiftUI colors converted from the ANSI 256-color indices used by
/// tmux-agent-sidebar's default `ColorTheme`. Keeping the same RGB
/// values keeps the two UIs visually compatible.
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
  static let statusBg      = rgb(135, 175, 215) // 110 (background == idle hue)
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

/// Permission badge mirrors hiroppy's `PermissionMode::badge()` labels and
/// `theme.badge_*` colors so the visual cue is consistent across sidebars.
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

  /// Trimmed prompt with leading/trailing whitespace removed; newlines kept
  /// for multi-line rendering (SwiftUI `Text` wraps them naturally).
  var promptDisplay: String? {
    guard let prompt else { return nil }
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Mirrors hiroppy's `PermissionMode::badge()` mapping. Returns nil for
  /// the default mode (no badge shown).
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

  /// Human-readable wait reason mirroring hiroppy's `wait_reason_label`.
  var waitReasonLabel: String? {
    guard let raw = waitReason, !raw.isEmpty else { return nil }
    switch raw {
    case "permission_prompt":       return "permission required"
    case "idle_prompt":              return "waiting for input"
    case "auth_success":             return "auth success"
    case "elicitation_dialog":       return "waiting for selection"
    case "rate_limit":               return "rate limit"
    case "permission_denied":        return "permission denied"
    case "session_resumed":          return "resumed"
    case "session_resumed_compact":  return "resumed (compact)"
    default:
      if let rest = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init).asTeammateIdlePayload() {
        return rest
      }
      return raw
    }
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

private extension Array where Element == String {
  /// Parses a `teammate_idle:Name[:Why]` split into a friendly label.
  /// Returns nil when the head is not `teammate_idle`.
  func asTeammateIdlePayload() -> String? {
    guard count >= 2, self[0] == "teammate_idle" else { return nil }
    let rest = self[1]
    let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    if parts.count == 2, !parts[1].isEmpty {
      return "\(parts[0]) idle (\(parts[1]))"
    }
    return "\(rest) idle"
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
