import Foundation
import PerchKit

/// Read-only remote trust verification through Codex's own `hooks/list` API.
///
/// One SSH process is launched per configured Codex home. The process is the exact child
/// Perch owns and is terminated after the response or timeout; no config file is read or
/// written by Perch during verification.
enum RemoteCodexHookTrustService {
  struct Result: Sendable, Equatable {
    var snapshot: RemoteCodexHookTrustSnapshot
    var error: String?
  }

  static func verify(host: RemoteHost, timeout: TimeInterval = 8) async -> Result {
    let roots = [RemoteCodexConfigRoot.defaultHome.path] + host.additionalCodexConfigRoots
    return await Task.detached {
      var states: [RemoteCodexHookTrustState] = []
      var failures: [String] = []
      for root in roots {
        switch probe(alias: host.name, root: root, timeout: timeout) {
        case .success(let state): states.append(state)
        case .failure(let error):
          states.append(.unverified)
          failures.append("\(root): \(error.localizedDescription)")
        }
      }

      let state: RemoteCodexHookTrustState
      if states.contains(.unverified) {
        state = .unverified
      } else if states.contains(.needsManualTrust) {
        state = .needsManualTrust
      } else {
        state = .trusted
      }
      return Result(
        snapshot: .init(state: state, lastCheckedAt: .now),
        error: failures.isEmpty ? nil : failures.joined(separator: "\n"))
    }.value
  }

  private static func probe(
    alias: String, root: String, timeout: TimeInterval
  ) -> Swift.Result<RemoteCodexHookTrustState, ProbeError> {
    guard let script = RepoScripts.url(of: "remote.sh") else {
      return .failure(.missingHelper)
    }

    let process = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    let capture = ResponseCapture(responseID: 2)
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [
      script.path, "codex-app-server", alias, Data(root.utf8).base64EncodedString(),
    ]
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr
    stdout.fileHandleForReading.readabilityHandler = { handle in
      capture.append(handle.availableData)
    }

    do {
      try process.run()
    } catch {
      stdout.fileHandleForReading.readabilityHandler = nil
      return .failure(.launch(error.localizedDescription))
    }

    let initialize = RPCRequest(
      id: 1, method: "initialize",
      params: .object([
        "clientInfo": .object(["name": .string("perch"), "version": .string("1")]),
        "capabilities": .object(["experimentalApi": .bool(true)]),
      ]))
    let list = RPCRequest(
      id: 2, method: "hooks/list", params: .object(["cwds": .array([])]))
    do {
      let encoder = JSONEncoder()
      var bytes = try encoder.encode(initialize)
      bytes.append(0x0A)
      bytes.append(try encoder.encode(list))
      bytes.append(0x0A)
      try stdin.fileHandleForWriting.write(contentsOf: bytes)
    } catch {
      stop(process, stdin: stdin, stdout: stdout)
      return .failure(.request(error.localizedDescription))
    }

    guard capture.wait(timeout: timeout), let data = capture.response else {
      stop(process, stdin: stdin, stdout: stdout)
      return .failure(.timedOut)
    }
    stop(process, stdin: stdin, stdout: stdout)

    do {
      let envelope = try JSONDecoder().decode(RPCResponse.self, from: data)
      if let error = envelope.error { return .failure(.server(error.message)) }
      guard let response = envelope.result else { return .failure(.malformedResponse) }
      return .success(RemoteCodexHookTrustEvaluator.evaluate(response))
    } catch {
      return .failure(.decode(error.localizedDescription))
    }
  }

  private static func stop(_ process: Process, stdin: Pipe, stdout: Pipe) {
    stdout.fileHandleForReading.readabilityHandler = nil
    try? stdin.fileHandleForWriting.close()
    if process.isRunning { process.terminate() }
  }

  private struct RPCRequest: Encodable {
    var id: Int
    var method: String
    var params: JSONValue
  }

  private struct RPCResponse: Decodable {
    struct ErrorBody: Decodable { var message: String }
    var id: Int
    var result: RemoteCodexHooksListResponse?
    var error: ErrorBody?
  }

  private enum ProbeError: LocalizedError {
    case missingHelper
    case launch(String)
    case request(String)
    case timedOut
    case server(String)
    case malformedResponse
    case decode(String)

    var errorDescription: String? {
      switch self {
      case .missingHelper: return "Remote helper is missing"
      case .launch(let detail): return "Could not launch SSH: \(detail)"
      case .request(let detail): return "Could not send the trust probe: \(detail)"
      case .timedOut: return "Codex hook trust probe timed out"
      case .server(let detail): return detail
      case .malformedResponse: return "Codex returned no hooks/list result"
      case .decode(let detail): return "Could not decode hooks/list: \(detail)"
      }
    }
  }
}

private final class ResponseCapture: @unchecked Sendable {
  private let lock = NSLock()
  private let signal = DispatchSemaphore(value: 0)
  private let responseID: Int
  private var buffer = Data()
  private var didSignal = false
  private(set) var response: Data?

  init(responseID: Int) { self.responseID = responseID }

  func append(_ data: Data) {
    guard !data.isEmpty else { return }
    lock.lock()
    defer { lock.unlock() }
    buffer.append(data)
    while let newline = buffer.firstIndex(of: 0x0A) {
      let line = Data(buffer[..<newline])
      buffer.removeSubrange(...newline)
      guard
        let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
        (object["id"] as? NSNumber)?.intValue == responseID
      else { continue }
      response = line
      if !didSignal {
        didSignal = true
        signal.signal()
      }
    }
  }

  func wait(timeout: TimeInterval) -> Bool {
    signal.wait(timeout: .now() + timeout) == .success
  }
}
