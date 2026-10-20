# audp-ecm (D)

[![CI](https://github.com/SbruiceS/AUDP-ECM-D/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/SbruiceS/AUDP-ECM-D/actions/workflows/ci.yml)
[![Release](https://github.com/SbruiceS/AUDP-ECM-D/actions/workflows/release.yml/badge.svg)](https://github.com/SbruiceS/AUDP-ECM-D/actions/workflows/release.yml)
[![D](https://img.shields.io/badge/D-DMD%20%7C%20LDC-B03931)](docs/building.md)
[![Platforms](https://img.shields.io/badge/platforms-linux%20%7C%20windows%20%7C%20macOS-informational)](docs/building.md)
[![API](https://img.shields.io/badge/API-%40safe-success)](docs/security.md)
[![License](https://img.shields.io/badge/license-Apache--2.0%20OR%20MIT-blue)](#licence)
[![Website](https://img.shields.io/badge/website-AUDP--ECM-0b7285)](https://sbruices.github.io/AUDP-ECM-Website/)

D bindings for **AUDP-ECM**, the AUDP Error Correction Mathematics Engine.
They provide Reed–Solomon over GF(256), CRC-16/CCITT-FALSE, and a burst-resilient
pipeline that interleaves across codewords. The bindings sit on top of the hardened `ecm-ffi` C ABI (v2).

> **Not cryptography.** CRC and Reed–Solomon correct channel noise; they do
> not authenticate data.

## Documentation

| | |
|---|---|
| [docs/api.md](docs/api.md) | API reference |
| [docs/building.md](docs/building.md) | Toolchains, linking per platform, CI |
| [docs/security.md](docs/security.md) | Safety design and guarantees |
| [docs/releasing.md](docs/releasing.md) | CD pipeline, dub registry, release verification |

## Requirements

- A D compiler (DMD ≥ 2.105 or LDC ≥ 1.35) and `dub`
- `libecm_ffi`, built from the core repository `SbruiceS/AUDP-ECM` (private):

```bash
git clone https://github.com/SbruiceS/AUDP-ECM && cd AUDP-ECM
cargo build -p ecm-ffi --release
export AUDP_ECM_LIB_DIR=$PWD/target/release     # Windows: set AUDP_ECM_LIB_DIR=...\target\release
```

Linux links `libecm_ffi.a` statically. macOS links `libecm_ffi`. Windows links the
import library `ecm_ffi.dll.lib`, so `ecm_ffi.dll` must be on `PATH` at run time.

## Use

```d
import audp_ecm;

auto rs = ReedSolomon(31, 23);                  // RAII, non-copyable
auto cw = rs.encode(data);                      // data.length == 23
auto res = rs.decode(received, [3, 17]);        // with erasures
// res.data, res.correctedSymbols

auto codec = BurstCodec(31, 23, BurstCodec.depthFor(31, 23, payload.length, 16));
auto tx = codec.protect(payload);
auto back = codec.recover(tx);                  // exact payload; bursts ≤ depth·t fixed

ushort c = crc16(bytes);
```

Errors are thrown as `EcmException` subclasses: `ConfigException`,
`InputLengthException`, `ErasureIndexException`, `DecodeException`.

```bash
dub test                 # unittests (needs AUDP_ECM_LIB_DIR)
dub run :example
```

## Security properties

- **`@safe` public API.** Raw pointers exist only inside small `@trusted`
  blocks, always built from D slices (`ptr` and `length` of the same slice),
  and are compiled with `-preview=dip1000` and bounds checks always on.
- **RAII ownership.** `ReedSolomon` and `BurstCodec` disable copying, so a
  handle cannot be double-freed or used after free from `@safe` code. A
  moved-from value throws on use instead of touching a stale pointer.
- **Every return code is checked** and mapped to a typed exception.
  Data is returned only after the core has verified it.
- **ABI check.** The linked library's ABI version is verified before the
  first handle is created.
- **Thread-safe handles.** A handle is immutable after creation, so `const`
  methods may run concurrently (tested).
- **Hardened core.** The core never lets a panic cross the C boundary, checks
  handles and lengths, zeroes outputs on failure, and caps erasure counts and
  depth. It is tested under Miri. See the core's `SECURITY.md`.

See [SECURITY.md](SECURITY.md) to report a vulnerability.

## Licence

Apache-2.0 OR MIT. © 2026 Sbruice Singh / Agriculture Service of Product Farm (ASPF).
