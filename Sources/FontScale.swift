import SwiftUI

// MARK: - Environment Key

private struct SidebarFontScaleKey: EnvironmentKey {
  static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
  var sidebarFontScale: Double {
    get { self[SidebarFontScaleKey.self] }
    set { self[SidebarFontScaleKey.self] = newValue }
  }
}

// MARK: - Scaled Font Helper

extension View {
  /// Applies a scaled system font based on the sidebar font scale environment value.
  func scaledFont(size baseSize: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
    modifier(ScaledFontModifier(baseSize: baseSize, weight: weight, design: design))
  }
}

private struct ScaledFontModifier: ViewModifier {
  @Environment(\.sidebarFontScale) private var scale
  let baseSize: CGFloat
  let weight: Font.Weight
  let design: Font.Design

  func body(content: Content) -> some View {
    content.font(.system(size: baseSize * scale, weight: weight, design: design))
  }
}
