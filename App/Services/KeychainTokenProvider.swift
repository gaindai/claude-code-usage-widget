import Foundation
import Security

/// Liest das OAuth-Token von Claude Code direkt aus dem macOS-Keychain.
/// Das Token wird ausschließlich im Speicher gehalten — niemals auf Disk
/// geschrieben, niemals geloggt. Beim ersten Zugriff zeigt macOS einen
/// Berechtigungs-Dialog ("Immer erlauben" merkt sich die Entscheidung).
enum KeychainTokenProvider {
    enum TokenError: LocalizedError {
        case notFound
        case accessDenied(OSStatus)
        case canceled(OSStatus)
        case interactionRequired
        case parseFailed

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "No Claude Code login found. Run `claude` in a terminal once and log in."
            case .accessDenied(let status):
                return "Keychain access denied (status \(status))."
            case .canceled:
                return "Keychain access was canceled — reconnect to retry."
            case .interactionRequired:
                return "Reconnect to read the Claude Code token from the keychain."
            case .parseFailed:
                return "The keychain entry has an unexpected format."
            }
        }
    }

    /// Claude Code verwendete je nach Version unterschiedliche Service-Namen.
    private static let serviceNames = ["Claude Code-credentials", "Claude Code"]

    /// Serialisiert alle Token-Reads: SecKeychainSetUserInteractionAllowed ist
    /// PROZESS-GLOBAL — ein nebenläufiger Connect-Klick (allowUI=true) und ein
    /// Hintergrund-Fetch (allowUI=false) würden sich sonst die Interaktions-
    /// Erlaubnis gegenseitig verstellen (sporadisch fehlschlagender Connect).
    private static let readLock = NSLock()

    static func accessToken(allowUI: Bool = true) throws -> String {
        readLock.lock()
        defer { readLock.unlock() }
        return try accessTokenLocked(allowUI: allowUI)
    }

    private static func accessTokenLocked(allowUI: Bool) throws -> String {
        // Automatische Hintergrund-Fetches dürfen NIE den ACL-Dialog auslösen:
        // Claude Codes Token-Refresh setzt die Keychain-Freigabe gelegentlich
        // zurück — ohne diese Sperre poppt sonst unvermittelt ein Passwort-Dialog
        // auf (sogar ohne offenes Fenster). Bei gesperrter Interaktion schlägt der
        // Zugriff mit errSecInteractionNotAllowed fehl; die App bietet dann ein
        // ruhiges „Reconnect" an. Nur explizite Nutzeraktionen lesen mit UI.
        if !allowUI {
            SecKeychainSetUserInteractionAllowed(false)
        }
        defer {
            if !allowUI { SecKeychainSetUserInteractionAllowed(true) }
        }

        // Ein Deny (z. B. errSecAuthFailed) hat Vorrang vor einem NotFound des
        // zweiten Service-Namens — sonst entsteht eine irreführende Meldung.
        var deniedStatus: OSStatus?
        var canceledStatus: OSStatus?
        for service in serviceNames {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecSuccess {
                guard let data = item as? Data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let oauth = json["claudeAiOauth"] as? [String: Any],
                      let token = oauth["accessToken"] as? String, !token.isEmpty else {
                    throw TokenError.parseFailed
                }
                return token
            }
            if status == errSecItemNotFound {
                continue // anderer Service-Name könnte passen
            }
            // Irgendein anderer Fehler. Bei unterdrückter UI (automatischer Fetch)
            // heißt das „der ACL-Dialog wäre nötig" — der genaue Code variiert je
            // nach Keychain-Typ (-25308 interactionNotAllowed / -25293 authFailed).
            if !allowUI {
                throw TokenError.interactionRequired
            }
            // UI war erlaubt, der Zugriff klappte trotzdem nicht. Nur ein echtes
            // „Deny" (errSecAuthFailed) soll die Abfrage später abschalten; ein
            // abgebrochener Dialog (errSecUserCanceled, etwa Escape) oder ein
            // transienter Keychain-Fehler darf das NICHT — sonst deaktiviert ein
            // versehentliches Abbrechen die ganze Funktion. Beides als „erneut
            // verbinden" behandeln.
            if status == errSecAuthFailed {
                deniedStatus = status
            } else {
                canceledStatus = status
            }
        }
        if let deniedStatus {
            throw TokenError.accessDenied(deniedStatus)
        }
        if let canceledStatus {
            throw TokenError.canceled(canceledStatus)
        }
        throw TokenError.notFound
    }
}
