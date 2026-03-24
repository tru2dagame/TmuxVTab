import SwiftUI

struct WindowRowView: View {
  let window: TmuxWindow
  @Environment(\.sidebarFontScale) private var fontScale

  var body: some View {
    HStack(spacing: 8) {
      // Status icon
      ZStack {
        if window.hasBell {
          Image(systemName: "bell.fill")
            .scaledFont(size: 10)
            .foregroundStyle(.orange)
        } else if let agent = window.detectedAgent {
          Image(systemName: agent.icon)
            .scaledFont(size: 10, weight: .medium)
            .foregroundStyle(agentColor(agent))
            .symbolEffect(.pulse, options: .repeating)
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

      // Window name + subtitle
      VStack(alignment: .leading, spacing: 1) {
        Text(window.windowName)
          .scaledFont(size: 13, weight: window.isActive ? .semibold : .regular, design: .monospaced)
          .foregroundStyle(window.isActive ? .primary : .secondary)
          .lineLimit(1)

        if window.isRunningTask {
          if let agent = window.detectedAgent {
            Text(window.displayCommand)
              .scaledFont(size: 10, design: .monospaced)
              .foregroundStyle(agentColor(agent).opacity(0.8))
              .lineLimit(1)
          } else {
            Text(window.displayCommand)
              .scaledFont(size: 10, design: .monospaced)
              .foregroundStyle(.tertiary)
              .lineLimit(1)
          }
        }
      }

      Spacer(minLength: 4)

      // Active indicator
      if window.isActive {
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

  private func agentColor(_ agent: DetectedAgent) -> Color {
    switch agent {
    case .claudeCode: Color(red: 0.85, green: 0.55, blue: 0.3)
    case .codex: .green
    case .aider: .cyan
    case .copilot: .blue
    }
  }
}
