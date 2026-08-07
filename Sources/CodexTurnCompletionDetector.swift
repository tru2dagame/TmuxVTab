import Foundation

struct CodexTurnCompletionCandidate: Hashable, Sendable {
  let paneID: String
  let turnID: String
  let transcriptPath: String
}

struct CodexTurnCompletion: Hashable, Sendable {
  let paneID: String
  let turnID: String
  let timestamp: Date
}

enum CodexTurnCompletionDetector {
  private static let maximumTailBytes: UInt64 = 256 * 1_024

  static func detect(
    _ candidates: [CodexTurnCompletionCandidate]
  ) async -> [CodexTurnCompletion] {
    await Task.detached {
      candidates.compactMap { candidate in
        completion(in: candidate.transcriptPath, turnID: candidate.turnID).map {
          CodexTurnCompletion(
            paneID: candidate.paneID,
            turnID: candidate.turnID,
            timestamp: $0
          )
        }
      }
    }.value
  }

  static func completion(in transcriptPath: String, turnID: String) -> Date? {
    let url = URL(fileURLWithPath: transcriptPath)
    guard url.pathExtension == "jsonl",
          let handle = try? FileHandle(forReadingFrom: url)
    else { return nil }
    defer { try? handle.close() }

    guard let endOffset = try? handle.seekToEnd() else { return nil }
    let startOffset = endOffset > maximumTailBytes ? endOffset - maximumTailBytes : 0
    do {
      try handle.seek(toOffset: startOffset)
    } catch {
      return nil
    }
    guard var data = try? handle.readToEnd(), !data.isEmpty else { return nil }

    // Starting in the middle of a line is expected for large rollouts.
    if startOffset > 0, let newline = data.firstIndex(of: 0x0A) {
      data.removeSubrange(data.startIndex...newline)
    }

    for line in data.split(separator: 0x0A).reversed() {
      guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
            object["type"] as? String == "event_msg",
            let payload = object["payload"] as? [String: Any],
            payload["type"] as? String == "task_complete",
            payload["turn_id"] as? String == turnID,
            let timestamp = object["timestamp"] as? String
      else { continue }

      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return formatter.date(from: timestamp)
    }
    return nil
  }
}
