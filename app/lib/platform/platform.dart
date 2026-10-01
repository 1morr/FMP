import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_android.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_windows.dart';
import 'package:fmp/platform/audio/audio_android.dart';
import 'package:fmp/platform/audio/audio_windows.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/platform/connectivity/connectivity_plus_interfaces.dart';
import 'package:fmp/platform/fonts/fonts_android.dart';
import 'package:fmp/platform/fonts/fonts_windows.dart';
import 'package:fmp/platform/platform_capabilities.dart';

/// 平台層的組裝點（ADR 0009 §決定 1–4）：依平台組出能力宣告與各能力的
/// 實作。整個 App 只有這裡判斷平台；lint `fmp_platform_checks` 擋的是
/// `lib/platform/` 以外。
final class AppPlatform {
  AppPlatform._({
    required this.capabilities,
    this.dataDirectory,
    this.networkInterfaces,
  }) : assert(capabilities.dataDirectory == (dataDirectory != null)),
       assert(capabilities.networkInterfaces == (networkInterfaces != null));

  /// 目前執行的平台。
  factory AppPlatform.current(AppFlavor flavor) =>
      AppPlatform.assemble(defaultTargetPlatform, flavor);

  /// 依 [platform] 組裝。
  ///
  /// 只有 Android 與 Windows 有實作；其他平台驗證前宣告全部為「沒有」、
  /// 也沒有實作檔（ADR 0009 §決定 4）。
  factory AppPlatform.assemble(TargetPlatform platform, AppFlavor flavor) =>
      switch (platform) {
        TargetPlatform.android => AppPlatform._(
          capabilities: const PlatformCapabilities(
            dataDirectory: true,
            singleInstance: false,
            fontFallback: androidFontFallback,
            playback: androidPlaybackSupport,
            networkInterfaces: true,
          ),
          dataDirectory: AndroidAppDataDirectory(
            flavor: flavor,
            applicationSupportPath: () async =>
                (await getApplicationSupportDirectory()).path,
          ),
          networkInterfaces: ConnectivityPlusInterfaces.system(),
        ),
        TargetPlatform.windows => AppPlatform._(
          capabilities: const PlatformCapabilities(
            dataDirectory: true,
            singleInstance: true,
            fontFallback: windowsFontFallback,
            playback: windowsPlaybackSupport,
            networkInterfaces: true,
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
}
