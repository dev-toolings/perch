import Foundation
import PerchKit

/// Fires a push through ntfy — the public instance by default, or a self-hosted one — for
/// the one case a notch on an empty desk cannot help with: a session blocked on an answer
/// while nobody is there to see it ask.
///
/// Fire-and-forget by design. `PushDecision` already did the only thing worth blocking
/// on — deciding whether to send at all — so a network failure here is not the caller's
/// problem to wait for; it is a log line.
enum PushNotifier {
    static func send(settings: PushSettings, title: String, body: String) {
        guard let url = URL(string: "\(settings.server)/\(settings.topic)") else {
            PerchLog.error("push: could not build a URL from the configured server/topic")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // ntfy reads the message title and body from headers/body directly — no JSON
        // envelope needed for the plain case this app uses.
        request.setValue(title, forHTTPHeaderField: "Title")
        // Long enough to say what is waiting, short enough that a phone notification does
        // not become the whole plan.
        request.httpBody = Data(String(body.prefix(200)).utf8)

        // Detached rather than awaited from the main actor: nothing downstream of a push
        // needs its result, and a hook response must not wait on someone's phone network.
        Task.detached(priority: .utility) {
            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                PerchLog.error("push: failed to send: \(error)")
            }
        }
    }
}
