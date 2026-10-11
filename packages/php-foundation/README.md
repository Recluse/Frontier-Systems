# PHP foundation

Shared ReactPHP infrastructure helpers for Frontier Systems services.

## Remembering cache failure behavior

`RememberingCache::remember()` returns a promise and coalesces concurrent work for the same key. Cache-read failures reject that promise and release the key so a later request can retry. This applies to both synchronous adapter exceptions and rejected promises.

Cache writes are best effort: a synchronous exception, rejected promise, or `false` result increments `write_failures`, releases the key, and preserves the successful producer value for every coalesced caller. Producer failures continue to reject callers and increment `producer_failures`.

The helper does not add operation deadlines or cancellation to an adapter or producer that never settles. Those remain the responsibility of the service boundary.
