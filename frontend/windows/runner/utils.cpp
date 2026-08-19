#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>
#include <string>

namespace {

bool RunHiddenCommand(const std::wstring& command) {
  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  startup_info.dwFlags = STARTF_USESHOWWINDOW;
  startup_info.wShowWindow = SW_HIDE;
  PROCESS_INFORMATION process_info{};

  std::wstring mutable_command = command;
  if (!CreateProcessW(nullptr, mutable_command.data(), nullptr, nullptr, FALSE,
                      CREATE_NO_WINDOW, nullptr, nullptr, &startup_info,
                      &process_info)) {
    return false;
  }

  WaitForSingleObject(process_info.hProcess, 5000);
  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);
  return true;
}

bool IsProcessAlive(DWORD pid) {
  if (pid <= 1) {
    return false;
  }
  HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, pid);
  if (process == nullptr) {
    return false;
  }
  const DWORD wait = WaitForSingleObject(process, 0);
  CloseHandle(process);
  return wait == WAIT_TIMEOUT;
}

void TerminatePidTree(DWORD pid) {
  if (pid <= 1) {
    return;
  }

  // Graceful stop first — uvicorn can exit cleanly on SIGTERM equivalent.
  HANDLE process =
      OpenProcess(PROCESS_TERMINATE, FALSE, static_cast<DWORD>(pid));
  if (process != nullptr) {
    TerminateProcess(process, 0);
    CloseHandle(process);
    Sleep(300);
  }

  if (!IsProcessAlive(pid)) {
    return;
  }

  // Kill the full tree (PyInstaller / worker children on Windows).
  RunHiddenCommand(L"taskkill.exe /PID " + std::to_wstring(pid) +
                   L" /T /F");
}

}  // namespace

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

void TerminatePackagedBackendIfNeeded() {
  static bool already_ran = false;
  if (already_ran) {
    return;
  }
  already_ran = true;

  wchar_t* profile = nullptr;
  size_t len = 0;
  if (_wdupenv_s(&profile, &len, L"USERPROFILE") != 0 || profile == nullptr) {
    return;
  }

  std::wstring pid_path(profile);
  free(profile);
  pid_path += L"\\.robot-studio\\backend.pid";

  FILE* file = nullptr;
  if (_wfopen_s(&file, pid_path.c_str(), L"r") != 0 || file == nullptr) {
    return;
  }

  int pid = 0;
  const bool parsed = fscanf_s(file, "%d", &pid) == 1;
  fclose(file);
  if (!parsed || pid <= 1) {
    _wremove(pid_path.c_str());
    return;
  }

  TerminatePidTree(static_cast<DWORD>(pid));
  _wremove(pid_path.c_str());
}
