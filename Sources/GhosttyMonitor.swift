import AppKit

private let ghosttyBundleID = "com.mitchellh.ghostty"

@MainActor @Observable
final class GhosttyMonitor {
  var isGhosttyRunning = false
  var isGhosttyActive = false
  var isGhosttyFullscreen = false
  /// Ghostty's main window frame in NS coordinates (origin bottom-left).
  var ghosttyWindowFrame: NSRect?

  private var framePollingTask: Task<Void, Never>?

  func start() {
    isGhosttyRunning = Self.checkGhosttyRunning()
    isGhosttyActive = Self.checkGhosttyActive()
    if isGhosttyRunning {
      updateGhosttyWindowFrame()
      startFramePolling()
    }

    let workspace = NSWorkspace.shared.notificationCenter

    workspace.addObserver(
      forName: NSWorkspace.didLaunchApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
        app.bundleIdentifier == ghosttyBundleID
      else { return }
      MainActor.assumeIsolated {
        self?.isGhosttyRunning = true
        self?.updateGhosttyWindowFrame()
        self?.startFramePolling()
      }
    }

    workspace.addObserver(
      forName: NSWorkspace.didTerminateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
        app.bundleIdentifier == ghosttyBundleID
      else { return }
      MainActor.assumeIsolated {
        self?.isGhosttyRunning = false
        self?.isGhosttyActive = false
        self?.ghosttyWindowFrame = nil
        self?.stopFramePolling()
      }
    }

    // Track ALL app activations to know when Ghostty gains/loses focus
    workspace.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      else { return }
      MainActor.assumeIsolated {
        let wasActive = self?.isGhosttyActive ?? false
        self?.isGhosttyActive = app.bundleIdentifier == ghosttyBundleID
        if self?.isGhosttyActive == true {
          self?.updateGhosttyWindowFrame()
        }
        // Resume/pause frame polling based on Ghostty focus
        if self?.isGhosttyActive == true && !wasActive {
          self?.startFramePolling()
        } else if self?.isGhosttyActive == false && wasActive {
          self?.stopFramePolling()
        }
      }
    }
  }

  // MARK: - Frame Polling

  private func startFramePolling() {
    stopFramePolling()
    framePollingTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(300))
        guard let self else { return }
        self.updateGhosttyWindowFrame()
      }
    }
  }

  private func stopFramePolling() {
    framePollingTask?.cancel()
    framePollingTask = nil
  }

  // MARK: - Window Detection

  func updateGhosttyWindowFrame() {
    guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]]
    else { return }

    guard let screenHeight = NSScreen.main?.frame.height else { return }

    for info in windowInfo {
      guard let ownerName = info[kCGWindowOwnerName as String] as? String,
        ownerName == "Ghostty",
        let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
        let cgX = boundsDict["X"],
        let cgY = boundsDict["Y"],
        let width = boundsDict["Width"],
        let height = boundsDict["Height"],
        width > 100, height > 100
      else { continue }

      let nsY = screenHeight - cgY - height
      let newFrame = NSRect(x: cgX, y: nsY, width: width, height: height)

      if ghosttyWindowFrame != newFrame {
        ghosttyWindowFrame = newFrame
      }

      // Detect fullscreen: window covers entire screen
      let fullscreen = NSScreen.screens.contains { screen in
        abs(width - screen.frame.width) < 2 && abs(height - screen.frame.height) < 2
      }
      if isGhosttyFullscreen != fullscreen {
        isGhosttyFullscreen = fullscreen
      }
      return
    }
  }

  private static func checkGhosttyRunning() -> Bool {
    NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == TmuxVTab.ghosttyBundleID }
  }

  private static func checkGhosttyActive() -> Bool {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier == TmuxVTab.ghosttyBundleID
  }
}
