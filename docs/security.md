# Security model

## Scope

Error correction protects against channel noise, not attackers; use a MAC/AEAD
for integrity. In scope: memory-safety issues reachable from `@safe` code,
crashes, unchecked error codes, incorrect results and resource exhaustion.

## Design

| Property | Mechanism |
|----------|-----------|
| Memory safety | public API is `@safe`; native pointers are formed only in small `@trusted` blocks, always from a single D slice (`ptr` and `length` of the same slice) |
| Scope safety | compiled with `-preview=dip1000`; slices are `scope` parameters |
| Bounds | `requireBoundsCheck`: never disabled, even in release builds |
| Ownership | non-copyable RAII handles; no double free or use-after-free from `@safe` code; moved-from values throw instead of dereferencing |
| Error handling | every native return code checked and mapped to a typed exception |
| Compatibility | native ABI version verified before the first handle is created |
| Concurrency | handles are immutable after creation; `const` methods are thread-safe (tested with 8 threads) |
| Native library | catches panics at the boundary, validates every pointer/length, rejects stale handles, zeroes outputs on failure, caps erasure counts and depth |

## Supply chain

- No dub dependencies.
- CI uses least-privilege permissions; checkout never persists credentials.
- Release archives carry SHA-256 checksums and signed build-provenance attestations.

## Reporting

Use GitHub private vulnerability reporting (**Security → Report a vulnerability**)
or email **sbruicesingh@haclon.in**. Please do not open a public issue.
