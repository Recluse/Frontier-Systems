# Godot Networking, Physics, and World Architecture

## Networking and authority for a persistent cooperative world

### Takeaway

Use a dedicated, server-authoritative Godot simulation for each active physical region. Clients send intents; the server validates actions and owns the canonical state. Persisted colony/world data should be modeled separately from Godot scene nodes and session replication.

### Cited Findings

- Godot 4.7 high-level multiplayer is a SceneTree-managed API with ENet, WebRTC, and WebSocket peers; ENet is the ordinary default multiplayer implementation. [High-level multiplayer](https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html)
- Godot documents that its high-level multiplayer API is not automatically secure: persistent/competitive game state should be server-authoritative, client RPC arguments validated, and frequently triggered actions rate-limited. It specifically recommends sending input or movement intent for server validation instead of accepting the client's final position. [High-level multiplayer](https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html)
- `MultiplayerSpawner` handles authority-side spawning and `MultiplayerSynchronizer` replicates configured properties from the multiplayer authority; synchronizers support per-peer visibility. They synchronize node properties, not `Object`/`Resource` values such as arbitrary server persistence records. [MultiplayerSpawner](https://docs.godotengine.org/en/4.7/classes/class_multiplayerspawner.html), [MultiplayerSynchronizer](https://docs.godotengine.org/en/4.7/classes/class_multiplayersynchronizer.html)
- Godot RPCs require corresponding node paths and RPC declarations on peers; reliable transfer has a performance cost. Channels can separate independent reliable traffic (Godot gives chat-vs-gameplay as an example), while unreliable-ordered transfer suits frequently superseded movement data. [High-level multiplayer](https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html)
- Built-in multiplayer authentication can gate peers, but the docs still advise protecting RPCs and validating gameplay requests. [High-level multiplayer](https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html)

### Inferences

- Treat DiscordPHP/Social SDK as the chat, presence, and voice layer; keep Godot networking for simulation commands, state deltas, and snapshots. Keep these concerns independently testable, and don't serialize voice/chat media through Godot game-state RPCs.
- Use stable entity IDs and versioned domain records as the persistence layer. Scene nodes should be runtime views/physics objects keyed by those IDs; Godot's spawn/synchronization helpers are transport conveniences, not the persistent-world database.
- Model interactions as server-validated commands (`open_door`, `set_breaker`, `move_item`, `run_program`) with actor, target, permissions, preconditions, and an idempotency/request ID. Have the authority apply a transaction, persist it, then publish the resulting state revision/event.
- Prefer custom, discrete system simulation for power, atmosphere, fluid, thermal, and machine networks, each with its own authored update cadence. Reserve rigid-body physics for local collisions, tools, loose objects, and character movement. This avoids treating every engineering state change as a physics body or replicated transform.
- Begin with one authoritative process per world/region. Define explicit APIs between region simulation, durable storage, account/auth, and Discord integration so region services can later split by colony/ship without rewriting domain mechanics.

### Gaps

- Godot's documentation does not prescribe a persistent-world database, transactional event model, multi-region service topology, or target player count; choose these after prototype load and recovery measurements.

## Headless servers, physics, and operational constraints

### Takeaway

Godot 4.7 can run the game project headlessly and has a dedicated-server export mode that strips visual resources. This supports the same authoritative simulation code on servers, but server code must be designed not to depend on client-only visuals or assume a rendered client is present.

### Cited Findings

- Since Godot 4.0, a dedicated server can use the regular engine/export template with `--headless`; no special server binary is needed. Dedicated-server export presets can strip visual assets while retaining gameplay resources. [Exporting for dedicated servers](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_dedicated_servers.html)
- A project can detect the `dedicated_server` feature tag, or detect the headless display server; dedicated export adds the tag and forces headless mode. The docs warn that removing resources which scenes still reference can make them fail to load. [Exporting for dedicated servers](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_dedicated_servers.html)
- `--headless` disables rendering and window-management functions; most RenderingServer calls return dummy values in that mode. [RenderingServer](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html)
- Physics runs at a fixed tick rate, 60 ticks/sec by default. Increasing tick rate raises CPU cost; physics interpolation smooths rendering but has caveats for teleporting and can add input latency. Godot notes that internet multiplayer often benefits from custom interpolation because remote snapshots do not necessarily line up with local physics ticks. [Physics interpolation introduction](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_introduction.html), [Jitter and stutter](https://docs.godotengine.org/en/4.7/tutorials/rendering/jitter_stutter.html)
- Godot 4.4 introduced built-in Jolt Physics, and the 4.7 docs say new projects use it by default. The built-in Jolt module supports separate-thread physics, but that thread-safety is described as not thoroughly tested and experimental. Jolt also has some joint-property differences from Godot Physics. [Using Jolt Physics](https://docs.godotengine.org/en/4.7/tutorials/physics/using_jolt_physics.html)
- PhysicsServer3D can create physics objects outside the scene tree, while normal Godot physics nodes register corresponding objects in the server. [PhysicsServer3D](https://docs.godotengine.org/en/4.7/classes/class_physicsserver3d.html)

### Inferences

- Maintain separate client and dedicated-server export presets early. Add headless startup and smoke checks in the first multiplayer prototype; keep rendering, camera, UI, and visual audio optional at the composition boundary.
- Keep the server's domain state authoritative even where Godot physics nodes simulate near-field motion. Persist meaningful outcomes (object pose/state, inventory, damage, machine configuration), not every solver intermediate or render frame.
- Pin the physics engine, tick rate, Godot version, and server/client build configuration for each released world. Test joint-heavy machinery and vehicle behavior against Jolt before standardizing it; defer separate-thread physics until measured and validated.
- Use separate replication policies by data class: input/aim and frequent transforms can be lossy and ordered; inventory, machine configuration, access control, construction, and durable commands need reliable ordered semantics and server-side validation. Use channels so reliable traffic classes do not queue behind unrelated work.

### Gaps

- The docs provide no throughput numbers for this game's proposed mix of rigid bodies, construction pieces, and machine networks. Profile representative worst-case scenes rather than selecting a player cap from generic Godot guidance.

## Planet, surface, ship, and scene topology

### Takeaway

Do not put a Moon-sized or interplanetary coordinate system into one ordinary Godot 3D physics scene. Keep physical simulation in compact, origin-centered sectors and store large-scale location in a separate logical coordinate system. The official large-world option is possible, but should only be enabled after the actual playable scale and extension/build consequences are proven to justify it.

### Cited Findings

- Godot 3D uses meters. In single precision, the docs recommend avoiding coordinates beyond roughly 2,048 m from origin for first-person play and 4,096 m for third-person play if avoiding rendering artifacts and physics glitches; precision degrades as coordinates move from zero. [Introduction to 3D](https://docs.godotengine.org/en/4.7/tutorials/3d/introduction_to_3d.html), [Large world coordinates](https://docs.godotengine.org/en/4.7/tutorials/physics/large_world_coordinates.html)
- The docs say large-world coordinates (double-precision vectors/physics) are aimed at space/planetary-scale games, but carry performance and memory costs, require custom editor/export-template builds (`precision=double`), and require matching build types across clients/server for consistent precision. GDExtensions must be rebuilt and their API changes incompatibly. [Large world coordinates](https://docs.godotengine.org/en/4.7/tutorials/physics/large_world_coordinates.html)
- The same docs describe loading large worlds in level portions around the origin as a reason large-world coordinates may not be needed; they also note origin shifting as an alternative with added multiplayer complexity. [Large world coordinates](https://docs.godotengine.org/en/4.7/tutorials/physics/large_world_coordinates.html)
- Godot PhysicsServer3D describes a physics space as a self-contained simulation world, separate from other spaces. [PhysicsServer3D](https://docs.godotengine.org/en/4.7/classes/class_physicsserver3d.html)

### Inferences

- Use a hierarchy such as `World/Body/Region/LocalTransform`: body/region IDs and fixed-point or double logical coordinates identify location, while loaded sector transforms are local meters around a nearby origin. For planets, persist a canonical surface address (e.g. body + map tile + local position/heading); for ships, persist ship ID + deck/compartment + local transform; for orbital/route travel, persist route/trajectory state separately.
- Load a bounded play region as the active Godot scene/physics space. A surface colony, a nearby exterior worksite, and a particular ship interior can be separate server regions or explicit simulation spaces, selected by proximity and activity. A region handoff should transfer stable entity IDs, player inventory/crew state, and a durable snapshot/event cursor.
- Represent interplanetary travel as a route/time/encounter state or a compact local flight sector, then load the destination region. Render distant planets as views/visuals. Do not simulate full planet radii, orbital mechanics, habitat interiors, and all ships as rigid bodies in one global physics world.
- Keep high-level simulation independent of visual scene chunks: procedural low-poly meshes, LOD, and instancing can be rebuilt on clients, while servers load collision/interaction data only. This also fits dedicated export resource stripping.
- In the first prototype, start with single precision and one compact Mars test site. Measure transform/physics errors at expected maximum local travel range. If a single active local region genuinely must exceed the documented ranges, compare a double-precision custom build against region-local coordinates before locking in the GDExtension toolchain.

### Gaps

- The official docs do not provide ready-made planet-scale terrain streaming, multi-body gravity, orbital transfer, or region-sharding systems. Those require project-specific design and profiling.

## Phased implementation recommendation and renderer implications

### Takeaway

Prove the world model with a headless authority and tiny client before building planetary content. Renderer choice belongs to the client: for a desktop-first 3D sim, Forward+ is the documentation-aligned default; headless server packaging is separate and does not depend on that renderer.

### Cited Findings

- Godot 4.7 describes Forward+ as the desktop renderer with all rendering features, Mobile as appropriate for newer mobile hardware and also desktop, and Compatibility as the widest support for older/low-end hardware and web. Forward+ and Mobile use Vulkan/Direct3D 12/Metal; Compatibility uses OpenGL. [Overview of renderers](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html)
- Dedicated-server exports can strip visual resources and execute headlessly. [Exporting for dedicated servers](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_dedicated_servers.html)

### Inferences

- **Milestone 0 — decision spike:** choose and pin a Godot 4.x release; export a headless process; create/connect two clients; prove authentication, server-side validation, disconnect/reconnect, and snapshot save/reload. Start Forward+ on a desktop target unless minimum-hardware policy requires Mobile or Compatibility.
- **Milestone 1 — vertical slice:** one small habitat, suit/airlock, one rover, one power loop, doors, inventory, and two players. Domain model is stable-ID data; server commands are versioned and persisted; clients render and predict only where necessary.
- **Milestone 2 — simulation foundation:** add atmosphere/pressure, electrical circuits, thermal, fluids, machines, scripting sandbox, and LLM tool calls through a strict allowlisted command API. Keep slow systems ticked at subsystem rates and test headless determinism/replay of commands (do not assume engine physics is deterministic lockstep).
- **Milestone 3 — persistent regions:** terrain chunks/tiles, save snapshots + recoverable event journal, region activity/offline catch-up, Discord identity mapping, and robust join-in-progress state snapshots. Measure network bytes, tick cost, memory, save duration, and crash recovery at increasing entity counts.
- **Milestone 4 — ships and travel:** add one ship interior/local exterior flight region and explicit server region transfer; then route-based lunar/Martian travel and multiple colonies. Add multi-process region orchestration only after a single-region load test establishes a real scaling need.
- Automate tests at each milestone: headless startup/exit; command authorization and rejection; two-client connect and join-in-progress; reconnect; crash/restart persistence; deterministic domain-system fixtures; replication bandwidth; and physics stress tests for loose rigid bodies, joints, and collision-heavy construction. Keep integration tests independent from renderer and Discord voice tests.

### Gaps

- No target platforms, minimum GPU, max concurrency, world uptime/SLA, or hosting budget was supplied. These determine whether Mobile/Compatibility support, process sharding, persistence technology, and a specific tick/snapshot budget are necessary.
