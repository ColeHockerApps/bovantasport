//
//  Components.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

// MARK: - Team Badge

public struct TeamBadgeView: View {
    @EnvironmentObject private var theme: AppTheme

    public struct Config: Equatable {
        public var title: String
        public var color: Color
        public var icon: Image
        public var textColor: Color
        public var subtitle: String?

        public init(title: String,
                    color: Color,
                    icon: Image,
                    textColor: Color,
                    subtitle: String? = nil) {
            self.title = title
            self.color = color
            self.icon = icon
            self.textColor = textColor
            self.subtitle = subtitle
        }
    }

    public let config: Config
    public var compact: Bool = false

    public init(config: Config, compact: Bool = false) {
        self.config = config
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(ColorSwatches.ringGradient(config.color))
                    .frame(width: compact ? 32 : 40, height: compact ? 32 : 40)
                config.icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 14 : 18, height: compact ? 14 : 18)
                    .foregroundStyle(config.textColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(config.title)
                    .font(.system(size: compact ? 14 : 16, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.palette.textPrimary)
                    .lineLimit(1)
                if let subtitle = config.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(theme.palette.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(config.title)")
    }
}

// MARK: - Color Picker Row (team palette)

public struct ColorPickerRow: View {
    @EnvironmentObject private var theme: AppTheme
    public let colors: [Color]
    @Binding public var selectedIndex: Int
    public var columns: Int = 10
    public var circleSize: CGFloat = 26

    /// Designated initializer (exposes colors explicitly).
    public init(colors: [Color],
                selectedIndex: Binding<Int>,
                columns: Int = 10,
                circleSize: CGFloat = 26) {
        self.colors = colors
        self._selectedIndex = selectedIndex
        self.columns = columns
        self.circleSize = circleSize
    }

    /// Convenience initializer (uses internal team swatches without leaking them in the public API).
    public init(selectedIndex: Binding<Int>,
                columns: Int = 10,
                circleSize: CGFloat = 26) {
        self.colors = ColorSwatches.teamSwatches
        self._selectedIndex = selectedIndex
        self.columns = columns
        self.circleSize = circleSize
    }

    public var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(circleSize + 6), spacing: 10), count: max(1, columns)), spacing: 10) {
            ForEach(colors.indices, id: \.self) { idx in
                let c = colors[idx]
                Button {
                    selectedIndex = idx
                } label: {
                    Circle()
                        .fill(c)
                        .overlay(
                            Circle().strokeBorder(.white.opacity(idx == selectedIndex ? 1.0 : 0.0), lineWidth: 2)
                        )
                        .frame(width: circleSize, height: circleSize)
                        .shadow(radius: 1, y: 1)
                        .accessibilityLabel("Color \(idx + 1)")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Icon Picker Grid (team badges)

public struct IconPickerGrid: View {
    @EnvironmentObject private var theme: AppTheme
    @Binding public var selectedName: String
    public var columns: Int = 8

    /// Pulls items from IconLibrary internally so we don't expose its item type in the public API.
    public init(selectedName: Binding<String>, columns: Int = 8) {
        self._selectedName = selectedName
        self.columns = columns
    }

    public var body: some View {
        let items = IconLibrary.teamBadgePickerItems() // must provide `name` and `icon`
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: max(2, columns)), spacing: 10) {
            ForEach(items, id: \.name) { item in
                let isSelected = item.name == selectedName
                Button {
                    selectedName = item.name
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? theme.accent.opacity(0.22) : theme.palette.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.white.opacity(isSelected ? 0.45 : 0.08), lineWidth: isSelected ? 1.2 : 1)
                            )
                            .frame(height: 44)
                        item.icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(isSelected ? theme.accent : theme.palette.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.name)
            }
        }
    }
}

// MARK: - Score Stepper

public struct ScoreStepper: View {
    @EnvironmentObject private var theme: AppTheme
    @EnvironmentObject private var haptics: HapticsManager

    @Binding public var value: Int
    public var step: Int = 1
    public var allowNegative: Bool = false
    public var accent: Color = .accentColor
    public var onChange: ((Int) -> Void)? = nil

    public init(value: Binding<Int>, step: Int = 1, allowNegative: Bool = false, accent: Color = .accentColor, onChange: ((Int) -> Void)? = nil) {
        self._value = value
        self.step = step
        self.allowNegative = allowNegative
        self.accent = accent
        self.onChange = onChange
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button {
                let newVal = value - step
                guard allowNegative || newVal >= 0 else { haptics.rigid(); return }
                value = newVal
                onChange?(value)
                haptics.rigid()
            } label: {
                Label("-\(step)", systemImage: "minus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.bordered)
            .tint(theme.palette.secondary)

            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .frame(minWidth: 50)
                .padding(.vertical, 6)
                .background(theme.palette.surface.cornerRadius(10))
                .foregroundColor(theme.palette.textPrimary)

            Button {
                value += step
                onChange?(value)
                step >= 2 ? haptics.heavy() : haptics.light()
            } label: {
                Label("+\(step)", systemImage: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score stepper")
        .accessibilityValue("\(value)")
    }
}

// MARK: - Timer Chip

public struct TimerChip: View {
    @EnvironmentObject private var theme: AppTheme
    public var title: String
    public var seconds: Int
    public var accent: Color
    public var leadingIcon: String? = "timer"

    public init(title: String, seconds: Int, accent: Color, leadingIcon: String? = "timer") {
        self.title = title
        self.seconds = seconds
        self.accent = accent
        self.leadingIcon = leadingIcon
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let leadingIcon = leadingIcon {
                Image(systemName: leadingIcon).imageScale(.medium)
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer(minLength: 6)
            Text(timeString)
                .monospacedDigit()
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ColorSwatches.softVerticalGradient(accent))
        .foregroundColor(ColorSwatches.bestTextColor(on: accent))
        .cornerRadius(12)
        .shadow(color: ColorSwatches.shadow(for: accent), radius: 6, x: 0, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(timeString)")
    }

    private var timeString: String {
        let mm = max(0, seconds) / 60
        let ss = max(0, seconds) % 60
        return String(format: "%02d:%02d", mm, ss)
    }
}

// MARK: - Stat Card

public struct StatCard: View {
    @EnvironmentObject private var theme: AppTheme
    public var title: String
    public var value: String
    public var subtitle: String
    public var accent: Color

    public init(title: String, value: String, subtitle: String, accent: Color) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.accent = accent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(theme.palette.textSecondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(theme.palette.textPrimary)
            Text(subtitle)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(theme.palette.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorSwatches.softVerticalGradient(accent))
        .foregroundColor(ColorSwatches.bestTextColor(on: accent))
        .cornerRadius(12)
        .shadow(color: ColorSwatches.shadow(for: accent), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Empty State

public struct EmptyStateView: View {
    @EnvironmentObject private var theme: AppTheme
    public var title: String
    public var subtitle: String
    public var systemIcon: String

    public init(title: String, subtitle: String, icon: String) {
        self.title = title
        self.subtitle = subtitle
        self.systemIcon = icon
    }

    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemIcon)
                .imageScale(.large)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(title)
                .font(theme.typography.titleSmall)
                .foregroundColor(theme.palette.textPrimary)
            Text(subtitle)
                .multilineTextAlignment(.center)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(theme.palette.textSecondary)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(theme.palette.surface.cornerRadius(12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

// MARK: - Convenience initializers for TeamBadgeView

public extension TeamBadgeView.Config {
    init(team: Team) {
        self.init(title: team.name,
                  color: team.color,
                  icon: team.badge,
                  textColor: team.foregroundOnColor,
                  subtitle: team.sport.label)
    }
}

// MARK: - Previews (optional)

#if DEBUG
struct Components_Previews: PreviewProvider {
    static var previews: some View {
        let theme = AppTheme()
        let team = Team(name: "Tigers", sport: .basketball, colorIndex: 3, badgeName: "sf:shield.fill", players: [])
        VStack(spacing: 16) {
            TeamBadgeView(config: .init(team: team))
                .environmentObject(theme)

            ColorPickerRow(selectedIndex: Binding.constant(3))
                .environmentObject(theme)

            IconPickerGrid(selectedName: Binding.constant("sf:shield.fill"))
                .environmentObject(theme)

            ScoreStepper(value: Binding.constant(7), step: 1, allowNegative: false, accent: .orange)
                .environmentObject(theme)
               // .environmentObject(HapticsManager(isEnabled: true))

            TimerChip(title: "Period 1/4", seconds: 8*60 + 12, accent: .orange)
                .environmentObject(theme)

            StatCard(title: "Matches", value: "42", subtitle: "total", accent: .purple)
                .environmentObject(theme)

            EmptyStateView(title: "No data", subtitle: "Start a match to see stats here.", icon: "sportscourt.fill")
                .environmentObject(theme)
        }
        .padding()
        .background(theme.background)
        .environmentObject(theme)
        .preferredColorScheme(.dark)
    }
}
#endif
