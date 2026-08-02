#include "encrypted_files.h"

/* This translation unit exists so linkers keep the public API symbols when
 * building as a shared library with --gc-sections. All implementations live in
 * the other .c files; this file documents the ABI surface for FFI. */

/* Force-reference core symbols. */
void ef_api_anchor(void) {
  (void)ef_suggest_chunk_size;
  (void)ef_secure_wipe;
  (void)ef_derive_master_key;
  (void)ef_stream_server_start;
}
