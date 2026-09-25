import Foundation
import IOKit.pwr_mgt

public struct SleepAssertionState: Sendable, Equatable, Identifiable {
    public enum Effect: Sendable, Equatable {
        case preventsSystemSleep
        case preventsDisplaySleep
    }

    public var pid: Int32
    public var processName: String
    public var effect: Effect
    /// The reason string the process supplied (e.g. "Music is playing").
    public var reason: String
    public var id: String { "\(pid)|\(effect)|\(reason)" }
}

enum SleepAssertions {
    private static let systemSleepTypes: Set<String> = [
        "PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion",
    ]
    private static let displaySleepTypes: Set<String> = [
        "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion",
    ]

    /// Current assertions that keep the system or display awake, excluding powerd's own
    /// bookkeeping assertions (e.g. "Prevent sleep while display is on").
    static func read() -> [SleepAssertionState] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let dict = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        var result: [SleepAssertionState] = []
        for (pidNumber, assertions) in dict {
            let pid = pidNumber.int32Value
            for assertion in assertions {
                guard let type = assertion[kIOPMAssertionTypeKey] as? String else { continue }
                let effect: SleepAssertionState.Effect
                if systemSleepTypes.contains(type) { effect = .preventsSystemSleep }
                else if displaySleepTypes.contains(type) { effect = .preventsDisplaySleep }
                else { continue }
                let processName = (assertion["Process Name"] as? String)
                    ?? Probes.basicInfo(pid)?.name ?? "pid \(pid)"
                if processName == "powerd" { continue }
                let reason = assertion[kIOPMAssertionNameKey] as? String ?? type
                result.append(SleepAssertionState(pid: pid, processName: processName, effect: effect, reason: reason))
            }
        }
        return result.sorted { ($0.processName, $0.reason) < ($1.processName, $1.reason) }
    }
}
