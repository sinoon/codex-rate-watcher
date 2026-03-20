import { Detail, ActionPanel, Action, showToast, Toast } from "@raycast/api";
import { useEffect, useState } from "react";
import {
  execCLI,
  parseJSON,
  statusEmoji,
  notFoundMarkdown,
  CLINotFoundError,
  type HistoryResponse,
} from "./utils";

export default function History() {
  const [markdown, setMarkdown] = useState<string>("Loading...");
  const [isLoading, setIsLoading] = useState(true);

  async function fetchHistory() {
    setIsLoading(true);
    try {
      const raw = await execCLI(["history", "--hours", "24", "--json"]);
      const data = parseJSON<HistoryResponse>(raw);
      setMarkdown(renderHistory(data));
    } catch (error) {
      if (error instanceof CLINotFoundError) {
        setMarkdown(notFoundMarkdown());
      } else {
        const msg = error instanceof Error ? error.message : String(error);
        setMarkdown(`# Error\n\n\`\`\`\n${msg}\n\`\`\``);
        await showToast({ style: Toast.Style.Failure, title: "Failed to fetch history", message: msg });
      }
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => { fetchHistory(); }, []);

  return (
    <Detail
      isLoading={isLoading}
      markdown={markdown}
      actions={
        <ActionPanel>
          <Action title="Refresh" shortcut={{ modifiers: ["cmd"], key: "r" }} onAction={fetchHistory} />
          <Action.CopyToClipboard title="Copy as Markdown" content={markdown} shortcut={{ modifiers: ["cmd", "shift"], key: "c" }} />
        </ActionPanel>
      }
    />
  );
}

function renderHistory(data: HistoryResponse): string {
  let md = `# Usage History (${data.hours}h)\n\n`;
  md += `> ${data.sample_count} samples collected\n\n`;

  function renderWindow(name: string, window: { sparkline: string; current: number; peak: number; average: number; values: number[] }): string {
    if (!window.values.length) return `### ${name}\n\nNo data available.\n\n`;

    let section = `### ${statusEmoji(100 - window.current)} ${name}\n\n`;
    section += `**Sparkline:** \`${window.sparkline}\`\n\n`;
    section += `| Metric | Value |\n|---|---|\n`;
    section += `| Current | ${Math.round(window.current)}% used |\n`;
    section += `| Peak | ${Math.round(window.peak)}% |\n`;
    section += `| Average | ${Math.round(window.average)}% |\n`;
    section += `| Samples | ${window.values.length} |\n\n`;

    // Trend
    const quarter = Math.max(1, Math.floor(window.values.length / 4));
    const firstQ = window.values.slice(0, quarter);
    const lastQ = window.values.slice(-quarter);
    const firstAvg = firstQ.reduce((a, b) => a + b, 0) / firstQ.length;
    const lastAvg = lastQ.reduce((a, b) => a + b, 0) / lastQ.length;
    const delta = lastAvg - firstAvg;

    let trend: string;
    if (Math.abs(delta) < 2) trend = "\u2192 Stable";
    else if (delta > 0) trend = `\u2197 Increasing (+${Math.round(delta)}%)`;
    else trend = `\u2198 Decreasing (${Math.round(delta)}%)`;
    section += `**Trend:** ${trend}\n\n`;

    return section;
  }

  md += renderWindow("Primary (5h)", data.primary);
  md += `---\n\n`;
  md += renderWindow("Weekly", data.weekly);
  md += `---\n\n`;
  md += renderWindow("Code Review", data.review);

  return md;
}
