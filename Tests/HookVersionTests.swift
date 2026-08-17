import Foundation
import Testing
@testable import TmuxVTab

struct HookVersionTests {
  @Test func comparesHookAndAppVersions() {
    #expect(HookVersion.compatibility(with: HookVersion.current) == .current)
    #expect(HookVersion.compatibility(with: "0.2.0") == .hookUpdateRequired)
    #expect(HookVersion.compatibility(with: "0.4.0") == .appUpdateRequired)
    #expect(HookVersion.compatibility(with: nil) == .unknown)
    #expect(HookVersion.compatibility(with: "unknown") == .unknown)
  }

  @Test func packagedVersionsStayInSync() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let hookVersion = try String(
      contentsOf: root.appendingPathComponent("hooks/VERSION"),
      encoding: .utf8
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(hookVersion == HookVersion.current)

    for manifest in [".claude-plugin/plugin.json", ".codex-plugin/plugin.json"] {
      let data = try Data(contentsOf: root.appendingPathComponent(manifest))
      let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
      #expect(object["version"] as? String == HookVersion.current)
    }
  }

  @Test func hookVersionDoesNotDependOnPathLookup() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [root.appendingPathComponent("hook.sh").path, "--version"]
    process.environment = ["HOME": NSHomeDirectory(), "PATH": ""]
    process.standardOutput = standardOutput
    process.standardError = standardError

    try process.run()
    let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
    let error = standardError.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
    #expect(String(decoding: output, as: UTF8.self) == "\(HookVersion.current)\n")
    #expect(error.isEmpty)
  }
}
