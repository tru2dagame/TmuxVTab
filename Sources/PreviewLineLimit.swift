import SwiftUI

enum PreviewLineLimit {
  static let defaultValue = 3
  static let allowedRange = 1...8

  static func parse(_ rawValue: String?) -> Int {
    guard
      let rawValue,
      let value = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      return defaultValue
    }

    return min(max(value, allowedRange.lowerBound), allowedRange.upperBound)
  }
}

private struct AgentPreviewLineLimitKey: EnvironmentKey {
  static let defaultValue = PreviewLineLimit.defaultValue
}

extension EnvironmentValues {
  var agentPreviewLineLimit: Int {
    get { self[AgentPreviewLineLimitKey.self] }
    set { self[AgentPreviewLineLimitKey.self] = newValue }
  }
}
