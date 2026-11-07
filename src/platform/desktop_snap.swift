import AppKit
import QuartzCore

let snapCaptureDistance = 12.0
let snapReleaseDistance = 16.0
let adjacentSnapCaptureDistance = 90.0
let adjacentSnapReleaseDistance = 90.0

@_cdecl("wallify_calculate_panel_snap")
public func calculatePanelSnap(_ candidates: UnsafePointer<WallifyWindowRect>?, _ count: UInt,
                               _ visualX: Double, _ visualY: Double, _ width: Double, _ height: Double,
                               _ offsetX: Double, _ offsetY: Double, _ insetX: Double, _ insetY: Double,
                               _ output: UnsafeMutablePointer<WallifyPanelSnap>?) {
    guard let output else { return }
    output.pointee = WallifyPanelSnap()
    guard let candidates, count <= 64 else { return }
    output.pointee = panelSnap(Array(UnsafeBufferPointer(start: candidates, count: Int(count))),
        visualX: visualX, visualY: visualY, width: width, height: height,
        offsetX: offsetX, offsetY: offsetY, insetX: insetX, insetY: insetY)
}

func nativeWidgetCard(_ rect: WallifyWindowRect) -> CGRect {
    // WindowServer's 180pt grid footprints include 8pt padding; non-grid bounds are already visible bounds.
    // Revisit this normalization if a future macOS release changes widget window geometry.
    let padded = abs(rect.width.truncatingRemainder(dividingBy: 180)) < 1 &&
        abs(rect.height.truncatingRemainder(dividingBy: 180)) < 1
    return CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height).insetBy(dx: padded ? 8 : 0, dy: padded ? 8 : 0)
}

func panelSnap(_ candidates: [WallifyWindowRect], visualX: Double, visualY: Double,
               width: Double, height: Double, offsetX: Double, offsetY: Double,
               insetX: Double, insetY: Double, bounds: CGRect? = nil,
               previous: WallifyPanelSnap = WallifyPanelSnap()) -> WallifyPanelSnap {
    guard candidates.count <= 64,
          [visualX, visualY, width, height, offsetX, offsetY, insetX, insetY].allSatisfy(\.isFinite),
          width >= 16, height >= 16, width <= 16384, height <= 16384,
          insetX >= 0, insetY >= 0, width > 2 * insetX, height > 2 * insetY else { return WallifyPanelSnap() }
    let neighbors = candidates.filter {
        [$0.x, $0.y, $0.width, $0.height].allSatisfy(\.isFinite) &&
            $0.width > 0 && $0.height > 0 && $0.width <= 16384 && $0.height <= 16384
    }
    let cardWidth = width - 2 * insetX, cardHeight = height - 2 * insetY
    func target(_ x: Double, _ y: Double) -> WallifyPanelSnap? {
        let left = (x - offsetX - insetX).rounded(), top = (y - offsetY - insetY).rounded()
        guard left >= Double(Int32.min), left <= Double(Int32.max),
              top >= Double(Int32.min), top <= Double(Int32.max) else { return nil }
        let footprint = CGRect(x: left + offsetX, y: top + offsetY, width: width, height: height)
        if let bounds, !bounds.contains(footprint) { return nil }
        guard !neighbors.contains(where: {
            footprint.minX < $0.x + $0.width && footprint.maxX > $0.x &&
                footprint.minY < $0.y + $0.height && footprint.maxY > $0.y
        }) else { return nil }
        var result = WallifyPanelSnap()
        result.found = true; result.margin_left = Int32(left); result.margin_top = Int32(top)
        result.outline_x = footprint.minX + insetX; result.outline_y = footprint.minY + insetY
        result.outline_width = cardWidth; result.outline_height = cardHeight
        result.distance_sq = pow(x - visualX, 2) + pow(y - visualY, 2)
        return result
    }
    var slot = WallifyPanelSnap(), slotDistance = Double.infinity
    var slotRetained = false
    func considerSlot(_ x: Double, _ y: Double) {
        let retained = previous.found && previous.kind == 1 &&
            abs(x - previous.outline_x) < 1 && abs(y - previous.outline_y) < 1
        let limit = retained ? adjacentSnapReleaseDistance : adjacentSnapCaptureDistance
        guard abs(x - visualX) <= limit, abs(y - visualY) <= limit,
              var result = target(x, y),
              retained && !slotRetained || retained == slotRetained && result.distance_sq < slotDistance else { return }
        result.kind = 1; result.axes = 3; slot = result; slotDistance = result.distance_sq; slotRetained = retained
    }
    for neighbor in neighbors {
        let columns = max(1, Int((neighbor.width / 180).rounded()))
        let rows = max(1, Int((neighbor.height / 180).rounded()))
        for column in 0..<columns {
            for playerColumn in 0..<max(1, Int((width / 180).rounded())) {
                let x = neighbor.x + Double(column - playerColumn) * 180 + insetX
                considerSlot(x, neighbor.y - height + insetY)
                considerSlot(x, neighbor.y + neighbor.height + insetY)
            }
        }
        for row in 0..<rows {
            for playerRow in 0..<max(1, Int((height / 180).rounded())) {
                let y = neighbor.y + Double(row - playerRow) * 180 + insetY
                considerSlot(neighbor.x - width + insetX, y)
                considerSlot(neighbor.x + neighbor.width + insetX, y)
            }
        }
    }
    if slot.found { return slot }
    // At most 128 edge matches per axis (64 widgets). Scan combinations only inside the capture band.
    var xs: [(Double, Double, WallifyWindowRect, Bool, Bool)] = [], ys: [(Double, Double, WallifyWindowRect, Bool, Bool)] = []
    for neighbor in neighbors {
        let card = nativeWidgetCard(neighbor)
        for trailing in [false, true] {
            let x = trailing ? card.maxX - cardWidth : card.minX
            let edgeX = trailing ? card.maxX : card.minX
            let retainedX = previous.found && previous.kind == 2 && previous.axes & 1 != 0 &&
                abs(edgeX - previous.guide_x) < 1
            if abs(x - visualX) <= (retainedX ? snapReleaseDistance : snapCaptureDistance) { xs.append((x, edgeX, neighbor, retainedX, trailing == (bounds.map { card.midX >= $0.midX } ?? false))) }
            let y = trailing ? card.maxY - cardHeight : card.minY
            let edgeY = trailing ? card.maxY : card.minY
            let retainedY = previous.found && previous.kind == 2 && previous.axes & 2 != 0 &&
                abs(edgeY - previous.guide_y) < 1
            if abs(y - visualY) <= (retainedY ? snapReleaseDistance : snapCaptureDistance) { ys.append((y, edgeY, neighbor, retainedY, trailing == (bounds.map { card.midY >= $0.midY } ?? false))) }
        }
    }
    var alignment = WallifyPanelSnap(), bestAxes = 0, bestDistance = Double.infinity
    var bestRetained = 0, bestPreferred = 0
    func considerAlignment(_ x: (Double, Double, WallifyWindowRect, Bool, Bool)?, _ y: (Double, Double, WallifyWindowRect, Bool, Bool)?) {
        guard var result = target(x?.0 ?? visualX, y?.0 ?? visualY) else { return }
        let axes = (x == nil ? 0 : 1) + (y == nil ? 0 : 1)
        let retained = (x?.3 == true ? 1 : 0) + (y?.3 == true ? 1 : 0)
        // Equal-edge ties favor the nearest display boundary, inferred from recordings; verify with mixed native sizes.
        let preferred = (x?.4 == true ? 1 : 0) + (y?.4 == true ? 1 : 0)
        guard axes > bestAxes || (axes == bestAxes && (retained > bestRetained ||
            retained == bestRetained && (result.distance_sq < bestDistance ||
                result.distance_sq == bestDistance && preferred > bestPreferred))) else { return }
        result.kind = 2
        if let x { result.axes |= 1; result.guide_x = x.1; result.vertical_neighbor = x.2 }
        if let y { result.axes |= 2; result.guide_y = y.1; result.horizontal_neighbor = y.2 }
        alignment = result; bestAxes = axes; bestDistance = result.distance_sq; bestRetained = retained; bestPreferred = preferred
    }
    for x in xs { for y in ys { considerAlignment(x, y) }; considerAlignment(x, nil) }
    for y in ys { considerAlignment(nil, y) }
    return alignment
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

// Notification Center widgets belong to another process, so NSApp.windows cannot supply snap candidates.
private func desktopWindows() -> [[String: Any]] {
    CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
}

@MainActor private func playerWindowInfo() -> WallifyWindowInfo {
    guard let panel = WidgetPanel.current, let primary = NSScreen.screens.first else { return WallifyWindowInfo() }
    let frame = panel.frame
    var result = WallifyWindowInfo()
    result.number = Int64(panel.windowNumber)
    result.layer = Int64(panel.level.rawValue)
    result.frame = WallifyWindowRect(x: frame.minX, y: primary.frame.maxY - frame.maxY,
                                     width: frame.width, height: frame.height)
    return result
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

struct SnapFeedback: Equatable {
    var outline: CGRect?
    var guides: [CGRect] = []

    init(outline: CGRect?) { self.outline = outline }
    init(_ snap: WallifyPanelSnap) {
        let card = CGRect(x: snap.outline_x, y: snap.outline_y, width: snap.outline_width, height: snap.outline_height)
        outline = snap.kind == 2 && snap.axes != 3 ? nil : card
        if snap.axes & 1 != 0 && snap.kind == 2 {
            for rect in (outline == nil ? [card] : []) + [nativeWidgetCard(snap.vertical_neighbor)] {
                guides.append(CGRect(x: snap.guide_x + (abs(snap.guide_x - card.maxX) < 1 ? 4 : -4) - 1, y: rect.minY - 16, width: 2, height: rect.height + 32))
            }
        }
        if snap.axes & 2 != 0 && snap.kind == 2 {
            for rect in (outline == nil ? [card] : []) + [nativeWidgetCard(snap.horizontal_neighbor)] {
                guides.append(CGRect(x: rect.minX - 16, y: snap.guide_y + (abs(snap.guide_y - card.maxY) < 1 ? 4 : -4) - 1, width: rect.width + 32, height: 2))
            }
        }
    }
    var bounds: CGRect? {
        let rects = guides + (outline.map { [$0] } ?? [])
        return rects.reduce(nil) { result, rect in result.map { $0.union(rect) } ?? rect }
    }
}

@MainActor final class SnapPreview {
    static let shared = SnapPreview()
    private(set) var panel: NSPanel?
    private var feedback: SnapFeedback?
    private var radius: CGFloat = 0

    func needsUpdate(rect: NSRect, radius: CGFloat, screenHeight: CGFloat) -> Bool {
        feedback != SnapFeedback(outline: rect) || self.radius != radius ||
            panel?.frame != snapPreviewFrame(rect, screenHeight: screenHeight)
    }

    func show(rect: NSRect, radius: CGFloat, screenHeight: CGFloat, playerLayer: Int?) {
        show(SnapFeedback(outline: rect), radius: radius, screenHeight: screenHeight, playerLayer: playerLayer)
    }

    func show(_ next: SnapFeedback, radius: CGFloat = 26, screenHeight: CGFloat, playerLayer: Int?) {
        guard let bounds = next.bounds, !bounds.isEmpty else { hide(); return }
        let frame = snapPreviewFrame(bounds, screenHeight: screenHeight)
        let level = playerLayer.map { $0 - 1 } ?? -2
        guard feedback != next || self.radius != radius || panel?.frame != frame || panel?.level.rawValue != level else { return }
        if panel == nil {
            let panel = NSPanel(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            panel.title = "Wallify Snap Preview"
            panel.isOpaque = false; panel.backgroundColor = .clear
            panel.ignoresMouseEvents = true; panel.hasShadow = false
            panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
            view.wantsLayer = true; view.autoresizingMask = [.width, .height]
            panel.contentView = view
            self.panel = panel
        }
        let panel = panel!, wasVisible = feedback != nil
        CATransaction.begin(); CATransaction.setDisableActions(true)
        panel.setFrame(frame, display: true); panel.level = NSWindow.Level(rawValue: level)
        // AppKit rounds window origins; keep strokes anchored to global coordinates after that rounding.
        let drawingBounds = snapPreviewFrame(panel.frame, screenHeight: screenHeight)
        let root = panel.contentView!.layer!
        root.sublayers = nil; root.borderWidth = 0; root.cornerRadius = 0
        root.frame = CGRect(origin: .zero, size: panel.frame.size)
        if let outline = next.outline {
            let border = next.guides.isEmpty ? root : CALayer()
            border.frame = CGRect(x: outline.minX - drawingBounds.minX, y: drawingBounds.maxY - outline.maxY,
                width: outline.width, height: outline.height)
            border.cornerRadius = radius; border.borderWidth = 2
            border.borderColor = NSColor.lightGray.withAlphaComponent(0.65).cgColor
            if border !== root { root.addSublayer(border) }
        }
        for guide in next.guides {
            let layer = CAGradientLayer()
            layer.frame = CGRect(x: guide.minX - drawingBounds.minX, y: drawingBounds.maxY - guide.maxY,
                                 width: guide.width, height: guide.height)
            let color = NSColor.white.withAlphaComponent(0.45)
            layer.colors = [color.withAlphaComponent(0).cgColor, color.cgColor, color.cgColor, color.withAlphaComponent(0).cgColor]
            let fade = min(0.5, 16 / max(guide.width, guide.height))
            layer.locations = [0, NSNumber(value: fade), NSNumber(value: 1 - fade), 1]
            layer.startPoint = .zero
            layer.endPoint = guide.width > guide.height ? CGPoint(x: 1, y: 0) : CGPoint(x: 0, y: 1)
            root.addSublayer(layer)
        }
        CATransaction.commit()
        self.radius = radius; feedback = next
        panel.orderFrontRegardless()
        if !wasVisible { panel.alphaValue = 0; panel.animator().alphaValue = 1 }
    }

    func hide() {
        guard feedback != nil else { return }
        feedback = nil
        panel?.orderOut(nil)
    }
}

@MainActor func showSnapFeedback(_ feedback: SnapFeedback) {
    guard let screen = NSScreen.screens.first else { return }
    let player = playerWindowInfo()
    SnapPreview.shared.show(feedback, screenHeight: screen.frame.maxY,
        playerLayer: player.number > 0 ? Int(player.layer) : nil)
    if let rect = feedback.outline {
        DesktopInteraction.shared.outline = WallifyWindowRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
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
public func hideSnapPreview() { DispatchQueue.main.async { hideSnapFeedback() } }

@MainActor func hideSnapFeedback() {
    SnapPreview.shared.hide()
    DesktopInteraction.shared.previousSnap = WallifyPanelSnap()
}
