<?php

declare(strict_types=1);

namespace Frontier\Profiling\Validation;

use InvalidArgumentException;
use stdClass;

/** Small record checks shared by the profiling transport contracts. */
final class RecordGuard
{
    public const MAX_EXACT_INTEGER = 9_007_199_254_740_990;

    /** @param list<string> $fields */
    public static function object(mixed $value, array $fields): stdClass
    {
        if (!$value instanceof stdClass) {
            throw new InvalidArgumentException('Expected a JSON record object.');
        }
        $keys = array_keys(get_object_vars($value));
        if (array_diff($fields, $keys) !== [] || array_diff($keys, $fields) !== []) {
            throw new InvalidArgumentException('Record fields do not match the versioned contract.');
        }

        return $value;
    }

    /** @return list<mixed> */
    public static function items(mixed $value, int $maximum): array
    {
        if (!is_array($value) || !array_is_list($value) || count($value) > $maximum) {
            throw new InvalidArgumentException('Expected a bounded JSON array.');
        }

        return $value;
    }

    public static function integer(mixed $value, int $minimum = 0, int $maximum = self::MAX_EXACT_INTEGER): int
    {
        if (
            (!is_int($value) && !is_float($value)) || !is_finite((float) $value)
            || floor((float) $value) !== (float) $value || $value < $minimum || $value > $maximum
        ) {
            throw new InvalidArgumentException('Expected an exact integer within the contract bounds.');
        }

        return (int) $value;
    }

    public static function identifier(mixed $value, int $maximumBytes = 128): string
    {
        if (!is_string($value) || trim($value) === '' || strlen($value) > $maximumBytes) {
            throw new InvalidArgumentException('Expected a bounded non-empty identifier.');
        }

        return $value;
    }

    public static function number(mixed $value): float
    {
        if ((!is_int($value) && !is_float($value)) || !is_finite((float) $value)) {
            throw new InvalidArgumentException('Expected a finite number.');
        }

        return (float) $value;
    }

    public static function counters(mixed $value): void
    {
        if (!$value instanceof stdClass || count(get_object_vars($value)) > 16) {
            throw new InvalidArgumentException('Expected at most sixteen numeric counters.');
        }
        foreach (get_object_vars($value) as $key => $counter) {
            self::identifier((string) $key, 64);
            self::number($counter);
        }
    }
}
