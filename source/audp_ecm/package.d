/**
 * AUDP-ECM for D: Reed–Solomon over GF(256), CRC-16/CCITT-FALSE and a
 * burst-resilient pipeline, over the hardened `ecm-ffi` C ABI.
 *
 * Safety design:
 * $(UL
 *   $(LI The whole public API is `@safe`. Raw pointers are created only inside
 *        small `@trusted` blocks, always from D slices, so pointer and length
 *        can never disagree.)
 *   $(LI Handles are owned by non-copyable RAII structs (`@disable this(this)`),
 *        so double-free and use-after-free are impossible from `@safe` code.
 *        Move with `std.algorithm.mutation.move`.)
 *   $(LI A handle is immutable once created; `const` methods may be called from
 *        several threads concurrently.)
 *   $(LI Every C return code is checked and mapped to a typed exception.
 *        Decoded data is returned only after verification by the core.)
 *   $(LI The library's ABI version is checked before the first handle is made.)
 * )
 *
 * This is error correction for channel noise, not cryptography.
 *
 * Copyright: © 2026 Sbruice Singh / ASPF
 * License: Apache-2.0 OR MIT
 */
module audp_ecm;

import audp_ecm.c;

/// Base class of all AUDP-ECM errors; `code` is the `ECM_*` value.
class EcmException : Exception
{
    immutable int code;

    this(int code, string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow @safe
    {
        super(msg, file, line);
        this.code = code;
    }
}

/// Invalid code parameters (n, k, depth).
class ConfigException : EcmException
{
    this(int code, string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow @safe
    {
        super(code, msg, file, line);
    }
}

/// A length does not match the code, or an input is too large.
class InputLengthException : EcmException
{
    this(int code, string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow @safe
    {
        super(code, msg, file, line);
    }
}

/// An erasure index is out of range.
class ErasureIndexException : EcmException
{
    this(int code, string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow @safe
    {
        super(code, msg, file, line);
    }
}

/// Too many errors, or the result failed verification.
class DecodeException : EcmException
{
    this(int code, string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow @safe
    {
        super(code, msg, file, line);
    }
}

/// Static description of an `ECM_*` code.
string errorString(int code) @trusted nothrow
{
    import std.string : fromStringz;

    // ecm_strerror returns a static NUL-terminated string that is never freed.
    return ecm_strerror(code).fromStringz.idup;
}

private void check(int rc, string file = __FILE__, size_t line = __LINE__) @safe
{
    if (rc == ECM_OK)
        return;
    immutable msg = errorString(rc);
    switch (rc)
    {
    case ECM_ERR_INVALID_CONFIG:
        throw new ConfigException(rc, msg, file, line);
    case ECM_ERR_INVALID_LENGTH:
        throw new InputLengthException(rc, msg, file, line);
    case ECM_ERR_INVALID_ERASURE:
        throw new ErasureIndexException(rc, msg, file, line);
    case ECM_ERR_DECODE_FAILED:
        throw new DecodeException(rc, msg, file, line);
    default:
        throw new EcmException(rc, msg, file, line);
    }
}

/// ABI revision of the linked library.
uint abiVersion() @trusted nothrow @nogc
{
    return ecm_abi_version();
}

/// Version string of the linked core library.
string libraryVersion() @trusted nothrow
{
    import std.string : fromStringz;

    return ecm_version().fromStringz.idup;
}

private void requireAbi() @safe
{
    static bool checked; // thread-local; the check is idempotent
    if (checked)
        return;
    immutable v = abiVersion();
    if (v < ECM_ABI_VERSION)
    {
        import std.conv : text;

        throw new EcmException(ECM_ERR_INTERNAL,
                text("libecm_ffi ABI ", v, " is older than required ", ECM_ABI_VERSION));
    }
    checked = true;
}

/// GF(256) multiply (irreducible 0x11D).
ubyte gfMul(ubyte a, ubyte b) @trusted nothrow @nogc
{
    return ecm_gf256_mul(a, b);
}

/// GF(256) inverse; throws for 0.
ubyte gfInv(ubyte a) @safe
{
    if (a == 0)
        throw new ConfigException(ECM_ERR_INVALID_CONFIG, "0 has no inverse in GF(256)");
    return (() @trusted => ecm_gf256_inv(a))();
}

/// CRC-16/CCITT-FALSE (detection only, not authentication).
ushort crc16(scope const(ubyte)[] data) @trusted
{
    ushort c;
    // data.ptr/data.length come from one slice, so they always agree.
    check(ecm_crc16_checked(data.ptr, data.length, &c));
    return c;
}

/// Result of a successful Reed–Solomon decode.
struct DecodeResult
{
    /// Recovered data (k bytes).
    ubyte[] data;
    /// Unknown symbol errors corrected.
    size_t correctedSymbols;
    /// Erasures supplied.
    size_t erasures;
}

/**
 * Systematic RS(n, k) over GF(256). Corrects e errors and s erasures when
 * 2e + s ≤ n − k. Non-copyable; frees its handle on destruction.
 */
struct ReedSolomon
{
    private RsHandle* handle;

    @disable this();
    @disable this(this);

    /// Throws `ConfigException` unless 0 < k < n ≤ 255.
    this(size_t n, size_t k) @trusted
    {
        requireAbi();
        handle = ecm_rs_create(n, k);
        if (handle is null)
        {
            import std.conv : text;

            throw new ConfigException(ECM_ERR_INVALID_CONFIG,
                    text("invalid RS(", n, ", ", k, "): need 0 < k < n <= 255"));
        }
    }

    ~this() @trusted nothrow @nogc
    {
        if (handle !is null)
        {
            ecm_rs_free(handle);
            handle = null;
        }
    }

    /// True unless this value was moved from.
    bool isValid() const @safe nothrow @nogc
    {
        return handle !is null;
    }

    private const(RsHandle)* live() const @safe
    {
        if (handle is null)
            throw new EcmException(ECM_ERR_INVALID_HANDLE, "use of a moved-from ReedSolomon");
        return handle;
    }

    size_t n() const @trusted
    {
        return ecm_rs_n(live());
    }

    size_t k() const @trusted
    {
        return ecm_rs_k(live());
    }

    /// Unknown-error capability (n − k) / 2.
    size_t t() const @safe
    {
        return (n - k) / 2;
    }

    /// Encode exactly k bytes into an n-byte codeword (parity first).
    ubyte[] encode(scope const(ubyte)[] data) const @trusted
    {
        auto h = live();
        auto output = new ubyte[ecm_rs_n(h)];
        check(ecm_rs_encode(h, data.ptr, data.length, output.ptr, output.length));
        return output;
    }

    /// Decode n received bytes; `erasures` are known-bad positions.
    DecodeResult decode(scope const(ubyte)[] received,
            scope const(size_t)[] erasures = null) const @trusted
    {
        auto h = live();
        auto output = new ubyte[ecm_rs_k(h)];
        size_t corrected;
        int verified;
        check(ecm_rs_decode(h, received.ptr, received.length, erasures.ptr,
                erasures.length, output.ptr, output.length, &corrected, &verified));
        if (!verified)
            throw new DecodeException(ECM_ERR_DECODE_FAILED, "decode not verified");
        return DecodeResult(output, corrected, erasures.length);
    }

    /// True if `word` decodes with zero corrections and no erasures.
    bool isCodeword(scope const(ubyte)[] word) const @safe
    {
        try
            return decode(word).correctedSymbols == 0;
        catch (DecodeException)
            return false;
    }
}

/**
 * Burst-resilient codec: len ‖ payload ‖ CRC-16 over `depth` RS(n, k)
 * codewords interleaved across codewords. Any contiguous burst of up to
 * depth·t symbols is corrected and `recover` returns the exact payload.
 */
struct BurstCodec
{
    private ReedSolomon rs;
    private size_t depth_;

    @disable this();
    @disable this(this);

    this(size_t n, size_t k, size_t depth) @safe
    {
        if (depth == 0 || depth > ECM_MAX_DEPTH)
        {
            import std.conv : text;

            throw new ConfigException(ECM_ERR_INVALID_CONFIG,
                    text("depth must be in 1..", ECM_MAX_DEPTH));
        }
        rs = ReedSolomon(n, k);
        depth_ = depth;
    }

    /// Smallest depth that fits `payloadLen` bytes and survives `burstLen` symbols.
    static size_t depthFor(size_t n, size_t k, size_t payloadLen, size_t burstLen) @safe
    {
        auto probe = ReedSolomon(n, k);
        immutable t = probe.t;
        if (t == 0)
            throw new ConfigException(ECM_ERR_INVALID_CONFIG, "code has t = 0");
        size_t d = (burstLen + t - 1) / t;
        if (d == 0)
            d = 1;
        while (d <= ECM_MAX_DEPTH && (() @trusted => ecm_burst_capacity(probe.handle, d))() < payloadLen)
            ++d;
        if (d > ECM_MAX_DEPTH)
            throw new InputLengthException(ECM_ERR_INVALID_LENGTH, "no allowed depth fits");
        return d;
    }

    size_t depth() const @safe nothrow @nogc
    {
        return depth_;
    }

    /// Maximum payload bytes.
    size_t capacity() const @trusted
    {
        return ecm_burst_capacity(rs.live(), depth_);
    }

    /// Transmitted length n·depth.
    size_t encodedLength() const @trusted
    {
        return ecm_burst_encoded_len(rs.live(), depth_);
    }

    /// Longest contiguous burst guaranteed correctable.
    size_t burstTolerance() const @safe
    {
        return depth_ * rs.t;
    }

    ubyte[] protect(scope const(ubyte)[] payload) const @trusted
    {
        auto h = rs.live();
        auto output = new ubyte[ecm_burst_encoded_len(h, depth_)];
        size_t written;
        check(ecm_burst_protect(h, payload.ptr, payload.length, depth_,
                output.ptr, output.length, &written));
        return output[0 .. written];
    }

    /// `erasures` index the transmitted stream.
    ubyte[] recover(scope const(ubyte)[] received, scope const(size_t)[] erasures = null) const @trusted
    {
        auto h = rs.live();
        auto output = new ubyte[ecm_burst_capacity(h, depth_)];
        size_t written;
        check(ecm_burst_recover(h, received.ptr, received.length, depth_,
                erasures.ptr, erasures.length, output.ptr, output.length, &written));
        return output[0 .. written];
    }
}

// ---------------------------------------------------------------------------
// Tests (run with `dub test`; require libecm_ffi, see README)
// ---------------------------------------------------------------------------

@safe unittest // versions
{
    assert(abiVersion() >= 2);
    assert(libraryVersion().length > 0);
    assert(errorString(ECM_ERR_DECODE_FAILED).length > 0);
}

@safe unittest // GF(256) and CRC known answers
{
    assert(gfMul(0x53, 0xCA) == 0x8F);
    assert(gfMul(0xFF, 0xFF) == 0xE2);
    foreach (int i; 1 .. 256)
    {
        immutable a = cast(ubyte) i;
        assert(gfMul(a, gfInv(a)) == 1);
    }
    import std.exception : assertThrown;

    assertThrown!ConfigException(gfInv(0));
    immutable(ubyte)[] msg = cast(immutable(ubyte)[]) "123456789";
    assert(crc16(msg) == 0x29B1);
    assert(crc16(null) == 0xFFFF);
}

@safe unittest // RS(7,3) known codeword and errors + erasures to full budget
{
    auto rs73 = ReedSolomon(7, 3);
    assert(rs73.encode([1, 2, 3]) == [0x17, 0x3A, 0x51, 0x52, 1, 2, 3]);

    auto rs = ReedSolomon(31, 23);
    assert(rs.n == 31 && rs.k == 23 && rs.t == 4);
    ubyte[23] data;
    foreach (i, ref b; data)
        b = cast(ubyte)(i * 37 + 5);
    auto cw = rs.encode(data[]);
    assert(rs.isCodeword(cw));

    foreach (s; 0 .. 9)
        foreach (e; 0 .. (8 - s) / 2 + 1)
        {
            auto rx = cw.dup;
            size_t[] eras;
            foreach (p; 31 - s .. 31)
            {
                rx[p] ^= 0x33;
                eras ~= p;
            }
            foreach (i; 0 .. e)
                rx[2 * i] ^= 0x5C;
            auto res = rs.decode(rx, eras);
            assert(res.data == data[]);
            assert(res.correctedSymbols == e);
        }
}

@safe unittest // misuse is reported, never undefined
{
    import std.exception : assertThrown;
    import std.algorithm.mutation : move;

    assertThrown!ConfigException(ReedSolomon(10, 10));
    assertThrown!ConfigException(ReedSolomon(300, 10));
    auto rs = ReedSolomon(15, 11);
    assertThrown!InputLengthException(rs.encode(new ubyte[10]));
    assertThrown!InputLengthException(rs.decode(new ubyte[14]));
    assertThrown!ErasureIndexException(rs.decode(new ubyte[15], [15]));
    assertThrown!InputLengthException(rs.decode(new ubyte[15], new size_t[16]));

    auto cw = rs.encode(new ubyte[11]);
    foreach (i; 0 .. 6)
        cw[i] ^= 0xFF;
    try
    {
        auto res = rs.decode(cw);
        assert(res.data != new ubyte[11]); // only a miscorrection could "succeed"
    }
    catch (DecodeException)
    {
    }

    auto moved = move(rs);
    assert(moved.isValid && !rs.isValid);
    assertThrown!EcmException(rs.n);
    assert(moved.n == 15);
}

@safe unittest // burst codec
{
    import std.exception : assertThrown;

    immutable depth = BurstCodec.depthFor(31, 23, 40, 14);
    auto codec = BurstCodec(31, 23, depth);
    assert(codec.burstTolerance >= 14);
    immutable(ubyte)[] payload = cast(immutable(ubyte)[]) "node=17;soil_moisture=0.42;temp=21.7";
    auto tx = codec.protect(payload);
    assert(tx.length == codec.encodedLength);
    foreach (i; 30 .. 30 + codec.burstTolerance)
        tx[i] ^= 0xC3;
    assert(codec.recover(tx) == payload);

    assertThrown!ConfigException(BurstCodec(31, 23, 0));
    assertThrown!InputLengthException(codec.protect(new ubyte[codec.capacity + 1]));
}

@system unittest // concurrent use of one immutable handle
{
    import core.thread : Thread;

    auto rs = new ReedSolomon(64, 48); // heap-allocated: shared by the threads below
    ubyte[48] data;
    foreach (i, ref b; data)
        b = cast(ubyte) i;
    auto cw = rs.encode(data[]);
    shared bool failed;
    const(ubyte)[] expected = data[].dup;

    // Build each worker in its own frame so every thread gets its own `seed`.
    static void delegate() worker(ReedSolomon* rs, const(ubyte)[] cw,
            const(ubyte)[] expected, size_t seed, shared(bool)* failed)
    {
        return {
            foreach (i; 0 .. 200)
            {
                auto rx = cw.dup;
                rx[(seed + i) % 64] ^= 0xA5;
                if (rs.decode(rx).data != expected)
                    *failed = true;
            }
        };
    }

    Thread[] threads;
    foreach (seed; 0 .. 8)
        threads ~= new Thread(worker(rs, cw, expected, seed, &failed)).start();
    foreach (t; threads)
        t.join();
    assert(!failed);
    destroy(*rs);
}
