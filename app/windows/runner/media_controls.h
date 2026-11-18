#ifndef RUNNER_MEDIA_CONTROLS_H_
#define RUNNER_MEDIA_CONTROLS_H_

// C++/WinRT needs <unknwn.h> before its headers for classic COM interop
// (ISystemMediaTransportControlsInterop).
#include <windows.h>
#include <unknwn.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <winrt/Windows.Media.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <optional>

// The Windows system media controls (SMTC: the media overlay and the media
// keys) for the main window. smtc_windows is not used because its
// flutter_rust_bridge version clashes with fjs (fact W7).
//
// Built only with the CMake option FMP_WINDOWS_SMTC (off by default until it
// has been compiled and tried on Windows); without it the channel has no
// handler and Dart runs without system media controls.
//
// The "fmp/media" channel (lib/platform/windows_media_controls.dart):
//
// - Dart -> runner: "available" answers true; "metadata" {title, artist,
//   thumbnail?} clears the display and sets it again (fact W6); "state"
//   {status, positionMs, durationMs?, canPrevious, canNext} sets the
//   playback status, the enabled buttons and the timeline; "clear" empties
//   and disables the controls.
// - Runner -> Dart: "command" {name, positionMs?} with name play, pause,
//   next, previous or seek.
//
// SMTC raises its events on a worker thread; they are posted to the main
// window and sent to Dart from HandleMessage, on the platform thread.
//
// ASCII only: the runner builds with /WX, and non-ASCII bytes trip C4819 on
// CJK locales.
class MediaControls {
 public:
  MediaControls() = default;
  ~MediaControls();

  MediaControls(const MediaControls&) = delete;
  MediaControls& operator=(const MediaControls&) = delete;

  // Opens the channel for |window|. The SMTC itself is created on the first
  // call from Dart.
  void Attach(HWND window, flutter::BinaryMessenger* messenger);

  // Stops listening to the SMTC and closes the channel. Safe to call more
  // than once.
  void Detach();

  // Handles the messages posted from the SMTC events; std::nullopt for any
  // other message.
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Gets the SMTC of the window and subscribes to its events; false when
  // Windows does not give one.
  bool EnsureControls();

  void ShowMetadata(const flutter::EncodableMap& arguments);
  void ShowState(const flutter::EncodableMap& arguments);
  void Clear();

  void SendCommand(const char* name, std::optional<int64_t> position_ms);

  HWND window_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  winrt::Windows::Media::SystemMediaTransportControls controls_{nullptr};
  winrt::event_token button_token_{};
  winrt::event_token seek_token_{};

  // The last position the overlay asked to seek to, in milliseconds.
  std::atomic<int64_t> seek_ms_{0};
};

#endif  // RUNNER_MEDIA_CONTROLS_H_
