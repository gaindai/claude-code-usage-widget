import SwiftUI

/// Zentrale Design-Tokens und wiederverwendbare Bausteine für die App-Fenster
/// (Status + Onboarding). BEWUSST nur im App-Target — die Widget-Extension
/// kompiliert diese Datei nicht und bleibt damit unverändert.
///
/// Die Marke lebt im Gradient: gaind-Signet Cyan → Blue → Purple → Magenta.
/// Bei Markenfarben tragen ihn Signet-Punkt und Hintergrund-Wash
/// (`WidgetAccent.isBrandColor` → `dotStyle`); Ringe und Sparkline folgen
/// dagegen der gewählten Einzelfarbe, damit die App parallel zum Widget umfärbt.
enum DS {
    // MARK: Farben
    static let cyan = Color(accentHex: 0x6EAAF0)
    static let blue = Color(accentHex: 0x0C4AB2)
    static let purple = Color(accentHex: 0x5748D4)
    static let magenta = Color(accentHex: 0xA945F8)

    static let canvasDark = Color(accentHex: 0x0E0E12)
    static let canvasLight = Color(accentHex: 0xF6F7F9)
    /// Warmes Bernstein als „nah an der Grenze"-Hinweis — bewusst NICHT System-Rot
    /// und nie Teil der Gradient-Bedeutung.
    static let danger = Color(accentHex: 0xE6892E)
    static let cardTopHighlight = Color.white.opacity(0.06)

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? canvasDark : canvasLight
    }

    // MARK: Gradient-Engine
    static var gaindStops: [Color] { [cyan, blue, purple, magenta] }
    static var gaindGradient: Gradient { Gradient(colors: gaindStops) }
    static var gaindLinear: LinearGradient {
        LinearGradient(gradient: gaindGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Maße
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }
    enum Radius {
        static let card: CGFloat = 18
        static let control: CGFloat = 10
    }
}

// MARK: - Akzent-Bridge

extension WidgetAccent {
    /// Ring-Füllung (der tatsächliche Verbrauch) — die gewählte Einzelfarbe,
    /// damit die App-Ringe parallel zum Widget umfärben (das Widget tint't seine
    /// Gauges ebenfalls mit `color`).
    var ringFillStyle: AnyShapeStyle { AnyShapeStyle(color) }

    /// Ring-Spur — dieselbe Farbe, nur gespenstisch leise, damit die Füllung
    /// selbst bei wenigen Prozent auf einer sichtbaren Bahn liegt.
    var ringTrackStyle: AnyShapeStyle { AnyShapeStyle(color.opacity(0.16)) }

    /// Signet-Punkt + Wash tragen die Marke: voller Signet-Gradient bei
    /// Markenfarben, sonst die einzelne Farbe. Bewusst NUR hier — Ringe und
    /// Sparkline folgen der gewählten Farbe, nicht dem Gradienten.
    var dotStyle: AnyShapeStyle {
        isBrandColor ? AnyShapeStyle(DS.gaindLinear) : AnyShapeStyle(color)
    }

    /// Linienfarbe der Sparkline — die gewählte Farbe (kräftig, einfarbig).
    var lineColor: Color { color }

    /// Flächenfüllung unter der Sparkline — vertikal nach unten ausblendend.
    var areaStyle: AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(colors: [color.opacity(0.35), color.opacity(0.04)],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}

// MARK: - RingGauge

/// Kreis-Gauge: leise Vollkreis-Spur (ganzer Gradient) + kräftige Teilkreis-Füllung.
struct RingGauge: View {
    let value: Double          // 0...100
    let label: String
    let accent: WidgetAccent
    var diameter: CGFloat = 120
    var lineWidth: CGFloat = 12
    var showsValueLabel = true

    private var fraction: Double { min(max(value, 0), 100) / 100 }

    var body: some View {
        ZStack {
            ZStack {
                Circle()
                    .stroke(accent.ringTrackStyle, style: StrokeStyle(lineWidth: lineWidth))
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(accent.ringFillStyle,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    // Ehrlicher „nah an der Grenze"-Hinweis — der Gradient selbst
                    // bedeutet nie Gefahr.
                    .shadow(color: value > 85 ? DS.danger.opacity(0.7) : .clear, radius: 5)
            }
            .rotationEffect(.degrees(-90))   // Start oben (12 Uhr)

            if showsValueLabel {
                VStack(spacing: 1) {
                    (Text("\(Int(value.rounded()))")
                        .font(.system(size: diameter * 0.27, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                     + Text("%")
                        .font(.system(size: diameter * 0.16, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Text(label)
                        .font(.caption2)
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.smooth(duration: 0.5), value: value)
    }
}

// MARK: - SignetDot

/// Marken-Anker: kleiner Punkt im vollen Gradient (oder einfarbig bei neutralem Akzent).
struct SignetDot: View {
    let accent: WidgetAccent
    var size: CGFloat = 9

    var body: some View {
        Circle()
            .fill(accent.dotStyle)
            .frame(width: size, height: size)
    }
}

// MARK: - BrandWash

/// Statischer Marken-Schimmer, der oben „pooled" und zur Mitte hin ausläuft.
/// Liegt hinter Header + Limits und stirbt vor der Activity-Karte.
struct BrandWash: View {
    let accent: WidgetAccent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(accent.dotStyle)
            .opacity(scheme == .dark ? 0.10 : 0.14)
            .mask(
                LinearGradient(colors: [.white, .clear],
                               startPoint: .top, endPoint: .center)
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

// MARK: - Card

/// Material-Karte mit zartem oberem Lichtsaum und weichem Schatten — keine
/// harten Ränder. Ersetzt die alten GroupBoxes.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(DS.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [DS.cardTopHighlight, .clear],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

// MARK: - Section-Header

/// Kleines, getracktes Großbuchstaben-Label über jeder Karte.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.9)
            .foregroundStyle(.secondary)
    }
}
