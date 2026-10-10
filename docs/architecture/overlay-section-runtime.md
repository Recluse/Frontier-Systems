# HUD section customization

## Implemented client behavior

The existing prototype controls panel now contains seven registered sections: pressure/alarms, airlock controls, local inventory demo, access bypass, machine maintenance, profiling and action feedback. **Expanded** opens all sections. **Compact** places feedback near status and initially collapses maintenance, access and profiling.

Each header offers Up/Down controls, and optional section titles toggle collapse. Pressure/alarms and action feedback remain expanded by host policy. Theme, panel layout and section customization controls remain outside the section stack, so section profiles cannot remove the reset path. All remain inside the existing scrollable client panel.

Collapsing a section hides its contents without removing nodes or stopping the underlying simulation, profiling capture or observer callbacks. Header controls remain available to expand it. When focus is inside collapsing content, it moves to the section header. Reordering uses native child ordering without recreating controls, preserving their existing callbacks and focus.

## Contracts

- `OverlaySectionProfile` validates schema version 1, stable ID/display name, and an ordered array of one to sixteen unique section IDs with boolean collapse flags. Unknown fields, including executable resource/script fields, reject.
- `OverlaySectionStack` registers trusted unparented controls, wraps them with native headers, and records whether each section is collapsible. JSON cannot register new controls or change that policy.
- Applying a profile resolves every section, requires all registered sections exactly once, checks node ownership and collapse permissions, then applies order and visibility. A missing/unknown section or illegal collapse rejects before changing any section.
- `capture_profile()` returns a detached JSON-compatible description of current order/collapse state. `move_section()` accepts only adjacent moves within bounds; `set_collapsed()` checks the host's collapse policy.
- `OverlaySectionController` provides profile selection, reset, local mod discovery and independent preferences. It neither references the world runtime nor grants gameplay capabilities.

The registered IDs in the current client are:

| ID | Contents | Collapsible |
| --- | --- | --- |
| `hud.status` | Pressure sensors and alarm observer | No |
| `hud.airlock` | Existing powered/manual airlock actions | Yes |
| `hud.inventory` | Local inventory interaction demo | Yes |
| `hud.access` | Existing local bypass controls | Yes |
| `hud.machine` | Circuit status, debug pulse and maintenance | Yes |
| `hud.profiling` | Existing capture controls and report | Yes |
| `hud.feedback` | Command outcome text | No |

The prototype's existing commands remain local development commands; organizing their controls does not implement production authentication. Inventory and PDA widgets still require their authoritative observation/action adapters before joining this registry.

## Local mods and saved customization

Copy `data/overlays/sections/default.v1.json`, assign a unique ID/name, reorder its section entries and change allowed collapse flags. Place the file in `user://overlay-sections/`, restart, and choose it from HUD sections. The schema is `docs/schema/overlay-section-profile-v1.schema.json`.

The shared document loader examines at most 32 entries without recursion and limits files to 16 KiB. The section profile catalog accepts two shipped presets plus at most 32 additional profiles. Duplicate IDs cannot replace shipped entries. A structurally valid profile referencing unavailable sections can register, but cannot activate; the current arrangement is preserved and the UI reports it as unavailable. No scripts, scene factories, new actions, URLs or external assets are accepted.

Manual edits and successful preset/reset selections save the actual order and collapse flags in `user://overlay-section-settings.json`, using the same v1 profile shape with `sections.user` as its saved ID. Restored state does not depend on the original preset or mod file remaining installed. Startup applies defaults before validating and restoring saved state, without overwriting the saved file first. Missing, invalid, incomplete or illegal saved profiles leave defaults intact. A later edit or reset replaces the saved state. Reads are bounded to 16 KiB; failed writes warn without reverting the visible edit.

Theme, panel-layout and section preferences have separate files. These are local appearance preferences, not world/account inventory records. A targeted additive migration appends `hud.inventory` expanded to older saved/mod profiles missing exactly that newly registered section, preserving existing order/collapse flags. Otherwise incomplete or unknown profiles still reject. Future section additions need their own explicit migration policy.

## Verification and limitations

Windows Godot 4.7.2 import, section checks and existing layout/habitat checks passed locally. `overlay_section_test.gd` covers shipped presets, duplicate/nonboolean/executable fields, required collapse rejection, atomic unknown-reference rejection, reorder/focus/callback preservation, bounds, JSON recovery, custom registration and world-state isolation. Isolated disk checks verify startup recovery, edit persistence, reset persistence and fallback from an illegal saved required collapse. Test files are removed afterward without touching normal player preferences.

Windows/Ubuntu CI includes the section script. Graphical readability, real input interaction, mod-directory discovery and Linux execution remain unverified locally. General HUD widget creation, arbitrary positioning/dragging, advanced inventory/PDA views and custom observation bindings remain future work. Native layout and theme contracts remain separate from this ordered section stack.
