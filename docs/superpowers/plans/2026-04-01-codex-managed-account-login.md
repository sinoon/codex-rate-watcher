# Codex Managed Account Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add browser-based Codex account login with isolated managed homes, keep add-account separate from account switching, and preserve quota monitoring plus local app replacement.

**Architecture:** Introduce a managed-account layer that owns isolated `CODEX_HOME` directories and runs `codex login`, then bridge that layer into the existing `profiles.json` and `auth-profiles/` runtime model. Keep current quota refresh, recommendation, CLI output, and switching behavior by syncing managed-home auth into the existing profile store and switching through `~/.codex/auth.json`.

**Tech Stack:** Swift 6, SwiftPM, AppKit, Foundation, Process/URLSession/FileManager, XCTest

---

### Task 1: Add Managed Account Paths And Models

**Files:**
- Modify: `Sources/CodexRateKit/AppPaths.swift`
- Modify: `Sources/CodexRateKit/Models.swift`
- Test: `Tests/CodexRateKitTests/AppPathsTests.swift`

- [ ] **Step 1: Write the failing path test**

Add assertions for:
- `managed-codex-homes`
- `managed-codex-accounts.json`

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppPathsTests`
Expected: failure because the new managed-account paths do not exist yet.

- [ ] **Step 3: Add managed-account path constants and model types**

Introduce:
- `AppPaths.managedCodexHomesDirectory`
- `AppPaths.managedCodexAccountsFile`
- `ManagedCodexAccount`
- `ManagedCodexAccountSet`

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppPathsTests`
Expected: passing path assertions.

### Task 2: Add Codex CLI Browser Login Runner

**Files:**
- Create: `Sources/CodexRateKit/CodexLoginRunner.swift`
- Modify: `Package.swift`
- Test: `Tests/CodexRateKitTests/CodexLoginRunnerTests.swift`

- [ ] **Step 1: Write the failing runner tests**

Cover:
- missing binary
- non-zero exit
- timeout
- success output capture

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CodexLoginRunnerTests`
Expected: failures because the runner does not exist.

- [ ] **Step 3: Implement `CodexLoginRunner`**

Behavior:
- resolve `codex` binary from environment/PATH
- optionally scope `CODEX_HOME`
- run `codex login`
- capture stdout/stderr
- enforce timeout
- return structured outcome

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CodexLoginRunnerTests`
Expected: all runner tests pass.

### Task 3: Add Managed Account Store And Service

**Files:**
- Create: `Sources/CodexRateKit/ManagedCodexAccountStore.swift`
- Create: `Sources/CodexRateKit/ManagedCodexAccountService.swift`
- Modify: `Sources/CodexRateKit/AuthStore.swift`
- Test: `Tests/CodexRateKitTests/ManagedCodexAccountServiceTests.swift`

- [ ] **Step 1: Write the failing service tests**

Cover:
- create managed home and persist account
- reject success without email
- reconcile duplicate email by replacing the managed home
- remove old managed home after replacement

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ManagedCodexAccountServiceTests`
Expected: failure because the store and service do not exist.

- [ ] **Step 3: Implement managed account storage and service**

Behavior:
- create isolated home directories
- invoke `CodexLoginRunner`
- read `<managed home>/auth.json`
- extract normalized email and account ID
- persist `ManagedCodexAccountSet`
- reconcile same-email reauthentication

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ManagedCodexAccountServiceTests`
Expected: all managed-account service tests pass.

### Task 4: Bridge Managed Accounts Into Existing Profile Store

**Files:**
- Modify: `Sources/CodexRateWatcherNative/Persistence.swift`
- Modify: `Sources/CodexRateKit/ProfileLoader.swift`
- Test: `Tests/CodexRateWatcherNativeTests/AuthProfileStoreManagedAccountTests.swift`

- [ ] **Step 1: Write the failing profile-bridge tests**

Cover:
- sync managed-home auth into `auth-profiles/`
- update existing profile instead of duplicating when email/account matches
- switch uses latest managed-home auth, not stale snapshot

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AuthProfileStoreManagedAccountTests`
Expected: failure because managed-account bridging does not exist.

- [ ] **Step 3: Implement profile-store bridge APIs**

Add APIs to:
- upsert a profile from raw auth payload
- resolve a managed account for a profile
- refresh cached snapshots from managed homes
- switch using managed-home auth when available

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AuthProfileStoreManagedAccountTests`
Expected: managed-account bridge tests pass.

### Task 5: Replace Device Code Flow In Runtime Logic

**Files:**
- Modify: `Sources/CodexRateWatcherNative/UsageMonitor.swift`
- Modify: `Sources/CodexRateWatcherNative/AppDelegate.swift`
- Modify: `Sources/CodexRateWatcherNative/Copy.swift`
- Modify: `Sources/CodexRateWatcherNative/PopoverViewController.swift`
- Test: `Tests/CodexRateWatcherNativeTests/QuotaCardLayoutTests.swift`

- [ ] **Step 1: Write the failing runtime/UI tests**

Cover:
- add-account action no longer depends on device code copy
- add-account success keeps active profile unchanged
- progress/error state strings match the new browser-login flow

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CodexRateWatcherNativeTests`
Expected: failures or missing assertions around the new flow.

- [ ] **Step 3: Replace device code wiring with managed login**

Make these changes:
- remove `DeviceCodeAuth` usage from the UI path
- add add-account async flow backed by `ManagedCodexAccountService`
- keep active account unchanged after add
- refresh profiles and quota after add
- update user-facing copy for browser login, timeout, CLI missing, and auth parse failures

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CodexRateWatcherNativeTests`
Expected: native target tests pass.

### Task 6: Remove Obsolete Device Code Surface

**Files:**
- Modify: `Package.swift`
- Delete or stop referencing: `Sources/CodexRateKit/DeviceCodeAuth.swift`
- Search: `Sources/`, `Tests/`

- [ ] **Step 1: Write the failing search-based regression check**

Search for stale references to `DeviceCodeAuth` in runtime code.

- [ ] **Step 2: Run the search and verify stale references exist before cleanup**

Run: `rg -n "DeviceCodeAuth|deviceCode" Sources Tests`
Expected: references still exist before cleanup.

- [ ] **Step 3: Remove or fully orphan obsolete device-code runtime paths**

The shipped app should no longer expose or depend on the device-code login route.

- [ ] **Step 4: Run the search to verify cleanup**

Run: `rg -n "DeviceCodeAuth|deviceCode" Sources Tests`
Expected: no runtime references remain other than historical comments/tests intentionally deleted or updated.

### Task 7: Full Verification And Local App Replacement

**Files:**
- Modify if needed: `scripts/build_app.sh`
- Output: `dist/Codex Rate Watcher.app`

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 2: Run the release build**

Run: `./scripts/build_app.sh 2.4.0`
Expected: build succeeds and outputs the `.app` and CLI into `dist/`.

- [ ] **Step 3: Replace the running local app**

Actions:
- stop the currently running app process
- replace the local app bundle with the newly built one
- relaunch the new app

- [ ] **Step 4: Smoke test the installed app**

Verify:
- the app launches
- "添加账号" is present
- no device-code flow is exposed anymore

