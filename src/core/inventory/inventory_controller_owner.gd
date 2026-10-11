extends RefCounted
class_name InventoryControllerOwner

## Trusted synchronous owner boundary. Candidates are detached projections of
## validated canonical inventory metadata, keyed by body ID. No external I/O.
## Each entry has body_id, principal_id, body_container_id and control_epoch.
func controller_candidate() -> ServiceResult:
	return ServiceResult.failure(&"invalid_candidate", "No canonical owner is installed.")


## Compare the complete expected body projection, validate the next exact epoch,
## then commit canonical metadata and body-scoped ongoing ownership atomically.
## Restorable inventory owners invalidate jobs/views/grips in this same commit.
## Failure must preserve all state, including ongoing work and token identity.
## Success must perform no callbacks and return before binding publishes a token.
func commit_control_epoch(_expected: Dictionary, _next_epoch: int) -> ServiceResult:
	return ServiceResult.failure(&"invalid_candidate", "No canonical owner is installed.")


## Volatile same-process restore fence, never serialized with canonical epochs.
## Owners that support restore must advance this on each successful restore.
func controller_restore_generation() -> ServiceResult:
	return ServiceResult.success(0)
