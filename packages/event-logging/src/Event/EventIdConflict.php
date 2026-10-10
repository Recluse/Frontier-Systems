<?php

declare(strict_types=1);

namespace Frontier\EventLogging\Event;

/** Retained identity cannot be reused for different event content. */
final class EventIdConflict extends \RuntimeException
{
}
