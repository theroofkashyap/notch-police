# Contributing

Notch Police is MIT-licensed. Small, tested changes are welcome.

## Setup

```sh
make test
make demo
```

Command Line Tools are enough. Full Xcode is not required.

## Ground rules

1. **Remaining is the default.** If you add UI, the number people see first should be how much is left, not how much was burned.
2. **Parsers before providers.** Add a fixture and a `make test` case for any new JSON shape. Do not ship a network adapter without a pinned parse.
3. **No invented percentages.** Unknown, unauthenticated, or malformed responses become a status, never a guessed ring.
4. **Do not log tokens, cookies, or Keychain payloads.** Lengths and HTTP statuses are fine.
5. **Claude OAuth refresh must persist.** If you touch `ClaudeProvider` / `ClaudeUsage.mergeRefreshedOAuth`, keep the round-trip test and write the new refresh token back before using it. Dropping a rotated refresh token signs the user out of Claude Code.
6. **Borrow, don't sign in.** Prefer a credential or loopback service the official app already owns. Do not add a username/password form.
7. **Stay original.** Do not paste code from other projects, whatever its license. Edge notches, borrowed local sessions, and unofficial usage endpoints are the category, not anyone's property; the code here should be ours.

## Layout of a provider

```
Kind  →  owned local source  →  official usage endpoint  →  [LimitWindow]
```

The ring uses the tightest window. Extra windows belong on the hover card.

## Release

Bump `CFBundleShortVersionString` / `CFBundleVersion` in `Resources/Info.plist`. Tag `v0.x.y`. Build with `ARCHS="arm64 x86_64" ./Scripts/build.sh release`, then run `./Scripts/bundle.sh release` and zip `.build/NotchPolice.app` (after Developer ID signing/notarization if you are distributing beyond your own Mac).
