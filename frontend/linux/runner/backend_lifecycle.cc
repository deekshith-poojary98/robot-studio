#include "backend_lifecycle.h"

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

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
  if (snprintf(pid_path, sizeof(pid_path), "%s/.robot-studio/backend.pid",
               home) >= (int)sizeof(pid_path)) {
    return;
  }

  FILE* file = fopen(pid_path, "r");
  if (file == nullptr) {
    return;
  }

  int pid = 0;
  const int parsed = fscanf(file, "%d", &pid);
  fclose(file);
  if (parsed != 1 || pid <= 1) {
    remove(pid_path);
    return;
  }

  // SIGTERM first so uvicorn can shut down cleanly, then SIGKILL.
  kill(pid, SIGTERM);
  kill(-pid, SIGTERM);
  usleep(300000);
  kill(pid, SIGKILL);
  kill(-pid, SIGKILL);
  remove(pid_path);
}
