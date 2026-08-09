# Releasing Battistics

The git tag is the single source of truth for the version. To ship:

```sh
git tag v1.0.1
git push --tags
```

The `Release` workflow stamps the version into `project.yml`, runs the core
tests, builds and signs the app, notarizes and staples the DMG, generates a
Sparkle-signed `appcast.xml` and publishes both to a GitHub release. The
`SUFeedURL` points at `releases/latest/download/appcast.xml`, so the feed URL
never changes between releases.

## Required repository secrets

Set these once with `gh secret set <NAME>`:

| Secret | Content |
|---|---|
| `MACOS_CERT_P12` | Developer ID Application certificate, base64: `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | Password of the exported .p12 |
| `MACOS_SIGN_IDENTITY` | Full identity string, e.g. `Developer ID Application: Name (TEAMID)` |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_TEAM_ID` | 10 character team identifier |
| `NOTARY_PASSWORD` | App-specific password for notarytool |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key (see below) |

## The Sparkle key

Updates are signed with an EdDSA key. The private key lives in the login
Keychain (created by Sparkle's `generate_keys`); the matching public key is
`SUPublicEDKey` in `project.yml`. The same developer key is shared across
this developer's apps, so the `SPARKLE_PRIVATE_KEY` secret has the same value
in each app repository.

Export it for CI with:

```sh
.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle_private_key
gh secret set SPARKLE_PRIVATE_KEY < sparkle_private_key
rm sparkle_private_key
```

WARNING: losing this key strands existing users on their current version.
Updates signed with a different key are rejected by installed apps. Keep the
Keychain item backed up.

## Manual fallback

If CI is unavailable, a full release can run locally:

```sh
make test
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" make dmg
xcrun notarytool submit dist/Battistics-*.dmg --keychain-profile battistics --wait
xcrun stapler staple dist/Battistics-*.dmg
make appcast   # requires the Sparkle key in the login Keychain
make release   # needs gh auth
```

The `battistics` notary profile is stored in the login Keychain
(`notarytool store-credentials`). Signing note: `make app` re-signs
Sparkle's nested XPC services and helpers with the Developer ID
(`scripts/sign-app.sh`); CLI builds keep Sparkle's own signature otherwise
and notarization rejects it.

## Checklist before tagging

- `CHANGELOG.md` has a section for the new version
- `make test` is green
- `make run` and a quick smoke test of the popover, dashboard and settings
