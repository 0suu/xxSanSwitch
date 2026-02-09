#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <filesystem>
#include <functional>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

std::wstring ExecutableDirectory() {
  std::wstring buffer(MAX_PATH, L'\0');
  while (true) {
    const DWORD copied =
        ::GetModuleFileNameW(nullptr, buffer.data(),
                             static_cast<DWORD>(buffer.size()));
    if (copied == 0) {
      return L".";
    }
    if (copied < buffer.size() - 1) {
      buffer.resize(copied);
      break;
    }
    buffer.resize(buffer.size() * 2);
  }

  const size_t sep = buffer.find_last_of(L"\\/");
  if (sep == std::wstring::npos) {
    return L".";
  }
  return buffer.substr(0, sep);
}

std::wstring TryGetShortPath(const std::wstring& path) {
  const DWORD required = ::GetShortPathNameW(path.c_str(), nullptr, 0);
  if (required == 0) {
    return path;
  }

  std::wstring short_path(required, L'\0');
  const DWORD copied =
      ::GetShortPathNameW(path.c_str(), short_path.data(), required);
  if (copied == 0) {
    return path;
  }

  if (!short_path.empty() && short_path.back() == L'\0') {
    short_path.pop_back();
  }
  return short_path;
}

bool ContainsNonAscii(const std::wstring& text) {
  for (wchar_t c : text) {
    if (c > 0x7F) {
      return true;
    }
  }
  return false;
}

std::wstring GetTempDirectory() {
  std::wstring buffer(MAX_PATH, L'\0');
  while (true) {
    const DWORD copied =
        ::GetTempPathW(static_cast<DWORD>(buffer.size()), buffer.data());
    if (copied == 0) {
      return L"";
    }
    if (copied < buffer.size()) {
      buffer.resize(copied);
      if (!buffer.empty() &&
          (buffer.back() == L'\\' || buffer.back() == L'/')) {
        buffer.pop_back();
      }
      return buffer;
    }
    buffer.resize(copied + 1);
  }
}

std::wstring PrepareAsciiRuntimeDirectory(const std::wstring& source_dir) {
  const std::wstring temp_dir = GetTempDirectory();
  if (temp_dir.empty()) {
    return L"";
  }

  const std::wstring runtime_root = temp_dir + L"\\xxSanSwitch_runtime";
  const std::wstring runtime_dir =
      runtime_root +
      L"\\" + std::to_wstring(std::hash<std::wstring>{}(source_dir));

  std::error_code ec;
  std::filesystem::create_directories(runtime_root, ec);
  if (ec) {
    return L"";
  }

  const std::filesystem::path src_data = std::filesystem::path(source_dir) / L"data";
  const std::filesystem::path dst_data = std::filesystem::path(runtime_dir) / L"data";
  std::filesystem::remove_all(dst_data, ec);
  ec.clear();
  std::filesystem::create_directories(std::filesystem::path(runtime_dir), ec);
  if (ec) {
    return L"";
  }
  std::filesystem::copy(src_data, dst_data,
                        std::filesystem::copy_options::recursive, ec);
  if (ec) {
    return L"";
  }

  return runtime_dir;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, L"Local\\xxSanSwitch.SingleInstance");
  if (single_instance_mutex == nullptr) {
    return EXIT_FAILURE;
  }
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    ::MessageBoxW(nullptr, L"xxSanSwitch is already running.",
                  L"xxSanSwitch", MB_OK | MB_ICONINFORMATION);
    ::CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  const std::wstring exe_dir = ExecutableDirectory();
  std::wstring project_dir = TryGetShortPath(exe_dir);
  if (ContainsNonAscii(project_dir)) {
    const std::wstring ascii_runtime_dir = PrepareAsciiRuntimeDirectory(exe_dir);
    if (!ascii_runtime_dir.empty()) {
      project_dir = ascii_runtime_dir;
    }
  }
  const std::wstring assets_path = project_dir + L"\\data\\flutter_assets";
  const std::wstring icu_path = project_dir + L"\\data\\icudtl.dat";
  const std::wstring aot_path = project_dir + L"\\data\\app.so";

  ::SetCurrentDirectoryW(project_dir.c_str());
  flutter::DartProject project(assets_path, icu_path, aot_path);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // Keep the startup window compact so it does not obstruct other apps.
  Win32Window::Size size(480, 251);
  if (!window.Create(L"xxSanSwtich", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::CloseHandle(single_instance_mutex);
  return EXIT_SUCCESS;
}
