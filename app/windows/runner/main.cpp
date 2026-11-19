#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

// `hiwiski://`. The app ships without an installer that could register
// the scheme, so it registers itself for the current user on every start: a copy that
// was moved or replaced points the scheme at where it is now.
void RegisterUriScheme() {
  wchar_t path[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length == MAX_PATH) {
    return;
  }
  const std::wstring key = L"Software\\Classes\\hiwiski";
  const std::wstring name = L"URL:Hiwiski";
  const std::wstring empty;
  const std::wstring command =
      L"\"" + std::wstring(path, length) + L"\" \"%1\"";
  const auto set = [](const std::wstring& subkey, const wchar_t* value_name,
                      const std::wstring& data) {
    ::RegSetKeyValueW(HKEY_CURRENT_USER, subkey.c_str(), value_name, REG_SZ,
                      data.c_str(),
                      static_cast<DWORD>((data.size() + 1) * sizeof(wchar_t)));
  };
  set(key, nullptr, name);
  set(key, L"URL Protocol", empty);
  set(key + L"\\shell\\open\\command", nullptr, command);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // A link opened while the app runs goes to that window instead of a second one.
  if (SendAppLinkToInstance()) {
    return EXIT_SUCCESS;
  }
  RegisterUriScheme();

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
  if (!window.Create(L"Hiwiski", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
