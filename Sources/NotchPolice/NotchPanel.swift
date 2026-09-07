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
        let vertical = edge.isVertical
        let count = CGFloat(max(1, store.visibleSnapshots.count))
        let cell = vertical ? NotchMetrics.cell : NotchMetrics.wideCell
        let pill = NotchMetrics.curl * 2 + cell * count + 16
        let showingTip = store.expanded && store.hovered != nil
        // The window has to hold the tooltip card as well: beside the pill on
        // vertical edges, above or below it on horizontal ones. The pill is
        // centred along the edge, so growing the window there does not move it.
        let along = showingTip
            ? max(pill, vertical ? NotchMetrics.tooltipHeightAllowance : NotchMetrics.tooltipWidth + 24)
            : pill
        let across = showingTip
            ? NotchMetrics.depth + NotchMetrics.tooltipGap + 24
                + (vertical ? NotchMetrics.tooltipWidth : NotchMetrics.tooltipHeightAllowance)
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
            frame = NSRect(
                x: full.midX - along / 2,
                y: full.maxY - across,
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

        // Every store change lands here, hover moves included. Re-setting an
        // unchanged frame still redraws the transparent window and drops its
        // shadow, which is what made the notch judder under the cursor.
        let hidden = store.isHidden
        let visibilityCorrect = hidden ? !panel.isVisible : panel.isVisible
        if frame == panel.frame, visibilityCorrect {
            return
        }
        if frame != panel.frame {
            panel.setFrame(frame, display: true)
            // The window is transparent and changes size when a tooltip opens,
            // so the cached shadow has to go or it smears at the old bounds.
            panel.invalidateShadow()
        }
        if hidden {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Routes to the single SwiftUI `Settings` scene, so this and ⌘, cannot
    /// end up showing two different windows over the same preferences.
    ///
    /// The private `showSettingsWindow:` selector did not open that scene from
    /// the notch's context menu; SwiftUI's public `openSettings` action does,
    /// so it is captured from the menu bar label (see `SettingsOpener`) and
    /// used first. Activation is asynchronous on modern macOS, hence the hop.
    static func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            if let open = SettingsOpener.shared.open {
                open()
            } else {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
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
