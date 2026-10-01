import Foundation

func animationSpeed(_ value: UInt8) -> Double { value == 0 ? 0.7 : value == 2 ? 1.4 : 1 }

func idleCompositorEligible(_ state: WallifyWidgetState) -> Bool {
    state.idle_mix == 1 && state.setting_animations && state.setting_idle_style != 0 &&
    !state.mode_transition_active && !state.panel_snap_active && !state.global_panel_dragging && state.animation_time >= state.cat_pet_until
}

final class IdleCompositor {
    private(set) var active = false
    private var card = WallifyCardRect()
    private var style: UInt8 = 0
    private var speed: UInt8 = 1

    func elapsed(_ seconds: Double) -> Double { max(0, seconds) * animationSpeed(speed) }

    func update(card: WallifyCardRect, state: WallifyWidgetState) {
        guard idleCompositorEligible(state) else {
            if active { stopIdleAnimation() }
            active = false; return
        }
        if active && self.card.x == card.x && self.card.y == card.y && self.card.w == card.w && self.card.h == card.h && self.card.radius == card.radius && style == state.setting_idle_style && speed == state.setting_speed { return }
        var copy = card
        active = startPetAnimation(Int32(state.setting_idle_style - 1), &copy, state.cat_time, animationSpeed(state.setting_speed))
        if active { self.card = card; style = state.setting_idle_style; speed = state.setting_speed }
    }
}

let idleCompositor = IdleCompositor()

@_cdecl("wallify_idle_compositor_active")
public func idleCompositorActive() -> Bool { idleCompositor.active }
@_cdecl("wallify_idle_compositor_elapsed")
public func idleCompositorElapsed(_ seconds: Double) -> Double { idleCompositor.elapsed(seconds) }
