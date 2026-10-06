import AppKit
import QuartzCore

@_cdecl("wallify_calculate_panel_snap")
public func calculatePanelSnap(_ candidates: UnsafePointer<WallifyWindowRect>?, _ count: UInt,
                               _ visualX: Double, _ visualY: Double, _ width: Double, _ height: Double,
                               _ offsetX: Double, _ offsetY: Double, _ insetX: Double, _ insetY: Double,
                               _ output: UnsafeMutablePointer<WallifyPanelSnap>?) {
    guard let output = output else { return }
    output.pointee = WallifyPanelSnap()
    guard let candidates = candidates, count <= 64,
          [visualX, visualY, width, height, offsetX, offsetY, insetX, insetY].allSatisfy({ $0.isFinite }),
          width >= 16, height >= 16, width <= 16384, height <= 16384 else { return }
    let pitch = 180.0
    let playerColumns = max(1, Int((width / pitch).rounded()))
    var best = 1100.0 * 1100.0
    func consider(_ x: Double, _ y: Double) {
        let distance = (x - visualX) * (x - visualX) + (y - visualY) * (y - visualY)
        let left = (x - offsetX - insetX).rounded()
        let top = (y - offsetY - insetY).rounded()
        guard distance < best, left >= Double(Int32.min), left <= Double(Int32.max),
              top >= Double(Int32.min), top <= Double(Int32.max) else { return }
        best = distance
        output.pointee = WallifyPanelSnap(found: true, margin_left: Int32(left), margin_top: Int32(top),
            outline_x: x + 8, outline_y: y + 8, outline_width: width - 16, outline_height: height - 16,
            distance_sq: distance)
    }
    for neighbor in UnsafeBufferPointer(start: candidates, count: Int(count)) {
        guard [neighbor.x, neighbor.y, neighbor.width, neighbor.height].allSatisfy({ $0.isFinite }),
              neighbor.width > 0, neighbor.height > 0, neighbor.width <= 16384, neighbor.height <= 16384 else { continue }
        let columns = max(1, Int((neighbor.width / pitch).rounded()))
        let rows = max(1, Int((neighbor.height / pitch).rounded()))
        for column in 0..<columns {
            let cellX = neighbor.x + Double(column) * pitch
            for playerColumn in 0..<playerColumns {
                let left = cellX - Double(playerColumn) * pitch
                consider(left, neighbor.y - height)
                consider(left, neighbor.y + neighbor.height)
            }
        }
        for row in 0..<rows {
            let top = neighbor.y + Double(row) * pitch
            consider(neighbor.x - width, top)
            consider(neighbor.x + neighbor.width, top)
        }
    }
}

func isWallifyWindow(_ info: [String: Any], expectedID: Int) -> Bool {
    let name = info[kCGWindowName as String] as? String
    func matches(_ value: String?, _ expected: String) -> Bool { value?.caseInsensitiveCompare(expected) == .orderedSame }
    if ["Wallify Debug Console", "Wallify Snap Outline", "Wallify Settings"].contains(where: { matches(name, $0) }) { return false }
    if expectedID > 0, let number = info[kCGWindowNumber as String] as? NSNumber { return number.intValue == expectedID }
    let owner = info[kCGWindowOwnerName as String] as? String
    guard matches(name, "Wallify") || matches(owner, "Wallify") else { return false }
    if name != nil && !matches(name, "Wallify") { return false }
    return (info[kCGWindowLayer as String] as? NSNumber)?.intValue == -1
}

func desktopWindowBounds(_ info: [String: Any]) -> CGRect? {
    guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
          let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
          [rect.minX, rect.minY, rect.width, rect.height].allSatisfy({ $0.isFinite }) else { return nil }
    return rect
}

func desktopWidgetCandidate(_ info: [String: Any]) -> CGRect? {
    guard let owner = info[kCGWindowOwnerName as String] as? String,
          ["Notification Center", "NotificationCenter"].contains(where: { owner.caseInsensitiveCompare($0) == .orderedSame }),
          let bounds = desktopWindowBounds(info) else { return nil }
    let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
    let layer = (info[kCGWindowLayer as String] as? NSNumber)?.int64Value ?? 0
    guard alpha >= 0.5, layer < 0, layer != -2147483602, bounds.maxX > 0, bounds.maxY > 0,
          (80...1400).contains(bounds.width), (80...800).contains(bounds.height) else { return nil }
    return bounds
}

private func desktopWindows() -> [[String: Any]] {
    CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
}

@MainActor private func playerWindowInfo() -> WallifyWindowInfo {
    let expectedID = WidgetPanel.current?.windowNumber ?? 0
    for info in desktopWindows() where isWallifyWindow(info, expectedID: expectedID) {
        guard let number = info[kCGWindowNumber as String] as? NSNumber, let frame = desktopWindowBounds(info) else { continue }
        var result = WallifyWindowInfo()
        result.number = number.int64Value
        result.layer = (info[kCGWindowLayer as String] as? NSNumber)?.int64Value ?? 0
        result.frame = WallifyWindowRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
        return result
    }
    return WallifyWindowInfo()
}

@_cdecl("wallify_query_player_window")
@MainActor public func queryPlayerWindow(_ output: UnsafeMutablePointer<WallifyWindowInfo>?) { output?.pointee = playerWindowInfo() }

@_cdecl("wallify_desktop_candidates")
public func copyDesktopCandidates(_ output: UnsafeMutablePointer<WallifyWindowRect>?, _ capacity: UInt) -> UInt {
    guard let output = output, capacity > 0 else { return 0 }
    var count: UInt = 0
    for info in desktopWindows() {
        guard let bounds = desktopWidgetCandidate(info) else { continue }
        output[Int(count)] = WallifyWindowRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
        count += 1
        if count == capacity { break }
    }
    return count
}

func snapPreviewFrame(_ rect: NSRect, screenHeight: CGFloat) -> NSRect {
    NSRect(x: rect.minX, y: screenHeight - rect.minY - rect.height, width: rect.width, height: rect.height)
}

@MainActor final class SnapPreview {
    static let shared = SnapPreview()
    private(set) var panel: NSPanel?
    private var wasVisible = false
    private var radius: CGFloat = 0

    func needsUpdate(rect: NSRect, radius: CGFloat, screenHeight: CGFloat) -> Bool {
        !wasVisible || panel?.frame != snapPreviewFrame(rect, screenHeight: screenHeight) || self.radius != radius
    }

    func show(rect: NSRect, radius: CGFloat, screenHeight: CGFloat, playerLayer: Int?) {
        let frame = snapPreviewFrame(rect, screenHeight: screenHeight)
        let level = playerLayer.map { $0 - 1 } ?? -2
        guard needsUpdate(rect: rect, radius: radius, screenHeight: screenHeight) || panel?.level.rawValue != level else { return }
        self.radius = radius
        if panel == nil {
            let panel = NSPanel(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            panel.title = "Wallify Snap Outline"
            panel.isOpaque = false; panel.backgroundColor = .clear
            panel.alphaValue = 1; panel.ignoresMouseEvents = true; panel.hasShadow = false
            panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
            view.wantsLayer = true; view.autoresizingMask = [.width, .height]
            view.layer?.masksToBounds = true; view.layer?.cornerRadius = radius; view.layer?.borderWidth = 2.5
            view.layer?.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
            view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            panel.contentView = view
            self.panel = panel
        }
        let panel = panel!
        panel.setFrame(frame, display: true)
        panel.level = NSWindow.Level(rawValue: level)
        panel.contentView?.layer?.cornerRadius = radius
        panel.orderFrontRegardless()
        if !wasVisible {
            NSLog("Wallify window: show snap preview id=%d frame=%@", panel.windowNumber, NSStringFromRect(frame))
            panel.alphaValue = 0
            panel.animator().alphaValue = 1
            wasVisible = true
        }
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView?.layer?.frame = NSRect(origin: .zero, size: frame.size)
    }

    func hide() {
        guard wasVisible else { return }
        panel?.orderOut(nil); wasVisible = false
    }
}

@_cdecl("wallify_show_snap_preview")
public func showSnapPreview(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ radius: Double) {
    guard [x, y, width, height, radius].allSatisfy({ $0.isFinite }), width > 0, height > 0, radius >= 0 else { return }
    let rect = NSRect(x: x, y: y, width: width, height: height)
    DispatchQueue.main.async {
        guard let screen = NSScreen.screens.first else { return }
        guard SnapPreview.shared.needsUpdate(rect: rect, radius: radius, screenHeight: screen.frame.maxY) else { return }
        let player = playerWindowInfo()
        SnapPreview.shared.show(rect: rect, radius: radius, screenHeight: screen.frame.maxY,
                                playerLayer: player.number > 0 ? Int(player.layer) : nil)
        widget_debug_window_show()
    }
}

@_cdecl("wallify_hide_snap_preview")
public func hideSnapPreview() { DispatchQueue.main.async { SnapPreview.shared.hide() } }
