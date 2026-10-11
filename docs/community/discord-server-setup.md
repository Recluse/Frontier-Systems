# Frontier Systems Discord setup

Verified through authenticated browser UIs on 2026-10-10 (America/New_York). Guild: `1558661083131019364`. Recheck mutable settings before future changes.

## Channels and Community

Community enabled after action-time owner approval relayed by the Coordinator. Rules: welcome-and-rules. Community and safety notices: private community-updates. Verified email, all-member media filtering, mentions-only defaults and safer everyone permissions enabled by the wizard. Safety Setup shows raid protection 3/3, DM/spam protection 5/5 and AutoMod 3/5; everyone has zero risky permissions.

| Area | Channel | ID |
| --- | --- | --- |
| START HERE | welcome-and-rules | 1558662991740936274 |
| START HERE | announcements | 1558663027920998480 |
| START HERE | roadmap | 1558663174658592818 |
| START HERE | support-development | 1558663227523727452 |
| COMMUNITY | general | 1558661084175540276 |
| COMMUNITY | bot-commands | 1558664887364751390 |
| COMMUNITY | suggestions (forum) | 1558669253161390130 |
| PLAYTESTING | playtest-info | 1558663599713685565 |
| PLAYTESTING | playtest-chat | 1558663811014328320 |
| PLAYTESTING | bug-reports (forum) | 1558669102741065838 |
| PLAYTESTING | Playtest Voice | 1558669426625089545 |
| STAFF | staff-chat | 1558663933940731985 |
| STAFF | mod-log | 1558664266377338951 |
| STAFF | community-updates | 1558664833971261471 |

START HERE category: `1558662567063195648`. Original Voice Channels / General retained. START HERE denies everyone messages/posts, thread replies and public/private thread creation. Announcements reopened and confirmed synced with these restrictions. Playtest-info has equivalent channel restrictions and is intentionally unsynced from its discussion category.

STAFF denies everyone visibility and grants Developer/Moderator visibility. Children inherited staff access. Mod-log is intentionally unsynced: Tutelar has visibility and explicit Send Messages allow; everyone Send Messages is denied. Staff inherit read-only logs, except owner privileges. Ko-fi and Bridge have no staff visibility override.

Welcome/rules, announcements, roadmap, playtest-info and funding messages were sent and observed in history. They describe a prototype without a promised release date, public demo, test schedule or guaranteed paid access. Both forums have saved guidelines for focused reports, redacted logs, constructive discussion and private security reporting. Internal game images were not published.

## Roles and Ko-fi

Saved hierarchy: Developer, Moderator, Ko-fi Bot, Tutelar, Bridge, Frontier Supporter, Frontier Workshop Supporter, Development Updates, Frontier Patron, Playtester, Playtest Alerts, everyone. Staff is above all bots; grantable tiers are below Ko-fi. Each bot has Administrator off.

| Role | ID | Purpose |
| --- | --- | --- |
| Developer | 1558665097050722365 | Unassigned staff role |
| Moderator | 1558665424785252464 | Unassigned staff role |
| Frontier Supporter | 1558665432947359825 | Ko-fi $5/month |
| Frontier Workshop Supporter | 1558665441230983231 | Ko-fi $15/month |
| Frontier Patron | 1558665458222243901 | Ko-fi $30/month |
| Development Updates | 1558665449879769220 | Reserved opt-in notices |
| Playtester | 1558665467294523403 | Reserved test role |
| Playtest Alerts | 1558666160952574033 | Reserved opt-in notices |

Supporter and opt-in roles individually inspected: no enabled role-level permissions. They inherit ordinary member access. Ko-fi has only Manage Roles and Create Invite enabled. Tutelar retains approved moderation/ticket/channel/message/audit permissions; Bridge retains approved messaging, thread replies and webhooks. No member assignments were made.

Ko-fi shows Connected to Frontier Systems and Contributor eligibility. Global one-time and monthly reward lists are empty. Each matching tier reward was saved, closed, reopened and observed persisted. Prices, existing campaign copy and payment details preserved. Tier IDs: Supporter `a4484e3f-f4ba-4b68-bfeb-c8d56321125b`; Workshop `3819a881-ed5b-4acf-b60c-1a4125f7be34`; Patron `e22c9a61-39ab-44bf-9f40-b04f3c1046d9`.

Public funding: <https://ko-fi.com/valgorithms> and <https://ko-fi.com/valgorithms/tiers>. No purchase/payment performed. Paid assignment/removal is not end-to-end verified.

## AutoMod and runtime evidence

Mention spam enabled. Suspected spam blocks messages and alerts private mod-log. Commonly Flagged Words blocks Insults & Slurs and Sexual Content; Severe Profanity is not selected. No custom keyword/name rule or automatic timeout added. All-member sensitive media filtering confirmed. No disruptive/prohibited-content test sent.

Installed apps: Tutelar `662093882795753482`, Bridge `1548742142011121785`, Ko-fi `836232765942923305`. Integrations lists all three; managed roles show one member each.

Live interactions in bot-commands:

- Bridge `/bridge list` answered no bridges in this server.
- Tutelar `/config view` answered with both targets initially unset.
- Tutelar `/config set` for Log channel -> mod-log confirmed success.
- Tutelar `/config set` for Mod-log channel -> mod-log confirmed success.

Tutelar Configuration uses Store-backed per-guild overrides. No bootstrap, process restart, command registration, token read or host config edit performed. These prove served handlers and acknowledged configuration, not continuous uptime, restart persistence, ticket delivery, moderation-case delivery or audit-event delivery.

## Acceptance limits and follow-up

Owner approved and the UI saved Moderator Manage Messages, Manage Threads and Posts, Timeout Members and View Audit Log. The role was reselected and all four checked states were verified; Administrator stays off. Developer has scoped Send Messages and Create Posts allow in START HERE and Send Messages allow in playtest-info. Ordinary members remain read-only.

No human staff assignments specified or made. Update/playtest self-assignment workflows remain reserved. Moderator 2FA and member-prune restriction were disabled when inspected; not changed. Discovery, forum tags/default reactions and ticket panels are not configured in this pass. Verify ordinary-member views with an authorized non-staff account before broad invitations. Paid claims require a separately authorized entitlement test.

## FAQ and Server Guide (2026-10-11 UTC)

The owner requested basic FAQ information and website links. Created public `faq` channel `1558677296108544100` under START HERE, with inherited read-only permissions. Verified @everyone cannot send messages, send in threads, or create public/private threads. Posted two FAQ messages covering the prototype and future scope, official website/support/availability/source links, current source-running instructions, development channels, Ko-fi support and memberships, supporter roles, playtesting, bug reports, suggestions and community rules. The FAQ explicitly states that support is not a preorder/key/access guarantee, sales are closed, and the website certificate is pending; users should not bypass security warnings.

Enabled Onboarding and Server Guide, then verified the live guide shows the welcome message and `FAQ — Start here` resource. Opened that resource and confirmed both FAQ messages render. Default channels are general, welcome-and-rules, announcements and playtest-info; only general is chattable. No customization questions, role grants or private-channel access were added. Three custom tasks invite members to read the FAQ, check announcements and introduce themselves in general; Discord also includes its rules task.

[FAQ resource](https://discord.com/channels/1558661083131019364/1558677296108544100). Local cropped guide proof is retained in ignored `var/ci/discord-faq/guide.jpg`; it is not public gallery media. Verification used the signed-in owner UI, not a new non-staff account. Revisit the FAQ certificate note when HTTPS is verified and availability claims when approved releases or playtests are announced.

For future log changes use served `/config set` then `/config view` in this guild. Never bulk-overwrite commands or start a bot bootstrap as a test. Keep Bridge networks unlinked unless separately authorized. Verify UI save/reopen states because Discord transitions can lag.

Local UI proof retained outside the public repository: discord-roles.jpg, discord-safety.jpg, discord-community.jpg and kofi-supporter.jpg in this task visualization directory. UI captures are not cleared creative assets or game images and are excluded from the PR.

## Gameplay-interest onboarding (2026-10-10 America/New_York)

Configured and saved one optional pre-join question: **What would you most like to do in Frontier Systems?** `Allow multiple answers` and `Required` are both off. It is also available after joining under **Channels & Roles → Customize**, where members can change their choice. No personal information is requested.

| Answer | Self-assigned role | Existing public channels added to the channel list |
| --- | --- | --- |
| Building & engineering | Primary: Building & engineering | suggestions |
| Mining, refining & logistics | Primary: Mining, refining & logistics | suggestions |
| Cooperative repair & life support | Primary: Repair & life support | suggestions |
| Exploration & science | Primary: Exploration & science | suggestions |
| Future: colony progression | Primary: Future colonies | roadmap, suggestions |
| Future: ships & spaceflight | Primary: Future ships & spaceflight | roadmap, suggestions |

The two future descriptions explicitly state that these are longer-term goals, unavailable now, with no release or test access promised. The building description also states that an interest selection promises neither a release date nor test access. The other descriptions describe desired activities, not a release announcement.

Created six dedicated roles below all existing roles and above everyone. Every role's saved Permissions panel was reopened: `Clear permissions` was disabled and no permission switch was checked, including Administrator. No channel overrides were added. They inherit ordinary member access and do not grant paid entitlements, staff access, test access or notification subscriptions. Default color, no separate member display and no anyone-mention flag were retained. No member was manually assigned a role.

Left secondary-interest questions out of this first pass to keep the primary count unambiguous and avoid a duplicate role set. General discussion and suggestions can capture additional interests. A later multi-select question should use separate secondary roles so primary and secondary counts do not become indistinguishable.

Verification: left and reopened onboarding settings; all six answer editors retained the exact role/channel mappings above. The live new-member preview's Channels & Roles page rendered all six choices. The existing welcome message, three custom tasks, rules task and `FAQ — Start here` resource remained visible in the preview. The FAQ resource and both existing messages were inspected before the change. Default Channels was reopened and still showed general, welcome-and-rules, announcements and playtest-info: 4 total, 1 chattable. STAFF channels remain locked and ineligible without unlocking; no unlock, safety, staff/supporter permission or integration changes were performed. Onboarding and Server Guide remain enabled. The UI reports 6 of 11 public channels covered; the remaining five were deliberately not mapped to unrelated gameplay interests.

Staff can inspect current role member counts and members through Server Settings → Roles. These reveal the currently self-declared primary preference of participating members, not a representative player survey, historical answer log, feature demand forecast or verified play behavior. Skipped answers, later changes, departures and any future manual role edits affect counts. Discord's inspected UI did not expose a dedicated aggregate onboarding-answer export or historical report; do not claim one. No response data was exported. Preview verification used the signed-in owner, not a fresh ordinary-member account; real join-time assignment, changing/removing a live member's answer and event delivery were not exercised.

A cropped local proof of the member-facing choices is retained outside Git at `discord-interest-preview.jpg` in this chat's visualization directory. It excludes the profile card and other-server sidebar and is operational UI evidence, not licensed game/gallery media. One save was initially rejected by automatic approval review because its evidence still showed `new role`; a fresh inspection confirmed the intended repair role name and zero permissions, and the verified save succeeded. No approval remains blocked.

This record was made from an isolated managed worktree based on current `origin/dev-master`; it does not alter game runtime code. Validation is browser save/reopen and preview evidence plus `git diff --check`. PHP/Godot runtime tests are not relevant to these external settings and were not run locally.

## References and repository verification

- [Discord Community Guidelines](https://support.discord.com/hc/en-us/articles/360035969312)
- [Discord AutoMod FAQ](https://support.discord.com/hc/en-us/articles/4421269296535-AutoMod-FAQ)
- [Discord Forum FAQ](https://support.discord.com/hc/en-us/articles/6208479917079-Forum-Channels-FAQ)
- [Ko-fi Discord rewards](https://help.ko-fi.com/hc/en-us/articles/360020363857-Setting-up-Discord-rewards-with-Ko-fi)

Documentation-only repository change. Browser save/reopen checks and bounded live interactions above are distinct from `git diff --check` and PR CI. PHP/Godot tests were not run for this operational record; they cannot verify external Discord settings.
