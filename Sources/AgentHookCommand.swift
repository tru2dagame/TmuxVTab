import Foundation

enum AgentHookCommand {
  /// Returns nil for the GUI invocation, otherwise the hook process exit code.
  static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
    guard arguments.count >= 2, arguments[1] == "hook" else { return nil }

    let agentHint = arguments.count > 2 ? arguments[2] : "auto"
    let eventHint = arguments.count > 3 ? arguments[3] : ""
    let input = readBoundedInput()

    if let input,
       let event = AgentHookNormalizer.normalize(
         agentHint: agentHint,
         eventHint: eventHint,
         input: input
       ) {
      _ = AgentIPC.send(event)
    }

    // Stop and SubagentStop require JSON output in current Codex releases.
    // An empty object is also a valid no-op response for Claude Code.
    if let kind = AgentHookNormalizer.eventKind(eventHint),
       kind == .completed || kind == .subagentStopped {
      FileHandle.standardOutput.write(Data("{}\n".utf8))
    }
    return 0
  }

  private static func readBoundedInput() -> Data? {
    var result = Data()
    while result.count <= AgentHookNormalizer.maximumInputBytes {
      guard let chunk = try? FileHandle.standardInput.read(upToCount: 64 * 1024),
            !chunk.isEmpty
      else { break }
      result.append(chunk)
    }
    guard !result.isEmpty, result.count <= AgentHookNormalizer.maximumInputBytes else {
      return nil
    }
    return result
  }
}
