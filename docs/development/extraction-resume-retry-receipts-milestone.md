# Extraction Resume retry receipts

Successor to PR100, baseline b2343530b5b8de9c10ae646ef8dc649be64e9992. ProductionSimulationSystem owns the persisted bounded receipts and extraction job; fixed-tick ingress remains the only writer. No schema, inventory, refinery, art or configuration expansion.

## Result and authorization

An identical retained Resume after completion returns a copy of its original successful receipt, including original request ID, fingerprint, revision and applying tick. Validation and application both supply the canonical command ID to the Resume authorization path. Current authenticated world/region, inventory permission, capable body and available unreserved hand checks precede receipt matching. The fingerprint binds principal, operation and the entire canonical payload, including expected revision. Only an exact retained match avoids mutable job existence/source reach checks. Fresh requests still require the reserved job and source reach; changed intent and foreign actors cannot retrieve prior success. The existing applying-tick/timebase/ID checks and bounded receipt retention remain unchanged. Evicted receipts do not guarantee retry success.

## Regression evidence

The existing PR100 paid checkpoint/reconnect fixture completes the remaining reserved cycle, then retries Resume through authenticated transport. It compares the exact original receipt and every production/inventory/tool field except advancing last-tick metadata. Repeated retries, changed revision, fresh absent-job requests, authenticated foreign wire requests, canonical ID collisions from another authorized principal and revoked permission are exercised. Completed matter, energy and component wear cannot repeat. The existing independent restore/Cancel branch remains covered.

## Verification and limits

Pinned Windows Godot 4.7.2 import/startup, sustained domain and paid recovery checks passed during iteration. The first recovery run exposed a freed foreign-client reference after replacement; reauthenticating that fixture client repaired the test, and the bounded rerun passed. Final committed-head focused verification and exact-head CI remain the Coordinator gate. Coordinator granted exclusive port 27849; the immediate pre-run TCP probe was empty, and the post-run probe found no local/remote TCP entries. Tests use a disposable APPDATA profile and fixture-owned cleanup. Source review and meaningful runtime regression are the evidence planned for this narrow ordering fix. No human, crash, graphical, controller/VR, public-network, deployment or release acceptance is claimed. Coordinator owns review and merge; managed worktree remains retained for review.
