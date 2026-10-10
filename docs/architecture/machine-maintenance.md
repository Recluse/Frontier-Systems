# Prototype machine maintenance

`MachineMaintenanceCommand` applies a parsed `MachineMaintenanceIntent` through the authoritative command queue. The v1 vocabulary is `isolate`, `restore_power`, `remove`, `install`, `attach_wire`, and `detach_wire`; v2 adds `replace_board`, `resume_board_job`, and `cancel_board_job`. Each permits only declared stable-ID parameters. The intent never carries credentials, module definitions, integrity, handler code or remote target authority. Both versioned schemas are under `docs/schema/`. See [reserved board replacement work](board-replacement-work.md).

## Authority and physical prerequisites

This slice is local-development-only: debug build, development-local authenticated context, `control.configure` grant and server-derived `tool.electrical_probe` capability are all required. The command base also validates world/region scope. Authenticated remote sessions are rejected even with a matching permission. Player position, reach, loadouts and general inventory authority are not implemented, so this is not a production construction interface.

The host is the prototype habitat airlock. Every maintenance operation requires an intact controller, closed host doors and no active bypass jobs. Isolation requires a powered controller; hardware changes and restoration require an isolated controller. `AccessControlSystem` owns power-state transitions and independently validates isolation prerequisites. The transition only supports `powered` to `isolated` and back; it cannot repair a controller or restore power from `unpowered`/`faulted` states. Manual crowbar operation remains available under its own constraints during isolation; doors must close again before maintenance continues.

## Part lifecycle

`MachineControlSystem` owns a shared host maintenance tray capped at 64 parts. Removal first verifies tray capacity, then removes the installed part and transfers its inspection record into the tray. Circuit removal disconnects associated wires and cancels pending receipts involving that part. Failed removal leaves installed state unchanged.

Installation takes only a tray part ID and destination slot ID. It resolves that part's saved definition revision through the trusted catalog and passes its existing integrity into the circuit. Successful fit removes it from the tray; an occupied or incompatible slot leaves the tray unchanged. Missing functional capabilities can still produce a physically fitted, dormant installation. Zero-integrity parts remain salvageable and do not become repaired through reinstallation. There is no command to create parts, supply arbitrary definitions or choose new integrity.

Wiring changes accept physical compatibility separately from signal compatibility. Inert wiring can be attached; unknown endpoints, radio sockets and duplicate endpoint pairs fail. Detaching a wire cancels its pending receipts. Reconnecting endpoints does not restore canceled work. These operations do not consume cable stock yet.

## Persistence and compatibility

Machine-control system snapshots now emit **schema version 3**, retaining v2 `salvage` and adding board ownership and reserved work. Circuit and part schemas remain v1. Restore validates parts against trusted catalogs, bounds the tray and rejects duplicate identities across trays and installed hardware. Existing system-v1 saves restore with an empty salvage tray; system-v1/v2 saves gain no spare boards or jobs. Saves without a control system still migrate to an empty commissioned circuit, without spawning parts. Controller isolation is persisted by the access-control system.

The tray is host-owned, not a player backpack, global inventory or fabrication source. The current region contains one control host; multiple-host and global item identity ownership require a later inventory system. Board replacement now has tick-based work and hardware interruptions; general construction recipes, materials, repairs and actor-presence interruptions remain separate tasks.

## Prototype panel sequence

1. Close both doors and finish any bypass jobs.
2. Select **Isolate controller**.
3. Remove the latch to the tray; its wire is removed automatically.
4. Reinstall the latch from the tray.
5. Wire the receiver to `unlock` or `lock`. To change an existing route, disconnect its wire first.
6. Restore controller power, then use the debug receiver pulse.

The existing wire ID remains stable when changing its destination input; IDs are not behavior names. The panel displays salvage count alongside circuit delivery counters. A successful queued maintenance command is separate from subsequent pulse delivery and door movement.

No new tests were added or run, and this addition has not been executed in Godot.
