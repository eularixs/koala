# Contributing to Koala

Thanks for your interest. Keep it brief — read this once, refer back as needed.

## Quick start

```bash
git clone https://github.com/eularixs/koala.git
cd koala
open koala.xcodeproj
```

Build via Xcode (⌘R) or:
```bash
xcodebuild -project koala.xcodeproj -scheme koala -configuration Debug -destination 'platform=macOS' build
```

## PR title convention

**Required.** PR title MUST start with one of:

| Prefix | When | Version bump |
|---|---|---|
| `major: ` | breaking change (e.g. drop config field) | X.0.0 |
| `minor: ` | new feature, backwards-compatible | 0.X.0 |
| `patch: ` | bugfix / chore / docs | 0.0.X |

Example: `minor: add GraphQL introspection builder`

CI rejects PRs without this prefix. On merge to `main`, the release workflow auto-bumps `MARKETING_VERSION`, tags, builds a DMG, and updates the Homebrew tap.

## Code style

- Swift 6. Use `@Observable` (not `ObservableObject`).
- Prefer `@MainActor` on UI-bound classes.
- Models in `Models/`, view-models in `ViewModels/`, views in `Views/<area>/`, services in `Services/`.
- Match existing patterns: `KeyValueEditorView` for kv tables, `_SettingsGroupView`/grouped cards for forms, `TagBadgeView` for badges.
- No external dependencies unless absolutely necessary (currently zero — Xcode 16 file-system synchronized groups, pure SwiftUI/AppKit).

## Commits inside a PR

Squash-merge is fine. Whatever you commit on the branch will be replaced by the PR title on merge.

## Reporting bugs

Open an issue with:
1. macOS version + Koala version
2. Reproduction steps
3. Expected vs. actual
4. Logs from `~/Library/Logs/koala/` if relevant (currently we don't write logs there — `Console.app` filtered to `com.koala` is the next-best).

## License & Developer Certificate of Origin (DCO)

By submitting a pull request, you certify that:

> The contribution was created by you (or you have rights to submit it) and you license it under the project's MIT license (see [LICENSE](LICENSE)).

Optional but encouraged: sign off your commits.
```bash
git commit -s -m "patch: fix tab close after sheet dismiss"
```
This adds a `Signed-off-by: <Your Name> <email>` line. Equivalent to agreeing to the DCO at https://developercertificate.org.

There is no separate CLA — submitting a PR under the MIT license is sufficient.

## Security issues

Do NOT open public issues for security vulnerabilities. Email dimsmauls@gmail.com with details. Public disclosure after a fix lands.

## Style for new contributors

- Small PRs > large PRs.
- One feature per PR.
- Match the project's caveman-tone code comments (terse, only WHY not WHAT).
- Don't add doc paragraphs unless asked.
