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
        // Hintergrund-Ticks. Immer still (allowUI:false): ein Öffnen darf NIE einen
        // Passwort-Dialog auslösen. Ist die Keychain-Freigabe noch gültig, holt der
        // stille Fetch frische Limits ohne Dialog; wurde sie (durch Claude Codes
        // Token-Refresh) zurückgesetzt, bleibt es beim ruhigen „Reconnect"-Hinweis,
        // den man bei Bedarf selbst antippt. Ein proaktiver Prompt beim Öffnen
        // brächte nichts Dauerhaftes — „Immer erlauben" hält nicht, weil Claude
        // Code das Keychain-Item beim nächsten Refresh ohnehin neu anlegt.
        Task { await state.refresh(force: true, allowUI: false) }
    }

    func windowWillClose(_ notification: Notification) {
        // Zurück in den Agent-Modus: kein Dock-Icon, kein Menü.
        NSApp.setActivationPolicy(.accessory)
    }
}
