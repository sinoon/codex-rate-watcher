# iCloud Token Ledger Design

**Date:** 2026-04-13

**Status:** Approved for implementation

## Goal

Extend token-cost analytics so multiple Macs can contribute to one merged token
ledger through iCloud Drive. The default token-cost surface should show the
all-device total, while detailed breakdowns can still drill into account-level
usage where attribution is reliable.

## Non-Goals

- Do not sync `auth.json`, managed account auth snapshots, or any other login
  secret in this iteration.
- Do not sync raw `~/.codex/sessions/**/*.jsonl` files to iCloud.
- Do not require CloudKit entitlements or a sandboxed app build in this
  iteration.
- Do not guess historical account ownership for old root `~/.codex/sessions`
  files that lack reliable attribution.

## Problem

The current token-cost stack is local-only:

- `TokenCostScanner` scans local session logs and managed homes.
- `token-cost-cache.json` stores the incremental scan cache.
- `TokenCostSnapshot` drives both the native dashboard and `codex-rate cost`.

That works on one Mac, but the numbers stay fragmented when the same user runs
Codex on several devices. A user who rotates between laptops wants one total
burn number, not one local subtotal per machine.

The current local scanner is still valuable and should remain the source of
truth for log parsing. The missing piece is a durable, mergeable ledger that can
travel through iCloud Drive without shipping raw logs or auth state.

## Product Decision

Build a filesystem-based iCloud Drive sync layer on top of the existing local
scanner.

The product behavior is:

- each device keeps scanning its own local logs
- each device writes a normalized token ledger file to iCloud Drive
- each device reads all ledger files from iCloud Drive and merges them into one
  all-device snapshot
- the all-device snapshot becomes the default token-cost view
- local-only subtotals remain visible as supporting detail

If iCloud Drive is unavailable, the app should fall back to the current local
behavior without breaking quota monitoring.

## Why iCloud Drive Instead Of CloudKit

This repository currently packages the app with `swift build` plus a handwritten
`.app` bundle in `scripts/build_app.sh`. There is no existing entitlement or
signing pipeline for CloudKit containers.

Using the user-visible iCloud Drive filesystem path:

- avoids introducing CloudKit container setup in this release
- works from the current non-sandboxed packaging model
- keeps the first release focused on ledger shape and merge correctness

The iCloud path for this iteration should live under:

`~/Library/Mobile Documents/com~apple~CloudDocs/Codex Rate Watcher/`

## Data Model

### Device identity

Add a persisted device identity file under app support. It stores:

- stable `deviceID` UUID
- best-effort `deviceName`
- creation time

This gives each Mac a stable writer identity for iCloud ledger files.

### Local ledger

Add a normalized ledger format separate from the scan cache.

Suggested shape:

- `TokenCostSyncLedger`
- `TokenCostSyncDevice`
- `TokenCostSyncSession`
- `TokenCostAccountSummary`
- `TokenCostSourceSummary`
- `TokenCostLocalSummary`

Each ledger file represents one device and contains a set of normalized session
records. Each session record contains:

- stable dedupe key:
  - `session:<sessionID>` when `session_id` exists
  - otherwise `file:<deviceID>:<pathHash>` fallback
- source type:
  - `managed`
  - `local_unknown`
- account key and display name:
  - managed accounts use stored email or account id
  - root local sessions use `local_unknown`
- per-day token buckets using the same `TokenCostCachedDay` shape already used
  by the scanner cache

The ledger intentionally stores aggregated buckets, not raw JSONL rows.

## Attribution Rules

### Managed homes

When a cached session file path belongs to a managed home under
`managed-codex-homes/*`, match that home path against `ManagedCodexAccountSet`
and attribute the session to that account.

### Root local sessions

Files under the root Codex home cannot be reliably assigned to a historical
account from existing logs alone. For this release:

- do not guess
- bucket them under `Local / Unknown`
- still count them in the all-device total

This preserves correctness for totals and honesty for account detail.

## Merge Rules

Each device writes its ledger to:

`<icloud-root>/token-ledgers/<deviceID>.json`

Each reader loads every device ledger in that directory and merges them by
session dedupe key.

Rules:

- prefer the newest copy when the same dedupe key appears in multiple device
  files
- merge all unique session day buckets into one aggregated day map
- build account summaries from the merged session set
- compute the main `TokenCostSnapshot` from the merged day map

The default top-level metrics become:

- all-device today
- all-device 7 days
- all-device 30 days
- all-device 90 days

The snapshot also carries:

- local-only today and 30-day summaries
- iCloud source metadata
- account summaries for detail views

## Runtime Flow

1. Load the local token-cost snapshot from the existing scanner/cache.
2. Load or create the stable device identity.
3. Build a device ledger from the local cache file plus managed-account
   metadata.
4. Save the device ledger under app support.
5. If iCloud Drive is available:
   - mirror the device ledger into the iCloud ledger directory
   - load all device ledgers from that directory
   - merge them into an all-device snapshot
6. Return:
   - merged snapshot when iCloud data is available
   - otherwise the local snapshot with local source metadata

## Code Structure

### Existing files to extend

- `Sources/CodexRateKit/AppPaths.swift`
  - add device identity, local ledger, and iCloud ledger paths
- `Sources/CodexRateKit/TokenCostModels.swift`
  - extend `TokenCostSnapshot` with source, local summary, and account summaries
- `Sources/CodexRateKit/TokenCostLoader.swift`
  - swap the loader to build merged snapshots through the sync service
- `Sources/CodexRateWatcherNative/TokenCostDashboardViewController.swift`
  - show all-device framing and account breakdown
- `Sources/CodexRateWatcherNative/PopoverViewController.swift`
  - show total by default, local as supporting detail
- `Sources/codex-rate/main.swift`
  - keep `cost` command on the shared merged snapshot

### New files

- `Sources/CodexRateKit/TokenCostSnapshotBuilder.swift`
  - shared aggregation helpers extracted from `TokenCostScanner`
- `Sources/CodexRateKit/TokenCostSyncModels.swift`
  - ledger, device, source, account, and local summary models
- `Sources/CodexRateKit/TokenCostDeviceStore.swift`
  - stable local device identity persistence
- `Sources/CodexRateKit/TokenCostLedgerStore.swift`
  - local + iCloud ledger file IO
- `Sources/CodexRateKit/TokenCostSyncService.swift`
  - build local ledger, mirror to iCloud, load ledgers, merge snapshot

## CLI Behavior

`codex-rate cost` should keep the current command shape, but its meaning changes:

- top-level metrics now represent the all-device total when iCloud data exists
- JSON output also exposes:
  - `source`
  - `local_summary`
  - `account_summaries`

Text output should make the scope explicit with phrases like:

- `All Devices`
- `Local Device`

## Native App Behavior

### Popover

Keep the compact cost card, but make the scope clear:

- primary metrics show all-device totals
- subline shows local-only supporting numbers
- when iCloud is unavailable, fall back to the current local framing

### Dashboard

Keep the existing dashboard layout, but change the copy and detail:

- header subtitle references all-device analytics when merged data exists
- digest/overview cards show all-device totals
- add one account leaderboard card for per-account detail
- keep model/day/hour analytics based on the merged total

## Failure Handling

Failure modes must be soft:

- local scan failure should not block quota refresh
- iCloud write failure should keep local cost working
- malformed remote ledger files should be ignored instead of poisoning the
  merged result
- when no iCloud directory exists, the app behaves as local-only

## Verification

The implementation should add regression coverage for:

- path derivation for iCloud and device files
- ledger construction from scanner cache files
- merging ledgers from two devices into one snapshot
- account attribution for managed vs local unknown sessions
- CLI payload fields for merged/local/account views
- monitor propagation of the merged snapshot

