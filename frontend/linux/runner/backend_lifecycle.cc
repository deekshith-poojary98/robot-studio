#include "backend_lifecycle.h"

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int read_int_file(const char* path, int* out) {
  FILE* file = fopen(path, "r");
  if (file == nullptr) {
    return 0;
  }
  const int parsed = fscanf(file, "%d", out);
  fclose(file);
  return parsed == 1;
}

static int pid_listens_on_port(int pid, int port) {
  char command[128];
  if (snprintf(command, sizeof(command),
               "lsof -nP -iTCP:%d -sTCP:LISTEN -t 2>/dev/null",
               port) >= (int)sizeof(command)) {
    return 0;
  }
  FILE* pipe = popen(command, "r");
  if (pipe == nullptr) {
    return 0;
  }
  char line[64];
  int matched = 0;
  while (fgets(line, sizeof(line), pipe) != nullptr) {
    int found = 0;
    if (sscanf(line, "%d", &found) == 1 && found == pid) {
      matched = 1;
      break;
    }
  }
  pclose(pipe);
  return matched;
}

void terminate_packaged_backend_if_needed(void) {
  static int already_ran = 0;
  if (already_ran) {
    return;
  }
  already_ran = 1;

  const char* home = getenv("HOME");
  if (home == nullptr || home[0] == '\0') {
    return;
  }

  char pid_path[1024];
  char port_path[1024];
  if (snprintf(pid_path, sizeof(pid_path), "%s/.robot-studio/backend.pid",
               home) >= (int)sizeof(pid_path)) {
    return;
  }
  if (snprintf(port_path, sizeof(port_path), "%s/.robot-studio/backend.port",
               home) >= (int)sizeof(port_path)) {
    return;
  }

  int pid = 0;
  if (!read_int_file(pid_path, &pid) || pid <= 1) {
    remove(pid_path);
    return;
  }

  int port = 0;
  if (read_int_file(port_path, &port) && port > 0) {
    if (!pid_listens_on_port(pid, port)) {
      // Stale / recycled PID — do not SIGKILL an unrelated process.
      remove(pid_path);
      return;
    }
  }

  // SIGTERM first so uvicorn can shut down cleanly, then SIGKILL.
  kill(pid, SIGTERM);
  kill(-pid, SIGTERM);
  usleep(300000);
  kill(pid, SIGKILL);
  kill(-pid, SIGKILL);
  remove(pid_path);
}
