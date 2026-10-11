# Basic gameplay tutorial and captioned videos

Owner requested this milestone on 2026-10-11 (America/New_York). Queue it when playable characters and the basic engineering loop are verified usable. Existing character movement fixtures alone do not establish that readiness. Do not interrupt active milestones or announce a release date.

## Readiness and scope

Require a character that can spawn, move, look, select and interact in the actual client, plus a repeatable finite resource/inventory/construction loop and working recovery. Verify the controls and interactions in the chosen build before writing instructions. Prioritize this milestone before advanced rail, colony or ship tutorials.

Teach first session setup, character movement and camera/UI controls, selection and reach, inventory/hands, gathering and transporting finite material, workstation processing and equipment, basic construction, and saving/reconnecting. Include existing repair/recovery only where the build supports it. Use current bindings, show unavailable prerequisites and explain authoritative rejection without implying visual targeting guarantees success. Keep lessons short and ordered; distinguish implemented features from future scope.

## Recorded and edited tutorial deliverables

- Record real gameplay from a pinned verified commit/build, using ordinary screen/game-engine capture. Record each demonstrated action and its result; never fabricate successful interactions or use AI-generated imagery at any stage.
- Edit recordings with standard nongenerative tools: trim waiting/debug clutter, preserve the order of actions, use readable zoom/callouts and chapter titles, and remove secrets, private identities and unrelated desktop content. Do not present accelerated or edited sequences as real-time performance.
- Produce captioned tutorial videos with accurate synchronized captions, covering instructions and meaningful sounds. Deliver UTF-8 WebVTT/SRT captions, a transcript and a captioned viewing version; retain an accessible caption-selectable version where the eventual player supports it. Verify captions manually against the final edit, including names, controls, timing, contrast and mobile readability. Narration is optional; essential steps must remain understandable without audio.
- Keep source recordings, edit project and exports locally until retention/publication is approved. Record source commit/build, capture route/settings, editor/render tools, author/license, edit notes, caption review and acceptance limits. Rights-cleared MIT/CC0 artwork only; no new music/fonts or third-party footage without clearance. Use Git LFS if approved video assets are retained in the repository, and verify pointers/upload.

The owner authorizes recording and editing tutorial videos as milestone work. This does not authorize public upload, campaign media replacement, game release/deployment, paid tools or unrelated external sends. Route any actual permission blocker and final public-media clearance through Coordinator. Current verification screenshots remain uncleared.

## Acceptance and handoff

A reviewer follows the tutorial from a fresh temporary profile/world using only its instructions, with an actual playable character. Verify the taught finite loop, prerequisites, failure/retry guidance and save/reconnect in the pinned build. Test keyboard/mouse first; claim controller, VR, Linux graphical or multiplayer coverage only when actually exercised. Run focused existing Windows/Linux checks for any changed code.

Verify the final edited videos play, captions stay synchronized and legible, links/chapters/transcripts match the build, and no step depends on unshown resources or administrator privileges. Record completed versus unverified acceptance separately. Public tutorial publication requires Coordinator owner clearance for the concrete final videos and destination.

Dispatch one narrow implementation chat when readiness is met: isolated current-origin/dev-master managed worktree, descriptive branch without `codex/`, attached draft PR for source/documentation changes and this milestone's evidence. Split a substantial independent recording/editing task into a separate owner-requested chat when useful; avoid simultaneous shared UI/authority edits. Use Sol/medium for routine implementation and Luna/medium for simple copy/caption edits; one agent by default.

## Current readiness evidence

The [isolated readiness review](basic-gameplay-tutorial-readiness.md) reran the bounded Windows runtime checks and native real-client finite collection loop on the equipment PR #34 integration base. Both passed. Tutorial readiness remains open: character motion/guide calls were scripted, and physical keyboard/mouse selection, fresh character construction and actual client-UI save/reconnect still need human acceptance. Captures remain ignored internal evidence; no videos or public media were produced.
