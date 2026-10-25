//
//  AppTheme.swift
//  Resonance
//
//  Resonance design system.
//
//  Color
//    violet      #5B3FD9  brand: buttons, tiles, charts
//    violetDeep  #2C1A86  hero gradient end
//    mint        #1FB38E  "stable" / done
//    amber       #E8962E  "noticeable change" / warnings
//    coral       #E5484D  alert / stop
//    ink         #1B1530  primary text on light
//    canvas      #F5F3FB  app background (light), #0E0A1C (dark)
//    surface     #FFFFFF  cards (light), #1B1630 (dark)
//
//  Type: SF Pro Rounded throughout (friendly, highly legible), large sizes by default.
//  Shape: hero 32 pt, cards 22 pt, controls 16 pt, chips are capsules.
//  Signature: the violet waveform hero on Today and Onboarding. Everything else stays quiet.
//

import SwiftUI
import UIKit

enum AppTheme {
    // MARK: Palette
    /// Slightly lighter in dark mode so violet text stays readable on dark surfaces.
    static let violet = Color(light: 0x5B3FD9, dark: 0x7D66F2)
    static let violetDeep = Color(hex: 0x2C1A86)
    static let violetSoft = Color(light: 0xEEEAFD, dark: 0x2A2150)
    static let mint = Color(hex: 0x1FB38E)
    static let blue = Color(hex: 0x2F80ED)
    static let amber = Color(hex: 0xE8962E)
    static let coral = Color(hex: 0xE5484D)
    static let ink = Color(light: 0x1B1530, dark: 0xF2F0FA)
    static let canvas = Color(light: 0xF5F3FB, dark: 0x0E0A1C)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1B1630)

    // Names used across the app
    static let accent = violet
    static let warning = amber
    static let danger = coral
    static let success = mint
    static let cardBackground = surface
    static let background = canvas

    static let heroGradient = LinearGradient(
        colors: [Color(hex: 0x6A4CF0), Color(hex: 0x5B3FD9), violetDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: Metrics
    static let minTapSize: CGFloat = 60
    static let cornerRadius: CGFloat = 22
    static let controlRadius: CGFloat = 16
    static let heroRadius: CGFloat = 32
    static let padding: CGFloat = 18
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A color that switches between light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

// MARK: - Buttons

/// Filled brand button for the main action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = AppTheme.violet
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
            .padding(.horizontal, 16)
            .background(color.opacity(isEnabled ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            .shadow(color: color.opacity(isEnabled ? 0.28 : 0), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Tinted button for secondary actions (Redo, Back, Check again).
struct SecondaryButtonStyle: ButtonStyle {
    var color: Color = AppTheme.violet

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
            .padding(.horizontal, 16)
            .background(color.opacity(configuration.isPressed ? 0.2 : 0.12),
                        in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
    }
}

/// Plain style with a gentle press-down, for custom card-like buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Surfaces

/// White rounded surface with a soft violet-tinted shadow.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.padding)
        .surfaceStyle()
    }
}

extension View {
    /// Card surface: white (or dark surface), continuous corners, soft shadow.
    func surfaceStyle(radius: CGFloat = AppTheme.cornerRadius) -> some View {
        background(AppTheme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: AppTheme.violetDeep.opacity(0.07), radius: 14, x: 0, y: 6)
    }

    /// The app's background color behind scrolling content.
    func screenBackground() -> some View {
        background(AppTheme.canvas.ignoresSafeArea())
    }
}

/// Rounded-square icon chip used in lists and cards.
struct IconBadge: View {
    let systemImage: String
    var color: Color = AppTheme.violet
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Section title inside a screen.
struct SectionTitle: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The brand's waveform mark, drawn as rounded bars.
struct WaveformMark: View {
    var color: Color = .white
    var heights: [CGFloat] = [0.35, 0.6, 0.95, 0.7, 0.45, 0.8, 1.0, 0.55, 0.3]
    var barWidth: CGFloat = 5
    var spacing: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: spacing) {
                ForEach(heights.indices, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: max(barWidth, geo.size.height * heights[i]))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

/// Simple screen used by features that aren't available.
struct ComingSoonView: View {
    let title: String
    let systemImage: String
    let detail: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                IconBadge(systemImage: systemImage, size: 72)
                Text(detail)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .navigationTitle(title)
        }
    }
}

/// "1 second left" / "5 seconds left".
func secondsLeft(_ remaining: Double) -> String {
    let n = Int(max(0, remaining).rounded(.up))
    return n == 1 ? "1 second left" : "\(n) seconds left"
}
