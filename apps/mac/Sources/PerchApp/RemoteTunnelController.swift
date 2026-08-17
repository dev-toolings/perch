import Foundation
import Observation
import PerchKit

enum RemoteTunnelStatus: Sendable, Equatable {
  case disconnected
  case connecting
  case connected
  case failed(String)

  var title: String {
    switch self {
    case .disconnected: return t("Disconnected")
    case .connecting: return t("Connecting…")
    case .connected: return t("Connected")
    case .failed(let message): return message
    }
  }
}

/// Owns only SSH processes Perch started itself. Each host has at most one reverse tunnel;
/// stopping a tunnel terminates that exact `Process` rather than searching for arbitrary
/// `ssh` processes on the machine.
@MainActor
@Observable
final class RemoteTunnelController {
  private(set) var statuses: [UUID: RemoteTunnelStatus] = [:]
  @ObservationIgnored private var processes: [UUID: Process] = [:]

  func status(for host: RemoteHost) -> RemoteTunnelStatus {
    statuses[host.id] ?? .disconnected
  }

  func connect(_ host: RemoteHost, port: UInt16) {
    guard processes[host.id] == nil else { return }
    guard let script = RepoScripts.url(of: "remote.sh") else {
      statuses[host.id] = .failed(t("Remote helper is missing"))
      return
    }

    let process = Process()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path, "connect", host.name]
    process.environment = ProcessInfo.processInfo.environment.merging(
      ["PERCH_REMOTE_PORT": String(port)]) { _, new in new }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = stderr
    process.terminationHandler = { [weak self] process in
      let data = stderr.fileHandleForReading.readDataToEndOfFile()
      let detail = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      Task { @MainActor [weak self] in
        self?.processes[host.id] = nil
        guard process.terminationReason != .uncaughtSignal else {
          self?.statuses[host.id] = .disconnected
          return
        }
        let failure = detail?.isEmpty == false ? detail : nil
        self?.statuses[host.id] =
          process.terminationStatus == 0
          ? .disconnected
          : .failed(failure ?? t("SSH tunnel exited"))
      }
    }

    do {
      try process.run()
      processes[host.id] = process
      statuses[host.id] = .connecting
      Task { @MainActor [weak self, weak process] in
        try? await Task.sleep(for: .seconds(1))
        guard let self, let process, self.processes[host.id] === process,
          process.isRunning
        else { return }
        self.statuses[host.id] = .connected
      }
    } catch {
      statuses[host.id] = .failed(error.localizedDescription)
    }
  }

  func disconnect(_ host: RemoteHost) {
    guard let process = processes[host.id] else {
      statuses[host.id] = .disconnected
      return
    }
    process.terminate()
  }

  func reportFailure(_ message: String, for host: RemoteHost) {
    guard processes[host.id] == nil else { return }
    statuses[host.id] = .failed(message)
  }

  func stopAll() {
    for process in processes.values where process.isRunning { process.terminate() }
    processes.removeAll()
    statuses.removeAll()
  }
}
