# Token Cost Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the popover token-cost card compact, add a dedicated `Token Cost Dashboard` window, and enrich the shared token-cost snapshot so the native app and `codex-rate cost` expose the same richer analytics surface.

**Architecture:** Extend `CodexRateKit` so `TokenCostScanner` produces one richer `TokenCostSnapshot` with derived range summaries, model summaries, hourly buckets, alerts, and narrative notes. Then expose that shared snapshot through the CLI and a new AppKit dashboard window, while leaving the popover as a compact summary with an `Open Dashboard` CTA.

**Tech Stack:** Swift 6, SwiftPM, Foundation, AppKit, XCTest

**Constraints:**
- Preserve the current local-log, lazy, cache-aware scanner behavior.
- Do not add a second analytics pipeline outside `CodexRateKit`.
- Keep `.superpowers/` artifacts out of product changes and commits.
- Keep popover density roughly unchanged; move rich analysis into a separate window.

---

### Task 1: Extend Shared Token Cost Domain Models

**Files:**
- Modify: `Sources/CodexRateKit/TokenCostModels.swift`
- Modify: `Sources/CodexRateKit/TokenCostScanner.swift`
- Test: `Tests/CodexRateKitTests/TokenCostScannerTests.swift`

- [ ] **Step 1: Write the failing tests**

Cover:
- 7-day totals and rolling averages derive from the same day ledger
- model summaries aggregate input, cache, output, tokens, cost, cost share, and token share
- hourly buckets aggregate by local hour-of-day
- partial-pricing state propagates into snapshot alerts
- narrative notes stay deterministic and factual

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `swift test --filter TokenCostScannerTests`
Expected: failures because the richer snapshot types and aggregates do not exist yet.

- [ ] **Step 3: Write the minimal implementation**

Add:
- range summary types for `7D`, `30D`, and rolling averages
- model summary types with share fields
- hourly summary types
- deterministic alert and narrative derivation
- snapshot assembly logic that derives all aggregates from cached daily buckets

- [ ] **Step 4: Run the targeted tests to verify they pass**

Run: `swift test --filter TokenCostScannerTests`
Expected: all token-cost scanner tests pass with the richer snapshot.

### Task 2: Extend Shared Formatting And CLI Output

**Files:**
- Modify: `Sources/CodexRateKit/TokenCostFormatting.swift`
- Modify: `Sources/codex-rate/main.swift`
- Test: `Tests/CodexRateKitTests/TokenCostCLITests.swift`

- [ ] **Step 1: Write the failing tests**

Cover:
- JSON output includes new range summaries, model summaries, hourly buckets, alerts, and narrative fields
- text output prints richer executive metrics plus model leaderboard and alert context
- partial-pricing state is explicitly labeled instead of silently folded into totals

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `swift test --filter TokenCostCLITests`
Expected: failures because the CLI payload and text renderer still expose the smaller snapshot surface.

- [ ] **Step 3: Write the minimal implementation**

Add:
- CLI JSON payload types for the richer snapshot
- compact but richer text rendering for `codex-rate cost`
- stable field names so downstream script consumers stay predictable

- [ ] **Step 4: Run the targeted tests to verify they pass**

Run: `swift test --filter TokenCostCLITests`
Expected: all CLI token-cost tests pass.

### Task 3: Add Dashboard Window Rendering

**Files:**
- Create: `Sources/CodexRateWatcherNative/TokenCostDashboardViewController.swift`
- Modify: `Sources/CodexRateWatcherNative/Copy.swift`
- Test: `Tests/CodexRateWatcherNativeTests/TokenCostDashboardViewTests.swift`

- [ ] **Step 1: Write the failing tests**

Cover:
- empty state renders honest local-log guidance
- populated state renders executive metrics, model leaderboard, hourly heatmap, and daily table sections
- partial-pricing state renders a visible warning
- narrative panel renders `What changed`, `What helped`, and `What to watch`

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `swift test --filter TokenCostDashboardViewTests`
Expected: failures because the dashboard view controller does not exist yet.

- [ ] **Step 3: Write the minimal implementation**

Add:
- native AppKit dashboard layout matching the approved `Research Desk` hierarchy
- compact charts built from existing snapshot arrays
- refresh timestamp and manual refresh affordance
- empty and partial-pricing states

- [ ] **Step 4: Run the targeted tests to verify they pass**

Run: `swift test --filter TokenCostDashboardViewTests`
Expected: dashboard view tests pass.

### Task 4: Wire The Dashboard Window Into The App Shell

**Files:**
- Modify: `Sources/CodexRateWatcherNative/AppDelegate.swift`
- Modify: `Sources/CodexRateWatcherNative/PopoverViewController.swift`
- Modify: `Sources/CodexRateWatcherNative/UsageMonitor.swift`
- Test: `Tests/CodexRateWatcherNativeTests/UsageMonitorTokenCostTests.swift`

- [ ] **Step 1: Write the failing tests**

Cover:
- popover exposes an `Open Dashboard` affordance when token-cost state is available
- app shell opens a single reusable dashboard window
- dashboard content refreshes as monitor state changes
- manual refresh from the dashboard triggers monitor refresh

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `swift test --filter UsageMonitorTokenCostTests`
Expected: failures because the new dashboard window flow is not wired yet.

- [ ] **Step 3: Write the minimal implementation**

Add:
- window lifecycle and reuse management in `AppDelegate`
- popover CTA callback into the app shell
- shared state propagation from `UsageMonitor` into both popover and dashboard

- [ ] **Step 4: Run the targeted tests to verify they pass**

Run: `swift test --filter UsageMonitorTokenCostTests`
Expected: token-cost monitor tests pass with the dashboard flow wired up.

### Task 5: Full Verification

**Files:**
- Modify if needed: `Package.swift`

- [ ] **Step 1: Run targeted token-cost tests**

Run: `swift test --filter TokenCost`
Expected: all token-cost specific tests pass.

- [ ] **Step 2: Run the native app test suite**

Run: `swift test --filter CodexRateWatcherNativeTests`
Expected: native tests pass, with any existing unrelated warnings explicitly called out if they remain.

- [ ] **Step 3: Run the full test suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 4: Run CLI smoke verification**

Run: `swift run codex-rate cost --json`
Expected: valid JSON including the richer dashboard aggregate fields.

- [ ] **Step 5: Run debug app smoke verification**

Run: `swift run CodexRateWatcherNative -- --window`
Expected: app launches with the updated token-cost surfaces.

- [ ] **Step 6: Run release build verification**

Run: `./scripts/build_app.sh 2.5.0`
Expected: build succeeds and outputs `dist/Codex Rate Watcher.app` and `dist/codex-rate`.
