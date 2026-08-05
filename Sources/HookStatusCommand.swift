import Foundation
import Darwin

enum HookStatusCommand {
  struct Installation: Sendable {
    enum Marketplace: Sendable {
      case git
      case local(path: String)
    }

    enum State: Sendable {
      case installed(version: String, enabled: Bool)
      case notInstalled
      case cliUnavailable
      case checkFailed
    }

    let source: AgentSource
    let state: State
    let marketplace: Marketplace?

    init(source: AgentSource, state: State, marketplace: Marketplace? = nil) {
      self.source = source
      self.state = state
      self.marketplace = marketplace
    }
  }

  static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
    guard arguments.count >= 2, arguments[1] == "hooks" else { return nil }

    let command = arguments.count > 2 ? arguments[2] : "check"
    guard command == "version" || command == "check" else {
      write("Usage: TmuxVTab hooks <version|check>\n", to: .standardError)
      return 2
    }

    let installations = inspectInstallations()
    write(report(installations))

    guard command == "check" else { return 0 }
    return installations.contains(where: needsAction) ? 1 : 0
  }

  static func report(_ installations: [Installation]) -> String {
    var lines = [
      "TmuxVTab hook bundle: \(HookVersion.current)",
      "Event protocol: \(AgentEvent.protocolVersion)",
    ]

    for installation in installations {
      let label = installation.source == .claude ? "Claude Code" : "Codex"
      switch installation.state {
      case .installed(let version, let enabled):
        let compatibility = HookVersion.compatibility(with: version)
        let suffix: String
        switch compatibility {
        case .current: suffix = enabled ? "current" : "disabled"
        case .hookUpdateRequired: suffix = "update required"
        case .appUpdateRequired: suffix = "newer than this VTab"
        case .unknown: suffix = "version unknown"
        }
        lines.append("\(label): \(version) (\(suffix))")
      case .notInstalled:
        lines.append("\(label): not installed")
      case .cliUnavailable:
        lines.append("\(label): CLI not found (skipped)")
      case .checkFailed:
        lines.append("\(label): unable to inspect")
      }
    }

    if installations.contains(where: needsHookUpdate) {
      lines.append("")
      lines.append("Install or update hooks manually:")
      if installations.contains(where: { $0.source == .claude && needsHookUpdate($0) }) {
        if installations.contains(where: { $0.source == .claude && $0.state.isNotInstalled }) {
          lines.append("  claude plugin install tmuxvtab@tru2dagame")
        } else {
          lines.append("  claude plugin marketplace update tru2dagame")
          lines.append("  claude plugin update tmuxvtab@tru2dagame")
        }
      }
      if installations.contains(where: { $0.source == .codex && needsHookUpdate($0) }) {
        let codex = installations.first(where: { $0.source == .codex })
        switch codex?.marketplace {
        case .git:
          lines.append("  codex plugin marketplace upgrade tru2dagame")
        case .local(let path):
          lines.append("  Update local Codex marketplace: \(path)")
        case nil:
          break
        }
        lines.append("  codex plugin add tmuxvtab@tru2dagame --json")
      }
      lines.append("Then start a new agent session; review changed hooks when prompted.")
    }

    return lines.joined(separator: "\n") + "\n"
  }

  private static func inspectInstallations() -> [Installation] {
    [inspectClaude(), inspectCodex()]
  }

  private static func inspectClaude() -> Installation {
    guard let executable = findExecutable("claude") else {
      return Installation(source: .claude, state: .cliUnavailable)
    }
    guard let data = run(executable, arguments: ["plugin", "list", "--json"]),
          let plugins = try? JSONDecoder().decode([ClaudePlugin].self, from: data)
    else { return Installation(source: .claude, state: .checkFailed) }

    guard let plugin = plugins.first(where: { $0.id == "tmuxvtab@tru2dagame" }) else {
      return Installation(source: .claude, state: .notInstalled)
    }
    return Installation(
      source: .claude,
      state: .installed(version: plugin.version, enabled: plugin.enabled)
    )
  }

  private static func inspectCodex() -> Installation {
    guard let executable = findExecutable("codex") else {
      return Installation(source: .codex, state: .cliUnavailable)
    }
    guard let data = run(executable, arguments: ["plugin", "list", "--json"]),
          let list = try? JSONDecoder().decode(CodexPluginList.self, from: data)
    else { return Installation(source: .codex, state: .checkFailed) }

    guard let plugin = list.installed.first(where: { $0.pluginID == "tmuxvtab@tru2dagame" }) else {
      return Installation(source: .codex, state: .notInstalled)
    }
    return Installation(
      source: .codex,
      state: .installed(version: plugin.version, enabled: plugin.enabled),
      marketplace: plugin.marketplaceSource?.installationKind
    )
  }

  private static func needsAction(_ installation: Installation) -> Bool {
    switch installation.state {
    case .installed(let version, let enabled):
      !enabled || HookVersion.compatibility(with: version) != .current
    case .notInstalled, .checkFailed:
      true
    case .cliUnavailable:
      false
    }
  }

  private static func needsHookUpdate(_ installation: Installation) -> Bool {
    guard case .installed(let version, _) = installation.state else {
      return installation.state.isNotInstalled
    }
    return HookVersion.compatibility(with: version) == .hookUpdateRequired
  }

  private static func findExecutable(_ name: String) -> URL? {
    let environment = ProcessInfo.processInfo.environment
    let pathEntries = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
    let fixedEntries = [
      "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
    ]
    return (pathEntries + fixedEntries).lazy
      .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  static func run(
    _ executable: URL,
    arguments: [String],
    timeout: TimeInterval = 10
  ) -> Data? {
    let process = Process()
    let output = Pipe()
    let completion = DispatchSemaphore(value: 0)
    process.executableURL = executable
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.terminationHandler = { _ in completion.signal() }
    do {
      try process.run()
      let deadline = DispatchTime.now() + .milliseconds(max(1, Int(timeout * 1_000)))
      guard completion.wait(timeout: deadline) == .success else {
        let processID = process.processIdentifier
        process.terminate()
        if completion.wait(timeout: .now() + .milliseconds(250)) == .timedOut {
          Darwin.kill(processID, SIGKILL)
          _ = completion.wait(timeout: .now() + .seconds(1))
        }
        return nil
      }

      let data = output.fileHandleForReading.readDataToEndOfFile()
      return process.terminationStatus == 0 ? data : nil
    } catch {
      return nil
    }
  }

  private static func write(_ string: String, to handle: FileHandle = .standardOutput) {
    handle.write(Data(string.utf8))
  }
}

private struct ClaudePlugin: Decodable {
  let id: String
  let version: String
  let enabled: Bool
}

private struct CodexPluginList: Decodable {
  let installed: [CodexPlugin]
}

private struct CodexPlugin: Decodable {
  let pluginID: String
  let version: String
  let enabled: Bool
  let marketplaceSource: CodexMarketplaceSource?

  enum CodingKeys: String, CodingKey {
    case pluginID = "pluginId"
    case version
    case enabled
    case marketplaceSource
  }
}

private struct CodexMarketplaceSource: Decodable {
  let sourceType: String
  let source: String

  var installationKind: HookStatusCommand.Installation.Marketplace? {
    switch sourceType {
    case "git": .git
    case "local": .local(path: source)
    default: nil
    }
  }
}

private extension HookStatusCommand.Installation.State {
  var isNotInstalled: Bool {
    if case .notInstalled = self { return true }
    return false
  }
}
