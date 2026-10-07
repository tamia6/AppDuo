# AppDuo automatic updates

The app checks for stable AppDuo releases in the background on launch. If a newer version is available, Sparkle offers the update. Choose Install Update to download it; choose Install and Relaunch when ready. The application menu also provides 检查更新…. Checks do not block opening AppDuo, and a failed download or signature check leaves the existing app usable. Installing/relaunching waits for active clone operations to finish. AppDuo's clone data, configuration and Keychain entries are outside the replaced application bundle.

ARM64 and Intel use separate HTTPS appcasts attached to the latest stable GitHub Release. Sparkle compares CFBundleVersion values, rejects skipped versions and authenticates the entire update archive using the embedded Ed25519 public key before extraction. The release generator additionally validates each archive signature against that same public key. No update feed or archive is accepted just because its filename or SHA-256 matches.

## Release setup

Before releasing the first updater-enabled version, the repository owner must approve and provision a dedicated Sparkle signing key. Keep its private key out of Git and public build logs. Configure the repository variable SPARKLE_PUBLIC_KEY with the base64 public key, and the Actions secret SPARKLE_PRIVATE_KEY with the exported base64 private seed. The project does not create these automatically. Preserve and securely back up this key; existing installed versions trust the embedded key, so rotating it requires Sparkle's supported migration process.

Normal development builds without a public key disable updating and explain this when Check for Updates is chosen. Tagged builds fail when the public key is absent or malformed; the release job fails if the private key is absent or mismatched. Only after both architecture builds and update authentication pass does the workflow publish the draft release containing the DMGs, SHA-256 files and appcast-arm64.xml/appcast-x86_64.xml. Existing v0.1.6 has no updater and must be upgraded manually once.

When the first updater-enabled version ships, add `auto_updates true` to the Homebrew cask alongside its new version and SHA-256 values. Sparkle updates the installed app; Homebrew's cask record may retain the originally installed version. Use normal brew upgrade/reinstall when updating through Homebrew. Do not change the current v0.1.6 cask to claim that it already updates itself.

Auto-updating does not add Apple notarization. Gatekeeper approval may still be required. Apps running inside a read-only DMG or with App Translocation should first be copied to Applications; protected installations can require macOS authorization through Sparkle. Do not disable Gatekeeper or remove quarantine as part of the updater.

## Validation

```sh
swift test
python3 script/test_publish_updates.py
CONFIGURATION=release bash script/build_and_run.sh --build
```

Test installs and upgrades must use an isolated app directory and user data root. A publicly documented RFC 8032 test vector can exercise signing and tampered-archive rejection locally; it must never be used as the release signing key. Production release testing requires the approved project key.

References: [Sparkle setup](https://sparkle-project.org/documentation/), [Programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/), [Publishing updates](https://sparkle-project.org/documentation/publishing/).
