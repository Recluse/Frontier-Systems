# Receipt-history optimization

Normal consciousness and motion commits now validate the current request/proposed change, shallow-copy bounded private arrays and append/evict a single receipt. Previously validated historical dictionaries remain private and immutable; public snapshots/receipts still deep-copy. Full saved-record validation remains on creation/loading.

Disposable receipt indexes replace history scans, and motion body indexes replace registry scans. Indexes rebuild from validated saves and update after successful commits; they are not canonical state. Atomic failure, detached observations, retry/eviction and corrupt-save checks still pass. Adapters must never mutate internal historical records.

## Five-repeat Windows comparison

Same debug executable/hardware and synthetic domain workloads as the [baseline](2026-10-09-baseline.md). Means average equally sized repeats; machine activity can affect results.

| Workload | Before | After | Ratio |
| --- | ---: | ---: | ---: |
| 64 consciousness commits with saturated histories | 56.364 ms/batch | 4.492 ms/batch | 12.55× faster |
| Paired motion commit with saturated history | 2.276 ms/commit | 0.091 ms/commit | 24.99× faster |

Raw comparison: [owner-optimization-60hz.json](owner-optimization-60hz.json), original [runtime.json](runtime.json). This comparison ran **before health world integration**, retaining the original four-system fixture. The domain owners are standalone in both runs. Full snapshot/load validation retains its cost.

The 64-body batch fits the 16.67 ms service-time budget in this measurement, not a worst-case guarantee or multiplayer capacity claim. Physics, chemistry, networking and scheduler work add costs; staggering remains appropriate.

The subsequent [runtime-60hz.json](runtime-60hz.json) rerun includes the new fifth world system. Compare its tick/snapshot costs as a changed workload. No 72/90 Hz performance or Quest result is claimed.

That integrated rerun measured mean idle tick costs of 0.045 ms without history and 0.081 ms with history; validated snapshot/JSON capture averaged 1.715 ms. The small two-body default health workload remains far below the 60 Hz tick budget. These are five-repeat means, not loaded-server guarantees.
