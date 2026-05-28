# Sparkle 2 Setup Guide

## 1. Generate EdDSA Keypair

After Sparkle is resolved by Xcode, the `generate_keys` tool is available inside the built framework.
Run it once from the project root:

```bash
./build/SourcePackages/checkouts/Sparkle/bin/generate_keys
```

Or if you installed Sparkle via Homebrew cask:

```bash
sparkle generate_keys
```

Output example:

```
Private key (base64-encoded, store safely — never commit):
<base64 string>

Public key (paste into Info.plist SUPublicEDKey):
<base64 string>
```

## 2. Add Public Key to Info.plist

The project uses `GENERATE_INFOPLIST_FILE = YES`, so the key is set in
`koala.xcodeproj/project.pbxproj` under `INFOPLIST_KEY_SUPublicEDKey`.

Replace the placeholder value `REPLACE_WITH_YOUR_SPARKLE_PUBLIC_ED_KEY` with
the public key string output by `generate_keys`:

```
INFOPLIST_KEY_SUPublicEDKey = "YOUR_PUBLIC_KEY_HERE";
```

You can also set it in Xcode: Target > Build Settings > search `SUPublicEDKey`.

## 3. Store Private Key as GitHub Secret

Go to your repository Settings > Secrets and variables > Actions > New repository secret:

- **Name:** `SPARKLE_PRIVATE_KEY`
- **Value:** the base64-encoded private key from step 1

## 4. Sign Releases

Uncomment the `Sign DMG with Sparkle EdDSA` step in `.github/workflows/release.yml`.
That step uses `sign_update` to compute the EdDSA signature and embeds it in
the `sparkle:edSignature` attribute of the `<enclosure>` element in
`web/public/appcast.xml` (and `appcast-beta.xml` for beta builds).

## 5. Beta Channel

`FeatureFlags.betaChannel` controls which feed URL Sparkle uses at runtime:

- `false` (default) → `https://koala.eularix.com/appcast.xml` (stable)
- `true` → `https://koala.eularix.com/appcast-beta.xml` (beta, Pro subscribers)

Set `KOALA_BETA=1` in the environment to activate beta channel without code changes.

## Notes

- Ad-hoc unsigned builds will be quarantined by Gatekeeper. The Homebrew tap's
  `postflight` block already strips `com.apple.quarantine` after `brew install`.
- Sparkle requires the app to be notarized or have the quarantine xattr removed
  for auto-updates to apply. For local dev builds, no action needed.
- The `SUFeedURL` in the generated Info.plist is the stable URL; the
  `SparkleUpdaterDelegate` overrides it at runtime for beta users.
