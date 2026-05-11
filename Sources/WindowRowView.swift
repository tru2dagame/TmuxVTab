import SwiftUI

struct WindowRowView: View {
  let window: TmuxWindow
  @Environment(\.sidebarFontScale) private var fontScale

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
          // Subagents (hiroppy uses ├ / └ tree connectors, teal text)
          if !runtime.subagents.isEmpty {
            ForEach(Array(runtime.subagents.enumerated()), id: \.offset) { idx, name in
              Text("\(idx == runtime.subagents.count - 1 ? "└" : "├") \(name)")
                .scaledFont(size: 10, design: .monospaced)
                .foregroundStyle(ThemeColor.subagent)
                .lineLimit(1)
                .truncationMode(.tail)
            }
          }

          // Wait reason
          if let label = runtime.waitReasonLabel {
            Text(label)
              .scaledFont(size: 10, design: .monospaced)
              .foregroundStyle(runtime.status == .error ? ThemeColor.statusError : ThemeColor.waitReason)
              .lineLimit(1)
              .truncationMode(.tail)
          }

          // Prompt: multi-line wrapped, up to 3 lines.
          // Responses get a leading cyan `▷` arrow on the first line (hiroppy convention).
          if let preview = runtime.promptDisplay {
            promptBlock(preview, isResponse: runtime.promptSource == .response)
          } else if runtime.status == .idle {
            Text("Waiting for prompt…")
              .scaledFont(size: 10, design: .monospaced)
              .foregroundStyle(window.isActive ? ThemeColor.textActive : ThemeColor.textInactive)
              .lineLimit(1)
          }
        }
      }

      Spacer(minLength: 4)

      // Per-pane status / active indicator. Hook attention overrides everything.
      Group {
        if let runtime = window.agentRuntime, runtime.needsAttention {
          Circle().fill(.orange).frame(width: 7, height: 7)
        } else if let runtime = window.agentRuntime, let color = statusDotColor(runtime.status) {
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
    .background(
      window.isActive
        ? AnyShapeStyle(.quaternary.opacity(0.3))
        : AnyShapeStyle(.clear),
      in: .rect(cornerRadius: 6)
    )
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

  /// Renders the prompt block. For responses, the first line is prefixed with
  /// a cyan ▷ arrow; the rest wraps under the body indent. For user prompts
  /// the body is plain, with a 2-character leading gutter to match hiroppy.
  @ViewBuilder
  private func promptBlock(_ text: String, isResponse: Bool) -> some View {
    HStack(alignment: .top, spacing: 4) {
      if isResponse {
        Text("▷")
          .scaledFont(size: 10, weight: .bold, design: .monospaced)
          .foregroundStyle(ThemeColor.responseArrow)
          .padding(.top, 1)
      } else {
        // Empty gutter that visually matches the response arrow column width
        // so user prompts line up with response continuation lines.
        Text(" ")
          .scaledFont(size: 10, design: .monospaced)
          .frame(width: 8)
      }
      Text(text)
        .scaledFont(size: 10, design: .monospaced)
        .foregroundStyle(window.isActive ? ThemeColor.textActive : ThemeColor.textInactive)
        .lineLimit(3)
        .truncationMode(.tail)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func runtimeSubtitle(_ runtime: AgentRuntime) -> String {
    let label = runtime.detectedAgent?.label ?? runtime.agent.capitalized
    return "\(label) · \(runtime.status.rawValue)"
  }

  private func runtimeSubtitleColor(_ runtime: AgentRuntime) -> Color {
    switch runtime.status {
    case .error: return ThemeColor.statusError
    case .waiting: return ThemeColor.statusWaiting
    case .running: return effectiveAgent.map { agentColor($0) } ?? ThemeColor.statusRunning
    case .background: return ThemeColor.statusBg
    case .idle: return ThemeColor.statusIdle
    case .unknown: return ThemeColor.statusUnknown
    }
  }

  private func statusDotColor(_ status: PaneStatus) -> Color? {
    switch status {
    case .running: return ThemeColor.statusRunning
    case .waiting: return ThemeColor.statusWaiting
    case .error: return ThemeColor.statusError
    case .background: return ThemeColor.statusBg
    case .idle, .unknown: return nil
    }
  }

  private var isPulsing: Bool {
    guard let runtime = window.agentRuntime else { return true }
    return runtime.status == .running || runtime.needsAttention
  }

  private func iconForeground(agent: DetectedAgent) -> Color {
    if let runtime = window.agentRuntime {
      if runtime.needsAttention { return .orange }
      switch runtime.status {
      case .error: return ThemeColor.statusError
      case .waiting: return ThemeColor.statusWaiting
      case .idle: return ThemeColor.statusIdle
      case .background: return ThemeColor.statusBg
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
