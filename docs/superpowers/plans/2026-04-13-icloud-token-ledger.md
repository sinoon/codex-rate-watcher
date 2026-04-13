# iCloud Token Ledger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an iCloud Drive backed token ledger so multiple Macs contribute to one merged token-cost total, while still exposing local-only and per-account detail.

**Architecture:** Keep the existing local token scanner and cache. Add a new sync layer that derives a normalized per-device ledger from cached session files, mirrors it to iCloud Drive, loads all device ledgers, then builds one merged `TokenCostSnapshot` with source metadata, local summary, and account summaries.

**Tech Stack:** Swift 6, SwiftPM, Foundation, AppKit, XCTest

---

### Task 1: Add Path And Snapshot Surface For Sync Metadata

**Files:**
- Modify: `Sources/CodexRateKit/AppPaths.swift`
- Modify: `Sources/CodexRateKit/TokenCostModels.swift`
- Test: `Tests/CodexRateKitTests/AppPathsTests.swift`

- [ ] Add iCloud-drive and device-ledger path properties without removing the existing local cache paths.
- [ ] Extend `TokenCostSnapshot` with source summary, local summary, and account summary arrays in a backward-compatible way for current call sites.
- [ ] Add path tests for the new device and ledger file locations.

### Task 2: Extract Shared Snapshot Builder

**Files:**
- Create: `Sources/CodexRateKit/TokenCostSnapshotBuilder.swift`
- Modify: `Sources/CodexRateKit/TokenCostScanner.swift`
- Test: `Tests/CodexRateKitTests/TokenCostScannerTests.swift`

- [ ] Move the daily/window/model/hour aggregation helpers out of `TokenCostScanner` into one shared builder.
- [ ] Keep scanner behavior unchanged for the existing local-only tests.
- [ ] Verify scanner tests still pass after the extraction.

### Task 3: Add Device Identity And Ledger Models

**Files:**
- Create: `Sources/CodexRateKit/TokenCostSyncModels.swift`
- Create: `Sources/CodexRateKit/TokenCostDeviceStore.swift`
- Create: `Sources/CodexRateKit/TokenCostLedgerStore.swift`
- Test: `Tests/CodexRateKitTests/TokenCostSyncServiceTests.swift`

- [ ] Add a stable local device identity model and persistence helper.
- [ ] Add normalized ledger models for device files and session records.
- [ ] Write tests that prove device identity persists and ledger files round-trip.

### Task 4: Build And Merge iCloud Ledgers

**Files:**
- Create: `Sources/CodexRateKit/TokenCostSyncService.swift`
- Modify: `Sources/CodexRateKit/ManagedCodexAccountStore.swift` if helper access is needed
- Test: `Tests/CodexRateKitTests/TokenCostSyncServiceTests.swift`

- [ ] Build a local device ledger from the existing token-cost cache file and managed-account metadata.
- [ ] Attribute managed-home sessions to managed accounts and root sessions to `Local / Unknown`.
- [ ] Mirror the local ledger to the iCloud ledger directory when available.
- [ ] Merge multiple device ledgers by dedupe key into one aggregated snapshot.
- [ ] Verify merged totals, local subtotals, and account summaries in tests.

### Task 5: Route The Shared Loader Through The Sync Service

**Files:**
- Modify: `Sources/CodexRateKit/TokenCostLoader.swift`
- Modify: `Sources/CodexRateKit/TokenCostCLIReport.swift`
- Modify: `Tests/CodexRateKitTests/TokenCostCLITests.swift`

- [ ] Swap `LiveTokenCostSnapshotLoader` to return merged snapshots through the sync service.
- [ ] Update CLI JSON payload to include `source`, `local_summary`, and `account_summaries`.
- [ ] Update CLI text rendering so all-device totals are the primary metrics and local detail is explicit.

### Task 6: Surface Merged Totals In The Native App

**Files:**
- Modify: `Sources/CodexRateWatcherNative/Copy.swift`
- Modify: `Sources/CodexRateWatcherNative/PopoverViewController.swift`
- Modify: `Sources/CodexRateWatcherNative/TokenCostDashboardViewController.swift`
- Modify: `Tests/CodexRateWatcherNativeTests/UsageMonitorTokenCostTests.swift`
- Modify: `Tests/CodexRateWatcherNativeTests/TokenCostDashboardViewTests.swift`

- [ ] Update copy so the token dashboard can distinguish `All Devices` from `Local Device`.
- [ ] Keep the compact cost card, but switch its headline metrics to merged totals.
- [ ] Add one account breakdown section to the dashboard using the new account summaries.
- [ ] Update UI tests to cover merged vs local labeling.

### Task 7: Verify End-To-End

**Files:**
- Modify if needed: `scripts/build_app.sh`

- [ ] Run targeted token cost tests.
- [ ] Run the full Swift test suite.
- [ ] Run `swift run codex-rate cost --json` to inspect the merged payload shape.
- [ ] Run a release build to confirm the app still packages correctly.
