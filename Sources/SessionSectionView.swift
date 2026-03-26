import SwiftUI

struct SessionSectionView: View {
  let session: TmuxSession
  @State private var isExpanded = true
  @Environment(\.sidebarFontScale) private var fontScale

  var body: some View {
    VStack(spacing: 0) {
      // Session header
      Button {
        withAnimation(.snappy(duration: 0.2)) {
          isExpanded.toggle()
        }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "chevron.right")
            .scaledFont(size: 10, weight: .semibold)
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .frame(width: 12)

          Text(session.name)
            .scaledFont(size: 13, weight: .semibold)
            .foregroundStyle(.secondary)
            .lineLimit(1)

          Spacer()

          Text("\(session.windows.count)")
            .scaledFont(size: 10)
            .foregroundStyle(.quaternary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.3), in: .capsule)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)

      // Windows
      if isExpanded {
        ForEach(session.windows) { window in
          WindowRowView(window: window)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .padding(.vertical, 4)
    .background(
      session.isAttached
        ? RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06))
        : nil
    )
  }
}
