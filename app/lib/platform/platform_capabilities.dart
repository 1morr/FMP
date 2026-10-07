import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';

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
    required this.networkInterfaces,
    required this.cache,
    this.mediaControls,
  });

  /// 還沒驗證的平台：什麼都沒有。
  static const none = PlatformCapabilities(
    dataDirectory: false,
    singleInstance: false,
    fontFallback: FontFallback.none,
    playback: null,
    networkInterfaces: false,
    cache: null,
    mediaControls: null,
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

  /// 有網路介面的實作（`connectivity/`）：網路層據此判斷 `noInterface`。沒有時
  /// 網路狀態只看請求結果（ADR 0016 §決定 6）。
  final bool networkInterfaces;

  /// 有快取目錄的實作（`cache_directory/`）時的快取大小：磁碟上限的預設與
  /// 記憶體 `ImageCache`（ADR 0016 §決定 3–4）。沒有時為 `null`，`ImageCache`
  /// 維持 Flutter 的預設。
  final CacheSizes? cache;

  /// 有系統媒體控制的實作（`media_controls/`）：通知、鎖定畫面、媒體鍵。沒有
  /// 時為 `null`；實作在啟動時初始化失敗也會改成 `null`（ADR 0009 §決定 2）。
  final MediaControlsSupport? mediaControls;

  /// 同一份宣告，但系統媒體控制改為沒有（初始化失敗時）。
  PlatformCapabilities withoutMediaControls() => PlatformCapabilities(
    dataDirectory: dataDirectory,
    singleInstance: singleInstance,
    fontFallback: fontFallback,
    playback: playback,
    networkInterfaces: networkInterfaces,
    cache: cache,
  );
}
