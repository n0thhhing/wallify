import AppKit
import QuartzCore

struct DesktopGlassGeometry: Equatable {
    let rect: NSRect
    let radius: Double
    let active: Bool
}

@MainActor
final class DesktopGlass {
    static let shared = DesktopGlass()
    private var glass: NSView?
    private var content: NSView?

    func update(_ geometry: DesktopGlassGeometry, panel: NSPanel, metalView: NSView, size: NSSize) {
        guard let container = panel.contentView else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if #available(macOS 26.0, *), geometry.active {
            if glass == nil {
                let view = NSGlassEffectView(frame: .zero)
                view.style = .regular
                // Preserve the desktop optical variant selected by the native port.
                // AppKit's hidden style knob: ask first so its disappearance leaves regular glass.
                let selector = NSSelectorFromString("set_variant:")
                if view.responds(to: selector) {
                    typealias SetVariant = @convention(c) (AnyObject, Selector, Int) -> Void
                    unsafeBitCast(view.method(for: selector), to: SetVariant.self)(view, selector, 5)
                }
                view.appearance = NSAppearance(named: .darkAqua)
                view.tintColor = nil
                let inner = NSView(frame: .zero)
                inner.wantsLayer = true
                inner.layer?.backgroundColor = NSColor.clear.cgColor
                inner.layer?.cornerCurve = .continuous
                inner.layer?.masksToBounds = true
                inner.clipsToBounds = true
                view.contentView = inner
                container.addSubview(view)
                glass = view
                content = inner
            }
            let view = glass as! NSGlassEffectView
            let inner = content!
            view.isHidden = false
            if metalView.superview !== inner {
                metalView.removeFromSuperview()
                metalView.autoresizingMask = []
                inner.addSubview(metalView)
            }
            let rect = geometry.rect
            let flippedY = size.height - rect.minY - rect.height
            view.frame = NSRect(x: rect.minX, y: flippedY, width: rect.width, height: rect.height)
            view.cornerRadius = geometry.radius
            inner.frame = view.bounds
            inner.layer?.cornerRadius = geometry.radius
            // Move the canvas backward by the crop offset; its drawing coordinates stay unchanged.
            metalView.frame = NSRect(x: -rect.minX, y: -flippedY, width: size.width, height: size.height)
            return
        }
        glass?.isHidden = true
        if metalView.superview !== container {
            metalView.removeFromSuperview()
            metalView.autoresizingMask = [.width, .height]
            container.addSubview(metalView)
        }
        metalView.frame = container.bounds
    }
}

private let desktopGlassLock = NSLock()
private var lastDesktopGlass: DesktopGlassGeometry?

@_cdecl("wallify_update_glass_rect")
public func updateDesktopGlass(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ radius: Double,
                               _ red: Float, _ green: Float, _ blue: Float, _ active: Bool) {
    guard [x, y, width, height, radius].allSatisfy({ $0.isFinite }), width >= 0, height >= 0, radius >= 0 else { return }
    let geometry = DesktopGlassGeometry(rect: NSRect(x: x, y: y, width: width, height: height), radius: radius, active: active)
    desktopGlassLock.lock()
    let unchanged = lastDesktopGlass == geometry
    lastDesktopGlass = geometry
    desktopGlassLock.unlock()
    guard !unchanged else { return }
    DispatchQueue.main.async {
        guard let panel = WidgetPanel.current, let view = WidgetView.current else { return }
        DesktopGlass.shared.update(geometry, panel: panel, metalView: view,
                                   size: NSSize(width: Int(wallify_width()), height: Int(wallify_height())))
    }
}
