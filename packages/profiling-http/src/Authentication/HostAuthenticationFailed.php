<?php

declare(strict_types=1);

namespace Frontier\ProfilingHttp\Authentication;

use RuntimeException;

/** Expected denial, with details kept out of HTTP responses. */
final class HostAuthenticationFailed extends RuntimeException
{
}
