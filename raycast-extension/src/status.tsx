import { Detail, ActionPanel, Action, showToast, Toast } from "@raycast/api";
import { useEffect, useState } from "react";
import {
  execCLI,
  parseJSON,
  progressBar,
  statusEmoji,
  timeUntilReset,
  planBadge,
  notFoundMarkdown,
  CLINotFoundError,
  type StatusResponse,
} from "./utils";

export default function Status() {
  const [markdown, setMarkdown] = useState<string>("Loading...");
  const [isLoading, setIsLoading] = useState(true);

  async function fetchStatus() {
    setIsLoading(true);
    try {
      const raw = await execCLI(["status", "--json"]);
      const data = parseJSON<StatusResponse>(raw);
      setMarkdown(renderStatus(data));
    } catch (error) {
      if (error instanceof CLINotFoundError) {
        setMarkdown(notFoundMarkdown());
      } else {
        const msg = error instanceof Error ? error.message : String(error);
        setMarkdown(`# Error\n\n\`\`\`\n${msg}\n\`\`\``);
        await showToast({ style: Toast.Style.Failure, title: "Failed to fetch status", message: msg });
      }
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => { fetchStatus(); }, []);

  return (
    <Detail
      isLoading={isLoading}
      markdown={markdown}
      actions={
        <ActionPanel>
          <Action title="Refresh" shortcut={{ modifiers: ["cmd"], key: "r" }} onAction={fetchStatus} />
          <Action.CopyToClipboard title="Copy as Markdown" content={markdown} shortcut={{ modifiers: ["cmd", "shift"], key: "c" }} />
        </ActionPanel>
      }
    />
  );
}

function renderStatus(data: StatusResponse): string {
  const primary = data.rate_limit.primary_window;
  const weekly = data.rate_limit.secondary_window;
  const review = data.code_review_rate_limit.primary_window;
  const isBlocked = !data.rate_limit.allowed || data.rate_limit.limit_reached || primary.remaining_percent <= 0;

  const overallStatus = isBlocked
    ? "\u274C **Blocked**"
    : primary.remaining_percent <= 15
      ? "\u26A0\uFE0F **Low**"
      : "\u2705 **Active**";

  let md = `# Codex Usage Status\n\n`;
  md += `> ${planBadge(data.plan_type)}`;
  if (data.email) md += ` \u00B7 ${data.email}`;
  md += ` \u00B7 ${overallStatus}\n\n`;

  md += `---\n\n`;

  // Primary
  md += `### ${statusEmoji(primary.remaining_percent)} Primary (5h Window)\n\n`;
  md += `\`${progressBar(primary.remaining_percent)}\` **${Math.round(primary.remaining_percent)}%** remaining\n\n`;
  md += `| Used | Remaining | Resets In |\n|---|---|---|\n`;
  md += `| ${Math.round(primary.used_percent)}% | ${Math.round(primary.remaining_percent)}% | ${timeUntilReset(primary.reset_at)} |\n\n`;

  // Weekly
  if (weekly) {
    md += `### ${statusEmoji(weekly.remaining_percent)} Weekly Window\n\n`;
    md += `\`${progressBar(weekly.remaining_percent)}\` **${Math.round(weekly.remaining_percent)}%** remaining\n\n`;
    md += `| Used | Remaining | Resets In |\n|---|---|---|\n`;
    md += `| ${Math.round(weekly.used_percent)}% | ${Math.round(weekly.remaining_percent)}% | ${timeUntilReset(weekly.reset_at)} |\n\n`;
  }

  // Review
  md += `### ${statusEmoji(review.remaining_percent)} Code Review\n\n`;
  md += `\`${progressBar(review.remaining_percent)}\` **${Math.round(review.remaining_percent)}%** remaining\n\n`;
  md += `| Used | Remaining | Resets In |\n|---|---|---|\n`;
  md += `| ${Math.round(review.used_percent)}% | ${Math.round(review.remaining_percent)}% | ${timeUntilReset(review.reset_at)} |\n\n`;

  md += `---\n\n`;
  md += `*Fetched at ${new Date(data.fetched_at).toLocaleTimeString()}*`;

  return md;
}
