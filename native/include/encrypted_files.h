#ifndef ENCRYPTED_FILES_H
#define ENCRYPTED_FILES_H

#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
  #ifdef EF_BUILDING_DLL
    #define EF_API __declspec(dllexport)
  #else
    #define EF_API __declspec(dllimport)
  #endif
#else
  #define EF_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Status codes */
#define EF_OK                 0
#define EF_ERR_INVALID_ARG   -1
#define EF_ERR_IO            -2
#define EF_ERR_CRYPTO        -3
#define EF_ERR_NOMEM         -4
#define EF_ERR_NOT_FOUND     -5
#define EF_ERR_ALREADY       -6
#define EF_ERR_AUTH          -7
#define EF_ERR_FORMAT        -8
#define EF_ERR_BUSY          -9
#define EF_ERR_UNSUPPORTED  -10
#define EF_ERR_INTERNAL     -99

#define EF_KEY_SIZE          32
#define EF_SALT_SIZE         16
#define EF_NONCE_SIZE        24
#define EF_MAC_SIZE          16
#define EF_BLIND_SIZE        32
#define EF_MAGIC             "EFENCv01"
#define EF_MAGIC_SIZE        8
#define EF_FORMAT_VERSION    1

/* Default Argon2id tuned for low-RAM phones (~16 MiB). */
#define EF_ARGON2_MEM_BLOCKS 16384  /* 16 MiB (blocks of 1 KiB) */
#define EF_ARGON2_PASSES     2
#define EF_ARGON2_LANES      1

#define EF_DEFAULT_CHUNK     (32 * 1024)

typedef struct {
  uint32_t mem_blocks; /* KiB blocks for Argon2 */
  uint32_t passes;
  uint32_t lanes;
} EfKdfParams;

/* ---------- Secure memory ---------- */
EF_API void ef_secure_wipe(void *ptr, size_t len);
EF_API int  ef_secure_random(uint8_t *out, size_t len);

/* ---------- Key derivation & blind index ---------- */
EF_API int ef_derive_master_key(
    const uint8_t *password, size_t password_len,
    const uint8_t salt[EF_SALT_SIZE],
    const EfKdfParams *params,
    uint8_t out_key[EF_KEY_SIZE]);

EF_API void ef_derive_subkeys(
    const uint8_t master_key[EF_KEY_SIZE],
    uint8_t enc_key[EF_KEY_SIZE],
    uint8_t blind_key[EF_KEY_SIZE]);

EF_API void ef_compute_blind_index(
    const uint8_t blind_key[EF_KEY_SIZE],
    uint8_t out_blind[EF_BLIND_SIZE]);

EF_API void ef_compute_file_blind_tag(
    const uint8_t blind_key[EF_KEY_SIZE],
    const uint8_t file_id[16],
    uint8_t out_tag[EF_BLIND_SIZE]);

/* ---------- Streaming encrypt / decrypt ---------- */
typedef struct EfEncryptCtx EfEncryptCtx;
typedef struct EfDecryptCtx EfDecryptCtx;

EF_API EfEncryptCtx *ef_encrypt_begin(
    const char *output_path,
    const uint8_t enc_key[EF_KEY_SIZE],
    const uint8_t salt[EF_SALT_SIZE],
    const EfKdfParams *params,
    uint32_t chunk_size,
    const char *real_name,
    const char *mime_type,
    uint64_t plaintext_size,
    const uint8_t file_blind_tag[EF_BLIND_SIZE]);

EF_API int ef_encrypt_update(EfEncryptCtx *ctx, const uint8_t *data, size_t len);
EF_API int ef_encrypt_finish(EfEncryptCtx *ctx);
EF_API void ef_encrypt_abort(EfEncryptCtx *ctx);

EF_API EfDecryptCtx *ef_decrypt_begin(
    const char *input_path,
    const uint8_t enc_key[EF_KEY_SIZE],
    uint32_t *out_chunk_size,
    char *out_real_name, size_t real_name_cap,
    char *out_mime, size_t mime_cap,
    uint64_t *out_plaintext_size,
    uint8_t out_file_blind_tag[EF_BLIND_SIZE]);

EF_API int ef_decrypt_update(EfDecryptCtx *ctx, uint8_t *out, size_t out_cap, size_t *out_len);
EF_API int ef_decrypt_finish(EfDecryptCtx *ctx);
EF_API void ef_decrypt_abort(EfDecryptCtx *ctx);

/* Probe header without full decrypt of payload (needs enc_key for header). */
EF_API int ef_probe_file(
    const char *path,
    uint8_t out_salt[EF_SALT_SIZE],
    EfKdfParams *out_params,
    uint32_t *out_chunk_size,
    uint8_t out_file_blind_tag[EF_BLIND_SIZE],
    int *out_is_ef_file);

/* Verify file belongs to password via blind tag (after deriving keys). */
EF_API int ef_verify_file_blind(
    const char *path,
    const uint8_t blind_key[EF_KEY_SIZE],
    const uint8_t enc_key[EF_KEY_SIZE]);

/* One-shot helpers for small buffers (still streamed internally). */
EF_API int ef_encrypt_file(
    const char *input_path,
    const char *output_path,
    const uint8_t enc_key[EF_KEY_SIZE],
    const uint8_t salt[EF_SALT_SIZE],
    const EfKdfParams *params,
    uint32_t chunk_size,
    const char *real_name,
    const char *mime_type,
    const uint8_t file_blind_tag[EF_BLIND_SIZE]);

EF_API int ef_decrypt_file(
    const char *input_path,
    const char *output_path,
    const uint8_t enc_key[EF_KEY_SIZE]);

/* Secure delete: overwrite then unlink. */
EF_API int ef_secure_delete(const char *path);

/* Suggest chunk size (bytes) from available RAM in KiB. */
EF_API uint32_t ef_suggest_chunk_size(uint64_t available_ram_kib);

/* In-memory AEAD seal/open for small metadata blobs.
 * Output layout: nonce(24) || mac(16) || ciphertext.
 * out_cap must be >= 40 + plaintext_len. */
EF_API int ef_aead_seal(
    const uint8_t key[EF_KEY_SIZE],
    const uint8_t *ad, size_t ad_len,
    const uint8_t *plaintext, size_t plaintext_len,
    uint8_t *out, size_t out_cap, size_t *out_len);

EF_API int ef_aead_open(
    const uint8_t key[EF_KEY_SIZE],
    const uint8_t *ad, size_t ad_len,
    const uint8_t *blob, size_t blob_len,
    uint8_t *out, size_t out_cap, size_t *out_len);

/* ---------- Localhost streaming HTTP server ---------- */
typedef struct EfStreamServer EfStreamServer;

EF_API EfStreamServer *ef_stream_server_start(
    const uint8_t enc_key[EF_KEY_SIZE],
    uint32_t chunk_size_override, /* 0 = use file header */
    int *out_port);

EF_API int ef_stream_server_register(
    EfStreamServer *server,
    const char *encrypted_path,
    char *out_token, size_t token_cap,
    char *out_url, size_t url_cap);

EF_API void ef_stream_server_unregister(EfStreamServer *server, const char *token);
EF_API void ef_stream_server_stop(EfStreamServer *server);

/* Wipe key material held by server before stop if needed. */
EF_API void ef_stream_server_clear_keys(EfStreamServer *server);

#ifdef __cplusplus
}
#endif

#endif /* ENCRYPTED_FILES_H */
