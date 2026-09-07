# Notch Police

[![test](https://github.com/theroofkashyap/notch-police/actions/workflows/test.yml/badge.svg)](https://github.com/theroofkashyap/notch-police/actions/workflows/test.yml)

A macOS edge notch that answers the question you actually care about: **how much agent usage is left?**

Claude, Cursor, ChatGPT, Antigravity, and Grok sit on the side of your screen as remaining-quota rings. Hover a ring for every limit window and when it resets. If you are burning quota fast, the tooltip says when you will hit the wall.

What it is built around:

- **Remaining first.** The number you see is how much is left. Used is a setting.
- **Pace.** "Empty in 22 min", fitted from the recent drop in remaining.
- **Alerts.** An optional notification when remaining falls below a threshold you set.
- **macOS 14+**, Intel and Apple silicon. Build it yourself; releases on GitHub.
- **Five providers**, each read from a session your Mac already holds. No sign-in form.

## What it looks like

A black bezel notch welded to a screen edge — inverse corners, thin brass hairline. Each agent is a ring that empties as remaining quota falls.

- **Green** — plenty left
- **Amber** — under 50% left
- **Red, pulsing** — under 20% left, or empty

Hover for 5-hour / weekly / cycle windows. Once remaining drops to your alert threshold, the card shows **Credits dying — copy context** — that puts a handover prompt plus the latest local session on the clipboard so you can paste into another agent. Next to it, **Copy summary prompt** goes the other way: paste that into the chat that is running out, and the agent that still holds the whole conversation writes the handover itself. Click a ring to open that product’s usage page. Right-click for Refresh, Copy context, Copy summary prompt, Preview context, Settings, Hide for an hour, Quit.

### The handover is your own conversation text

Copy context reads the most recent local transcript available from Claude Code, Cursor, Codex, Antigravity, or Grok CLI and puts the last few turns on the clipboard. Two things follow from that:

- **It is scoped to one project.** The newest transcript on the machine is often from a different repository than the one in front of you, so candidates are grouped by the working directory that produced them and the group holding the most recently touched transcript wins. The chosen project is printed on the button before you click and again in the pasted text.
- **Read it before pasting.** Nothing is redacted. Right-click the notch and choose **Preview context…** to see the exact text, with its length, before it goes anywhere.

**Copy summary prompt** puts none of your conversation on the clipboard. It is a prompt asking the current agent for a handover brief — goal, done, in progress, decisions, next steps, gotchas, commands — with a header line so its answer can be pasted into the next agent as-is. When the chat still has enough credits to answer, this is the better handover; Copy context is the fallback for when it does not.

## What it reads

Notch Police **never signs you in**. It borrows a session the tool on your Mac already holds, and only talks to that product’s own usage endpoint.

| Agent | Where the session lives | What you see |
|---|---|---|
| **Claude** | Claude Code Keychain item `Claude Code-credentials`, or `~/.claude/.credentials.json` | 5-hour session and weekly remaining, same family of numbers as `/usage` |
| **Cursor** | The editor’s `state.vscdb` access token | Included and API remaining, with spend as context |
| **ChatGPT** | `~/.codex/auth.json` from `codex login` | 5-hour and weekly remaining |
| **Antigravity** | The app, IDE, or `agy` CLI language server on `127.0.0.1` | Per-model remaining and reset times |
| **Grok** | `~/.grok/auth.json` from `grok login` | Grok Build’s weekly credits and reset |

If a session is missing — or Antigravity is not running — that ring shows a dash and the hover card tells you what to open or how to sign in. Demo data is a toggle in Settings (`NOTCH_POLICE_DEMO=1` on launch).

### Honest caveats

No vendor publishes a supported “remaining %” SDK for these consumer plans. The adapters call the same unofficial endpoints the official apps already call. Those shapes can change without notice. A throttled or failed poll keeps the previous reading rather than blanking the ring, and a missing session shows `needs auth` — the notch will not invent a percentage.

**Claude refresh tokens rotate, and Claude Code rotates them too.** If Notch Police refreshes the OAuth token, it re-reads the stored credentials and only writes back when the refresh token it started from is still there. If Claude Code rotated in the meantime, the write is abandoned rather than replacing a newer token with an older one and locking both apps out.

**Notch Police never asks for Keychain permission.** It reads and writes that item through `/usr/bin/security`, the Apple tool Claude Code created it with and the only client the item’s access list names, so no build of Notch Police triggers the “Always Allow” dialog — not even an ad-hoc one straight out of `make run`. If macOS ever does show a Keychain dialog, it is asking you to unlock the *login keychain*, not to grant Notch Police access; unlock it and the ring recovers on the next poll.

**Cursor’s included allowance running out does not mean you are cut off.** Cursor keeps serving requests from bonus credits, so the rings follow the percentages Cursor’s own UI quotes and treat spend dollars as context. An exhausted $20 allowance will not show as an empty quota.

**ChatGPT desktop does not expose a readable session.** Use Codex / ChatGPT CLI login (`codex login`). That is the same ChatGPT plan quota.

**Antigravity is local-only.** Its port is chosen afresh every launch and its TLS certificate is self-signed. Notch Police discovers the owning process and listening ports, extracts the IDE’s CSRF token when required, and trusts that certificate only on loopback. No Antigravity credential is copied or sent elsewhere. The ring is available while Antigravity or `agy` is running.

**Grok means Grok Build here, not Grok used through Cursor.** The ring reads the weekly credits endpoint used by Grok CLI’s own `/usage` command. Grok models selected inside Cursor still consume Cursor’s allowance and therefore belong to the Cursor ring.

Polling is gentle (90s by default). If a provider returns 429, that provider alone stops being polled — 60s, then 120s, up to 15 minutes, honouring `Retry-After` when it asks for longer.

## Build

macOS 14+ and the Xcode Command Line Tools. Full Xcode is not required, and there is no `Package.swift`: the build is three shell scripts, so `xcode-select --install` is the whole setup.

```sh
make demo         # sample remaining data — notch on the right edge
make run          # live readings from all installed/signed-in providers
make test
```

`make` builds for the machine it runs on. For a universal binary:

```sh
ARCHS="arm64 x86_64" ./Scripts/build.sh release
```

`AppIcon.icns` is committed, so a normal build needs no image tooling. After
editing `Resources/AppIcon.png`, run `make icon` (needs Pillow and numpy) —
it masks the square art to the macOS squircle on Apple's 824-of-1024 icon grid.

After `make demo`, you should see:

1. **NP** (or `CL 12  CU …`) in the menu bar
2. A black pill on the **right** edge of the screen, vertically centered

Settings opens by itself on the very first launch only, so the app does not steal focus every time it starts.

If the notch is easy to miss against a dark wallpaper, click the menu bar extra and choose **Settings…**. Quit from there or from the extra.

The app lands at `.build/NotchPolice.app`. Drag it to `/Applications` if you want it to stay.

There is no Developer ID requirement for local builds, and ad-hoc builds do not trigger Keychain prompts: the Claude item is read through `/usr/bin/security`, so the app’s own signature never enters into it.

## Settings

- Edge: right, left, top, bottom
- Remaining vs used
- Per-agent on/off (off means that provider’s local data source is not read)
- Poll interval
- Notify when remaining drops below N%
- Dock icon on/off
- Demo data

## Architecture

- `Sources/NotchPoliceCore` — parsers, providers, remaining forecast, preferences
- `Sources/NotchPolice` — bezel notch `NSPanel`, rings, tooltip, settings
- `Tests` — response-shape fixtures and unit tests, compiled into the same module as the core so they can reach internal helpers without widening the shipped API

Each provider returns a `ProviderSnapshot` with one or more `LimitWindow`s. The ring shows the **tightest** window (least remaining). Percentages are normalised per response rather than per value, because a lone `1.0` is ambiguous between one percent and a full quota — a payload only counts as 0–1 when every reading in it is under 1.

Forecast is a least-squares fit over remaining samples from the last few hours. It discards samples from before a quota reset, and stays quiet until it has at least two minutes of real decline. Samples live in memory, so pace appears a few minutes after launch rather than immediately.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). New agents should land as a parser with fixtures first, then a provider that only reads a local session.

## License

[MIT](LICENSE) for this project's code.

The provider logos in `Resources/Providers` are **not** covered by that grant — they belong to Anthropic, Cursor, OpenAI, Google, and xAI, and are included only to identify which ring is which. See [TRADEMARKS.md](TRADEMARKS.md) before you fork or redistribute.
