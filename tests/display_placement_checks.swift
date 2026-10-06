import AppKit

@MainActor func checkDisplayPlacements() {
    for screen in NSScreen.screens { precondition(widgetDisplayID(screen) != nil) }
    var memory = DisplayPlacements()
    memory.remember("laptop", placement: DisplayPlacement(left: 20, top: 30))
    memory.remember("external", placement: DisplayPlacement(left: 900, top: 200))
    memory.preferredDisplay = "external"
    let restored = try! JSONDecoder().decode(DisplayPlacements.self, from: JSONEncoder().encode(memory))
    precondition(restored.positions["laptop"] == DisplayPlacement(left: 20, top: 30))
    precondition(restored.positions["external"] == DisplayPlacement(left: 900, top: 200))
    precondition(restored.connectedDisplay(["laptop"]) == "laptop")
    precondition(restored.connectedDisplay(["external", "laptop"]) == "external")
    precondition(restored.connectedDisplay(["laptop", "external"]) == "external")
    precondition(restored.connectedDisplay([]) == nil)
    let bounds = NSSize(width: 1200, height: 800), widget = NSSize(width: 540, height: 180)
    precondition(DisplayPlacement(left: 3000, top: -180).clamped(to: bounds, widget: widget) == DisplayPlacement(left: 660, top: 0))
    precondition(DisplayPlacement(left: 10, top: 10).clamped(to: NSSize(width: 100, height: 100), widget: widget) == DisplayPlacement(left: 0, top: 0))
}
