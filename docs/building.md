# Building and linking

## Toolchain

- DMD ≥ 2.105 or LDC ≥ 1.35, and `dub`
- The native library `libecm_ffi` (C ABI v2), built from the AUDP-ECM core
  (private repository; request access from the maintainer)

```bash
cargo build -p ecm-ffi --release          # inside the core checkout
export AUDP_ECM_LIB_DIR=/path/to/core/target/release
```

## How `dub.json` links

| Platform | Linked artifact | Run-time requirement |
|----------|-----------------|----------------------|
| Linux | `libecm_ffi.a` (static) + `pthread`, `dl`, `m` | none |
| macOS | `libecm_ffi.dylib` with an rpath to `$AUDP_ECM_LIB_DIR` | library stays at that path (or set `DYLD_LIBRARY_PATH`) |
| Windows | import library `ecm_ffi.dll.lib` | `ecm_ffi.dll` on `PATH` |

## Compiler settings

| Setting | Why |
|---------|-----|
| `-preview=dip1000` | scope checking for slices passed to `@trusted` code |
| `-preview=in` | `in` parameters are `scope const` |
| `requireBoundsCheck` | array bounds checks stay on in release builds |
| `disallowDeprecations` | deprecations fail the build |

## Commands

```bash
dub test                 # unittests
dub run :example         # examples/telemetry.d
dub build -b release     # library
```

## Continuous integration (`.github/workflows/ci.yml`)

Runs on push / pull request to `main`, manually, and as part of every release:

| Matrix | |
|--------|---|
| OS | Linux, Windows, macOS |
| Compiler | latest DMD and LDC (DMD skipped on Apple Silicon) |

Each job checks out the pinned core commit with a read-only, single-repository
deploy key, builds `libecm_ffi`, runs `dub test` and the example.
