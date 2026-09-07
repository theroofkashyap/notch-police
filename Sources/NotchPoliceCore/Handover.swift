import Foundation

public enum Handover {
    public static func make(
        snapshot: ProviderSnapshot,
        pace: Pace?,
        excerpt: SessionExcerpt?,
        now: Date = Date()
    ) -> String {
        var lines: [String] = []
        let remaining = snapshot.primaryRemaining.map { Int($0.rounded()) }
        let remainingCopy = remaining.map { "\($0)% left" } ?? "remaining unknown"
        lines.append("I'm switching agents because \(snapshot.displayName) credits are about to run out (\(remainingCopy)).")
        lines.append("")
        lines.append("## Status")
        if let plan = snapshot.plan {
            lines.append("- Plan: \(plan)")
        }
        for window in snapshot.windows {
            var row = "- \(window.label): \(Int(window.remainingPercent.rounded()))% left"
            if let resets = window.resetsAt {
                row += " (resets \(ResetCopy.format(resets, now: now)))"
            }
            if let detail = window.detail {
                row += " — \(detail)"
            }
            lines.append(row)
        }
        if let pace {
            lines.append("- Pace: \(pace.copy)")
        }
        lines.append("")
        lines.append("Continue this work in the other agent. Do not restart from scratch.")
        if let excerpt {
            lines.append("")
            lines.append("## Latest \(excerpt.source)")
            if let project = excerpt.project, !project.isEmpty {
                lines.append("Project: \(project)")
            }
            if let title = excerpt.title, !title.isEmpty {
                lines.append("Title: \(title)")
            }
            for turn in excerpt.turns {
                lines.append("")
                lines.append("### \(turn.role.capitalized)")
                lines.append(turn.text)
            }
        } else {
            lines.append("")
            lines.append("(No local session transcript found. Ask me to recap the current task before continuing.)")
        }
        return lines.joined(separator: "\n")
    }
}

public extension ProviderSnapshot {
    func isDying(below threshold: Double) -> Bool {
        guard let remaining = primaryRemaining else { return false }
        return remaining <= threshold
    }
}
