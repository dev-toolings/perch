import Foundation
import PerchKit

/// Fires an end-to-end encrypted Bark notification. The phone owns the matching AES key
/// and IV; the selected Bark server sees only an opaque `ciphertext` field.
enum PushNotifier {
  static func send(
    settings: PushSettings,
    credentials: BarkCredentials,
    title: String,
    body: String,
    kind: InterruptionKind? = nil
  ) {
    let request: URLRequest
    do {
      request = try BarkRequest.make(
        server: settings.server,
        credentials: credentials,
        title: title,
        body: body,
        level: level(for: kind))
    } catch {
      PerchLog.error("bark: could not build notification: \(error)")
      return
    }

    Task.detached(priority: .utility) {
      do {
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else {
          let status = (response as? HTTPURLResponse)?.statusCode ?? 0
          PerchLog.error("bark: server rejected notification with HTTP \(status)")
          return
        }
      } catch {
        PerchLog.error("bark: failed to send: \(error)")
      }
    }
  }

  private static func level(for kind: InterruptionKind?) -> String {
    guard let kind else { return "active" }
    return kind.isBlocking || kind == .taskError ? "timeSensitive" : "active"
  }
}
