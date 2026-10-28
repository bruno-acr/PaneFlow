import AppKit

// Resident menu-bar utility: no Dock icon (`LSUIElement` in Info.plist; `.accessory` here as well
// so that `swift run` behaves the same as the bundled app).
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
