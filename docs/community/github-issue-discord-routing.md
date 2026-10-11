# GitHub issue notifications in Discord

The default-branch issue-discord.yml Actions workflow handles issues labeled and closed. Bug maps to forum1558669102741065838; enhancement, suggestion, suggestions, feature request and feature-request map to forum1558669253161390130. PRs and unrelated labels are ignored. Adding a routing label to an open issue creates a forum thread with a GitHub link and bounded body excerpt. Additional aliases in the same category do not create another thread.

Closure posts to each previously recorded thread, even if its routing label was removed. Closure of an issue never routed by this workflow creates no notification. Discord users receive notifications according to their own forum/thread settings; no role/everyone mentions are sent. Both categories on one issue create one thread in each forum.

Required repository Actions secrets: DISCORD_BUG_REPORTS_WEBHOOK_URL and DISCORD_SUGGESTIONS_WEBHOOK_URL. Create dedicated incoming webhooks in the exact forum channels; never commit their URLs/tokens. The workflow verifies webhook channel metadata before posting. No bot token or third-party action is used. Issue text is JSON data, never shell interpolation or executed code; allowed_mentions is empty.

The workflow has issues:read and contents:write solely for a dedicated discord-issue-state branch containing issues/NUMBER.json with forum thread/message IDs and closure state. Do not delete this branch: it preserves mappings for older and relabeled issues. No credentials or supporter data are stored. State branch pushes do not target dev-master or trigger its push CI. Checkout is explicitly default-branch code, never issue/PR-contributed code.

Manual workflow dispatch accepts one issue number, synchronizes missing category threads for an open issue, or retries unrecorded closure delivery. Inspect Discord first after an uncertain send or state-write failure: Discord sends and GitHub state writes are not an atomic transaction. Overlapping label events or automatic reruns can duplicate messages if both observe missing state; do not blindly retry. Delivery errors remain failed Actions runs, never silent successes. Closed forum threads are not automatically locked or archived by this workflow.

Offline Node tests use injected HTTP responses, with no real Discord sends. Live forum webhook configuration and genuine labeled/closed delivery must be verified separately. No game release/deployment or game media upload is involved.

