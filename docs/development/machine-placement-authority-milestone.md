# Deployed machinery placement authority

## Authority and bounds

Production owns placement poses and module mounts. `MachineryPlacement` derives conservative, axis-aligned millimetre bounds from those records at authenticated command ingress; presentation nodes never authorize placement. There is no periodic collision work, new runtime owner or service wait. Existing production/machinery profiling counts still apply.

Both surface and freeform positions are the **bottom centre** of the reserved box in the workbench-relative coordinate frame. Surface placement requires Y=0. Freeform translates the same box in XYZ, including its bottom Y; it does not attach to a surface or rotate. Positions retain the existing integral-millimetre ±10,000,000 mm coordinate limit and 1.5 m actor reach.

| Physical assembly | Reserved dimensions X × Y × Z |
| --- | --- |
| Frame with any ordinary heads/modules and up to four retained sockets | 1.3 × 1.5 × 1.3 m |
| Fitted expander, including empty/damaged expanders | 2.5 × 1.5 × 1.3 m |
| Five retained sockets after expander removal | 1.9 × 1.5 × 1.3 m |
| Six retained sockets after expander removal | 2.5 × 1.5 × 1.3 m |

The base box preserves the prior spatial-wall machine envelope and contains the solar panel, printhead and other prototype heads. The expander reserves all six possible canister positions before insertion, including the sixth canister's +1.25 m X edge. Socket geometry remains reserved even if empty or broken. Removing an expander cannot erase its still-fitted sockets' footprint. Canister insertion/removal and solar fitting stay within the reserved envelope; loose printed cargo uses the existing bounded storage contract rather than aggregating arbitrary payload geometry.

Deployment rejects positive overlap with **every** existing deployed envelope, spatial wall, registered body (including the actor) and trusted production fixture. Disabled, incomplete and zero-condition assemblies still occupy space. Module fitting checks the prospective envelope when its dimensions change, before relocating the physical part. New wall building also checks the wider machinery bounds, so construction order cannot bypass expansion clearance.

The shared wall utilities define strict overlap on all three axes. Face/edge/corner contact is allowed; one millimetre of positive overlap on all axes rejects. Body bounds use the established 0.35 m horizontal / 0.9 m vertical half extents and legacy floor-anchor centre clamp. Fixture bounds remain the established workbench box (centre [0,850,1000], half [1750,1000,500] mm) and each finite source box (source + [0,250,0], half [300,250,300] mm). Cables, trays, arbitrary habitat geometry and terrain have no general placement keepout here.

## Transactions and compatibility

The existing planner works on detached production/inventory candidates. Rejection retains matter, physical parentage, nested contents, placements, mounts, buffers, links and receipts. Revision races have one winner; retained successful retries acknowledge the original transaction. Packing/disconnection and independent capability loss retain their existing rules.

**No persisted record or schema version changes.** Production v7 and machinery v1 remain current. Restore retains the prior validation policy: trusted v6/v7 saves may contain machine/machine, machine/body or machine/fixture overlaps that were legal before this authority existed. Existing wall validation retains its prior 1.3 × 1.5 × 1.3 m machine box on restore. Expanded overhangs in old saves are therefore grandfathered too. Malformed records, conservation failures and mismatched authoritative world-storage poses continue to reject.

Grandfathering is deterministic and local to existing placements: enable/disable, non-growing module fitting, removal, processing, disconnection and packing do not trigger a new global machine clearance check. A packed machine's next deployment and any envelope-growing fit must pass full current clearance. Growth also rejects an existing overlap; it does not grant a partial-overlap exemption. New wall commands check only the proposed wall against expanded bounds, leaving unrelated legacy expanded overhangs untouched. There is no save-time relocation, matter grant or deletion, and no player field can request a legacy exemption. This intentionally means importing a structurally valid trusted checkpoint does not certify placement clearance.

## Verification

`machinery_placement_authority_test.gd` builds real frames, modules, six sockets, a loaded canister, solar power and a cable from seven finite iron-ore batches. It exercises exact overlap/contact, workbench/source/body/wall keepouts, floor/freeform coordinates, reach, injected-bound rejection, atomic growth failures, cooperative ownership/revision races, retained deployment retries and JSON checkpoint recovery. Both v6 and v7 overlapping damaged saves resume through enable, module removal/refitting, disconnection and packing; forbidden redeployment remains atomic. Nested contents, conserved mass, exact grid buffers and links survive restart.

Existing machinery, autolathe, chemistry, wall and placement-feedback fixtures use legal positions and player approach points under the new authority. The two-client acceptance route deploys its shared generator at a clear floor position before durable restart verification. CI discovers the new headless script on the existing pinned Godot 4.7.2 Windows/Linux matrix.

Local verification results and exact-head CI are recorded in the PR. Headless checks do not establish graphical, VR/controller or human usability. No integration-branch push, merge, deployment, external messaging or live-service action is part of this milestone; authorized Coordinator chat updates are the only cross-chat coordination.

## Remaining scope

Client previews remain advisory and may display a smaller visual approximation than the reserved server box. General body/machinery movement collision, rotation, arbitrary ship/surface attachment, rigid-body settling, room atmosphere topology, terrain authority and cargo geometry aggregation remain separate work.
