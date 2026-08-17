import Foundation
import PerchKit
import Testing

@Suite("Bark requests")
struct BarkRequestTests {
  @Test("generated Bark credentials match the phone's field lengths")
  func generatedCredentials() throws {
    let credentials = try BarkCredentials.generated(deviceKey: "device")
    #expect(credentials.encryptionKey?.utf8.count == 32)
    #expect(credentials.encryptionIV?.utf8.count == 16)
    #expect(credentials.isComplete)
  }

  @Test("a device key is a complete plain Bark destination")
  func plainCredentialsAreComplete() {
    #expect(BarkCredentials(deviceKey: "device").isComplete)
  }

  @Test("partial encryption material is never complete")
  func partialEncryptionIsIncomplete() {
    #expect(
      !BarkCredentials(deviceKey: "device", encryptionKey: "key").isComplete)
  }

  @Test("plain Bark requests use API v2")
  func plainRequest() throws {
    let request = try BarkRequest.make(
      server: "https://api.day.app/",
      credentials: BarkCredentials(deviceKey: "device"),
      title: "Perch",
      body: "Needs approval")

    #expect(request.url?.absoluteString == "https://api.day.app/push")
    #expect(request.httpMethod == "POST")
    let body = try #require(request.httpBody)
    let payload = try #require(
      JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(payload["device_key"] as? String == "device")
    #expect(payload["title"] as? String == "Perch")
    #expect(payload["body"] as? String == "Needs approval")
    #expect(payload["ciphertext"] == nil)
  }

  @Test("encrypted Bark requests expose no conversation text")
  func encryptedRequest() throws {
    let request = try BarkRequest.make(
      server: "https://api.day.app",
      credentials: BarkCredentials(
        deviceKey: "device",
        encryptionKey: "0123456789abcdef0123456789abcdef",
        encryptionIV: "0123456789abcdef"),
      title: "Secret project",
      body: "Secret question")

    let body = try #require(request.httpBody)
    let payload = try #require(
      JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(payload["body"] as? String == "Encrypted notification")
    #expect(payload["title"] == nil)
    #expect((payload["ciphertext"] as? String)?.isEmpty == false)
    #expect(!String(decoding: body, as: UTF8.self).contains("Secret"))
  }

  @Test("partial encryption configuration is rejected")
  func rejectsPartialEncryption() {
    #expect(throws: BarkRequestError.incompleteEncryptionCredentials) {
      try BarkRequest.make(
        server: "https://api.day.app",
        credentials: BarkCredentials(deviceKey: "device", encryptionKey: "key"),
        title: "Perch",
        body: "Question")
    }
  }
}
