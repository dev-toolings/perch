import AppKit
import SwiftUI

/// Design tokens for the notch UI.
///
/// The direction is the one the category has converged on and that reads well against a
/// physically black cutout: near-black surfaces, hairline white borders, monospaced text,
/// and one saturated accent per state. Colours are stated as hex so the palette is
/// auditable in one place rather than scattered through the views.
enum Theme {
    // MARK: - Surfaces

    static let surface = Color.black
    static let raised = Color(hex: 0x1A1A1A)
    static let hairline = Color.white.opacity(0.08)
    static let hairlineStrong = Color.white.opacity(0.14)

    // MARK: - Text

    static let primary = Color.white
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.38)

    // MARK: - Accents

    /// Working / succeeded.
    static let active = Color(hex: 0x4ADE80)
    /// Claude's own colour — used for anything permission-related.
    static let claude = Color(hex: 0xD97757)
    /// Informational: token counts, cache, rank.
    static let info = Color(hex: 0x60A5FA)
    static let warning = Color(hex: 0xF59E0B)
    static let danger = Color(hex: 0xEF4444)

    // MARK: - Type
    //
    // Vibe uses SwiftUI's platform designs rather than a bundled typeface: monospaced for
    // commands and counters, rounded/default for the session chrome and prose. Keeping
    // these tokens system-backed also preserves the same hinting and weight interpolation
    // on Retina and non-Retina displays.

    /// What `--diagnose` reports for the active island typography.
    static var resolvedTypefaceName: String { "system (monospaced/default/rounded)" }

    /// How wide a run of monospaced text will actually be.
    static func monoWidth(_ text: String, size: CGFloat) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Chrome uses Vibe's rounded system design, distinct from command text.
    static func label(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Prose uses Vibe's default system design; code blocks call `mono` explicitly.
    static func prose(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // MARK: - Metrics

    static let cornerRadius: CGFloat = 8
    static let rowSpacing: CGFloat = 8
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Compact number formatting — the notch has room for `1.2M`, not `1 203 481`.
extension Int {
    var compactTokens: String {
        switch self {
        case ..<1_000: return String(self)
        case ..<1_000_000:
            return String(format: "%.1fK", Double(self) / 1_000)
        case ..<1_000_000_000:
            return String(format: "%.1fM", Double(self) / 1_000_000)
        default:
            return String(format: "%.2fB", Double(self) / 1_000_000_000)
        }
    }
}

extension Double {
    /// Costs are shown to the cent above a dollar, and to a tenth of a cent below it —
    /// a run that cost $0.004 should not render as `$0.00`.
    var compactCost: String {
        if self >= 1 { return String(format: "$%.2f", self) }
        if self >= 0.01 { return String(format: "$%.2f", self) }
        return String(format: "$%.3f", self)
    }
}
