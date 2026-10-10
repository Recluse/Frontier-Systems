# Customizable overlays

## Product requirement

Player overlays must support selectable defaults, optional themes and player/mod customization. Apply the same presentation contracts to future HUD, inventory/equipment, PDA, machine controls, engineering diagnostics and station-AI views. Keep appearance and layout local to the client; player identity and body capabilities decide which data/actions the server makes available.

The current client panel implements appearance themes, [registered panel layouts](../architecture/overlay-layout-runtime.md) and [HUD section ordering/collapse](../architecture/overlay-section-runtime.md), including presets, local JSON customization and saved user edits. Widget replacement, movable windows and a general overlay module registry remain planned below.

## Implemented themes

`OverlayThemeDefinition` validates declarative v1 JSON and builds native Godot `Theme`/`StyleBoxFlat` resources. It supports:

- Semantic background, panel, text and accent colors using opaque `#RRGGBB` strings.
- Font size from 12 to 32, spacing from 4 to 24 and corner radius from 0 to 16.
- Inherited colors and styles for common controls, panel/popup styles, container spacing and visible focus borders.

Three first-party presets ship under `data/overlays/`: **Frontier** (default), **Terminal**, and **High contrast**. They use Godot's existing font fallback and native styles; no additional creative assets or dependencies are imported. “High contrast” is a preset name, not a claim of accessibility certification.

`OverlayThemeController` adds a picker and Default reset button to the existing client panel. Selection applies to the client root and background immediately. The selected theme ID is saved in `user://overlay-settings.cfg`; missing/unregistered selections fall back to Frontier. Preference reads are limited to 4 KiB. A failed save leaves the theme applied and reports a warning.

Theme changes never reference the world runtime, command queue or PHP services. Headless bootstrap omits the UI and selector. Current title sizing and alarm-indicator spacing/color conventions remain explicit widget overrides. 3D world geometry/materials and alarm meaning are outside the theme contract.

## Creating a local theme mod

1. Copy `data/overlays/default.v1.json` as a starting template.
2. Give it a unique `definition_id` such as `overlay.my-colony` and a display name.
3. Edit supported colors/dimensions, keeping the exact fields described by `docs/schema/overlay-theme-v1.schema.json`.
4. Save the JSON file in `user://overlay-themes/` in the game's Godot user-data directory, creating that folder if necessary.
5. Restart the client and select it from Overlay theme. Use Default to restore Frontier.

The loader accepts JSON objects only, with a 16 KiB file limit. It examines at most 32 directory entries and registers at most 32 additional themes, without descending into subdirectories. Directory order is not guaranteed; keep the folder dedicated to a small set of theme files. Invalid files and duplicate IDs are skipped with warnings. Shipped IDs are registered first and cannot be shadowed by local files; customize them by creating a new ID. There is no live filesystem watcher, import editor or network download.

Definitions do not accept scripts, scene/resource paths, external fonts, shaders, URLs or gameplay bindings. Unknown fields, translucent/malformed colors and out-of-range dimensions reject. These are appearance data mods; arbitrary GDScript mod execution is not part of this contract. Local customization is user-controlled; any theme/assets distributed with the game must satisfy the project's MIT/creative-asset policy and provenance rules.

## Layout and overlay extension plan

The two-panel prototype now uses a separate versioned layout definition and trusted control registry. Extend those contracts when the HUD and inventory UI exist; do not encode layout in theme colors or world snapshots. Broader contracts:

| Contract | Responsibility |
| --- | --- |
| Theme | Semantic appearance tokens |
| Overlay definition | Stable widget ID, presentation role, supported observation/input interfaces |
| Layout profile | Widget arrangement, anchors, visibility, scale and ordering within declared bounds |
| Client preference | Selected theme/layout and user overrides |
| View model | Validated, server-visible observation data for the widget |
| Action binding | Typed intent sent through existing authenticated command adapters |

Prefer registered, reusable widget factories and declarative layouts over copied scenes with hidden logic. Allow players to rearrange status panels, choose compact/expanded inventory presentation and select optional overlay packs. Body-specific views can share the inventory model without sharing slot layout. Include a reset path and schema migrations for saved preferences.

Layout validation must bound widget counts, tree depth, scale and update budgets; reject unknown IDs/bindings and preserve keyboard focus/navigation. Responsive constraints should keep controls reachable at supported resolutions. Distinguish visual customization from server visibility: a mod cannot reveal hidden inventory, bypass station permissions or create mechanical actions that the server would reject.

Preserve text/icon cues for state, readable labels and usable focus indicators. Add UI scale, key remapping, motion/blink preferences and contrast validation as explicit settings rather than assuming a palette implements accessibility. Shared/approved custom icons/fonts need an asset boundary before they can be imported.

Overlay subscriptions should consume existing bounded observations, not poll external services per widget/frame. Profile widget count, observation fanout, layout work, frame update cost and allocation. Rebuilding a theme should be an explicit selection operation, not per-frame work.

## Verification and next tasks

Windows Godot 4.7.2 import, `overlay_theme_test.gd` and the existing client habitat-layout checks passed. Checks cover all preset definitions, native resources, palette/spacing inheritance, invalid executable fields/colors/dimensions, detached records, custom registration/selection, default reset, duplicate/missing IDs and unchanged canonical world snapshots. Windows/Ubuntu CI includes the script. Graphical readability, keyboard navigation, resolution extremes, saved-preference recovery and directory discovery still need dedicated checks; Linux is not locally verified.

Next: finish authoritative inventory integration, build its default overlay with these theme tokens, then extend the existing panel/layout registry for HUD widgets and more detailed in-game customization. Optional future Steam Workshop distribution should reuse the same declarative contracts and remain a separate packaging milestone.
