import { execFile } from "child_process";
import { existsSync } from "fs";
import { homedir } from "os";
import path from "path";

// ── Types ──────────────────────────────────────────────────────────

export interface QuotaWindow {
  used_percent: number;
  remaining_percent: number;
  limit_window_seconds: number;
  reset_after_seconds: number;
  reset_at: number;
}

export interface RateLimit {
  allowed: boolean;
  limit_reached: boolean;
  primary_window: QuotaWindow;
  secondary_window?: QuotaWindow;
}

export interface StatusResponse {
  plan_type: string;
  email?: string;
  account_id?: string;
  auth_mode?: string;
  rate_limit: RateLimit;
  code_review_rate_limit: RateLimit;
  credits: { has_credits: boolean; unlimited: boolean };
  fetched_at: string;
}

export interface ProfileUsage {
  planDisplayName: string;
  primaryRemainingPercent: number;
  secondaryRemainingPercent?: number;
  reviewRemainingPercent: number;
  isBlocked: boolean;
  isRunningLow: boolean;
}

export interface Profile {
  fingerprint: string;
  email?: string;
  accountID?: string;
  authMode?: string;
  discoveredAt: string;
  lastSeenAt: string;
  latestUsage?: ProfileUsage;
  validationError?: string;
}

export interface HistoryWindow {
  values: number[];
  sparkline: string;
  current: number;
  peak: number;
  average: number;
}

export interface HistoryResponse {
  hours: number;
  sample_count: number;
  primary: HistoryWindow;
  weekly: HistoryWindow;
  review: HistoryWindow;
}

// ── CLI Path Resolution ────────────────────────────────────────────

const CLI_CANDIDATES = [
  "/usr/local/bin/codex-rate",
  path.join(homedir(), ".local/bin/codex-rate"),
  "/opt/homebrew/bin/codex-rate",
  path.join(homedir(), "codebase/codex-rate-watcher/.build/release/codex-rate"),
  path.join(homedir(), "codebase/codex-rate-watcher/.build/debug/codex-rate"),
];

let cachedPath: string | null = null;

function findCLI(): string | null {
  if (cachedPath && existsSync(cachedPath)) return cachedPath;
  for (const p of CLI_CANDIDATES) {
    if (existsSync(p)) {
      cachedPath = p;
      return p;
    }
  }
  return null;
}

// ── CLI Execution ──────────────────────────────────────────────────

export class CLINotFoundError extends Error {
  constructor() {
    super("codex-rate CLI not found");
    this.name = "CLINotFoundError";
  }
}

export class CLIExecError extends Error {
  stderr: string;
  exitCode: number | null;
  constructor(message: string, stderr: string, exitCode: number | null) {
    super(message);
    this.name = "CLIExecError";
    this.stderr = stderr;
    this.exitCode = exitCode;
  }
}

export function execCLI(args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const cliPath = findCLI();
    if (!cliPath) {
      reject(new CLINotFoundError());
      return;
    }
    execFile(
      cliPath,
      args,
      { timeout: 15_000, maxBuffer: 1024 * 1024, env: { ...process.env, NO_COLOR: "1" } },
      (error, stdout, stderr) => {
        if (error) {
          reject(new CLIExecError(error.message, stderr, error.code ? parseInt(error.code) : null));
          return;
        }
        resolve(stdout);
      }
    );
  });
}

// ── Formatting Helpers ─────────────────────────────────────────────

export function progressBar(percent: number, width = 25): string {
  const clamped = Math.max(0, Math.min(100, percent));
  const filled = Math.round((clamped / 100) * width);
  return "█".repeat(filled) + "░".repeat(width - filled);
}

export function statusEmoji(remaining: number): string {
  if (remaining <= 0) return "❌";
  if (remaining <= 15) return "🔴";
  if (remaining <= 30) return "🟠";
  if (remaining <= 50) return "🟡";
  return "🟢";
}

export function timeUntilReset(resetAt: number): string {
  const now = Date.now() / 1000;
  const diff = Math.max(0, Math.round(resetAt - now));
  if (diff <= 0) return "now";
  const h = Math.floor(diff / 3600);
  const m = Math.floor((diff % 3600) / 60);
  if (h > 24) {
    const d = Math.floor(h / 24);
    return `${d}d ${h % 24}h`;
  }
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

export function planBadge(plan: string): string {
  const upper = plan.toUpperCase();
  if (upper.includes("MAX")) return "💎 MAX";
  if (upper.includes("PRO")) return "⭐ PRO";
  if (upper.includes("TEAM")) return "👥 TEAM";
  return `📦 ${plan}`;
}

export function parseJSON<T>(raw: string): T {
  try {
    return JSON.parse(raw) as T;
  } catch {
    throw new Error(`Failed to parse CLI output: ${raw.substring(0, 200)}`);
  }
}

export function notFoundMarkdown(): string {
  return `# codex-rate CLI Not Found

The \`codex-rate\` CLI tool is required but was not found on your system.

## Install

\`\`\`bash
# Clone and build
git clone https://github.com/patchwork-body/shakeflow.git
cd shakeflow
swift build -c release --target codex-rate

# Copy to PATH
cp .build/release/codex-rate /usr/local/bin/
\`\`\`

## Searched Paths
${CLI_CANDIDATES.map((p) => `- \`${p}\``).join("\n")}
`;
}
