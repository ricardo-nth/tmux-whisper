import AppKit

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
// Menu-bar only (the bundle also sets LSUIElement).
app.setActivationPolicy(.accessory)
app.run()
