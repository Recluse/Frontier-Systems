# Game event logging

First-party MIT, PSR-4 `Frontier\EventLogging\`. GameEvent/EventPolicy validate host events; EventIngestor records them through a supplied logger. DiscordPhpEventBridge attaches a queued Monolog 3 handler to **`$discord->getLogger()`**, using **`$discord->getLoop()`** and the existing asynchronous channel sender. It creates no second Discord client/logger and never uses child processes.

## Configure an existing bot

1. Install this package into the operator-owned DiscordPHP application, sharing compatible Monolog 3/ReactPHP dependencies. DiscordPHP is an optional integration dependency rather than bundled into the game's control plane; its other features/dependencies are outside this logging adapter.
2. Copy `config/development/event-logging.example.json` to an ignored local file. Set the actual guild ID, authoritative world/region, approved staff role/user IDs (including any bot overwrite grants), conversation audiences and channel routes. No bot tokens belong in that file.
3. After the bot's ready event and complete guild cache, call `examples/attach-to-discordphp.php` with the existing client, decoded configuration and a host-only bearer token. Keep the returned server/socket/bridge for shutdown. The example binds only loopback port 27841; remote hosting needs a deliberate authenticated TLS deployment.
4. Set `FRONTIER_EVENT_URL=http://127.0.0.1:27841/v1/events` and the matching `FRONTIER_EVENT_TOKEN` in the game host process. Empty URL disables telemetry. Environment files are examples; the launch process must load the variables.

Example `channels` (replace IDs):

```json
{
  "111111111111111111": {"audience":"public","scope_id":"","kinds":["game.event","production.batch"]},
  "222222222222222222": {"audience":"public","scope_id":"","kinds":["chat.public"]},
  "333333333333333333": {"audience":"staff","scope_id":"","kinds":["llm.request","llm.response"]},
  "444444444444444444": {"audience":"staff","scope_id":"","kinds":["simulation.command","production.extraction","chat.private"]},
  "555555555555555555": {"audience":"private","scope_id":"conversation-a","kinds":["chat.private"]}
}
```

Staff routes can observe private events for moderation. Private conversation routes match only their configured scope. Public routes accept only public event kinds. Unknown kinds, wrong audiences, missing private scope, extra fields and credential-shaped field names reject. LLM request/response kinds are staff-only, never public fallback. EventPolicy supports additional server-owned types with explicit scalar fields; it forbids replacing default classifications.

## Channel permissions

DiscordGuildAudienceVerifier checks current cached text/announcement channels in the configured guild before every send. Staff/private destinations require an explicit @everyone View Channel denial, no unapproved role/member View Channel grants, and all Administrator roles approved as staff. Private conversation grants additionally require the scope's approved users/roles. Guild owners inherently bypass channel permissions and must be trusted operators. Keep the cache complete/current and close the integration when guild authorization becomes uncertain. Unsupported threads/DMs/missing caches reject. A custom asynchronous verifier can replace this conservative policy for other channel types.

The routing handler consumes typed game events before lower-priority unclassified Monolog exporters can leak them. Ordinary SDK logs continue through existing handlers and are not automatically forwarded. Do not put an unclassified exporter above the event handler; route local audit storage through an explicitly trusted sink. Closing the bridge keeps the closed classifier attached to avoid shutdown leakage.

## Runtime API

Godot: `world.event_outbox.publish(kind, audience, conversation_scope_or_empty, data)` returns a bounded queue result. `publish_async(...)` returns the existing GamePromise; acknowledgement/rejection continuations run through PromiseDispatcher outside physics callbacks. Never await it from a simulation tick. Built-in data contracts:

| Kind | Audience | Exact data fields |
|---|---|---|
| `game.event` | public | text |
| `chat.public` | public | text, speaker |
| `chat.private` | private | text, speaker |
| `llm.request`, `llm.response` | staff | text, agent |
| `simulation.command` | staff | operation, success, request_id, code |
| `production.batch` | public | recipe_id |
| `production.extraction` | staff | request_id, completed_cycles |

Command results (excluding continuous movement poses), production batch completions and completed extraction cycles are wired automatically. Existing/future subsystems publish additional registered semantic events through the same API. Chat/LLM contracts provide logging hooks; they do not implement those gameplay systems. Do not pass arbitrary command payloads, authorization headers, credentials or model execution permissions. Credential-name rejection cannot identify secrets embedded inside natural-language text; prompt producers remain responsible for removing them before tracing.

The exact event v1 envelope includes identity, world/region, tick, kind, audience, private scope and scalar data. Limit: 16 KiB encoded/event, eight data fields, 8 KiB/string. Larger traces need explicit correlated chunk events/custom policy rather than silently dropping text. Telemetry cannot authorize or mutate canonical world state.

## Delivery guarantees and metrics

Godot enqueues from runtime signals and sends HTTP only during idle `_process`; no simulation tick awaits PHP or Discord. Its queue is bounded to 256 events/512 KiB, one 5 s request, no redirects, at most three attempts with increasing delay. HTTP 202 acknowledges validation/Monolog ingestion, **not Discord delivery**. The host outbox is memory-only and independent of world checkpoints.

PHP deduplicates 1024 retained scoped event fingerprints; retained conflicting IDs reject. DiscordRoutingHandler queues whole fanouts atomically (256 fragments/512 KiB by default), emits conservative UTF-8 chunks below 1900 bytes and disables Discord mentions. One promise is dispatched per pump; explicit failures retry at most three times. An uncertain 30 s timeout stalls the dispatcher until operator restart rather than spawning unlimited unresolved sends. Late callbacks cannot settle another item. SDK rate-limit behavior remains owned by DiscordPHP. A send acknowledged remotely but lost locally may duplicate after retry; this is best-effort telemetry, not an exactly-once audit journal.

Counters expose queued bytes/messages, in-flight state, accepted/delivered, invalid/unrouted/overflow/failed and stalled/closed status. Use these with existing profiling. Overload never stalls the world. Durable disk/database outboxes, retention/encryption/access policy, multi-host authentication and live bot/ACL deployment verification remain extensions.

## Check locally without Discord sends

Run `composer unit` in `services/control-plane` (includes event tests), `composer cs`, `composer phar`/`composer phpacker`, and `tools/test-event-logging.ps1` with the console Godot executable if needed. The harness creates a temporary host credential, starts a hidden loopback PHP receiver and confirms public/staff ingestion, credential exclusion and unchanged canonical snapshot. Its stdout is private developer telemetry, not a public channel. Logs stay in ignored `var/event-logging/`.
