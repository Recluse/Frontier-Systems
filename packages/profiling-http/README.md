# Profiling HTTP adapter

First-party MIT/PSR-4 package (`Frontier\ProfilingHttp\`) over profiling contracts and ReactPHP HTTP, streams, event loop and promises. It implements **POST `/v1/profiling/captures`**, but is not connected to the control-plane application or a listening socket.

## Composition and authority

Construct `ProfileCaptureHttpHandler` with an event loop, `HostAuthenticatorInterface` and the core `ProfileCaptureIngestor`. `ProfileCaptureServerFactory::create` installs ReactPHP streaming-request middleware and returns an unbound server. Automatic buffering is unsupported: the handler requires an event-driven readable body and refuses synchronous PSR streams.

The authenticator derives authorized world/region scope from server-owned host/session state, never JSON, client world headers, source IP or Discord messages. It must use nonblocking verification. Expected credential denials reject `HostAuthenticationFailed`; `DenyAllHostAuthenticator` is the safe unconfigured provider. Credential issuance, token lookup, Steam verification and host leases remain unimplemented.

The body pauses before authentication. Successful scope enters bounded body reading and core ingestion, which independently matches payload identity. Authentication has a deadline; late results cannot begin ingestion. Best-effort cancellation cannot override an already settled deadline result.

## Limits and lifecycle

Defaults are one MiB payload, two active uploads, five-second authentication and ten-second body deadlines. Configuration permits up to eight MiB, sixteen concurrent uploads and thirty-second deadlines. Authentication, body reading and repository settlement hold admission slots. Excess uploads receive 429 with `Retry-After: 1`; no application queue is created.

Only `application/json` with no compressed encoding or URL query is accepted. Declared content length is checked without overflow; unknown/chunked lengths are bounded as data arrives. Size is checked before concatenation. The reader rejects mismatched lengths, stream errors, premature closure and timeouts, removing listeners and timers on settlement. Failed bodies pause consumption. Every response uses `Connection: close` to avoid reusing incomplete rejected uploads; connection failure may prevent response delivery.

The application owns TLS, socket/connection caps, host rate limits, listener errors and graceful shutdown. Upload admission does not bound all TCP connections or PHP heap overhead. Storage adapters must provide bounded deadlines and resolve ambiguous writes using idempotency; the handler does not timeout a write that may have committed. The memory adapter settles immediately. The factory opens no socket.

## Responses and metrics

| Status | Meaning |
| --- | --- |
| 200 | Stored or retained identical-byte receipt, including sequence, capture tick and fingerprint. |
| 400 | Invalid query/header, unavailable body, length mismatch or interrupted stream. |
| 401 | Host credentials denied. |
| 404 / 405 | Wrong route/method; 405 advertises POST. |
| 408 / 413 / 415 | Body deadline, size limit or unsupported media/encoding. |
| 422 | Invalid capture, scope mismatch or stale repository input. |
| 429 | Upload capacity reached. |
| 503 | Authentication/storage outage or missing streaming pipeline. |

Versioned receipt/error schemas are under `docs/schema/`. Responses expose stable codes, no exceptions, capture content or credentials, and use `Cache-Control: no-store`. Numeric metrics report active, accepted, post-admission failed and overload-rejected uploads; early route/header failures are excluded from post-admission counts.

## Development status

Composer here resolves local profiling/world-contract paths. Consumers must register all three packages at their root. This package is not a live route, control-plane production dependency or PHAR component. Formatting/PHPDocumentor commands and Windows/Ubuntu package metadata/autoload CI include it. PSR-12 formatting was applied; no dependency installation, HTTP execution or tests were performed. Godot uploads, production authentication and durable storage remain pending.
