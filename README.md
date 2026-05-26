# Koala

Native macOS API client. Postman-like REST + GraphQL workflows, with mock servers, environments, and collaboration — all backed by your own Vercel account.

> **Status:** v0.1.x — early but usable. macOS 14+ required.

---

## Install

```bash
brew tap eularixs/koala https://github.com/eularixs/koala-homebrew.git
brew install --cask eularixs/koala/koala
```

App is ad-hoc signed (no Apple Dev account). The cask's `postflight` strips `com.apple.quarantine` automatically so Gatekeeper allows launch on first run.

Upgrade later:
```bash
brew upgrade --cask eularixs/koala/koala
```

---

## Features

### Requests
- **REST**: GET / POST / PUT / PATCH / DELETE / HEAD / OPTIONS, any custom verb
- **GraphQL**: Hasura-style three-pane builder — introspect schema, click checkboxes to compose queries, edit variables JSON
- **Body types**: JSON / Form / Multipart / Raw / GraphQL / Binary
- **Auth**: Bearer / Basic / API Key / OAuth 2.0 (manual token paste) / AWS Signature v4
- **Environments & globals**: `{{var_name}}` substitution with live highlighting badges in the URL bar
- **Tabs**: Finder-style, dirty dot for unsaved changes, close confirmation, ⌘W / ⌘T / ⌘S / ⌘F

### Mock Servers
- Deploy a Next.js mock backend to **your own Vercel account** in ~60s
- Edit response per endpoint inline (status / body / headers / delay)
- **Apidog-style rules engine**: define conditional responses matched by query / header / JSON body / path
- Storage via **Vercel Edge Config** — instant config updates, no redeploy

### Collaboration
- Share project bundle (collections + envs + globals) via Vercel Edge Config
- Generate a share key from the project owner → teammates paste in the welcome screen to join
- Joiner does NOT need their own Vercel account

### Project Organization
- Multiple projects, optional groups
- Color tagging (Development / Staging / Production + custom tags)
- Persisted collection expand/collapse state per project
- Import/export: Postman 2.1, OpenAPI 3.0, HAR, Insomnia, Apidog, Swagger, Markdown

### Misc
- ⌘F search across all requests in current project
- History (capped 100, FIFO)
- Native macOS Settings scene
- Code editor with monospace font, auto-pair brackets, JSON formatter

---

## Setup Vercel

1. Open [vercel.com/account/tokens](https://vercel.com/account/tokens)
2. Create Token → name "Koala" → Full Account scope
3. Copy token (shown once)
4. In Koala: Settings → Vercel → paste into **Personal Access Token** → Save

That's it. No OAuth integration setup needed.

> Optional: if you're distributing Koala to others under your own OAuth app, the Vercel Settings → Advanced section lets you register Client ID + Secret.

---

## Architecture

| Layer | Tech |
|---|---|
| UI | SwiftUI (macOS 14+), AppKit hosting for NSScrollView code editor |
| State | `@Observable` (Swift 6 observation, no Combine) |
| Persistence | JSON files in `~/Library/Application Support/koala/` (no SQLite) |
| Mock backend | Next.js 14 deployed per Koala project on Vercel |
| Mock storage | Vercel Edge Config (1 store per project, shared with collab) |
| Secrets | macOS Keychain (Vercel PAT + OAuth secrets) |

---

## Development

```bash
git clone https://github.com/eularixs/koala.git
cd koala
open koala.xcodeproj
```

Build with `xcodebuild` directly:
```bash
xcodebuild -project koala.xcodeproj -scheme koala -configuration Debug -destination 'platform=macOS' build
```

### Requirements
- Xcode 16+
- macOS 14+
- Swift 6 toolchain

### Tests
Unit tests only (UI tests skipped in CI due to TCC permissions):
```bash
xcodebuild -project koala.xcodeproj -scheme koala -only-testing:koalaTests test
```

---

## Releasing

PRs MUST be titled with one of:
- `major: <subject>` → breaking change → X.0.0
- `minor: <subject>` → new feature → 0.X.0
- `patch: <subject>` → bugfix / chore → 0.0.X

On merge to `main`, GitHub Actions auto-bumps version, tags, builds DMG, publishes GitHub Release, and updates the Homebrew tap.

See [.github/workflows/release.yml](.github/workflows/release.yml).

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
