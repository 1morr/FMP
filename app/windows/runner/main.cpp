#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shobjidl.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// FMP_* 由 runner/CMakeLists.txt 依 flavor 定義（app_identity.cmake）。
// 窄字串前接 L"" 會串接成寬字串。
namespace {

constexpr wchar_t kMainWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kMainWindowTitle[] = L"" FMP_DISPLAY_NAME;
constexpr wchar_t kAppUserModelId[] = L"" FMP_APP_USER_MODEL_ID;
constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\" FMP_SINGLE_INSTANCE_NAME;

// 把已在執行的同 flavor 實例帶到前景；照舊版 windows/runner/main.cpp。
void ActivateExistingInstance() {
  HWND existing_window =
      ::FindWindowW(kMainWindowClassName, kMainWindowTitle);
  if (existing_window == nullptr) {
    return;
  }

  if (!::IsWindowVisible(existing_window)) {
    ::ShowWindow(existing_window, SW_SHOW);
  }
  if (::IsIconic(existing_window)) {
    ::ShowWindow(existing_window, SW_RESTORE);
  }
  ::SetForegroundWindow(existing_window);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // 系統媒體控制與工作列分組都以 AUMID 認 App；dev 與 prod 各自一個。
  ::SetCurrentProcessExplicitAppUserModelID(kAppUserModelId);

  // 第二個同 flavor 的實例把第一個帶到前景後結束。
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateExistingInstance();
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

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kMainWindowTitle, origin, size)) {
    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (single_instance_mutex != nullptr) {
    ::CloseHandle(single_instance_mutex);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
