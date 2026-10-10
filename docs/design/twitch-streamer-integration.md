# Optional Twitch integration

## Direction and current implementation

Allow a streamer to link a Twitch channel to an authorized Frontier Systems server/world, interact with Twitch chat, expose selected public server information and optionally enable platform-event interactions. Twitch remains an optional adapter alongside Discord and Steam. Basic gameplay remains the development priority; this service must not become a dependency of simulation startup, tick progress or player chat/voice.

The initial MIT/PSR-4 package `packages/twitch` implements asynchronous **outgoing chat** through an injectable HTTP boundary and ReactPHP adapter. Live account linking, token management, incoming EventSub, server telemetry publication, Extension frontend/backend and gameplay event bindings are not implemented. No live Twitch account is connected, message sent or panel published by this change.

Twitch currently recommends EventSub plus its HTTP API for chat, rather than relying on its more limited IRC interface: [chat documentation](https://dev.twitch.tv/docs/chat/). Use EventSub for incoming messages, deletions/moderation events and eligible channel events; use Helix for supported outbound actions. Verify endpoint scopes and versioned subscription requirements when each feature is implemented.

## Server/channel linking and authorization

Persist broadcaster ID, authenticated world/region binding, publisher identity, enabled features and disclosure policy in a versioned binding. Twitch account IDs are not game permissions. Only a verified broadcaster/authorized channel manager and an authorized game server operator can establish or change that binding. Revoke both directions on unlink or lost grants; clear queued outbound work when the binding changes.

OAuth credentials remain in the PHP service, never Godot snapshots, client exports, Extension JavaScript or log records. Use approved OAuth flows with state validation, token validation/refresh, minimal scopes and reconnect/revocation handling. Credentials and Extension JWT secrets are different contracts; do not reuse one as the other. Full onboarding still needs a registered Twitch application and service configuration.

The initial sender expects an **app access token** with the bot/broadcaster authorizations described in [Send Chat Message](https://dev.twitch.tv/docs/api/reference/#send-chat-message). It explicitly sets `for_source_only=true`, limiting shared-chat delivery to the bound channel. User-token sends have different shared-chat behavior and cannot specify that field; they require a separate future adapter rather than accepting an arbitrary token mode.

## Chat and platform interactions

- Configurable incoming chat presentation and opt-in outbound status replies, announcements and approved player/chat relays. Separate Twitch, Discord and in-game scopes, with source labels, moderation and loop prevention; no automatic broadcast of private crew/PDA/LLM conversations.
- Commands such as server-status lookup use a closed registry and bounded execution. Broadcaster/moderator roles can authorize service administration where configured, but do not automatically become station administrators or bypass game capabilities.
- Later event bindings may include stream online/offline, raids, subscriptions, cheers, reward redemptions and poll outcomes, subject to scopes, channel eligibility and selected subscriptions. Each feature can be independently disabled.
- Viewer-driven gameplay is opt-in per server/world with quotas, cooldowns and a narrow action registry. Authenticated Twitch events become validated game intents for a later tick, never direct canonical mutations. Event IDs, binding generation and durable receipts prevent replay/double rewards. Redemptions require explicit fulfilled/cancelled outcomes when applicable.
- Chat text, user names and platform-event payloads are untrusted input. Bound message sizes, sanitize display output and prevent chat text from becoming executable scripts or LLM authorization. Any LLM-assisted reply uses explicit context/disclosure and the same outgoing limits.

Service I/O uses ReactPHP promises and bounded queues. Honor current Twitch API/chat limits and response headers with per-account/channel scheduling, configurable deadlines and backoff. A concurrency cap alone is not a rate limiter. Drop/replace expired status replies rather than retaining unlimited messages. Network timeouts can leave delivery unknown; do not automatically repeat a non-idempotent chat send. Distinguish HTTP acceptance from `is_sent=false`.

## Streamer panel and server information

Use a Twitch **Panel Extension** for a dynamic viewer-facing server card, with a broadcaster configuration view. A private streamer dashboard/OBS browser source and a linked hosted status page can reuse the same public projection. The simple linked page is a lower-infrastructure first deployment option; the design does not assume ordinary channel profile panels can be rewritten dynamically through Helix.

Suggested public fields: chosen server name, online/stale state, player count/capacity, campaign mode, public world description, advertised join instructions and selected public events. Precise body locations, private server endpoints, access codes, detailed profiler captures, medical records, moderator-only state and LLM/private chat remain outside the default projection. Publish player names only under an explicit server disclosure policy. Public text comes from validated server-owned metadata, not arbitrary Twitch request fields.

Godot supplies detached, versioned, permission-scoped status observations; PHP caches/coalesces them and serves timestamped summaries at a low configured cadence. The panel displays stale/offline state when data expires and cannot pretend an unavailable server is live. Snapshot exports and panel requests never pause simulation ticks. Authentication must bind status submissions to the correct host/world and panel requests to the correct broadcaster, with cross-channel isolation and bounded retention.

An Extension may use a PHP Extension Backend Service. Verify Twitch-issued JWTs, expiry, role/channel binding and secret rotation according to [Extension building guidance](https://dev.twitch.tv/docs/extensions/building/). Host/public deployments require their own registration/review/configuration. The first-party code/assets remain MIT; Twitch-provided runtime services/helper resources retain their separate platform terms and are not bundled by this initial package.

## Event delivery and failure handling

An installed/small service can start with EventSub WebSockets; a hosted multi-channel service may use authenticated HTTPS webhooks or a conduit when justified. Implement welcome/subscription timing, keepalives, reconnection, revocation and deduplication explicitly; see [WebSocket handling](https://dev.twitch.tv/docs/eventsub/handling-websocket-events/). Webhooks require signature/timestamp/challenge validation before enqueueing work. Bound event sizes, retained deduplication windows and channel counts; missed notifications must not be silently invented.

Observe bounded counters for active bindings/subscriptions, queue occupancy/drops, requests, rate-limit responses, retries, stale status, event deduplication, last successful update and token lifecycle failures. Never emit credential values. Disconnect/revocation stops new Twitch activity without stopping the game or Discord integration.

## Staged implementation

1. **Implemented foundation:** independent PSR-4 outgoing chat contracts, fixed-host ReactPHP HTTP transport, finite response/time limits, one in-flight send, sanitized failures and mock-based Windows checks.
2. Add account linking, encrypted/secure credential storage, OAuth validation/refresh, binding lifecycle and rate/deadline scheduling. No live send until its operator enables the configured channel.
3. Add EventSub incoming chat and moderation lifecycle, normalized events, deduplication and explicitly scoped UI/relay behavior.
4. Define public status schema, authenticated server publication and bounded cached projection; start with hosted status/dashboard presentation.
5. Build the Twitch Panel Extension/configuration/EBS and test with Twitch development tooling before publication.
6. Add independently configurable rewards/polls/other eligible events and game intents after basic gameplay/action authorization is ready.

Acceptance checks cover token/grant loss, multi-channel isolation, shared-chat scope, queue overflow, rate errors, unknown delivery, malformed responses/events, duplicated redemptions, stale snapshots, malicious chat/HTML and service disconnect while the Godot world continues ticking. Credentials and live-platform tests are separate from offline mock checks.
