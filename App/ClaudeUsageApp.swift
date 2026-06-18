import SwiftUI

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Die App läuft als Hintergrund-Agent (LSUIElement); das Fenster wird
        // vom AppDelegate verwaltet, damit Login-Item-Starts unsichtbar bleiben.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = AppState()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.start()
        // Onboarding nur beim allerersten Start automatisch zeigen — sonst
        // poppt das Fenster bei jedem Login erneut auf, wenn jemand es ohne
        // „Fertig" geschlossen hat. Manuelles Öffnen geht jederzeit (Reopen).
        let didAutoShow = UserDefaults.standard.bool(forKey: "didAutoShowOnboarding")
        if !state.onboardingCompleted && !didAutoShow {
            UserDefaults.standard.set(true, forKey: "didAutoShowOnboarding")
            showWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func showWindow() {
        if window == nil {
            let hosting = NSHostingController(rootView: RootView().environmentObject(state))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Claude Code Usage"
            // Randloses, frei skalierbares Fenster: Inhalt läuft unter die
            // Titelleiste, der eigene Header übernimmt deren Rolle — nahtloser Canvas.
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.contentMinSize = NSSize(width: 460, height: 360)
            w.setContentSize(NSSize(width: 560, height: 740))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        // Solange ein Fenster offen ist, als reguläre App im Dock erscheinen;
        // beim Schließen zurück zum unsichtbaren Hintergrund-Agent (LSUIElement).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        // Beim Öffnen frische Daten ziehen — sonst zeigt das gerade geöffnete
        // Fenster den Stand des letzten (ggf. lange durch App Nap verzögerten)
        // Hintergrund-Ticks, bis man manuell aktualisiert. Wurde die Keychain-
        // Freigabe zurückgesetzt (rateLimitNeedsReconnect), JETZT einen erlaubten
        // Fetch anstoßen: der Dialog erscheint genau beim Öffnen — ein erwarteter
        // Moment — statt die kleine „Reconnect"-Aktion erst suchen zu müssen.
        // Sonst still (allowUI:false), damit ein Öffnen nie unerwartet promptet.
        let needsReconnect = state.rateLimitsEnabled && state.rateLimitNeedsReconnect
        Task { await state.refresh(force: needsReconnect, allowUI: needsReconnect) }
    }

    func windowWillClose(_ notification: Notification) {
        // Zurück in den Agent-Modus: kein Dock-Icon, kein Menü.
        NSApp.setActivationPolicy(.accessory)
    }
}
