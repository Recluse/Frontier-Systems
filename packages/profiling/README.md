# Frontier Systems profiling package

First-party MIT PHP library for detached Godot tick captures, reusable outside the control-plane application. Namespace: `Frontier\Profiling\`; every source file declares strict types and uses PSR-4. PHP 8.3+, ReactPHP promises and the existing world-contracts package are the production requirements.

## Contracts

- `Capture\ProfileCaptureDocument::fromJson` validates the v1 capture/history/report contracts, with an eight MiB encoded limit and JSON nesting depth 32. It stores immutable normalized JSON bytes, not mutable decoded objects.
- `Validation\RecordGuard` supplies shared exact-field, bounded-array, identifier, numeric and counter checks.
- `Persistence\ProfileCaptureRepositoryInterface` returns ReactPHP `PromiseInterface` values for loading/storing latest captures.
- `Persistence\InMemoryProfileCaptureRepository` is a bounded development adapter: latest capture per world/region, default 16 regions and 16 MiB retained encoded data, configurable to at most 128 regions and 128 MiB.
- `Ingestion\ProfileCaptureIngestor` binds captures to a **server-derived authenticated world identity** before invoking a repository. It converts validation/scope errors to rejected promises.

```php
$repository = new \Frontier\Profiling\Persistence\InMemoryProfileCaptureRepository();
$ingestor = new \Frontier\Profiling\Ingestion\ProfileCaptureIngestor($repository);

// Scope comes from authenticated host/session state, never capture JSON.
$ingestor->ingest($authenticatedWorldIdentity, $capturedJson)->then(
    function (\Frontier\Profiling\Persistence\StoredProfileCapture $stored): void {
        // Record the receipt without touching Godot world state.
    },
    function (\Throwable $failure): void {
        // Surface or count rejection; do not block a simulation tick.
    },
);
```

The memory adapter settles immediately without I/O. Durable adapters must use event-loop-compatible drivers and preserve the interface's ordering/failure behavior. No files, runtime subprocesses, child processes, shell orchestration or POSIX APIs are used.

## Validation and retention

Validation enforces exact record fields, collection bounds, nonnegative exact tick/count values, increasing sample ticks within the capture frontier, unique system observations, finite bounded-key numeric counters, consistent budget flags and summary window totals. Timing summaries must have consistent ranges and observation counts. Empty windows require null endpoints/statistics. World IDs and identifiers use byte limits consistent with the PHP world contract; prefer ASCII stable IDs for cross-runtime compatibility.

Percentile values and per-system summary provenance are shape/range checked, **not recomputed or certified** from raw history. Telemetry is observational, not gameplay authority or a signed benchmark. Transport authentication, host leases, request buffering limits, rate limits and concurrency limits are still required before accepting remote uploads.

The normalized fingerprint hashes encoded JSON bytes with insignificant whitespace removed. Object key ordering and numeric encodings can still differ; this is not semantic deduplication or a signature. Identical retained bytes resolve the same immutable receipt. A delayed capture cannot replace a newer capture-time tick. Different bytes at the same tick use successful store order. Replacement refreshes retention order; reads and identical retries do not. Oldest stored regions are evicted when count or encoded-byte limits are exceeded. Receipt sequences and retention exist only within this process; eviction/restart removes retry and frontier memory.

An oversized store rejects before eviction, retaining prior content. Encoded-byte limits do not measure PHP heap overhead or transient parsing memory. The captured payload may exceed eight MiB at the maximum Godot history size; select a smaller window before exporting. Keep JSON parsing and aggregation off the Godot tick loop, and rate-limit PHP work so large captures cannot monopolize its event loop.

## Development integration

Running Composer from this package resolves the local `../world-contracts` path and ReactPHP promises. Consumers must register both local package paths in their root Composer repository configuration because dependency repositories are not inherited. The control-plane application's production dependency graph and lock file have not been changed; this package is not yet wired into its HTTP handler or PHAR.

The main `composer cs`/`composer cs-check` finder includes this source, and `composer docs` generates its PHPDocumentor output. CI has a Windows/Ubuntu metadata/dependency/autoload job for this package. There is no HTTP upload endpoint, Godot network exporter, database adapter or PHP capture-to-report recomputation yet. No tests were added or run, and PHP execution/dependency installation were not performed for this change.
