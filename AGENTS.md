# Working on Notch Police

Read this before changing anything, whether you are a person or an agent. It is the short version of how the repo is built, tested, and verified without a screen, plus the handful of rules that are not negotiable. `CONTRIBUTING.md` has the ground rules in full; `README.md` has the product.

## What it is

A macOS menu bar app (Swift, SwiftUI hosted in an `NSPanel`) that pins a black bezel "notch" to a screen edge showing **remaining** quota for Claude, Cursor, ChatGPT, Antigravity, and Grok as rings. It never signs in: each provider borrows a session the official tool already keeps on the Mac and calls that product's own usage endpoint. Remaining-first is the product. If you add a number, the first thing people see is how much is left.

## Layout

| Path | What lives there |
|---|---|
| `Sources/NotchPoliceCore/` | Everything without UI. One `*Usage.swift` parser and one `*Provider.swift` per agent; `Keychain`; `Preferences`; `UsageStore` (polling enabled providers only, backoff, persisted remaining samples); `Forecast` (pace); `Handover` and `SessionContext` (the context copy and the summary prompt); `Fixtures` (demo data). |
| `Sources/NotchPolice/` | The app. `NotchPanel` (window and placement), `NotchRootView` (rings, hover, context menu), `RingCell`, `TooltipCard`, `BezelNotchShape`, `SettingsView`, `NotchPoliceApp` (menu bar extra, Settings scene). |
| `Tests/SelfTests.swift` | The whole suite, compiled into the core module so it can reach internal helpers. `Scripts/TestHost.swift` runs it. |
| `Scripts/` | `build.sh`, `bundle.sh`, `test.sh`, `generate-icon.py`. There is no `Package.swift` and no Xcode project. |
| `Resources/` | `Info.plist`, `AppIcon.icns`, and the provider logos, which are trademarks (see `TRADEMARKS.md`). |

## Commands

```sh
make test     # builds core + tests and runs them; one line per check, "All tests passed." at the end
make demo     # debug build on sample data (NOTCH_POLICE_DEMO=1); reads no credentials
make run      # debug build on live readings from whatever is signed in locally
make release  # ARCHS="arm64 x86_64" for a universal binary
make icon     # regenerate AppIcon.icns from Resources/AppIcon.png (needs Pillow and numpy)
```

`make run` and `make demo` kill the running instance, rebuild, and relaunch. `pkill -x NotchPolice` stops it. Only the Command Line Tools are needed. CI (`.github/workflows/test.yml`) runs `make test` and a universal release build on `macos-15`.

## Verifying without looking at the screen

An agent usually cannot see the notch. These checks work from a shell.

- **Tests.** `make test`. Add a `check("name", condition)` line in `Tests/SelfTests.swift` for anything you change. Parser changes need a fixture.
- **Is it running, and in which mode?** `pgrep -x NotchPolice`, then `defaults export com.notchpolice.mac - | plutil -p -` for the saved preferences, `demo` included. `NOTCH_POLICE_DEMO=1` is a launch-only override and never persists.
- **Logs.** The app deliberately logs nothing of its own (rule 4 below). System-side events are in the unified log, but call the binary by path, because zsh has a builtin named `log` that silently shadows it:
  `/usr/bin/log show --predicate 'process == "NotchPolice"' --last 5m --style compact`
  Keychain decisions are logged by `securityd` under category `kcacl`.
- **Keychain read works?** `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w | wc -c` prints a byte count without showing the secret. It is the same path the app uses, so if that prompts, the app would too.
- **Window geometry.** The notch is an `NSPanel` owned by the app; `CGWindowListCopyWindowInfo` from a short Swift script lists its bounds without any permission. Screenshots need Screen Recording permission for the calling terminal, which is usually not granted.
- **Settings scene.** `open -a NotchPolice` while it is running triggers the Dock re-open path, which opens Settings through the same code as the notch's context menu.

## Rules that are not negotiable

1. **Remaining is the number.** Used is a setting.
2. **Parsers before providers.** A new JSON shape gets a fixture and a test first, then the network adapter.
3. **No invented percentages.** Unknown, unauthenticated, or malformed becomes a status, never a guessed ring.
4. **Never log or print tokens, cookies, Keychain payloads, or transcripts.** Lengths and HTTP statuses only.
5. **`Keychain` goes through `/usr/bin/security` on purpose.** The Claude item's access list names that tool and nothing else, so the Security framework from an ad-hoc build triggers a two-step permission dialog after every rebuild. The header comment in `Keychain.swift` has the full reasoning. Do not "modernise" it back.
6. **The Claude OAuth write-back must survive.** Refresh tokens rotate; dropping one signs the user out of Claude Code. Keep the round-trip test.
7. **Borrow, don't sign in.** No username/password forms and no OAuth flows of our own.
8. **Original code only.** Do not paste from other projects, whatever the license.

## Adding a provider

1. `ProviderKind`: the case, display name, short name, dashboard URL, sign-in hint and command. If the plan has more than one limit window, add `stableRingWindows` so Settings can pin the ring before the first poll.
2. `XUsage.swift`: the parser, pure functions from JSON to `[LimitWindow]`. Fixture and tests in `SelfTests.swift`.
3. `XProvider.swift`: find the local session, call the usage endpoint, return a `ProviderSnapshot`. 401 is `.needsAuth`, 429 is `.rateLimited`, anything else is `.error`. Never a guessed number.
4. `Fixtures.demoSnapshots()`: a demo entry. A test checks that every provider has one.
5. `ProviderMark`: a mark for the ring. Logos are trademarks; see `TRADEMARKS.md`.
6. `UsageStore.poll`, and `SessionContext` if the tool keeps local transcripts.
7. The README "What it reads" table, and an "Honest caveats" paragraph if the provider has quirks.

## Gotchas

- Ad-hoc signed builds get a new cdhash every time. Nothing depends on it now that Keychain goes through `security`, but it is why that decision exists.
- Endpoints are unofficial. When one changes shape, the fix is a fixture plus a parser change, not a workaround in the UI.
- Antigravity is loopback-only and its port changes per launch; `LocalhostTrust` pins its self-signed certificate to `127.0.0.1`.
- Claude's usage endpoint returns 429 readily. `Backoff` handles it per provider; do not add retries elsewhere.
- Horizontal edges (top and bottom) lay ring and label side by side because the pill is only `NotchMetrics.depth` tall. A vertical cell does not fit there and gets clipped by the bezel.
- The window resizes when the tooltip shows. `NotchWindowController.reposition` returns early when nothing changed; keep it that way or the notch judders under the cursor.

## Releasing

See the Release section of `CONTRIBUTING.md`: bump `Info.plist`, tag `v0.x.y`, build universal, bundle, zip.
