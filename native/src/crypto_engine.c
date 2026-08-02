#include "encrypted_files.h"

#include <stdlib.h>
#include <string.h>

#include "monocypher.h"

static EfKdfParams ef_default_kdf(void) {
  EfKdfParams p;
  p.mem_blocks = EF_ARGON2_MEM_BLOCKS;
  p.passes = EF_ARGON2_PASSES;
  p.lanes = EF_ARGON2_LANES;
  return p;
}

int ef_derive_master_key(
    const uint8_t *password, size_t password_len,
    const uint8_t salt[EF_SALT_SIZE],
    const EfKdfParams *params,
    uint8_t out_key[EF_KEY_SIZE]) {
  if (password == NULL || password_len == 0 || salt == NULL || out_key == NULL) {
    return EF_ERR_INVALID_ARG;
  }

  EfKdfParams p = params ? *params : ef_default_kdf();
  if (p.mem_blocks < 8 || p.passes < 1 || p.lanes < 1) {
    return EF_ERR_INVALID_ARG;
  }

  /* Cap memory for very low-RAM devices: min 8 MiB, max 64 MiB. */
  if (p.mem_blocks < 8192) {
    p.mem_blocks = 8192;
  }
  if (p.mem_blocks > 65536) {
    p.mem_blocks = 65536;
  }

  size_t work_bytes = (size_t)p.mem_blocks * 1024u;
  void *work = malloc(work_bytes);
  if (work == NULL) {
    /* Fallback: try half memory. */
    p.mem_blocks /= 2;
    if (p.mem_blocks < 8192) {
      p.mem_blocks = 8192;
    }
    work_bytes = (size_t)p.mem_blocks * 1024u;
    work = malloc(work_bytes);
    if (work == NULL) {
      return EF_ERR_NOMEM;
    }
  }

  crypto_argon2_config cfg;
  cfg.algorithm = CRYPTO_ARGON2_ID;
  cfg.nb_blocks = p.mem_blocks;
  cfg.nb_passes = p.passes;
  cfg.nb_lanes = p.lanes;

  crypto_argon2_inputs inputs;
  inputs.pass = password;
  inputs.pass_size = (uint32_t)password_len;
  inputs.salt = salt;
  inputs.salt_size = EF_SALT_SIZE;

  crypto_argon2(out_key, EF_KEY_SIZE, work, cfg, inputs, crypto_argon2_no_extras);
  ef_secure_wipe(work, work_bytes);
  free(work);
  return EF_OK;
}

void ef_derive_subkeys(
    const uint8_t master_key[EF_KEY_SIZE],
    uint8_t enc_key[EF_KEY_SIZE],
    uint8_t blind_key[EF_KEY_SIZE]) {
  static const uint8_t enc_info[] = "EncryptedFiles/v1/enc";
  static const uint8_t blind_info[] = "EncryptedFiles/v1/blind";

  crypto_blake2b_keyed(enc_key, EF_KEY_SIZE,
                       master_key, EF_KEY_SIZE,
                       enc_info, sizeof(enc_info) - 1);
  crypto_blake2b_keyed(blind_key, EF_KEY_SIZE,
                       master_key, EF_KEY_SIZE,
                       blind_info, sizeof(blind_info) - 1);
}

void ef_compute_blind_index(
    const uint8_t blind_key[EF_KEY_SIZE],
    uint8_t out_blind[EF_BLIND_SIZE]) {
  static const uint8_t msg[] = "EncryptedFiles/v1/vault";
  crypto_blake2b_keyed(out_blind, EF_BLIND_SIZE,
                       blind_key, EF_KEY_SIZE,
                       msg, sizeof(msg) - 1);
}

void ef_compute_file_blind_tag(
    const uint8_t blind_key[EF_KEY_SIZE],
    const uint8_t file_id[16],
    uint8_t out_tag[EF_BLIND_SIZE]) {
  crypto_blake2b_keyed(out_tag, EF_BLIND_SIZE,
                       blind_key, EF_KEY_SIZE,
                       file_id, 16);
}

uint32_t ef_suggest_chunk_size(uint64_t available_ram_kib) {
  /* Keep working set small: ~0.5% of RAM, clamped to allowed sizes. */
  static const uint32_t choices[] = {
    8 * 1024, 16 * 1024, 32 * 1024, 64 * 1024,
    128 * 1024, 256 * 1024, 512 * 1024, 1024 * 1024
  };
  const size_t n = sizeof(choices) / sizeof(choices[0]);

  if (available_ram_kib == 0) {
    return EF_DEFAULT_CHUNK;
  }

  uint64_t suggest = (available_ram_kib * 1024ull) / 200ull; /* 0.5% */
  if (suggest < choices[0]) {
    return choices[0];
  }

  uint32_t best = choices[0];
  for (size_t i = 0; i < n; i++) {
    if ((uint64_t)choices[i] <= suggest) {
      best = choices[i];
    }
  }

  /* Very low RAM (< 768 MiB): force <= 32 KiB. */
  if (available_ram_kib < 768ull * 1024ull && best > 32u * 1024u) {
    best = 32u * 1024u;
  }
  return best;
}

int ef_aead_seal(
    const uint8_t key[EF_KEY_SIZE],
    const uint8_t *ad, size_t ad_len,
    const uint8_t *plaintext, size_t plaintext_len,
    uint8_t *out, size_t out_cap, size_t *out_len) {
  if (!key || (!plaintext && plaintext_len > 0) || !out || !out_len) {
    return EF_ERR_INVALID_ARG;
  }
  if (out_cap < EF_NONCE_SIZE + EF_MAC_SIZE + plaintext_len) {
    return EF_ERR_INVALID_ARG;
  }
  uint8_t nonce[EF_NONCE_SIZE];
  if (ef_secure_random(nonce, EF_NONCE_SIZE) != EF_OK) {
    return EF_ERR_INTERNAL;
  }
  memcpy(out, nonce, EF_NONCE_SIZE);
  crypto_aead_lock(out + EF_NONCE_SIZE + EF_MAC_SIZE,
                   out + EF_NONCE_SIZE,
                   key, nonce, ad, ad_len, plaintext, plaintext_len);
  ef_secure_wipe(nonce, sizeof(nonce));
  *out_len = EF_NONCE_SIZE + EF_MAC_SIZE + plaintext_len;
  return EF_OK;
}

int ef_aead_open(
    const uint8_t key[EF_KEY_SIZE],
    const uint8_t *ad, size_t ad_len,
    const uint8_t *blob, size_t blob_len,
    uint8_t *out, size_t out_cap, size_t *out_len) {
  if (!key || !blob || !out || !out_len) {
    return EF_ERR_INVALID_ARG;
  }
  if (blob_len < EF_NONCE_SIZE + EF_MAC_SIZE) {
    return EF_ERR_FORMAT;
  }
  size_t ct_len = blob_len - EF_NONCE_SIZE - EF_MAC_SIZE;
  if (out_cap < ct_len) {
    return EF_ERR_INVALID_ARG;
  }
  const uint8_t *nonce = blob;
  const uint8_t *mac = blob + EF_NONCE_SIZE;
  const uint8_t *ct = blob + EF_NONCE_SIZE + EF_MAC_SIZE;
  if (crypto_aead_unlock(out, mac, key, nonce, ad, ad_len, ct, ct_len) != 0) {
    ef_secure_wipe(out, ct_len);
    return EF_ERR_AUTH;
  }
  *out_len = ct_len;
  return EF_OK;
}
