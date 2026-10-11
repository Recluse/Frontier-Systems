# Less obstructive gameplay UI

Owner requested 2026-10-11: reorganize the actual UI using Stationeers and Space Station 13 as behavioral references. This is a presentation successor priority after the active inventory recovery context milestone; preserve current implementation scopes.

## Direction

Keep the central scene and selected object visible. Use a compact persistent active-hand and essential status display. Open inventory/equipment on demand. Show one contextual workstation or construction panel for the current interaction, with advanced details, help and diagnostics collapsed by default. Keep pending, rejection, disconnected and recovery uncertainty visible even when detailed panels are closed. Preserve all stable IDs, keyboard focus, accessible text, canonical commands and authority boundaries.

Current FirstPlayable bootstrap builds a tabbed side panel with a 420-pixel minimum width and separate production/inventory/settings/machinery/terrain/guide sections. Review actual desktop and narrow-window occupancy before changing layout, including long IDs and error text. A video-only hidden HUD does not satisfy this gameplay requirement.

## References and provenance

Stationeers beginner guide, read 2026-10-11: https://www.stationeers-wiki.com/Beginner%27s_Guide documents bottom-center hands, explicit inventory access and separate in-game help. Behavioral inspiration only; no artwork, text or bindings copied.

/tg/station HUD documentation, read 2026-10-11: https://codedocs.tgstation13.org/datum/hud.html documents distinct inventory slot objects and HUD ownership. Independently express requirements; no upstream code or assets copied. Baystation source remains excluded from AI review.

## Acceptance

Use real integrated client views at 1920x1080 and 1100x700. Demonstrate selection, active-hand/equipment, inventory transfer, workstation processing, construction and reconnect while the object of interest stays visible. Verify keyboard-only focus and scroll, no clipping, readable captions, preserved pending request identity and rejection/recovery cues, and unchanged simulation snapshots. Use meaningful existing layout/input tests; record genuine captures when they resolve layout uncertainty. Human usability remains unverified until a player is available.
