import SwiftUI
import NotchPoliceCore

struct NotchRootView: View {
    @ObservedObject var store: UsageStore
    var onSettings: () -> Void
    var onPreview: (ProviderKind) -> Void
    var onQuit: () -> Void

    /// Pending collapse after the cursor leaves. The window resizes around
    /// the tooltip, and hover flaps while it does, so leaving waits a beat
    /// and re-entering cancels it.
    @State private var collapse: Task<Void, Never>?

    var body: some View {
        let edge = store.preferences.edge
        let snaps = store.visibleSnapshots
        let vertical = edge.isVertical

        ZStack(alignment: alignment(for: edge)) {
            tooltip(edge: edge, snaps: snaps)

            VStack(spacing: 0) {
                if vertical {
                    stack(snaps, edge: edge)
                } else {
                    HStack(spacing: 0) {
                        stack(snaps, edge: edge)
                    }
                }
            }
            .padding(.vertical, vertical ? NotchMetrics.curl + 6 : 8)
            .padding(.horizontal, vertical ? 8 : NotchMetrics.curl + 6)
            .frame(
                width: vertical ? NotchMetrics.depth : nil,
                height: vertical ? nil : NotchMetrics.depth
            )
            .background(Palette.bezel)
            .clipShape(BezelNotchShape(edge: edge))
            .overlay(
                BezelNotchShape(edge: edge)
                    .stroke(Palette.brass.opacity(0.35), lineWidth: 0.8)
            )
            .contextMenu { menu }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(for: edge))
        .background(Color.clear)
        // Hover has to cover the whole transparent window, gap and card
        // included, or crossing from the pill to the tooltip counts as leaving.
        .contentShape(Rectangle())
        .preferredColorScheme(.dark)
        .onHover { hovering in
            collapse?.cancel()
            if hovering {
                store.expanded = true
            } else {
                collapse = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    guard !Task.isCancelled else { return }
                    store.expanded = false
                    store.hovered = nil
                }
            }
        }
    }

    @ViewBuilder
    private func stack(_ snaps: [ProviderSnapshot], edge: ScreenEdge) -> some View {
        ForEach(snaps) { snap in
            RingCell(
                snapshot: snap,
                mode: store.preferences.displayMode,
                highlighted: store.hovered == snap.kind,
                vertical: edge.isVertical
            )
            .onHover { hovering in
                guard hovering else { return }
                collapse?.cancel()
                // Only publish real changes: every store change re-lays out
                // the window, and re-hovering the same ring is not a change.
                if store.hovered != snap.kind {
                    store.hovered = snap.kind
                }
                if !store.expanded {
                    store.expanded = true
                }
                store.prepareContext(for: snap.kind)
            }
            .onTapGesture {
                NSWorkspace.shared.open(snap.kind.dashboardURL)
            }
        }
    }

    @ViewBuilder
    private func tooltip(edge: ScreenEdge, snaps: [ProviderSnapshot]) -> some View {
        if store.expanded, let hovered = store.hovered,
           let snap = snaps.first(where: { $0.kind == hovered })
        {
            TooltipCard(
                snapshot: snap,
                mode: store.preferences.displayMode,
                pace: store.pace(for: snap.kind),
                dyingBelow: store.preferences.dyingBelow,
                contextProject: store.contextProjects[snap.kind],
                destination: store.handoverDestination(leaving: snap.kind),
                onCopyContext: { copyContext(for: snap.kind) },
                onCopySummary: { copySummaryPrompt(for: snap.kind) }
            )
            .padding(edgePadding(edge))
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: tooltipAnchor(edge))))
        }
    }

    private var menu: some View {
        Group {
            Button("Refresh now") {
                Task { await store.refresh() }
            }
            Button(copyMenuTitle) {
                if let kind = preferredKind { copyContext(for: kind) }
            }
            Button("Copy summary prompt") {
                if let kind = preferredKind { copySummaryPrompt(for: kind) }
            }
            Button("Preview context…") {
                if let kind = preferredKind { onPreview(kind) }
            }
            Button("Settings…", action: onSettings)
            Divider()
            Button("Hide for 1 hour") { store.hide(for: 3600) }
            Button("Quit Notch Police", action: onQuit)
        }
    }

    private var preferredKind: ProviderKind? {
        store.hovered ?? store.dyingKind ?? store.visibleSnapshots.first?.kind
    }

    private var copyMenuTitle: String {
        guard let kind = store.hovered ?? store.dyingKind else { return "Copy context" }
        let snap = store.visibleSnapshots.first { $0.kind == kind }
        let dying = snap?.isDying(below: store.preferences.dyingBelow) == true
        if let dest = store.handoverDestination(leaving: kind) {
            return dying
                ? "Copy dying \(kind.displayName) for \(dest.displayName)"
                : "Copy \(kind.displayName) for \(dest.displayName)"
        }
        return dying
            ? "Copy dying \(kind.displayName) context"
            : "Copy \(kind.displayName) context"
    }

    private func copyContext(for kind: ProviderKind) {
        Task { @MainActor in
            Clipboard.copy(await store.handover(for: kind))
        }
    }

    private func copySummaryPrompt(for kind: ProviderKind) {
        Task { @MainActor in
            Clipboard.copy(await store.summaryPrompt(for: kind))
        }
    }

    private func alignment(for edge: ScreenEdge) -> Alignment {
        switch edge {
        case .right: return .trailing
        case .left: return .leading
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    private func tooltipAnchor(_ edge: ScreenEdge) -> UnitPoint {
        switch edge {
        case .right: return .trailing
        case .left: return .leading
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    private func edgePadding(_ edge: ScreenEdge) -> EdgeInsets {
        switch edge {
        case .right: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: NotchMetrics.depth + NotchMetrics.tooltipGap)
        case .left: return EdgeInsets(top: 0, leading: NotchMetrics.depth + NotchMetrics.tooltipGap, bottom: 0, trailing: 0)
        case .top: return EdgeInsets(top: NotchMetrics.depth + NotchMetrics.tooltipGap, leading: 0, bottom: 0, trailing: 0)
        case .bottom: return EdgeInsets(top: 0, leading: 0, bottom: NotchMetrics.depth + NotchMetrics.tooltipGap, trailing: 0)
        }
    }
}
