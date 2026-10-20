# audp-ecm for D — technical documentation

| Document | Contents |
|----------|----------|
| [api.md](api.md) | Complete API reference |
| [building.md](building.md) | Toolchains, linking on Linux / macOS / Windows, CI |
| [security.md](security.md) | Safety design, guarantees, reporting |
| [releasing.md](releasing.md) | CD pipeline, versioning, dub registry, verifying releases |

## What the package does

| Capability | API |
|------------|-----|
| Reed–Solomon over GF(256): corrects `e` errors and `s` erasures whenever `2e + s ≤ n − k` | `ReedSolomon` |
| Burst-resilient framing: exact payload back, any contiguous burst ≤ `depth · t` symbols corrected | `BurstCodec` |
| CRC-16/CCITT-FALSE (detection) | `crc16` |
| GF(256) arithmetic (irreducible 0x11D) | `gfMul`, `gfInv` |
| Library introspection | `abiVersion`, `libraryVersion`, `errorString` |

Not cryptography: these mechanisms correct channel noise; they do not authenticate data.

## Layers

| Module | Role |
|--------|------|
| `audp_ecm` | public, `@safe` API (use this) |
| `audp_ecm.c` | raw `extern(C)` declarations of the native library's C ABI v2 (`ecm_ffi.h`) |

## Compatibility

| Item | Supported |
|------|-----------|
| Compilers | DMD ≥ 2.105, LDC ≥ 1.35 (CI: latest DMD and LDC) |
| Platforms | Linux x86_64, Windows x64, macOS (LDC) |
| Native library | `libecm_ffi`, C ABI version ≥ 2 (checked at run time) |
