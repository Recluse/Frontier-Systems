# Gameplay UI organization implementation

Presentation milestone following the owner request in `gameplay-ui-organization-milestone.md`.

## Scope

The integrated FirstPlayable client will start with its interaction drawer closed. Persistent hands, connection and command uncertainty remain visible beside the scene; inventory/equipment, workstation and construction share one on-demand drawer. Help and diagnostics start collapsed. UI navigation must preserve exact selected and submitted identities and may not change canonical state.

## Provenance

Independently authored Godot layout and controls under the project MIT license. Behavioral requirements come from the owner-authored milestone's Stationeers and SS13 notes. No upstream source, text, bindings or artwork copied; no Baystation source consulted; no generative art used. Existing procedural engine visuals and project theme are retained.

## Acceptance record

Pending implementation and exact-head verification. Use the actual client bootstrap with no-port paid-domain fixtures at 1920x1080 and 1100x700. Check focus/scroll, selection, hands/equipment, transfers, production, construction, long target/error text, and disconnect/reconnect recovery. Native engine captures resolve layout uncertainty. Human usability, controller/VR and live-network acceptance remain unverified.
