import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    isFloatingPanel = true
    level = .floating
    isOpaque = false
    backgroundColor = .clear
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = false  // Position controlled by Ghostty tracking
    collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    hasShadow = false
    animationBehavior = .utilityWindow
    minSize = NSSize(width: 180, height: 300)
    maxSize = NSSize(width: 400, height: CGFloat.infinity)
  }

  // Don't become key window (keeps focus on Ghostty)
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  func showPanel() {
    orderFront(nil)
  }

  func hidePanel() {
    orderOut(nil)
  }
}
