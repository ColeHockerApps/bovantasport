//
//  AppTheme.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

final class AppTheme: ObservableObject {
    // MARK: - Nested Types

    struct Palette {
        let background: Color
        let surface: Color
        let secondary: Color
        let accent: Color
        let textPrimary: Color
        let textSecondary: Color
        let success: Color
        let warning: Color
        let danger: Color
        let teamColors: [Color]
    }

    struct Typography {
        let titleLarge: Font
        let titleMedium: Font
        let titleSmall: Font
        let body: Font
        let label: Font
        let caption: Font
    }

    // MARK: - Published Properties

    @Published var isDarkMode: Bool = true
    @Published var palette: Palette
    @Published var typography: Typography

    // MARK: - Init

    init(darkMode: Bool = true) {
        self.isDarkMode = darkMode
        self.palette = darkMode ? Self.darkPalette : Self.lightPalette
        self.typography = Self.defaultTypography
    }

    // MARK: - Computed

    var background: Color { palette.background }
    var accent: Color { palette.accent }

    // MARK: - Public Methods

    func toggleMode() {
        isDarkMode.toggle()
        palette = isDarkMode ? Self.darkPalette : Self.lightPalette
    }

    // MARK: - Static Presets

    private static let darkPalette = Palette(
        background: Color(red: 10/255, green: 14/255, blue: 20/255),
        surface: Color(red: 18/255, green: 24/255, blue: 32/255),
        secondary: Color(red: 24/255, green: 32/255, blue: 44/255),
        accent: Color(red: 30/255, green: 136/255, blue: 229/255), // #1E88E5
        textPrimary: .white,
        textSecondary: .white.opacity(0.7),
        success: Color.green.opacity(0.85),
        warning: Color.orange.opacity(0.85),
        danger: Color.red.opacity(0.85),
        teamColors: [
            Color(hue: 0.58, saturation: 0.65, brightness: 0.95), // blue
            Color(hue: 0.02, saturation: 0.70, brightness: 0.95), // red
            Color(hue: 0.11, saturation: 0.75, brightness: 0.95), // yellow
            Color(hue: 0.80, saturation: 0.50, brightness: 0.95), // purple
            Color(hue: 0.38, saturation: 0.65, brightness: 0.95), // green
            Color(hue: 0.92, saturation: 0.55, brightness: 0.95)  // pink
        ]
    )

    private static let lightPalette = Palette(
        background: Color(red: 242/255, green: 245/255, blue: 250/255),
        surface: Color(red: 255/255, green: 255/255, blue: 255/255),
        secondary: Color(red: 230/255, green: 235/255, blue: 240/255),
        accent: Color(red: 25/255, green: 118/255, blue: 210/255), // #1976D2
        textPrimary: Color(red: 33/255, green: 33/255, blue: 33/255),
        textSecondary: Color(red: 100/255, green: 100/255, blue: 100/255),
        success: Color.green.opacity(0.8),
        warning: Color.orange.opacity(0.8),
        danger: Color.red.opacity(0.8),
        teamColors: [
            Color(hue: 0.58, saturation: 0.65, brightness: 0.65),
            Color(hue: 0.02, saturation: 0.70, brightness: 0.70),
            Color(hue: 0.11, saturation: 0.75, brightness: 0.70),
            Color(hue: 0.80, saturation: 0.50, brightness: 0.70),
            Color(hue: 0.38, saturation: 0.65, brightness: 0.70),
            Color(hue: 0.92, saturation: 0.55, brightness: 0.70)
        ]
    )

    private static let defaultTypography = Typography(
        titleLarge: .system(size: 26, weight: .bold, design: .rounded),
        titleMedium: .system(size: 20, weight: .semibold, design: .rounded),
        titleSmall: .system(size: 17, weight: .medium, design: .rounded),
        body: .system(size: 16, weight: .regular, design: .rounded),
        label: .system(size: 14, weight: .semibold, design: .rounded),
        caption: .system(size: 12, weight: .regular, design: .rounded)
    )
}
