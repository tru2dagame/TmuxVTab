import Testing
@testable import TmuxVTab

struct PreviewLineLimitTests {
  @Test func defaultsWhenTheOptionIsMissingOrInvalid() {
    #expect(PreviewLineLimit.parse(nil) == 3)
    #expect(PreviewLineLimit.parse("") == 3)
    #expect(PreviewLineLimit.parse("many") == 3)
  }

  @Test func parsesAndClampsConfiguredValues() {
    #expect(PreviewLineLimit.parse(" 5\n") == 5)
    #expect(PreviewLineLimit.parse("0") == 1)
    #expect(PreviewLineLimit.parse("99") == 8)
  }
}
