# Frontier Systems server-status package

MIT, PHP 8.3+, strict types and PSR-4 namespace `Frontier\ServerStatus\`. ReactPHP promises and the existing world-contracts library are the runtime dependencies.

- `PublicServerStatus`: exact, bounded immutable publication; detached viewer projection excludes world/region/tick routing.
- `PublicStatusIngestor`: validates an already authenticated host scope before storing; it does not authenticate callers.
- `PublicStatusRepositoryInterface`: promise-based store/view boundary.
- `InMemoryPublicStatusRepository`: finite latest-per-region count/byte retention, timestamp freshness, replay/conflict checks and numeric diagnostics.

See [the architecture contract](../../docs/architecture/public-server-status.md). Twitch channel routing remains in its own adapter. No network endpoints, player counting, database writes or live platform calls are added.
