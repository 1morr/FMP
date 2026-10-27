import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_android.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_windows.dart';
import 'package:fmp/platform/app_info/app_info.dart';
import 'package:fmp/platform/app_info/package_info_app_info.dart';
import 'package:fmp/platform/app_restart/app_restart.dart';
import 'package:fmp/platform/app_restart/app_restart_android.dart';
import 'package:fmp/platform/app_restart/app_restart_windows.dart';
import 'package:fmp/platform/audio/audio_android.dart';
import 'package:fmp/platform/audio/audio_windows.dart';
import 'package:fmp/platform/cache_directory/cache_directory.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes_android.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes_windows.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/platform/connectivity/connectivity_plus_interfaces.dart';
import 'package:fmp/platform/files/file_picker_dialogs.dart';
import 'package:fmp/platform/files/files.dart';
import 'package:fmp/platform/legacy_data/legacy_data_locations.dart';
import 'package:fmp/platform/legacy_data/legacy_data_locator.dart';
import 'package:fmp/platform/fonts/fonts_android.dart';
import 'package:fmp/platform/fonts/fonts_windows.dart';
import 'package:fmp/platform/login_webview/flutter_inappwebview_login.dart';
import 'package:fmp/platform/login_webview/login_webview.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';
import 'package:fmp/platform/media_controls/media_controls_android.dart';
import 'package:fmp/platform/media_controls/media_controls_windows.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/platform/secure_storage/flutter_secure_storage_adapter.dart';
import 'package:fmp/platform/secure_storage/secure_storage.dart';
import 'package:fmp/platform/share/share.dart';
import 'package:fmp/platform/share/share_plus_file_sharer.dart';
import 'package:fmp/platform/url_opener/url_launcher_opener.dart';
import 'package:fmp/platform/url_opener/url_opener.dart';
import 'package:fmp/platform/window_chrome/window_chrome.dart';
import 'package:fmp/platform/window_chrome/window_manager_chrome.dart';

/// 平台層的組裝點（ADR 0009 §決定 1–4）：依平台組出能力宣告與各能力的
/// 實作。整個 App 只有這裡判斷平台；lint `fmp_platform_checks` 擋的是
/// `lib/platform/` 以外。
final class AppPlatform {
  AppPlatform._({
    required this.capabilities,
    this.appInfo,
    this.dataDirectory,
    this.networkInterfaces,
    this.cacheDirectory,
    this.secureStorage,
    this.fileDialogs,
    this.loginWebView,
    this.urlOpener,
    this.fileSharer,
    this.mediaControls,
    this.legacyDataLocator,
    this.windowChrome,
    Future<WindowChrome> Function()? windowChromeFactory,
    Future<SystemMediaControls> Function(Log log)? mediaControlsFactory,
    AppRestarter Function(SystemMediaControls? mediaControls)? restarterFactory,
  }) : _mediaControlsFactory = mediaControlsFactory,
       _windowChromeFactory = windowChromeFactory,
       _restarterFactory = restarterFactory,
       assert(capabilities.dataDirectory == (dataDirectory != null)),
       assert(capabilities.dataDirectory == (restarterFactory != null)),
       assert(capabilities.dataDirectory == (legacyDataLocator != null)),
       assert(capabilities.files == (fileDialogs != null)),
       assert(capabilities.loginWebView == (loginWebView != null)),
       assert(capabilities.urlOpener == (urlOpener != null)),
       assert(capabilities.shareFiles == (fileSharer != null)),
       assert(capabilities.networkInterfaces == (networkInterfaces != null)),
       assert((capabilities.cache != null) == (cacheDirectory != null)),
       assert(capabilities.secureStorage == (secureStorage != null)),
       assert(
         capabilities.customTitleBar ==
             (windowChrome != null || windowChromeFactory != null),
       ),
       assert(
         (capabilities.mediaControls != null) ==
             (mediaControls != null || mediaControlsFactory != null),
       );

  /// 目前執行的平台。
  ///
  /// [legacyDirectory] 是 dev 入口 `--fmp-legacy-dir` 的值（`legacyDirectoryPath`）；prod 一律
  /// 不看它。
  factory AppPlatform.current(AppFlavor flavor, {String? legacyDirectory}) =>
      AppPlatform.assemble(
        defaultTargetPlatform,
        flavor,
        legacyDirectory: legacyDirectory,
      );

  /// 依 [platform] 組裝。
  ///
  /// 只有 Android 與 Windows 有實作；其他平台驗證前宣告全部為「沒有」、
  /// 也沒有實作檔（ADR 0009 §決定 4）。
  ///
  /// [androidMediaControls] 取代 Android 系統媒體控制的初始化（測試用，預設是
  /// `AndroidSystemMediaControls.init`）；[windowsMediaControls] 同理（預設是
  /// `WindowsSystemMediaControls.init`）；[windowsWindowChrome] 取代 Windows 自繪標題列的
  /// 初始化（預設是 `WindowManagerChrome.init`）。
  factory AppPlatform.assemble(
    TargetPlatform platform,
    AppFlavor flavor, {
    Future<SystemMediaControls> Function(Log log)? androidMediaControls,
    Future<SystemMediaControls> Function(Log log)? windowsMediaControls,
    Future<WindowChrome> Function()? windowsWindowChrome,
    String? legacyDirectory,
  }) => switch (platform) {
    TargetPlatform.android => AppPlatform._(
      capabilities: const PlatformCapabilities(
        dataDirectory: true,
        singleInstance: false,
        fontFallback: androidFontFallback,
        fontChoices: androidFontChoices,
        playback: androidPlaybackSupport,
        networkInterfaces: true,
        cache: androidCacheSizes,
        secureStorage: true,
        files: true,
        loginWebView: true,
        urlOpener: true,
        restartsItself: false,
        shareFiles: true,
        // 讀任意目錄要 SAF（ADR 0025「之後要注意」）：另立 ADR 前不提供。
        pluginDevTools: false,
        mediaControls: MediaControlsSupport(supportsSeek: true),
      ),
      // 資料目錄在 App 的沙盒裡，路徑不含使用者名稱：沒有要換成 `~` 的家目錄。
      appInfo: PackageInfoAppInfo(
        platform: 'Android',
        osVersion: Platform.operatingSystemVersion,
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
      secureStorage: FlutterSecureStorageAdapter.system(flavor),
      fileDialogs: const FilePickerDialogs(),
      loginWebView: InAppLoginWebView.android(),
      urlOpener: const UrlLauncherOpener(),
      fileSharer: SharePlusFileSharer(),
      mediaControlsFactory:
          androidMediaControls ?? AndroidSystemMediaControls.init,
      restarterFactory: AndroidAppRestarter.forMediaControls,
      legacyDataLocator: androidLegacyDataLocator(
        flavor: flavor,
        devDirectory: legacyDirectory,
        documentsPath: () async =>
            (await getApplicationDocumentsDirectory()).path,
        applicationSupportPath: () async =>
            (await getApplicationSupportDirectory()).path,
      ),
    ),
    TargetPlatform.windows => _windows(
      flavor,
      windowsMediaControls,
      windowsWindowChrome,
      legacyDirectory,
    ),
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => AppPlatform._(
      capabilities: PlatformCapabilities.none,
    ),
  };

  static AppPlatform _windows(
    AppFlavor flavor,
    Future<SystemMediaControls> Function(Log log)? windowsMediaControls,
    Future<WindowChrome> Function()? windowsWindowChrome,
    String? legacyDirectory,
  ) {
    final dataDirectory = WindowsAppDataDirectory(
      flavor: flavor,
      executablePath: Platform.resolvedExecutable,
      roamingAppDataPath: Platform.environment['APPDATA'],
      applicationSupportPath: () async =>
          (await getApplicationSupportDirectory()).path,
      documentsPath: () async =>
          (await getApplicationDocumentsDirectory()).path,
    );
    return AppPlatform._(
      capabilities: const PlatformCapabilities(
        dataDirectory: true,
        singleInstance: true,
        fontFallback: windowsFontFallback,
        fontChoices: windowsFontChoices,
        playback: windowsPlaybackSupport,
        networkInterfaces: true,
        cache: windowsCacheSizes,
        secureStorage: true,
        files: true,
        loginWebView: true,
        urlOpener: true,
        restartsItself: true,
        shareFiles: true,
        pluginDevTools: true,
        // 系統標題列隱藏、App 自繪（ADR 0035 §決定 6）；Windows 的快捷鍵用 Ctrl。
        customTitleBar: true,
        // SMTC 不支援 seek，timeline 也不會自己前進：播放中每 5 秒重推位置。
        mediaControls: MediaControlsSupport(
          supportsSeek: false,
          positionRefresh: Duration(seconds: 5),
        ),
      ),
      appInfo: PackageInfoAppInfo(
        platform: 'Windows',
        osVersion: Platform.operatingSystemVersion,
        homeDirectory: Platform.environment['USERPROFILE'],
      ),
      dataDirectory: dataDirectory,
      networkInterfaces: ConnectivityPlusInterfaces.system(),
      cacheDirectory: CacheDirectory(
        applicationCachePath: _applicationCachePath,
      ),
      secureStorage: FlutterSecureStorageAdapter.system(flavor),
      fileDialogs: const FilePickerDialogs(),
      // WebView2 的使用者資料跟著資料目錄（dev 與 prod 分開、重設資料一起刪）。
      loginWebView: InAppLoginWebView.windows(
        userDataFolder: () async => p.join(
          (await dataDirectory.resolve()).path,
          loginWebViewDirectoryName,
        ),
      ),
      urlOpener: const UrlLauncherOpener(),
      fileSharer: SharePlusFileSharer(),
      windowChromeFactory: windowsWindowChrome ?? WindowManagerChrome.init,
      mediaControlsFactory:
          windowsMediaControls ?? (_) => WindowsSystemMediaControls.init(),
      restarterFactory: (_) => WindowsAppRestarter.system(),
      legacyDataLocator: windowsLegacyDataLocator(
        flavor: flavor,
        devDirectory: legacyDirectory,
        documentsPath: () async =>
            (await getApplicationDocumentsDirectory()).path,
        applicationSupportPath: () async =>
            (await getApplicationSupportDirectory()).path,
        roamingAppDataPath: Platform.environment['APPDATA'],
      ),
    );
  }

  final PlatformCapabilities capabilities;

  /// 版本號與平台名稱；只有能跑主 App 的平台（有資料目錄的 Android、Windows）有，其他
  /// 平台為 `null`。不是能力宣告：沒有畫面依它決定入口，`main()` 沒有資料目錄就不會讀它。
  final AppInfoReader? appInfo;

  /// App 資料目錄；[PlatformCapabilities.dataDirectory] 為假時為 `null`。
  final AppDataDirectory? dataDirectory;

  /// 網路介面；[PlatformCapabilities.networkInterfaces] 為假時為 `null`。
  final NetworkInterfaces? networkInterfaces;

  /// 快取目錄；[PlatformCapabilities.cache] 為 `null` 時為 `null`。只交給快取
  /// 模組（`openCacheStore`），其他地方不拿快取目錄（ADR 0016 §決定 2）。
  final CacheDirectory? cacheDirectory;

  /// 憑證存放；[PlatformCapabilities.secureStorage] 為假時為 `null`。
  final SecureStorage? secureStorage;

  /// 檔案對話框；[PlatformCapabilities.files] 為假時為 `null`。
  final FileDialogs? fileDialogs;

  /// 登入 WebView；[PlatformCapabilities.loginWebView] 為假時為 `null`。
  final LoginWebView? loginWebView;

  /// 網址開啟器；[PlatformCapabilities.urlOpener] 為假時為 `null`。
  final UrlOpener? urlOpener;

  /// 檔案分享；[PlatformCapabilities.shareFiles] 為假時為 `null`。
  final FileSharer? fileSharer;

  /// 找舊版資料（M5 舊資料匯入）；[PlatformCapabilities.dataDirectory] 為假時為 `null`。不是
  /// 能力宣告：沒有畫面依它決定入口，只有 `main()` 在首次啟動時問它。
  final LegacyDataLocator? legacyDataLocator;

  /// 視窗動作（自繪標題列）；[PlatformCapabilities.customTitleBar] 為假，或還沒呼叫
  /// [withWindowChrome] 時為 `null`。
  final WindowChrome? windowChrome;

  /// 系統媒體控制；宣告為沒有，或還沒呼叫 [withMediaControls] 時為 `null`。
  final SystemMediaControls? mediaControls;

  final Future<SystemMediaControls> Function(Log log)? _mediaControlsFactory;
  final Future<WindowChrome> Function()? _windowChromeFactory;
  final AppRestarter Function(SystemMediaControls? mediaControls)?
  _restarterFactory;

  /// 重設資料與還原之後的重啟；沒有資料目錄的平台為 `null`。Android 的實作要收掉系統媒體
  /// 工作階段，所以依 [mediaControls]（[withMediaControls] 之後才有）組出來，每次讀都建一個新的。
  AppRestarter? get restarter => _restarterFactory?.call(mediaControls);

  /// 初始化系統媒體控制，回傳帶著它的平台。`main()` 在開好資料庫之後、`runApp`
  /// 之前呼叫一次。失敗時呼叫 [onFailure]、宣告改為沒有（ADR 0009 §決定 2），
  /// App 照常啟動。
  ///
  /// [log] 交給實作記下初始化之後才發生的錯誤（Android 的 `audio_service`
  /// 非同步錯誤）。
  Future<AppPlatform> withMediaControls({
    required Log log,
    required void Function(Object error, StackTrace stackTrace) onFailure,
  }) async {
    final factory = _mediaControlsFactory;
    if (factory == null) return this;
    SystemMediaControls? controls;
    try {
      controls = await factory(log);
    } on Object catch (error, stackTrace) {
      onFailure(error, stackTrace);
    }
    return AppPlatform._(
      capabilities: controls == null
          ? capabilities.withoutMediaControls()
          : capabilities,
      appInfo: appInfo,
      dataDirectory: dataDirectory,
      networkInterfaces: networkInterfaces,
      cacheDirectory: cacheDirectory,
      secureStorage: secureStorage,
      fileDialogs: fileDialogs,
      loginWebView: loginWebView,
      urlOpener: urlOpener,
      fileSharer: fileSharer,
      mediaControls: controls,
      legacyDataLocator: legacyDataLocator,
      windowChrome: windowChrome,
      windowChromeFactory: _windowChromeFactory,
      restarterFactory: _restarterFactory,
    );
  }

  /// 隱藏系統標題列並取得視窗動作，回傳帶著它的平台。`main()` 在 `runApp` 之前呼叫一次。
  /// 失敗時呼叫 [onFailure]、宣告改為沒有自繪標題列，App 照常啟動（系統標題列留著）。
  Future<AppPlatform> withWindowChrome({
    required void Function(Object error, StackTrace stackTrace) onFailure,
  }) async {
    final factory = _windowChromeFactory;
    if (factory == null) return this;
    WindowChrome? chrome;
    try {
      chrome = await factory();
    } on Object catch (error, stackTrace) {
      onFailure(error, stackTrace);
    }
    return AppPlatform._(
      capabilities: chrome == null
          ? capabilities.withoutCustomTitleBar()
          : capabilities,
      appInfo: appInfo,
      dataDirectory: dataDirectory,
      networkInterfaces: networkInterfaces,
      cacheDirectory: cacheDirectory,
      secureStorage: secureStorage,
      fileDialogs: fileDialogs,
      loginWebView: loginWebView,
      urlOpener: urlOpener,
      fileSharer: fileSharer,
      mediaControls: mediaControls,
      mediaControlsFactory: _mediaControlsFactory,
      legacyDataLocator: legacyDataLocator,
      windowChrome: chrome,
      restarterFactory: _restarterFactory,
    );
  }
}

Future<String> _applicationCachePath() async =>
    (await getApplicationCacheDirectory()).path;
