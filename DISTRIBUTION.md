# Distributing SimpleShot

Recommended: a universal, Developer ID-signed and notarized `SimpleShot.dmg`
on GitHub Releases, with a README download button and an optional personal
Homebrew tap. Users need macOS 14+, but do not need Xcode or Swift.

## Interim Homebrew preview

While enrollment is pending, `Scripts/package-preview.sh` creates a universal
ad-hoc signed `build/preview/SimpleShot.zip` and checksum file. This is explicitly
unnotarized, published as `v0.1.0-preview.1`, and distributed through
`evanreilly/homebrew-tap`. The cask includes first-launch and permission caveats.
Do not remove quarantine or disable Gatekeeper in the installer.

When the notarized release is ready, replace the tap's cask with the generated
release cask and switch the README button to the stable DMG URL. The first
stable version should be newer than `0.1.0-preview.1` (for example `0.1.1`) so
Homebrew recognizes the upgrade.

## One-time Apple setup

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/)
   ($99 USD/year, or local pricing). A free Apple Development certificate is
   not the Developer ID certificate used for public distribution.
2. Create a **Developer ID Application** certificate using Xcode's account
   certificate manager or the Apple Developer portal. Keep the private key in
   your login Keychain and back it up securely. Use the same team and bundle
   identifier for updates; the app remains `com.simpleshot.app`.
3. Create an app-specific password for your Apple Account, then run:

   ```sh
   xcrun notarytool store-credentials simpleshot-notary
   ```

   Follow the interactive prompts for Apple ID, Team ID, and password. This
   keeps the credentials in Keychain. Do not commit them or put them in GitHub
   issues. `security find-identity -v -p codesigning` lists available signing
   identities.

Notarization is Apple's automated software check, separate from App Store
review. This distribution route does not require an App Store listing.

## Prepare a release

From a clean checkout of the commit you intend to release:

```sh
VERSION=0.1.0 BUILD_NUMBER=1 \
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE=simpleshot-notary ./Scripts/release.sh
```

Increment the version and build number for subsequent releases. The script
runs tests, builds Apple Silicon and Intel slices, enables hardened runtime,
signs, notarizes and staples the app, then builds and notarizes a disk image
with an Applications shortcut. The Apple Events entitlement preserves the
app's Finder automation under hardened runtime. No sandbox is enabled.

Results are in `build/release-0.1.0/`: `SimpleShot.dmg`, `SHA256SUMS`, and
`simpleshot.rb`. No release is published automatically. Failed signing,
notarization, stapling, or Gatekeeper checks stop the script. For a rejected
submission, use `xcrun notarytool log SUBMISSION_ID --keychain-profile
simpleshot-notary` to inspect Apple's report.

Before publishing, test the downloaded disk image on a Mac with normal
Gatekeeper settings. Drag the app into Applications and verify launch, Screen
Recording approval, all three capture shortcuts, annotations, and Finder
automation. Test Intel hardware separately if available; building an Intel
slice is not runtime verification. Check an upgrade preserves permissions.

## Publish the reviewed artifacts

After committing and pushing the release source, create a draft release at
that exact commit:

```sh
gh release create v0.1.0 --target COMMIT_SHA --draft \
  --title 'SimpleShot 0.1.0' --generate-notes \
  build/release-0.1.0/SimpleShot.dmg \
  build/release-0.1.0/SHA256SUMS
```

Review the draft in GitHub and publish it. After the first release, replace
the README's releases badge with this direct-download button:

```markdown
[![Download for macOS](https://img.shields.io/badge/Download_for_macOS-Apple_Silicon_%2B_Intel-147EFB?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/evanreilly/simpleshot/releases/latest/download/SimpleShot.dmg)
```

Keep the filename `SimpleShot.dmg` consistent across releases so that the
button always downloads the latest stable version.

## Optional Homebrew install

Create `evanreilly/homebrew-tap` on GitHub and place the generated
`simpleshot.rb` in `Casks/simpleshot.rb`. Commit a new generated cask with each
release, after its download is public. Validate with `brew audit --cask
evanreilly/tap/simpleshot` and a fresh install. Users can then run:

```sh
brew install --cask evanreilly/tap/simpleshot
```

Updates: quit SimpleShot, then run `brew upgrade --cask
evanreilly/tap/simpleshot`. A personal tap does not need admission to the main
Homebrew cask repository. Homebrew still quarantines app downloads, so it
does not eliminate the need for signing and notarization for smooth launch.

Without Apple enrollment, a source build is possible, but it requires build
tools; unsigned/ad-hoc binary downloads incur Gatekeeper friction and can
lose Screen Recording approval when updated. Neither is the recommended
installation experience for this app. Do not ask users to disable Gatekeeper.
