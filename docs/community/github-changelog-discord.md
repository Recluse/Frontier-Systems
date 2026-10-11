# GitHub to Discord player changelogs

Existing [issue routing](github-issue-discord-routing.md) already creates bug/suggestion forum threads on routing labels and posts closures to their original threads. The general read-only GitHub feed remains separate. This extension adds reviewed player summaries in dedicated read-only #changelog through GitHub Actions, following Civ13's behavioral contract independently; no upstream code is imported.

The workflow is manual-dispatch only on `dev-master`. Merges, pushes and CI passes are not proof of an available game version and send no announcement. Unlike Civ13's production deployment-status integration, this task installs no Frontier deployment trigger: game release/deployment remains outside its authorization.

Repository Actions configuration:

| Name | Type | Value |
| --- | --- | --- |
| `DISCORD_CHANGELOG_WEBHOOK_URL` | Secret | Dedicated incoming webhook; never record its URL |
| `DISCORD_CHANGELOG_CHANNEL_ID` | Variable | `1558871000383234182` |
| `DISCORD_CHANGELOG_ENABLED` | Variable | Absent/false until approved activation |

The webhook must belong to Frontier guild `1558661083131019364` and that channel. URLs are HTTPS `discord.com` incoming webhook paths only; redirects and extra URL components are rejected. The publisher logs no response bodies or credential-bearing errors. Issue text and manifests are data, never shell code. Discord mentions are disabled.

Setup on 2026-10-11: the dedicated text channel's inherited read-only permissions were checked. The owner manually configured the posting secret; GitHub API inspection confirmed its name and the exact channel variable, without reading the secret value. Activation remains absent. Secret-name presence does not prove the saved webhook works; no live send or game availability has been verified.

Behavioral reference reviewed: Civ13 commit `039cdc98a4086fb83057b2c366479cb2d90e6095`, `.github/workflows/changelog.yml` and `tools/changelog/README.md`. Frontier implementation is independently authored; no source/assets were copied.

Remote branch `discord-changelog-receipts` was provisioned from `dev-master` at `f58fe715b3e8aa087f665b9cf8ea4d30744ba3bd` on 2026-10-11, before activation. Keep it permanently; never merge it into gameplay or delete its records. The workflow writes only `receipts/<manifest-id>.json` there. All runs share one non-canceling concurrency group. Optimistic GitHub file SHA checks fail closed on conflicting state writes.

After reviewing a [manifest](../../changelogs/README.md), dispatch **Reviewed Discord player changelog** on `dev-master` with its ID and exact full game SHA, leaving `dry_run=true`. This prints only the intended public text and performs no network requests or receipt writes. After separately approving publication and confirming that exact integrated SHA is available to players, enable the variable and dispatch with `dry_run=false`, `confirm_live=true`. Neither operation deploys anything. No live game publication is authorized merely by configuring this feature.

Before each Discord POST a durable pending receipt is saved. Confirmed message IDs are then saved as sent. Known sent chunks are skipped; changed manifests and pending/invalid receipts block replay. Network errors, HTTP errors (including rate limits), invalid confirmations or failed post-send state writes leave pending. No blind automatic POST retry runs. Inspect the exact Discord destination and receipt: if delivered, record the actual message ID as sent; if positively proven undelivered, remove only the pending final chunk in a reviewed state commit. Uncertain delivery stays blocked. GitHub and Discord cannot provide a shared exactly-once transaction.

Local `node --test tools/github/changelog-discord.test.mjs` checks admission, bounded payloads, mention suppression, durable reservation, ambiguous delivery, state failures, partial batch recovery and changed-content rejection with injected transports. Existing issue tests remain in the Windows/Linux Actions matrix. Offline checks do not prove live Discord delivery or game availability. No game media is posted.

## Implementation acceptance

PR83 head `523e1434b3878b3436189251652c4c0c8ef6b0e5` merged as `4ecfad52c75e837f458f777a42b46f1f53587311` after all 13 exact-head checks passed. CI `38153946534` tested synthetic `8730e9100fda1cdd3708f4c8b70fafbd45876445`; both OS notification contracts passed in `38153946630`. Local Node 24.21.0 ran 14 changelog and eight unchanged issue contracts successfully. The default-branch workflow is registered. No real changelog message, webhook delivery or available game version is claimed; activation remains absent.
