# Public server status and channel projections

## Scope

`packages/server-status` is a first-party MIT, PHP 8.3+/PSR-4 library, separate from Twitch, Discord, simulation state and detailed profiling. It validates explicit public observations and stores bounded latest-per-region data through ReactPHP promise contracts. `packages/twitch/src/Status/ChannelStatusProvider.php` maps an operator-approved Twitch broadcaster to a world/region and returns the public view.

This is an internal backend foundation. Authenticated network publication, a real Godot status producer, connected-player accounting, durable broadcaster bindings and Twitch panel/dashboard UI are not implemented. Tests publish synthetic observations; logical inventory body count must never be presented as connected multiplayer users.

## Publication and disclosure

The exact v1 host publication has schema version, private routing `world_id`/`region_id`, tick number, public server name, online flag, players online, configured capacity and observation Unix time. `PublicServerStatus` rejects extra fields, malformed/deep/oversized JSON, invalid UTF-8/control text, fractional/negative/oversized counters and inconsistent offline/capacity states. Names are limited to 128 code points; scope IDs to 128 bytes. Input is at most 4096 bytes and stored as immutable normalized JSON.

`PublicStatusIngestor.ingest()` receives world/region scope from an already authenticated host session and requires payload scope to match. Its API does not perform authentication itself; never create that scope solely from the publication JSON. Viewer projection excludes routing IDs/tick and returns only approved public fields. No whole world snapshots, medical state, chat, access codes, profiler content or connection addresses enter this contract. Frontends must still escape public text as text rather than HTML.

## Cache and freshness

`PublicStatusRepositoryInterface` returns promises for store and public view. The in-memory adapter defaults to **16 regions, 64 KiB encoded data and 30 seconds freshness**; supported maxima are 128 regions, 512 KiB and 300 seconds. It stores latest successful publication order and evicts oldest publication when either count/byte capacity is exceeded. These are encoded-payload limits; PHP object/container overhead and bindings also consume bounded memory. It is disposable presentation cache, not world persistence.

Publication uses service-supplied current time. Future-dated or already stale observations reject. Retained tick and observation time cannot regress. Identical normalized retries return the existing document without extending freshness or changing retention order. Conflicting data at an identical tick/time frontier reject. A newer observation timestamp can report offline status at an unchanged final simulation tick. After eviction/restart, historical frontier detection is lost; ingestion freshness still applies. Production host epochs/restart handling require an explicit binding policy.

Views return `availability` (`fresh`, `stale`, `unavailable`), `effective_online`, and a detached latest public status or null. Stale views may include last known data, but **effective_online is false**; clients must not render the retained `status.online` alone as current liveness. Reads cannot make old data fresh. A service clock before the recorded observation marks it stale. Counters expose only retained region count, encoded bytes and bounded evictions.

## Channel bindings and races

`ChannelStatusProvider.bind()`/`unbind()` are trusted controller methods after broadcaster and host-operator approval; they are not viewer endpoints. Bindings cap at 16 by default, configurable to 128. Numeric broadcaster IDs resolve to server-side world scope, so a viewer cannot choose a private world ID in a read request. Unbound channels return no status.

Each bind/rebind advances an internal bounded generation. A repository promise resolving after unlink/rebind must match the captured generation, including unlink/rebind to the exact same world object; otherwise it returns unbound with no payload. Bindings are not persisted or cached inside Godot. Production JWT/OAuth access checks and current-channel validation must wrap this provider.

## TwitchPHP integration direction

Use the owner's existing **TwitchPHP** (`vzgcoders/twitchphp`) and **TwitchPHP-Http** (`twitchphp/http`) as the preferred providers for OAuth, Helix repositories, EventSub and channel events behind Frontier's adapters. Reviewed local revisions: TwitchPHP `26a6c39202c951030bdb436d04af9e064a9b4e3f`, HTTP `c1cb8a7e176535f7e103317ee5c88476cf373f99`. Both declare MIT; no upstream source is copied or edited here.

The reviewed TwitchPHP framework requires PHP 8.4, while current Frontier packages support PHP 8.3; host a future framework adapter/service in an explicit PHP 8.4+ boundary. Its HTTP library supports PHP 8.1+ and can fit the current runtime. The reviewed HTTP client automatically retries transport errors and some HTTP errors, with a queued concurrency model. Non-idempotent chat sends require explicit retry/queue/deadline policy before switching from the conservative direct sender. Proposed upstream extensions: configurable write-retry policy, bounded pending queue/response buffers and explicit source-only options on the chat repository. Reuse the libraries rather than duplicate OAuth/EventSub implementations; selection/installation remains future work.

## Checks and next steps

Offline Windows PHPUnit scenarios cover authenticated scope mismatch, forbidden private fields, freshness/TTL edges, clock bounds, delayed/conflicting publications, normalized retries, detached views, channel isolation/unbind, delayed rebind results and retention under 100 oversized-name publications. No Twitch account, live HTTP request, token or viewer panel is involved.

Next implement authenticated host publication and explicit connected-player counts, broadcaster authorization and durable binding epochs, then reuse TwitchPHP providers for OAuth/EventSub and implement the first read-only panel/status page. All external I/O stays asynchronous and never blocks Godot ticks.
