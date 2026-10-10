# Overlay layout runtime

## Implemented scope

The prototype client now arranges its existing controls and habitat view through a validated layout definition and trusted panel registry. Themes still own appearance; layouts own order, orientation, spacing and relative allocation. Both remain disposable client presentation state and are absent from world snapshots and headless bootstrap.

Shipped presets under `data/overlays/layouts/` are **Controls left**, **Controls right**, and **Stacked**. An in-game layout picker, Reset layout button and slider select them and customize the leading panel's space weight. Reset restores the Controls left profile and its 0.44 weight. Theme settings remain independent.

This remains a two-panel v1 contract. The controls panel now separately supports [section order and collapse customization](overlay-section-runtime.md). Arbitrary positioning, hidden top-level panels, widget creation, nested layouts, movable windows, inventory overlays and additional observation/action bindings are not implemented.

## Contracts and ownership

- `OverlayLayoutDefinition` accepts an exact versioned record with stable ID/name, horizontal or vertical orientation, exactly two unique panel IDs, finite leading weight from 0.25 to 0.75, and integer spacing from 4 to 24. Reads are detached.
- `OverlayPanelRegistry` registers existing unparented `Control` instances from trusted host code, with unique IDs and no control aliases. It is bounded to 16 registrations for later growth, but v1 layouts require exactly two panels and must include every registered panel.
- `OverlayLayoutHost` resolves every panel and validates its parent before applying a profile. Unknown/missing references, unavailable controls, foreign-parent conflicts and invalid overrides leave the existing arrangement unchanged. Layout data cannot provide a scene path, script or factory.
- `OverlayLayoutController` owns selection and local preferences, never simulation state. `OverlayDocumentLoader` shares bounded JSON reads/discovery with themes.

Switching order/orientation reparents existing panels into a native `HBoxContainer` or `VBoxContainer`, preserving their descendants and command callbacks. It restores keyboard focus when the focused descendant remains available. Changing only weights/spacing updates the existing container rather than recreating it during slider interaction.

The weight controls proportional distribution through `size_flags_stretch_ratio`, subject to native minimum-size rules; it is not a guarantee of exact screen-width percentage. A horizontal profile stacks vertically when the host is narrower than 1,000 pixels or the combined panel minimum widths plus spacing, whichever is larger. Window resize and panel minimum-size changes re-evaluate this fallback. Returning to sufficient width restores the requested horizontal order. The selected profile and weight remain unchanged during fallback.

The controls retain their scroll container. The habitat viewport has a 240-pixel minimum height. Extremely small windows or very large custom control minima can still exceed available space; full accessibility/resolution guarantees remain a later UI gate.

## Local layout mods

Copy a shipped layout JSON, use a unique ID/name, and place it in `user://overlay-layouts/`. The current registered IDs are `overlay.controls` and `overlay.habitat`; include each exactly once. Change their order, orientation, spacing or leading weight. Restart the client and select the new profile.

The loader examines at most 32 directory entries without recursion, accepts one JSON object per file up to 16 KiB, and registers at most 32 additional profiles. Built-in IDs are loaded first and duplicates reject. Unknown fields and invalid definition values reject registration. Structurally valid definitions with unknown panel IDs cannot activate; the current arrangement remains intact. Discovery order is not guaranteed, so keep the folder dedicated to a small set of layout files.

`user://overlay-layout-settings.json` stores schema version 1, selected layout ID and current leading weight. Reads are bounded to 4 KiB and validate exact fields, registered ID and finite weight. Missing, malformed or unavailable selections fall back to the default; a structurally valid selection that cannot resolve its panels also falls back. Pointer slider drags save on release; keyboard changes save immediately. Failed writes warn without reverting the applied layout. Layout preferences have their own file so theme selection cannot overwrite them.

Schemas are `overlay-layout-v1.schema.json` and `overlay-layout-preference-v1.schema.json`. Panel resolution and parent ownership remain code checks beyond JSON Schema. Mods only arrange registered controls and inherit the same authenticated action adapters; they add no capabilities or access to hidden server data.

## Verification

Windows Godot 4.7.2 import, `overlay_layout_test.gd`, existing theme checks and the client habitat-layout checks passed locally. Layout tests cover all presets, rejected executable fields/duplicates/nonfinite weights, panel alias rejection, order changes, callback/focus preservation, allocation updates without recreation, atomic failure, custom profile registration, missing widget references, responsive fallback/restoration, reset, preference validation, bounded document reads and unchanged world snapshots.

Windows/Ubuntu CI includes the layout script. Actual mod-directory discovery, saved-preference disk recovery, graphical readability, mouse/keyboard interaction and Linux execution still need dedicated checks.

Next: configurable HUD/inventory widgets over authoritative observations, a generalized layout schema and widget registry, then drag/reorder customization and additional accessibility settings.
