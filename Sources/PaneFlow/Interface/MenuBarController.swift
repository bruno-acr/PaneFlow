import AppKit
import PaneFlowCore
import PaneFlowSystem

/// Status-bar item and its menu. The menu is rebuilt on demand (open, permission or display change),
/// never on a timer.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private unowned let coordinator: ApplicationCoordinator
    /// Commands referenced by menu items (NSMenuItem.representedObject needs an object).
    private var commands: [Int: WindowCommand] = [:]

    init(coordinator: ApplicationCoordinator) {
        self.coordinator = coordinator
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "PaneFlow")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        rebuild()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        coordinator.permissions.refresh()
        rebuild()
    }

    func rebuild() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()
        commands.removeAll()
        let prefs = coordinator.preferences
        let canControl = coordinator.permissions.accessibilityGranted && prefs.enabled

        if !coordinator.permissions.accessibilityGranted {
            let warning = item("Permissão de Acessibilidade necessária…", #selector(showPermissions))
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(warning)
            menu.addItem(.separator())
        } else if let other = ConflictingWindowManagers.running().first, prefs.snapOnDrag {
            let warning = info("\(other) está aberto e também encaixa janelas — feche-o ou desative o encaixe dele")
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(warning)
            menu.addItem(.separator())
        } else if NativeWindowManagerSettings.read().edgeDragTilingEnabled == true && prefs.snapOnDrag {
            let warning = item("O encaixe do macOS está ativo e compete com o PaneFlow…", #selector(showPermissions))
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        let enabled = item("PaneFlow ativado", #selector(toggleEnabled))
        enabled.state = prefs.enabled ? .on : .off
        menu.addItem(enabled)
        menu.addItem(.separator())

        let swap = commandItem(.swap, enabled: canControl)
        swap.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)
        menu.addItem(swap)

        let snap = submenu("Encaixar janela atual", enabled: canControl)
        for region in [SnapRegion.leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize] {
            snap.submenu?.addItem(commandItem(.snap(region), enabled: canControl))
        }
        snap.submenu?.addItem(.separator())
        for region in [SnapRegion.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter] {
            snap.submenu?.addItem(commandItem(.snap(region), enabled: canControl))
        }
        snap.submenu?.addItem(.separator())
        snap.submenu?.addItem(commandItem(.center, enabled: canControl))
        menu.addItem(snap)

        let topology = coordinator.displays.topology
        if topology.displays.count > 1 {
            let move = submenu("Mover para monitor", enabled: canControl)
            for display in topology.displays.sorted(by: { $0.frame.minX < $1.frame.minX }) {
                let entry = submenu(display.name + (display.isPrimary ? " (principal)" : ""), enabled: canControl)
                for region in [SnapRegion.leftHalf, .rightHalf, .maximize] {
                    entry.submenu?.addItem(commandItem(.snap(region, displayID: display.id), enabled: canControl))
                }
                move.submenu?.addItem(entry)
            }
            menu.addItem(move)
        }
        menu.addItem(commandItem(.restore, enabled: canControl))
        menu.addItem(commandItem(.nextDisplay, enabled: canControl && topology.displays.count > 1))

        if let status = coordinator.lastStatus {
            menu.addItem(.separator())
            menu.addItem(info(status))
        }

        menu.addItem(.separator())
        let preferences = submenu("Preferências", enabled: true)
        preferences.submenu?.addItem(toggle("Encaixar ao arrastar para as bordas", prefs.snapOnDrag, #selector(toggleSnapOnDrag)))
        preferences.submenu?.addItem(toggle("Segurar o cursor na divisa entre monitores", prefs.edgeResistance, #selector(toggleEdgeResistance)))
        preferences.submenu?.addItem(toggle("Mostrar outras janelas após encaixar (Snap Assist)", prefs.snapAssist, #selector(toggleSnapAssist)))
        preferences.submenu?.addItem(toggle("Redimensionar janelas vizinhas juntas", prefs.linkedResize, #selector(toggleLinkedResize)))
        preferences.submenu?.addItem(toggle("Atalhos de teclado", prefs.keyboardShortcuts, #selector(toggleShortcuts)))
        preferences.submenu?.addItem(.separator())
        preferences.submenu?.addItem(info("Segure ⌥ ao arrastar para não encaixar"))
        preferences.submenu?.addItem(info("Na divisa entre monitores: empurre mais para passar ao outro"))
        menu.addItem(preferences)

        let shortcuts = submenu("Atalhos de teclado", enabled: true)
        for (shortcut, command) in ApplicationCoordinator.shortcuts {
            let conflict = coordinator.shortcutConflicts.contains(shortcut.display)
            shortcuts.submenu?.addItem(info("\(shortcut.display)   \(command.title)\(conflict ? " — em uso por outro app" : "")"))
        }
        shortcuts.submenu?.addItem(.separator())
        shortcuts.submenu?.addItem(info("Repita ⌃⌥← / ⌃⌥→ para passar ao monitor vizinho"))
        menu.addItem(shortcuts)

        menu.addItem(item("Permissões…", #selector(showPermissions)))
        let diagnostics = submenu("Diagnóstico", enabled: true)
        let selfTest = item("Executar autoteste de geometria", #selector(runSelfTest))
        selfTest.isEnabled = coordinator.permissions.accessibilityGranted
        diagnostics.submenu?.addItem(selfTest)
        diagnostics.submenu?.addItem(item("Exportar relatório de diagnóstico…", #selector(exportDiagnostics)))
        menu.addItem(diagnostics)

        menu.addItem(.separator())
        menu.addItem(item("Sobre o PaneFlow", #selector(showAbout)))
        menu.addItem(item("Sair do PaneFlow", #selector(quit)))
    }

    // MARK: Builders

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func toggle(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let entry = item(title, action)
        entry.state = on ? .on : .off
        return entry
    }

    private func submenu(_ title: String, enabled: Bool) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.autoenablesItems = false
        entry.submenu = menu
        entry.isEnabled = enabled
        return entry
    }

    private func commandItem(_ command: WindowCommand, enabled: Bool) -> NSMenuItem {
        let entry = item(command.title, #selector(performCommand(_:)))
        entry.tag = commands.count
        commands[entry.tag] = command
        entry.isEnabled = enabled
        return entry
    }

    // MARK: Actions

    @objc private func performCommand(_ sender: NSMenuItem) {
        guard let command = commands[sender.tag] else { return }
        coordinator.perform(command)
    }

    @objc private func toggleEnabled() { coordinator.isEnabled.toggle() }

    @objc private func toggleSnapOnDrag() {
        coordinator.preferences.snapOnDrag.toggle()
        coordinator.refreshServices()
    }

    @objc private func toggleEdgeResistance() {
        coordinator.preferences.edgeResistance.toggle()
        coordinator.refreshServices()
    }

    @objc private func toggleSnapAssist() {
        coordinator.preferences.snapAssist.toggle()
        rebuild()
    }

    @objc private func toggleLinkedResize() {
        coordinator.preferences.linkedResize.toggle()
        coordinator.refreshServices()
    }

    @objc private func toggleShortcuts() {
        coordinator.preferences.keyboardShortcuts.toggle()
        coordinator.refreshServices()
    }

    @objc private func showPermissions() { coordinator.showPermissions() }

    @objc private func runSelfTest() {
        Task { await coordinator.runSelfTest(terminateWhenDone: false) }
    }

    @objc private func exportDiagnostics() { coordinator.exportDiagnostics() }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
