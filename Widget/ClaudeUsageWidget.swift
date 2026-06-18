import SwiftUI
import WidgetKit

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeUsageWidget()
    }
}

struct ClaudeUsageWidget: Widget {
    var body: some WidgetConfiguration {
        // StaticConfiguration: Die Akzentfarbe kommt aus dem Snapshot (in der
        // App gewählt), nicht aus einer macOS-Widget-Konfiguration — Letztere
        // ist bei selbst gebauten Widgets und beim Config-Typ-Wechsel über den
        // System-Cache unzuverlässig.
        StaticConfiguration(kind: "ClaudeUsageWidget", provider: SnapshotProvider()) { entry in
            WidgetRootView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Code Usage")
        .description("Claude Code limits and token usage.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?

    /// Akzentfarbe aus dem Snapshot (in der App gewählt), Default Cyan.
    var accent: WidgetAccent { WidgetAccent.from(snapshot?.accent?.rawValue) }

    /// Snapshot deutlich älter als das Schreibintervall der App (3 min) und die
    /// Timeline-Reload-Kadenz (~30-60 min, budget-gedrosselt) — die
    /// Hintergrund-App läuft sehr wahrscheinlich nicht mehr.
    static let staleThreshold: TimeInterval = 45 * 60

    var isStale: Bool {
        guard let snapshot else { return false }
        return date.timeIntervalSince(snapshot.generatedAt) > Self.staleThreshold
    }
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        // Beispieldaten nur in der Widget-Galerie — sonst echte Daten oder
        // ehrlich „keine Daten".
        let snapshot = SnapshotLocation.read() ?? (context.isPreview ? .preview : nil)
        completion(SnapshotEntry(date: Date(), snapshot: snapshot))
    }

    /// Future-Entries rendern Zustandsübergänge (Stale-Badge, 5-h-Reset) exakt
    /// zum richtigen Zeitpunkt OHNE einen Reload zu verbrauchen — WidgetKit
    /// archiviert alle Entries vorab. Die Policy ist nur noch der Fallback.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = SnapshotLocation.read()
        let now = Date()
        var entries = [SnapshotEntry(date: now, snapshot: snapshot)]
        if let snapshot {
            let staleAt = snapshot.generatedAt.addingTimeInterval(SnapshotEntry.staleThreshold + 1)
            if staleAt > now {
                entries.append(SnapshotEntry(date: staleAt, snapshot: snapshot))
            }
            if let reset = snapshot.rateLimits?.fiveHourResetsAt, reset > now {
                // Beim 5-h-Reset fällt das Fenster auf ~0 %. Eine angepasste Kopie
                // archivieren, damit der Gauge exakt zum Reset auf 0 springt, statt
                // den alten (hohen) Prozentwert weiterzuzeigen, bis die App neue
                // Limits holt. Kostet keinen Reload (vorab archiviert); die
                // Wochen-Werte bleiben unberührt — nur das 5-h-Fenster resettet hier.
                var resetSnap = snapshot
                resetSnap.rateLimits?.fiveHourPercent = 0
                resetSnap.rateLimits?.fiveHourProjectedPercent = nil
                resetSnap.rateLimits?.fiveHourResetsAt = nil
                entries.append(SnapshotEntry(date: reset.addingTimeInterval(1), snapshot: resetSnap))
            }
        }
        entries.sort { $0.date < $1.date }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

// MARK: - Views

struct WidgetRootView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "moon.zzz")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
                Text("Open “Claude Code Usage” once, then data will appear here.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func content(_ snapshot: UsageSnapshot) -> some View {
        switch family {
        case .systemSmall:
            SmallView(snapshot: snapshot, isStale: entry.isStale, accent: entry.accent)
        case .systemLarge:
            LargeView(snapshot: snapshot, isStale: entry.isStale, now: entry.date, accent: entry.accent)
        default:
            MediumView(snapshot: snapshot, isStale: entry.isStale, now: entry.date, accent: entry.accent)
        }
    }
}

private struct LimitGauge: View {
    let title: String
    let percent: Double
    let accent: WidgetAccent

    var body: some View {
        VStack(spacing: 2) {
            Gauge(value: min(percent, 100), in: 0...100) {
                // Leer: der accessoryCircular-Style würde dieses Label sonst
                // zusätzlich zum expliziten Titel darunter rendern (Dopplung).
                Text("")
            } currentValueLabel: {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(Int(percent.rounded()))")
                        .font(.system(.title3, design: .rounded).bold())
                    Text("%")
                        .font(.system(.caption2, design: .rounded).bold())
                        .foregroundStyle(.secondary)
                }
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(accent.color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StaleBadge: View {
    var body: some View {
        Label("paused", systemImage: "pause.circle")
            .font(.caption2)
            .foregroundStyle(.orange)
    }
}

// MARK: Small — Fokus aufs 5-h-Fenster

private struct SmallView: View {
    let snapshot: UsageSnapshot
    let isStale: Bool
    let accent: WidgetAccent

    var body: some View {
        VStack(spacing: 4) {
            if let rl = snapshot.rateLimits {
                LimitGauge(title: "5 h", percent: rl.fiveHourPercent, accent: accent)
                Text("Week \(Format.percent(rl.sevenDayPercent))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Tokens today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(Format.tokens(snapshot.local.today?.tokens ?? 0))
                    .font(.system(.title2, design: .rounded).bold())
                Text("\(snapshot.local.today?.messageCount ?? 0) messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isStale { StaleBadge() }
        }
    }
}

// MARK: Medium — Limits + Tokenverbrauch

private struct MediumView: View {
    let snapshot: UsageSnapshot
    let isStale: Bool
    let now: Date
    let accent: WidgetAccent

    var body: some View {
        HStack(spacing: 16) {
            if let rl = snapshot.rateLimits {
                LimitGauge(title: "5 h", percent: rl.fiveHourPercent, accent: accent)
                LimitGauge(title: "Week", percent: rl.sevenDayPercent, accent: accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                row(label: "Tokens today", value: Format.tokens(snapshot.local.today?.tokens ?? 0))
                row(label: "Tokens 7 days", value: Format.tokens(snapshot.local.weekTokens))
                row(label: "Tokens 30 days", value: Format.tokens(snapshot.local.monthTokens))
                // Reset-Countdown nur solange er in der Zukunft liegt — ein
                // Timeline-Entry exakt zum Reset blendet die Zeile aus.
                if let rl = snapshot.rateLimits, let reset = rl.fiveHourResetsAt,
                   reset > now, rl.fiveHourPercent > 0 {
                    HStack(spacing: 4) {
                        Text("Reset")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(reset, style: .relative)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        // Hochrechnung aufs Fensterende, im Kontext der Reset-Zeile.
                        if let projected = rl.notableFiveHourProjection {
                            Text("· ≈ \(Format.percent(projected))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if isStale { StaleBadge() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(.body, design: .rounded).bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: Large — Limits + 7-Tage-Verlauf

private struct LargeView: View {
    let snapshot: UsageSnapshot
    let isStale: Bool
    let now: Date
    let accent: WidgetAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claude Code Usage").font(.headline)
                Spacer()
                if isStale { StaleBadge() }
            }

            if let rl = snapshot.rateLimits {
                HStack(spacing: 24) {
                    LimitGauge(title: "5 h", percent: rl.fiveHourPercent, accent: accent)
                    LimitGauge(title: "Week", percent: rl.sevenDayPercent, accent: accent)
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        if let reset = rl.fiveHourResetsAt, reset > now {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(reset, style: .relative)
                                    .font(.caption.monospacedDigit().bold())
                                Text("until 5-hour reset").font(.caption2).foregroundStyle(.secondary)
                            }
                            if let projected = rl.notableFiveHourProjection {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("≈ \(Format.percent(projected))")
                                        .font(.caption.monospacedDigit().bold())
                                    Text("by reset at this pace").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if rl.extraUsageEnabled, let extra = rl.extraUsagePercent {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(String(format: "%.0f %%", extra))
                                    .font(.caption.monospacedDigit().bold())
                                Text("Extra usage").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                statColumn(Format.tokens(snapshot.local.today?.tokens ?? 0), "Tokens today")
                statColumn(Format.tokens(snapshot.local.weekTokens), "Tokens 7 days")
                statColumn(Format.tokens(snapshot.local.monthTokens), "Tokens 30 days")
                statColumn("\(snapshot.local.today?.sessionCount ?? 0)", "Sessions today")
            }

            // Balkendiagramm zeigt die letzten 7 Tage (auch wenn 30 gesammelt werden).
            DayBars(days: snapshot.local.lastWeek, accent: accent)
                .frame(maxHeight: .infinity)
        }
    }

    /// Gleich breite Statistik-Spalte — verteilt die Metriken symmetrisch.
    /// Labels einzeilig (skalieren minimal statt umzubrechen), damit alle
    /// Spalten gleich hoch bleiben.
    private func statColumn(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(.body, design: .rounded).bold().monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Einfache 7-Tage-Token-Balken ohne Charts-Abhängigkeit.
private struct DayBars: View {
    let days: [UsageSnapshot.DayStat]
    let accent: WidgetAccent

    var body: some View {
        let maxTokens = max(days.map(\.tokens).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days, id: \.date) { day in
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(day.date == days.last?.date ? accent.color : accent.color.opacity(0.45))
                                .frame(height: max(geo.size.height * CGFloat(day.tokens) / CGFloat(maxTokens), 2))
                        }
                    }
                    Text(weekdayLabel(day.date))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func weekdayLabel(_ dateString: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dateString) else { return "" }
        let out = DateFormatter()
        out.dateFormat = "EE"
        return out.string(from: date)
    }
}

// MARK: - Preview-Daten für die Widget-Galerie

extension UsageSnapshot {
    static var preview: UsageSnapshot {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let today = cal.startOfDay(for: Date())
        let days: [DayStat] = (0..<30).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let scale = 1 + (offset % 7)
            return DayStat(date: fmt.string(from: date), inputTokens: 20_000 * scale,
                           outputTokens: 400_000 * scale, cacheReadTokens: 60_000_000,
                           cacheWriteTokens: 2_000_000, messageCount: 300, sessionCount: 5)
        }
        return UsageSnapshot(
            generatedAt: Date(),
            rateLimits: RateLimits(
                fiveHourPercent: 35, fiveHourResetsAt: Date().addingTimeInterval(3600),
                fiveHourProjectedPercent: 52,
                sevenDayPercent: 43, sevenDayResetsAt: Date().addingTimeInterval(86_400),
                sevenDayOpusPercent: nil, sevenDaySonnetPercent: 0,
                extraUsageEnabled: true, extraUsagePercent: 9.6,
                fetchedAt: Date()
            ),
            local: LocalUsage(days: days)
        )
    }
}
