import AppKit
import Combine
import SwiftUI
import NotchPoliceCore

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none
        isReleasedWhenClosed = false
    }
}

@MainActor
final class NotchWindowController: NSObject {
    private let panel = NotchPanel()
    private let store: UsageStore
    private let preview = HandoverPreviewWindow()
    private var screenObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []

    init(store: UsageStore) {
        self.store = store
        super.init()
        let root = NotchRootView(
            store: store,
            onSettings: { Self.showSettings() },
            onPreview: { [weak self] kind in self?.showPreview(for: kind) },
            onQuit: { NSApp.terminate(nil) }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.contentView?.wantsLayer = true
        reposition()
        panel.orderFrontRegardless()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reposition()
            }
            .store(in: &cancellables)
    }

    func reposition() {
        guard let screen = Self.anchorScreen() else { return }
        let visible = screen.visibleFrame
        let full = screen.frame
        let edge = store.preferences.edge
        let count = CGFloat(max(1, store.visibleSnapshots.count))
        let along = NotchMetrics.curl * 2 + NotchMetrics.cell * count + 16
        let showingTip = store.expanded && store.hovered != nil
        let across = showingTip
            ? NotchMetrics.depth + NotchMetrics.tooltipWidth + NotchMetrics.tooltipGap + 24
            : NotchMetrics.depth

        var frame = NSRect.zero
        switch edge {
        case .right:
            frame = NSRect(
                x: full.maxX - across,
                y: visible.midY - along / 2,
                width: across,
                height: along
            )
        case .left:
            frame = NSRect(
                x: full.minX,
                y: visible.midY - along / 2,
                width: across,
                height: along
            )
        case .top:
            let hardware = screen.safeAreaInsets.top
            frame = NSRect(
                x: full.midX - along / 2,
                y: full.maxY - across - (hardware > 0 ? 0 : 0),
                width: along,
                height: across
            )
        case .bottom:
            frame = NSRect(
                x: full.midX - along / 2,
                y: visible.minY,
                width: along,
                height: across
            )
        }
        panel.setFrame(frame, display: true)
        // The window is transparent and changes size when a tooltip opens, so
        // the cached shadow has to be dropped or it smears at the old bounds.
        panel.invalidateShadow()
        if store.isHidden {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Routes to the single SwiftUI `Settings` scene, so this and ⌘, cannot
    /// end up showing two different windows over the same preferences.
    static func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    func showPreview(for kind: ProviderKind) {
        Task { @MainActor in
            let text = await store.handover(for: kind)
            preview.show(kind: kind, project: store.contextProjects[kind], text: text)
        }
    }

    func setHidden(_ hidden: Bool) {
        if hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    private static func anchorScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let hovered = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return hovered
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}
