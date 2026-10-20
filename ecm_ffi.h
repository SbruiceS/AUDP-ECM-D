/*
 * AUDP-ECM C ABI (ecm-ffi), ABI version 2.
 *
 * Pure C header for C, D, Python (cffi/ctypes) and other FFI consumers.
 * Link with libecm_ffi (cdylib or staticlib built by `cargo build -p ecm-ffi --release`).
 *
 * Safety contract (see crates/ecm-ffi/src/lib.rs for details):
 *  - All buffers are caller-owned; every (pointer, length) pair must describe
 *    valid memory. NULL is accepted only where documented or when length == 0.
 *  - A handle is immutable after creation and may be shared across threads;
 *    ecm_rs_free must not race with any other call on the same handle.
 *  - No Rust panic crosses this boundary (reported as ECM_ERR_INTERNAL).
 *  - On decode/recover failure the output buffer is zeroed and out-params reset.
 *
 * Copyright (c) 2026 Sbruice Singh / ASPF. Apache-2.0 OR MIT.
 */
#ifndef AUDP_ECM_FFI_H
#define AUDP_ECM_FFI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ECM_ABI_VERSION 2u
#define ECM_MAX_DEPTH 4096u

#define ECM_OK                  0
#define ECM_ERR_INVALID_CONFIG (-1)
#define ECM_ERR_INVALID_LENGTH (-2)
#define ECM_ERR_DECODE_FAILED  (-3)
#define ECM_ERR_NULL_POINTER   (-4)
#define ECM_ERR_INVALID_ERASURE (-5)
#define ECM_ERR_INTERNAL       (-6)
#define ECM_ERR_INVALID_HANDLE (-7)

/* Opaque Reed–Solomon handle. */
typedef struct RsHandle RsHandle;

/* ---- versioning ------------------------------------------------------- */
uint32_t    ecm_abi_version(void);          /* == ECM_ABI_VERSION for this header */
const char* ecm_version(void);              /* static, NUL-terminated; never free */
const char* ecm_strerror(int code);         /* static, NUL-terminated; never free */

/* ---- Reed–Solomon over GF(256), 0 < k < n <= 255 ---------------------- */
RsHandle* ecm_rs_create(size_t n, size_t k);  /* NULL on invalid (n, k) */
void      ecm_rs_free(RsHandle* h);           /* NULL ignored */
size_t    ecm_rs_n(const RsHandle* h);        /* 0 for NULL/invalid handle */
size_t    ecm_rs_k(const RsHandle* h);

/* data_len == k, out_len >= n. Returns ECM_OK or ECM_ERR_*. */
int ecm_rs_encode(const RsHandle* h, const unsigned char* data, size_t data_len,
                  unsigned char* out, size_t out_len);

/* received_len == n, out_len >= k, num_erasures <= n (erasures may be NULL iff 0).
 * Unique recovery when 2*errors + erasures <= n - k. corrected_symbols and
 * verified may be NULL. */
int ecm_rs_decode(const RsHandle* h, const unsigned char* received, size_t received_len,
                  const size_t* erasures, size_t num_erasures,
                  unsigned char* out, size_t out_len,
                  size_t* corrected_symbols, int* verified);

/* ---- burst pipeline: len||payload||CRC over `depth` interleaved codewords */
size_t ecm_burst_capacity(const RsHandle* h, size_t depth);     /* max payload bytes; 0 if invalid */
size_t ecm_burst_encoded_len(const RsHandle* h, size_t depth);  /* n*depth; 0 if invalid */

int ecm_burst_protect(const RsHandle* h, const unsigned char* data, size_t data_len,
                      size_t depth, unsigned char* out, size_t out_len, size_t* written);

/* erasures index the transmitted stream. *written = exact payload length. */
int ecm_burst_recover(const RsHandle* h, const unsigned char* received, size_t received_len,
                      size_t depth, const size_t* erasures, size_t num_erasures,
                      unsigned char* out, size_t out_len, size_t* written);

/* ---- GF(256) (irreducible 0x11D) and CRC-16/CCITT-FALSE --------------- */
unsigned char ecm_gf256_mul(unsigned char a, unsigned char b);
unsigned char ecm_gf256_inv(unsigned char a);   /* 0 for a == 0 */
uint8_t       ecm_gf_mul(uint8_t a, uint8_t b); /* alias */
uint8_t       ecm_gf_inv(uint8_t a);            /* alias */
uint16_t      ecm_crc16(const uint8_t* data, size_t len);   /* 0 for (NULL, len > 0) */
int           ecm_crc16_checked(const uint8_t* data, size_t len, uint16_t* out);

#ifdef __cplusplus
}
#endif

#endif /* AUDP_ECM_FFI_H */
