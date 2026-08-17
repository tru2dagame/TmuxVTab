import Testing
@testable import TmuxVTab

@MainActor
struct TmuxServicePaneTests {
  @Test func groupsAllPanesAndKeepsTheActivePaneAsTheInitialSelection() throws {
    let output = """
      1\twork\t1\t0\t0\tcodex\t101\t%agent
      1\twork\t1\t0\t1\tzsh\t102\t%shell
      2\tlogs\t0\t1\t1\ttail\t103\t%logs
      """

    let windows = TmuxService.parseWindows(output, sessionName: "main")
    #expect(windows.count == 2)

    let work = try #require(windows.first)
    #expect(work.windowIndex == 1)
    #expect(work.panes.count == 2)
    #expect(work.paneId == "%shell")
    #expect(work.currentCommand == "zsh")

    let logs = try #require(windows.last)
    #expect(logs.windowIndex == 2)
    #expect(logs.hasBell)
  }
}
