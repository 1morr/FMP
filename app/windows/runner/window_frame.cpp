#include "window_frame.h"

#include <flutter/standard_method_codec.h>
#include <windowsx.h>

#include <cmath>

namespace {

constexpr wchar_t kFrameProperty[] = L"FmpWindowFrame";

// Smallest client area in logical pixels, the same as contentMinSize in
// macos/Runner/MainFlutterWindow.swift.
constexpr int kMinClientWidth = 720;
constexpr int kMinClientHeight = 560;

// Thickness of the resize border Windows puts around a sizable window, which
// is also how far a maximized window hangs over the edges of the monitor.
// Windows Terminal uses the same sum for its top resize handle.
int ResizeBorder(UINT dpi) {
  return GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) +
         GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}

int ResizeBorderX(UINT dpi) {
  return GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) +
         GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}

void ToggleMaximize(HWND window) {
  ShowWindow(window, IsZoomed(window) ? SW_RESTORE : SW_MAXIMIZE);
}

int Scale(double logical, UINT dpi) {
  return static_cast<int>(std::lround(logical * dpi / 96.0));
}

const flutter::EncodableValue* Find(const flutter::EncodableMap& map,
                                    const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::optional<double> GetDouble(const flutter::EncodableMap& map,
                                const char* key) {
  const auto* value = Find(map, key);
  if (value == nullptr) return std::nullopt;
  if (const auto* d = std::get_if<double>(value)) return *d;
  if (const auto* i = std::get_if<int32_t>(value)) return *i;
  if (const auto* l = std::get_if<int64_t>(value)) {
    return static_cast<double>(*l);
  }
  return std::nullopt;
}

}  // namespace

WindowFrame::~WindowFrame() { Detach(); }

void WindowFrame::Detach() {
  if (content_ != nullptr && IsWindow(content_)) {
    SetWindowLongPtr(content_, GWLP_WNDPROC,
                     reinterpret_cast<LONG_PTR>(content_proc_));
    RemoveProp(content_, kFrameProperty);
  }
  content_ = nullptr;
  channel_ = nullptr;
}

void WindowFrame::Attach(HWND window, HWND content,
                         flutter::BinaryMessenger* messenger) {
  window_ = window;
  content_ = content;
  SetProp(content_, kFrameProperty, this);
  content_proc_ = reinterpret_cast<WNDPROC>(SetWindowLongPtr(
      content_, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(ContentProc)));

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "fmp/window", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });

  maximized_ = IsZoomed(window_) != 0;
  // Recompute the frame now that WM_NCCALCSIZE is handled.
  SetWindowPos(window_, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOACTIVATE);
}

// static
LRESULT CALLBACK WindowFrame::ContentProc(HWND content, UINT message,
                                          WPARAM wparam, LPARAM lparam) {
  auto* frame = static_cast<WindowFrame*>(GetProp(content, kFrameProperty));
  if (frame == nullptr) return DefWindowProc(content, message, wparam, lparam);
  if (message == WM_NCHITTEST) {
    POINT screen = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    if (frame->HitTestClient(frame->window_, screen) != HTCLIENT) {
      // Let the main window answer (a top resize code or HTMAXBUTTON).
      return HTTRANSPARENT;
    }
  }
  return CallWindowProc(frame->content_proc_, content, message, wparam,
                        lparam);
}

LRESULT WindowFrame::HitTestClient(HWND window, POINT screen) const {
  POINT point = screen;
  ScreenToClient(window, &point);
  const UINT dpi = GetDpiForWindow(window);
  RECT client;
  GetClientRect(window, &client);
  if (!IsZoomed(window) && point.y >= 0 && point.y < ResizeBorder(dpi)) {
    // The corners of the top band resize diagonally, like the side borders.
    const int corner = ResizeBorderX(dpi);
    if (point.x < corner) return HTTOPLEFT;
    if (point.x >= client.right - corner) return HTTOPRIGHT;
    return HTTOP;
  }
  if (has_maximize_button_) {
    const LONG right = client.right - Scale(button_right_, dpi);
    const LONG top = Scale(button_top_, dpi);
    const RECT button = {right - Scale(button_width_, dpi), top, right,
                         top + Scale(button_height_, dpi)};
    if (PtInRect(&button, point)) return HTMAXBUTTON;
  }
  return HTCLIENT;
}

std::optional<LRESULT> WindowFrame::HandleMessage(HWND window, UINT message,
                                                  WPARAM wparam,
                                                  LPARAM lparam) {
  switch (message) {
    case WM_NCCALCSIZE: {
      if (!wparam) return std::nullopt;
      // Let Windows compute the standard frame, then give the caption and
      // the top border back to the client area.
      auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
      const LONG top = params->rgrc[0].top;
      const LRESULT result = DefWindowProc(window, message, wparam, lparam);
      if (result != 0) return result;
      params->rgrc[0].top = top;
      if (IsZoomed(window)) {
        // A maximized window hangs over the monitor by its resize border.
        params->rgrc[0].top += ResizeBorder(GetDpiForWindow(window));
      }
      return 0;
    }

    case WM_NCHITTEST: {
      // The left, right and bottom borders are still non-client.
      const LRESULT hit = DefWindowProc(window, message, wparam, lparam);
      if (hit != HTCLIENT) return hit;
      return HitTestClient(window,
                           {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)});
    }

    case WM_GETMINMAXINFO: {
      // Windows wants the whole window: the client area plus the left,
      // right and bottom borders, scaled for this window's DPI.
      const UINT dpi = GetDpiForWindow(window);
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x =
          Scale(kMinClientWidth, dpi) + 2 * ResizeBorderX(dpi);
      info->ptMinTrackSize.y = Scale(kMinClientHeight, dpi) + ResizeBorder(dpi);
      return 0;
    }

    case WM_NCMOUSEMOVE: {
      const bool over = wparam == HTMAXBUTTON;
      if (over && !hovered_) {
        // Ask for WM_NCMOUSELEAVE when the pointer leaves the button.
        TRACKMOUSEEVENT track = {sizeof(track), TME_LEAVE | TME_NONCLIENT,
                                 window, 0};
        TrackMouseEvent(&track);
      }
      SetMaximizeButtonState(over, over && pressed_);
      return std::nullopt;
    }

    case WM_NCMOUSELEAVE:
      SetMaximizeButtonState(false, false);
      return std::nullopt;

    case WM_NCLBUTTONDOWN:
    case WM_NCLBUTTONDBLCLK:
      if (wparam != HTMAXBUTTON) return std::nullopt;
      // Not passed on: the default handling tracks and paints a classic
      // caption button.
      SetMaximizeButtonState(true, true);
      return 0;

    case WM_NCLBUTTONUP:
      if (wparam != HTMAXBUTTON) {
        if (pressed_) SetMaximizeButtonState(hovered_, false);
        return std::nullopt;
      }
      if (pressed_) ToggleMaximize(window);
      SetMaximizeButtonState(true, false);
      return 0;

    case WM_SIZE:
      NotifyMaximized();
      return std::nullopt;
  }
  return std::nullopt;
}

void WindowFrame::SetMaximizeButtonState(bool hovered, bool pressed) {
  if (hovered == hovered_ && pressed == pressed_) return;
  hovered_ = hovered;
  pressed_ = pressed;
  if (!channel_) return;
  channel_->InvokeMethod(
      "maximizeButton",
      std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
          {flutter::EncodableValue("hovered"), flutter::EncodableValue(hovered)},
          {flutter::EncodableValue("pressed"), flutter::EncodableValue(pressed)},
      }));
}

void WindowFrame::NotifyMaximized() {
  if (window_ == nullptr) return;
  const bool maximized = IsZoomed(window_) != 0;
  if (maximized == maximized_) return;
  maximized_ = maximized;
  if (!channel_) return;
  channel_->InvokeMethod("maximized",
                         std::make_unique<flutter::EncodableValue>(maximized));
}

void WindowFrame::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "startDrag") {
    // Answer first: the move loop below runs until the mouse is released.
    result->Success();
    // Flutter holds the mouse capture while its pan gesture runs; hand the
    // drag to Windows as if the caption had been pressed, so dragging to a
    // screen edge snaps like a native window.
    ReleaseCapture();
    POINT cursor;
    GetCursorPos(&cursor);
    SendMessage(window_, WM_NCLBUTTONDOWN, HTCAPTION,
                MAKELPARAM(cursor.x, cursor.y));
  } else if (method == "zoom") {
    ToggleMaximize(window_);
    result->Success();
  } else if (method == "minimize") {
    ShowWindow(window_, SW_MINIMIZE);
    result->Success();
  } else if (method == "close") {
    // Same path as the system close button, so the app's exit handling runs.
    PostMessage(window_, WM_CLOSE, 0, 0);
    result->Success();
  } else if (method == "isMaximized") {
    result->Success(flutter::EncodableValue(IsZoomed(window_) != 0));
  } else if (method == "setMaximizeButtonRect") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("bad-args", "expected a map");
      return;
    }
    const auto right = GetDouble(*args, "right");
    const auto top = GetDouble(*args, "top");
    const auto width = GetDouble(*args, "width");
    const auto height = GetDouble(*args, "height");
    if (!right || !top || !width || !height) {
      result->Error("bad-args", "expected right, top, width and height");
      return;
    }
    button_right_ = *right;
    button_top_ = *top;
    button_width_ = *width;
    button_height_ = *height;
    has_maximize_button_ = true;
    result->Success();
  } else {
    result->NotImplemented();
  }
}
