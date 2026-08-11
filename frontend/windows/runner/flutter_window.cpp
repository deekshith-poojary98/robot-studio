#include "flutter_window.h"

#include <optional>
#include <cstdio>
#include <set>
#include <string>
#include <vector>

#include <windows.h>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {
int CALLBACK EnumMonospaceFonts(const LOGFONTW* lf, const TEXTMETRICW*, DWORD,
                                LPARAM lparam) {
  auto* out = reinterpret_cast<std::set<std::string>*>(lparam);
  if ((lf->lfPitchAndFamily & 0x3) != FIXED_PITCH) {
    return TRUE;
  }
  if (lf->lfFaceName[0] == L'@' || lf->lfFaceName[0] == L'.') {
    return TRUE;
  }
  std::string name = Utf8FromUtf16(lf->lfFaceName);
  if (!name.empty()) {
    out->insert(std::move(name));
  }
  return TRUE;
}

std::vector<std::string> ListMonospaceFontFamilies() {
  std::set<std::string> names;
  HDC hdc = GetDC(nullptr);
  if (hdc == nullptr) {
    return {};
  }
  LOGFONTW pattern = {};
  pattern.lfCharSet = DEFAULT_CHARSET;
  EnumFontFamiliesExW(hdc, &pattern, EnumMonospaceFonts,
                      reinterpret_cast<LPARAM>(&names), 0);
  ReleaseDC(nullptr, hdc);
  return {names.begin(), names.end()};
}

void RegisterFontCatalogChannel(
    flutter::BinaryMessenger* messenger,
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>* slot) {
  *slot = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "robot_studio/fonts",
      &flutter::StandardMethodCodec::GetInstance());
  slot->get()->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "listMonospaceFamilies") {
          result->NotImplemented();
          return;
        }
        flutter::EncodableList names;
        for (const auto& family : ListMonospaceFontFamilies()) {
          names.emplace_back(family);
        }
        result->Success(flutter::EncodableValue(std::move(names)));
      });
}
}  // namespace

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
  RegisterFontCatalogChannel(flutter_controller_->engine()->messenger(),
                             &fonts_channel_);
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
