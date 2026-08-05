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
}
