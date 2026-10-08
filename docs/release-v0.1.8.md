# AppDuo v0.1.8

- Fix WeCom 5.0.9 startup crashes caused by renaming its main executable. The built-in YAML now preserves the original main name; helper names remain configurable. WeChat keeps its existing executable renaming behavior.
- Updating older WeCom clones adopts the built-in naming policy while preserving their identity, configuration choices and data directory.
- Includes v0.1.7 Sparkle updates with signed ARM64/Intel feeds. v0.1.7 users can update in-app; v0.1.6 users must install manually once.
- Native ARM startup tests passed for an isolated WeCom clone. Concurrent account operation and complete data isolation have not been verified; compatibility varies by application.
- Ad-hoc signed; not Apple notarized. Existing opening instructions still apply.
