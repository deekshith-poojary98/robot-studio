#include "flutter_window.h"

#include <optional>
#include <cstdio>
#include <string>

#include <windows.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Mirror macOS AppDelegate: kill packaged sidecar via BackendHost pid file.
  wchar_t* profile = nullptr;
  size_t len = 0;
  if (_wdupenv_s(&profile, &len, L"USERPROFILE") == 0 && profile != nullptr) {
    std::wstring pid_path(profile);
    free(profile);
    pid_path += L"\\.robot-studio\\backend.pid";
    FILE* file = nullptr;
    if (_wfopen_s(&file, pid_path.c_str(), L"r") == 0 && file != nullptr) {
      int pid = 0;
      if (fscanf_s(file, "%d", &pid) == 1 && pid > 1) {
        HANDLE process =
            OpenProcess(PROCESS_TERMINATE, FALSE, static_cast<DWORD>(pid));
        if (process != nullptr) {
          TerminateProcess(process, 0);
          CloseHandle(process);
        }
      }
      fclose(file);
      _wremove(pid_path.c_str());
    }
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
