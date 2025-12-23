//
//  Color+Theme.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

extension Color {
    static let theme = ThemeColors()
}

struct ThemeColors {
    
    // MARK: - Chat Interface
    let chatBackground = Color(.systemGroupedBackground)
    let messageBackground = Color(.secondarySystemFill)
    let userMessageBackground = Color(.tertiarySystemFill)
    let messageBubbleUser = Color(.tertiarySystemFill)
    let messageBubbleAI = Color.clear
    
    // MARK: - Input Interface
    let inputBackground = Color(.systemGray6)
    let inputFieldBackground = Color(.systemGray5)
    let sendButtonEnabled = Color.blue
    let sendButtonDisabled = Color(.systemGray4)
    
    // MARK: - Navigation & UI
    let primaryAccent = Color.blue
    let secondaryAccent = Color(.systemBlue)
    let surfaceBackground = Color(.systemBackground)
    let groupedBackground = Color(.systemGroupedBackground)
    
    // MARK: - Semantic Colors
    let success = Color.green
    let error = Color.red
    let warning = Color.orange
    let info = Color.blue
    
    // MARK: - Text Colors
    let primaryText = Color(.label)
    let secondaryText = Color(.secondaryLabel)
    let tertiaryText = Color(.tertiaryLabel)
    let quaternaryText = Color(.quaternaryLabel)
    
    // MARK: - Status Colors
    let connected = Color.green
    let disconnected = Color.red
    let loading = Color.orange
    
    // MARK: - System Integration
    let separator = Color(.separator)
    let opaqueSeparator = Color(.opaqueSeparator)
    let link = Color(.link)
    let placeholderText = Color(.placeholderText)
    
    // MARK: - Material Backgrounds (Note: These are ShapeStyle, not Color)
    // Materials should be used directly as .regularMaterial, .thickMaterial, etc.
    // in background modifiers, not as Color instances
    
    // MARK: - Fill Colors
    let systemFill = Color(.systemFill)
    let secondarySystemFill = Color(.secondarySystemFill)
    let tertiarySystemFill = Color(.tertiarySystemFill)
    let quaternarySystemFill = Color(.quaternarySystemFill)
    
    // MARK: - Grouped Fill Colors
    let systemGroupedBackground = Color(.systemGroupedBackground)
    let secondarySystemGroupedBackground = Color(.secondarySystemGroupedBackground)
    let tertiarySystemGroupedBackground = Color(.tertiarySystemGroupedBackground)
    
    // MARK: - Home Screen Gradient
    let gradientStart = Color(red: 0.0, green: 0.48, blue: 1.0) // #007AFF Blue
    let gradientEnd = Color(red: 0.345, green: 0.337, blue: 0.839) // #5856D6 Purple
    let gradientDark = Color(red: 0.05, green: 0.05, blue: 0.08) // Near black
    
    /// Home screen gradient background
    var homeGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: gradientStart.opacity(0.6), location: 0.0),
                .init(color: gradientEnd.opacity(0.4), location: 0.3),
                .init(color: gradientDark, location: 0.7)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Sheet background - uses system color for Light/Dark mode adaptation
    let sheetBackground = Color(.systemGroupedBackground)
}

// MARK: - Convenience Extensions
extension Color {
    
    /// Returns a color that adapts automatically to light/dark mode
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(.init { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
    
    /// Returns a semi-transparent version of the color for overlays
    func overlay(opacity: Double = 0.1) -> Color {
        self.opacity(opacity)
    }
    
    /// Returns a gradient version of the color
    var gradient: LinearGradient {
        LinearGradient(
            colors: [self, self.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Theme Provider
@Observable
class ThemeProvider {
    var currentTheme: ColorScheme? = nil
    
    func setTheme(_ scheme: ColorScheme?) {
        currentTheme = scheme
    }
}

// MARK: - Gradient Background Modifier
struct HomeGradientBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.theme.homeGradient)
            .background(Color.black) // Fallback
    }
}

extension View {
    func homeGradientBackground() -> some View {
        modifier(HomeGradientBackground())
    }
}