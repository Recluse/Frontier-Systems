# Simulation rate benchmark candidates

The opt-in benchmark matrix includes **60, 72 and 90 Hz**. The saved project and authoritative gameplay default remain **60 Hz**. These rates are candidates for comparison, not adopted production settings.

| Candidate | Approximate tick deadline | Ticks per second versus 60 Hz |
| --- | ---: | ---: |
| 60 Hz | 16.67 ms | Baseline |
| 72 Hz | 13.89 ms | 20% more |
| 90 Hz | 11.11 ms | 50% more |

Both benchmark scripts accept `--physics-hz=60`, `--physics-hz=72` or `--physics-hz=90` after Godot's `--` separator. They set the benchmark process's physics rate and runner budget; manual ticks use the corresponding delta. Defaults stay at 60 Hz. Budgets round upward to integer microseconds (16,667 / 13,889 / 11,112). Rate-qualified output filenames preserve the original baseline files and distinguish new runs. Run candidates sequentially, never concurrently on the same hardware.

```powershell
$godotBench = 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
foreach ($candidateRate in @(60, 72, 90)) {
    & $godotBench --headless --xr-mode off --path . --script res://tools/godot/benchmark_runtime.gd -- "--physics-hz=$candidateRate"
    & $godotBench --xr-mode off --path . --resolution 1280x720 --script res://tools/godot/benchmark_client.gd -- "--physics-hz=$candidateRate"
    & $godotBench --xr-mode off --rendering-method mobile --rendering-driver vulkan --path . --resolution 1280x720 --script res://tools/godot/benchmark_client.gd -- "--physics-hz=$candidateRate"
}
```

`--benchmark-config` prints the parsed rate, delta and budget without running workloads, activating rendering or changing the process rate. Duplicate/unsupported rate arguments reject. Example:

```powershell
& $godotBench --headless --xr-mode off --path . --script res://tools/godot/benchmark_runtime.gd -- --physics-hz=90 --benchmark-config
```

## Compare like workloads

Record mean/p95/p99/max tick service time, total work per simulated second, budget overruns, command setup, observer overhead, render CPU/GPU, memory and frame pacing. Current command fixtures keep commands **per tick** constant, so 72/90 Hz represent increased commands per simulated second. Domain fixtures are service-time microbenchmarks, not a complete physiology scheduler. Add a fixed-work-per-second comparison before selecting a production rate.

Changing physics rate does not automatically make rendering faster or set headset refresh. The desktop client benchmark is not a headset benchmark. Compare Quest 3 native presentation/tracking and physical-hand interactions at intended headset refresh separately; first hold server rate constant, then evaluate local physics/prediction and any proposed authoritative rate change. Never let each client's headset change shared server cadence.

Before gameplay rate changes, convert or explicitly rescale tick-based durations, assessment gaps, job progress, command budgets and persistence clocks. Current consciousness recovery is 60 ticks: 1.0 s at 60 Hz, approximately 0.833 s at 72 Hz and 0.667 s at 90 Hz. Current benchmarks deliberately measure existing contracts; they do not retune those health semantics. Any saved-world migration needs an explicit versioned timebase policy.

## Status

The original measured baseline remains [the 60 Hz Windows run](../../reports/performance/2026-10-09-baseline.md). **72/90 Hz workload measurements and Quest hardware validation are pending.** Candidate option parsing can be checked without claiming performance or changing the project default.
