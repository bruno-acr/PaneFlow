import AppKit
import Observation
import PaneFlowCore
import SwiftUI

// MARK: - Model

struct AssistItem: Identifiable, Equatable {
    let token: WindowToken
    let windowID: UInt32?
    let pid: pid_t
    let appName: String
    let title: String?
    /// "2 de 3" when the app has several candidate windows.
    let siblingLabel: String?
    let aspectRatio: CGFloat
    var id: WindowToken { token }
}

@MainActor
@Observable
final class SnapAssistViewModel {
    var items: [AssistItem]
    var query = "" {
        didSet { selection = filtered.isEmpty ? nil : 0 }
    }
    var selection: Int? = 0
    var columns = 3
    var thumbnails: [WindowToken: NSImage] = [:]
    let showsCaptureHint: Bool
    let regionTitle: String

    @ObservationIgnored var onChoose: ((AssistItem) -> Void)?
    @ObservationIgnored var onCancel: (() -> Void)?
    @ObservationIgnored var onEnableThumbnails: (() -> Void)?
    @ObservationIgnored private var icons: [pid_t: NSImage] = [:]

    init(items: [AssistItem], regionTitle: String, showsCaptureHint: Bool) {
        self.items = items
        self.regionTitle = regionTitle
        self.showsCaptureHint = showsCaptureHint
    }

    var filtered: [AssistItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.appName.localizedCaseInsensitiveContains(q) || ($0.title?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    func icon(for pid: pid_t) -> NSImage {
        if let icon = icons[pid] { return icon }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)!
        icons[pid] = icon
        return icon
    }

    func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selection = min(max((selection ?? 0) + delta, 0), count - 1)
    }

    func confirm() {
        let list = filtered
        guard let selection, list.indices.contains(selection) else { return }
        onChoose?(list[selection])
    }

    func remove(_ token: WindowToken) {
        items.removeAll { $0.token == token }
        if let selection, selection >= filtered.count { self.selection = filtered.isEmpty ? nil : filtered.count - 1 }
    }
}

// MARK: - Panel

/// Borderless panel that can take keyboard focus without activating PaneFlow, so the app the user
/// was working in stays active (like Spotlight).
final class AssistPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // Navigation keys are handled before the search field sees them.
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

@MainActor
final class SnapAssistPanelController {
    private let panel: AssistPanel
    let model: SnapAssistViewModel

    /// - Parameter frame: AppKit coordinates of the empty region.
    init(frame: CGRect, model: SnapAssistViewModel) {
        self.model = model
        panel = AssistPanel(contentRect: frame.insetBy(dx: 8, dy: 8), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = NSHostingView(rootView: SnapAssistView(model: model))
        panel.keyHandler = { [weak model] event in
            guard let model else { return false }
            switch Int(event.keyCode) {
            case 123: model.move(-1); return true                    // ←
            case 124: model.move(1); return true                     // →
            case 125: model.move(model.columns); return true         // ↓
            case 126: model.move(-model.columns); return true        // ↑
            case 36, 76: model.confirm(); return true                // ↩ / enter
            case 53: model.onCancel?(); return true                  // esc
            default: return false
            }
        }
        // Losing key status alone does not close the panel: a system alert (e.g. the screen
        // recording reminder) can take focus without the user leaving. SnapAssistController closes
        // it on clicks outside or when the user switches apps.
    }

    /// AppKit frame of the panel.
    var frame: CGRect { panel.frame }

    func show() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
    }

    func close() {
        panel.onResignKey = nil
        panel.keyHandler = nil
        panel.orderOut(nil)
        panel.close()
    }
}

// MARK: - Views

struct SnapAssistView: View {
    @Bindable var model: SnapAssistViewModel
    @FocusState private var searchFocused: Bool

    private let cardWidth: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Escolha uma janela").font(.headline)
                    Text(model.regionTitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar app ou título", text: $model.query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .frame(maxWidth: 220)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            GeometryReader { proxy in
                let columns = max(1, Int((proxy.size.width + 12) / (cardWidth + 12)))
                ScrollViewReader { scroller in
                    ScrollView(.vertical) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                            ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, item in
                                AssistCard(item: item, icon: model.icon(for: item.pid), thumbnail: model.thumbnails[item.token],
                                           selected: model.selection == index)
                                    .id(item.id)
                                    .onTapGesture { model.selection = index; model.confirm() }
                                    .onHover { if $0 { model.selection = index } }
                            }
                        }
                        .padding(2)
                    }
                    .onChange(of: model.selection) { _, new in
                        let list = model.filtered
                        if let new, list.indices.contains(new) { scroller.scrollTo(list[new].id) }
                    }
                }
                .onAppear { model.columns = columns }
                .onChange(of: columns) { _, new in model.columns = new }
            }

            HStack(spacing: 14) {
                Label("setas para navegar", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                Label("↩ escolher", systemImage: "return")
                Label("esc cancelar", systemImage: "escape")
                Spacer()
                if model.showsCaptureHint {
                    Button("Mostrar miniaturas…") { model.onEnableThumbnails?() }
                        .buttonStyle(.link)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .padding(16)
        .background(VisualEffect().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .onAppear { searchFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Snap Assist: escolha uma janela para \(model.regionTitle)")
    }
}

private struct AssistCard: View {
    let item: AssistItem
    let icon: NSImage
    let thumbnail: NSImage?
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(6)
                        .transition(.opacity)
                } else {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 56, height: 56)
                }
            }
            .frame(height: 130)
            .animation(.easeOut(duration: 0.15), value: thumbnail != nil)

            HStack(spacing: 6) {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                Text(item.appName).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let sibling = item.siblingLabel {
                    Text(sibling).font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
            Text(item.title?.isEmpty == false ? item.title! : "Sem título")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.18) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.appName), \(item.title ?? "sem título")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
