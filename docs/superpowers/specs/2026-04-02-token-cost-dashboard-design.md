# Token Cost Dashboard Design

Date: 2026-04-02
Repo: `/Users/bytedance/codebase/codex-rate-watcher`
Status: proposed and approved for planning

## Goal

Replace the current lightweight token cost card with a two-layer experience:

1. Keep the menu bar popover compact and scannable.
2. Add a dedicated dashboard window for richer token cost analysis.

The dashboard should feel like a product-grade analysis surface, not an internal admin panel and not a raw debug dump.

## Chosen Direction

We will keep the existing compact cost card inside the popover and add a dedicated `Token Cost Dashboard` window.

For the dashboard window, the chosen visual direction is:

- `Research Desk`
- dense, but ordered
- dark native Mac aesthetic
- strong grid discipline
- productized analysis board rather than cold ops-console styling

This direction was selected over:

- a lighter summary page, which would not be rich enough
- a harsher “ops console” layout, which carries more diagnostic density but feels too tool-like for this app

## Non-Goals

These are intentionally out of scope for the first implementation:

- full session forensics view
- per-message or per-turn transcript drilldown
- cross-account cost comparison window
- editable pricing rules in the UI
- background sync to remote services

The first version should stay focused on local session-log analytics for the current app user.

## Product Shape

### 1. Popover Cost Card

The popover should remain compact. It should answer:

- how much did I spend today
- how many tokens did I use today
- what is the 30-day total
- is something abnormal right now
- where do I click for deeper inspection

The popover should not try to host tables, multiple charts, or dense drilldowns.

Required elements:

- `Today Cost`
- `Today Tokens`
- `30D Cost`
- a compact trend sparkline
- one-line sub-summary
- `Open Dashboard` affordance

### 2. Dedicated Dashboard Window

The dashboard window becomes the canonical detailed token-cost surface.

It should support:

- quick scanning
- trend reading
- model mix understanding
- cache leverage understanding
- day-level comparison
- anomaly detection

## Information Architecture

The dashboard window will use a structured grid with clear reading order.

### Header

Purpose:

- establish this as a full analysis surface
- provide time-range controls
- expose export entry point later

Contents:

- title: `Token Cost Research Desk`
- subtitle explaining what the board tracks
- range chips: `7D`, `30D`, `90D`
- `Export` action, with JSON export allowed in the first version

### Row 1: Executive Metrics

This row should answer the highest-value questions first.

Cards:

- `Today Cost`
- `30D Cost`
- `Today Tokens`
- `Cache Share`
- `Dominant Model`

Design rules:

- `Today Cost` is visually strongest
- `Dominant Model` is not hidden in secondary UI
- each card has one supporting line only

### Row 2: Trend + Alert Rail

#### Burn Timeline

This is the primary chart.

It should show:

- daily cost line
- token overlay
- visible spike markers

Questions it answers:

- is cost trending up
- are tokens and dollars moving together
- where were the abnormal days

#### Alert Rail

This is a stacked right-side rail with compact analysis alerts.

Examples:

- high burn day
- strong cache efficiency
- unknown-priced model present

This rail should feel like interpretation, not just stats repetition.

### Row 3: Structural Breakdown

Three side-by-side blocks:

- `Model Leaderboard`
- `Cost Structure`
- `Hourly Heatmap`

#### Model Leaderboard

Shows ranked cost contribution by model.

Questions it answers:

- which model is driving spend
- is there one dominant model or multiple meaningful contributors

#### Cost Structure

Shows:

- input tokens
- cache-read tokens
- output tokens

Purpose:

- explain cost anatomy
- make cache leverage legible
- prevent users from confusing total tokens with total dollar drivers

#### Hourly Heatmap

Shows relative cost or token intensity by hour bucket.

Purpose:

- reveal burst windows
- make session rhythm visible without requiring raw-session drilldown

### Row 4: Daily Table + Narrative Panel

#### Daily Detail Table

This is the dense factual ledger.

Columns:

- date
- cost
- input
- cache
- output
- dominant model

Future-safe extension:

- expandable rows for more model detail

#### Narrative Panel

This is a structured textual interpretation block.

Sections:

- `What changed`
- `What helped`
- `What to watch`

Purpose:

- turn dense metrics into readable conclusions
- make the dashboard useful even when the user does not inspect every block

## Data Model Changes

The current `TokenCostSnapshot` already supports:

- today totals
- 30-day totals
- day-level rows
- per-day model breakdowns

That is not sufficient for the approved dashboard design.

We should extend the token-cost domain model to support richer derived analytics while keeping the scanner as the single source of truth.

### Required Additions

#### Time-range summary

Add explicit summary fields for:

- `last7DaysCostUSD`
- `last7DaysTokens`
- `averageDailyCostUSD`
- `averageDailyTokens`

#### Model summary

Add aggregated model-level totals across the selected snapshot window:

- model name
- total cost
- total tokens
- input tokens
- cache-read tokens
- output tokens
- cost share
- token share

#### Hourly summary

Add hour-bucket aggregation for recent activity:

- hour bucket
- cost
- tokens

The first version can bucket by local hour-of-day and aggregate over recent days rather than storing full per-session timelines.

#### Alert summary

Add derived alert objects so the UI does not have to infer complex conditions directly from raw series.

Examples:

- high-burn spike
- unusual model concentration
- high or low cache share
- unknown-priced data present

#### Narrative summary

Add a lightweight derived interpretation layer created from deterministic heuristics.

This should remain small and factual, not “AI generated” prose.

## Scanner Strategy

The scanner should remain local-log based and cache-aware.

Current scanner properties we should preserve:

- local Codex session log scan
- managed-home support
- session de-duplication
- cache file reuse
- default 60-second refresh cache

The richer dashboard should not change the core loading model into live streaming.

Instead:

- continue scanning lazily
- continue using cached snapshots
- compute richer aggregates during scan or snapshot assembly

## Window Behavior

The dashboard window should be an explicit separate window, not a popover expansion.

Reasons:

- the chosen design needs stable width and height
- charts and tables need more breathing room
- a separate window matches “analysis desk” behavior better than a transient popover

### Required interactions

- open from popover via `Open Dashboard`
- reuse existing dashboard window if already open
- refresh contents when the main monitor state updates
- show empty state when there is no local session data
- show partial-pricing warning when unknown-priced models affect totals

## Visual Principles

The dashboard should keep the current dark native visual language, but with better hierarchy and higher information density.

Principles:

- disciplined grid
- strong typography contrast
- restrained accent color usage
- denser than current popover, but not chaotic
- analysis-first, not decorative-first

Avoid:

- random card sizes without reading order
- “ops wall” harshness
- over-styled gradients that obscure data
- fake complexity without decision value

## Empty, Partial, and Error States

### Empty state

When no local session logs exist:

- keep the dashboard window usable
- explain that local Codex usage data will appear after running Codex

### Partial pricing state

When tokens exist but some models are not priced:

- totals affected by missing pricing must be visually marked
- the alert rail should surface this
- the narrative panel should mention that totals are partial

### Load latency state

Because the scanner is cached and lazy, the UI should acknowledge freshness:

- show `updated at`
- allow manual refresh
- avoid implying per-token realtime precision

## CLI Compatibility

The CLI should continue reading the same shared token-cost snapshot model.

If snapshot richness increases, `codex-rate cost --json` should expose the same new aggregate data in a stable JSON form.

This keeps GUI and CLI on one data contract and prevents dual cost definitions from returning.

## Testing Strategy

### Domain tests

Add tests for:

- model aggregation
- hour-bucket aggregation
- alert derivation
- narrative derivation
- partial-pricing propagation

### Native UI tests

Add focused layout and rendering tests for:

- dashboard empty state
- dashboard populated state
- partial-pricing badge or alert state
- dominant-model and timeline sections rendering

### Manual validation

Validate:

- popover remains compact
- dashboard opens and reopens reliably
- dashboard reflects local real data
- cache-driven refresh still feels fast

## Implementation Slices

The work should be implemented in this order:

1. extend token-cost domain models and snapshot aggregation
2. extend CLI JSON and text output to match richer snapshot data
3. add dashboard window controller and layout
4. connect popover CTA to dashboard window
5. polish empty, partial, and refresh states

## Decision Summary

Approved design:

- keep popover cost card compact
- add separate dashboard window
- use `Research Desk` style, not `Ops Console`
- make the dashboard notably denser than the current card
- keep strong layout order and grid discipline
- enrich shared snapshot data rather than inventing a second analytics path
