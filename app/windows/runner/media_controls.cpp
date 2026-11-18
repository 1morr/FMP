#include "media_controls.h"

#include <flutter/standard_method_codec.h>
#include <systemmediatransportcontrolsinterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>

#include <chrono>
#include <string>

namespace {

namespace media = winrt::Windows::Media;

// Posted to the main window from the SMTC event handlers (worker thread).
constexpr UINT kButtonMessage = WM_APP + 0x41;
constexpr UINT kSeekMessage = WM_APP + 0x42;

const flutter::EncodableValue* Find(const flutter::EncodableMap& map,
                                    const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::optional<std::string> GetString(const flutter::EncodableMap& map,
                                     const char* key) {
  const auto* value = Find(map, key);
  if (value == nullptr) return std::nullopt;
  if (const auto* s = std::get_if<std::string>(value)) return *s;
  return std::nullopt;
}

// The standard codec sends small ints as int32 and large ones as int64.
std::optional<int64_t> GetInt(const flutter::EncodableMap& map,
                              const char* key) {
  const auto* value = Find(map, key);
  if (value == nullptr) return std::nullopt;
  if (const auto* i = std::get_if<int32_t>(value)) return *i;
  if (const auto* l = std::get_if<int64_t>(value)) return *l;
  return std::nullopt;
}

bool GetBool(const flutter::EncodableMap& map, const char* key) {
  const auto* value = Find(map, key);
  if (value == nullptr) return false;
  const auto* b = std::get_if<bool>(value);
  return b != nullptr && *b;
}

winrt::Windows::Foundation::TimeSpan Milliseconds(int64_t ms) {
  return std::chrono::milliseconds(ms);
}

}  // namespace

MediaControls::~MediaControls() { Detach(); }

void MediaControls::Attach(HWND window, flutter::BinaryMessenger* messenger) {
  window_ = window;
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "fmp/media", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

void MediaControls::Detach() {
  if (controls_) {
    try {
      controls_.ButtonPressed(button_token_);
      controls_.PlaybackPositionChangeRequested(seek_token_);
    } catch (const winrt::hresult_error&) {
      // The window is going away; nothing to undo.
    }
    controls_ = nullptr;
  }
  channel_ = nullptr;
}

bool MediaControls::EnsureControls() {
  if (controls_) return true;
  try {
    auto interop = winrt::get_activation_factory<
        media::SystemMediaTransportControls,
        ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(interop->GetForWindow(
        window_, winrt::guid_of<media::SystemMediaTransportControls>(),
        winrt::put_abi(controls_)));
    controls_.IsPlayEnabled(true);
    controls_.IsPauseEnabled(true);
    HWND window = window_;
    button_token_ = controls_.ButtonPressed(
        [window](const auto&,
                 const media::SystemMediaTransportControlsButtonPressedEventArgs&
                     args) {
          PostMessage(window, kButtonMessage,
                      static_cast<WPARAM>(args.Button()), 0);
        });
    seek_token_ = controls_.PlaybackPositionChangeRequested(
        [this, window](
            const auto&,
            const media::PlaybackPositionChangeRequestedEventArgs& args) {
          seek_ms_ = std::chrono::duration_cast<std::chrono::milliseconds>(
                         args.RequestedPlaybackPosition())
                         .count();
          PostMessage(window, kSeekMessage, 0, 0);
        });
    return true;
  } catch (const winrt::hresult_error&) {
    controls_ = nullptr;
    return false;
  }
}

std::optional<LRESULT> MediaControls::HandleMessage(UINT message,
                                                    WPARAM wparam,
                                                    LPARAM /* lparam */) {
  if (message == kButtonMessage) {
    switch (static_cast<media::SystemMediaTransportControlsButton>(
        static_cast<int32_t>(wparam))) {
      case media::SystemMediaTransportControlsButton::Play:
        SendCommand("play", std::nullopt);
        break;
      case media::SystemMediaTransportControlsButton::Pause:
        SendCommand("pause", std::nullopt);
        break;
      case media::SystemMediaTransportControlsButton::Next:
        SendCommand("next", std::nullopt);
        break;
      case media::SystemMediaTransportControlsButton::Previous:
        SendCommand("previous", std::nullopt);
        break;
      default:
        break;
    }
    return 0;
  }
  if (message == kSeekMessage) {
    SendCommand("seek", seek_ms_.load());
    return 0;
  }
  return std::nullopt;
}

void MediaControls::SendCommand(const char* name,
                                std::optional<int64_t> position_ms) {
  if (!channel_) return;
  flutter::EncodableMap arguments = {
      {flutter::EncodableValue("name"), flutter::EncodableValue(name)},
  };
  if (position_ms) {
    arguments[flutter::EncodableValue("positionMs")] =
        flutter::EncodableValue(*position_ms);
  }
  channel_->InvokeMethod(
      "command", std::make_unique<flutter::EncodableValue>(arguments));
}

void MediaControls::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = call.method_name();
  if (method != "metadata" && method != "state" && method != "clear") {
    result->NotImplemented();
    return;
  }
  if (!EnsureControls()) {
    result->Error("unavailable", "Windows gave no media controls");
    return;
  }
  const auto* arguments =
      std::get_if<flutter::EncodableMap>(call.arguments());
  try {
    if (method == "clear") {
      Clear();
    } else if (arguments == nullptr) {
      result->Error("bad_arguments", "Expected a map");
      return;
    } else if (method == "metadata") {
      ShowMetadata(*arguments);
    } else {
      ShowState(*arguments);
    }
    result->Success();
  } catch (const winrt::hresult_error& error) {
    result->Error("smtc", winrt::to_string(error.message()));
  }
}

void MediaControls::ShowMetadata(const flutter::EncodableMap& arguments) {
  auto updater = controls_.DisplayUpdater();
  // Fields left unset would keep the previous track's values (fact W6).
  updater.ClearAll();
  updater.Type(media::MediaPlaybackType::Music);
  auto music = updater.MusicProperties();
  music.Title(winrt::to_hstring(GetString(arguments, "title").value_or("")));
  music.Artist(winrt::to_hstring(GetString(arguments, "artist").value_or("")));
  if (auto thumbnail = GetString(arguments, "thumbnail")) {
    updater.Thumbnail(
        winrt::Windows::Storage::Streams::RandomAccessStreamReference::
            CreateFromUri(winrt::Windows::Foundation::Uri(
                winrt::to_hstring(*thumbnail))));
  }
  updater.Update();
  controls_.IsEnabled(true);
}

void MediaControls::ShowState(const flutter::EncodableMap& arguments) {
  const auto status = GetString(arguments, "status").value_or("paused");
  controls_.PlaybackStatus(status == "playing"
                               ? media::MediaPlaybackStatus::Playing
                           : status == "changing"
                               ? media::MediaPlaybackStatus::Changing
                               : media::MediaPlaybackStatus::Paused);
  controls_.IsPreviousEnabled(GetBool(arguments, "canPrevious"));
  controls_.IsNextEnabled(GetBool(arguments, "canNext"));

  const int64_t duration = GetInt(arguments, "durationMs").value_or(0);
  media::SystemMediaTransportControlsTimelineProperties timeline;
  timeline.StartTime(Milliseconds(0));
  timeline.MinSeekTime(Milliseconds(0));
  timeline.EndTime(Milliseconds(duration));
  timeline.MaxSeekTime(Milliseconds(duration));
  timeline.Position(Milliseconds(GetInt(arguments, "positionMs").value_or(0)));
  controls_.UpdateTimelineProperties(timeline);
}

void MediaControls::Clear() {
  auto updater = controls_.DisplayUpdater();
  updater.ClearAll();
  updater.Update();
  controls_.PlaybackStatus(media::MediaPlaybackStatus::Closed);
  controls_.IsEnabled(false);
}
