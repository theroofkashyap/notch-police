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

    /// The other direction. Nothing from the transcript goes on the clipboard,
    /// only a prompt for the chat that is running out. Pasted there, the agent
    /// that still holds the whole conversation writes the handover itself,
    /// which beats raw turns whenever it has credits left to answer. `make`
    /// is the fallback for when it does not.
    public static func summaryPrompt(
        snapshot: ProviderSnapshot,
        pace: Pace?,
        project: String?
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

        var lines: [String] = []
        lines.append("My \(snapshot.displayName) credits are about to run out (\(why)). Before I switch to another agent, write a handover summary of this session so the next agent can continue without restarting.")
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
        lines.append("Be specific: real names, paths, commands, and numbers. Describe the state of the work, not the conversation in order. Start with the line \"\(header)\" so I can paste your answer into the next agent as-is, and keep it under 500 words.")
        return lines.joined(separator: "\n")
    }
}

public extension ProviderSnapshot {
    func isDying(below threshold: Double) -> Bool {
        guard let remaining = primaryRemaining else { return false }
        return remaining <= threshold
    }
}
