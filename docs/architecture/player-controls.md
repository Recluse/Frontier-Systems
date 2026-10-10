# Configurable player controls and held UI cursor

## Player behavior

Hold **Left Alt** (default) to expose the cursor and interact with UI. Movement and mouse look pause while the cursor is exposed. Releasing Alt resumes the previous camera capture only when the look/navigation binding remains held. Releasing that binding, the cursor-release action (default Escape), losing window focus or opening settings clears capture. Returning to the app never silently recaptures the cursor.

The cooperative client has a **Settings** tab and a configurable settings shortcut (default F10). Inventory defaults to I, hand switching to X, active tool use to F and camera shortcuts to F1/F2/F3. The legacy lab exposes the same preferences through its Controls settings button.

Click an action binding, then press a keyboard key/chord, mouse button, controller button or move a controller axis. Modifier-only bindings are accepted on release; hold a modifier and press another key for a chord. Cancel rebinding with its button. Shared bindings are allowed and reported; users can resolve conflicts or intentionally share an input. Restore defaults and mouse sensitivity are available. Movement, jump, sprint, free-camera ascent/descent, look capture, held UI cursor, release, world selection, overview zoom, player shortcuts and core UI keyboard navigation are listed. New gameplay actions must be registered here rather than hard-coded in consumers.

Mouse world selection retains click/select and double-click/use. A keyboard/controller selection binding uses a ray from the viewport pointer (or screen center when captured) and activates the hit object. Habitat bodies occlude the ray; the player capsule is excluded by collision layers. Selection is presentation intent; server ownership/reach still determines whether an action succeeds.

## Architecture and storage

`PlayerInputSettings` is a local presentation service autoloaded as PlayerControls. Typed consumers obtain it through instance(), use named InputMap actions and request/release camera capture with their owning node. The service arbitrates held cursor, settings suspension and focus loss across the root viewport and game SubViewport. It never creates an authenticated context or changes simulation state.

Preferences live in `user://player-controls.v1.json`, bounded to 32 KiB, with explicit binding kinds and numeric bounds. See `docs/schema/player-controls-v1.schema.json`. Missing/malformed entries retain defaults. Keyboard bindings use physical codes and left/right location; defaults deliberately distinguish Left Alt. Each action currently has one binding, with modifier chords supported. Controller axes have a direction and use Godot action deadzones; mouse look sensitivity is independent. No arbitrary scripts or executable resources load from this file.

Settings suspend capture and navigation while visible, including during key capture. Rebinding suppresses gameplay shortcuts. User appearance and controls remain separate from persistent shared-world records and server command authorization. Native mouse UI interaction remains Godot's standard GUI behavior; controller UI uses the configurable navigation actions. OpenXR action-map remapping is a separate future settings integration.

## Verification scope

Editor import and affected-script parsing passed. No gameplay suites or interactive focus/rebinding/controller checks were run for this change. Follow-up verification should exercise hold/release in both walking cameras and overview, release of look while Alt is held, tab switching, focus loss, remapping the cursor key itself, persistence/restart, conflicting bindings, keyboard world selection, controller axes and the legacy lab.
