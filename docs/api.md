# API reference (`module audp_ecm`)

Everything below is `@safe` unless noted.

## Exceptions

```
EcmException (code: int)          base class, `code` is the native ECM_* value
├── ConfigException               invalid parameters (n, k, depth), gfInv(0)
├── InputLengthException          wrong length, output too small, payload over capacity
├── ErasureIndexException         erasure index out of range
└── DecodeException               too many errors, or verification failed
```

Every native return code is checked; no failure is silent.

## `struct ReedSolomon`

Non-copyable RAII owner of a native handle (`@disable this(this)`). Move with
`std.algorithm.mutation.move`; a moved-from value reports `isValid == false` and
throws `EcmException` on use instead of touching a stale pointer.

| Member | Notes |
|--------|-------|
| `this(size_t n, size_t k)` | `0 < k < n ≤ 255`, else `ConfigException`; verifies the library ABI on first use |
| `n()`, `k()`, `t()` | `t = (n − k) / 2` |
| `ubyte[] encode(const(ubyte)[] data) const` | `data.length == k`; returns `n` bytes (parity first) |
| `DecodeResult decode(const(ubyte)[] received, const(size_t)[] erasures = null) const` | `received.length == n`; `2e + s ≤ n − k` |
| `bool isCodeword(const(ubyte)[] word) const` | |
| `bool isValid() const` | false after being moved from |

`const` methods may be called concurrently from several threads on one instance.

### `struct DecodeResult`

| Field | Meaning |
|-------|---------|
| `ubyte[] data` | the `k` recovered bytes |
| `size_t correctedSymbols` | unknown errors corrected |
| `size_t erasures` | erasures supplied |

## `struct BurstCodec`

`len ‖ payload ‖ CRC-16` over `depth` RS(n, k) codewords interleaved across codewords.

| Member | Notes |
|--------|-------|
| `this(size_t n, size_t k, size_t depth)` | `1 ≤ depth ≤ 4096` |
| `static size_t depthFor(n, k, payloadLen, burstLen)` | smallest depth fitting the payload and the burst |
| `depth()`, `capacity()`, `encodedLength()`, `burstTolerance()` | `encodedLength = n·depth`, `burstTolerance = depth·t` |
| `ubyte[] protect(const(ubyte)[] payload) const` | `payload.length ≤ capacity` |
| `ubyte[] recover(const(ubyte)[] received, const(size_t)[] erasures = null) const` | exact payload; erasures index the transmitted stream |

## Functions

| Function | Notes |
|----------|-------|
| `ubyte gfMul(ubyte a, ubyte b)` | `@trusted nothrow @nogc` |
| `ubyte gfInv(ubyte a)` | `ConfigException` for 0 |
| `ushort crc16(const(ubyte)[] data)` | `crc16("123456789") == 0x29B1` |
| `uint abiVersion()` | native ABI version (≥ 2) |
| `string libraryVersion()` | native library version |
| `string errorString(int code)` | description of an `ECM_*` code |

## Example

```d
import audp_ecm;

auto rs = ReedSolomon(31, 23);
auto cw = rs.encode(new ubyte[23]);
cw[0] ^= 0xFF;
assert(rs.decode(cw).correctedSymbols == 1);

auto codec = BurstCodec(31, 23, BurstCodec.depthFor(31, 23, 26, 16));
auto tx = codec.protect(cast(immutable(ubyte)[]) "node=17;soil_moisture=0.42");
assert(codec.recover(tx) == "node=17;soil_moisture=0.42");
```
