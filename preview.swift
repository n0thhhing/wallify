import AppKit

class PreviewApp: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 0, height: 0),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .floating
        
        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.25).cgColor
        contentView.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.85).cgColor
        contentView.layer?.borderWidth = 2.5
        contentView.layer?.cornerRadius = 26.0
        contentView.layer?.masksToBounds = true
        panel.contentView = contentView
        
        DispatchQueue.global().async {
            self.readInput()
        }
    }
    
    func readInput() {
        while let line = readLine() {
            let parts = line.split(separator: " ")
            if parts.count == 4, let x = Double(parts[0]), let y = Double(parts[1]), let w = Double(parts[2]), let h = Double(parts[3]) {
                DispatchQueue.main.async {
                    if w <= 0 || h <= 0 {
                        self.panel.orderOut(nil)
                    } else {
                        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
                        let rect = NSRect(x: x, y: screenHeight - y - h, width: w, height: h)
                        self.panel.setFrame(rect, display: true)
                        self.panel.orderFrontRegardless()
                    }
                }
            }
        }
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = PreviewApp()
app.delegate = delegate
app.run()
