import Foundation

public enum Fixtures {
    public static func demoSnapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                kind: .claude,
                plan: "Max 5x",
                windows: [
                    LimitWindow(
                        id: "session",
                        label: "5-hour session",
                        usedPercent: 88,
                        resetsAt: now.addingTimeInterval(18 * 60)
                    ),
                    LimitWindow(
                        id: "weekly",
                        label: "Weekly",
                        usedPercent: 11,
                        resetsAt: now.addingTimeInterval(4 * 24 * 3600)
                    ),
                ],
                fetchedAt: now,
                status: .demo
            ),
            ProviderSnapshot(
                kind: .cursor,
                plan: "Pro",
                windows: [
                    LimitWindow(
                        id: "included",
                        label: "Included usage",
                        usedPercent: 41,
                        resetsAt: now.addingTimeInterval(12 * 24 * 3600),
                        detail: "$8 of $20 included · $4 bonus"
                    ),
                    LimitWindow(
                        id: "api",
                        label: "API / named models",
                        usedPercent: 64,
                        resetsAt: now.addingTimeInterval(12 * 24 * 3600)
                    ),
                ],
                fetchedAt: now,
                status: .demo
            ),
            ProviderSnapshot(
                kind: .chatgpt,
                plan: "Plus",
                windows: [
                    LimitWindow(
                        id: "five-hour",
                        label: "5-hour",
                        usedPercent: 18,
                        resetsAt: now.addingTimeInterval(3 * 3600)
                    ),
                    LimitWindow(
                        id: "weekly",
                        label: "Weekly",
                        usedPercent: 44,
                        resetsAt: now.addingTimeInterval(3 * 24 * 3600)
                    ),
                ],
                fetchedAt: now,
                status: .demo
            ),
            ProviderSnapshot(
                kind: .antigravity,
                plan: "Pro",
                windows: [
                    LimitWindow(
                        id: "gemini-3.1-pro",
                        label: "Gemini 3.1 Pro",
                        usedPercent: 36,
                        resetsAt: now.addingTimeInterval(2 * 24 * 3600)
                    ),
                    LimitWindow(
                        id: "claude-sonnet-4.6",
                        label: "Claude Sonnet 4.6",
                        usedPercent: 22,
                        resetsAt: now.addingTimeInterval(2 * 24 * 3600)
                    ),
                ],
                fetchedAt: now,
                status: .demo
            ),
            ProviderSnapshot(
                kind: .grok,
                plan: "SuperGrok",
                windows: [
                    LimitWindow(
                        id: "credits",
                        label: "Grok Build",
                        usedPercent: 47,
                        resetsAt: now.addingTimeInterval(5 * 24 * 3600)
                    ),
                ],
                fetchedAt: now,
                status: .demo
            ),
        ]
    }
}
