# Machinery bounds presentation

## Ownership and behavior

MachineryPanel owns volatile intent and pending display dimensions. MachineryPlacementFeedback reads scoped physical mount records and reuses MachineryPlacement.half_size without calling placement clearance or changing canonical state. MachineryPreview draws decorations on input, visibility, observation and command-result events; unchanged feedback stays cached. No simulation tick, schema, persistence, bootstrap or terrain changes.

The ghost and selected machine now display the host's conservative bottom-centre axis-aligned envelope: 1.3 × 1.5 × 1.3 m ordinarily, 2.5 × 1.5 × 1.3 m with a fitted expander or six retained sockets, and 1.9 × 1.5 × 1.3 m with five retained sockets after expander removal. Broken mounted modules, disabled frames and empty sockets retain space. Grandfathered extra sockets use the same uncapped geometry as the host. Selected machines show all twelve box edges; walls keep their existing footprint presentation.

Text identifies server envelope dimensions and explicitly says that reach/floor feedback is advisory; clearance has not been checked. The host still decides overlap, ownership, hands and revision. Blue advice cannot certify placement, and a trusted restored overlapping machine is not certified by its selected outline. Pending targets hold submitted coordinates, mode, identity and display dimensions through subsequent observations; the host validates its current state. Rejection leaves the ghost for correction, success retires it, and hiding, retirement, unavailable observations or disconnect clears decorations. No decorative geometry has collision or picking authority.

## Verification route

The focused machinery_placement_bounds_test.gd exercises empty frames, broken expanders, six empty broken sockets, removed expanders, five/four retained sockets, broken ordinary heads and grandfathered eight-socket bounds. It checks ghost sizes, bottom-centre offsets, selected edge extents, cached feedback, cleanup and unchanged observations. machinery_placement_feedback_test.gd retains the real finite-material workshop and verifies queued-target locking, actual host floor rejection, freeform success, selection and panel cleanup. Existing wall feedback and machine preview tests check compatibility.

Run the repository's bounded tools/ci/run-godot-checks.ps1 with those test filenames. CI discovers the new bounds test on the existing pinned Godot 4.7.2 Windows/Linux matrix.

Graphical reproduction requires rendering and Coordinator reservation of loopback port 27851:

~~~powershell
& 'D:Godot_v4.7.2-stable_win64.exeGodot_v4.7.2-stable_win64_console.exe' --path . --xr-mode off --audio-driver Dummy --rendering-method gl_compatibility --script res://tools/godot/capture_machinery_bounds.gd
~~~

The bounded tool inherits the real finite-material workshop, opens a temporary authenticated host/client, checks the actual observed expanded envelope, captures ghost, genuine host rejection, pending and selected states under reports/machinery-bounds, and checks disconnect cleanup. It pauses host transport for one rendered frame solely to expose actual queued state. No external services or shared 27849 acceptance route.

## Results and limitations

On source head 51cccd73b1cf0267967ff27b157ccf32e858a38d (rebased onto 407f49e), Windows Godot 4.7.2 import/startup and all five focused scripts passed: machinery authority, bounds, machinery feedback, machinery preview and wall feedback. The authenticated Compatibility/OpenGL capture route passed with zero failures on that exact source head, including host rejection and disconnect cleanup. All four captures were visually inspected; two representative unedited views were retained in [the LFS gallery](../gallery/machinery-bounds/README.md) with exact provenance and limits. Logs/JUnit remain under ignored var/ci/final-bounds. Draft [PR #11](https://github.com/Valgorithms/Frontier-Systems/pull/11) tracks exact final-head Windows/Linux CI separately; local Windows success does not establish Linux acceptance. Linux local rendering, VR/controller interaction and human usability are separate acceptance limits. No merge, integration-branch push, release or deployment is part of this chat.
