# Benchmarks

`bench.d` (dub sub-package `:bench`) measures the public `@safe` API as applications use it.

```bash
export AUDP_ECM_LIB_DIR=/path/to/core/target/release    # see docs/building.md
dub run :bench -b release                    # JSON on stdout, table on stderr
dub run :bench -b release -- --quick         # short smoke run
```

## What is measured

| Operation | Input |
|-----------|-------|
| `encode` | `k` random data bytes |
| `decode_clean` | an error-free codeword |
| `decode_t_errors` | exactly `t = (n − k)/2` symbol errors |
| `decode_full_erasures` | `n − k` erased symbols with positions supplied |
| `burst_protect` / `burst_recover_max_burst` | 64-byte payload over RS(31,23), one contiguous burst of `depth·t` symbols |

Codes: RS(16,12) … RS(255,223), with seeded inputs (`SEED = 20261020`). These are the
same operations and seed as the Python suite, so results are directly comparable.

## Method

- Warm-up, then 7 rounds (3 with `--quick`). Each round runs a batch sized to about
  50 ms, timed with `MonoTime`.
- Reported per operation: median, min, `spread` (max ÷ min), throughput, and GC bytes
  allocated per call (`GC.allocatedInCurrentThread`). Native memory belongs to the core
  library.
- A run is flagged `noisy` when any spread exceeds 1.5×. Throttled laptops on battery
  produce unreliable numbers, so prefer mains power or CI.

## Reproducible runs in CI

**Actions → Benchmarks → Run workflow**, then choose a release tag. The workflow checks
out that tag and builds `libecm_ffi` from the core commit the release pins. It then runs
the suite with LDC on Linux, Windows and macOS, uploads the JSON results and writes a
summary table.
