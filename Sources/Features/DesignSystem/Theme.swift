//  Created by Mingchen Liang on 2026/10/22.

import SwiftUI
import UIKit

/// Sage and cream palette. Every color adapts to dark mode and keeps text at 4.5:1 or better.
enum Palette {
    static let sage = dynamic(light: 0x4F7360, dark: 0x9CC3A6)
    static let sageDeep = dynamic(light: 0x3B5C4A, dark: 0x7FAE8D)
    static let onSage = dynamic(light: 0xFFFFFF, dark: 0x0F2318)
    static let sageSoft = dynamic(light: 0xE3ECE5, dark: 0x22322A)
    static let canvas = dynamic(light: 0xF5F3ED, dark: 0x0E1210)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1A1F1C)
    static let shell = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.035, darkAlpha: 0.05)
    static let hairline = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.09)
    static let amber = dynamic(light: 0x9A5A12, dark: 0xF2B266)
    static let amberSoft = dynamic(light: 0xF6E8D6, dark: 0x3A2B17)
    /// Neon orange accent for live and "now" details. Use `emberText` when it carries text.
    static let ember = dynamic(light: 0xF26B1D, dark: 0xFF8A3D)
    static let emberText = dynamic(light: 0xB4470A, dark: 0xFF9A55)
    static let shadow = dynamic(light: 0x2A3A30, dark: 0x000000, lightAlpha: 0.08, darkAlpha: 0.35)

    private static func dynamic(
        light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1
    ) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Font {
    /// SF Rounded at a Dynamic Type text style, so sizes still follow the user's text size setting.
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

enum Theme {
    static let outerRadius: CGFloat = 28
    static let bezel: CGFloat = 5
    static let innerRadius: CGFloat = outerRadius - bezel
    static let spring = Animation.spring(response: 0.5, dampingFraction: 0.82)
}

// MARK: - Surfaces

private struct BezelCard<Fill: ShapeStyle>: ViewModifier {
    let fill: Fill
    let padding: CGFloat

    func body(content: Content) -> some View {
        let inner = RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous)
        let outer = RoundedRectangle(cornerRadius: Theme.outerRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: inner)
            .overlay(inner.strokeBorder(Palette.hairline, lineWidth: 0.5))
            .padding(Theme.bezel)
            .background(Palette.shell, in: outer)
            .overlay(outer.strokeBorder(Palette.hairline, lineWidth: 0.5))
            .shadow(color: Palette.shadow, radius: 22, x: 0, y: 10)
    }
}

private struct PlannerCanvas: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                ZStack {
                    Palette.canvas
                    RadialGradient(
                        colors: [Palette.sage.opacity(0.16), .clear],
                        center: .topTrailing, startRadius: 0, endRadius: 460
                    )
                }
                .ignoresSafeArea()
            }
    }
}

private struct RevealOnScroll: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.scrollTransition(.animated(Theme.spring)) { view, phase in
                view
                    .opacity(phase.isIdentity ? 1 : 0.35)
                    .scaleEffect(phase.isIdentity ? 1 : 0.97)
                    .offset(y: phase.value * 14)
            }
        }
    }
}

extension View {
    /// Shows a card on the canvas inside a List: no row background, separator or default insets.
    func canvasRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// A machined, two-layer card: a faint outer tray holding the content plate.
    func bezelCard<Fill: ShapeStyle>(_ fill: Fill, padding: CGFloat = 18) -> some View {
        modifier(BezelCard(fill: fill, padding: padding))
    }

    func bezelCard(padding: CGFloat = 18) -> some View {
        modifier(BezelCard(fill: Palette.surface, padding: padding))
    }

    /// Cream canvas with a soft sage glow; hides the default list and form background.
    func plannerCanvas() -> some View {
        modifier(PlannerCanvas())
    }

    /// Cards ease in as they scroll into view. Skipped when Reduce Motion is on.
    func revealOnScroll() -> some View {
        modifier(RevealOnScroll())
    }
}

// MARK: - Labels

/// A small uppercase tag above a heading.
struct Eyebrow: View {
    let text: String
    var systemImage: String?
    var tint: Color = Palette.sage

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
            Text(text.uppercased())
        }
        .font(.rounded(.caption2, weight: .semibold))
        .tracking(1.3)
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// An eyebrow tag and a heading for a group of cards.
struct SectionHeading: View {
    let eyebrow: String
    let title: String
    var systemImage: String?
    var tint: Color = Palette.sage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: eyebrow, systemImage: systemImage, tint: tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.rounded(.title3, weight: .bold))
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A status shown as icon plus text, so it never relies on color alone.
struct StatusBadge: View {
    let text: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.rounded(.caption, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.13), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// An icon tile for a non-meal row, like a pantry batch.
struct IconTile: View {
    let systemImage: String
    var tint: Color = Palette.sage
    var background: Color = Palette.sageSoft
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// Primary pill. A trailing icon sits in its own circle and nudges up and right when pressed.
struct PillButtonStyle: ButtonStyle {
    var systemImage: String?
    var prominent = true
    var fillsWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration, systemImage: systemImage, prominent: prominent, fillsWidth: fillsWidth)
    }

    private struct PillButton: View {
        let configuration: ButtonStyleConfiguration
        let systemImage: String?
        let prominent: Bool
        let fillsWidth: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let foreground = prominent ? Palette.onSage : Palette.sage
            HStack(spacing: 10) {
                configuration.label
                    .font(.rounded(.body, weight: .semibold))
                    .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: fillsWidth ? .leading : .center)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.footnote.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(foreground.opacity(0.16), in: Circle())
                        .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? -1 : 0)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(foreground)
            .padding(.leading, 20)
            .padding(.trailing, systemImage == nil ? 20 : 7)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .background(prominent ? Palette.sage : Palette.sageSoft, in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Capsule())
        }
    }
}

/// A full card that reports a failure with a retry action.
struct ErrorCard: View {
    let message: String
    var detail: String?
    var retryTitle = "Retry"
    var retryDisabled = false
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.rounded(.subheadline, weight: .semibold))
                .foregroundStyle(Palette.amber)
            if let detail {
                Text(detail)
                    .font(.rounded(.footnote))
                    .foregroundStyle(.secondary)
            }
            Button(retryTitle, action: retry)
                .buttonStyle(PillButtonStyle(systemImage: "arrow.clockwise", prominent: false))
                .disabled(retryDisabled)
        }
        .bezelCard(Palette.amberSoft)
    }
}
