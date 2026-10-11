# Coordinated milestone work

The owner requested separate milestone chats on 2026-10-10. The primary **Coordinator** chat reviews and integrates milestones. Each implementation chat uses a managed worktree and a feature branch with a draft PR targeting dev-master. Concurrent chats do not push dev-master, merge, deploy or modify global milestone reports. Each reports its exact commit, PR, tests and acceptance limitations for coordinator review.

| Chat | Assigned milestone | Scope | Dependencies / non-goals |
| --- | --- | --- | --- |
| Improve construction placement feedback | Procedural placement ghost, coordinates/reach feedback and selection affordances | Presentation helpers, machinery UI, focused tests and its own milestone doc | No canonical rules or production/schema changes; preserve additive spatial-wall UI |
| Harden checkpoint recovery | Safe corruption/interruption/stale-completion behavior and accurate durable acknowledgement | Persistence adapters, temporary fault-injected tests and its own milestone doc | No per-command journal, account/database work or wire/snapshot migration |
| Build terrain excavation ownership | Bounded finite excavation/deposition owner and restart/retry contracts | Existing material plans plus terrain-specific owner/schema/tests/doc | No live world/inventory/production bridge, mesh editing or planet streaming |

Chat IDs respectively: `01a12845-2c55-76b3-bd83-3b4cd9d6a4db`, `01a12845-3a53-7ab3-9334-6c1dd315a035`, `01a12845-482f-75d0-9cb0-b534d977652e`.

The owner now explicitly authorizes the coordinator to review completed milestone PRs, merge them with admin bypass if repository protections require it, and create a successor milestone chat after each merge. Exact-head required CI must pass; bypass does not waive failed or missing checks. Shared schemas and authority boundaries are serialized. At most three implementation chats run concurrently. Fixed-loopback acceptance tests use port 27849 serially. Live services, releases and production deployment remain outside these assignments.

## Completed first wave

| Milestone | Reviewed head | PR | Required CI | Verified merge |
| --- | --- | --- | --- | --- |
| Machine placement feedback | `d1da671cc79f752b69c7162a531c7d02ef171f0a` | [#2](https://github.com/Valgorithms/Frontier-Systems/pull/2) | [PR CI success](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38097625885), [branch CI success](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38097623121) | `0dfdb8d61d7ca6745fb6e242cbf0f323171a04f3` |
| Checkpoint recovery | `baee588685265161b83bedd07d63483aac356baa` | [#1](https://github.com/Valgorithms/Frontier-Systems/pull/1) | [PR CI success](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38097654887), [branch CI success](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38097652129) | `3cafbde0ba3a80ec7f9d1f996fcc878ee05a40c6` |
| Finite terrain owner | `2ca77b2d65a58da1f0415e42492cb6dfc5de6672` | [#3](https://github.com/Valgorithms/Frontier-Systems/pull/3) | [PR CI success](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38097764379), [branch CI success](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38097761314) | `7e2c4daf35aa4d7f8bfda47198ebfbcc21156260` |

No admin bypass was needed. Review confirmed presentation-only ghost state and preserved v7 wall controls; verified staged writes, bounded recovery and matching worker acknowledgements; and finite terrain provenance, pure plans, retained/expired retries and restart replay. Terrain remains a domain owner; it does not yet imply live inventory transfer or graphical excavation. Exact branch/PR CI includes Windows/Linux PHP, Godot, telemetry integrations and development exports. Merged-head integration CI is separate: [first combined run](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38098099136). On combined head `7e2c4da`, all seven coordinator checks passed: import, startup, checkpoint recovery, real two-client durable acceptance, machine placement feedback, spatial walls and terrain ownership. Logs/JUnit are under ignored `var/ci/coordinator-wave-1`.

## Completed second wave

| Chat | ID | Scope | Integration constraints |
| --- | --- | --- | --- |
| Add wall construction placement feedback | `01a12853-6d0b-7920-8136-b6cf06fb886c` | Floor/grid/orientation ghost, owned-plate intent, pending target and selected wall feedback | Presentation only; wall commands, schemas and authority unchanged |
| Add bounded checkpoint backup history | `01a12854-5d3d-7a03-b098-cfa237928117` | Opt-in bounded verified history, pruning and explicit stopped-world recovery selection | Detached worker I/O; active save acknowledgement remains separate from backup failure |
| Register authoritative terrain commands and recovery | `01a12855-3bab-7a10-9ef3-8a12c805ae5e` | Fixed-tick terrain owner registration, authenticated tool/reach/retry commands and checkpoint migration | Separate finite fixture budget; legacy saves grant no matter; loose transfer escrow stays terrain-owned |

| Milestone | Reviewed head | PR | Exact-head required CI | Verified merge |
| --- | --- | --- | --- | --- |
| Opt-in checkpoint history | `3e285d20ab4b9ed02fbb5ea2c031303d423be286` | [#4](https://github.com/Valgorithms/Frontier-Systems/pull/4) | [PR CI](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38098740532), [push CI](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38098739445): success | `552a68b910491c4ee1315db3a4b3c7768ade5da4` |
| Physical wall previews | `5fca8f681275a1576bcd4f2fa0580a487bcac570` | [#5](https://github.com/Valgorithms/Frontier-Systems/pull/5) | [PR CI](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38098724926), [push CI](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38098722054): success | `2f879448c5079fafea4d14610a84ff2ccfc787cc` |
| Terrain runtime/escrow | `cb8c79cb70842a8f9a61d711748d7733bb41ee9c` | [#6](https://github.com/Valgorithms/Frontier-Systems/pull/6) | [PR CI](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38098862021), [push CI](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38098860031): success | `ad2367296149647e29bb38c9ad8299291258c19e` |

Review found no outstanding runtime/authority blockers. The wall reproduction paths were corrected before final CI. Checkpoint history preserves active acknowledgements, last recoverable backups and explicit stopped-world recovery into a fresh destination; its diagnostics stay separate from the wire status. Terrain runtime validates tools, reach, supporting hands, claimant permissions, sequence allocation and atomic restart, with zero-budget legacy migration. Neither terrain escrow nor previews imply physical terrain pickup or room sealing. Admin bypass was not needed. On combined head `ad23672`, all nine Windows Godot checks passed: import, startup, history, recovery, real two-client checkpoint acceptance, machine placement feedback, spatial walls, terrain runtime and wall placement feedback. Logs/JUnit are under ignored `var/ci/coordinator-wave-2`.

## Active third wave

| Chat | ID | Scope | Integration constraints |
| --- | --- | --- | --- |
| Expose checkpoint history operator controls | `01a12865-952a-71f3-b022-34e1b61205e5` | Strict opt-in launch configuration, bounded metadata listing and explicit fresh-destination recovery | Persistence/operator tooling and narrow host-startup wiring; no network/domain schemas or automatic rollback |
| Enforce machinery placement obstruction rules | `01a12865-b991-7a00-a83d-0698045fe6c3` | Conservative server placement/growing-module obstruction checks | Machinery/Production only; deliberate legacy restore compatibility; no terrain or presentation redesign |
| Add cooperative terrain command controls | `01a12867-4ceb-7fe0-b38a-0c3e16b1cd29` | Authenticated two-client terrain commands, validated scoped projection and readable escrow controls | No physical terrain pickup, second payload provider, timed digging or mesh editing; peer ordinals must not collide in ack routing |

Each successor starts from current origin/dev-master in its own managed worktree and owns its own milestone documentation. Rebase before final validation. The coordinator owns cross-milestone review, merge and successor creation.

## Ongoing coordination

## Third-wave integration progress

Checkpoint operator PR [#8](https://github.com/Valgorithms/Frontier-Systems/pull/8) was reviewed at `c118ced527b1358e46606896f184ae07f3e78840` and merged normally as `9b301fcb8173b11ea37f2b0e5c03f8c235539933`. Exact-head [PR CI](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38099816480) and [push CI](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38099812844) passed, including Windows/Linux operator CLI checks. Review confirmed strict opt-in limits, metadata-only diagnostics, exact descriptor revalidation, fresh stopped recovery and source preservation. Worker Windows evidence includes seven Godot checks, launcher/CLI exit checks and final-head two-client acceptance in 36.21 seconds. No new graphical images were provided for this milestone's gallery.

Successor **Add checkpoint recovery preflight**, chat `01a1287a-0770-7503-973f-d8ef8cd7a524`, uses explicit Sol/medium and starts from current origin/dev-master in a managed worktree. It owns bounded read-only descriptor/domain preflight in persistence/operator helpers, focused tests and its own milestone doc; bootstrap, terrain, machinery and shared network/schema boundaries remain outside its scope. The other two third-wave implementation chats remain active, preserving the three-chat limit.

Machinery PR #7's earlier head failed an inherited scratch fixture that used newly forbidden overlapping placements. Reviewed corrections at `73282df98da56d7eeb61e17ef13d099020f12f86` only move test/capture targets to clear reachable positions and update evidence. Runtime authority remains unchanged from reviewed `c99907f`; exact-head CI remains pending, so no merge is authorized yet.

Future milestone completion reviews select suitable verification captures for `docs/gallery/`, using Git LFS and the gallery's provenance/acceptance metadata rules. Repository storage does not authorize external public publishing.

The user explicitly approved recurring coordination on 2026-10-10. Active heartbeat `coordinate-frontier-milestone-prs` runs in this chat every ten minutes until the owner changes or stops it. It reviews completed PRs, requires exact-head CI, merges with a matching-head guard, queues one successor per merge and updates this ledger. It stays quiet while state is unchanged or non-actionable and reports meaningful completion, merge, failure or required user action. It does not authorize releases/deployment or waive separate cross-chat write authorization.

Live fixed-port reservations are recorded in ignored `var/ci/milestone-coordination/port-reservations.json` in the primary checkout and confirmed through chat messages/snapshots. Consult that record before granting 27849; if missing, inspect the latest reservation messages rather than assuming it is free. The wall graphical capture uses separate port 27852. Never terminate another chat's listener to obtain a test port. Reservation handoffs alone do not require a fresh versioned milestone commit or another full CI run.
