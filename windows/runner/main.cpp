#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shobjidl.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kMainWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kMainWindowTitle[] = L"FMP - Flutter Music Player";
constexpr wchar_t kSingleInstanceMutexName[] = L"Local\\FMP_MainInstance";

bool IsMultiWindowLaunch(const std::vector<std::string>& arguments) {
  return !arguments.empty() && arguments.front() == "multi_window";
}

void ActivateExistingInstance() {
  HWND existing_window =
      ::FindWindowW(kMainWindowClassName, kMainWindowTitle);
  if (existing_window == nullptr) {
    existing_window = ::FindWindowW(nullptr, kMainWindowTitle);
  }
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
  // Set AppUserModelID for SMTC (System Media Transport Controls) identity.
  ::SetCurrentProcessExplicitAppUserModelID(L"com.personal.fmp");

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();

  HANDLE single_instance_mutex = nullptr;
  if (!IsMultiWindowLaunch(command_line_arguments)) {
    single_instance_mutex =
        ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
    if (single_instance_mutex != nullptr &&
        ::GetLastError() == ERROR_ALREADY_EXISTS) {
      ActivateExistingInstance();
      ::CloseHandle(single_instance_mutex);
      ::CoUninitialize();
      return EXIT_SUCCESS;
    }
  }

  flutter::DartProject project(L"data");
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
