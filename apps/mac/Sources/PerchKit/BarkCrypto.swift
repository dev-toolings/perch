import CommonCrypto
import Foundation

public enum BarkCryptoError: Error, Equatable, LocalizedError {
  case invalidKeyLength(actual: Int)
  case invalidIVLength(actual: Int)
  case encryptionFailed(status: Int32)

  public var errorDescription: String? {
    switch self {
    case .invalidKeyLength(let actual):
      return "Bark AES-256 key must be exactly 32 UTF-8 bytes; received \(actual)."
    case .invalidIVLength(let actual):
      return "Bark CBC IV must be exactly 16 UTF-8 bytes; received \(actual)."
    case .encryptionFailed(let status):
      return "Bark AES-256-CBC encryption failed with CommonCrypto status \(status)."
    }
  }
}

/// Bark decrypts the `ciphertext` field with the algorithm configured on the phone.
/// Vibe's setup flow fixes that contract to AES-256-CBC with PKCS#7 padding and copies
/// the same 32-byte key and 16-byte IV to Bark.
public enum BarkCrypto {
  public static func encrypt(_ plaintext: Data, key: String, iv: String) throws -> String {
    let keyBytes = Array(key.utf8)
    let ivBytes = Array(iv.utf8)
    guard keyBytes.count == kCCKeySizeAES256 else {
      throw BarkCryptoError.invalidKeyLength(actual: keyBytes.count)
    }
    guard ivBytes.count == kCCBlockSizeAES128 else {
      throw BarkCryptoError.invalidIVLength(actual: ivBytes.count)
    }

    let encryptedCapacity = plaintext.count + kCCBlockSizeAES128
    var encrypted = Data(count: encryptedCapacity)
    var encryptedCount = 0
    let status = encrypted.withUnsafeMutableBytes { encryptedBuffer in
      plaintext.withUnsafeBytes { plaintextBuffer in
        keyBytes.withUnsafeBytes { keyBuffer in
          ivBytes.withUnsafeBytes { ivBuffer in
            CCCrypt(
              CCOperation(kCCEncrypt),
              CCAlgorithm(kCCAlgorithmAES),
              CCOptions(kCCOptionPKCS7Padding),
              keyBuffer.baseAddress,
              keyBytes.count,
              ivBuffer.baseAddress,
              plaintextBuffer.baseAddress,
              plaintext.count,
              encryptedBuffer.baseAddress,
              encryptedCapacity,
              &encryptedCount)
          }
        }
      }
    }
    guard status == kCCSuccess else {
      throw BarkCryptoError.encryptionFailed(status: status)
    }
    encrypted.removeSubrange(encryptedCount..<encrypted.count)
    return encrypted.base64EncodedString()
  }
}
