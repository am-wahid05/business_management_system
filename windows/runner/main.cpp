#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cwchar>
#include <string>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kAuthCallbackScheme[] = L"businessms";

LSTATUS WriteRegistryString(HKEY root, const wchar_t* subkey,
                            const wchar_t* value_name, const wchar_t* value) {
  HKEY key = nullptr;
  LSTATUS result = RegCreateKeyExW(
      root, subkey, static_cast<DWORD>(0), nullptr, static_cast<DWORD>(0),
      KEY_WRITE, nullptr, &key, nullptr);
  if (result != ERROR_SUCCESS) {
    return result;
  }

  result = RegSetValueExW(
      key, value_name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value),
      static_cast<DWORD>((std::wcslen(value) + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
  return result;
}

// Register the unpackaged development/release executable as the handler for
// Supabase's email-confirmation callback. Updating this on every launch keeps
// the command path correct after the executable is moved or rebuilt.
bool RegisterAuthCallbackProtocol() {
  wchar_t executable[MAX_PATH] = {};
  const DWORD length = GetModuleFileNameW(nullptr, executable, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return false;
  }

  const std::wstring protocol_key =
      std::wstring(L"Software\\Classes\\") + kAuthCallbackScheme;
  const std::wstring command_key = protocol_key + L"\\shell\\open\\command";
  const std::wstring command =
      L"\"" + std::wstring(executable, length) + L"\" \"%1\"";

  return WriteRegistryString(HKEY_CURRENT_USER, protocol_key.c_str(),
                             L"URL Protocol", L"") == ERROR_SUCCESS &&
         WriteRegistryString(HKEY_CURRENT_USER, command_key.c_str(), L"",
                             command.c_str()) == ERROR_SUCCESS;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Forward the callback to the running Flutter window instead of opening a
  // second application instance.
  if (SendAppLinkToInstance()) {
    return EXIT_SUCCESS;
  }
  RegisterAuthCallbackProtocol();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Business Management System", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);
  window.Show();

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
