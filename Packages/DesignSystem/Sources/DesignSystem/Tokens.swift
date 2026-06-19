import SwiftUI

/// Color tokens for Notova. Centralizing here keeps feature views theme-agnostic.
public enum NotovaColor {
    public static let accent = Color(red: 0.36, green: 0.30, blue: 0.92)
    public static let recording = Color(red: 0.92, green: 0.25, blue: 0.30)
    #if canImport(UIKit)
    public static let surface = Color(.secondarySystemBackground)
    #else
    public static let surface = Color.gray.opacity(0.15)
    #endif
    public static let textPrimary = Color.primary
    public static let textSecondary = Color.secondary
}

/// Typography tokens.
public enum NotovaFont {
    public static let title = Font.system(.largeTitle, design: .rounded).weight(.bold)
    public static let heading = Font.system(.headline, design: .rounded)
    public static let body = Font.system(.body)
    public static let caption = Font.system(.caption)
}

/// Spacing tokens (points).
public enum NotovaSpacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
}
