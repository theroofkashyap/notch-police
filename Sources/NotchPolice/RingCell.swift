import SwiftUI
import NotchPoliceCore

struct RingCell: View {
    var snapshot: ProviderSnapshot
    var mode: DisplayMode
    var highlighted: Bool
    /// Vertical edges stack the label under the ring. Horizontal edges put it
    /// beside the ring instead: the pill is only `depth` tall there, and a
    /// stacked cell overflows it and gets clipped by the bezel.
    var vertical: Bool = true

    var body: some View {
        let remaining = snapshot.primaryRemaining
        let band = UsageBand.fromRemaining(remaining)
        let percent = snapshot.tightest.map { $0.displayPercent(mode: mode) }
        let ring = RemainingRing(
            remaining: mode == .remaining ? remaining : percent,
            band: band,
            kind: snapshot.kind,
            pulse: band == .critical || band == .empty
        )
        .frame(width: NotchMetrics.ring, height: NotchMetrics.ring)
        let label = Text(percentLabel(percent, status: snapshot.status, mode: mode))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(labelColor(snapshot.status, band: band))
            .monospacedDigit()

        Group {
            if vertical {
                VStack(spacing: 4) {
                    ring
                    label
                }
                .frame(width: NotchMetrics.depth - 8, height: NotchMetrics.cell)
            } else {
                HStack(spacing: 6) {
                    ring
                    label
                }
                .frame(width: NotchMetrics.wideCell, height: NotchMetrics.depth - 16)
            }
        }
        .opacity(highlighted || snapshot.isLive ? 1 : 0.85)
    }

    private func percentLabel(_ percent: Double?, status: SnapshotStatus, mode: DisplayMode) -> String {
        switch status {
        case .needsAuth: return "—"
        case .accessDenied: return "key"
        case .error: return "!"
        case .ok, .stale, .demo, .rateLimited:
            guard let percent else { return "—" }
            return "\(Int(percent.rounded()))%"
        }
    }

    private func labelColor(_ status: SnapshotStatus, band: UsageBand) -> Color {
        switch status {
        case .needsAuth, .accessDenied: return Palette.muted
        case .error: return Palette.band(.critical)
        default: return Palette.band(band) == Palette.band(.unknown) ? .white : Palette.band(band)
        }
    }
}
