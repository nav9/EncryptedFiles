#include "encrypted_files.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#if defined(EF_PLATFORM_WINDOWS)
  #ifndef WIN32_LEAN_AND_MEAN
    #define WIN32_LEAN_AND_MEAN
  #endif
  #include <winsock2.h>
  #include <ws2tcpip.h>
  #include <process.h>
  #include <windows.h>
  typedef SOCKET ef_sock_t;
  #define EF_INVALID_SOCK INVALID_SOCKET
  #define ef_close_sock closesocket
  #define ef_sock_err WSAGetLastError()
#else
  #include <unistd.h>
  #include <pthread.h>
  #include <sys/types.h>
  #include <sys/socket.h>
  #include <netinet/in.h>
  #include <arpa/inet.h>
  typedef int ef_sock_t;
  #define EF_INVALID_SOCK (-1)
  #define ef_close_sock close
  #define ef_sock_err errno
#endif

#include "monocypher.h"

#define EF_MAX_ROUTES 64
#define EF_TOKEN_LEN 32

typedef struct {
  int in_use;
  char token[EF_TOKEN_LEN * 2 + 1];
  char path[1024];
  char mime[128];
  uint64_t size;
} EfRoute;

struct EfStreamServer {
  ef_sock_t listen_fd;
  int port;
  int running;
  uint8_t enc_key[EF_KEY_SIZE];
  uint32_t chunk_override;
  EfRoute routes[EF_MAX_ROUTES];
#if defined(EF_PLATFORM_WINDOWS)
  HANDLE thread;
  CRITICAL_SECTION lock;
#else
  pthread_t thread;
  pthread_mutex_t lock;
#endif
};

#if defined(EF_PLATFORM_WINDOWS)
static volatile LONG g_wsa_ready = 0;

static int ef_net_init(void) {
  if (InterlockedCompareExchange(&g_wsa_ready, 1, 0) == 0) {
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
      InterlockedExchange(&g_wsa_ready, 0);
      return -1;
    }
  }
  return 0;
}
#else
static int ef_net_init(void) { return 0; }
#endif

static void hex_encode(const uint8_t *in, size_t len, char *out) {
  static const char *hex = "0123456789abcdef";
  for (size_t i = 0; i < len; i++) {
    out[i * 2] = hex[(in[i] >> 4) & 0xF];
    out[i * 2 + 1] = hex[in[i] & 0xF];
  }
  out[len * 2] = '\0';
}

static void lock_server(EfStreamServer *s) {
#if defined(EF_PLATFORM_WINDOWS)
  EnterCriticalSection(&s->lock);
#else
  pthread_mutex_lock(&s->lock);
#endif
}

static void unlock_server(EfStreamServer *s) {
#if defined(EF_PLATFORM_WINDOWS)
  LeaveCriticalSection(&s->lock);
#else
  pthread_mutex_unlock(&s->lock);
#endif
}

static EfRoute *find_route(EfStreamServer *s, const char *token) {
  for (int i = 0; i < EF_MAX_ROUTES; i++) {
    if (s->routes[i].in_use && strcmp(s->routes[i].token, token) == 0) {
      return &s->routes[i];
    }
  }
  return NULL;
}

static int send_all(ef_sock_t fd, const char *data, size_t len) {
  size_t sent = 0;
  while (sent < len) {
#if defined(EF_PLATFORM_WINDOWS)
    int n = send(fd, data + sent, (int)(len - sent), 0);
#else
    ssize_t n = send(fd, data + sent, len - sent, 0);
#endif
    if (n <= 0) {
      return -1;
    }
    sent += (size_t)n;
  }
  return 0;
}

static void send_error(ef_sock_t fd, int code, const char *msg) {
  char buf[256];
  int n = snprintf(buf, sizeof(buf),
                   "HTTP/1.1 %d %s\r\nConnection: close\r\nContent-Length: 0\r\n\r\n",
                   code, msg);
  if (n > 0) {
    send_all(fd, buf, (size_t)n);
  }
}

static void handle_client(EfStreamServer *server, ef_sock_t client) {
  char req[2048];
  size_t got = 0;
  while (got < sizeof(req) - 1) {
#if defined(EF_PLATFORM_WINDOWS)
    int n = recv(client, req + got, (int)(sizeof(req) - 1 - got), 0);
#else
    ssize_t n = recv(client, req + got, sizeof(req) - 1 - got, 0);
#endif
    if (n <= 0) {
      ef_close_sock(client);
      return;
    }
    got += (size_t)n;
    req[got] = '\0';
    if (strstr(req, "\r\n\r\n")) {
      break;
    }
  }

  /* Expect: GET /d/<token> HTTP/1.1 */
  char method[16] = {0};
  char path[256] = {0};
  if (sscanf(req, "%15s %255s", method, path) != 2) {
    send_error(client, 400, "Bad Request");
    ef_close_sock(client);
    return;
  }
  if (strcmp(method, "GET") != 0 && strcmp(method, "HEAD") != 0) {
    send_error(client, 405, "Method Not Allowed");
    ef_close_sock(client);
    return;
  }

  const char *prefix = "/d/";
  if (strncmp(path, prefix, strlen(prefix)) != 0) {
    send_error(client, 404, "Not Found");
    ef_close_sock(client);
    return;
  }
  const char *token = path + strlen(prefix);
  char token_clean[EF_TOKEN_LEN * 2 + 1];
  size_t tl = 0;
  while (token[tl] && token[tl] != '?' && token[tl] != ' ' && tl < sizeof(token_clean) - 1) {
    token_clean[tl] = token[tl];
    tl++;
  }
  token_clean[tl] = '\0';

  char file_path[1024];
  char mime[128];
  uint64_t size = 0;
  uint8_t key_copy[EF_KEY_SIZE];

  lock_server(server);
  EfRoute *route = find_route(server, token_clean);
  if (!route) {
    unlock_server(server);
    send_error(client, 404, "Not Found");
    ef_close_sock(client);
    return;
  }
  strncpy(file_path, route->path, sizeof(file_path) - 1);
  file_path[sizeof(file_path) - 1] = '\0';
  strncpy(mime, route->mime, sizeof(mime) - 1);
  mime[sizeof(mime) - 1] = '\0';
  size = route->size;
  memcpy(key_copy, server->enc_key, EF_KEY_SIZE);
  unlock_server(server);

  char header[512];
  int hlen = snprintf(header, sizeof(header),
                      "HTTP/1.1 200 OK\r\n"
                      "Content-Type: %s\r\n"
                      "Content-Length: %llu\r\n"
                      "Accept-Ranges: none\r\n"
                      "Cache-Control: no-store, no-cache, must-revalidate, max-age=0\r\n"
                      "Pragma: no-cache\r\n"
                      "Connection: close\r\n"
                      "\r\n",
                      mime[0] ? mime : "application/octet-stream",
                      (unsigned long long)size);
  if (hlen <= 0 || send_all(client, header, (size_t)hlen) != 0) {
    ef_secure_wipe(key_copy, sizeof(key_copy));
    ef_close_sock(client);
    return;
  }

  if (strcmp(method, "HEAD") == 0) {
    ef_secure_wipe(key_copy, sizeof(key_copy));
    ef_close_sock(client);
    return;
  }

  char real_name[8];
  char out_mime[8];
  uint32_t chunk = 0;
  uint64_t plain = 0;
  uint8_t tag[EF_BLIND_SIZE];
  EfDecryptCtx *dctx = ef_decrypt_begin(file_path, key_copy, &chunk, real_name,
                                        sizeof(real_name), out_mime, sizeof(out_mime),
                                        &plain, tag);
  ef_secure_wipe(key_copy, sizeof(key_copy));
  if (!dctx) {
    ef_close_sock(client);
    return;
  }

  uint32_t use_chunk = chunk;
  if (server->chunk_override > 0) {
    use_chunk = server->chunk_override;
  }
  uint8_t *buf = (uint8_t *)malloc(use_chunk);
  if (!buf) {
    ef_decrypt_abort(dctx);
    ef_close_sock(client);
    return;
  }

  while (1) {
    size_t n = 0;
    int rc = ef_decrypt_update(dctx, buf, use_chunk, &n);
    if (rc != EF_OK) {
      break;
    }
    if (n == 0) {
      ef_decrypt_finish(dctx);
      dctx = NULL;
      break;
    }
    if (send_all(client, (const char *)buf, n) != 0) {
      ef_secure_wipe(buf, n);
      break;
    }
    ef_secure_wipe(buf, n);
  }

  free(buf);
  if (dctx) {
    ef_decrypt_abort(dctx);
  }
  ef_close_sock(client);
}

#if defined(EF_PLATFORM_WINDOWS)
static unsigned __stdcall server_thread(void *arg) {
#else
static void *server_thread(void *arg) {
#endif
  EfStreamServer *server = (EfStreamServer *)arg;
  while (server->running) {
    struct sockaddr_in addr;
    socklen_t alen = sizeof(addr);
    ef_sock_t client = accept(server->listen_fd, (struct sockaddr *)&addr, &alen);
    if (client == EF_INVALID_SOCK) {
      if (!server->running) {
        break;
      }
      continue;
    }
    /* Only accept localhost. */
    if (addr.sin_addr.s_addr != htonl(INADDR_LOOPBACK)) {
      ef_close_sock(client);
      continue;
    }
    handle_client(server, client);
  }
#if defined(EF_PLATFORM_WINDOWS)
  return 0;
#else
  return NULL;
#endif
}

EfStreamServer *ef_stream_server_start(
    const uint8_t enc_key[EF_KEY_SIZE],
    uint32_t chunk_size_override,
    int *out_port) {
  if (!enc_key || !out_port) {
    return NULL;
  }
  if (ef_net_init() != 0) {
    return NULL;
  }

  EfStreamServer *s = (EfStreamServer *)calloc(1, sizeof(EfStreamServer));
  if (!s) {
    return NULL;
  }
  memcpy(s->enc_key, enc_key, EF_KEY_SIZE);
  s->chunk_override = chunk_size_override;
  s->listen_fd = EF_INVALID_SOCK;

#if defined(EF_PLATFORM_WINDOWS)
  InitializeCriticalSection(&s->lock);
#else
  pthread_mutex_init(&s->lock, NULL);
#endif

  s->listen_fd = socket(AF_INET, SOCK_STREAM, 0);
  if (s->listen_fd == EF_INVALID_SOCK) {
    free(s);
    return NULL;
  }

  int yes = 1;
  setsockopt(s->listen_fd, SOL_SOCKET, SO_REUSEADDR, (const char *)&yes, sizeof(yes));

  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  addr.sin_port = htons(0); /* ephemeral */

  if (bind(s->listen_fd, (struct sockaddr *)&addr, sizeof(addr)) != 0 ||
      listen(s->listen_fd, 8) != 0) {
    ef_close_sock(s->listen_fd);
    free(s);
    return NULL;
  }

  socklen_t len = sizeof(addr);
  if (getsockname(s->listen_fd, (struct sockaddr *)&addr, &len) != 0) {
    ef_close_sock(s->listen_fd);
    free(s);
    return NULL;
  }
  s->port = ntohs(addr.sin_port);
  *out_port = s->port;
  s->running = 1;

#if defined(EF_PLATFORM_WINDOWS)
  s->thread = (HANDLE)_beginthreadex(NULL, 0, server_thread, s, 0, NULL);
  if (!s->thread) {
    s->running = 0;
    ef_close_sock(s->listen_fd);
    free(s);
    return NULL;
  }
#else
  if (pthread_create(&s->thread, NULL, server_thread, s) != 0) {
    s->running = 0;
    ef_close_sock(s->listen_fd);
    pthread_mutex_destroy(&s->lock);
    free(s);
    return NULL;
  }
#endif
  return s;
}

int ef_stream_server_register(
    EfStreamServer *server,
    const char *encrypted_path,
    char *out_token, size_t token_cap,
    char *out_url, size_t url_cap) {
  if (!server || !encrypted_path || !out_token || !out_url) {
    return EF_ERR_INVALID_ARG;
  }

  char real_name[512];
  char mime[128];
  uint64_t size = 0;
  uint32_t chunk = 0;
  uint8_t tag[EF_BLIND_SIZE];

  EfDecryptCtx *probe = ef_decrypt_begin(encrypted_path, server->enc_key, &chunk,
                                         real_name, sizeof(real_name),
                                         mime, sizeof(mime), &size, tag);
  if (!probe) {
    return EF_ERR_AUTH;
  }
  ef_decrypt_abort(probe);

  uint8_t rnd[EF_TOKEN_LEN];
  if (ef_secure_random(rnd, sizeof(rnd)) != EF_OK) {
    return EF_ERR_INTERNAL;
  }
  char token[EF_TOKEN_LEN * 2 + 1];
  hex_encode(rnd, sizeof(rnd), token);

  lock_server(server);
  int slot = -1;
  for (int i = 0; i < EF_MAX_ROUTES; i++) {
    if (!server->routes[i].in_use) {
      slot = i;
      break;
    }
  }
  if (slot < 0) {
    unlock_server(server);
    return EF_ERR_BUSY;
  }
  EfRoute *r = &server->routes[slot];
  memset(r, 0, sizeof(*r));
  r->in_use = 1;
  strncpy(r->token, token, sizeof(r->token) - 1);
  strncpy(r->path, encrypted_path, sizeof(r->path) - 1);
  strncpy(r->mime, mime, sizeof(r->mime) - 1);
  r->size = size;
  unlock_server(server);

  if (token_cap < strlen(token) + 1) {
    return EF_ERR_INVALID_ARG;
  }
  strcpy(out_token, token);
  snprintf(out_url, url_cap, "http://127.0.0.1:%d/d/%s", server->port, token);
  return EF_OK;
}

void ef_stream_server_unregister(EfStreamServer *server, const char *token) {
  if (!server || !token) {
    return;
  }
  lock_server(server);
  EfRoute *r = find_route(server, token);
  if (r) {
    memset(r, 0, sizeof(*r));
  }
  unlock_server(server);
}

void ef_stream_server_clear_keys(EfStreamServer *server) {
  if (!server) {
    return;
  }
  lock_server(server);
  ef_secure_wipe(server->enc_key, sizeof(server->enc_key));
  unlock_server(server);
}

void ef_stream_server_stop(EfStreamServer *server) {
  if (!server) {
    return;
  }
  server->running = 0;
  if (server->listen_fd != EF_INVALID_SOCK) {
    ef_close_sock(server->listen_fd);
    server->listen_fd = EF_INVALID_SOCK;
  }
#if defined(EF_PLATFORM_WINDOWS)
  if (server->thread) {
    WaitForSingleObject(server->thread, 5000);
    CloseHandle(server->thread);
  }
  DeleteCriticalSection(&server->lock);
#else
  pthread_join(server->thread, NULL);
  pthread_mutex_destroy(&server->lock);
#endif
  for (int i = 0; i < EF_MAX_ROUTES; i++) {
    memset(&server->routes[i], 0, sizeof(server->routes[i]));
  }
  ef_secure_wipe(server->enc_key, sizeof(server->enc_key));
  free(server);
}
