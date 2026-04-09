import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, @unchecked Sendable {
  private var panel: FloatingPanel?
  private let tmuxService = TmuxService()
  private let ghosttyMonitor = GhosttyMonitor()
  private var runningObservation: Any?
  private var frameObservation: Any?
  private var activeObservation: Any?
  private var fullscreenObservation: Any?
  private var signalSource: DispatchSourceSignal?
  private let settings = UserDefaults(suiteName: "app.tru2dagame.tmuxvtab")!

  // Persisted settings (read from UserDefaults)
  private var dockSide: String = "left"
  private var alwaysOnTop: Bool = false
  private var floatMode: Bool = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    loadSettings()
    setupSignalHandler()
    ghosttyMonitor.start()
    createPanel()
    observeGhosttyState()
    observeGhosttyFrame()
    observeGhosttyActive()
    observeGhosttyFullscreen()

    if ghosttyMonitor.isGhosttyRunning {
      showPanel()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    tmuxService.stopPolling()
  }

  // Close button terminates the app immediately
  func windowWillClose(_ notification: Notification) {
    NSApp.terminate(nil)
  }

  // MARK: - Settings

  private func loadSettings() {
    settings.synchronize()
    dockSide = settings.string(forKey: "dockSide") ?? "left"
    alwaysOnTop = settings.bool(forKey: "alwaysOnTop")
    floatMode = settings.bool(forKey: "floatMode")
  }

  private func applySettings() {
    loadSettings()
    if shouldFloat {
      panel?.isMovableByWindowBackground = true
    } else {
      panel?.isMovableByWindowBackground = false
      snapToGhostty()
    }
    updatePanelLevel()
  }

  // MARK: - Signal Handler (SIGUSR1 = reload settings)

  private func setupSignalHandler() {
    signal(SIGUSR1, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
    source.setEventHandler { [weak self] in
      Task { @MainActor [weak self] in
        self?.applySettings()
      }
    }
    source.resume()
    signalSource = source
  }

  // MARK: - Panel

  private func createPanel() {
    let defaultRect = NSRect(x: 0, y: 0, width: 240, height: 600)
    let panel = FloatingPanel(contentRect: defaultRect)
    panel.delegate = self

    let contentView = SidebarContentView(
      tmuxService: tmuxService,
      ghosttyMonitor: ghosttyMonitor
    )
    panel.contentView = NSHostingView(rootView: contentView)
    self.panel = panel
  }

  private func showPanel() {
    if !shouldFloat {
      snapToGhostty()
    }
    updatePanelLevel()
    panel?.showPanel()
    tmuxService.startPolling()
  }

  private func hidePanel() {
    panel?.hidePanel()
    tmuxService.stopPolling()
  }

  // MARK: - Positioning

  /// Whether the panel should float freely (not track Ghostty).
  private var shouldFloat: Bool {
    floatMode || ghosttyMonitor.isGhosttyFullscreen
  }

  /// Dock mode: snap panel outside Ghostty's edge, tracking its position.
  private func snapToGhostty() {
    // In float mode, don't follow Ghostty
    guard !shouldFloat else { return }
    guard let panel, let ghosttyFrame = ghosttyMonitor.ghosttyWindowFrame else { return }

    let panelWidth = panel.frame.width
    let x: CGFloat = dockSide == "right"
      ? ghosttyFrame.maxX
      : ghosttyFrame.minX - panelWidth
    let newFrame = NSRect(
      x: x,
      y: ghosttyFrame.minY,
      width: panelWidth,
      height: ghosttyFrame.height
    )

    if panel.frame != newFrame {
      panel.setFrame(newFrame, display: true, animate: false)
    }
  }

  /// Float mode: position panel on the right side of the screen, full height.
  private func positionFloatPanel() {
    guard let panel else { return }
    let screen = NSScreen.main ?? NSScreen.screens.first
    guard let screenFrame = screen?.visibleFrame else { return }

    let panelWidth = panel.frame.width
    let newFrame = NSRect(
      x: screenFrame.maxX - panelWidth,
      y: screenFrame.minY,
      width: panelWidth,
      height: screenFrame.height
    )
    panel.setFrame(newFrame, display: true, animate: false)
  }

  private func updatePanelLevel() {
    guard let panel else { return }
    if alwaysOnTop {
      panel.level = .floating
    } else {
      panel.level = ghosttyMonitor.isGhosttyActive ? .floating : .normal
    }
  }

  // MARK: - Observations

  private func observeGhosttyState() {
    runningObservation = withObservationTracking {
      _ = ghosttyMonitor.isGhosttyRunning
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if self.ghosttyMonitor.isGhosttyRunning {
          self.showPanel()
        } else {
          self.hidePanel()
        }
        self.observeGhosttyState()
      }
    }
  }

  private func observeGhosttyFrame() {
    frameObservation = withObservationTracking {
      _ = ghosttyMonitor.ghosttyWindowFrame
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.snapToGhostty()
        self.observeGhosttyFrame()
      }
    }
  }

  private func observeGhosttyActive() {
    activeObservation = withObservationTracking {
      _ = ghosttyMonitor.isGhosttyActive
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.updatePanelLevel()
        self.observeGhosttyActive()
      }
    }
  }

  private func observeGhosttyFullscreen() {
    fullscreenObservation = withObservationTracking {
      _ = ghosttyMonitor.isGhosttyFullscreen
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if self.ghosttyMonitor.isGhosttyFullscreen {
          self.panel?.isMovableByWindowBackground = true
          // Re-order to move panel into Ghostty's new fullscreen Space
          self.panel?.orderFront(nil)
          self.positionFloatPanel()
        } else {
          // Exiting fullscreen → always restore dock mode
          self.floatMode = false
          self.settings.set(false, forKey: "floatMode")
          self.panel?.isMovableByWindowBackground = false
          self.snapToGhostty()
        }
        self.updatePanelLevel()
        self.observeGhosttyFullscreen()
      }
    }
  }
}
