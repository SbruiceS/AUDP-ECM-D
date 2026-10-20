/**
 * Reproducible benchmarks for the audp-ecm D binding.
 *
 * Run:  dub run :bench -b release            (needs AUDP_ECM_LIB_DIR, see README)
 *       dub run :bench -b release -- --quick
 *
 * Method (same as the Python suite): seeded inputs; warm-up; ROUNDS rounds,
 * each calling the operation in a batch sized to ~TARGET_MS; reports median,
 * min and spread (max/min) of per-call time, throughput, and GC heap bytes
 * allocated per call. A run is flagged "noisy" if any spread exceeds 1.5.
 *
 * © 2026 Sbruice Singh / ASPF. All rights reserved.
 */
module bench;

import audp_ecm;
import core.memory : GC;
import core.time : MonoTime, Duration;
import std.algorithm : max, min, sort;
import std.array : array;
import std.conv : to;
import std.format : format;
import std.json;
import std.random : Mt19937, uniform;
import std.stdio : File, stderr, stdout;

enum uint SEED = 20261020;
immutable size_t[2][] CODES = [[16, 12], [32, 24], [64, 48], [128, 96], [255, 223]];

struct Timing { double medianNs, minNs, maxNs; size_t batch, rounds; }

Timing timeOp(void delegate() fn, size_t rounds, double targetMs)
{
    foreach (_; 0 .. 50) fn();
    size_t batch = 1;
    double elapsedMs = 0;
    while (elapsedMs < targetMs && batch < (1 << 22))
    {
        batch *= 2;
        const t0 = MonoTime.currTime;
        foreach (_; 0 .. batch) fn();
        elapsedMs = (MonoTime.currTime - t0).total!"hnsecs" / 1e4;
    }
    double[] perCall;
    foreach (round; 0 .. rounds)
    {
        const t0 = MonoTime.currTime;
        foreach (call; 0 .. batch) fn();
        perCall ~= (MonoTime.currTime - t0).total!"hnsecs" * 100.0 / batch;
    }
    auto s = perCall.dup;
    s.sort();
    return Timing(s[$ / 2], s[0], s[$ - 1], batch, rounds);
}

ulong gcBytesPerCall(void delegate() fn, size_t calls)
{
    const before = GC.allocatedInCurrentThread;
    foreach (_; 0 .. calls) fn();
    return (GC.allocatedInCurrentThread - before) / calls;
}

string osName()
{
    version (Windows) return "windows";
    else version (OSX) return "macos";
    else version (linux) return "linux";
    else return "other";
}

string cpuName()
{
    version (linux)
    {
        import std.algorithm : startsWith;
        import std.string : strip;
        try
            foreach (line; File("/proc/cpuinfo").byLineCopy)
                if (line.startsWith("model name"))
                    return line[line.indexOf(':') + 1 .. $].strip;
        catch (Exception) {}
    }
    return "unknown";
}

private ptrdiff_t indexOf(string s, char c)
{
    foreach (i, ch; s) if (ch == c) return i;
    return -1;
}

void main(string[] args)
{
    import std.algorithm : canFind;
    const quick = args.canFind("--quick");
    const rounds = quick ? 3 : 7;
    const targetMs = quick ? 15.0 : 50.0;
    auto rng = Mt19937(SEED);
    JSONValue[] results;

    void record(string code, size_t n, size_t k, string op, size_t payload, void delegate() fn)
    {
        auto t = timeOp(fn, rounds, targetMs);
        results ~= JSONValue([
            "code": JSONValue(code), "n": JSONValue(n), "k": JSONValue(k), "op": JSONValue(op),
            "payload_bytes": JSONValue(payload), "median_ns": JSONValue(t.medianNs),
            "min_ns": JSONValue(t.minNs), "max_ns": JSONValue(t.maxNs),
            "spread": JSONValue(t.maxNs / t.minNs), "batch": JSONValue(t.batch),
            "rounds": JSONValue(t.rounds), "throughput_mb_s": JSONValue(payload / t.medianNs * 1e3),
            "gc_bytes_per_call": JSONValue(gcBytesPerCall(fn, quick ? 200 : 1000)),
        ]);
    }

    foreach (c; CODES)
    {
        const n = c[0], k = c[1];
        auto rs = new ReedSolomon(n, k);
        const t = rs.t;
        auto data = new ubyte[k];
        foreach (ref b; data) b = cast(ubyte) uniform(0, 256, rng);
        auto cw = rs.encode(data);
        auto err = cw.dup;
        foreach (i; 0 .. t) err[(i * n) / t] ^= 0x5A;
        auto erasWord = cw.dup;
        size_t[] eras;
        foreach (p; 0 .. n - k) { erasWord[p] = 0; eras ~= p; }
        assert(rs.decode(err).data == data && rs.decode(erasWord, eras).data == data);
        const code = format("RS(%s,%s)", n, k);
        record(code, n, k, "encode", k, () { cast(void) rs.encode(data); });
        record(code, n, k, "decode_clean", k, () { cast(void) rs.decode(cw); });
        record(code, n, k, "decode_t_errors", k, () { cast(void) rs.decode(err); });
        record(code, n, k, "decode_full_erasures", k, () { cast(void) rs.decode(erasWord, eras); });
    }

    const depth = BurstCodec.depthFor(31, 23, 64, 16);
    auto codec = new BurstCodec(31, 23, depth);
    auto payload = new ubyte[64];
    foreach (ref b; payload) b = cast(ubyte) uniform(0, 256, rng);
    auto tx = codec.protect(payload);
    foreach (i; 10 .. 10 + codec.burstTolerance) tx[i] ^= 0xC3;
    assert(codec.recover(tx) == payload);
    const bcode = format("BurstCodec(31,23,depth=%s)", depth);
    record(bcode, 31, 23, "burst_protect", 64, () { cast(void) codec.protect(payload); });
    record(bcode, 31, 23, "burst_recover_max_burst", 64, () { cast(void) codec.recover(tx); });

    bool noisy = false;
    foreach (r; results) if (r["spread"].floating > 1.5) noisy = true;
    auto report = JSONValue([
        "suite": JSONValue("audp-ecm d"),
        "library_version": JSONValue(libraryVersion()),
        "abi_version": JSONValue(abiVersion()),
        "compiler": JSONValue(format("%s %s", __VENDOR__, __VERSION__)),
        "os": JSONValue(osName()),
        "cpu": JSONValue(cpuName()),
        "seed": JSONValue(SEED),
        "mode": JSONValue(quick ? "quick" : "full"),
        "noisy": JSONValue(noisy),
        "results": JSONValue(results),
    ]);
    stdout.writeln(report.toPrettyString);

    stderr.writefln("audp-ecm D · core %s · ABI %s · %s %s · %s", libraryVersion(), abiVersion(), __VENDOR__, __VERSION__, osName());
    stderr.writefln("%-26s %-24s %10s %9s %8s %8s", "code", "operation", "median µs", "min µs", "MB/s", "GC B");
    foreach (r; results)
        stderr.writefln("%-26s %-24s %10.2f %9.2f %8.1f %8d", r["code"].str, r["op"].str,
            r["median_ns"].floating / 1e3, r["min_ns"].floating / 1e3, r["throughput_mb_s"].floating,
            r["gc_bytes_per_call"].uinteger);
    if (noisy) stderr.writeln("WARNING: unstable timings (spread > 1.5x): check power/thermal state and rerun");
}
