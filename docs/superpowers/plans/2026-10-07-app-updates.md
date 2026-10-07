# AppDuo Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add authenticated, user-confirmed Sparkle updates without touching clone data.
**Architecture:** Sparkle standard updater controller in AppDuo; small testable configuration in CloneCore; signed per-architecture feeds produced by release tools.
**Tech Stack:** Swift 6 / SwiftUI, Sparkle 2.10.0, GitHub Actions, Python XML generation.

## Global Constraints
- macOS 14+, ARM64 and Intel, HTTPS feeds, stable releases only.
- No permanent key creation, new release, or system-security bypass.
- Independent clone data stays unchanged; defer installation while AppStore.busy.

### Task 1: Configuration and updater
- Files: Sources/CloneCore/AppUpdateConfiguration.swift, Tests/CloneCoreTests/AppUpdateTests.swift, Sources/AppDuo/App/AppUpdater.swift, AppDuoApp.swift, Package.swift.
- [ ] Test missing/invalid key and ARM/Intel feed choice first; run `swift test --filter AppUpdateTests` and observe failure.
- [ ] Implement configuration and rerun targeted tests.
- [ ] Integrate Sparkle controller, startup background check, menu, deferred installation, and configuration-error UI.

### Task 2: Packaging and release
- Files: script/build_and_run.sh, script/check_packaged_app.sh, script/publish_updates.py, .github/workflows/build.yml, website/updates/*.xml.
- [ ] Write fixture tests for stable versions, archive signature output and architecture separation; run and observe missing implementation failure.
- [ ] Embed universal Sparkle framework preserving symlinks, add rpath, validate packaged libraries and resources.
- [ ] Require signing secrets for tagged releases, produce signed feeds and publish only after successful build; expose configuration requirements in docs.

### Task 3: Validate and review
- [ ] Run Swift and feed-generation tests and release-mode isolated packaging.
- [ ] Validate executable launch and update UI against an isolated feed; record tests blocked by absent signing key.
- [ ] Review changes, preserve all user applications and clone data, prepare reviewable commit/PR without issuing a release.
