<?php

declare(strict_types=1);

namespace Frontier\ControlPlane\Tests\Unit;

use Frontier\WorldContracts\Commands\CommandEnvelope;
use InvalidArgumentException;
use PHPUnit\Framework\TestCase;

final class CommandEnvelopeTest extends TestCase
{
    public function testIntegerJsonNumbersRoundTripWithoutChangingPayload(): void
    {
        foreach ([0, 42, 9_007_199_254_740_990] as $tick) {
            $record = $this->record();
            $record['expected_tick_number'] = $tick;
            $envelope = CommandEnvelope::fromJson(json_encode($record, JSON_THROW_ON_ERROR));

            self::assertSame($tick, $envelope->expectedTickNumber);
            self::assertSame($record['payload'], $envelope->payload);
            self::assertSame($envelope->toArray(), CommandEnvelope::fromJson($envelope->toJson())->toArray());
        }

        self::assertNull(CommandEnvelope::fromArray($this->record())->expectedTickNumber);
    }

    public function testIntegralFloatEnvelopeFieldsNormalize(): void
    {
        $record = $this->record();
        $record['protocol_version'] = 1.0;
        $record['expected_tick_number'] = 42.0;
        self::assertSame(42, CommandEnvelope::fromArray($record)->expectedTickNumber);
        self::assertSame(42, CommandEnvelope::fromJson(json_encode($record, JSON_THROW_ON_ERROR | JSON_PRESERVE_ZERO_FRACTION))->expectedTickNumber);
    }

    public function testInvalidEnvelopeNumbersAreRejected(): void
    {
        foreach ([-1, 0.5, 9_007_199_254_740_991, PHP_INT_MAX, NAN, INF, -INF, null, true, '1', []] as $value) {
            $record = $this->record();
            $record['expected_tick_number'] = $value;
            $this->assertRejected($record);
        }
        foreach ([null, true, '1', 1.5, 2, NAN, INF, []] as $value) {
            $record = $this->record();
            $record['protocol_version'] = $value;
            $this->assertRejected($record);
        }
    }

    public function testTickLimitMatchesTheSharedSchema(): void
    {
        $schema = json_decode(file_get_contents(dirname(__DIR__, 4) . '/docs/schema/command-intent-v1.schema.json'), true, flags: JSON_THROW_ON_ERROR);
        self::assertSame(CommandEnvelope::MAX_EXPECTED_TICK, $schema['properties']['expected_tick_number']['maximum']);
    }

    /** @param array<string, mixed> $record */
    private function assertRejected(array $record): void
    {
        try {
            CommandEnvelope::fromArray($record);
            self::fail('Invalid envelope number was accepted.');
        } catch (InvalidArgumentException) {
            self::assertTrue(true);
        }
    }

    /** @return array<string, mixed> */
    private function record(): array
    {
        return [
            'protocol_version' => 1,
            'request_id' => 'request-1',
            'world_id' => 'world-1',
            'region_id' => 'region-1',
            'command_type' => 'airlock.action',
            'payload' => ['quantity' => 0.25, 'count' => 2],
        ];
    }
}
