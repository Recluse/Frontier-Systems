# Coordinated milestone work

The owner requested separate milestone chats on 2026-10-10. The primary **Advance project milestones** chat coordinates integration and owns the current physical wall milestone. Each independent chat uses a managed worktree and a feature branch with a draft PR targeting dev-master. Concurrent chats do not push dev-master, merge, deploy or modify global milestone reports. Each reports its exact commit, PR, tests and acceptance limitations for coordinator review.

| Chat | Assigned milestone | Scope | Dependencies / non-goals |
| --- | --- | --- | --- |
| Improve construction placement feedback | Procedural placement ghost, coordinates/reach feedback and selection affordances | Presentation helpers, machinery UI, focused tests and its own milestone doc | No canonical rules or production/schema changes; preserve additive spatial-wall UI |
| Harden checkpoint recovery | Safe corruption/interruption/stale-completion behavior and accurate durable acknowledgement | Persistence adapters, temporary fault-injected tests and its own milestone doc | No per-command journal, account/database work or wire/snapshot migration |
| Build terrain excavation ownership | Bounded finite excavation/deposition owner and restart/retry contracts | Existing material plans plus terrain-specific owner/schema/tests/doc | No live world/inventory/production bridge, mesh editing or planet streaming |

Chat IDs respectively: `01a12845-2c55-76b3-bd83-3b4cd9d6a4db`, `01a12845-3a53-7ab3-9334-6c1dd315a035`, `01a12845-482f-75d0-9cb0-b534d977652e`.

The coordinator checks compact chat snapshots, reviews resulting diffs and runs checks appropriate to integration. Branch CI and draft PRs are review evidence; they do not themselves authorize merging or publishing. The repository separately authorizes the coordinator's milestone commits/pushes on dev-master. Shared schema and authority boundaries are serialized by the coordinator. Live services and production deployment remain outside these assignments.
