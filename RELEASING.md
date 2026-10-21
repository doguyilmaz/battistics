# Releasing Battistics

To ship, rename `## Unreleased` in `CHANGELOG.md` to the version (for
example `## 1.0.1`) and merge it into `main`. The `Release` workflow tags
`v1.0.1` itself when the top heading is a version with no tag yet; any other
push to `main` releases nothing. Do not create the release on GitHub by
hand: the workflow opens it as a draft and fails when one already exists.

Pushing a tag yourself still works, for a commit that is not on `main`:

```sh
git tag v1.0.1
git push origin v1.0.1
```

## What happens

1. On `main`, the version job pushes the tag with the tapster tag key
   (`TAPSTER_TAG_KEY` in the `release` environment, which only `main` may
   use). A tag pushed with that key starts the workflow again.
2. The tag run stamps the version into `project.yml` as both
   `CFBundleShortVersionString` and `CFBundleVersion`, runs the core tests
   and builds the app with `make app`, signed ad hoc only.
3. It opens a draft release with `Battistics-<version>.app.tar.gz`, the
   frozen `appcast.xml` and `checksums.txt`, attests them and rings the
   tapster hub. The release notes are the CHANGELOG section for the version.
4. The tapster hub in `doguyilmaz/homebrew-tap` checks the app, signs it with
   the Developer ID, builds, notarizes and staples
   `Battistics-<version>.dmg`, signs the DMG and `appcast-2.xml` with the
   Sparkle key, publishes the release and writes the Homebrew cask.

This repository holds no certificate, notary password, Sparkle key or tap
token. They live in the hub.

## What the hub checks

The hub refuses the draft and publishes nothing when:

- `CFBundleShortVersionString` or `CFBundleVersion` differs from the tag;
- the bundle id, `SUFeedURL` or `SUPublicEDKey` differs from the hub's
  `tapster.yml`;
- `SURequireSignedFeed` or `SUVerifyUpdateBeforeExtraction` is not `true`;
- the embedded Sparkle is older than 2.9.0;
- a helper inside the app is not what the hub entry lists under `code`. The
  hub signs each helper with the identifier and entitlements listed there and
  drops any other entitlement, so a new helper or a changed identifier or
  entitlement needs the hub entry changed first;
- `appcast.xml` differs from the digest pinned under `carry`.

## The Sparkle key

Updates are signed with an EdDSA key. The public key is `SUPublicEDKey` in
`project.yml`. The private key is stored in the hub through tapster setup.
An offline copy stays in the password manager.

WARNING: losing this key strands existing users on their current version.
Updates signed with a different key are rejected by installed apps. Keep the
offline copy.

## Local builds

`make app` builds `dist/Battistics.app`, signed ad hoc. The power helper
needs a team signature, so to try it locally build with
`SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" make run`. Releases
never do that: only the hub signs them.

## Checklist before tagging

- `CHANGELOG.md` has a section for the new version
- `make test` is green
- `make run` and a quick smoke test of the popover, dashboard and settings

## Two appcasts

Builds up to 1.0.2 carry the old bundle identifier `com.dogukyilmaz.Battistics`.
Sparkle refuses to install an update whose identifier differs from the running
app's, so those copies cannot be updated in place. They need one manual
download.

- `appcast-2.xml` is the live feed, written and signed by the hub. Every
  build from 1.1.0 reads it.
- `appcast.xml` is `scripts/legacy-appcast.xml`, attached unchanged to every
  draft. Old copies poll `releases/latest/download/appcast.xml`, so **it must
  be attached to every release** or their update check starts failing
  silently. The hub pins its digest under `carry` and refuses a draft whose
  copy differs, so changing the file needs that digest changed too. It
  carries no enclosure, which is what makes Sparkle treat it as an
  informational update: the notice appears with a link instead of a download.

The frozen file links straight at the 1.1.0 DMG so Sparkle's "Learn More"
starts a download rather than opening a page. That pin is deliberate: it only
has to carry someone across the identifier change once, after which ordinary
updates take over. So do not delete the v1.1.0 release while it is live. The
whole thing can be dropped once nobody is left on 1.0.x.
