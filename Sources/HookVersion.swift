import Foundation

enum HookCompatibility: String, Codable, Hashable, Sendable {
  case current
  case hookUpdateRequired
  case appUpdateRequired
  case unknown
}

enum HookVersion {
  static let current = "0.3.0"

  static func compatibility(with installedVersion: String?) -> HookCompatibility {
    guard let installedVersion,
          let installed = components(installedVersion),
          let expected = components(current)
    else { return .unknown }
    if installedVersion == current { return .current }

    if installed.lexicographicallyPrecedes(expected) { return .hookUpdateRequired }
    if expected.lexicographicallyPrecedes(installed) { return .appUpdateRequired }
    return .current
  }

  private static func components(_ version: String) -> [Int]? {
    let core = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
    let components = core.split(separator: ".").compactMap { Int($0) }
    guard components.count == 3 else { return nil }
    return components
  }
}
