import Foundation
import LocalAuthentication
import Security

public enum BarkCredentialStoreError: Error, Equatable, LocalizedError {
  case keychain(OSStatus)
  case invalidRecord

  public var errorDescription: String? {
    switch self {
    case .keychain(let status):
      let detail = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
      return "Bark credentials could not be stored in the login keychain: \(detail) (\(status))."
    case .invalidRecord:
      return "Stored Bark credentials are not a valid credential record."
    }
  }
}

/// Bark's device key and encryption material are credentials, not preferences. Keeping
/// them in the login keychain prevents `.perch/push.json` and diagnostics from exposing
/// the values that can address or decrypt a phone notification.
public struct BarkCredentialStore: Sendable {
  public let service: String
  public let account: String

  public init(service: String = "tech.kweli.perch.bark", account: String = "notification") {
    self.service = service
    self.account = account
  }

  public func load() throws -> BarkCredentials? {
    try load(authenticationContext: nil)
  }

  /// Reads the optional Bark record without opening a macOS authentication prompt.
  ///
  /// Perch performs this read during launch while push is disabled by default. An ad-hoc
  /// debug signature changes after every rebuild, so an interactive Keychain lookup would
  /// repeatedly ask the user to approve the same development binary. Explicit Bark setup
  /// still uses `load()`, which preserves the normal Keychain UX when requested.
  public func loadWithoutPrompt() throws -> BarkCredentials? {
    let context = LAContext()
    context.interactionNotAllowed = true
    return try load(authenticationContext: context)
  }

  private func load(authenticationContext: LAContext?) throws -> BarkCredentials? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    if let authenticationContext {
      query[kSecUseAuthenticationContext as String] = authenticationContext
    }
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw BarkCredentialStoreError.keychain(status) }
    guard let data = result as? Data,
      let credentials = try? JSONDecoder().decode(BarkCredentials.self, from: data)
    else { throw BarkCredentialStoreError.invalidRecord }
    return credentials
  }

  public func save(_ credentials: BarkCredentials) throws {
    let data = try JSONEncoder().encode(credentials)
    let attributes = [kSecValueData as String: data]
    let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw BarkCredentialStoreError.keychain(updateStatus)
    }

    var item = baseQuery
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(item as CFDictionary, nil)
    guard addStatus == errSecSuccess else { throw BarkCredentialStoreError.keychain(addStatus) }
  }

  public func remove() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw BarkCredentialStoreError.keychain(status)
    }
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
