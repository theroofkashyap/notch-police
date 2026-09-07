# Security

Notch Police reads credentials that other tools already hold on your Mac — Claude Code's Keychain item, Cursor's `state.vscdb`, `~/.codex/auth.json`, `~/.grok/auth.json`, and Antigravity's loopback language server. Anything that could leak, log, or mishandle those is in scope.

## Reporting

Do not open a public issue for a vulnerability. Use GitHub's private vulnerability reporting:

https://github.com/theroofkashyap/notch-police/security/advisories/new

Include the macOS version, the provider involved, and steps to reproduce. Never include tokens, cookies, or Keychain contents in a report — lengths, HTTP statuses, and redacted payload shapes are enough. This is a small project without a formal SLA; reports are read and acknowledged as soon as possible.

## In scope

- Tokens, cookies, or Keychain payloads reaching logs, the clipboard outside the explicit handover action, or any host other than the provider's own usage endpoint
- The Claude OAuth write-back (`ClaudeUsage.mergeRefreshedOAuth`) replacing a newer refresh token with an older one
- The Antigravity loopback trust (`LocalhostTrust.swift`) accepting a certificate from anything other than `127.0.0.1`
- Handover copying transcript text from a project other than the one shown on the button

## Out of scope

- A provider's unofficial endpoint changing shape — that is a bug; report it publicly
- Anything that requires an already-compromised user account on the Mac

## Supported versions

Only the latest release on `main` receives fixes.
