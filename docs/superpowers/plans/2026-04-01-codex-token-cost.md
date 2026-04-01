# Codex Token Cost Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace quota-derived cost estimates with a real local token-cost scanner for Codex and use that shared snapshot in both the native app and `codex-rate cost`.

**Architecture:** Add a Codex-only token-cost module inside `CodexRateKit` that scans local session JSONL logs, computes per-day token deltas by model, prices them with a static model table, and exposes a shared `TokenCostSnapshot`. Then replace current `CostTracker` call sites in the native app and CLI with the new snapshot loader.

**Tech Stack:** Swift 6, SwiftPM, Foundation, AppKit, XCTest

---

### Task 1: Add Token Cost Models And Pricing

**Files:**
- Create: `Sources/CodexRateKit/TokenCostModels.swift`
- Create: `Sources/CodexRateKit/TokenCostPricing.swift`
- Test: `Tests/CodexRateKitTests/TokenCostPricingTests.swift`

- [ ] **Step 1: Write the failing test**

Cover:
- Codex model normalization strips `openai/`
- dated model aliases resolve to known base models
- cached input uses the cached input rate
- unknown models return no cost

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TokenCostPricingTests`
Expected: failure because token-cost pricing types do not exist.

- [ ] **Step 3: Write minimal implementation**

Add:
- token-cost snapshot and daily-entry models
- Codex pricing table for the current GPT-5 family models
- normalization and cost calculation helpers

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TokenCostPricingTests`
Expected: all pricing tests pass.

### Task 2: Add Token Cost Scanner Core

**Files:**
- Create: `Sources/CodexRateKit/TokenCostScanner.swift`
- Create: `Sources/CodexRateKit/TokenCostCache.swift`
- Modify: `Sources/CodexRateKit/AppPaths.swift`
- Test: `Tests/CodexRateKitTests/TokenCostScannerTests.swift`

- [ ] **Step 1: Write the failing test**

Cover:
- parse `token_count` event deltas from `total_token_usage`
- fall back to `last_token_usage`
- aggregate by day and model
- include `managed-codex-homes/*/sessions`
- deduplicate duplicate session files

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TokenCostScannerTests`
Expected: failure because the scanner and cache do not exist.

- [ ] **Step 3: Write minimal implementation**

Add:
- session root discovery
- JSONL scanning for `event_msg`, `turn_context`, `session_meta`
- per-file incremental cache
- shared `loadSnapshot(now:)` entry point

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TokenCostScannerTests`
Expected: scanner tests pass with deterministic fixtures.

### Task 3: Replace CLI Cost Command

**Files:**
- Modify: `Sources/codex-rate/main.swift`
- Test: `Tests/CodexRateKitTests/TokenCostCLITests.swift`

- [ ] **Step 1: Write the failing test**

Cover:
- JSON output includes today, last-30-days, and daily breakdown fields
- text output no longer depends on monthly subscription heuristics

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TokenCostCLITests`
Expected: failure because CLI rendering still uses `CostTracker`.

- [ ] **Step 3: Write minimal implementation**

Replace:
- `CostTracker.weeklyStats(...)`
- `CostTracker.todaySummary(...)`

With:
- shared token-cost snapshot loader
- new text rendering
- new `--json` payload

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TokenCostCLITests`
Expected: CLI token-cost tests pass.

### Task 4: Replace Native App Cost Dashboard

**Files:**
- Modify: `Sources/CodexRateWatcherNative/UsageMonitor.swift`
- Modify: `Sources/CodexRateWatcherNative/PopoverViewController.swift`
- Modify: `Sources/CodexRateWatcherNative/Copy.swift`
- Test: `Tests/CodexRateWatcherNativeTests/TokenCostViewTests.swift`

- [ ] **Step 1: Write the failing test**

Cover:
- monitor state exposes token-cost snapshot instead of quota estimate
- popover renders today and last-30-days token cost summaries
- unavailable token-cost data renders an honest fallback state

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TokenCostViewTests`
Expected: failure because the native app still expects `LiveCostState`.

- [ ] **Step 3: Write minimal implementation**

Replace:
- `State.liveCost`
- `CostTracker.todaySummary(...)` rendering

With:
- shared token-cost snapshot loading
- simplified cost card labels driven by token-cost data

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TokenCostViewTests`
Expected: native token-cost view tests pass.

### Task 5: Remove Obsolete CostTracker Usage

**Files:**
- Modify: `Sources/CodexRateKit/CostTracker.swift` or stop referencing it
- Search: `Sources/`, `Tests/`

- [ ] **Step 1: Write the failing regression check**

Search for `CostTracker` call sites that still drive user-facing cost output.

- [ ] **Step 2: Run the check to verify stale references exist**

Run: `rg -n "CostTracker" Sources Tests`
Expected: existing cost paths still reference the old estimator before cleanup.

- [ ] **Step 3: Write minimal implementation**

Remove or isolate:
- app-facing `CostTracker` usage
- CLI-facing `CostTracker` usage

Keep any remaining internal code only if it no longer affects shipped output.

- [ ] **Step 4: Run the check to verify cleanup**

Run: `rg -n "CostTracker" Sources Tests`
Expected: no user-facing call sites remain.

### Task 6: Full Verification

**Files:**
- Modify if needed: `scripts/build_app.sh`

- [ ] **Step 1: Run targeted token-cost tests**

Run: `swift test --filter TokenCost`
Expected: all token-cost specific tests pass.

- [ ] **Step 2: Run the full test suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 3: Run CLI smoke verification**

Run: `swift run codex-rate cost --json`
Expected: valid JSON with token-cost fields.

- [ ] **Step 4: Run release build verification**

Run: `./scripts/build_app.sh 2.4.0`
Expected: build succeeds and outputs `dist/Codex Rate Watcher.app` and `dist/codex-rate`.
