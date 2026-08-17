import Foundation
import PerchKit
import Testing

@Suite("Bark encryption")
struct BarkCryptoTests {
  @Test("AES-256-CBC output matches an OpenSSL vector")
  func matchesOpenSSL() throws {
    let plaintext = Data(#"{"title":"Perch","body":"Needs approval"}"#.utf8)

    let ciphertext = try BarkCrypto.encrypt(
      plaintext,
      key: "0123456789abcdef0123456789abcdef",
      iv: "0123456789abcdef")

    #expect(ciphertext == "nRiTB3KTyrzc5DpJPrcB2R4ZWctQJEkPCVGjnH3WHq5IQhr2Ud8z00f3rm7hmv4r")
  }

  @Test("Bark rejects keys that are not 32 UTF-8 bytes")
  func rejectsInvalidKey() {
    #expect(throws: BarkCryptoError.invalidKeyLength(actual: 5)) {
      try BarkCrypto.encrypt(Data("hello".utf8), key: "short", iv: "0123456789abcdef")
    }
  }

  @Test("Bark rejects IVs that are not 16 UTF-8 bytes")
  func rejectsInvalidIV() {
    #expect(throws: BarkCryptoError.invalidIVLength(actual: 5)) {
      try BarkCrypto.encrypt(
        Data("hello".utf8),
        key: "0123456789abcdef0123456789abcdef",
        iv: "short")
    }
  }
}
