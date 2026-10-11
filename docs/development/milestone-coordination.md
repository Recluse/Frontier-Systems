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

## Active successor wave

| Chat | ID | Scope | Integration constraints |
| --- | --- | --- | --- |
| Add wall construction placement feedback | `01a12853-6d0b-7920-8136-b6cf06fb886c` | Floor/grid/orientation ghost, owned-plate intent, pending target and selected wall feedback | Presentation only; wall commands, schemas and authority unchanged |
| Add bounded checkpoint backup history | `01a12854-5d3d-7a03-b098-cfa237928117` | Opt-in bounded verified history, pruning and explicit stopped-world recovery selection | Detached worker I/O; active save acknowledgement remains separate from backup failure |
| Register authoritative terrain commands and recovery | `01a12855-3bab-7a10-9ef3-8a12c805ae5e` | Fixed-tick terrain owner registration, authenticated tool/reach/retry commands and checkpoint migration | Separate finite fixture budget; legacy saves grant no matter; loose transfer escrow stays terrain-owned |

Each successor starts from current origin/dev-master in its own managed worktree and owns its own milestone documentation. Rebase before final validation. The coordinator owns cross-milestone review, merge and successor creation.

## Ongoing coordination

The user explicitly approved recurring coordination on 2026-10-10. Active heartbeat `coordinate-frontier-milestone-prs` runs in this chat every ten minutes until the owner changes or stops it. It reviews completed PRs, requires exact-head CI, merges with a matching-head guard, queues one successor per merge and updates this ledger. It stays quiet while state is unchanged or non-actionable and reports meaningful completion, merge, failure or required user action. It does not authorize releases/deployment or waive separate cross-chat write authorization.

Current fixed-port reservation: checkpoint-backup-history chat holds 27849 for final acceptance; wall-placement-feedback is next in the queue. The coordinator grants/releases reservations through chat messages and snapshots. The wall graphical capture uses separate port 27852. Never terminate another chat's listener to obtain a test port.
