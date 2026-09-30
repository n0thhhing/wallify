import AppKit
import ApplicationServices

// Only playback keys belong to Wallify; volume/brightness releases pass through.
func mediaKeyAction(data: Int) -> (key: Int32, pressed: Bool)? {
    let key = Int32((data >> 16) & 0xFFFF)
    guard key == 16 || key == 19 || key == 20 else { return nil }
    return (key, ((data >> 8) & 0xFF) == 0x0A)
}

// The tap and its callback run exclusively on the main run loop.
private final class MediaKeyTap {
    static let shared = MediaKeyTap()
    var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func update(target: Int32) {
        NSLog("Wallify: media key target -> %d", target)
        if target == 0 {
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            source = nil
            tap = nil
            return
        }
        guard tap == nil else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            NSLog("Wallify: Accessibility permission required for media key interception.")
            return
        }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                            options: .defaultTap,
                                            eventsOfInterest: CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue,
                                            callback: mediaKeyCallback, userInfo: nil),
              let newSource = CFMachPortCreateRunLoopSource(nil, newTap, 0) else {
            NSLog("Wallify: Failed to create CGEventTap (check Accessibility permission).")
            return
        }
        tap = newTap
        source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        NSLog("Wallify: Media key tap installed (target=%d).", target)
    }
}

private func mediaKeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = MediaKeyTap.shared.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard let nativeEvent = NSEvent(cgEvent: event), nativeEvent.type == .systemDefined,
          nativeEvent.subtype.rawValue == 8, let action = mediaKeyAction(data: nativeEvent.data1) else {
        return Unmanaged.passUnretained(event)
    }
    if action.pressed { wallify_media_key_event(action.key) }
    return nil // Consume both press and release for playback keys.
}

@_cdecl("wallify_update_media_key_tap")
public func updateMediaKeyTap(_ target: Int32) {
    DispatchQueue.main.async { MediaKeyTap.shared.update(target: target) }
}
