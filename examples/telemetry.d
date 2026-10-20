/// Run: dub run :example   (with AUDP_ECM_LIB_DIR set, see README)
module telemetry;

import std.stdio : writeln, writefln;
import audp_ecm;

void main() @safe
{
    writefln("AUDP-ECM %s (ABI %s)", libraryVersion(), abiVersion());

    // 1. Reed–Solomon with errors and erasures
    auto rs = ReedSolomon(31, 23);
    ubyte[23] data = 7;
    auto rx = rs.encode(data[]);
    rx[0] ^= 0xFF;          // unknown error
    rx[10] = 0;             // known-bad symbol
    auto res = rs.decode(rx, [10]);
    writefln("RS(31,23): corrected %s error(s), %s erasure(s), ok=%s",
            res.correctedSymbols, res.erasures, res.data == data[]);

    // 2. Burst-resilient framing
    immutable(ubyte)[] payload = cast(immutable(ubyte)[]) "node=17;soil_moisture=0.42";
    auto codec = BurstCodec(31, 23, BurstCodec.depthFor(31, 23, payload.length, 16));
    auto tx = codec.protect(payload);
    foreach (i; 12 .. 12 + 16)
        tx[i] ^= 0x5A;      // 16-symbol burst
    writefln("burst depth %s (tolerates %s): recovered \"%s\"",
            codec.depth, codec.burstTolerance, cast(const(char)[]) codec.recover(tx));

    try
        rs.decode(new ubyte[30]);
    catch (InputLengthException e)
        writeln("wrong length rejected: ", e.msg);
}
