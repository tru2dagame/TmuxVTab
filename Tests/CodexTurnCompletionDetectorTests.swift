import Foundation
import Testing
@testable import TmuxVTab

struct CodexTurnCompletionDetectorTests {
  @Test func matchesOnlyTheRequestedCompletedTurn() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: url) }

    let contents = """
      {"timestamp":"2026-08-07T10:00:00.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"old-turn"}}
      {"timestamp":"2026-08-07T10:01:00.000Z","type":"event_msg","payload":{"type":"token_count","turn_id":"current-turn"}}
      {"timestamp":"2026-08-07T10:02:00.123Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"current-turn"}}
      """
    try Data(contents.utf8).write(to: url)

    #expect(CodexTurnCompletionDetector.completion(
      in: url.path,
      turnID: "missing-turn"
    ) == nil)

    let completion = try #require(CodexTurnCompletionDetector.completion(
      in: url.path,
      turnID: "current-turn"
    ))
    #expect(abs(completion.timeIntervalSince1970 - 1_786_096_920.123) < 0.001)
  }
}
