# Native rewrite implementation

The new sibling repository preserves the existing Python repository as a reference. A shared Swift library serves SwiftUI and a native CLI; there is no Python bridge. SwiftPM keeps the project buildable from Xcode and a terminal. SwiftUI uses a sidebar, feature views and a five-step creation sheet. The actor-backed repository serializes operations and uses an advisory filesystem lock and atomic JSON writes.

The cloning sequence is: validate → inspect → copy to staging → prepare data → icon/plist/language → environment injection or launcher → rename processes → compatibility patches → sign nested code → verify → replace destination. Both icon bytes and the previous application remain available throughout staging. Native compilation tests exercise actual process paths and signatures.

Reusable upstream assets: GPL-licensed recipes, icon, and Objective-C interposition shim. YAML uses Yams instead of a partial ad-hoc parser. Dedicated Mach-O parsing checks bounds before changing bytes. Password records use Security.framework Keychain.

Completion checks: SwiftPM build and tests; launch packaged application; exercise source selection, automatic recipe detection and original-icon preview; package and verify DMG. App-specific login/notification/proxy behavior needs a separate compatibility matrix, since binary patches depend on upstream application versions.

## Verified locally (2026-09-17)

- `swift test`: 4 tests passed, including multiple real binary build/update combinations.
- Native SwiftUI app launched; five-step wizard inspected through accessibility and screenshot, including WeChat source detection and its original icon preview.
- A temporary clone of installed WeChat 4.1.13 was built with the Swift engine, using the custom blue-violet icon. It reached the QR login screen. `proc_pidpath` reported `.../Contents/MacOS/WeWorkSwiftVerified`; installed icon bytes matched the selected .icns.
- Fixed issues exposed by integration testing: URL identity normalization, nested-code signing order, stripping restricted third-party developer entitlements, and avoiding applying the Bundle ID suffix twice.
- No sign-in was performed; temporary test clones were removed after validation. Actual Clash rule routing, long-running stability, notifications and all 34 app families are not certified by this smoke test.
