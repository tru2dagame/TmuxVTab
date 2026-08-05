import Foundation
import Testing
@testable import TmuxVTab

struct HookStatusCommandTests {
  @Test func reportExplainsManualUpdates() {
    let report = HookStatusCommand.report([
      .init(source: .claude, state: .installed(version: "0.2.0", enabled: true)),
      .init(source: .codex, state: .installed(version: HookVersion.current, enabled: true)),
    ])

    #expect(report.contains("Claude Code: 0.2.0 (update required)"))
    #expect(report.contains("claude plugin update tmuxvtab@tru2dagame"))
    #expect(!report.contains("codex plugin marketplace upgrade"))
  }

  @Test func localCodexMarketplaceDoesNotSuggestGitUpgrade() {
    let report = HookStatusCommand.report([
      .init(
        source: .codex,
        state: .installed(version: "0.2.0", enabled: true),
        marketplace: .local(path: "/path/to/tmuxvtab")
      ),
    ])

    #expect(report.contains("Update local Codex marketplace: /path/to/tmuxvtab"))
    #expect(report.contains("codex plugin add tmuxvtab@tru2dagame --json"))
    #expect(!report.contains("codex plugin marketplace upgrade"))
  }

  @Test func commandInspectionDoesNotInheritTerminalInput() throws {
    let output = try #require(HookStatusCommand.run(
      URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", "if read ignored; then exit 9; fi; printf done"],
      timeout: 1
    ))

    #expect(String(decoding: output, as: UTF8.self) == "done")
  }

  @Test func commandInspectionTimesOut() {
    let startedAt = Date()
    let output = HookStatusCommand.run(
      URL(fileURLWithPath: "/bin/sleep"),
      arguments: ["2"],
      timeout: 0.05
    )

    #expect(output == nil)
    #expect(Date().timeIntervalSince(startedAt) < 1)
  }
}
