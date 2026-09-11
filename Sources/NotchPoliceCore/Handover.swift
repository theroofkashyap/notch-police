import Foundation

public enum Handover {
    /// The live ring with the most remaining, other than the one we are
    /// leaving. Unsigned or empty-status rings are skipped so the paste
    /// target is never a guessed percentage.
    public static func destination(
        among snapshots: [ProviderSnapshot],
        leaving kind: ProviderKind
    ) -> ProviderSnapshot? {
        snapshots
            .filter { $0.kind != kind && $0.isLive && $0.primaryRemaining != nil }
            .max { ($0.primaryRemaining ?? -1) < ($1.primaryRemaining ?? -1) }
    }

    public static func make(
        snapshot: ProviderSnapshot,
        pace: Pace?,
        excerpt: SessionExcerpt?,
        destination: ProviderSnapshot? = nil,
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
        lines.append(continueLine(destination: destination))
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

    /// The other direction. Nothing from the transcript goes on the clipboard,
    /// only a prompt for the chat that is running out. Pasted there, the agent
    /// that still holds the whole conversation writes the handover itself,
    /// which beats raw turns whenever it has credits left to answer. `make`
    /// is the fallback for when it does not.
    public static func summaryPrompt(
        snapshot: ProviderSnapshot,
        pace: Pace?,
        project: String?,
        destination: ProviderSnapshot? = nil
    ) -> String {
        let remaining = snapshot.primaryRemaining.map { Int($0.rounded()) }
        var why = remaining.map { "\($0)% left" } ?? "remaining unknown"
        if let pace {
            let copy = pace.copy
            why += ", " + copy.prefix(1).lowercased() + copy.dropFirst()
        }
        var header = "Handover from a \(snapshot.displayName) session"
        if let project, !project.isEmpty {
            header += " on \(project)"
        }
        let nextAgent = destination.map(\.displayName) ?? "the next agent"
        let beforeSwitch = destination.map { dest in
            "Before I switch to \(dest.displayName) (\(remainingCopy(dest))), write a handover summary of this session so \(dest.displayName) can continue without restarting."
        } ?? "Before I switch to another agent, write a handover summary of this session so the next agent can continue without restarting."

        var lines: [String] = []
        lines.append("My \(snapshot.displayName) credits are about to run out (\(why)). \(beforeSwitch)")
        if let project, !project.isEmpty {
            lines.append("")
            lines.append("Project: \(project)")
        }
        lines.append("")
        lines.append("Cover these, in this order, as plain markdown:")
        lines.append("")
        lines.append("1. **Goal** — what we are building or fixing, in one or two sentences.")
        lines.append("2. **Done** — what is finished and verified, with file paths.")
        lines.append("3. **In progress** — what is half-done and exactly where it stands.")
        lines.append("4. **Decisions** — choices made and why, especially anything non-obvious or rejected.")
        lines.append("5. **Next steps** — the concrete next actions, in order.")
        lines.append("6. **Watch out** — gotchas, failing tests, environment quirks, anything that bit us.")
        lines.append("7. **Commands and paths** — how to build, test, and run, and the key files.")
        lines.append("")
        lines.append("Be specific: real names, paths, commands, and numbers. Describe the state of the work, not the conversation in order. Start with the line \"\(header)\" so I can paste your answer into \(nextAgent) as-is, and keep it under 500 words.")
        return lines.joined(separator: "\n")
    }

    static func continueLine(destination: ProviderSnapshot?) -> String {
        guard let destination else {
            return "Continue this work in the other agent. Do not restart from scratch."
        }
        return "Continue this work in \(destination.displayName) (\(remainingCopy(destination))). Do not restart from scratch."
    }

    static func remainingCopy(_ snapshot: ProviderSnapshot) -> String {
        snapshot.primaryRemaining.map { "\(Int($0.rounded()))% left" } ?? "remaining unknown"
    }
}

public extension ProviderSnapshot {
    func isDying(below threshold: Double) -> Bool {
        guard let remaining = primaryRemaining else { return false }
        return remaining <= threshold
    }
}
