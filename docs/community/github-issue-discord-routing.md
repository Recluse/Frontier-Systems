# GitHub issue notifications in Discord

The default-branch issue-discord.yml Actions workflow handles issues labeled and closed. Bug maps to forum1558669102741065838; enhancement, suggestion, suggestions, feature request and feature-request map to forum1558669253161390130. PRs and unrelated labels are ignored. Adding a routing label to an open issue creates a forum thread with a GitHub link and bounded body excerpt. Additional aliases in the same category do not create another thread.

Closure posts to each previously recorded thread, even if its routing label was removed. Closure of an issue never routed by this workflow creates no notification. Discord users receive notifications according to their own forum/thread settings; no role/everyone mentions are sent. Both categories on one issue create one thread in each forum.

Required repository Actions secrets: DISCORD_BUG_REPORTS_WEBHOOK_URL and DISCORD_SUGGESTIONS_WEBHOOK_URL. Create dedicated incoming webhooks in the exact forum channels; never commit their URLs/tokens. The workflow verifies webhook channel metadata before posting. No bot token or third-party action is used. Issue text is JSON data, never shell interpolation or executed code; allowed_mentions is empty.

The workflow has issues:read and contents:write solely for a dedicated discord-issue-state branch containing issues/NUMBER.json with forum thread/message IDs and closure state. Do not delete this branch: it preserves mappings for older and relabeled issues. No credentials or supporter data are stored. State branch pushes do not target dev-master or trigger its push CI. Checkout is explicitly default-branch code, never issue/PR-contributed code.

Manual workflow dispatch accepts one issue number, synchronizes missing category threads for an open issue, or retries unrecorded closure delivery. Inspect Discord first after an uncertain send or state-write failure: Discord sends and GitHub state writes are not an atomic transaction. Overlapping label events or automatic reruns can duplicate messages if both observe missing state; do not blindly retry. Delivery errors remain failed Actions runs, never silent successes. Closed forum threads are not automatically locked or archived by this workflow.

Offline Node tests use injected HTTP responses, with no real Discord sends. Live forum webhook configuration and genuine labeled/closed delivery must be verified separately. No game release/deployment or game media upload is involved.


## Live verification — 2026-10-11

Configured dedicated incoming hooks Frontier GitHub Bugs (ID1558862598881943685) in forum1558669102741065838 and Frontier GitHub Suggestions (ID1558861372429828169) in forum1558669253161390130. Both named Actions secrets are saved and independently listed. No webhook URLs or tokens are recorded here.

PR79 head9ba4528bae49ad1e48434f2cf7e9846b361e75a7 merged asfd7ccea7d795b6e45b2cd9e4cf538e86da3cb133 after eight offline tests and all13 exact-head CI checks passed, including both OS routing contracts. CI run38150919274 tested syntheticcb68b0af26d3c22029e117220d121f29d87c3e26 againstf9f708513116656cbe16d9128da247e29053eb38.

Owner explicitly approved one public verification issue and four Discord messages after automatic approval review required specific live-test authorization. [Issue80](https://github.com/Valgorithms/Frontier-Systems/issues/80) is closed. Bug label run38151787393 created thread1558865266669256715; enhancement label run38151865989 created thread1558865518390153227. Both labels were removed before closure2026-10-11T15:35:52Z. Successful closure run38151939659 posted messages1558865786045599929 and1558865802718093435 into those original respective threads; persisted routing records confirm both closed timestamps. The separate state branch now exists with credential-free issue80 mappings. No game images, release, deployment or external outreach occurred.

Webhook receipt/channel IDs plus successful workflow/state writes establish live delivery. Discord per-user push/notification preferences and concurrent-event/uncertain-send recovery are not claimed as verified. Test issue and clearly marked forum threads remain as closed verification evidence.

Read-only Discord DOM verification additionally confirmed exactly two unique rendered messages in each respective forum thread, correct dedicated hook authors, exact starter/closure titles and all four links to issue80. No extra messages, edits, follows or reactions were sent. Screenshot attempts timed out; no screenshot evidence is claimed.
