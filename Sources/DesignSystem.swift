import AppKit
import SwiftUI

/// Raw palette. Warm "paper" neutrals plus a few small accents.
enum Palette {
    static let sand50: UInt32 = 0xFCFCFB
    static let sand200: UInt32 = 0xF8F7F3
    static let sand500: UInt32 = 0xF5F4F0
    static let sand600: UInt32 = 0xEEEBE3
    static let sand700: UInt32 = 0xC5C0B3
    static let sand900: UInt32 = 0x736E62

    static let vast50: UInt32 = 0xE9E8E1
    static let vast300: UInt32 = 0xB3B2AD
    static let vast400: UInt32 = 0x9D9C98
    static let vast500: UInt32 = 0x878683
    static let vast600: UInt32 = 0x71716E
    static let vast800: UInt32 = 0x464544
    static let vast875: UInt32 = 0x343432
    static let vast900: UInt32 = 0x30302F
    static let vast910: UInt32 = 0x2A2A29
    static let vast925: UInt32 = 0x202020
    static let vast950: UInt32 = 0x1A1A1A

    static let dawn100: UInt32 = 0xFCF7FF
    static let dawn700: UInt32 = 0xA26EC1
    static let dawn900: UInt32 = 0x502B66

    static let chord600: UInt32 = 0x7232A6
    static let fathom500: UInt32 = 0x68BDB0
    static let fathom800: UInt32 = 0x247872
    static let glow100: UInt32 = 0xFCE5D1
    static let glow300: UInt32 = 0xFFA946
    static let red450: UInt32 = 0xFF5757
    static let red600: UInt32 = 0xDC2626
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    /// A color that follows the effective light/dark appearance of the view it is drawn in.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: dark)
                : NSColor(hex: light)
        })
    }
}

/// Semantic colors. Views should use these, never the raw palette.
enum Theme {
    static let windowBackground = Color.adaptive(light: Palette.sand500, dark: Palette.vast950)
    static let panel = Color.adaptive(light: Palette.sand50, dark: Palette.vast925)
    static let card = Color.adaptive(light: Palette.sand500, dark: Palette.vast910)
    static let rowHover = Color.adaptive(light: Palette.sand600, dark: Palette.vast875)
    static let selection = Color.adaptive(light: Palette.sand600, dark: Palette.vast875)
    static let pillSelected = Color.adaptive(light: Palette.dawn100, dark: Palette.dawn900)
    static let border = Color.adaptive(light: Palette.sand600, dark: Palette.vast875)
    static let divider = Color.adaptive(light: Palette.sand600, dark: Palette.vast900)

    static let textPrimary = Color.adaptive(light: Palette.vast950, dark: Palette.vast50)
    static let textSecondary = Color.adaptive(light: Palette.vast600, dark: Palette.vast300)
    static let textTertiary = Color.adaptive(light: Palette.vast400, dark: Palette.vast500)

    static let primaryButton = Color.adaptive(light: Palette.vast950, dark: Palette.sand50)
    static let primaryButtonText = Color.adaptive(light: Palette.sand50, dark: Palette.vast950)
    static let secondaryButton = Color.adaptive(light: Palette.sand600, dark: Palette.vast875)
    static let toggleOn = Color.adaptive(light: Palette.vast950, dark: Palette.sand50)
    static let toggleOff = Color.adaptive(light: Palette.sand700, dark: Palette.vast800)

    static let keycap = Color(hex: Palette.glow300)
    static let keycapText = Color(hex: Palette.vast950)
    static let highlight = Color.adaptive(light: Palette.glow100, dark: Palette.vast875)
    static let micActive = Color.adaptive(light: Palette.chord600, dark: Palette.dawn700)
    static let chart = Color.adaptive(light: Palette.fathom800, dark: Palette.fathom500)
    static let destructive = Color.adaptive(light: Palette.red600, dark: Palette.red450)
}

enum Radius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
}

extension Animation {
    /// Fast start, very soft landing. The default for state changes.
    static let suki = Animation.timingCurve(0.05, 0.6, 0.4, 0.95, duration: 0.25)
    /// Small overshoot for things that pop in.
    static let sukiPop = Animation.spring(response: 0.32, dampingFraction: 0.68)
}

/// Apple system fonts: SF Pro for UI text, New York (the system serif) for display headings and numbers.
enum SukiFont {
    enum Weight {
        case regular, medium, semibold, bold

        fileprivate var system: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }
    }

    static func ui(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight.system)
    }

    static func display(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight.system, design: .serif)
    }

    static func displayItalic(_ size: CGFloat) -> Font {
        .system(size: size, design: .serif).italic()
    }
}

extension View {
    /// Small all-caps section label, e.g. "TODAY" or "WORDS PER MINUTE".
    func sectionLabelStyle() -> some View {
        font(SukiFont.ui(11, .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textSecondary)
    }
}
