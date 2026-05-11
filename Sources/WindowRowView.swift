import SwiftUI

struct WindowRowView: View {
  let window: TmuxWindow
  @Environment(\.sidebarFontScale) private var fontScale

  /// Agent inferred from the hook plugin if available, falling back to ps-walk detection.
  private var effectiveAgent: DetectedAgent? {
    window.agentRuntime?.detectedAgent ?? window.detectedAgent
  }

  var body: some View {
    HStack(spacing: 8) {
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

      // Window name + subtitle + optional prompt preview
      VStack(alignment: .leading, spacing: 1) {
        Text(window.windowName)
          .scaledFont(size: 13, weight: window.isActive ? .semibold : .regular, design: .monospaced)
          .foregroundStyle(window.isActive ? .primary : .secondary)
          .lineLimit(1)

        subtitle

        if let runtime = window.agentRuntime, let preview = runtime.promptPreview {
          HStack(spacing: 4) {
            Text(runtime.promptSource == .response ? "◂" : "▸")
              .scaledFont(size: 9, weight: .bold, design: .monospaced)
              .foregroundStyle(promptArrowColor(runtime.promptSource))
            Text(preview)
              .scaledFont(size: 10, design: .monospaced)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.tail)
          }
        }
      }

      Spacer(minLength: 4)

      // Per-pane status / active indicator. Hook attention overrides everything.
      if let runtime = window.agentRuntime, runtime.needsAttention {
        Circle()
          .fill(.orange)
          .frame(width: 7, height: 7)
      } else if let runtime = window.agentRuntime, let color = statusDotColor(runtime.status) {
        Circle()
          .fill(color)
          .frame(width: 7, height: 7)
      } else if window.isActive {
        Circle()
          .fill(.green)
          .frame(width: 7, height: 7)
      }
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

  private func runtimeSubtitle(_ runtime: AgentRuntime) -> String {
    let label = runtime.detectedAgent?.label ?? runtime.agent.capitalized
    if let reason = runtime.waitReason, !reason.isEmpty {
      return "\(label) · \(runtime.status.rawValue) (\(reason))"
    }
    return "\(label) · \(runtime.status.rawValue)"
  }

  private func runtimeSubtitleColor(_ runtime: AgentRuntime) -> Color {
    switch runtime.status {
    case .error: return .red.opacity(0.85)
    case .waiting: return .orange.opacity(0.85)
    case .running: return effectiveAgent.map { agentColor($0).opacity(0.85) } ?? .green.opacity(0.85)
    case .background: return .blue.opacity(0.75)
    case .idle: return Color.gray.opacity(0.65)
    case .unknown: return Color.gray.opacity(0.5)
    }
  }

  private func statusDotColor(_ status: PaneStatus) -> Color? {
    switch status {
    case .running: return .green
    case .waiting: return .yellow
    case .error: return .red
    case .background: return .blue
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
      case .error: return .red
      case .waiting: return .yellow
      case .idle: return Color.gray
      case .background: return .blue
      case .running, .unknown: break
      }
    }
    return agentColor(agent)
  }

  private func promptArrowColor(_ source: PromptSource?) -> Color {
    switch source {
    case .user: return effectiveAgent.map { agentColor($0) } ?? .blue
    case .response: return Color.gray.opacity(0.7)
    case .none: return Color.gray.opacity(0.5)
    }
  }

  private func agentColor(_ agent: DetectedAgent) -> Color {
    switch agent {
    case .claudeCode: Color(red: 0.85, green: 0.55, blue: 0.3)
    case .codex: .green
    case .aider: .cyan
    case .copilot: .blue
    }
  }
}
