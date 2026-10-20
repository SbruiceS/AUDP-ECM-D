/**
 * Raw C ABI of AUDP-ECM (`ecm_ffi.h`, ABI version 2).
 *
 * Low-level and `@system`: prefer the safe API in `audp_ecm`.
 *
 * Copyright: © 2026 Sbruice Singh / ASPF
 * License: Proprietary — ASPF Proprietary Software License (see LICENSE). All rights reserved.
 */
module audp_ecm.c;

// Plain constants live outside the `@system` block so `@safe` code can read them.
enum uint ECM_ABI_VERSION = 2;
enum size_t ECM_MAX_DEPTH = 4096;

enum : int
{
    ECM_OK = 0,
    ECM_ERR_INVALID_CONFIG = -1,
    ECM_ERR_INVALID_LENGTH = -2,
    ECM_ERR_DECODE_FAILED = -3,
    ECM_ERR_NULL_POINTER = -4,
    ECM_ERR_INVALID_ERASURE = -5,
    ECM_ERR_INTERNAL = -6,
    ECM_ERR_INVALID_HANDLE = -7,
}

/// Opaque Reed–Solomon handle.
struct RsHandle;

extern (C) nothrow @nogc @system:

uint ecm_abi_version();
const(char)* ecm_version();
const(char)* ecm_strerror(int code);

RsHandle* ecm_rs_create(size_t n, size_t k);
void ecm_rs_free(RsHandle* h);
size_t ecm_rs_n(const(RsHandle)* h);
size_t ecm_rs_k(const(RsHandle)* h);

int ecm_rs_encode(const(RsHandle)* h, const(ubyte)* data, size_t data_len,
        ubyte* out_, size_t out_len);

int ecm_rs_decode(const(RsHandle)* h, const(ubyte)* received, size_t received_len,
        const(size_t)* erasures, size_t num_erasures,
        ubyte* out_, size_t out_len,
        size_t* corrected_symbols, int* verified);

size_t ecm_burst_capacity(const(RsHandle)* h, size_t depth);
size_t ecm_burst_encoded_len(const(RsHandle)* h, size_t depth);

int ecm_burst_protect(const(RsHandle)* h, const(ubyte)* data, size_t data_len,
        size_t depth, ubyte* out_, size_t out_len, size_t* written);

int ecm_burst_recover(const(RsHandle)* h, const(ubyte)* received, size_t received_len,
        size_t depth, const(size_t)* erasures, size_t num_erasures,
        ubyte* out_, size_t out_len, size_t* written);

ubyte ecm_gf256_mul(ubyte a, ubyte b);
ubyte ecm_gf256_inv(ubyte a);
ubyte ecm_gf_mul(ubyte a, ubyte b);
ubyte ecm_gf_inv(ubyte a);
ushort ecm_crc16(const(ubyte)* data, size_t len);
int ecm_crc16_checked(const(ubyte)* data, size_t len, ushort* out_);
