import Foundation

// One animation worker consumes requests; repeated producers share one token.
final class FrameWakeups {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var pending = false

    func wake() {
        lock.lock()
        defer { lock.unlock() }
        // A doorbell, not a to-do list: ten producers still owe the worker only one wakeup.
        if !pending {
            pending = true
            semaphore.signal()
        }
    }

    @discardableResult func wait(until deadline: DispatchTime = .distantFuture) -> Bool {
        guard semaphore.wait(timeout: deadline) == .success else { return false }
        lock.lock()
        pending = false
        lock.unlock()
        return true
    }
}

private let frameWakeups = FrameWakeups()

@_cdecl("wallify_frame_wakeup_init")
public func initializeFrameWakeups() { _ = frameWakeups }

@_cdecl("wallify_frame_wake")
public func wakeFrame() { frameWakeups.wake() }

@_cdecl("wallify_frame_wait")
public func waitForFrame() { frameWakeups.wait() }

@_cdecl("wallify_frame_wait_for")
public func waitForFrameInterval(_ nanoseconds: UInt64) {
    let (deadline, overflow) = DispatchTime.now().uptimeNanoseconds.addingReportingOverflow(nanoseconds)
    frameWakeups.wait(until: overflow ? .distantFuture : DispatchTime(uptimeNanoseconds: deadline))
}
