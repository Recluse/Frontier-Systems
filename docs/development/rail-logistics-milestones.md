# On-rail vehicles and logistics milestones

Owner requested Astroneer-inspired trains in the milestone roadmap on 2026-10-10 (America/New_York). Planned work, not implemented features. Queue after the basic finite engineering loop, inventory transactions, recovery and usable construction; do not interrupt active implementation chats.

## Reference and independent direction

Reviewed System Era's [Rails Update, version 1.25.147.0](https://blog.astroneer.space/p/rails-update/). Relevant reference mechanics are connected rail posts, branch junctions, coupled vehicles, powered movement, station loading/unloading, autonomous travel, train-wide storage sensing and arrival/departure signals. Astroneer also conducts oxygen and power along rails. Frontier should model any utility links as explicit components using its existing network owners; rails must not implicitly create breathing gas or electrical supply.

No Astroneer code, assets, names, UI or balance values are imported. The reviewed page is a version-labelled descriptive reference, not an immutable source revision or a reuse license.

## Ordered milestone queue

| ID | Deliverable | Prerequisites | Concrete acceptance |
| --- | --- | --- | --- |
| rail-01 | Finite rail construction and bounded track graph | Existing material construction and spatial authority | Build/recover supports and segments with stable IDs and material provenance. Validate span/clearance and occupied-track edits. Reject stale/foreign requests without matter loss; graph restores identically. |
| rail-02 | Powered cart and manual on-rail travel | rail-01; bounded vehicle motion and component energy contracts | One extraction-to-refinery route, reversible travel, braking/end stops, safe boarding and finite energy. Persist segment/progress/direction and passengers; reconnect cannot duplicate a cart or move it beyond the track. |
| rail-03 | Coupled cargo trains and station transfers | rail-02; inventory/container transactions | Bounded acyclic coupling and consist mass/capacity. Load/unload whole legitimate items atomically at a stopped station. Full/foreign/stale/retried transfers conserve cargo; coupling, uncoupling and restart preserve unique ownership. |
| rail-04 | Junctions, dispatch and automatic routes | rail-03; server-owned controls/signals | Three-way branch selection, call/dispatch commands and a repeatable two-station delivery. Reserve occupied segments and switches; competing trains stop safely. No remote switch/route bypass; lost acknowledgements and restart do not repeat deliveries. |
| rail-05 | Storage sensors, repair and optional utility integration | rail-04; bounded signal processing; integrated power/gas networks for utilities | Train-wide inventory state and arrival/departure signals drive authorized routes with bounded processing. Damaged drive/coupler/rail retains repairable parts and cargo. Optional utility ports conserve energy/gas and isolate breaks; disabled supply never implies safe breathing. |

Each row becomes its own isolated milestone chat and document when dependencies are ready. Each must define simulation owner, fixed-tick cadence, explicit units, versioned persistence/migration, command authority, failure/recovery and bounded profiling counts. Presentation observes the canonical graph and vehicle state; external services and unloaded UI cannot advance trains. Require focused Windows/Linux contract checks, two-client retry/recovery tests when transport is introduced, and actual graphical acceptance before claiming usable driving. Initial scope is one local route, not planets, procedural railway streaming or an unrestricted rail physics simulation.
