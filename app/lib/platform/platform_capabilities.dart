import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/platform/fonts/fonts.dart';

/// 目前平台的能力宣告。`main()` 以 `AppPlatform` 組出的宣告 override；沒
/// override 就讀會拋錯。
final platformCapabilitiesProvider = Provider<PlatformCapabilities>(
  (ref) => throw UnimplementedError(
    'platformCapabilitiesProvider is overridden by main()',
  ),
);

/// 目前平台有哪些能力（ADR 0009 §決定 2）。每個平台一份，由
/// `platform.dart` 組出；UI 依它決定是否顯示入口。
///
/// 只列已經有實作的能力：新能力連同實作一起加欄位（ADR 0009 §決定 4），
/// 不先為之後的里程碑預留。
@immutable
final class PlatformCapabilities {
  const PlatformCapabilities({
    required this.dataDirectory,
    required this.singleInstance,
    required this.fontFallback,
    required this.playback,
  });

  /// 還沒驗證的平台：什麼都沒有。
  static const none = PlatformCapabilities(
    dataDirectory: false,
    singleInstance: false,
    fontFallback: FontFallback.none,
    playback: null,
  );

  /// 有 App 資料目錄的實作（`app_data_directory/`）。沒有時 `main()` 不啟動
  /// 資料層，只顯示「此平台尚未支援」。
  final bool dataDirectory;

  /// 原生端保證只跑一個實例、再次啟動時把第一個帶到前景。Windows 由
  /// `windows/runner/main.cpp` 的 mutex 實作（`app/AGENTS.md` § App 身分），
  /// Dart 端只宣告。
  final bool singleInstance;

  /// 各介面語言的 CJK 字型 fallback（ADR 0024 §決定 2）。
  final FontFallback fontFallback;

  /// 播放用的後端與可播格式（ADR 0018 §決定 3）；沒有播放的實作時為 `null`。
  final PlaybackSupport? playback;
}
