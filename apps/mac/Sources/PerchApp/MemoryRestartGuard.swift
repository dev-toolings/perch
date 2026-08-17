import AppKit
import Darwin
import Foundation
import PerchKit

/// Relaunches Perch only after a sustained, genuinely abnormal memory footprint and only
/// while no agent can be interrupted. The Labs switch is deliberately off by default.
@MainActor
final class MemoryRestartGuard {
    private let thresholdBytes: UInt64
    private let sustainedFor: TimeInterval
    private var highSince: Date?
    private var timer: Timer?

    init(thresholdBytes: UInt64 = 1_000_000_000, sustainedFor: TimeInterval = 5 * 60) {
        self.thresholdBytes = thresholdBytes
        self.sustainedFor = sustainedFor
    }

    func start(
        isEnabled: @escaping @MainActor @Sendable () -> Bool,
        isIdle: @escaping @MainActor @Sendable () -> Bool
    ) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sample(isEnabled: isEnabled, isIdle: isIdle)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        highSince = nil
    }

    private func sample(isEnabled: () -> Bool, isIdle: () -> Bool, now: Date = .now) {
        guard isEnabled(), Self.physicalFootprint() >= thresholdBytes else {
            highSince = nil
            return
        }
        if highSince == nil { highSince = now }
        guard let highSince, now.timeIntervalSince(highSince) >= sustainedFor, isIdle() else {
            return
        }

        stop()
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL, configuration: configuration
        ) { _, error in
            guard error == nil else {
                PerchLog.error("memory safety relaunch failed: \(error!.localizedDescription)")
                return
            }
            Task { @MainActor in NSApplication.shared.terminate(nil) }
        }
    }

    private static func physicalFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
