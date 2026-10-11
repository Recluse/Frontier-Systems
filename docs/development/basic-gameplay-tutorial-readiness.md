# Tutorial readiness evidence

Readiness review in progress for the [basic gameplay tutorial milestone](basic-gameplay-tutorial-milestone.md).

Pinned runtime base: `1b973cabfadd8dab3c44bd46514590bacaabfc0b` (equipment PR #34 merged). This branch changes verification tooling and documentation only. Source prototype verification does not establish a public demo or human tutorial acceptance.

## Reproduce locally

Reserve loopback ports 27849 and 27850 through Coordinator, then run the bounded route from a clean isolated worktree:

```powershell
./tools/ci/run-tutorial-readiness-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -PortsReserved
```

The wrapper uses the existing headless and graphical runners sequentially, refuses an existing project override, creates a unique Godot user profile, pins HEAD in an ignored manifest, and captures ordinary native-renderer output under ignored `var/ci/tutorial-readiness/`. It never stops an existing listener. The unique user profile remains local for evidence review; remove only its exact directory after review. Existing configuration and capture environment are restored. `-PortsReserved` asserts a Coordinator reservation and does not acquire it.

## Acceptance boundary

The headless cooperative test uses direct authenticated commands. The graphical route instantiates the actual client, advances character physics and invokes contextual guide methods. It disables local keyboard sampling. Neither route proves that a human can discover controls, move/look with physical keyboard/mouse, select the intended UI target, complete the loop unaided or save/reconnect through the client UI. Do not record those routes as human tutorial footage.
## Results on 2026-10-11 (America/New_York)

**Readiness gate not met.** Automated runtime and native graphical evidence passed; end-to-end human character/input usability and client-UI recovery remain unverified. This review identifies acceptance gaps, not an observed gameplay failure.

- Tested tooling HEAD: `72c97447f070eb5417bcbd3071c3e965946900e5`, runtime base `1b973cabfadd8dab3c44bd46514590bacaabfc0b`. Godot `4.7.2.stable.official.ed1daf0bf`; Windows; Compatibility/OpenGL 3.3; NVIDIA GeForce RTX 3080 Ti. Source checkout, no packaged/exported build.
- Evidence run: `dc7f8d26650443ffa1140941fca0adc0`, 05:04:37–05:05:56 UTC. Ignored `var/ci/tutorial-readiness/<run>/manifest.json`, runtime logs/JUnit, graphical stdout/stderr and `capture/client.png`. Native screenshot inspected locally at 1920×1080; captures are not staged or uploaded.
- Existing bounded runner: import, startup, `desktop_controls_help_test`, `first_playable_acceptance`, `first_playable_task_guide_test`, `local_character_navigation_test`: **6 checks, 0 failures**. Cooperative acceptance took 36.31 seconds and exercises authenticated authority, finite resources, physical crafting/recycling, durable checkpoints and a replacement host reconnect using command fixtures.
- Existing graphical basic route: authenticated Crew 1, local capsule movement to ore and workstation, two 1000 g extractions, unload/refine/plate collection/recycle/reprint; collection guide **7/7**. Screenshot shows iron deposit **8.000 kg remaining**, shared iron **0.200 kg**, tailings **0.800 kg**. The route then materializes/drops the recrafted plate and switches to overview for capture.
- Unique custom user directory was verified under Windows roaming application data. Real player preferences/journals/worlds were not used. The temporary profile contains test artifacts and remains local; project `override.cfg` was removed after the run and the capture environment restored.
- Coordinator reserved 27849/27850; immediate probes succeeded; post-run listener inspection found neither listening. Reservation released to Coordinator.

## Tutorial candidate steps and gaps

| Candidate lesson | Current evidence | Gate still required |
| --- | --- | --- |
| Authenticate and spawn persistent crew body | Real client authenticated; scripted capsule initialized | Human follows fresh profile setup and identifies their body |
| Move, look, switch camera and expose cursor | Local physics/collision and camera contracts pass; help uses current bindings | Physical keyboard/mouse movement, look, Alt cursor handoff and focus recovery in the real client |
| Select UI/world target and interact within reach | Help focus/navigation tested with injected input; guide invoked directly | Human pointer selection and actual target use; clear authoritative rejection/retry |
| Gather and transport finite iron | Native real-client scripted route collects 2 kg and returns to workstation | Unaided movement, targeting and canister/hands management |
| Refine, collect, recycle and reprint | Native route completes seven-stage loop from fresh world | Human starts actions through visible UI and recognizes completed versus pending work |
| Equipment and basic construction | Cooperative runtime fixture exercises equipment/wall/generator authority and persistence | Fresh character-driven graphical equipment and construction loop; basic route does not demonstrate these lessons |
| Save and reconnect | Cooperative runtime fixture confirms worker checkpoint and restarted-host restore | Click client save, observe durable acknowledgement, reconnect through actual client and verify depletion/items/construction |

Defaults checked in `src/presentation/input/player_controls.gd`: RMB holds look/navigation; WASD moves; Shift sprints; Space jumps; Alt exposes UI cursor; Escape releases capture; I opens inventory; F10 settings; F1/F2/F3 cameras; X switches hand; F uses active tool; LMB selects a world target (double-click to use). These are source-verified defaults, not a validated human instruction sequence; settings may remap them.

The current graphical fixture explicitly sets `read_local_keyboard = false`, walks via `set_motion_intent`, and calls the guide method. Its final overview screenshot cannot establish look controls, pointer selection, complete construction or recovery. Native desktop automation is unavailable in this chat; browser controls cannot operate the Godot window. No human playtest was performed. Linux graphical, controller, VR, multiplayer ergonomics and public packaged-demo coverage are not claimed.

At 1920×1080 the final target-help sentence is clipped with an ellipsis. The collection guide and main buttons are readable in this frame, but the workstation panel requires scrolling. This is a concrete presentation observation for Coordinator/visual scope, not a code change in this branch. Avoid drawing usability conclusions from one overview frame.

## Next acceptance and recording gate

Coordinator should arrange a fresh-profile human keyboard/mouse run on the chosen integrated HEAD, covering every gap above. Resolve input/presentation issues in their assigned scopes, then rerun only affected verification. Do not begin final tutorial instructions or represent this branch as tutorial-ready until that gate passes.

After readiness passes, prepare short ordered lessons for setup, movement/cursor/selection, inventory/hands, finite gathering/processing, equipment/construction and recovery. Record each real action and result in the pinned build with ordinary capture; retain original order and label any speed changes. Keep recordings/edit project/exports ignored and local. Use standard nongenerative editing, UTF-8 WebVTT/SRT, transcript and manually synchronized caption review; verify playback, controls, contrast and mobile legibility against the final edit. Record author, project MIT provenance, exact build, capture/editor/render settings and acceptance limits. No new third-party art/fonts/music or media uploads are included. Concrete final videos and public destination require owner clearance through Coordinator.

This is a conditional work order, not a completed tutorial outline or video deliverable. No videos were recorded or edited because the readiness gate remains open. No source/media public publishing, release, deployment, merge or dev-master push occurred.
