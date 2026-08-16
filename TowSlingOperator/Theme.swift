import SwiftUI

/// The dashboard's palette, lifted from the web app so the two do not drift.
///
/// These are the same hex values as :root in index.html. When a colour changes
/// there it has to change here — there is no way to share them short of
/// generating one from the other, and a colour that is nearly right reads worse
/// than one that is obviously different.
enum Theme {

    static let bg      = Color(hex: 0x0D1117)
    static let panel   = Color(hex: 0x151B23)
    static let panel2  = Color(hex: 0x1B232D)
    static let line    = Color(hex: 0x242E3A)

    static let ink     = Color(hex: 0xE6EDF3)
    static let inkDim  = Color(hex: 0x8B98A8)
    static let inkFaint = Color(hex: 0x5D6B7D)

    static let accent    = Color(hex: 0xFF7A18)
    static let accentDim = Color(hex: 0xC25A0E)

    static let green = Color(hex: 0x2EA043)
    static let red   = Color(hex: 0xE5534B)
    static let amber = Color(hex: 0xD29922)

    /// The "will not start" / "accident" chip on a job card.
    static let problemInk = Color(hex: 0xF0B429)
    static let problemBg  = Color(hex: 0x241D0D)
    static let problemLine = Color(hex: 0x6B4F0F)
}

extension Color {
    /// 0xRRGGBB, so the values above can be pasted straight from the CSS.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Shared bits of chrome

/// A panel with the same border and radius as the web `.pane`.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

extension View {
    func cardBackground(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

/// The orange primary button, sized for a thumb in a work glove.
struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(enabled ? Theme.accent : Theme.accentDim.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

/// The quieter outline button.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.inkDim)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Theme.panel2)
            .overlay(
                RoundedRectangle(cornerRadius: 11).stroke(Theme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

/// Money, formatted the one way for the whole app.
///
/// Never string interpolation on a Double: `"\(99.5)"` is "99.5" and a driver
/// reading "$99.5" on a payout screen has every right to wonder where the rest
/// went.
enum Money {
    static func string(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}
