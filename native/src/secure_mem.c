#include "encrypted_files.h"

#include <string.h>

#if defined(EF_PLATFORM_WINDOWS)
  #include <windows.h>
  #include <bcrypt.h>
  #pragma comment(lib, "bcrypt.lib")
#elif defined(EF_PLATFORM_APPLE)
  #include <Security/SecRandom.h>
#elif defined(__linux__) || defined(EF_PLATFORM_ANDROID) || defined(EF_PLATFORM_LINUX)
  #include <fcntl.h>
  #include <unistd.h>
  #include <errno.h>
#endif

#include "monocypher.h"

void ef_secure_wipe(void *ptr, size_t len) {
  if (ptr == NULL || len == 0) {
    return;
  }
  crypto_wipe(ptr, len);
}

int ef_secure_random(uint8_t *out, size_t len) {
  if (out == NULL || len == 0) {
    return EF_ERR_INVALID_ARG;
  }

#if defined(EF_PLATFORM_WINDOWS)
  NTSTATUS status = BCryptGenRandom(NULL, out, (ULONG)len, BCRYPT_USE_SYSTEM_PREFERRED_RNG);
  return (status == 0) ? EF_OK : EF_ERR_INTERNAL;
#elif defined(EF_PLATFORM_APPLE)
  return (SecRandomCopyBytes(kSecRandomDefault, len, out) == errSecSuccess)
             ? EF_OK
             : EF_ERR_INTERNAL;
#else
  int fd = open("/dev/urandom", O_RDONLY);
  if (fd < 0) {
    return EF_ERR_IO;
  }
  size_t got = 0;
  while (got < len) {
    ssize_t n = read(fd, out + got, len - got);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      close(fd);
      return EF_ERR_IO;
    }
    if (n == 0) {
      close(fd);
      return EF_ERR_IO;
    }
    got += (size_t)n;
  }
  close(fd);
  return EF_OK;
#endif
}
