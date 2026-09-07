import SwiftUI
import NotchPoliceCore

struct TooltipCard: View {
    var snapshot: ProviderSnapshot
    var mode: DisplayMode
    var pace: Pace?
    var dyingBelow: Double
    var contextProject: String?
    var onCopyContext: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProviderMark(kind: snapshot.kind)
                    .frame(width: 20, height: 20)
                Text("\(snapshot.displayName) usage")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if let plan = snapshot.plan {
                    Text(plan)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.brass)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.brass.opacity(0.12), in: Capsule())
                }
            }

            switch snapshot.status {
            case .needsAuth, .accessDenied:
                Text(snapshot.signInHint ?? snapshot.kind.signInHint)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let command = snapshot.kind.signInCommand {
                    Text(command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.brass)
                }
            case .error(let message):
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.band(.critical))
            case .ok, .stale, .demo, .rateLimited:
                if snapshot.windows.isEmpty {
                    Text("No quota windows on this plan.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                } else {
                    ForEach(snapshot.windows) { window in
                        WindowRow(window: window, mode: mode)
                    }
                    if let pace {
                        Text(pace.copy)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.brass)
                    }
                    if snapshot.status == .demo {
                        Text("Demo data")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    }
                    if case .rateLimited = snapshot.status {
                        Text("Rate limited — showing the last reading")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    }
                    CopyContextButton(
                        dying: snapshot.isDying(below: dyingBelow),
                        project: contextProject,
                        copied: copied,
                        action: {
                            onCopyContext()
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                                copied = false
                            }
                        }
                    )
                }
            }
        }
        .padding(14)
        .frame(width: NotchMetrics.tooltipWidth, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.brass.opacity(0.22), lineWidth: 0.8)
        )
    }
}

private struct CopyContextButton: View {
    var dying: Bool
    /// Named on the button because the handover carries real conversation
    /// text, and the user should see which project it came from before the
    /// clipboard is involved.
    var project: String?
    var copied: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                    Text(copied ? "Copied — paste into another agent" : label)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let project, !copied {
                    Text(project)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .opacity(0.75)
                }
            }
            .foregroundStyle(dying && !copied ? Color.black : .white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                copied ? Palette.band(.clear).opacity(0.85)
                    : dying ? Palette.brass : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var label: String {
        dying ? "Credits dying — copy context" : "Copy context"
    }
}

private struct WindowRow: View {
    var window: LimitWindow
    var mode: DisplayMode

    var body: some View {
        let remaining = window.remainingPercent
        let shown = window.displayPercent(mode: mode)
        let band = UsageBand.fromRemaining(remaining)
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
                Spacer()
                if let resets = window.resetsAt {
                    Text(ResetCopy.format(resets))
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track)
                    Capsule()
                        .fill(Palette.band(band))
                        .frame(width: max(4, geo.size.width * CGFloat(shown / 100)))
                }
            }
            .frame(height: 5)
            HStack {
                Text("\(Int(shown.rounded()))% \(mode == .remaining ? "left" : "used")")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.band(band))
                Spacer()
                if let detail = window.detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }
}
