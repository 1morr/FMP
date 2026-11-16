#ifndef RUNNER_WINDOW_FRAME_H_
#define RUNNER_WINDOW_FRAME_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <optional>

// The main window without the native title bar (design doc, "desktop",
// Windows). The app draws minimize / maximize / close itself
// (lib/ui/shell/caption_buttons.dart); this class keeps the window behaving
// like a normal Windows window:
//
// - WM_NCCALCSIZE drops the caption and the top frame but keeps the left,
//   right and bottom resize borders (the Windows Terminal approach).
// - The top few pixels of the client area resize the window, and the
//   maximize button reports HTMAXBUTTON so Windows 11 opens Snap Layouts
//   over it (fact W12). The Flutter view covers the client area, so its
//   WM_NCHITTEST answers HTTRANSPARENT there and the message falls through
//   to the main window.
// - Hover, press and click of the maximize button then arrive as non-client
//   messages; they are handled here and the state is sent to Dart.
// - The "fmp/window" channel (lib/platform/window_controls.dart,
//   lib/platform/window_drag.dart) drags, minimizes, maximizes and closes.
//
// ASCII only: the runner builds with /WX, and non-ASCII bytes trip C4819 on
// CJK locales.
class WindowFrame {
 public:
  WindowFrame() = default;
  ~WindowFrame();

  WindowFrame(const WindowFrame&) = delete;
  WindowFrame& operator=(const WindowFrame&) = delete;

  // Hooks the Flutter view |content| of |window| and opens the channel.
  void Attach(HWND window, HWND content, flutter::BinaryMessenger* messenger);

  // Undoes Attach: restores the Flutter view's window procedure and closes
  // the channel. Safe to call more than once.
  void Detach();

  // Handles a message of the main window; std::nullopt lets the default
  // handling run.
  std::optional<LRESULT> HandleMessage(HWND window, UINT message,
                                       WPARAM wparam, LPARAM lparam);

 private:
  // Window procedure installed on the Flutter view.
  static LRESULT CALLBACK ContentProc(HWND content, UINT message,
                                      WPARAM wparam, LPARAM lparam);

  // Hit test of a point of the client area, in screen coordinates: HTTOP,
  // HTMAXBUTTON or HTCLIENT.
  LRESULT HitTestClient(HWND window, POINT screen) const;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void SetMaximizeButtonState(bool hovered, bool pressed);
  void NotifyMaximized();

  HWND window_ = nullptr;
  HWND content_ = nullptr;
  WNDPROC content_proc_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // Where Dart drew the maximize button, in logical pixels measured from
  // the top-right corner of the client area. Empty until Dart reports it.
  bool has_maximize_button_ = false;
  double button_right_ = 0;
  double button_top_ = 0;
  double button_width_ = 0;
  double button_height_ = 0;

  bool hovered_ = false;
  bool pressed_ = false;
  bool maximized_ = false;
};

#endif  // RUNNER_WINDOW_FRAME_H_
