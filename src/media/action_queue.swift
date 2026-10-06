import Foundation

enum MediaAction: Equatable {
    case command(UInt32)
    case seek(Double)
}

final class MediaActionQueue {
    private let lock = NSLock()
    private let worker: DispatchQueue
    private let execute: (MediaAction) -> Void
    private var actions = [MediaAction?](repeating: nil, count: 32)
    private var tail = 0
    private var count = 0
    private var scheduled = false

    init(worker: DispatchQueue = DispatchQueue(label: "wallify.media.commands", qos: .userInitiated),
         execute: @escaping (MediaAction) -> Void) {
        self.worker = worker
        self.execute = execute
    }

    @discardableResult func enqueue(_ action: MediaAction) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // A scrub gesture can produce targets faster than AppleScript or IPC can
        // execute them. Replace only the last waiting seek, never an earlier one
        // across a command: seek(10), pause, seek(20) must keep that exact order.
        // The worker removes its current action before executing, so this also
        // cannot rewrite a seek already in flight. The fixed ring bounds memory
        // when a backend stalls; enqueue reports false when there is no room.
        if case .seek = action, count > 0 {
            let last = (tail + count - 1) % actions.count
            if case .seek? = actions[last] {
                actions[last] = action
                return true
            }
        }
        guard count < actions.count else { return false }
        actions[(tail + count) % actions.count] = action
        count += 1
        if !scheduled {
            scheduled = true
            worker.async { self.drain() }
        }
        return true
    }

    private func drain() {
        while true {
            lock.lock()
            guard count > 0 else {
                scheduled = false
                lock.unlock()
                return
            }
            let action = actions[tail]!
            actions[tail] = nil
            tail = (tail + 1) % actions.count
            count -= 1
            lock.unlock()
            autoreleasepool { execute(action) }
        }
    }
}

private let mediaActions = MediaActionQueue {
    switch $0 {
    case .command(let command): wallify_execute_media_command(command)
    case .seek(let target): wallify_execute_media_seek(target)
    }
}

@_cdecl("wallify_enqueue_media_command")
public func enqueueMediaCommand(_ command: UInt32) {
    guard command <= 5 else { return }
    mediaActions.enqueue(.command(command))
}

@_cdecl("wallify_enqueue_media_seek")
public func enqueueMediaSeek(_ target: Double) {
    guard target.isFinite else { return }
    mediaActions.enqueue(.seek(max(0, target)))
}
