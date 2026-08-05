import Foundation
import Testing
@testable import TmuxVTab

@MainActor
struct AgentStateStoreTests {
  @Test func preservesQuestionAcrossApprovalAndCompletion() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let stateURL = directory.appendingPathComponent("state.json")
    let store = AgentStateStore(persistenceURL: stateURL)

    store.apply(event(.userPrompt, prompt: "What is broken?"))
    store.apply(event(.approvalRequired, detail: "Run integration tests"))

    var runtime = try #require(store.runtime(for: "%1"))
    #expect(runtime.phase == .waitingForApproval)
    #expect(runtime.question == "What is broken?")
    #expect(runtime.approval == "Run integration tests")
    #expect(runtime.needsAttention)

    store.apply(event(.completed, response: "The socket path was stale."))
    runtime = try #require(store.runtime(for: "%1"))
    #expect(runtime.phase == .complete)
    #expect(runtime.question == "What is broken?")
    #expect(runtime.response == "The socket path was stale.")
    #expect(runtime.approval == nil)

    let stateAttributes = try FileManager.default.attributesOfItem(atPath: stateURL.path)
    let statePermissions = stateAttributes[.posixPermissions] as? NSNumber
    #expect(statePermissions?.intValue == 0o600)
    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    let directoryPermissions = directoryAttributes[.posixPermissions] as? NSNumber
    #expect(directoryPermissions?.intValue == 0o700)

    let reloaded = AgentStateStore(persistenceURL: stateURL)
    let persisted = try #require(reloaded.runtime(for: "%1"))
    #expect(persisted.source == runtime.source)
    #expect(persisted.phase == runtime.phase)
    #expect(persisted.sessionID == runtime.sessionID)
    #expect(persisted.question == runtime.question)
    #expect(persisted.response == runtime.response)
    #expect(abs(persisted.updatedAt.timeIntervalSince(runtime.updatedAt)) < 0.001)
  }

  @Test func sessionEndOnlyClearsMatchingSession() {
    let store = AgentStateStore(persistenceURL: nil)
    store.apply(event(.userPrompt, sessionID: "current", prompt: "Keep me"))
    store.apply(event(.sessionEnded, sessionID: "old"))
    #expect(store.runtime(for: "%1") != nil)

    store.apply(event(.sessionEnded, sessionID: "current"))
    #expect(store.runtime(for: "%1") == nil)
  }

  private func event(
    _ kind: AgentEventKind,
    sessionID: String = "session",
    prompt: String? = nil,
    response: String? = nil,
    detail: String? = nil
  ) -> AgentEvent {
    AgentEvent(
      source: .codex,
      kind: kind,
      sessionID: sessionID,
      paneID: "%1",
      prompt: prompt,
      response: response,
      detail: detail
    )
  }
}
