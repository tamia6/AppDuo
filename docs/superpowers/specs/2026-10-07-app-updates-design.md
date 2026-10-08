# AppDuo automatic updates

Approved by the user: Sparkle-based updates, launch-time background stable-release check, prompt before downloading/installing/relaunching, and manual Check for Updates menu. ARM64 and Intel use distinct feeds published with the stable GitHub Release over HTTPS and signed update archives on GitHub Releases.

Sparkle owns version comparison, authenticated archive verification, progress, privileged installation when needed, and error recovery. AppDuo defers installation while a clone build/removal is running. Clone data and configuration are outside the replaced app bundle and remain intact. Applications copied from DMG and installed by Homebrew use the same updater; the cask declares auto_updates when the feature ships. A read-only/translocated installation must not be silently replaced.

Release signing needs an Ed25519 public key embedded in the app and a private key available only to release CI. No permanent signing keys or credentials are created without user approval. Builds without a configured public key disable updating with an explanation; tagged releases must fail rather than publish unsigned updates. Apple notarization remains separate and unchanged. Existing v0.1.6 cannot update itself because it has no updater; users install the first updater-enabled release manually.

No new release is authorized. Validate isolated packaging and UI on ARM, Intel compilation/packaging where feasible, and tests for feed selection, absent/malformed configuration, startup checks, and clone-busy install gating. A real signed upgrade requires approved signing-key setup; do not claim it has passed until exercised.
