import Foundation
import Testing
@testable import TmuxVTab

struct AgentIPCTests {
  @Test func sendsEventOverPrivateUnixSocket() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let socketPath = directory.appendingPathComponent("agent.sock").path

    let received = ReceivedEvent()
    let server = AgentEventServer(socketPath: socketPath) { event in
      received.set(event)
    }
    try server.start()
    defer { server.stop() }

    let event = AgentEvent(
      source: .claude,
      kind: .userPrompt,
      sessionID: "session",
      paneID: "%4",
      prompt: "Synthetic prompt"
    )
    #expect(AgentIPC.send(event, socketPath: socketPath))

    let deadline = ContinuousClock.now + .seconds(2)
    while received.value == nil, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(received.value == event)

    let attributes = try FileManager.default.attributesOfItem(atPath: socketPath)
    let permissions = attributes[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o600)
  }

  @Test func refusesToReplaceAnActiveSocket() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let socketPath = directory.appendingPathComponent("agent.sock").path
    let first = AgentEventServer(socketPath: socketPath) { _ in }
    let second = AgentEventServer(socketPath: socketPath) { _ in }
    try first.start()
    defer {
      second.stop()
      first.stop()
    }

    var refused = false
    do {
      try second.start()
    } catch AgentIPCError.socketAlreadyActive {
      refused = true
    }
    #expect(refused)
  }
}

private final class ReceivedEvent: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: AgentEvent?

  var value: AgentEvent? {
    lock.withLock { stored }
  }

  func set(_ event: AgentEvent) {
    lock.withLock { stored = event }
  }
}
