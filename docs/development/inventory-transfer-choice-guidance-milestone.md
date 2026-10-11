# Inventory transfer choice guidance milestone

Successor to merged PR95, base 856df31112f23cd4e8c08306152e884adcfc5193.

Assessment: the owned Move preview repeated the destination capacity immediately above it and displayed an equipment slot and occupant that Move does not submit. Browsing was labeled knowledge but did not explicitly distinguish viewing from physical access.

The existing browse label now explains that viewing opens and moves nothing. The existing destination label identifies physical transfer into owned storage. The Move preview retains exact selected item/source/destination, loaded mass and freshness-fenced closure paths; capacity remains once beside the destination selector. Equipment retains its separate slot/occupant guidance. Tray collection keeps its own capacity evidence.

Scope is disposable presentation and directly relevant tests. No controls, schemas, command payloads, authority, transport, automatic open/retry, or predictions change. PR96 machinery recovery and PR97 extraction fixtures are excluded.

Verification pending: pinned Windows checks, paid nested actual-shell keyboard/focus/scroll/conservation, and exact-head Windows/Linux CI. No port or captures needed unless uncertainty arises. Human tutorial gate awaits human; controller/VR, live network and Linux graphical acceptance remain unverified. Coordinator owns merge. Keep the isolated worktree for review.
