# Releasing MCMagic

The **Xcode - Release** GitHub Actions workflow builds a universal Release app
for Apple Silicon (`arm64`) and Intel (`x86_64`), applies an ad hoc signature with
the hardened runtime, and uploads an app ZIP and SHA-256 checksum. It verifies
both architectures and the code signature before packaging.

No paid Apple Developer Program membership, signing certificate, Apple account,
or repository secrets are required. The app is **not notarized**, and its ad hoc
signature does not establish a verified developer identity.

## Build a release

1. Update `MARKETING_VERSION` in both target configurations for a new version.
2. Commit and push the change. Run **Actions → Xcode - Release → Run workflow**,
   selecting the desired branch, or push a version tag such as `v1.0`.
3. For a tag build, the tag must equal `v` followed by `MARKETING_VERSION`.
   The workflow uses its run number for `CFBundleVersion`.
4. Download the `MCMagic-<version>-<run number>-macOS-universal-adhoc` artifact
   from the successful workflow run. Extract the artifact wrapper to obtain
   the app ZIP and its `.sha256` file. Keep the inner ZIP intact for distribution.
5. Verify the checksum with `shasum -a 256 -c <archive>.sha256` and test the app
   on another Mac, including Accessibility permission, gestures, and reconnect.

Release artifacts are retained for 30 days. The workflow does not create or
publish a GitHub Release; the ZIP can be attached to one after testing.

## Opening the downloaded app

macOS Gatekeeper may block this unnotarized app. After attempting to open it,
users who trust the download can allow it through **System Settings → Privacy
& Security → Open Anyway**, if that option is available under their Mac's policy.
The app still needs Accessibility permission for its gesture functionality.
Ad hoc signatures can change between builds, so a replacement build may require
renewed Accessibility approval.

The app currently contains a single executable and no embedded third-party code.
If helpers, frameworks, or extensions are added, update signing to sign each
nested component before signing the outer app bundle.

## References

- [Apple: Safely open apps on your Mac](https://support.apple.com/en-us/102445)
- [Apple: Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
