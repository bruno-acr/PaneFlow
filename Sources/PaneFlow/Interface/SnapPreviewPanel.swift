import AppKit

/// Translucent rounded rectangle showing where a window will land. Never takes focus or clicks.
@MainActor
final class SnapPreviewPanel {
    private let panel: NSPanel
    private let effect = NSVisualEffectView()
    private var visible = false

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        // Above normal windows (including the one being dragged), below menus.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 2
        panel.contentView = effect
        updateColors()
    }

    private func updateColors() {
        effect.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        effect.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
    }

    /// - Parameter frame: AppKit coordinates.
    func show(_ frame: CGRect) {
        let inset = frame.insetBy(dx: 6, dy: 6)
        updateColors()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !visible {
            visible = true
            // Grow from the centre of the target area.
            let start = reduceMotion ? inset : CGRect(x: inset.midX - inset.width * 0.45, y: inset.midY - inset.height * 0.45,
                                                     width: inset.width * 0.9, height: inset.height * 0.9)
            panel.setFrame(start, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(inset, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard visible else { return }
        visible = false
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0 : 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.visible else { return }
                self.panel.orderOut(nil)
            }
        })
    }
}
