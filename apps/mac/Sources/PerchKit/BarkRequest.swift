import CommonCrypto
import Foundation
import Security

public struct BarkCredentials: Codable, Sendable, Equatable {
  public let deviceKey: String
  public let encryptionKey: String?
  public let encryptionIV: String?

  public init(deviceKey: String, encryptionKey: String? = nil, encryptionIV: String? = nil) {
    self.deviceKey = deviceKey
    self.encryptionKey = encryptionKey
    self.encryptionIV = encryptionIV
  }
}

extension BarkCredentials {
  public var isComplete: Bool {
    guard !deviceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    switch (encryptionKey, encryptionIV) {
    case (nil, nil): return true
    case (.some(let key), .some(let iv)):
      return key.utf8.count == kCCKeySizeAES256 && iv.utf8.count == kCCBlockSizeAES128
    default: return false
    }
  }
}

public enum BarkRequestError: Error, Equatable, LocalizedError {
  case missingDeviceKey
  case incompleteEncryptionCredentials
  case invalidServer
  case encodingFailed

  public var errorDescription: String? {
    switch self {
    case .missingDeviceKey: return "Bark device key is empty."
    case .incompleteEncryptionCredentials:
      return "Bark encryption requires both a 32-byte key and a 16-byte IV."
    case .invalidServer: return "Bark server must be an absolute HTTP or HTTPS URL."
    case .encodingFailed: return "Bark notification payload could not be encoded as JSON."
    }
  }
}

public enum BarkCredentialGenerationError: Error, Equatable, LocalizedError {
  case randomGenerationFailed(OSStatus)

  public var errorDescription: String? {
    switch self {
    case .randomGenerationFailed(let status):
      return "Bark encryption credentials could not be generated (Security status \(status))."
    }
  }
}

extension BarkCredentials {
  public static func generated(deviceKey: String = "") throws -> BarkCredentials {
    BarkCredentials(
      deviceKey: deviceKey,
      encryptionKey: try randomText(length: kCCKeySizeAES256),
      encryptionIV: try randomText(length: kCCBlockSizeAES128))
  }

  private static func randomText(length: Int) throws -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    var bytes = [UInt8](repeating: 0, count: length)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
      throw BarkCredentialGenerationError.randomGenerationFailed(status)
    }
    return String(bytes.map { alphabet[Int($0 & 63)] })
  }
}

public enum BarkRequest {
  private struct Notification: Codable {
    let title: String
    let body: String
    let group: String
    let level: String
  }

  private struct Envelope: Encodable {
    let deviceKey: String
    let title: String?
    let body: String
    let group: String
    let level: String
    let ciphertext: String?

    enum CodingKeys: String, CodingKey {
      case deviceKey = "device_key"
      case title, body, group, level, ciphertext
    }
  }

  public static func make(
    server: String,
    credentials: BarkCredentials,
    title: String,
    body: String,
    group: String = "Perch",
    level: String = "active"
  ) throws -> URLRequest {
    let deviceKey = credentials.deviceKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !deviceKey.isEmpty else { throw BarkRequestError.missingDeviceKey }
    guard
      let baseURL = URL(string: server),
      let scheme = baseURL.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      baseURL.host != nil
    else { throw BarkRequestError.invalidServer }

    let endpoint = baseURL.appendingPathComponent("push")
    let notification = Notification(
      title: title,
      body: String(body.prefix(240)),
      group: group,
      level: level)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let envelope: Envelope
    switch (credentials.encryptionKey, credentials.encryptionIV) {
    case (nil, nil):
      envelope = Envelope(
        deviceKey: deviceKey, title: notification.title, body: notification.body,
        group: group, level: level, ciphertext: nil)
    case (.some(let key), .some(let iv)):
      guard let plaintext = try? encoder.encode(notification) else {
        throw BarkRequestError.encodingFailed
      }
      envelope = Envelope(
        deviceKey: deviceKey, title: nil, body: "Encrypted notification",
        group: group, level: level,
        ciphertext: try BarkCrypto.encrypt(plaintext, key: key, iv: iv))
    default:
      throw BarkRequestError.incompleteEncryptionCredentials
    }

    guard let data = try? encoder.encode(envelope) else {
      throw BarkRequestError.encodingFailed
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.httpBody = data
    return request
  }
}
