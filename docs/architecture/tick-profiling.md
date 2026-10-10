# Bounded tick profiling

`SimulationRunner` keeps its existing cumulative tick/system metrics and now provides an opt-in recent history through `TickProfileHistory`. `WorldRuntime` exposes the observer APIs without exposing the runner node. Profiling is disposable observer state, never part of world saves or simulation decisions.

## APIs and lifecycle

- `configure_profile_history(true, capacity)` starts a fresh capture. Capacity must be 1–2,048 ticks; the default is 120. Configuration is rejected during an active tick.
- `configure_profile_history(false)` stops capture while retaining existing samples. The supplied capacity is validated but does not resize retained history when disabling.
- `profiling_history(limit)` returns the latest requested samples in chronological order with detached nested records. The request is clamped to capacity; zero returns metadata without samples.
- `profiling_snapshot()` retains existing metrics and adds command execution time/count, capture-enabled state, last capture overhead and total measured tick time.
- `capture_profiling(limit)` builds a detached world/region capture with history and a report; `capture_profiling_json(limit)` encodes the same envelope without I/O. Both reject invocation inside a simulation tick. The panel summary button requests this on demand.

Capture is disabled by default. The prototype panel has a 120-sample toggle, command/tick/capture timing, queue depth and over-budget count. At 60 Hz, 120 ticks cover roughly two seconds and the maximum history roughly 34 seconds. Stopping simulation retains the history for post-run inspection; enabling a new capture discards the previous history. Restore begins with fresh observer metrics rather than loading them from domain records.

No synchronous files, sockets, Discord calls, Steam calls or LLM requests run during capture. Future exporters should obtain a detached bounded record between ticks and use an asynchronous adapter for I/O. No export service is implemented yet.

## Timing boundaries

All timings use Godot's monotonic microsecond clock. `command_usec` covers command application, completion signal callbacks and queue compaction. Per-system `elapsed_usec` covers that system's `simulate_tick`. Tick `elapsed_usec` also includes runner accounting and lightweight timing-sample collection.

Numeric counter hooks and ring insertion run after the tick execution measurement. Their cost is reported separately as `last_profile_usec`; `last_total_tick_usec` sums execution and capture time. The existing budget counters and historical `over_budget` flag compare execution time to the configured tick budget, excluding this final capture overhead. Inspect total time when judging the actual frame budget. UI rendering, GPU time, physics outside these system calls, asynchronous continuations, startup/import and storage costs are outside this measurement.

History insertion replaces one ring entry without shifting the retained sample array. Reading history makes deep copies and is bounded by the requested count, but can be expensive at maximum capacity; do not request a full history every frame. Reports calculate descriptive percentiles for the captured window; this does not establish a representative benchmark or prove deterministic behavior.

## On-demand reports and capture format

`TickProfileReport.summarize` computes count, minimum, maximum, arithmetic mean and nearest-rank p50/p95/p99 for tick, command and observed system durations. Nearest rank selects sorted index `ceil(p * count) - 1`; p50 for two samples is the lower value, not the interpolated median. Empty captures have null tick endpoints and null timing values, with zero counts. Queue peak, total processed commands and over-budget sample count refer only to the requested window, not the full run. Tick gaps are allowed and no missing observations are synthesized.

System summaries are sorted by stable ID and use only ticks in which that system was observed. Each includes its last observed tick and latest numeric counters; the report does not infer whether a counter is cumulative or a gauge. At most 64 distinct systems are retained across the entire report. Registration churn can introduce additional identities; their observation count is reported as `omitted_system_observations`. Aggregation validates bounded numeric observations and sorts only bounded arrays.

Reports run between ticks on explicit request; copying and sorting at maximum capacity can still affect frame responsiveness and must not be invoked every frame. Historical timing excludes report generation and final capture overhead. JSON encoding happens after aggregation and also stays outside tick execution.

The capture envelope identifies world, region and capture-time simulation tick, and contains raw history plus its derived report. When capture has stopped, the current tick may be newer than the historical window. Contracts are `tick-profile-report-v1.schema.json` and `tick-profile-capture-v1.schema.json` under `docs/schema/`, referencing the history contract. The [PHP profiling package](../../packages/profiling/README.md) now validates external capture JSON, binds it to authenticated host scope and provides a promise repository with a bounded memory adapter. There is no file writer, network exporter, HTTP ingestion endpoint or durable telemetry store yet. The Godot summary helper remains for internally generated records rather than complete untrusted validation.

## Counter contract

`SimulationSystem.profiling_counters()` defaults to an empty dictionary. It is invoked only while capture is enabled. Implementations must return at most 16 numeric counters, stay bounded, perform no I/O and leave canonical state unchanged. The ring examines only the first 16 entries, retains finite numbers with bounded string keys and ignores other values. At most the first 64 systems in runner order are sampled, even if more systems are registered; execution is unaffected.

Pressure counters report volume/airlock/sensor counts and cumulative transferred moles. Access control reports device count without walking all jobs. Machine controls report queue depth, queue age beyond due tick, peak pending receipts, last delivery attempts, cumulative delivered/dropped/rejected counts, installed part/wire counts, salvage/spare counts and board work progress/activity. Cumulative counters should be compared as deltas between samples; restoring a circuit resets disposable delivery counters and initializes queue peak from restored pending work.

Samples contain no actor IDs, sessions, command objects, freeform messages or live scene references. The versioned record contract is `docs/schema/tick-profile-history-v1.schema.json`. There is no untrusted history-ingress parser; records are generated by the runner and sanitized for retention.

## Remaining profiling work

The [Godot upload adapter](godot-profiling-upload.md) now provides explicit promise-based HTTP submission of detached captures with single-request backpressure, timeouts and validated receipts. It is not instantiated by bootstrap and performs no automatic uploads. Production authentication and deployment remain pending.

The [HTTP adapter](../../packages/profiling-http/README.md) now implements an authenticated streaming upload boundary with bounded admission and deadlines, but is unbound and not enabled in the control plane. A real authentication provider, socket configuration, Godot exporter and durable storage are still required.

Add controlled workload captures and measured baseline comparisons, startup/import timing, Godot CPU/GPU profiling integration, memory/resource diagnostics, bounded traces and asynchronous artifact export. Multi-region aggregation and PHP-service correlation need stable event/trace contracts. No tests were added or run, and this addition has not been executed in Godot.
