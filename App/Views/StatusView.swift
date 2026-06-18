import SwiftUI

/// Status window after onboarding: a calm material console — two gaind-gradient
/// capacity rings centered as a symmetric pair, a 7-day trend, a collapsible
/// settings card. All previous states, settings and the footer are preserved.
struct StatusView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var refreshing = false
    @State private var showSettings = false
    /// Hält den „Fetch limits"-Schalter sichtbar an, solange Keychain-Dialog und
    /// Fetch laufen — sonst springt er zurück auf AUS und wirkt kaputt.
    @State private var connectingLimits = false

    /// Snapshot deutlich älter als App-Schreibintervall + Reload-Kadenz → die
    /// Hintergrund-App läuft vermutlich nicht mehr (gleiche Schwelle wie das Widget).
    private var isStale: Bool {
        guard let g = state.snapshot?.generatedAt else { return false }
        return Date().timeIntervalSince(g) > 45 * 60
    }

    var body: some View {
        ZStack(alignment: .top) {
            DS.canvas(scheme).ignoresSafeArea()
            BrandWash(accent: state.accent)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                    header
                    if state.widgetPlaced == false { widgetCTA }
                    limitsSection
                    activitySection
                    settingsSection
                    footer
                }
                .padding(DS.Spacing.xxl)
                // Etwas Luft oben, damit der Header die Ampel-Buttons frei lässt
                // (fullSizeContentView).
                .padding(.top, DS.Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 480, idealWidth: 560)
        .onAppear { state.checkWidgetPlaced() }
    }

    // MARK: Widget-Platzierungs-Hinweis (verschwindet, sobald eines liegt)

    private var widgetCTA: some View {
        VStack(spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .foregroundStyle(state.accent.color)
                Text("Add the widget to your desktop")
                    .font(.callout.weight(.semibold))
            }
            Text("This window is just the app. Right-click the desktop → “Edit Widgets” → search **Claude Code Usage**.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.m)
        .background(state.accent.color.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(state.accent.color.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DS.Spacing.s) {
            SignetDot(accent: state.accent, size: 10)
            Text("Claude Code Usage").font(.title3.weight(.semibold))
            Spacer()
            if isStale { pausedPill }
            if let last = state.lastRefresh {
                Text("Updated \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            refreshButton
        }
    }

    private var pausedPill: some View {
        Label("Paused", systemImage: "pause.circle")
            .font(.caption2)
            .foregroundStyle(DS.danger)
            .padding(.horizontal, DS.Spacing.s)
            .padding(.vertical, 3)
            .background(DS.danger.opacity(0.12), in: Capsule())
    }

    private var refreshButton: some View {
        Button {
            refreshing = true
            Task {
                await state.refresh(force: true)
                refreshing = false
            }
        } label: {
            if refreshing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .buttonStyle(.borderless)
        .help("Refresh now")
        .disabled(refreshing)
    }

    // MARK: Limits

    @ViewBuilder
    private var limitsSection: some View {
        if let rl = state.snapshot?.rateLimits {
            section("Limits") {
                Card {
                    VStack(spacing: DS.Spacing.l) {
                        HStack(alignment: .top, spacing: DS.Spacing.xxl + DS.Spacing.m) {
                            ring(value: rl.fiveHourPercent, label: "5 H",
                                 reset: rl.fiveHourResetsAt,
                                 projection: rl.notableFiveHourProjection,
                                 diameter: 104, lineWidth: 11)
                            ring(value: rl.sevenDayPercent, label: "Week",
                                 reset: rl.sevenDayResetsAt, diameter: 104, lineWidth: 11)
                        }
                        .frame(maxWidth: .infinity)
                        let chips = limitChips(rl)
                        if !chips.isEmpty {
                            HStack(spacing: DS.Spacing.s) {
                                ForEach(chips) { chip in chipView(chip) }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        if state.rateLimitNeedsReconnect {
                            reconnectHint
                        } else if let error = state.rateLimitError {
                            // z. B. 401 „Token expired": Keychain-Lesen klappte,
                            // aber der Server lehnt das Token ab — Reconnect hilft
                            // nicht (Claude Code muss es erneuern). Daher nur ein
                            // ruhiger Hinweis über den zuletzt bekannten Werten,
                            // kein Reconnect-Button.
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } else if state.rateLimitsEnabled, state.rateLimitNeedsReconnect {
            section("Limits") {
                Card {
                    VStack(spacing: DS.Spacing.s) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                            .imageScale(.large)
                        Text("Limits paused — reconnect to refresh your 5-hour and weekly usage.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        reconnectButton
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } else if state.rateLimitsEnabled, let error = state.rateLimitError {
            section("Limits") {
                Card {
                    VStack(spacing: DS.Spacing.s) {
                        Image(systemName: "key.slash")
                            .foregroundStyle(.secondary)
                            .imageScale(.large)
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Connect") {
                            Task { await state.connectRateLimits() }
                        }
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        // Limits deaktiviert → Sektion entfällt, Activity wird zum Hero.
    }

    private func ring(value: Double, label: String, reset: Date?,
                      projection: Double? = nil,
                      diameter: CGFloat, lineWidth: CGFloat) -> some View {
        VStack(spacing: DS.Spacing.s) {
            RingGauge(value: value, label: label, accent: state.accent,
                      diameter: diameter, lineWidth: lineWidth)
            if let reset, reset > Date() {
                (Text("resets ") + Text(reset, style: .relative))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                // Hochrechnung aufs Fensterende — bei drohendem Limit in der
                // Warnfarbe, damit der Blick hängen bleibt.
                if let projection {
                    Text("≈ \(Format.percent(projection)) by reset")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(projection >= 99.5 ? DS.danger : Color.secondary)
                }
            }
        }
    }

    private struct LimitChip: Identifiable {
        let id: String
        let label: String
        let value: Double
    }

    private func limitChips(_ rl: UsageSnapshot.RateLimits) -> [LimitChip] {
        var chips: [LimitChip] = []
        if let opus = rl.sevenDayOpusPercent {
            chips.append(LimitChip(id: "opus", label: "Opus", value: opus))
        }
        if rl.extraUsageEnabled, let extra = rl.extraUsagePercent {
            chips.append(LimitChip(id: "extra", label: "Extra", value: extra))
        }
        return chips
    }

    private func chipView(_ chip: LimitChip) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            SignetDot(accent: state.accent, size: 6)
            Text(chip.label).font(.caption2).foregroundStyle(.secondary)
            Text(Format.percent(chip.value)).font(.caption2.monospacedDigit().weight(.medium))
        }
        .padding(.horizontal, DS.Spacing.s)
        .padding(.vertical, DS.Spacing.xs)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    // MARK: Reconnect (Keychain-Freigabe nach Token-Refresh zurückgesetzt)

    private var reconnectButton: some View {
        Button {
            Task { await state.connectRateLimits() }
        } label: {
            Label("Reconnect", systemImage: "arrow.clockwise")
        }
        .controlSize(.small)
        .tint(state.accent.color)
    }

    /// Dezenter Hinweis unter den Ringen, wenn nur noch gecachte Werte gezeigt werden.
    private var reconnectHint: some View {
        Button {
            Task { await state.connectRateLimits() }
        } label: {
            Label("Showing last values · reconnect to refresh", systemImage: "arrow.clockwise")
                .font(.caption2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: Activity

    @ViewBuilder
    private var activitySection: some View {
        section("Activity") {
            Card {
                if let local = state.snapshot?.local, !local.days.isEmpty {
                    VStack(spacing: DS.Spacing.m) {
                        VStack(spacing: DS.Spacing.xs) {
                            Text(Format.tokens(local.today?.tokens ?? 0))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            HStack(spacing: DS.Spacing.s) {
                                Text("tokens today")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                deltaBadge(local)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Sparkline(days: local.lastWeek, accent: state.accent, height: 72, showsAxes: true)

                        HStack(spacing: DS.Spacing.xxl + DS.Spacing.m) {
                            labeledStat("7 days", Format.tokens(local.weekTokens))
                            labeledStat("30 days", Format.tokens(local.monthTokens))
                        }
                        .frame(maxWidth: .infinity)

                        Text("\(local.today?.messageCount ?? 0) messages · \(local.today?.sessionCount ?? 0) sessions today")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: DS.Spacing.s) {
                        Image(systemName: "moon.zzz")
                            .imageScale(.large)
                            .foregroundStyle(.secondary)
                        Text("No local data yet. Run Claude Code once.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.l)
                }
            }
        }
    }

    @ViewBuilder
    private func deltaBadge(_ local: UsageSnapshot.LocalUsage) -> some View {
        let days = local.days
        if days.count >= 2, days[days.count - 2].tokens > 0 {
            let today = days[days.count - 1].tokens
            let yesterday = days[days.count - 2].tokens
            let pct = Double(today - yesterday) / Double(yesterday) * 100
            let up = pct >= 0
            HStack(spacing: 2) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                Text("\(abs(Int(pct.rounded())))% vs yest.")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func labeledStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Settings (Card-basierte Klappsektion — kein DisclosureGroup-Clipping)

    private var settingsSection: some View {
        Card {
            VStack(spacing: DS.Spacing.m) {
                Button {
                    withAnimation(.smooth(duration: 0.22)) { showSettings.toggle() }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        SectionLabel("Settings")
                        Image(systemName: showSettings ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showSettings {
                    VStack(alignment: .leading, spacing: DS.Spacing.m) {
                        accentPicker
                        Toggle("Launch at login", isOn: Binding(
                            get: { state.loginItemEnabled },
                            set: { state.setLoginItem($0) }
                        ))
                        Toggle("Fetch session/weekly limits (keychain)", isOn: Binding(
                            get: { connectingLimits || state.rateLimitsEnabled },
                            set: { enabled in
                                if enabled {
                                    connectingLimits = true
                                    Task {
                                        await state.connectRateLimits()
                                        connectingLimits = false
                                    }
                                } else {
                                    state.disconnectRateLimits()
                                }
                            }
                        ))
                        if state.loginItemNeedsApproval {
                            HStack(spacing: DS.Spacing.s) {
                                Text("macOS needs your approval under Login Items.")
                                    .font(.caption)
                                    .foregroundStyle(DS.danger)
                                Button("Open System Settings") {
                                    LoginItemManager.openSystemSettings()
                                }
                                .controlSize(.small)
                            }
                        }
                        Button("Show onboarding again") {
                            state.onboardingCompleted = false
                        }
                        .buttonStyle(.link)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    accentPreview
                }
            }
            .frame(maxWidth: .infinity)
        }
        .tint(state.accent.color)
    }

    /// Nicht-interaktive Vorschau der Akzentfarbe im eingeklappten Zustand.
    private var accentPreview: some View {
        HStack(spacing: DS.Spacing.s) {
            ForEach(WidgetAccent.allCases) { a in
                Circle()
                    .fill(a.color)
                    .frame(width: 9, height: 9)
                    .opacity(a == state.accent ? 1 : 0.4)
            }
        }
    }

    private var accentPicker: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text("Widget accent color").font(.callout)
            HStack(spacing: DS.Spacing.m) {
                ForEach(WidgetAccent.allCases) { a in
                    Button {
                        state.setAccent(a)
                    } label: {
                        Circle()
                            .fill(a.color)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.6),
                                            lineWidth: a == state.accent ? 2 : 0)
                                    .padding(-3)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(a.displayName)
                }
            }
            HStack(spacing: DS.Spacing.xs) {
                Text("Brand palette by")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Link("gaind.ai", destination: URL(string: "https://gaind.ai")!)
                    .font(.caption2)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: DS.Spacing.xs) {
            Divider().opacity(0.5)
            Text("Read-only on local Claude Code data · token stays in the keychain · only network call: api.anthropic.com")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: DS.Spacing.xs) {
                Text("Made by")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Link("gaind.ai", destination: URL(string: "https://gaind.ai")!)
                    .font(.caption2)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Link("Julian Hermes", destination: URL(string: "https://www.linkedin.com/in/julianhermes")!)
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Spacing.s)
    }

    // MARK: Helper

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: DS.Spacing.s) {
            SectionLabel(title)
            content()
        }
        .frame(maxWidth: .infinity)
    }
}
