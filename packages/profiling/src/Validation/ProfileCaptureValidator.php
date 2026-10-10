<?php

declare(strict_types=1);

namespace Frontier\Profiling\Validation;

use Frontier\WorldContracts\World\WorldIdentity;
use InvalidArgumentException;
use stdClass;

/** Validates telemetry shape and frontier consistency, never gameplay authority. */
final class ProfileCaptureValidator
{
    public static function validate(mixed $value): stdClass
    {
        $capture = RecordGuard::object($value, ['schema_version', 'world_id', 'region_id', 'capture_tick_number', 'history', 'report']);
        RecordGuard::integer($capture->schema_version, 1, 1);
        new WorldIdentity(RecordGuard::identifier($capture->world_id), RecordGuard::identifier($capture->region_id));
        $frontier = RecordGuard::integer($capture->capture_tick_number);
        $history = RecordGuard::object($capture->history, ['schema_version', 'capacity', 'retained_samples', 'overwritten_samples', 'samples']);
        RecordGuard::integer($history->schema_version, 1, 1);
        $capacity = RecordGuard::integer($history->capacity, 1, 2048);
        $retained = RecordGuard::integer($history->retained_samples, 0, $capacity);
        RecordGuard::integer($history->overwritten_samples);
        $samples = RecordGuard::items($history->samples, $retained);
        $first = null;
        $last = null;
        $peak = 0;
        $commands = 0;
        $overBudget = 0;
        foreach ($samples as $value) {
            $sample = RecordGuard::object($value, ['schema_version', 'tick_number', 'elapsed_usec', 'command_usec', 'commands_processed', 'queued_commands', 'budget_usec', 'over_budget', 'systems']);
            RecordGuard::integer($sample->schema_version, 1, 1);
            $tick = RecordGuard::integer($sample->tick_number, 0, $frontier);
            if ($last !== null && $tick <= $last) {
                throw new InvalidArgumentException('History ticks must increase within the capture frontier.');
            }
            $first ??= $tick;
            $last = $tick;
            $elapsed = RecordGuard::integer($sample->elapsed_usec);
            RecordGuard::integer($sample->command_usec, 0, $elapsed);
            $commands += RecordGuard::integer($sample->commands_processed, 0, 65536);
            $peak = max($peak, RecordGuard::integer($sample->queued_commands, 0, 1048576));
            $budget = RecordGuard::integer($sample->budget_usec, 1);
            if (!is_bool($sample->over_budget) || $sample->over_budget !== ($elapsed > $budget)) {
                throw new InvalidArgumentException('Sample budget flag does not match its timing.');
            }
            $overBudget += (int) $sample->over_budget;
            $seen = [];
            foreach (RecordGuard::items($sample->systems, 64) as $value) {
                $system = RecordGuard::object($value, ['system_id', 'elapsed_usec', 'counters']);
                $id = RecordGuard::identifier($system->system_id);
                if (isset($seen[$id])) {
                    throw new InvalidArgumentException('A tick cannot observe a system twice.');
                }
                $seen[$id] = true;
                RecordGuard::integer($system->elapsed_usec, 0, $elapsed);
                RecordGuard::counters($system->counters);
            }
        }
        $report = RecordGuard::object($capture->report, ['schema_version', 'sample_count', 'first_tick', 'last_tick', 'tick_timing_usec', 'command_timing_usec', 'over_budget_samples', 'queue_peak', 'commands_processed', 'omitted_system_observations', 'systems']);
        RecordGuard::integer($report->schema_version, 1, 1);
        $count = count($samples);
        if (
            RecordGuard::integer($report->sample_count, 0, 2048) !== $count
            || ($first === null ? $report->first_tick !== null : RecordGuard::integer($report->first_tick) !== $first)
            || ($last === null ? $report->last_tick !== null : RecordGuard::integer($report->last_tick) !== $last)
            || RecordGuard::integer($report->queue_peak) !== $peak
            || RecordGuard::integer($report->commands_processed) !== $commands
            || RecordGuard::integer($report->over_budget_samples) !== $overBudget
        ) {
            throw new InvalidArgumentException('Report window totals do not match its history.');
        }
        self::statistics($report->tick_timing_usec, $count);
        self::statistics($report->command_timing_usec, $count);
        RecordGuard::integer($report->omitted_system_observations, 0, $count * 64);
        $seen = [];
        foreach (RecordGuard::items($report->systems, $count === 0 ? 0 : 64) as $value) {
            $system = RecordGuard::object($value, ['system_id', 'timing_usec', 'last_observed_tick', 'latest_counters']);
            $id = RecordGuard::identifier($system->system_id);
            if (isset($seen[$id])) {
                throw new InvalidArgumentException('System report identities must be unique.');
            }
            $seen[$id] = true;
            RecordGuard::integer($system->last_observed_tick, $first ?? 0, $last ?? 0);
            $stats = RecordGuard::object($system->timing_usec, ['count', 'minimum', 'maximum', 'mean', 'p50', 'p95', 'p99']);
            self::statistics($stats, RecordGuard::integer($stats->count, 1, $count));
            RecordGuard::counters($system->latest_counters);
        }

        return $capture;
    }

    private static function statistics(mixed $value, int $expectedCount): void
    {
        $stats = RecordGuard::object($value, ['count', 'minimum', 'maximum', 'mean', 'p50', 'p95', 'p99']);
        if (RecordGuard::integer($stats->count, 0, 2048) !== $expectedCount) {
            throw new InvalidArgumentException('Timing counts must match the observed window.');
        }
        foreach (['minimum', 'maximum', 'mean', 'p50', 'p95', 'p99'] as $field) {
            if ($expectedCount === 0) {
                if ($stats->{$field} !== null) {
                    throw new InvalidArgumentException('Empty timing statistics must be null.');
                }
            } elseif (RecordGuard::number($stats->{$field}) < 0.0) {
                throw new InvalidArgumentException('Timing statistics must be non-negative.');
            }
        }
        if (
            $expectedCount > 0 && ($stats->minimum > $stats->p50 || $stats->p50 > $stats->p95
            || $stats->p95 > $stats->p99 || $stats->p99 > $stats->maximum
            || $stats->mean < $stats->minimum || $stats->mean > $stats->maximum)
        ) {
            throw new InvalidArgumentException('Timing statistics have inconsistent ranges.');
        }
    }
}
