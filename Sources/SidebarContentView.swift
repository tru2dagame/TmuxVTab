import SwiftUI

struct SidebarContentView: View {
  @State var tmuxService: TmuxService
  @State var ghosttyMonitor: GhosttyMonitor
  @AppStorage("fontScale") private var fontScale: Double = 1.0
  @State private var dockSide: String = UserDefaults(suiteName: "app.tru2dagame.tmuxvtab")?.string(forKey: "dockSide") ?? "left"
  @State private var alwaysOnTop: Bool = UserDefaults(suiteName: "app.tru2dagame.tmuxvtab")?.bool(forKey: "alwaysOnTop") ?? false
  private let settings = UserDefaults(suiteName: "app.tru2dagame.tmuxvtab")!

  var body: some View {
    VStack(spacing: 0) {
      // Drag area in titlebar region
      Color.clear
        .frame(height: 28)

      if tmuxService.sessions.isEmpty {
        emptyState
      } else {
        sessionList
      }

      footer
    }
    .environment(\.sidebarFontScale, fontScale)
    .background(Color.black.opacity(0.50))
    .background(.ultraThinMaterial)
    .preferredColorScheme(.dark)
    .contextMenu {
      Menu("Font Size") {
        Button("Larger") { fontScale = min(fontScale + 0.1, 2.0) }
        Button("Smaller") { fontScale = max(fontScale - 0.1, 0.6) }
        Button("Reset") { fontScale = 1.0 }
      }

      Divider()

      Menu("Dock Side") {
        Button {
          setSetting("dockSide", string: "left")
        } label: {
          if dockSide == "left" { Text("Left  \u{2713}") } else { Text("Left") }
        }
        Button {
          setSetting("dockSide", string: "right")
        } label: {
          if dockSide == "right" { Text("Right  \u{2713}") } else { Text("Right") }
        }
      }

      Button(alwaysOnTop ? "Unpin (Follow Focus)" : "Pin (Always on Top)") {
        setSetting("alwaysOnTop", bool: !alwaysOnTop)
      }

      Divider()

      Button("Quit") {
        NSApp.terminate(nil)
      }
    }
  }

  // MARK: - Settings Helpers

  private func setSetting(_ key: String, string value: String) {
    settings.set(value, forKey: key)
    if key == "dockSide" { dockSide = value }
    kill(getpid(), SIGUSR1)
  }

  private func setSetting(_ key: String, bool value: Bool) {
    settings.set(value, forKey: key)
    if key == "alwaysOnTop" { alwaysOnTop = value }
    kill(getpid(), SIGUSR1)
  }

  // MARK: - Session List

  private var sessionList: some View {
    ScrollView {
      LazyVStack(spacing: 2) {
        ForEach(tmuxService.sessions) { session in
          SessionSectionView(session: session)
        }
      }
      .padding(.horizontal, 8)
      .padding(.top, 4)
    }
    .scrollIndicators(.never)
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: 12) {
      Spacer()
      Image(systemName: "terminal")
        .font(.system(size: 32, weight: .thin))
        .foregroundStyle(.tertiary)
      if tmuxService.error != nil {
        Text("tmux not available")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        Text("No sessions")
          .font(.callout)
          .foregroundStyle(.secondary)
        Text("Start a tmux session in Ghostty")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(tmuxService.isConnected ? .green : .red.opacity(0.7))
        .frame(width: 6, height: 6)

      if tmuxService.sessions.isEmpty {
        Text("tmux")
          .font(.caption)
          .foregroundStyle(.tertiary)
      } else {
        Text("\(tmuxService.sessions.count) sessions")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.tertiary)
        Text("·")
          .foregroundStyle(.quaternary)
        Text("\(tmuxService.totalWindows) windows")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.tertiary)
      }

      Spacer()

      if !ghosttyMonitor.isGhosttyRunning {
        Image(systemName: "moon.zzz")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .help("Ghostty is not running")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.ultraThinMaterial)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(.quaternary)
        .frame(height: 0.5)
    }
  }
}
