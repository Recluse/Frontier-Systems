# Privacy-aware DiscordPHP event logging

Implemented as an opt-in Godot host outbox plus the MIT PSR-4 `packages/event-logging` adapter. See its [configuration, contracts and guarantees](../../packages/event-logging/README.md). A single existing DiscordPHP Monolog 3 logger receives validated events; a ReactPHP queue routes them to separately configured public, staff or private-conversation channels. Native cached permission checks fail closed for staff/private destinations, and typed events cannot bubble into lower-priority unclassified exporters.

Automatic integration covers discrete command outcomes, production batch completions and sustained extraction cycles. Every subsystem can publish registered events through `world.event_outbox.publish`; public/private chat and LLM prompt/response event kinds are already classified for later consumers. Unknown kinds and audience downgrades reject. No logging callback mutates canonical state or waits inside a simulation tick.

Local verification: PHP routing/ACL/policy/deduplication/UTF-8/overflow/failure/deadline tests; authenticated streaming HTTP; actual Godot-to-PHP ingestion with credential-field rejection and unchanged world snapshot; editor import; Composer metadata, strict PSR-4, Windows runtime policy, formatting and unit checks. CI covers PHP 8.3/8.5 and Windows/Ubuntu, plus the integration harness. Monolog runtime dependency is documented in third-party notices.

Configuration remains necessary: real guild/channel IDs, staff and conversation audiences, complete Discord cache and a secret host token. No live Discord messages or real LLM/private-chat content were sent during development. SDK compatibility was checked against local DiscordPHP revision `580c66a1d8a37f68cb570fd0e20497ac1f516f52` (`getLogger`, `getLoop`, channel lookup/message builder and permissions access). The generic receiver/queued transport were exercised; live platform permissions and delivery require an operator deployment check.

Durable audit journals, large correlated trace chunks, log retention/encryption and a general production host-authentication service are future work. Existing queues/receipts are bounded and memory-only; overload and uncertain delivery are exposed in metrics. This is not a guarantee that every event survives a crash or Discord outage.

Next gameplay milestone: terrain excavation, preserving the environmental extraction/refinement/recycling priority and conserved material/component contracts.
