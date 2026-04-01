# Codex Managed Account Login Design

**Date:** 2026-04-01

**Status:** Approved for implementation

## Goal

Add a reliable "添加账号" capability for Codex accounts by reusing the browser-based
`codex login` flow, while keeping the current active account unchanged after a new
account is added. The app must let the user switch to any added account later and
must continue to monitor quota changes for all known accounts.

## Non-Goals

- Do not keep the existing device code login flow.
- Do not add manual `auth.json` import, custom OAuth callback handling, or
  arbitrary directory selection in this change.
- Do not redesign the whole profile/recommendation UI.
- Do not replace the current quota model, relay planner, or proxy mode logic.

## Current Constraints

- The app already treats `~/.codex/auth.json` as the live account used by GUI,
  CLI, proxy mode, and quota refresh.
- The app already stores account snapshots under
  `~/Library/Application Support/CodexRateWatcherNative/auth-profiles/` and uses
  `profiles.json` as the main UI index.
- The app already knows how to switch accounts by overwriting
  `~/.codex/auth.json` from a stored snapshot.
- The current device code flow writes directly into `~/.codex/auth.json`, which
  couples "add account" with "switch account". That behavior must be removed.

## Product Decision

Use a managed-home model modeled after `codexbar`:

- Each added Codex account gets its own isolated `CODEX_HOME`.
- The app launches `codex login` with that `CODEX_HOME`.
- Browser authentication and redirect handling are performed by the Codex CLI,
  not by this app.
- On successful login, the app reads the managed home's `auth.json`, extracts the
  account identity, registers the account, and syncs a snapshot into the existing
  profile store.
- Adding an account never changes `~/.codex/auth.json`.
- Switching an account updates `~/.codex/auth.json` from the managed home for the
  selected account, then reuses the existing refresh and validation flow.

This keeps the login flow robust without reimplementing OAuth in AppKit and lets
the current app architecture keep working.

## Data Model

Add a new managed account store alongside the existing profile store.

### New Storage

Root:
`~/Library/Application Support/CodexRateWatcherNative/managed-codex-homes/`

Index file:
`~/Library/Application Support/CodexRateWatcherNative/managed-codex-accounts.json`

Each managed account record stores:

- `id`: stable UUID
- `email`: normalized account email
- `managedHomePath`: absolute path to the isolated `CODEX_HOME`
- `accountID`: OpenAI account ID when available
- `createdAt`
- `updatedAt`
- `lastAuthenticatedAt`

Each account home stores its own Codex-managed files, including `auth.json`.

### Relationship to Existing Profile Store

The existing `profiles.json` and `auth-profiles/` remain the main runtime source
for UI rendering, usage ranking, CLI output, and relay planning.

Managed accounts become the source of truth for identity and fresh auth material.
Profile snapshots remain the source of truth for historical display and fallback
rendering.

The sync rule is:

1. Login succeeds inside a managed home.
2. Read that home's `auth.json`.
3. Upsert the managed account record by email, then by account ID if needed.
4. Sync the same auth payload into `auth-profiles/`.
5. Upsert `profiles.json` so the new account appears in the UI.

## Runtime Flows

### Add Account

1. User clicks "添加账号".
2. App creates a new managed home directory under `managed-codex-homes/UUID/`.
3. App launches `codex login` with `CODEX_HOME=<managed home>`.
4. User completes login in the browser.
5. App waits for the process to exit successfully.
6. App reads `<managed home>/auth.json`.
7. App extracts email and account ID.
8. App upserts the managed account record.
9. App syncs the auth payload into the existing profile store.
10. App refreshes account validation and usage snapshots.
11. The current live account in `~/.codex/auth.json` remains unchanged.

### Switch Account

1. User selects an added account from the existing account list.
2. App resolves the matching managed account for that profile.
3. App backs up the current `~/.codex/auth.json` as it does today.
4. App copies the selected managed account's current `auth.json` into
   `~/.codex/auth.json`.
5. App refreshes usage and revalidates profiles.
6. App syncs the selected auth payload back into `auth-profiles/` so the cached
   snapshot stays aligned with the live managed home.

### Refresh and Detection

Quota monitoring remains based on the existing `UsageMonitor` and
`AuthProfileStore.validateProfiles(using:)`.

The only behavior change is how the app obtains the auth payload for an added
account:

- Active account refresh still reads `~/.codex/auth.json`.
- Non-active profile validation still reads `auth-profiles/*.json`.
- When a managed home is known for a profile, the app should prefer syncing the
  latest managed-home `auth.json` into the cached snapshot before validating, so
  validation does not lag behind reauthentication.

## Deduplication Rules

Managed account deduplication is required to avoid duplicate rows after repeated
login for the same email.

Rules:

- Primary key for reconciliation: normalized email.
- Secondary hint: account ID when available.
- If the same email is added again, keep the existing logical account ID and
  replace its managed home path with the newly authenticated one.
- Delete the old managed home after a successful replacement.
- Keep the existing profile UUID when reconciling the same logical account, so UI
  state and recommendations do not churn unnecessarily.

## UI and Interaction Changes

### Keep

- Existing "添加账号" label.
- Existing account list and switch behavior.
- Existing recommendation card and usage cards.

### Change

- Remove the device code login implementation and all UI copy tied to it.
- Replace add-account behavior with a browser-login progress flow driven by
  `codex login`.
- Show an explicit in-progress state while authentication is running.
- Surface concrete errors for:
  - Codex CLI missing
  - Login timeout
  - Login failed or user aborted
  - `auth.json` missing after reported success
  - Account identity missing from auth payload

### UX Rule

Adding an account must not silently switch the active account. The user should
only switch through the existing explicit switch action.

## Code Shape

The implementation should introduce focused components instead of overloading the
current device code types.

Planned responsibilities:

- `CodexLoginRunner`: run `codex login` with optional `CODEX_HOME`, capture
  timeout and output, and report structured outcomes.
- `ManagedCodexAccountStore`: persist the managed account index file.
- `ManagedCodexAccountService`: create managed homes, authenticate, reconcile
  duplicates, and sync snapshots into the existing profile store.
- `AuthProfileStore`: gain APIs for syncing auth payloads from managed homes and
  for resolving a managed-home-backed switch target.
- `UsageMonitor`: trigger the new add-account flow and refresh after successful
  account registration.
- `AppDelegate` / `PopoverViewController`: replace device code UI copy and wire
  the new add-account action and progress feedback.

## Migration

This change should be backward compatible with existing users.

- Existing `profiles.json` and `auth-profiles/` remain valid.
- On first launch after upgrade, the app may have zero managed accounts but still
  have existing profiles; that state is allowed.
- Managed accounts are only created for accounts added through the new flow.
- Existing switch and quota monitoring must still work for pre-existing profiles,
  with no forced migration.

## Testing Strategy

Add tests for:

- Managed account creation creates a managed home and stores a record.
- Re-authenticating the same email reconciles instead of duplicating.
- Successful managed login syncs into the existing profile store.
- Switching prefers the managed home's latest `auth.json`.
- Missing `codex` binary returns a structured failure.
- Login success without usable auth identity fails cleanly.
- Existing profile-only users still load without managed-account data.

Manual verification should cover:

1. Add a new account through browser login.
2. Confirm the current active account does not change.
3. Confirm the new account appears in the list.
4. Switch to the new account.
5. Confirm `codex-rate status` reflects the switched account.
6. Confirm the menu bar app updates quota cards and recommendations.
7. Build a release app and replace the currently running local installation.

## Build and Replacement Outcome

The implementation is complete only when all of the following are true:

- `swift test` passes for the affected targets.
- A release build succeeds via `./scripts/build_app.sh <version>`.
- The running local app instance is stopped.
- The new `.app` bundle replaces the currently used local bundle.
- The replacement app launches successfully and exposes the new add-account flow.

## Risks

- `codex login` behavior is owned by the installed Codex CLI, so timeout and
  output handling must be defensive.
- Some auth payloads may lack email in the JWT; the implementation should fail
  clearly instead of creating anonymous managed accounts.
- The repository already has in-flight uncommitted changes; implementation must
  avoid overwriting unrelated local edits.

## Acceptance Criteria

- The app no longer offers or uses device code login.
- "添加账号" uses browser-based `codex login` under an isolated managed home.
- Adding an account does not switch the active account.
- Added accounts appear in the account list and can be switched explicitly.
- Account quota changes continue to be detected after add and switch flows.
- The built app can replace the currently running local installation.
