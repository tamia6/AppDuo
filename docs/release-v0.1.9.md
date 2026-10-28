# AppDuo v0.1.9

- Fix WeChat 4.1.15 clone creation failing during XPlayer signing with an unsigned `vk_swiftshader_icd.json` error (#12).
- Preserve existing extended-attribute signatures on nested generic code while removing quarantine, FinderInfo and resource-fork attributes before re-signing. Strict deep signature verification remains enabled.
- Add a synthetic regression covering nested signed JSON, attribute cleanup and rejection of modified resources, plus an opt-in signing integration test for installed WeChat bundles.
- Signing verification covers disposable WeChat 4.1.15 hard clones on macOS 27.2 arm64. GUI launch, login, messaging, concurrent account operation, MacBook Air M5 and macOS 27.1 have not been verified.
- Includes the previously merged custom clone launch arguments and Chrome nested-bundle signing fix from PR #11.
- ARM64 and Intel downloads retain signed Sparkle update feeds. Current builds are ad-hoc signed and are not Apple notarized; existing first-launch approval instructions still apply.
