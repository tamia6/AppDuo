# 独立进程名称 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make cloned apps keep their original process names by default, with an allowlisted opt-in for network rules that depend on independent process names.

**Architecture:** Recipe files declare whether an app supports independent process names. CloneConfiguration persists the user opt-in with a backward-compatible false default. CloneEngine skips or performs the existing ProcessNames.rename call based on that value, while WizardView exposes the opt-in only for allowlisted hard clones.

**Tech Stack:** Swift 6 / SwiftUI / XCTest / YAML recipes / macOS Mach-O bundle builder.

## Global Constraints

- Preserve all existing uncommitted icon changes.
- Keep the current URL-routing experiment unchanged.
- The new process-name option defaults to false.
- Existing saved clone configurations without the new field must continue loading.

### Task 1: Add failing coverage for the process-name policy

**Files:**
- Modify: `Tests/CloneCoreTests/CoreTests.swift`
- Modify: `Tests/CloneCoreTests/EngineTests.swift`
- Modify: `Sources/CloneCore/Resources/recipes/com.tencent.xinWeChat.yaml`

- [ ] Add assertions that the WeChat recipe allows the option, a decoded old configuration defaults to false, a default hard clone keeps `CFBundleExecutable` and the original binary name, and an opted-in clone still exposes the renamed executable.
- [ ] Run the focused tests and confirm they fail because the new recipe/configuration properties do not exist yet.

### Task 2: Implement persisted capability and build behavior

**Files:**
- Modify: `Sources/CloneCore/Models.swift`
- Modify: `Sources/CloneCore/Recipes.swift`
- Modify: `Sources/CloneCore/CloneEngine.swift`

- [ ] Add `Recipe.allowIndependentProcessName` decoded from `allow_independent_process_name`, defaulting to false.
- [ ] Add `CloneConfiguration.useIndependentProcessName`, custom decode with `decodeIfPresent(... ) ?? false`, and validation that an unsupported recipe cannot opt in.
- [ ] In `CloneEngine`, choose the original executable name when the option is false, call `ProcessNames.rename` only when true, and pass the selected target name to the existing launcher.
- [ ] Run the focused tests and confirm they pass.

### Task 3: Expose the opt-in in the wizard

**Files:**
- Modify: `Sources/AppDuo/Views/WizardView.swift`

- [ ] Add the persisted state, restore it from existing records, and write it into `CloneConfiguration`.
- [ ] Show `Toggle("使用独立进程名称")` only for allowlisted hard-clone recipes in “网络与存储”, defaulting off.
- [ ] Update the summary text to show the selected process-name policy without changing icon or storage behavior.
- [ ] Build AppDuo to verify the SwiftUI changes compile.

### Task 4: Full verification and real clone

**Files:**
- No additional source files.

- [ ] Run `swift test`.
- [ ] Build the latest AppDuo.
- [ ] Rebuild WeChat 3 with the new default policy, inspect its process names, and open it.
- [ ] After login is available, click avatar → 朋友圈 and record whether the clone opens the Moments page or still shows no response.
