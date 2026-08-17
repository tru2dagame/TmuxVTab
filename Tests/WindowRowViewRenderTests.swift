import AppKit
import SwiftUI
import Testing
@testable import TmuxVTab

@MainActor
struct WindowRowViewRenderTests {
  @Test func rendersQuestionApprovalAndCompletionStates() throws {
    let question = "Why is Codex only showing that it is running?"

    let approvalImage = try render(runtime: AgentRuntime(
      source: .codex,
      phase: .waitingForApproval,
      hookVersion: HookVersion.current,
      permissionMode: "default",
      sessionID: "synthetic",
      question: question,
      approval: "Run the integration test suite",
      needsAttention: true
    ))
    #expect(approvalImage.count > 1_000)

    let completionImage = try render(runtime: AgentRuntime(
      source: .claude,
      phase: .complete,
      hookVersion: "0.2.0",
      permissionMode: "plan",
      sessionID: "synthetic",
      question: question,
      response: "The structured hook preview is now available.",
      needsAttention: true
    ))
    #expect(completionImage.count > 1_000)
    #expect(completionImage != approvalImage)
  }

  private func render(runtime: AgentRuntime) throws -> Data {
    let window = TmuxWindow(
      sessionName: "work",
      windowIndex: 1,
      windowName: "tmuxvtab",
      isActive: true,
      currentCommand: runtime.source.rawValue,
      panePid: 42,
      paneId: "%1",
      detectedAgent: runtime.detectedAgent,
      agentRuntime: runtime
    )
    let content = WindowRowView(window: window, onSelect: {})
      .frame(width: 240)
      .padding(8)
      .background(Color(nsColor: .windowBackgroundColor))

    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    return try #require(bitmap.representation(using: .png, properties: [:]))
  }
}
