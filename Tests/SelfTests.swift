import Foundation

public enum PoliceSelfTests {
    public static func run() -> Int {
        var failed = 0
        func check(_ name: String, _ ok: Bool) {
            if ok {
                print("ok   \(name)")
            } else {
                print("FAIL \(name)")
                failed += 1
            }
        }

        do {
            let json = """
            {
              "five_hour": { "utilization": 27.0, "resets_at": "2026-09-07T08:29:59Z" },
              "seven_day": { "utilization": 11.0, "resets_at": "2026-09-13T11:59:59Z" },
              "limits": [
                {
                  "kind": "weekly_scoped",
                  "percent": 10,
                  "is_active": true,
                  "resets_at": "2026-09-13T11:59:59Z",
                  "scope": { "model": { "display_name": "Fable" } }
                }
              ]
            }
            """.data(using: .utf8)!
            let object = try JSONSerialization.jsonObject(with: json) as! [String: Any]
            let parsed = ClaudeUsage.parse(object: object, plan: "Max 5x")
            check("claude window count", parsed.windows.count == 3)
            check("claude remaining", parsed.windows[0].remainingPercent == 73)
            check("claude session label", parsed.windows[0].label == "5-hour session")
            check("claude scoped label", parsed.windows[2].label == "Fable weekly")
        } catch {
            check("claude parse threw \(error)", false)
        }

        let fraction = ClaudeUsage.parse(object: [
            "five_hour": ["utilization": 0.27],
            "seven_day": ["utilization": 0.11],
        ])
        check("claude fraction scale", abs(fraction.windows[0].usedPercent - 27) < 0.01)

        // A fresh window at 1% used must not be mistaken for an exhausted one:
        // the old per-value heuristic scaled anything <= 1.5 up to 100%.
        let lowPercent = ClaudeUsage.parse(object: [
            "five_hour": ["utilization": 1.0],
            "seven_day": ["utilization": 12.0],
        ])
        check("claude 1 percent stays 1", abs(lowPercent.windows[0].usedPercent - 1) < 0.01)
        check("claude 1 percent not empty", lowPercent.windows[0].remainingPercent == 99)

        check("scale percent when mixed", PercentScale.detect([0.4, 12]) == .percent)
        check("scale fraction when all sub-one", PercentScale.detect([0.4, 0.1]) == .fraction)
        check("scale percent at exactly one", PercentScale.detect([1.0]) == .percent)
        check("scale percent when empty", PercentScale.detect([]) == .percent)

        let existing: [String: Any] = [
            "mcpOAuth": ["keep": true],
            "claudeAiOauth": [
                "accessToken": "old",
                "refreshToken": "old-refresh",
                "expiresAt": 1,
            ],
        ]
        let merged = ClaudeUsage.mergeRefreshedOAuth(
            existing: existing,
            accessToken: "new-access",
            refreshToken: "new-refresh",
            expiresIn: 100,
            scope: "user:inference user:profile",
            now: Date(timeIntervalSince1970: 1_000)
        )
        let oauth = merged["claudeAiOauth"] as! [String: Any]
        check("merge access", oauth["accessToken"] as? String == "new-access")
        check("merge refresh", oauth["refreshToken"] as? String == "new-refresh")
        check("merge expiry", oauth["expiresAt"] as? Int == 1_100_000)
        check("merge preserves extras", (merged["mcpOAuth"] as? [String: Any])?["keep"] as? Bool == true)

        do {
            // Shape captured from the live endpoint: the included allowance is
            // spent in full while bonus credits keep the account working, and
            // Cursor's own UI still reports 10% and 31% used.
            let json = """
            {
              "billingCycleEnd": "1789475907000",
              "planUsage": {
                "totalSpend": 4927,
                "includedSpend": 2000,
                "bonusSpend": 2927,
                "limit": 2000,
                "autoPercentUsed": 7.89,
                "apiPercentUsed": 30.55,
                "totalPercentUsed": 9.95
              }
            }
            """.data(using: .utf8)!
            let object = try JSONSerialization.jsonObject(with: json) as! [String: Any]
            let parsed = CursorUsage.parse(object: object, membership: "pro")
            check("cursor plan", parsed.plan == "Pro")
            let included = parsed.windows.first { $0.id == "included" }
            let api = parsed.windows.first { $0.id == "api" }
            check("cursor included percent", abs((included?.usedPercent ?? 0) - 9.95) < 0.01)
            check("cursor api percent", abs((api?.usedPercent ?? 0) - 30.55) < 0.01)
            // The whole point: an exhausted included allowance is not empty.
            check("cursor not falsely empty", (included?.remainingPercent ?? 0) > 89)
            check("cursor tightest is api", parsed.windows.max { $0.usedPercent < $1.usedPercent }?.id == "api")
            check("cursor spend detail", included?.detail == "$20 of $20 included · $29 bonus")
        } catch {
            check("cursor parse threw \(error)", false)
        }

        do {
            let json = """
            {
              "plan_type": "plus",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 18,
                  "limit_window_seconds": 18000,
                  "reset_at": 1890000000
                },
                "secondary_window": {
                  "used_percent": 44,
                  "limit_window_seconds": 604800,
                  "reset_at": 1890500000
                }
              }
            }
            """.data(using: .utf8)!
            let object = try JSONSerialization.jsonObject(with: json) as! [String: Any]
            let parsed = ChatGPTUsage.parse(object: object)
            check("chatgpt plan", parsed.plan == "Plus")
            check("chatgpt 5h", parsed.windows[0].label == "5-hour")
            check("chatgpt remaining", parsed.windows[0].remainingPercent == 82)
            check("chatgpt weekly", parsed.windows[1].label == "Weekly")
        } catch {
            check("chatgpt parse threw \(error)", false)
        }

        let antigravityStatus = """
        {
          "code": 0,
          "userStatus": {
            "userTier": { "name": "Antigravity Pro" },
            "cascadeModelConfigData": {
              "clientModelConfigs": [
                {
                  "label": "Gemini 3.1 Pro",
                  "modelOrAlias": { "model": "gemini-3.1-pro" },
                  "quotaInfo": {
                    "remainingFraction": 0.64,
                    "resetTime": "2026-09-12T08:21:18.802818+00:00"
                  }
                },
                {
                  "label": "Claude Sonnet 4.6",
                  "modelOrAlias": { "model": "claude-sonnet-4.6" },
                  "quotaInfo": {
                    "remainingFraction": 0.22,
                    "resetTime": "2026-09-12T08:21:18Z"
                  }
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!
        let antigravity = AntigravityUsage.parseUserStatus(antigravityStatus)
        check("antigravity plan", antigravity?.plan == "Antigravity Pro")
        check("antigravity model windows", antigravity?.windows.count == 2)
        check(
            "antigravity remaining fraction",
            abs((antigravity?.windows[0].remainingPercent ?? 0) - 64) < 0.01
        )
        check(
            "antigravity tightest model",
            antigravity?.windows.max { $0.usedPercent < $1.usedPercent }?.id
                == "claude-sonnet-4.6"
        )

        let antigravitySummary = """
        {
          "response": {
            "groups": [{
              "displayName": "Gemini family",
              "buckets": [{
                "bucketId": "gemini-weekly",
                "displayName": "Weekly Limit Remaining",
                "remainingFraction": 0.75,
                "resetTime": "2026-09-14T00:00:00Z"
              }]
            }]
          }
        }
        """.data(using: .utf8)!
        let summary = AntigravityUsage.parseQuotaSummary(antigravitySummary)
        check("antigravity summary label", summary?.windows.first?.label == "Gemini family")
        check("antigravity summary used", summary?.windows.first?.usedPercent == 25)

        let badAntigravity = """
        {"code":0,"userStatus":{"cascadeModelConfigData":{"clientModelConfigs":[{
          "label":"Broken","modelOrAlias":{"model":"broken"},
          "quotaInfo":{"remainingFraction":1.2}
        }]}}}
        """.data(using: .utf8)!
        check(
            "antigravity rejects impossible fraction",
            AntigravityUsage.parseUserStatus(badAntigravity)?.windows.isEmpty == true
        )

        let antigravityProcess = """
          123 /Applications/Antigravity.app/Contents/language_server_macos_arm \
          --app_data_dir antigravity --csrf_token secret --https_server_port 0
        """
        let endpoint = AntigravityBridge.discover(
            processTable: antigravityProcess,
            listeningPorts: { $0 == 123 ? [41002, 41001] : [] }
        )
        check("antigravity finds language server", endpoint?.ports == [41001, 41002])
        check("antigravity extracts csrf", endpoint?.csrfToken == "secret")

        let cliEndpoint = AntigravityBridge.discover(
            processTable: "321 /usr/local/bin/agy serve",
            listeningPorts: { $0 == 321 ? [42000] : [] }
        )
        check("antigravity finds agy", cliEndpoint?.ports == [42000])
        check("antigravity cli needs no csrf", cliEndpoint?.csrfToken == "")
        check(
            "antigravity ignores unrelated server",
            AntigravityBridge.discover(
                processTable: "444 /tmp/language_server --csrf_token nope",
                listeningPorts: { _ in [43000] }
            ) == nil
        )
        let lsof = """
        COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        server  123 me   8u IPv4 0x0 0t0 TCP 127.0.0.1:41001 (LISTEN)
        server  123 me   9u IPv6 0x0 0t0 TCP [::1]:41002 (LISTEN)
        """
        check(
            "antigravity parses listening ports",
            AntigravityBridge.parsePorts(fromLSOF: lsof) == [41001, 41002]
        )

        let grokJSON = """
        {
          "config": {
            "currentPeriod": {
              "type": "USAGE_PERIOD_TYPE_WEEKLY",
              "end": "2026-09-12T08:21:18.802818+00:00"
            },
            "creditUsagePercent": 8.0,
            "productUsage": [
              { "product": "GrokBuild", "usagePercent": 8.0 }
            ]
          }
        }
        """.data(using: .utf8)!
        let grok = GrokUsage.parse(data: grokJSON)
        check("grok credits window", grok.count == 1 && grok[0].id == "credits")
        check("grok label", grok.first?.label == "Grok Build")
        check("grok remaining", grok.first?.remainingPercent == 92)
        check("grok weekly reset", grok.first?.resetsAt != nil)

        let grokProductsOnly = """
        {"config":{"productUsage":[{"product":"GrokBuild","usagePercent":33}],
        "billingPeriodEnd":"2026-09-12T08:21:18Z"}}
        """.data(using: .utf8)!
        let grokFallback = GrokUsage.parse(data: grokProductsOnly)
        check("grok product fallback", grokFallback.first?.usedPercent == 33)
        check("grok rejects empty config", GrokUsage.parse(data: Data(#"{"config":{}}"#.utf8)).isEmpty)
        check("grok humanizes product", GrokUsage.humanize("GrokBuild") == "Grok Build")

        let trustedGrok: [String: Any] = [
            "https://auth.x.ai::cli": [
                "key": "trusted",
                "expires_at": "2099-09-12T08:21:18Z",
            ],
            "https://customer.example::cli": [
                "key": "private",
                "expires_at": "2099-09-12T08:21:18Z",
            ],
        ]
        check("grok only picks xai issuer", GrokCredentials.pick(from: trustedGrok)?["key"] as? String == "trusted")
        check(
            "grok rejects customer idp",
            GrokCredentials.pick(from: [
                "customer": [
                    "key": "private",
                    "oidc_issuer": "https://customer.example",
                ],
            ]) == nil
        )
        check(
            "demo covers every provider",
            Fixtures.demoSnapshots().map(\.kind) == ProviderKind.allCases
        )
        check(
            "every provider enabled by default",
            ProviderKind.allCases.allSatisfy(Preferences.default.isEnabled)
        )

        check(
            "revoked session covers invalid_grant and unauthorized",
            ClaudeAuthError.isSessionRevoked(400)
                && ClaudeAuthError.isSessionRevoked(401)
                && ClaudeAuthError.isSessionRevoked(403)
        )
        check(
            "transient statuses are not a revoked session",
            !ClaudeAuthError.isSessionRevoked(429)
                && !ClaudeAuthError.isSessionRevoked(500)
                && !ClaudeAuthError.isSessionRevoked(200)
        )

        do {
            let suite = "notchpolice.tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let plain = PreferenceStore(defaults: defaults, environment: [:])
            let override = PreferenceStore(defaults: defaults, environment: ["NOTCH_POLICE_DEMO": "1"])

            var live = plain.load()
            live.edge = .left
            plain.save(live)
            check("demo override applies at launch", override.load().demo)
            override.save(override.load())
            check("demo override does not persist", plain.load().demo == false)
            check("demo override keeps other settings", plain.load().edge == .left)

            var off = override.load()
            off.demo = false
            override.save(off)
            check("demo off under override persists", plain.load().demo == false)

            var on = plain.load()
            on.demo = true
            plain.save(on)
            override.save(override.load())
            check("demo override keeps a saved on", plain.load().demo)
        }

        do {
            // A scratch keychain in a temp directory: never the login keychain.
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("notchpolice-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let path = dir.appendingPathComponent("scratch.keychain-db").path
            func security(_ args: [String]) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
                p.arguments = args
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                try? p.run()
                p.waitUntilExit()
            }
            defer {
                security(["delete-keychain", path])
                try? FileManager.default.removeItem(at: dir)
            }
            security(["create-keychain", "-p", "scratch", path])

            let service = "notchpolice.test.\(UUID().uuidString)"
            let json = Data(#"{"claudeAiOauth":{"accessToken":"a\"b\\c d","refreshToken":"r/t=","expiresAt":1}}"#.utf8)
            try Keychain.updateGenericPassword(service: service, account: "tester", data: json, keychain: path)
            let back = try Keychain.readGenericPassword(service: service, keychain: path)
            check("keychain round-trip via security tool", back.data == json && back.account == "tester")

            let rotated = Data(#"{"claudeAiOauth":{"accessToken":"n","refreshToken":"r2","expiresAt":2}}"#.utf8)
            try Keychain.updateGenericPassword(service: service, account: back.account, data: rotated, keychain: path)
            check(
                "keychain update in place",
                try Keychain.readGenericPassword(service: service, keychain: path).data == rotated
            )

            var missing = false
            do {
                _ = try Keychain.readGenericPassword(service: "\(service).missing", keychain: path)
            } catch KeychainError.notFound {
                missing = true
            }
            check("keychain missing item is notFound", missing)
        } catch {
            check("keychain scratch test threw \(error)", false)
        }

        let start = Date(timeIntervalSince1970: 0)
        let pace = Forecast.pace(
            samples: [
                RemainingSample(at: start, remaining: 50),
                RemainingSample(at: start.addingTimeInterval(600), remaining: 40),
            ],
            now: start.addingTimeInterval(600),
            minimumSpan: 120
        )
        check("pace minutes", pace?.minutesToEmpty == 40)
        check("pace copy", pace?.copy == "Empty in 40 min")

        let blip = Forecast.pace(
            samples: [
                RemainingSample(at: start, remaining: 80),
                RemainingSample(at: start.addingTimeInterval(10), remaining: 79),
            ],
            minimumSpan: 120
        )
        check("pace ignores blips", blip == nil)

        // Samples from before a quota reset describe a window that is gone.
        let acrossReset = Forecast.sinceLastReset([
            RemainingSample(at: start, remaining: 30),
            RemainingSample(at: start.addingTimeInterval(300), remaining: 8),
            RemainingSample(at: start.addingTimeInterval(600), remaining: 100),
            RemainingSample(at: start.addingTimeInterval(900), remaining: 90),
        ])
        check("pace drops pre-reset samples", acrossReset.count == 2)
        check("pace restarts after reset", acrossReset.first?.remaining == 100)

        // Fitted across every sample rather than just the endpoints, so a
        // flat final poll cannot drag the estimate on its own. Endpoints alone
        // would say 28 minutes here.
        let noisy = Forecast.pace(
            samples: [
                RemainingSample(at: start, remaining: 60),
                RemainingSample(at: start.addingTimeInterval(300), remaining: 50),
                RemainingSample(at: start.addingTimeInterval(600), remaining: 40),
                RemainingSample(at: start.addingTimeInterval(900), remaining: 39),
            ],
            minimumSpan: 120
        )
        check("pace fits all samples", noisy?.minutesToEmpty == 27)

        var backoff = Backoff(minimum: 60, maximum: 600)
        let first = backoff.record(now: start)
        check("backoff starts at minimum", first == start.addingTimeInterval(60))
        // The old code derived the next wait from an already-expired deadline,
        // which pinned it at the minimum forever.
        let second = backoff.record(now: start.addingTimeInterval(120))
        check("backoff doubles", second == start.addingTimeInterval(120 + 120))
        check("backoff blocks until deadline", backoff.isBlocked(now: start.addingTimeInterval(150)))
        check("backoff clears after deadline", !backoff.isBlocked(now: start.addingTimeInterval(500)))
        let hinted = backoff.record(retryAfter: start.addingTimeInterval(9_999), now: start)
        check("backoff honours server hint", hinted == start.addingTimeInterval(9_999))
        backoff.reset()
        check("backoff reset", !backoff.isBlocked(now: start))
        check("backoff restarts at minimum", backoff.record(now: start) == start.addingTimeInterval(60))

        let now = Date(timeIntervalSince1970: 1_000_000)
        check("reset copy", ResetCopy.format(now.addingTimeInterval(51 * 60), now: now) == "in 51 min")
        check("band clear", UsageBand.fromRemaining(80) == .clear)
        check("band warning", UsageBand.fromRemaining(30) == .warning)
        check("band critical", UsageBand.fromRemaining(10) == .critical)
        check("band empty", UsageBand.fromRemaining(0) == .empty)
        check("band unknown", UsageBand.fromRemaining(nil) == .unknown)

        let jsonl = """
        {"type":"ai-title","aiTitle":"Notch Police handover"}
        {"type":"user","message":{"role":"user","content":"Ship the copy-context button."}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read"},{"type":"text","text":"Adding a clipboard handover next."}]}}
        """
        let excerpt = SessionContext.parseJSONL(jsonl, source: "test")
        check("jsonl title", excerpt?.title == "Notch Police handover")
        check("jsonl turns", excerpt?.turns.count == 2)
        check("jsonl skips tools", excerpt?.turns.last?.text == "Adding a clipboard handover next.")

        let dying = ProviderSnapshot(
            kind: .claude,
            plan: "Max",
            windows: [LimitWindow(id: "session", label: "5-hour session", usedPercent: 88, resetsAt: now.addingTimeInterval(18 * 60))],
            fetchedAt: now,
            status: .ok
        )
        check("dying flag", dying.isDying(below: 15))
        check("dying respects threshold", !dying.isDying(below: 10))
        let pack = Handover.make(snapshot: dying, pace: nil, excerpt: excerpt, now: now)
        check("handover remaining", pack.contains("12% left"))
        check("handover prompt", pack.contains("switching agents"))
        check("handover transcript", pack.contains("Ship the copy-context button."))

        var scoped = excerpt
        scoped?.project = "notch-police"
        let scopedPack = Handover.make(snapshot: dying, pace: nil, excerpt: scoped, now: now)
        check("handover names project", scopedPack.contains("Project: notch-police"))

        let prompt = Handover.summaryPrompt(
            snapshot: dying,
            pace: Pace(minutesToEmpty: 22, copy: "Empty in 22 min"),
            project: "notch-police"
        )
        check("summary prompt names provider", prompt.contains("My Claude credits"))
        check("summary prompt states remaining and pace", prompt.contains("12% left, empty in 22 min"))
        check("summary prompt names project", prompt.contains("Project: notch-police"))
        check("summary prompt asks for next steps", prompt.contains("**Next steps**"))
        check(
            "summary prompt sets the handover header",
            prompt.contains("\"Handover from a Claude session on notch-police\"")
        )
        check("summary prompt carries no transcript", !prompt.contains("Ship the copy-context button."))
        let bare = Handover.summaryPrompt(snapshot: dying, pace: nil, project: nil)
        check(
            "summary prompt without project",
            bare.contains("\"Handover from a Claude session\"") && !bare.contains("Project:")
        )

        // Claude and Cursor slug the same working directory differently.
        check(
            "project key normalises across providers",
            ProjectKey(directoryName: "-Users-me-code-thing").normalized
                == ProjectKey(directoryName: "Users-me-code-thing").normalized
        )
        check("project display drops home", ProjectKey(directoryName: "-Users-me-code-thing").displayName == "code-thing")

        let transcripts = [
            SessionContext.Transcript(
                url: URL(fileURLWithPath: "/tmp/other.jsonl"),
                modified: now,
                project: ProjectKey(directoryName: "-Users-me-other"),
                kind: .claude
            ),
            SessionContext.Transcript(
                url: URL(fileURLWithPath: "/tmp/active.jsonl"),
                modified: now.addingTimeInterval(-60),
                project: ProjectKey(directoryName: "-Users-me-active"),
                kind: .claude
            ),
            SessionContext.Transcript(
                url: URL(fileURLWithPath: "/tmp/cursor-active.jsonl"),
                modified: now.addingTimeInterval(10),
                project: ProjectKey(directoryName: "Users-me-active"),
                kind: .cursor
            ),
        ]
        let active = SessionContext.activeProject(in: transcripts)
        check("active project is newest", active?.displayName == "active")
        // Claude's newest transcript belongs to another repo; scoping to the
        // active project is what stops one project's context leaking into it.
        let ranked = SessionContext.rank(transcripts, for: .claude, preferring: active)
        check("rank prefers active project", ranked.first?.lastPathComponent == "active.jsonl")
        let unmatched = SessionContext.rank(transcripts, for: .claude, preferring: ProjectKey(directoryName: "nope"))
        check("rank falls back to newest", unmatched.first?.lastPathComponent == "other.jsonl")

        print(failed == 0 ? "All tests passed." : "\(failed) test(s) failed.")
        return failed
    }
}
