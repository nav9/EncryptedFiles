#include "encrypted_files.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32) || defined(EF_PLATFORM_WINDOWS)
  #include <io.h>
  #include <stdio.h>
#else
  #include <unistd.h>
#endif

#include "monocypher.h"

#pragma pack(push, 1)
typedef struct {
  char magic[EF_MAGIC_SIZE];
  uint16_t version;
  uint16_t flags;
  uint32_t chunk_size;
  uint8_t salt[EF_SALT_SIZE];
  uint32_t kdf_mem_blocks;
  uint32_t kdf_passes;
  uint32_t kdf_lanes;
  uint8_t stream_nonce[EF_NONCE_SIZE];
  uint8_t file_blind_tag[EF_BLIND_SIZE];
  uint16_t header_len;
  uint8_t header_mac[EF_MAC_SIZE];
} EfFileHeaderFixed;
#pragma pack(pop)

/* Encrypted header plaintext layout (variable):
 * uint64 plaintext_size
 * uint16 real_name_len + real_name bytes
 * uint16 mime_len + mime bytes
 */

struct EfEncryptCtx {
  FILE *fp;
  crypto_aead_ctx aead;
  uint8_t *buf;
  size_t buf_cap;
  size_t buf_len;
  uint32_t chunk_size;
  uint8_t enc_key[EF_KEY_SIZE];
  int finished;
};

struct EfDecryptCtx {
  FILE *fp;
  crypto_aead_ctx aead;
  uint8_t *cipher_buf;
  uint8_t *plain_buf;
  size_t chunk_size;
  uint64_t remaining_plain;
  int finished;
  int eof;
};

static int write_all(FILE *fp, const void *data, size_t len) {
  const uint8_t *p = (const uint8_t *)data;
  size_t left = len;
  while (left > 0) {
    size_t n = fwrite(p, 1, left, fp);
    if (n == 0) {
      return EF_ERR_IO;
    }
    p += n;
    left -= n;
  }
  return EF_OK;
}

static int read_exact(FILE *fp, void *data, size_t len) {
  uint8_t *p = (uint8_t *)data;
  size_t left = len;
  while (left > 0) {
    size_t n = fread(p, 1, left, fp);
    if (n == 0) {
      return EF_ERR_IO;
    }
    p += n;
    left -= n;
  }
  return EF_OK;
}

static int build_header_plain(
    uint64_t plaintext_size,
    const char *real_name,
    const char *mime_type,
    uint8_t **out, size_t *out_len) {
  size_t name_len = real_name ? strlen(real_name) : 0;
  size_t mime_len = mime_type ? strlen(mime_type) : 0;
  if (name_len > 4096 || mime_len > 256) {
    return EF_ERR_INVALID_ARG;
  }

  size_t total = 8 + 2 + name_len + 2 + mime_len;
  uint8_t *buf = (uint8_t *)malloc(total);
  if (buf == NULL) {
    return EF_ERR_NOMEM;
  }

  size_t o = 0;
  memcpy(buf + o, &plaintext_size, 8);
  o += 8;
  uint16_t nl = (uint16_t)name_len;
  uint16_t ml = (uint16_t)mime_len;
  memcpy(buf + o, &nl, 2);
  o += 2;
  if (name_len) {
    memcpy(buf + o, real_name, name_len);
    o += name_len;
  }
  memcpy(buf + o, &ml, 2);
  o += 2;
  if (mime_len) {
    memcpy(buf + o, mime_type, mime_len);
    o += mime_len;
  }

  *out = buf;
  *out_len = total;
  return EF_OK;
}

static int parse_header_plain(
    const uint8_t *buf, size_t len,
    uint64_t *plaintext_size,
    char *out_real_name, size_t real_name_cap,
    char *out_mime, size_t mime_cap) {
  if (len < 12) {
    return EF_ERR_FORMAT;
  }
  size_t o = 0;
  memcpy(plaintext_size, buf + o, 8);
  o += 8;
  uint16_t nl = 0, ml = 0;
  memcpy(&nl, buf + o, 2);
  o += 2;
  if (o + nl + 2 > len) {
    return EF_ERR_FORMAT;
  }
  if (out_real_name && real_name_cap > 0) {
    size_t copy = nl < real_name_cap - 1 ? nl : real_name_cap - 1;
    memcpy(out_real_name, buf + o, copy);
    out_real_name[copy] = '\0';
  }
  o += nl;
  memcpy(&ml, buf + o, 2);
  o += 2;
  if (o + ml > len) {
    return EF_ERR_FORMAT;
  }
  if (out_mime && mime_cap > 0) {
    size_t copy = ml < mime_cap - 1 ? ml : mime_cap - 1;
    memcpy(out_mime, buf + o, copy);
    out_mime[copy] = '\0';
  }
  return EF_OK;
}

EfEncryptCtx *ef_encrypt_begin(
    const char *output_path,
    const uint8_t enc_key[EF_KEY_SIZE],
    const uint8_t salt[EF_SALT_SIZE],
    const EfKdfParams *params,
    uint32_t chunk_size,
    const char *real_name,
    const char *mime_type,
    uint64_t plaintext_size,
    const uint8_t file_blind_tag[EF_BLIND_SIZE]) {
  if (!output_path || !enc_key || !salt || !file_blind_tag) {
    return NULL;
  }
  if (chunk_size < 4096) {
    chunk_size = EF_DEFAULT_CHUNK;
  }

  EfKdfParams p;
  if (params) {
    p = *params;
  } else {
    p.mem_blocks = EF_ARGON2_MEM_BLOCKS;
    p.passes = EF_ARGON2_PASSES;
    p.lanes = EF_ARGON2_LANES;
  }

  EfEncryptCtx *ctx = (EfEncryptCtx *)calloc(1, sizeof(EfEncryptCtx));
  if (!ctx) {
    return NULL;
  }

  ctx->fp = fopen(output_path, "wb");
  if (!ctx->fp) {
    free(ctx);
    return NULL;
  }

  ctx->chunk_size = chunk_size;
  memcpy(ctx->enc_key, enc_key, EF_KEY_SIZE);
  ctx->buf_cap = chunk_size;
  ctx->buf = (uint8_t *)malloc(ctx->buf_cap);
  if (!ctx->buf) {
    fclose(ctx->fp);
    free(ctx);
    return NULL;
  }

  uint8_t *hdr_plain = NULL;
  size_t hdr_plain_len = 0;
  if (build_header_plain(plaintext_size, real_name, mime_type, &hdr_plain, &hdr_plain_len) != EF_OK) {
    ef_encrypt_abort(ctx);
    return NULL;
  }

  uint8_t stream_nonce[EF_NONCE_SIZE];
  uint8_t header_nonce[EF_NONCE_SIZE];
  if (ef_secure_random(stream_nonce, EF_NONCE_SIZE) != EF_OK ||
      ef_secure_random(header_nonce, EF_NONCE_SIZE) != EF_OK) {
    ef_secure_wipe(hdr_plain, hdr_plain_len);
    free(hdr_plain);
    ef_encrypt_abort(ctx);
    return NULL;
  }

  uint8_t *hdr_cipher = (uint8_t *)malloc(hdr_plain_len);
  uint8_t hdr_mac[EF_MAC_SIZE];
  if (!hdr_cipher) {
    ef_secure_wipe(hdr_plain, hdr_plain_len);
    free(hdr_plain);
    ef_encrypt_abort(ctx);
    return NULL;
  }

  /* Header encrypted with one-shot XChaCha20-Poly1305; AAD = magic||version. */
  uint8_t ad[10];
  memcpy(ad, EF_MAGIC, EF_MAGIC_SIZE);
  uint16_t ver = EF_FORMAT_VERSION;
  memcpy(ad + 8, &ver, 2);

  /* Store header_nonce in unused part: we put stream_nonce in fixed header,
   * and prepend header_nonce before ciphertext. */
  crypto_aead_lock(hdr_cipher, hdr_mac, enc_key, header_nonce, ad, sizeof(ad),
                   hdr_plain, hdr_plain_len);
  ef_secure_wipe(hdr_plain, hdr_plain_len);
  free(hdr_plain);

  EfFileHeaderFixed fixed;
  memset(&fixed, 0, sizeof(fixed));
  memcpy(fixed.magic, EF_MAGIC, EF_MAGIC_SIZE);
  fixed.version = EF_FORMAT_VERSION;
  fixed.flags = 0;
  fixed.chunk_size = chunk_size;
  memcpy(fixed.salt, salt, EF_SALT_SIZE);
  fixed.kdf_mem_blocks = p.mem_blocks;
  fixed.kdf_passes = p.passes;
  fixed.kdf_lanes = p.lanes;
  memcpy(fixed.stream_nonce, stream_nonce, EF_NONCE_SIZE);
  memcpy(fixed.file_blind_tag, file_blind_tag, EF_BLIND_SIZE);
  fixed.header_len = (uint16_t)(EF_NONCE_SIZE + hdr_plain_len);
  memcpy(fixed.header_mac, hdr_mac, EF_MAC_SIZE);

  if (write_all(ctx->fp, &fixed, sizeof(fixed)) != EF_OK ||
      write_all(ctx->fp, header_nonce, EF_NONCE_SIZE) != EF_OK ||
      write_all(ctx->fp, hdr_cipher, hdr_plain_len) != EF_OK) {
    free(hdr_cipher);
    ef_encrypt_abort(ctx);
    return NULL;
  }
  free(hdr_cipher);

  crypto_aead_init_x(&ctx->aead, enc_key, stream_nonce);
  ef_secure_wipe(stream_nonce, sizeof(stream_nonce));
  ef_secure_wipe(header_nonce, sizeof(header_nonce));
  return ctx;
}

static int flush_chunk(EfEncryptCtx *ctx, int final_chunk) {
  (void)final_chunk;
  if (ctx->buf_len == 0) {
    return EF_OK;
  }

  uint8_t *cipher = (uint8_t *)malloc(ctx->buf_len);
  uint8_t mac[EF_MAC_SIZE];
  if (!cipher) {
    return EF_ERR_NOMEM;
  }

  crypto_aead_write(&ctx->aead, cipher, mac, NULL, 0, ctx->buf, ctx->buf_len);
  int rc = write_all(ctx->fp, cipher, ctx->buf_len);
  if (rc == EF_OK) {
    rc = write_all(ctx->fp, mac, EF_MAC_SIZE);
  }
  ef_secure_wipe(ctx->buf, ctx->buf_len);
  ef_secure_wipe(cipher, ctx->buf_len);
  free(cipher);
  ctx->buf_len = 0;
  return rc;
}

int ef_encrypt_update(EfEncryptCtx *ctx, const uint8_t *data, size_t len) {
  if (!ctx || (!data && len > 0) || ctx->finished) {
    return EF_ERR_INVALID_ARG;
  }
  size_t off = 0;
  while (off < len) {
    size_t space = ctx->buf_cap - ctx->buf_len;
    size_t take = (len - off) < space ? (len - off) : space;
    memcpy(ctx->buf + ctx->buf_len, data + off, take);
    ctx->buf_len += take;
    off += take;
    if (ctx->buf_len == ctx->buf_cap) {
      int rc = flush_chunk(ctx, 0);
      if (rc != EF_OK) {
        return rc;
      }
    }
  }
  return EF_OK;
}

int ef_encrypt_finish(EfEncryptCtx *ctx) {
  if (!ctx || ctx->finished) {
    return EF_ERR_INVALID_ARG;
  }
  int rc = flush_chunk(ctx, 1);
  if (rc != EF_OK) {
    return rc;
  }
  if (fflush(ctx->fp) != 0) {
    return EF_ERR_IO;
  }
  ctx->finished = 1;
  crypto_wipe(&ctx->aead, sizeof(ctx->aead));
  ef_secure_wipe(ctx->enc_key, sizeof(ctx->enc_key));
  fclose(ctx->fp);
  ctx->fp = NULL;
  free(ctx->buf);
  ctx->buf = NULL;
  free(ctx);
  return EF_OK;
}

void ef_encrypt_abort(EfEncryptCtx *ctx) {
  if (!ctx) {
    return;
  }
  if (ctx->fp) {
    fclose(ctx->fp);
  }
  if (ctx->buf) {
    ef_secure_wipe(ctx->buf, ctx->buf_cap);
    free(ctx->buf);
  }
  crypto_wipe(&ctx->aead, sizeof(ctx->aead));
  ef_secure_wipe(ctx->enc_key, sizeof(ctx->enc_key));
  free(ctx);
}

static int read_and_decrypt_header(
    FILE *fp,
    const uint8_t enc_key[EF_KEY_SIZE],
    EfFileHeaderFixed *fixed,
    uint64_t *plaintext_size,
    char *out_real_name, size_t real_name_cap,
    char *out_mime, size_t mime_cap) {
  if (read_exact(fp, fixed, sizeof(*fixed)) != EF_OK) {
    return EF_ERR_IO;
  }
  if (memcmp(fixed->magic, EF_MAGIC, EF_MAGIC_SIZE) != 0) {
    return EF_ERR_FORMAT;
  }
  if (fixed->version != EF_FORMAT_VERSION) {
    return EF_ERR_UNSUPPORTED;
  }
  if (fixed->header_len < EF_NONCE_SIZE) {
    return EF_ERR_FORMAT;
  }

  size_t cipher_len = fixed->header_len - EF_NONCE_SIZE;
  uint8_t header_nonce[EF_NONCE_SIZE];
  uint8_t *hdr_cipher = (uint8_t *)malloc(cipher_len);
  uint8_t *hdr_plain = (uint8_t *)malloc(cipher_len);
  if (!hdr_cipher || !hdr_plain) {
    free(hdr_cipher);
    free(hdr_plain);
    return EF_ERR_NOMEM;
  }

  int rc = read_exact(fp, header_nonce, EF_NONCE_SIZE);
  if (rc == EF_OK) {
    rc = read_exact(fp, hdr_cipher, cipher_len);
  }
  if (rc != EF_OK) {
    free(hdr_cipher);
    free(hdr_plain);
    return rc;
  }

  uint8_t ad[10];
  memcpy(ad, EF_MAGIC, EF_MAGIC_SIZE);
  uint16_t ver = fixed->version;
  memcpy(ad + 8, &ver, 2);

  if (crypto_aead_unlock(hdr_plain, fixed->header_mac, enc_key, header_nonce,
                         ad, sizeof(ad), hdr_cipher, cipher_len) != 0) {
    ef_secure_wipe(hdr_plain, cipher_len);
    free(hdr_cipher);
    free(hdr_plain);
    return EF_ERR_AUTH;
  }

  rc = parse_header_plain(hdr_plain, cipher_len, plaintext_size,
                          out_real_name, real_name_cap, out_mime, mime_cap);
  ef_secure_wipe(hdr_plain, cipher_len);
  free(hdr_cipher);
  free(hdr_plain);
  ef_secure_wipe(header_nonce, sizeof(header_nonce));
  return rc;
}

EfDecryptCtx *ef_decrypt_begin(
    const char *input_path,
    const uint8_t enc_key[EF_KEY_SIZE],
    uint32_t *out_chunk_size,
    char *out_real_name, size_t real_name_cap,
    char *out_mime, size_t mime_cap,
    uint64_t *out_plaintext_size,
    uint8_t out_file_blind_tag[EF_BLIND_SIZE]) {
  if (!input_path || !enc_key) {
    return NULL;
  }

  FILE *fp = fopen(input_path, "rb");
  if (!fp) {
    return NULL;
  }

  EfFileHeaderFixed fixed;
  uint64_t plain_size = 0;
  int rc = read_and_decrypt_header(fp, enc_key, &fixed, &plain_size,
                                   out_real_name, real_name_cap,
                                   out_mime, mime_cap);
  if (rc != EF_OK) {
    fclose(fp);
    return NULL;
  }

  EfDecryptCtx *ctx = (EfDecryptCtx *)calloc(1, sizeof(EfDecryptCtx));
  if (!ctx) {
    fclose(fp);
    return NULL;
  }

  ctx->fp = fp;
  ctx->chunk_size = fixed.chunk_size;
  ctx->remaining_plain = plain_size;
  ctx->cipher_buf = (uint8_t *)malloc(ctx->chunk_size);
  ctx->plain_buf = (uint8_t *)malloc(ctx->chunk_size);
  if (!ctx->cipher_buf || !ctx->plain_buf) {
    ef_decrypt_abort(ctx);
    return NULL;
  }

  crypto_aead_init_x(&ctx->aead, enc_key, fixed.stream_nonce);
  if (out_chunk_size) {
    *out_chunk_size = fixed.chunk_size;
  }
  if (out_plaintext_size) {
    *out_plaintext_size = plain_size;
  }
  if (out_file_blind_tag) {
    memcpy(out_file_blind_tag, fixed.file_blind_tag, EF_BLIND_SIZE);
  }
  return ctx;
}

int ef_decrypt_update(EfDecryptCtx *ctx, uint8_t *out, size_t out_cap, size_t *out_len) {
  if (!ctx || !out || !out_len || ctx->finished) {
    return EF_ERR_INVALID_ARG;
  }
  *out_len = 0;

  if (ctx->remaining_plain == 0) {
    ctx->eof = 1;
    return EF_OK;
  }

  size_t want = ctx->chunk_size;
  if ((uint64_t)want > ctx->remaining_plain) {
    want = (size_t)ctx->remaining_plain;
  }
  if (want > out_cap) {
    want = out_cap;
  }
  if (want == 0) {
    return EF_OK;
  }

  if (read_exact(ctx->fp, ctx->cipher_buf, want) != EF_OK) {
    return EF_ERR_IO;
  }
  uint8_t mac[EF_MAC_SIZE];
  if (read_exact(ctx->fp, mac, EF_MAC_SIZE) != EF_OK) {
    return EF_ERR_IO;
  }

  if (crypto_aead_read(&ctx->aead, out, mac, NULL, 0, ctx->cipher_buf, want) != 0) {
    ef_secure_wipe(out, want);
    return EF_ERR_AUTH;
  }

  ctx->remaining_plain -= want;
  *out_len = want;
  return EF_OK;
}

int ef_decrypt_finish(EfDecryptCtx *ctx) {
  if (!ctx || ctx->finished) {
    return EF_ERR_INVALID_ARG;
  }
  if (ctx->remaining_plain != 0) {
    return EF_ERR_FORMAT;
  }
  ctx->finished = 1;
  crypto_wipe(&ctx->aead, sizeof(ctx->aead));
  if (ctx->cipher_buf) {
    ef_secure_wipe(ctx->cipher_buf, ctx->chunk_size);
    free(ctx->cipher_buf);
  }
  if (ctx->plain_buf) {
    ef_secure_wipe(ctx->plain_buf, ctx->chunk_size);
    free(ctx->plain_buf);
  }
  if (ctx->fp) {
    fclose(ctx->fp);
  }
  free(ctx);
  return EF_OK;
}

void ef_decrypt_abort(EfDecryptCtx *ctx) {
  if (!ctx) {
    return;
  }
  crypto_wipe(&ctx->aead, sizeof(ctx->aead));
  if (ctx->cipher_buf) {
    ef_secure_wipe(ctx->cipher_buf, ctx->chunk_size);
    free(ctx->cipher_buf);
  }
  if (ctx->plain_buf) {
    ef_secure_wipe(ctx->plain_buf, ctx->chunk_size);
    free(ctx->plain_buf);
  }
  if (ctx->fp) {
    fclose(ctx->fp);
  }
  free(ctx);
}

int ef_probe_file(
    const char *path,
    uint8_t out_salt[EF_SALT_SIZE],
    EfKdfParams *out_params,
    uint32_t *out_chunk_size,
    uint8_t out_file_blind_tag[EF_BLIND_SIZE],
    int *out_is_ef_file) {
  if (!path || !out_is_ef_file) {
    return EF_ERR_INVALID_ARG;
  }
  *out_is_ef_file = 0;
  FILE *fp = fopen(path, "rb");
  if (!fp) {
    return EF_ERR_IO;
  }
  EfFileHeaderFixed fixed;
  size_t n = fread(&fixed, 1, sizeof(fixed), fp);
  fclose(fp);
  if (n < EF_MAGIC_SIZE) {
    return EF_OK;
  }
  if (memcmp(fixed.magic, EF_MAGIC, EF_MAGIC_SIZE) != 0) {
    return EF_OK;
  }
  *out_is_ef_file = 1;
  if (n < sizeof(fixed)) {
    return EF_ERR_FORMAT;
  }
  if (out_salt) {
    memcpy(out_salt, fixed.salt, EF_SALT_SIZE);
  }
  if (out_params) {
    out_params->mem_blocks = fixed.kdf_mem_blocks;
    out_params->passes = fixed.kdf_passes;
    out_params->lanes = fixed.kdf_lanes;
  }
  if (out_chunk_size) {
    *out_chunk_size = fixed.chunk_size;
  }
  if (out_file_blind_tag) {
    memcpy(out_file_blind_tag, fixed.file_blind_tag, EF_BLIND_SIZE);
  }
  return EF_OK;
}

int ef_verify_file_blind(
    const char *path,
    const uint8_t blind_key[EF_KEY_SIZE],
    const uint8_t enc_key[EF_KEY_SIZE]) {
  (void)blind_key;
  /* Decrypt header; success means key is correct. Blind tag already in file. */
  char name[8];
  char mime[8];
  uint64_t sz = 0;
  uint32_t chunk = 0;
  uint8_t tag[EF_BLIND_SIZE];
  EfDecryptCtx *ctx = ef_decrypt_begin(path, enc_key, &chunk, name, sizeof(name),
                                       mime, sizeof(mime), &sz, tag);
  if (!ctx) {
    return EF_ERR_AUTH;
  }
  ef_decrypt_abort(ctx);
  return EF_OK;
}

int ef_encrypt_file(
    const char *input_path,
    const char *output_path,
    const uint8_t enc_key[EF_KEY_SIZE],
    const uint8_t salt[EF_SALT_SIZE],
    const EfKdfParams *params,
    uint32_t chunk_size,
    const char *real_name,
    const char *mime_type,
    const uint8_t file_blind_tag[EF_BLIND_SIZE]) {
  FILE *in = fopen(input_path, "rb");
  if (!in) {
    return EF_ERR_IO;
  }
  if (fseek(in, 0, SEEK_END) != 0) {
    fclose(in);
    return EF_ERR_IO;
  }
  long sz = ftell(in);
  if (sz < 0) {
    fclose(in);
    return EF_ERR_IO;
  }
  rewind(in);

  EfEncryptCtx *ctx = ef_encrypt_begin(output_path, enc_key, salt, params, chunk_size,
                                       real_name, mime_type, (uint64_t)sz, file_blind_tag);
  if (!ctx) {
    fclose(in);
    return EF_ERR_IO;
  }

  uint8_t *buf = (uint8_t *)malloc(chunk_size ? chunk_size : EF_DEFAULT_CHUNK);
  if (!buf) {
    ef_encrypt_abort(ctx);
    fclose(in);
    return EF_ERR_NOMEM;
  }
  size_t cap = chunk_size ? chunk_size : EF_DEFAULT_CHUNK;
  int rc = EF_OK;
  while (rc == EF_OK) {
    size_t n = fread(buf, 1, cap, in);
    if (n > 0) {
      rc = ef_encrypt_update(ctx, buf, n);
    }
    if (n < cap) {
      if (ferror(in)) {
        rc = EF_ERR_IO;
      }
      break;
    }
  }
  ef_secure_wipe(buf, cap);
  free(buf);
  fclose(in);
  if (rc != EF_OK) {
    ef_encrypt_abort(ctx);
    return rc;
  }
  return ef_encrypt_finish(ctx);
}

int ef_decrypt_file(
    const char *input_path,
    const char *output_path,
    const uint8_t enc_key[EF_KEY_SIZE]) {
  char real_name[512];
  char mime[128];
  uint64_t plain_size = 0;
  uint32_t chunk = 0;
  uint8_t tag[EF_BLIND_SIZE];

  EfDecryptCtx *ctx = ef_decrypt_begin(input_path, enc_key, &chunk, real_name,
                                       sizeof(real_name), mime, sizeof(mime),
                                       &plain_size, tag);
  if (!ctx) {
    return EF_ERR_AUTH;
  }

  FILE *out = fopen(output_path, "wb");
  if (!out) {
    ef_decrypt_abort(ctx);
    return EF_ERR_IO;
  }

  uint8_t *buf = (uint8_t *)malloc(chunk);
  if (!buf) {
    fclose(out);
    ef_decrypt_abort(ctx);
    return EF_ERR_NOMEM;
  }

  int rc = EF_OK;
  while (rc == EF_OK) {
    size_t n = 0;
    rc = ef_decrypt_update(ctx, buf, chunk, &n);
    if (rc != EF_OK) {
      break;
    }
    if (n == 0) {
      break;
    }
    if (fwrite(buf, 1, n, out) != n) {
      rc = EF_ERR_IO;
      break;
    }
    ef_secure_wipe(buf, n);
  }

  free(buf);
  fclose(out);
  if (rc != EF_OK) {
    ef_decrypt_abort(ctx);
    remove(output_path);
    return rc;
  }
  return ef_decrypt_finish(ctx);
}

int ef_secure_delete(const char *path) {
  if (!path) {
    return EF_ERR_INVALID_ARG;
  }
  FILE *fp = fopen(path, "rb+");
  if (!fp) {
    /* Already gone. */
    return remove(path) == 0 ? EF_OK : EF_ERR_IO;
  }
  if (fseek(fp, 0, SEEK_END) != 0) {
    fclose(fp);
    return EF_ERR_IO;
  }
  long sz = ftell(fp);
  if (sz < 0) {
    fclose(fp);
    return EF_ERR_IO;
  }
  rewind(fp);

  /* Single-pass random overwrite is enough for already-encrypted ciphertext. */
  uint8_t block[4096];
  long left = sz;
  while (left > 0) {
    size_t n = left > (long)sizeof(block) ? sizeof(block) : (size_t)left;
    if (ef_secure_random(block, n) != EF_OK) {
      memset(block, 0, n);
    }
    if (fwrite(block, 1, n, fp) != n) {
      fclose(fp);
      return EF_ERR_IO;
    }
    left -= (long)n;
  }
  fflush(fp);
#if defined(_WIN32)
  _commit(_fileno(fp));
#else
  fsync(fileno(fp));
#endif
  fclose(fp);
  return remove(path) == 0 ? EF_OK : EF_ERR_IO;
}
