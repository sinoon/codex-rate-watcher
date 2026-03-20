import { List, ActionPanel, Action, Icon, Color, showToast, Toast } from "@raycast/api";
import { useEffect, useState } from "react";
import {
  execCLI,
  parseJSON,
  progressBar,
  statusEmoji,
  planBadge,
  notFoundMarkdown,
  CLINotFoundError,
  type Profile,
} from "./utils";

export default function Profiles() {
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [cliNotFound, setCLINotFound] = useState(false);

  async function fetchProfiles() {
    setIsLoading(true);
    try {
      const raw = await execCLI(["profiles", "--json"]);
      setProfiles(parseJSON<Profile[]>(raw));
      setCLINotFound(false);
    } catch (error) {
      if (error instanceof CLINotFoundError) {
        setCLINotFound(true);
      } else {
        const msg = error instanceof Error ? error.message : String(error);
        await showToast({ style: Toast.Style.Failure, title: "Failed to fetch profiles", message: msg });
      }
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => { fetchProfiles(); }, []);

  if (cliNotFound) {
    return <List><List.EmptyView title="CLI Not Found" description="Install codex-rate to use this extension" /></List>;
  }

  return (
    <List isLoading={isLoading} isShowingDetail searchBarPlaceholder="Filter profiles...">
      {profiles.map((profile) => (
        <List.Item
          key={profile.fingerprint}
          title={profile.email ?? profile.fingerprint.substring(0, 8)}
          subtitle={profile.authMode ?? ""}
          icon={{ source: Icon.Person, tintColor: profile.latestUsage ? Color.Blue : Color.SecondaryText }}
          accessories={[
            {
              tag: {
                value: profile.latestUsage?.planDisplayName ?? "Unknown",
                color: profile.latestUsage?.planDisplayName?.includes("max") ? Color.Purple : Color.Blue,
              },
            },
          ]}
          detail={
            <List.Item.Detail
              markdown={renderProfileDetail(profile)}
            />
          }
          actions={
            <ActionPanel>
              <Action title="Refresh" shortcut={{ modifiers: ["cmd"], key: "r" }} onAction={fetchProfiles} />
              {profile.email && <Action.CopyToClipboard title="Copy Email" content={profile.email} shortcut={{ modifiers: ["cmd"], key: "e" }} />}
              <Action.CopyToClipboard title="Copy Fingerprint" content={profile.fingerprint} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}

function renderProfileDetail(profile: Profile): string {
  let md = `# ${profile.email ?? "Unknown Account"}\n\n`;
  md += `| Field | Value |\n|---|---|\n`;
  md += `| Fingerprint | \`${profile.fingerprint.substring(0, 12)}...\` |\n`;
  if (profile.authMode) md += `| Auth Mode | ${profile.authMode} |\n`;
  md += `| First Seen | ${new Date(profile.discoveredAt).toLocaleDateString()} |\n`;
  md += `| Last Seen | ${new Date(profile.lastSeenAt).toLocaleDateString()} |\n`;

  if (profile.latestUsage) {
    const u = profile.latestUsage;
    md += `\n---\n\n### Usage\n\n`;
    md += `**Plan:** ${planBadge(u.planDisplayName)}\n\n`;

    const status = u.isBlocked ? "\u274C Blocked" : u.isRunningLow ? "\u26A0\uFE0F Low" : "\u2705 Active";
    md += `**Status:** ${status}\n\n`;

    md += `| Window | Remaining |\n|---|---|\n`;
    md += `| Primary | ${statusEmoji(u.primaryRemainingPercent)} \`${progressBar(u.primaryRemainingPercent, 15)}\` ${Math.round(u.primaryRemainingPercent)}% |\n`;
    if (u.secondaryRemainingPercent != null) {
      md += `| Weekly | ${statusEmoji(u.secondaryRemainingPercent)} \`${progressBar(u.secondaryRemainingPercent, 15)}\` ${Math.round(u.secondaryRemainingPercent)}% |\n`;
    }
    md += `| Review | ${statusEmoji(u.reviewRemainingPercent)} \`${progressBar(u.reviewRemainingPercent, 15)}\` ${Math.round(u.reviewRemainingPercent)}% |\n`;
  } else if (profile.validationError) {
    md += `\n---\n\n### \u26A0\uFE0F Error\n\n\`${profile.validationError}\`\n`;
  }

  return md;
}
