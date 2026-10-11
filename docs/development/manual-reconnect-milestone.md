# Manual source-playable reconnect

The client offers a persistent **Reconnect to shared host** button after disconnect or a failed connection. It reuses operator environment configuration without displaying or saving host/invite credentials. One pending connection is allowed; actions wait for authentication and a fresh observation. Rejection remains visible and retryable.

Disconnect clears adapter observations, world previews, crew avatars, movement bookkeeping and displayed hands/inventory. Production presentation is rebuilt against the same remote adapter after fresh data. Pending construction/inventory/checkpoint commands are abandoned with unknown outcomes and never resubmitted. The existing bounded terrain journal and explicit original-intent retry remain unchanged. Canonical world state and identity belong to the host; no schemas or core authority change.

Draft [PR #53](https://github.com/Valgorithms/Frontier-Systems/pull/53) targets dev-master from `manual-client-reconnect`, based on `834bea7dd9e581f4fc2ddd6f9f80ef52f0584ec6` (includes PR #49). No external services, public host, deployment or merge.

## Verification

Windows Godot 4.7.2 dedicated adapter/shell checks pass: initial/duplicate suppression, authentication without a fresh observation, abandoned command completion, stale projection clearing, failed attempt and rejected authentication recovery. The same running actual client also passes disposable loopback checkpoint save, disconnect, unavailable-host attempt, real invite rejection and manual reconnect to a restored host. It retains body/slot, items, active hand, inventory revision, production stock/deposits/walls/structures/components and the integer-normalized original terrain intent. Reconnect transmits no abandoned command or automatic terrain retry. The synthetic retained return targets an absent fixture parcel; it proves preservation and explicit retry availability, not successful terrain settlement.

The initial Windows run for the source tree committed as `37b9682` passed all 11 checks: import, startup and the nine scripts listed below, including existing two-client finite engineering/checkpoint acceptance and inventory/production shell regressions. `git diff --check` passed. PHP and domain schemas are unchanged; their cross-platform checks remain CI evidence.

Use the existing runners:

```powershell
./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames manual_reconnect_adapter_test.gd,manual_reconnect_acceptance.gd,first_playable_acceptance.gd,client_inventory_shell_test.gd,integrated_panel_layout_test.gd,first_playable_task_guide_test.gd,recipe_requirements_test.gd,maintenance_requirements_test.gd,equipment_prerequisites_view_test.gd -OutputDirectory var/ci/manual-reconnect-final
./tools/ci/run-first-playable-render-check.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -Route manual-reconnect -PortsReserved -TimeoutSeconds 60
```

Port 27849 requires a Coordinator lease and a fresh free-listener probe before binding. Run the headless route with a disposable custom user profile; the native route creates a unique profile override and removes it in `finally`, preserving an existing override. Test world/checkpoints are ignored under `var/ci/manual-reconnect-world-*`; native logs/provenance manifest are under `var/ci/render-manual-reconnect`, and captures under `var/ci/manual-reconnect-render/captures`. No profile override remains after the checks; only disposable test files are retained as local evidence.

Native OpenGL Compatibility acceptance passes through button-signal activation with real loopback authentication and checkpoint I/O. Ordinary viewport captures of connected/disconnected/rejected/reconnected states were inspected locally; recovery status and button are visible, direct actions disable while disconnected, and production is rebuilt after fresh data. Existing MIT engine geometry is the capture source; no generative art or third-party assets. All captures remain ignored/internal, with no upload.

Automated adapter, headless network and native Compatibility evidence does not establish human usability, physical keyboard/mouse reconnect activation, controller, VR, Forward+, public networking, TLS or Linux graphical acceptance. Windows/Linux CI for the exact final pushed head remains the Coordinator review gate; earlier-head success does not certify the final head.

## Repeated reconnect navigation review correction

The persistent workstation selection emitter now connects once during client setup to a named guarded bootstrap handler. Rebuilding a production panel no longer installs another anonymous callback. Workstation signals during disconnect or deferred panel deletion leave navigation unchanged and never dereference the absent panel.

`reconnect_workstation_navigation_test.gd` drives four actual-shell observation/disconnect cycles with a socket-free recording adapter and canonical fixture observations. Each fresh cycle invokes exactly one handler and changes to the workstation tab, the persistent emitter has one owned connection, and signals both before and after deferred deletion safely leave the current tab alone. It also verifies navigation submits no canonical command. This is automated presentation evidence, not another network or native-render acceptance run.

Windows Godot 4.7.2 import/startup and `reconnect_workstation_navigation_test.gd`, `manual_reconnect_adapter_test.gd`, `client_inventory_shell_test.gd`, `integrated_panel_layout_test.gd` passed (six checks, ignored `var/ci/reconnect-navigation-review`). `git diff --check` passed. No sockets were opened, no new port lease was needed, and prior native/network evidence above remains scoped to the earlier source tree. Exact new-head Windows/Linux CI remains separate.

## Windows checkpoint receipt assertion correction

On head `7ba02e371dd225c48a026030cc805c372ea47322`, [CI run 38128517363, Windows job 114437816565](https://github.com/Valgorithms/Frontier-Systems/actions/runs/38128517363/job/114437816565) failed only the reconnect acceptance assertion `actual save button confirms disk checkpoint`. Import/startup and the repeated-navigation test passed; the dependent CI gate failed and development export skipped. The failed log and run metadata are preserved internally under `var/ci/pr53-failed-*` (log SHA256 `51466050dbafdbc8323d9a856743f6de71b1ba889d1a165278dc18aa3e92e2ac`). No unchanged-head retry or gate waiver was used.

That assertion polled a transient UI label after socket processing. A subsequent observation in the same poll can replace the checkpoint status before the test resumes. The socket-free shell regression reproduces this deterministically by delivering completion and a fresh observation in one frame: checkpoint success/status is observable at receipt delivery, then the label is replaced. The loopback test now captures the successful checkpoint receipt and status synchronously, following the existing native client acceptance pattern, and independently checks that the disposable disk checkpoint exists. This proves delivered receipt/status and disk presence, not a duration guarantee for the status label. Runtime behavior is unchanged.

Windows Godot 4.7.2 import/startup plus the socket-free receipt-race/navigation and adapter tests passed under `var/ci/reconnect-receipt-race`; import/startup plus the corrected real loopback acceptance passed under `var/ci/reconnect-receipt-loopback`. A fresh Coordinator port 27849 lease and immediate free-listener probe were used with a disposable world/profile; process exited and the profile override was removed. The new commit needs fresh exact-head Windows/Linux CI; earlier green runs do not erase the preserved failure.
