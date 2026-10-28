import AppKit
import PaneFlowSystem
import SwiftUI

@MainActor
final class PermissionsWindowController: NSObject, NSWindowDelegate {
    private let permissions: PermissionManager
    private var window: NSWindow?

    init(permissions: PermissionManager) {
        self.permissions = permissions
    }

    func present() {
        if window == nil {
            let hosting = NSHostingController(rootView: PermissionsView(permissions: permissions))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Permissões do PaneFlow"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        permissions.setInteractiveMonitoring(true)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        permissions.setInteractiveMonitoring(false)
    }
}

struct PermissionsView: View {
    let permissions: PermissionManager
    @State private var nativeSettings = NativeWindowManagerSettings.read()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configurar o PaneFlow").font(.title2.weight(.semibold))
                    Text("O PaneFlow só pede o que usa. Nada sai do seu Mac.")
                        .foregroundStyle(.secondary)
                }
            }

            PermissionRow(
                title: "Acessibilidade",
                badge: "Obrigatória",
                reason: "Permite ao PaneFlow ler a posição e o tamanho das janelas de outros apps e movê-las ou redimensioná-las. O PaneFlow nunca lê nem altera o conteúdo dos documentos.",
                revoke: "Para revogar: Ajustes do Sistema › Privacidade e Segurança › Acessibilidade, desative o PaneFlow.",
                granted: permissions.accessibilityGranted,
                request: { permissions.request(.accessibility) },
                openSettings: { permissions.openSystemSettings(for: .accessibility) }
            )

            PermissionRow(
                title: "Gravação de Tela",
                badge: "Opcional",
                reason: "Usada apenas para mostrar miniaturas das janelas no Snap Assist. As capturas são feitas sob demanda, ficam só na memória e nunca são salvas nem enviadas. Sem ela, o PaneFlow mostra ícones e títulos.",
                revoke: "Para revogar: Ajustes do Sistema › Privacidade e Segurança › Gravação de Tela e Áudio do Sistema.",
                granted: permissions.screenRecordingGranted,
                request: { permissions.request(.screenRecording) },
                openSettings: { permissions.openSystemSettings(for: .screenRecording) }
            )

            Label {
                Text("Monitoramento de Entrada **não** é necessário: o PaneFlow só observa cliques e arrastes do mouse, já cobertos pela Acessibilidade.")
            } icon: {
                Image(systemName: "keyboard").foregroundStyle(.secondary)
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if nativeSettings.edgeDragTilingEnabled == true {
                GroupBox {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("O encaixe de janelas do macOS está ativo").font(.headline)
                            Text("O macOS também encaixa janelas arrastadas para as bordas, o que compete com o PaneFlow. Desative em Ajustes do Sistema › Mesa e Dock › “Arrastar janelas para as bordas da tela para organizá-las”. O PaneFlow nunca altera esse ajuste por você.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Abrir ajustes de Mesa e Dock") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .controlSize(.small)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    }
                    .padding(4)
                }
            }

            Text("Problemas? Se o PaneFlow aparece na lista mas não funciona depois de uma atualização, remova-o da lista com “–” e conceda de novo. A permissão fica vinculada à assinatura do app.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 520)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            nativeSettings = .read()
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let badge: String
    let reason: String
    let revoke: String
    let granted: Bool
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.headline)
                    Text(badge)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    Spacer()
                    if granted {
                        Label("Concedida", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("\(title) concedida")
                    } else {
                        Label("Não concedida", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("\(title) não concedida")
                    }
                }
                Text(reason)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text(revoke)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !granted {
                    HStack {
                        Button("Conceder acesso…", action: request).buttonStyle(.borderedProminent)
                        Button("Abrir Ajustes do Sistema", action: openSettings)
                    }
                    .controlSize(.small)
                }
            }
            .padding(4)
        }
    }
}
