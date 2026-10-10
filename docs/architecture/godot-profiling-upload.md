# Promise-based Godot profiling upload

`ProfileCaptureUploader` is a host-owned integration node under `src/integrations/profiling/`. It uses the existing `GamePromise`, `ServiceResult` and `PromiseDispatcher` contracts. It is not an autoload, simulation system or public player/LLM tool, and is not created by bootstrap. No upload happens by default.

## Explicit configuration

`configure(endpoint, bearer_token, maximum_bytes, timeout_seconds, allow_local_http)` takes server-owned startup configuration. The route must be `/v1/profiling/captures`, with no query, fragment or URL credentials. Endpoint authority syntax is deliberately narrow ASCII; HTTPRequest still validates the actual URL and performs HTTPS certificate verification. Credentials must match opaque bearer-token syntax and are not read from world saves, Discord messages or client intents.

HTTPS is the normal mode. Debug builds may explicitly permit HTTP on literal `localhost`, `127.0.0.1` or `[::1]` endpoints. Plain HTTP to arbitrary hosts is rejected. Redirects are disabled so authorization cannot follow a different destination. Tokens/endpoints are never included in diagnostic records or error messages. This node and its credentials belong on the trusted host, never in replicated client configuration or committed assets.

Defaults are one MiB request limit, fifteen-second request timeout and four KiB response limit. Request limits may be 1–8 MiB, timeouts positive and at most sixty seconds. These must agree with deployment-specific PHP upload limits. Configuration changes are rejected while an upload is active. Failed configuration leaves the previous configuration intact.

## Capture and transport lifecycle

`upload_world_capture(world, sample_limit)` always returns a `GamePromise`. It rejects physics-frame calls, absent configuration, missing scene-tree membership, invalid worlds/limits and concurrent submissions. Call from idle processing or an explicit UI/admin action, not a physics callback. Capture copying, percentile aggregation and JSON encoding are bounded synchronous CPU work performed before network submission; they should not run every frame. Sample limits are 0–2,048, with a default of 120.

The method asks the world for a detached profiling capture, checks UTF-8 encoded byte size and starts a fresh threaded `HTTPRequest`. The network operation does not suspend simulation ticks. A second upload is rejected without creating a queue. Only JSON content/accept headers and the configured bearer header are supplied; compression is not requested. Transport callbacks settle telemetry promises rather than mutating world systems.

Each request has a generation-bound completion callback. Cancellation invalidates the generation before aborting transport; late callbacks cannot settle a subsequent request. Completion frees the request node and releases its slot before deferred promise reactions execute. Leaving the scene tree cancels pending work and clears configuration. The owner must keep the node alive for the request's lifetime and handle both promise branches.

```gdscript
var uploader := ProfileCaptureUploader.new()
add_child(uploader)
var configured: ServiceResult = uploader.configure(telemetry_endpoint, telemetry_credential)
if configured.is_success:
	uploader.upload_world_capture(world, 120).then(on_telemetry_saved, on_telemetry_failed)
```

This example assumes host-supplied configuration and pre-existing callbacks; it does not implement credential acquisition or activate an endpoint. Promise continuation overload follows the existing dispatcher rejection policy. Never await telemetry from a fixed-tick simulation system.

## Response and failure handling

Only HTTP 200 with the exact versioned receipt fields resolves success. Validation checks schema/status, positive exact sequence, the requested capture-time tick and a 64-character lowercase hexadecimal fingerprint. The fingerprint is a server receipt value, not locally recomputed proof of semantic equality. No receipt grants gameplay authority.

Transport failures/timeouts, non-200 responses, oversized responses and malformed receipts reject with typed `ServiceResult` errors. Raw response bodies, credential values and upstream exception text are not exposed. There is no automatic retry; cancellation or timeout may occur after remote storage has committed. A future retry mechanism must retain the same immutable capture bytes rather than generating a new capture, and respect repository retention/idempotency limits and HTTP backpressure.

Numeric diagnostics expose active, completed, failed, cancelled and rejected-submission counts; cancellations also count as failed uploads. These are disposable integration metrics and are not world state.

## Remaining deployment work

The PHP HTTP adapter still defaults to deny-all authentication and remains unbound. A production host credential provider, token rotation, TLS/socket/rate-limit configuration and durable storage are needed before enabling uploads. This Godot node has not been executed and no tests were added or run. No credential was configured and no network request was made during development.
