import 'dart:async';

import 'package:fmp/playback/backends/just_audio_backend.dart';

import 'start_time.dart';

/// 票 12 的對照實驗，只在 macOS、iOS 跑：同 `start_time_run.dart`，但 AVPlayer
/// 直接播串流網址、不包成 HLS（ADR 0040 之前的做法），看 M0 驗收時 macOS
/// 點下到出聲約 15 秒是不是直接播單檔 fragmented MP4 造成的（事實 M14）。
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/start_direct_run.dart
///
/// 只挑 1 小時內的結果：14 小時的那首直接播時 AVPlayer 一開就回 -1008
/// ，3 小時的那首 45 秒沒出聲、被看門狗切掉（2026-11-18 試過），量不到。
void main() => startTimeScenario(
  maxLength: const Duration(hours: 1),
  wrapAudioBackend: (platform) {
    unawaited(platform.dispose());
    return JustAudioBackend();
  },
);
