#ifndef RUNNER_BACKEND_LIFECYCLE_H_
#define RUNNER_BACKEND_LIFECYCLE_H_

#ifdef __cplusplus
extern "C" {
#endif

// Kill the packaged Python sidecar using ~/.robot-studio/backend.pid.
// Mirrors macOS AppDelegate.terminatePackagedBackendIfNeeded().
void terminate_packaged_backend_if_needed(void);

#ifdef __cplusplus
}
#endif

#endif  // RUNNER_BACKEND_LIFECYCLE_H_
