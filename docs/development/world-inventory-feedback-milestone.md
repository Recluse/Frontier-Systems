# World inventory interaction feedback

Presentation-only improvements on the first-playable inventory tab: stable item/root IDs, current host-observed distance and ownership advice, explicit world drop destination, and frozen pickup/drop submission details until acknowledgement. Disconnect clears pending state, selectors and cached details; rejection retains the host's reason and allows correction. Selected 3D proxies show their stable identity and observed distance.

Canonical inventory remains owned by the existing fixed-tick InventorySimulationSystem and shared coordinator. The panel only sends existing world intents and reads scoped projections. No state, wire or persistence versions change. Reach/access, ownership and capacity feedback is advisory; the host validates again at application time. Pending commands do not move displayed items optimistically.

The existing first-playable 3D double-click shortcut remains a separate bootstrap command route. The frozen pending details apply to the inventory tab's Collect/Drop actions. No terrain, machinery or bootstrap code changes are included.

Verification and graphical evidence are recorded after checks complete. Captures must use the real invite-authenticated loopback client on reserved port 27861 and disclose procedural art and capture limits. No merge, dev-master push or deployment is authorized in this milestone chat.
