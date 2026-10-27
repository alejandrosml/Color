#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// One studio at a time. The recovery copy and the album belong to a single
// process: a second launch shows the window of the first one and ends,
// instead of opening another studio on the same folders. The name is local
// to the Windows session: each person signed in keeps a studio of their own.
constexpr wchar_t kSingleStudioName[] =
    L"Local\\com.example.edupaint_flutter_study.studio";
// The class and the title given to the window in win32_window.cpp and below.
constexpr wchar_t kStudioWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kStudioWindowTitle[] = L"Color";

// True when another process of this session already runs the studio. Its
// window, when it is there, comes to the front.
bool AnotherStudioIsRunning() {
  HANDLE studio = ::CreateMutexW(nullptr, FALSE, kSingleStudioName);
  if (studio == nullptr) {
    // The system refused the name: start as before rather than not at all.
    return false;
  }
  if (::GetLastError() != ERROR_ALREADY_EXISTS) {
    // Kept until the process ends: the name is the mark of this studio.
    return false;
  }
  ::CloseHandle(studio);
  HWND window = ::FindWindowW(kStudioWindowClass, kStudioWindowTitle);
  if (window != nullptr) {
    if (::IsIconic(window)) {
      ::ShowWindow(window, SW_RESTORE);
    }
    ::SetForegroundWindow(window);
  }
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (AnotherStudioIsRunning()) {
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
  if (!window.Create(kStudioWindowTitle, origin, size)) {
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
