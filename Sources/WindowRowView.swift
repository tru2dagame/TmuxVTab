import SwiftUI

struct WindowRowView: View {
  let window: TmuxWindow
  let onSelect: () -> Void
  @Environment(\.sidebarFontScale) private var fontScale
  @Environment(\.agentPreviewLineLimit) private var agentPreviewLineLimit
  @State private var isHovering = false

  /// Agent inferred from the hook plugin if available, falling back to ps-walk detection.
  private var effectiveAgent: DetectedAgent? {
    window.agentRuntime?.detectedAgent ?? window.detectedAgent
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      // Status icon
      ZStack {
        if window.hasBell {
          Image(systemName: "bell.fill")
            .scaledFont(size: 10)
            .foregroundStyle(.orange)
        } else if let agent = effectiveAgent {
          Image(systemName: agent.icon)
            .scaledFont(size: 10, weight: .medium)
            .foregroundStyle(iconForeground(agent: agent))
            .symbolEffect(.pulse, options: .repeating, isActive: isPulsing)
        } else if window.isRunningTask {
          ProgressView()
            .controlSize(.mini)
        } else {
          Image(systemName: "terminal")
            .scaledFont(size: 10, weight: .medium)
            .foregroundStyle(window.isActive ? .yellow : Color(red: 0.55, green: 0.36, blue: 0.85))
        }
      }
      .frame(width: 14 * fontScale, height: 14 * fontScale)
      // Pull the icon down so it baselines with the first text line, not the
      // top of the multi-line block.
      .padding(.top, 1)

      VStack(alignment: .leading, spacing: 1) {
        // Status row: window name + permission badge
        HStack(spacing: 6) {
          Text(window.windowName)
            .scaledFont(size: 13, weight: window.isActive ? .semibold : .regular, design: .monospaced)
            .foregroundStyle(window.isActive ? .primary : .secondary)
            .lineLimit(1)
            .truncationMode(.tail)

          if let badge = window.agentRuntime?.permissionBadge {
            badgeView(badge)
          }
        }

        subtitle

        if let runtime = window.agentRuntime {
          if runtime.hookCompatibility != .current {
            hookWarning(runtime)
          }

          if !runtime.subagents.isEmpty {
            ForEach(Array(runtime.subagents.enumerated()), id: \.offset) { idx, name in
              Text("\(idx == runtime.subagents.count - 1 ? "└" : "├") \(name)")
                .scaledFont(size: 10, design: .monospaced)
                .foregroundStyle(ThemeColor.subagent)
                .lineLimit(1)
                .truncationMode(.tail)
            }
          }

          if let question = runtime.question {
            previewBlock(question, marker: "›", color: ThemeColor.textMuted)
          }

          if runtime.phase == .waitingForApproval, let approval = runtime.approval {
            previewBlock(approval, marker: "!", color: ThemeColor.statusWaiting)
          } else if let activity = runtime.activity {
            previewBlock(
              activity,
              marker: runtime.phase == .error ? "×" : "·",
              color: runtime.phase == .error ? ThemeColor.statusError : ThemeColor.taskProgress,
              lineLimit: 1
            )
          }

          if let response = runtime.response {
            previewBlock(response, marker: "✓", color: ThemeColor.responseArrow)
          } else if runtime.phase == .idle {
            Text("Waiting for prompt…")
              .scaledFont(size: 10, design: .monospaced)
              .foregroundStyle(window.isActive ? ThemeColor.textActive : ThemeColor.textInactive)
              .lineLimit(1)
          }
        } else if effectiveAgent == .claudeCode || effectiveAgent == .codex {
          Text("Preview inactive · tmuxvtab hooks check")
            .scaledFont(size: 9, design: .monospaced)
            .foregroundStyle(ThemeColor.statusWaiting)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }

      Spacer(minLength: 4)

      // Per-pane status / active indicator. Hook attention overrides everything.
      Group {
        if let runtime = window.agentRuntime, runtime.needsAttention {
          Circle().fill(.orange).frame(width: 7, height: 7)
        } else if let runtime = window.agentRuntime, let color = statusDotColor(runtime.phase) {
          Circle().fill(color).frame(width: 7, height: 7)
        } else if window.isActive {
          Circle().fill(.green).frame(width: 7, height: 7)
        }
      }
      .padding(.top, 6)
    }
    .padding(.horizontal, 8)
    .padding(.leading, 12)
    .padding(.vertical, 5)
    .contentShape(.rect(cornerRadius: 6))
    .background(rowBackground, in: .rect(cornerRadius: 6))
    .onHover { hovering in
      isHovering = hovering
      if hovering {
        NSCursor.pointingHand.push()
      } else {
        NSCursor.pop()
      }
    }
    .onTapGesture { onSelect() }
    .help("Jump to \(window.sessionName):\(window.windowIndex) \(window.windowName)")
  }

  private var rowBackground: AnyShapeStyle {
    if window.isActive {
      return AnyShapeStyle(.quaternary.opacity(0.3))
    }
    if isHovering {
      return AnyShapeStyle(.quaternary.opacity(0.15))
    }
    return AnyShapeStyle(.clear)
  }

  @ViewBuilder
  private var subtitle: some View {
    if let runtime = window.agentRuntime {
      Text(runtimeSubtitle(runtime))
        .scaledFont(size: 10, design: .monospaced)
        .foregroundStyle(runtimeSubtitleColor(runtime))
        .lineLimit(1)
    } else if window.isRunningTask {
      Text(window.displayCommand)
        .scaledFont(size: 10, design: .monospaced)
        .foregroundStyle(effectiveAgent.map { agentColor($0).opacity(0.8) } ?? Color.gray.opacity(0.6))
        .lineLimit(1)
    }
  }

  @ViewBuilder
  private func badgeView(_ badge: PermissionBadge) -> some View {
    Text(badge.label)
      .scaledFont(size: 9, weight: .semibold, design: .monospaced)
      .foregroundStyle(badge.color)
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(badge.color.opacity(0.18), in: .capsule)
      .overlay(Capsule().stroke(badge.color.opacity(0.35), lineWidth: 0.5))
      .fixedSize()
  }

  @ViewBuilder
  private func previewBlock(
    _ text: String,
    marker: String,
    color: Color,
    lineLimit: Int? = nil
  ) -> some View {
    HStack(alignment: .top, spacing: 4) {
      Text(marker)
        .scaledFont(size: 10, weight: .bold, design: .monospaced)
        .foregroundStyle(color)
        .frame(width: 8)
        .padding(.top, 1)
      Text(text)
        .scaledFont(size: 10, design: .monospaced)
        .foregroundStyle(window.isActive ? ThemeColor.textActive : ThemeColor.textInactive)
        .lineLimit(lineLimit ?? agentPreviewLineLimit)
        .truncationMode(.tail)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private func hookWarning(_ runtime: AgentRuntime) -> some View {
    let message = switch runtime.hookCompatibility {
    case .hookUpdateRequired:
      "Hook \(runtime.hookVersion ?? "?") · update available"
    case .appUpdateRequired:
      "Hook \(runtime.hookVersion ?? "?") · update TmuxVTab"
    case .unknown:
      "Hook version unknown · run hooks check"
    case .current:
      ""
    }
    if !message.isEmpty {
      Text(message)
        .scaledFont(size: 9, weight: .medium, design: .monospaced)
        .foregroundStyle(ThemeColor.statusWaiting)
        .lineLimit(1)
        .truncationMode(.tail)
    }
  }

  private func runtimeSubtitle(_ runtime: AgentRuntime) -> String {
    "\(runtime.detectedAgent.label) · \(runtime.phase.label)"
  }

  private func runtimeSubtitleColor(_ runtime: AgentRuntime) -> Color {
    switch runtime.phase {
    case .error: return ThemeColor.statusError
    case .waitingForApproval: return ThemeColor.statusWaiting
    case .running: return effectiveAgent.map { agentColor($0) } ?? ThemeColor.statusRunning
    case .complete, .idle: return ThemeColor.statusIdle
    case .unknown: return ThemeColor.statusUnknown
    }
  }

  private func statusDotColor(_ phase: AgentPhase) -> Color? {
    switch phase {
    case .running: return ThemeColor.statusRunning
    case .waitingForApproval: return ThemeColor.statusWaiting
    case .error: return ThemeColor.statusError
    case .complete: return ThemeColor.statusIdle
    case .idle, .unknown: return nil
    }
  }

  private var isPulsing: Bool {
    guard let runtime = window.agentRuntime else { return true }
    return runtime.phase == .running || runtime.needsAttention
  }

  private func iconForeground(agent: DetectedAgent) -> Color {
    if let runtime = window.agentRuntime {
      if runtime.needsAttention { return .orange }
      switch runtime.phase {
      case .error: return ThemeColor.statusError
      case .waitingForApproval: return ThemeColor.statusWaiting
      case .complete, .idle: return ThemeColor.statusIdle
      case .running, .unknown: break
      }
    }
    return agentColor(agent)
  }

  private func agentColor(_ agent: DetectedAgent) -> Color {
    switch agent {
    case .claudeCode: ThemeColor.agentClaude
    case .codex: ThemeColor.agentCodex
    case .aider: .cyan
    case .copilot: .blue
    }
  }
}
