import SwiftUI

/// Guided first launch, streamlined to two real action steps and laid out on a
/// single centered axis (matching the status window). The "we found your data"
/// status is folded into the welcome header as a confirmation, not a step:
/// 1. Show your usage limits (the point)   2. Add the widget + autostart.
struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var connecting = false

    var body: some View {
        ZStack(alignment: .top) {
            DS.canvas(scheme).ignoresSafeArea()
            BrandWash(accent: state.accent)

            VStack(spacing: 0) {
                welcomeHeader

                Divider().opacity(0.5)

                ScrollView {
                    VStack(spacing: DS.Spacing.l) {
                        stepLimits
                        stepWidget
                    }
                    .padding(.horizontal, DS.Spacing.xxl)
                    .padding(.vertical, DS.Spacing.xxl)
                }

                Divider().opacity(0.5)

                VStack(spacing: DS.Spacing.s) {
                    Text("Everything stays on your Mac — the only network call goes to api.anthropic.com.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Done") {
                        state.onboardingCompleted = true
                    }
                    .keyboardShortcut(.defaultAction)
                    .tint(state.accent.color)
                }
                .frame(maxWidth: .infinity)
                .padding(DS.Spacing.l)
            }
        }
        .frame(minWidth: 480, idealWidth: 560)
    }

    // MARK: Welcome + data confirmation (centered hero)

    private var welcomeHeader: some View {
        VStack(spacing: DS.Spacing.s) {
            SignetDot(accent: state.accent, size: 12)
            Text("Welcome to Claude Code Usage")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("Two quick steps, then your desktop shows your Claude Code usage.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: DS.Spacing.xs) {
                Text("by")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("gaind.ai", destination: URL(string: "https://gaind.ai")!)
                    .font(.caption)
            }

            dataConfirmation
                .padding(.top, DS.Spacing.s)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.xxl)
        .padding(.top, DS.Spacing.s)
    }

    @ViewBuilder
    private var dataConfirmation: some View {
        if state.localDataAvailable, let local = state.snapshot?.local, !local.days.isEmpty {
            VStack(spacing: DS.Spacing.xs) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(state.accent.color)
                    Text("Found your Claude Code data · \(Format.tokens(local.weekTokens)) tokens this week")
                        .font(.callout)
                }
                Sparkline(days: local.lastWeek, accent: state.accent, height: 36)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: DS.Spacing.s) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "moon.zzz").foregroundStyle(.secondary)
                    Text("No local Claude Code data yet — run Claude Code once.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button("Check again") {
                    Task { await state.refresh(force: true) }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Step 1 — limits (the point)

    private var stepLimits: some View {
        StepBox(number: 1, done: state.rateLimitsEnabled, accent: state.accent,
                title: "Show your usage limits") {
            VStack(spacing: DS.Spacing.s) {
                Text("The whole point: your live 5-hour window and weekly limit on the desktop, just like `/usage`. To do that the app reads the Claude Code token from the keychain — it is only ever sent to api.anthropic.com for this request and never stored or logged.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                // Auf dauerhafte Signale stützen (persistiertes rateLimitsEnabled,
                // tatsächliche Limits im Snapshot), NICHT auf das pro Sitzung
                // zurückgesetzte keychainConnected — sonst zeigt ein erneut
                // geöffnetes Onboarding direkt nach dem Start fälschlich „Connect"
                // und löst einen unnötigen Keychain-Dialog aus.
                if state.rateLimitsEnabled, let rl = state.snapshot?.rateLimits {
                    HStack(spacing: DS.Spacing.xxl) {
                        RingGauge(value: rl.fiveHourPercent, label: "5 H", accent: state.accent,
                                  diameter: 84, lineWidth: 9)
                        RingGauge(value: rl.sevenDayPercent, label: "Week", accent: state.accent,
                                  diameter: 84, lineWidth: 9)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Spacing.xs)
                } else {
                    Button {
                        connecting = true
                        Task {
                            await state.connectRateLimits()
                            connecting = false
                        }
                    } label: {
                        if connecting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Connect — choose “Always Allow” in the dialog")
                        }
                    }
                    .tint(state.accent.color)
                    .disabled(connecting)
                    if let error = state.rateLimitError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(DS.danger)
                            .multilineTextAlignment(.center)
                    }
                    Text("No keychain access? The widget still shows your local token usage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Step 2 — widget + autostart

    private var stepWidget: some View {
        StepBox(number: 2, done: state.loginItemEnabled, accent: state.accent,
                title: "Add the widget & keep it current") {
            VStack(spacing: DS.Spacing.s) {
                Text("Right-click the desktop → “Edit Widgets” → search for **Claude Code Usage** → pick a size and place it.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Launch at login", isOn: Binding(
                    get: { state.loginItemEnabled },
                    set: { state.setLoginItem($0) }
                ))
                .fixedSize()
                Text("Recommended — keeps the widget current.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct StepBox<Content: View>: View {
    let number: Int
    let done: Bool
    let accent: WidgetAccent
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: DS.Spacing.m) {
            HStack(spacing: DS.Spacing.s) {
                stepIndicator
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity)
            content
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [DS.cardTopHighlight, .clear],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        )
    }

    // Reine Status-Anzeige, KEIN Bedienelement: die Schrittnummer wird bei
    // Erledigung zum Haken. Ein gefüllter Nummern-Disc liest sich klar als
    // „Schritt N", anders als ein leeres `circle`, das wie eine anklickbare
    // Checkbox wirkt.
    @ViewBuilder
    private var stepIndicator: some View {
        if done {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(accent.color)
                .imageScale(.large)
        } else {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
        }
    }
}
