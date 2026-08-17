import Foundation
import PerchKit

/// Activity-triggered remote Codex quota read through the same owned SSH/app-server
/// transport as trust verification. It never reads credentials or starts a Codex turn.
enum RemoteCodexUsageProbe {
  struct Result: Sendable, Equatable {
    var limits: RateLimits?
    var error: String?
  }

  static func read(host: RemoteHost, timeout: TimeInterval = 8) async -> Result {
    let roots = [RemoteCodexConfigRoot.defaultHome.path] + host.additionalCodexConfigRoots
    return await Task.detached {
      var windows: [NamedWindow] = []
      var failures: [String] = []
      for root in roots {
        switch probe(
          alias: host.name, root: root,
          rootLabel: roots.count > 1 ? root : nil, timeout: timeout)
        {
        case .success(let limits): windows.append(contentsOf: limits.windows)
        case .failure(let error): failures.append("\(root): \(error.localizedDescription)")
        }
      }
      return Result(
        limits: windows.isEmpty ? nil : RateLimits(modelScoped: windows),
        error: failures.isEmpty ? nil : failures.joined(separator: "\n"))
    }.value
  }

  private static func probe(
    alias: String, root: String, rootLabel: String?, timeout: TimeInterval
  ) -> Swift.Result<RateLimits, ProbeError> {
    guard let script = RepoScripts.url(of: "remote.sh") else {
      return .failure(.missingHelper)
    }

    let process = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    let capture = UsageResponseCapture(responseID: 2)
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
    let read = RPCRequest(id: 2, method: "account/rateLimits/read", params: .object([:]))
    do {
      let encoder = JSONEncoder()
      var bytes = try encoder.encode(initialize)
      bytes.append(0x0A)
      bytes.append(try encoder.encode(read))
      bytes.append(0x0A)
      try stdin.fileHandleForWriting.write(contentsOf: bytes)
    } catch {
      stop(process, stdin: stdin, stdout: stdout)
      return .failure(.request(error.localizedDescription))
    }

    guard capture.wait(timeout: timeout), let data = capture.capturedResponse() else {
      stop(process, stdin: stdin, stdout: stdout)
      return .failure(.timedOut)
    }
    stop(process, stdin: stdin, stdout: stdout)

    do {
      let envelope = try JSONDecoder().decode(RPCResponse.self, from: data)
      if let error = envelope.error { return .failure(.server(error.message)) }
      guard let response = envelope.result,
        let limits = RemoteCodexRateLimitsEvaluator.evaluate(response, rootLabel: rootLabel)
      else { return .failure(.malformedResponse) }
      return .success(limits)
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
    var result: RemoteCodexRateLimitsResponse?
    var error: ErrorBody?
  }

  private enum ProbeError: LocalizedError {
    case missingHelper, timedOut, malformedResponse
    case launch(String), request(String), server(String), decode(String)

    var errorDescription: String? {
      switch self {
      case .missingHelper: return "Remote helper is missing"
      case .launch(let detail): return "Could not launch SSH: \(detail)"
      case .request(let detail): return "Could not send the usage probe: \(detail)"
      case .timedOut: return "Codex usage probe timed out"
      case .server(let detail): return detail
      case .malformedResponse: return "Codex returned no account/rateLimits/read result"
      case .decode(let detail): return "Could not decode account/rateLimits/read: \(detail)"
      }
    }
  }
}

private final class UsageResponseCapture: @unchecked Sendable {
  private let lock = NSLock()
  private let signal = DispatchSemaphore(value: 0)
  private let responseID: Int
  private var buffer = Data()
  private var response: Data?
  private var didSignal = false

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

  func capturedResponse() -> Data? {
    lock.lock()
    defer { lock.unlock() }
    return response
  }
}
