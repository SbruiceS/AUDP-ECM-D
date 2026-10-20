# Releasing (CD)

Pipeline: `.github/workflows/release.yml`.

```
tag vX.Y.Z ─▶ validate tag ─▶ full CI matrix (3 OS × DMD/LDC) ─▶ package ─▶ GitHub Release [environment: AUDP-ECM]
```

| Stage | What it does |
|-------|--------------|
| Validate | tag must be `vMAJOR.MINOR.PATCH[-pre]` (dub's version source) |
| Test | reuses `ci.yml` in full against the pinned core |
| Package | `audp-ecm-d-<tag>.tar.gz` (git archive), `ecm_ffi.h`, `SHA256SUMS` |
| GitHub Release | signed build-provenance attestation, release notes; protected `AUDP-ECM` environment (tags `v*` only) |

**Dry run:** *Actions → Release → Run workflow* validates, tests and packages without publishing.

## Cutting a release

```bash
git tag -s v0.2.0 -m "audp-ecm (D) 0.2.0"      # or -a
git push origin v0.2.0
```

## dub registry (one time)

1. Sign in at https://code.dlang.org with GitHub.
2. *My packages → Register new package* → GitHub → `SbruiceS/AUDP-ECM-D`.

The registry then picks up every new `vX.Y.Z` tag automatically. Users add
`"audp-ecm": "~>0.2"` to their `dub.json` (they still need `libecm_ffi`; see
[building.md](building.md)).

## Verifying a release

```bash
sha256sum -c SHA256SUMS
gh attestation verify audp-ecm-d-v0.2.0.tar.gz --repo SbruiceS/AUDP-ECM-D
```
