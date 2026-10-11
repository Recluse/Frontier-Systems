# Moonbase Alpha gameplay inspiration

Owner-requested reference, reviewed 2026-10-11 UTC. This means NASA's 2010 game, not the television setting. These are independently authored Frontier Systems proposals, not implemented features or release promises.

## Reviewed evidence

[NASA's 2011 account](https://spinoff.nasa.gov/Spinoff2011/cg_4.html) describes a bounded cooperative emergency: restore life support with available repair tools, robots and rovers, with time and resource use affecting performance. The [official Steam description](https://store.steampowered.com/app/39000/Moonbase_Alpha/) describes repairing or replacing damaged equipment after an impact, transporting players and supplies, piloting repair robots, and multiple successful approaches. Neither page is an immutable source revision. The linked manual was inaccessible through the research tool and was not reviewed; no detailed repair minigame, battery or oxygen rules are attributed to it.

## Proposed Frontier mechanics and order

| Priority | Mechanic | Independently authored adaptation and acceptance |
| --- | --- | --- |
| First | Diagnose, isolate, repair and restart | Start with one existing machine and a visible failed capability. Show the cause, required tool, work/resources and resulting capability. Damage retains stable components. A two-client test must reject stale/double work and conserve resources through retry and restart. |
| First | Cooperative repair logistics | One player retrieves finite parts while another isolates equipment and prepares work. Shared task markers expose authoritative reservations and blockers; no mandatory player count or class lock. Disconnect releases or recovers reservations without duplicating material. |
| Next, after network integration | Infrastructure dependencies | Let players trace loss of service from the consuming device through power and fluid connections. Display measured state separately from predicted recovery. A repair changes only the affected capabilities; repairing a downstream device cannot create missing upstream supply. |
| Later, after breathing/pressure integration | Recoverable emergency scenarios | Use a contained outpost failure with several repair paths and useful partial recovery. Derive urgency from simulated reserves and flow, with optional timed challenge mode. Persist incident state and recovery; avoid a global countdown that erases a persistent colony or guarantees occupant death. |
| Later, after vehicle/body contracts | Cargo rovers | Carry physically accounted tools, parts and passengers. Capacity, loading, unloading and damage use existing inventory and component owners. No cargo duplication on reconnect or vehicle replacement. |
| Later, after remote-body authority | Remote repair robots | Robots use replaceable task modules, finite stored energy and the same command/capability rules as other bodies. Validate operator access and reach; loss of control stops unsafe work while preserving the robot and cargo. |

The first candidate milestone should be a narrow, playable machinery fault-and-repair interaction after current implementation chats finish. Inspect existing tool-maintenance and machinery owners first, reuse their contracts, and scope any missing transaction authority separately from presentation. Do not introduce lunar terrain, vehicles, remote bodies and atmosphere changes in the same milestone.

## Contract boundaries

Follow [survival and recovery](survival-pressure-and-recovery.md), [modular tools](../architecture/modular-tool-components.md), [breathing and pressure](breathing-mixtures-and-pressure-control.md), and [persistence/commands](persistence-and-command-boundary.md). Godot simulation owners apply tick commands; UI and service callbacks never settle repairs. Each implementation must identify owner, cadence, persisted revision, failure behavior and bounded profiling counters, with meaningful Windows/Linux checks. Work progress cannot debit resources twice or waive permissions.

Optional communication aids should begin with text task markers and accessible status messages. Voice or text-to-speech is not a prerequisite for cooperative repairs and needs its own moderation, accessibility and dependency review if proposed.

## Provenance

Only public descriptive pages were reviewed. No game source, assets, screenshots, audio, UI layouts or text were imported. NASA publication/free availability does not establish file-level MIT-compatible reuse rights; the Steam page lists a third-party EULA and an all-rights-reserved notice. Any proposed import requires separate rights clearance. Keep this game as a behavioral reference alongside Civ13's later progression direction.
