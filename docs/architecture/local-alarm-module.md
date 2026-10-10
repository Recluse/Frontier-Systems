# Wired local alarm module

The first optional action module is `module.alarm.local.utility` revision 1, defined in `data/control/modules/local_alarm.v1.json`. It uses the utility interface, one size unit, a declared one-watt idle demand, and a wired pulse input named `raise_alarm`. Required host capabilities are existing `power.consumer` and `control.wired`; declared watts are metadata until the electrical solver exists.

## Installation and behavior

New prototype worlds seed one existing alarm part (`habitat_airlock-alarm-module`) into the shared maintenance tray. This is a startup fixture, not free fabrication or a material recipe. Older saves restore their own tray unchanged and do not gain a new spare. The expanded door board accepts the alarm in a general utility bay; the stock receiver-only board does not.

The prototype panel provides install/remove and connect/disconnect alarm buttons. Close both doors, isolate the controller, install the alarm in `door.utility.2`, attach its wire, then restore power. The existing receiver output can remain wired to the latch at the same time. A debug receiver pulse then queues both recipients for the next tick. Connections use explicit instance/port IDs, and duplicate wiring is rejected.

`LocalAlarmPulseAdapter` binds the declared input to one server-owned module and host. It cannot select another device, clear alarms, claim actor permissions or run arbitrary code. The control system retains both its latch and alarm adapter objects and reconstructs their trusted bindings after restore.

`AccessControlSystem.apply_circuit_alarm_request` checks the current authoritative tick, host/controller existence, controller integrity and power. Quiet becomes local. An already local alarm stays local; a remote alarm is preserved. Disabled/faulted alarm hardware rejects the trigger. The circuit independently enforces installed part condition and wiring, so a missing or zero-integrity alarm cannot act.

The effect uses the existing controller alarm record and persists with access-control snapshots; no new snapshot version is needed. The panel now has a [visual indicator and optional synthesized tone](alarm-presentation.md). Physical sirens, alarm clearing, independent source aggregation, notifications and Discord messages remain future work. Repeated triggers return success without downgrading alarm state. Security bypass audit records and credential grants are unaffected.

## Degradation and recovery

Removing the alarm disconnects its wires and cancels pending deliveries involving it; the latch and other destinations continue to function. Zero-integrity alarms remain salvageable with their condition intact. Board replacement still requires every installed module to fit: remove utility modules before downgrading to the stock board.

The recovery suite now covers installation, two-destination saved fanout, fixed target binding, remote/disabled alarm behavior, damaged optional modules and salvage. Tests passed on Windows Godot 4.7.2. Linux CI and graphical UI/audio checks remain pending.
