# Releasing MCMagic

The **Xcode - Release** GitHub Actions workflow builds a universal macOS app
(Apple Silicon and Intel), signs it with Developer ID and the hardened runtime,
submits it to Apple for notarization, staples the ticket, and verifies Gatekeeper
acceptance before uploading an app ZIP and SHA-256 checksum.

## One-time setup

In the repository's **Settings → Secrets and variables → Actions**, add:

| Repository secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded password-protected `.p12` containing one **Developer ID Application** certificate and its private key. |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used to export that `.p12`. |
| `APPLE_ID` | Apple Account email authorized to notarize software for the team. |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for that Apple Account. |
| `APPLE_TEAM_ID` | Developer team ID that owns the certificate (currently `M62S2H9PQ6` in the Xcode project). |

Export the Developer ID Application identity and private key from Keychain
Access as a password-protected P12. An Apple Development or Mac App Distribution
certificate cannot replace the Developer ID Application certificate.

To upload the encoded P12 without printing it or saving its contents in the repo:

```sh
base64 -i /path/to/DeveloperID.p12 | gh secret set DEVELOPER_ID_CERTIFICATE_BASE64
```

Enter the other secrets through GitHub's settings or interactive `gh secret set`
prompts. Do not put certificates, private keys, or passwords in Git or chat.
The workflow imports the identity into a temporary keychain and cleans it up
even when a later step fails. It never falls back to an unsigned release.

## Build a release

1. Update `MARKETING_VERSION` in both project configurations for a new version.
2. Commit and push the change. Run **Actions → Xcode - Release → Run workflow**,
   selecting the desired branch, or push a version tag such as `v1.0`.
3. For a tag build, the tag must equal `v` followed by `MARKETING_VERSION`.
   The workflow uses its run number for `CFBundleVersion`.
4. Download the `MCMagic-<version>-<run number>-macOS-universal` artifact from the
   successful workflow run. Extract the artifact wrapper to obtain the signed
   app ZIP and its `.sha256` file. Keep the inner ZIP intact for distribution.
5. Verify the checksum with `shasum -a 256 -c <archive>.sha256` and test the app
   on another Mac, including Accessibility permission, gestures, and reconnect.

Release artifacts are retained for 30 days. The workflow does not create or
publish a GitHub Release; the ZIP can be attached to one after testing.
Notarization responses and logs are retained separately for 14 days.

The app currently contains a single executable and no embedded third-party code.
If helpers, frameworks, or extensions are added, update signing to sign each
nested component before signing the outer app bundle.

## References

- [Apple: Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Apple: Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
- [GitHub: Installing an Apple certificate on macOS runners](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
