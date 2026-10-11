extends RefCounted
class_name InventoryControllerOwner

## Trusted synchronous owner boundary. Candidates are detached projections of
## validated canonical inventory metadata, keyed by body ID. No external I/O.
## Each entry has body_id, principal_id, body_container_id and control_epoch.
func controller_candidate() -> ServiceResult:
	return ServiceResult.failure(&"invalid_candidate", "No canonical owner is installed.")


## Compare the complete expected body projection, validate the next exact epoch,
## then commit canonical metadata atomically. Failure must preserve all state.
## Success must perform no callbacks and return before binding publishes a token.
func commit_control_epoch(_expected: Dictionary, _next_epoch: int) -> ServiceResult:
	return ServiceResult.failure(&"invalid_candidate", "No canonical owner is installed.")
