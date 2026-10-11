# Coordinator snapshots and focused CI

This change keeps the append-only coordination evidence in
`milestone-coordination.md` intact. A compact, explicit active-state record and a
read-only snapshot command will let the Coordinator compare current evidence and
due deadlines without rereading the historical ledger at every heartbeat.

CI will validate feature work through pull requests to `dev-master`, retain merge
queue checks, and keep full builds for integration pushes and manual dispatch.
Only an explicit prose-only pull request classification may omit runtime jobs;
the stable `CI required` gate still reports and validates the classification.

This tooling does not authorize merges, deployments, public media, or outreach.
Exact reviewed heads and required checks remain the merge evidence. Art
provenance, owner approval routing, exclusive task boundaries, and port
reservations remain governed by the existing project instructions.
