# Reviewed player changelogs

Add one reviewed JSON manifest here after a player-facing change is verified and merged. The commit is the exact game version to announce, not the later manifest commit. No automatic commit scraping or AI classification runs.

```json
{
  "schema": 1,
  "id": "unique-update-id",
  "commit": "FULL_40_CHARACTER_GAME_COMMIT_SHA",
  "heading": "",
  "entries": ["A concise verified change, with practical controls when helpful."],
  "skip": ""
}
```

Use at most 40 single-line entries, each at most 1500 UTF-16 units. No mentions, angle brackets or control characters. For a version without meaningful player changes use empty entries and a nonempty skip reason. Exclude CI, internal refactors, unsupported performance claims, dormant systems and unreleased promises. Never reuse or change an ID after publication begins. Each manifest is a complete summary; avoid overlapping announcements.

No initial public announcement is included: Frontier has no confirmed released game version in this task. Publication does not deploy or restart a game. See [setup and reconciliation](../docs/community/github-changelog-discord.md).
