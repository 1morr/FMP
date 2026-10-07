import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_android.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_windows.dart';
import 'package:fmp/platform/audio/audio_android.dart';
import 'package:fmp/platform/audio/audio_windows.dart';
import 'package:fmp/platform/cache_directory/cache_directory.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes_android.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes_windows.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/platform/connectivity/connectivity_plus_interfaces.dart';
import 'package:fmp/platform/fonts/fonts_android.dart';
import 'package:fmp/platform/fonts/fonts_windows.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';
import 'package:fmp/platform/media_controls/media_controls_android.dart';
import 'package:fmp/platform/media_controls/media_controls_windows.dart';
import 'package:fmp/platform/platform_capabilities.dart';

/// 平台層的組裝點（ADR 0009 §決定 1–4）：依平台組出能力宣告與各能力的
/// 實作。整個 App 只有這裡判斷平台；lint `fmp_platform_checks` 擋的是
/// `lib/platform/` 以外。
final class AppPlatform {
  AppPlatform._({
    required this.capabilities,
    this.dataDirectory,
    this.networkInterfaces,
    this.cacheDirectory,
    this.mediaControls,
    Future<SystemMediaControls> Function()? mediaControlsFactory,
  }) : _mediaControlsFactory = mediaControlsFactory,
       assert(capabilities.dataDirectory == (dataDirectory != null)),
       assert(capabilities.networkInterfaces == (networkInterfaces != null)),
       assert((capabilities.cache != null) == (cacheDirectory != null)),
       assert(
         (capabilities.mediaControls != null) ==
             (mediaControls != null || mediaControlsFactory != null),
       );

  /// 目前執行的平台。
  factory AppPlatform.current(AppFlavor flavor) =>
      AppPlatform.assemble(defaultTargetPlatform, flavor);

  /// 依 [platform] 組裝。
  ///
  /// 只有 Android 與 Windows 有實作；其他平台驗證前宣告全部為「沒有」、
  /// 也沒有實作檔（ADR 0009 §決定 4）。
  ///
  /// [androidMediaControls] 取代 Android 系統媒體控制的初始化（測試用，預設是
  /// `AndroidSystemMediaControls.init`）；[windowsMediaControls] 同理（預設是
  /// `WindowsSystemMediaControls.init`）。
  factory AppPlatform.assemble(
    TargetPlatform platform,
    AppFlavor flavor, {
    Future<SystemMediaControls> Function()? androidMediaControls,
    Future<SystemMediaControls> Function()? windowsMediaControls,
  }) => switch (platform) {
    TargetPlatform.android => AppPlatform._(
      capabilities: const PlatformCapabilities(
        dataDirectory: true,
        singleInstance: false,
        fontFallback: androidFontFallback,
        playback: androidPlaybackSupport,
        networkInterfaces: true,
        cache: androidCacheSizes,
        mediaControls: MediaControlsSupport(supportsSeek: true),
      ),
      dataDirectory: AndroidAppDataDirectory(
        flavor: flavor,
        applicationSupportPath: () async =>
            (await getApplicationSupportDirectory()).path,
      ),
      networkInterfaces: ConnectivityPlusInterfaces.system(),
      cacheDirectory: CacheDirectory(
        applicationCachePath: _applicationCachePath,
      ),
      mediaControlsFactory:
          androidMediaControls ?? AndroidSystemMediaControls.init,
    ),
    TargetPlatform.windows => AppPlatform._(
      capabilities: const PlatformCapabilities(
        dataDirectory: true,
        singleInstance: true,
        fontFallback: windowsFontFallback,
        playback: windowsPlaybackSupport,
        networkInterfaces: true,
        cache: windowsCacheSizes,
        // SMTC 不支援 seek，timeline 也不會自己前進：播放中每 5 秒重推位置。
        mediaControls: MediaControlsSupport(
          supportsSeek: false,
          positionRefresh: Duration(seconds: 5),
        ),
      ),
      dataDirectory: WindowsAppDataDirectory(
        flavor: flavor,
        executablePath: Platform.resolvedExecutable,
        roamingAppDataPath: Platform.environment['APPDATA'],
        applicationSupportPath: () async =>
            (await getApplicationSupportDirectory()).path,
        documentsPath: () async =>
            (await getApplicationDocumentsDirectory()).path,
      ),
      networkInterfaces: ConnectivityPlusInterfaces.system(),
      cacheDirectory: CacheDirectory(
        applicationCachePath: _applicationCachePath,
      ),
      mediaControlsFactory:
          windowsMediaControls ?? WindowsSystemMediaControls.init,
    ),
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => AppPlatform._(
      capabilities: PlatformCapabilities.none,
    ),
  };

  final PlatformCapabilities capabilities;

  /// App 資料目錄；[PlatformCapabilities.dataDirectory] 為假時為 `null`。
  final AppDataDirectory? dataDirectory;

  /// 網路介面；[PlatformCapabilities.networkInterfaces] 為假時為 `null`。
  final NetworkInterfaces? networkInterfaces;

  /// 快取目錄；[PlatformCapabilities.cache] 為 `null` 時為 `null`。只交給快取
  /// 模組（`openCacheStore`），其他地方不拿快取目錄（ADR 0016 §決定 2）。
  final CacheDirectory? cacheDirectory;

  /// 系統媒體控制；宣告為沒有，或還沒呼叫 [withMediaControls] 時為 `null`。
  final SystemMediaControls? mediaControls;

  final Future<SystemMediaControls> Function()? _mediaControlsFactory;

  /// 初始化系統媒體控制，回傳帶著它的平台。`main()` 在開好資料庫之後、`runApp`
  /// 之前呼叫一次。失敗時呼叫 [onFailure]、宣告改為沒有（ADR 0009 §決定 2），
  /// App 照常啟動。
  Future<AppPlatform> withMediaControls({
    required void Function(Object error, StackTrace stackTrace) onFailure,
  }) async {
    final factory = _mediaControlsFactory;
    if (factory == null) return this;
    SystemMediaControls? controls;
    try {
      controls = await factory();
    } on Object catch (error, stackTrace) {
      onFailure(error, stackTrace);
    }
    return AppPlatform._(
      capabilities: controls == null
          ? capabilities.withoutMediaControls()
          : capabilities,
      dataDirectory: dataDirectory,
      networkInterfaces: networkInterfaces,
      cacheDirectory: cacheDirectory,
      mediaControls: controls,
    );
  }
}

Future<String> _applicationCachePath() async =>
    (await getApplicationCacheDirectory()).path;
