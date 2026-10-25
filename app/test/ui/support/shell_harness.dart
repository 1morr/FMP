import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app_material.dart';
import 'package:fmp/app/app_scope.dart';
import 'package:fmp/app/data_reset.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/settings/appearance_settings.dart';
import 'package:fmp/domain/developer.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/app_info/app_info.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/platform/files/files.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/login_webview/login_webview.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/platform/share/share.dart';
import 'package:fmp/platform/url_opener/url_opener.dart';
import 'package:fmp/playback/playback_controller.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_session.dart';
import 'package:fmp/playback/stream_resolver.dart';
import 'package:fmp/plugins/plugin_artwork.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/settings/developer_settings.dart';
import 'package:fmp/settings/playback_settings.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/search/search_state.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:fmp/ui/toast/toast_host.dart';
import 'package:fmp/ui/errors/error_detail_page.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/app/root_navigator.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_audio_backend.dart';
import '../../playback/fake_source_plugin.dart';
import '../../support/fake_network_interfaces.dart';
import '../../support/memory_database.dart';

/// 一首搜尋結果（插件 `fmp-test`）。
TrackSummary summary(
  String id, {
  Duration? duration,
  List<Artwork> artwork = const [],
  int? partCount,
}) => TrackSummary(
  sourceTypeId: 'fmp-test',
  sourceId: id,
  title: 'Song $id',
  uploader: 'Uploader $id',
  duration: duration ?? const Duration(minutes: 3, seconds: 5),
  artwork: artwork,
  partCount: partCount,
);

/// 外殼與頁面的測試環境：可以搜尋、可以解析的假插件，假後端上的真
/// `PlaybackController`，記憶體資料庫、[Toaster] 與有介面的假網路介面
/// （[interfaces]）。介面語言是英文（測試的系統語言 `en_US`）。
String? _noUnavailableSource(Ref ref, String pluginId) => null;

final class ShellHarness {
  ShellHarness({
    FutureOr<SearchPage> Function(SearchQuery query)? onSearch,
    List<SourcePlugin>? sources,
    this.cacheStore,
    FakeOutputDevices? outputDevices,
    this.outputDeviceSelection = false,
    this.artworkManager,
    this.database,
    this.fileDialogs,
    this.urlOpener,
    this.fileSharer,
    this.redactor,
    this.loginWebView,
    this.pluginDevTools = false,
    this.cacheUnavailable = false,
    this.registrySources = false,
    this.registryOfSources = false,
    bool live = false,
    bool mix = false,
    bool multiPart = false,
    bool trackDetail = false,
    bool libraryRead = false,
    bool libraryWrite = false,
    this.secureStorage = false,
    this.restartsItself = false,
    this.fontChoices = const [],
    this.dataReset,
    this.sourceUnavailable = _noUnavailableSource,
    this.flavor = AppFlavor.dev,
    this.buildLogLevel = LogLevelSetting.info,
    this.extraOverrides = const [],
    Log? log,
  }) : log = log ?? Log(redactor: Redactor(), minimumLevel: LogLevel.warning),
       backend = FakeAudioBackend(
         durationOf: (_) => const Duration(minutes: 3),
         outputDevices: outputDevices,
       ),
       plugin = FakeSourcePlugin(
         (request) => [candidate('${request.sourceId}.m4a')],
         name: 'Test Source',
         live: live,
         mix: mix,
         multiPart: multiPart,
         trackDetail: trackDetail,
         libraryRead: libraryRead,
         libraryWrite: libraryWrite,
         onSearch:
             onSearch ??
             (query) => SearchPage(
               items: [
                 for (final id in ['a', 'b', 'c']) summary(id),
               ],
               hasMore: false,
             ),
       ) {
    this.sources = sources ?? [plugin];
    controller = PlaybackController(
      session: PlaybackSession(
        backend: backend,
        resolver: StreamResolver(
          plugin: (id) => id == plugin.manifest.id ? plugin : null,
          formats: const [PlayableFormat('mp4', 'aac')],
          preferences: () => _readStreamPreferences(),
          log: this.log,
        ),
        log: this.log,
      ),
      log: this.log,
      // 和 App 的組裝點一樣讀「播放」設定（記憶體資料庫裡的值）與網路狀態；
      // 解析時的偏好也是（見 resolver 的 preferences）。
      temporaryReturnSettings: () => _readReturnSettings(),
      skipPreviewClips: () => _readSkipPreviewClips(),
      networkStatus: () => _readNetworkStatus(),
      networkStatusChanges: _networkChanges.stream,
      // 插件清單在這個 harness 裡不變。
      pluginChanges: const Stream.empty(),
      preferredOutputDevice: () => _readPreferredOutputDevice(),
      saveOutputDevice: (device) => _saveOutputDevice(device),
      registerLiveInfoJob: (_, run) => liveInfoJob = run,
      unregisterLiveInfoJob: () => liveInfoJob = null,
    );
    toaster = Toaster(
      log: this.log,
      translations: AppLocale.en.buildSync,
      sourceName: (_) => null,
      developerMode: () => toastDeveloperMode,
      openErrorDetail: (record) {
        final navigator = navigatorKey.currentState;
        if (navigator != null) unawaited(openErrorDetail(navigator, record));
      },
    );
    addTearDown(toaster.dispose);
  }

  /// 封面的 cache manager（`artworkCacheManagerProvider` 的 override）；不給就不 override，
  /// 封面都是佔位圖。
  final BaseCacheManager? artworkManager;

  /// 設定頁「網路」組用的快取庫；不給就是還沒開好（用量不顯示）。
  final CacheStore? cacheStore;

  /// 快取庫開不起來（`cacheStoreProvider` 是錯誤）：移除插件時略過快取那一步，不會
  /// 等一個永遠開不好的快取庫。
  final bool cacheUnavailable;

  /// 主資料庫；不給就是新的記憶體資料庫。要和別的元件（插件的載入器）共用時給。
  final AppDatabase? database;

  /// 平台的檔案對話框；給了平台就宣告 `files`。
  final FileDialogs? fileDialogs;

  /// 平台的網址開啟器；`null` 是沒有這個能力（錯誤詳細頁只複製並顯示網址）。
  final UrlOpener? urlOpener;

  /// 平台的檔案分享；給了平台就宣告 `shareFiles`（診斷包的「分享」依它出現）。
  final FileSharer? fileSharer;

  /// 遮蔽函式；錯誤詳細頁讀它（`redactorProvider`）。不給就不 override：用 `PluginHarness` 的
  /// 測試（插件頁）自己經 `extraOverrides` 給，同一個 provider 不能 override 兩次。
  final Redactor? redactor;

  /// 平台的登入 WebView；給了平台就宣告 `loginWebView`。
  final LoginWebView? loginWebView;

  /// 平台宣告插件開發工具（Debug 頁的「插件開發」區塊依它出現）。
  final bool pluginDevTools;

  /// 搜尋的音源讀真的插件清單（`searchSourcesProvider` 不 override）：要看安裝、停用
  /// 之後搜尋頁怎麼變時用（首次啟動引導）。
  final bool registrySources;

  /// 插件清單（`pluginRegistryProvider`）就是 [sources]：電台（以網址新增、狀態工作）要
  /// 向插件清單要插件。不和 [registrySources] 一起用。
  final bool registryOfSources;

  /// 收聽直播時控制器登記的 `live-info` 更新（排程器每分鐘跑的那一個）；不在收聽時為
  /// `null`。測試直接呼叫它，當作排程器到期。
  Future<void> Function()? liveInfoJob;

  /// 平台宣告有 secure storage（`PlatformCapabilities.secureStorage`）：帳號頁的登入
  /// 按鈕依它出現。實作本身由 [extraOverrides] 的 `credentialStoreProvider` 給。
  final bool secureStorage;

  /// 平台宣告重設資料、還原之後 App 會自己重啟（Windows）；預設是 Android 的行為（要手動重開）。
  final bool restartsItself;

  /// 平台宣告的外觀設定字型清單（不含系統預設）；預設沒有。
  final List<String> fontChoices;

  /// Debug 頁的備份、還原與重設（`dataResetProvider`）；不給就不 override，用到會讀到真的
  /// 實作所需的 provider 而拋錯。
  final DataReset? dataReset;

  /// `sourceUnavailableProvider` 的值（音源停用或未安裝的原因）；預設沒有不可用的音源。
  final String? Function(Ref ref, String pluginId) sourceUnavailable;

  /// 這個建置的 flavor：「開發者」組的預設跟著它（dev 開、prod 關）。
  final AppFlavor flavor;

  /// 這個建置的預設 log 層級（`buildLogLevelProvider`）。`flutter test` 永遠是 debug build，
  /// 所以固定下來：預設是 release 的 info，要看 debug build 給 [LogLevelSetting.debug]。
  final LogLevelSetting buildLogLevel;

  /// 加在最後的 override（要和上面不重複）。
  final List<Override> extraOverrides;

  /// 「關於」與 Debug 頁概覽讀的版本與平台。家目錄是資料目錄的上層，概覽顯示成 `~/…`。
  static const appInfo = AppInfo(
    version: '1.2.3',
    platform: 'Windows',
    osVersion: 'Windows 11 (test)',
    homeDirectory: '/home/tester',
  );

  /// 資料目錄（Debug 頁的概覽顯示它）；測試不在這裡讀寫檔案。
  static final dataDirectory = Directory('/home/tester/fmp-dev');

  final FakeSourcePlugin plugin;
  late final List<SourcePlugin> sources;

  /// 平台宣告能選輸出裝置（Windows）；播放列的輸出裝置入口依它出現。後端的裝置
  /// 清單另由 `outputDevices` 給。
  final bool outputDeviceSelection;

  /// 曲目長 3 分鐘：測試期間不會自己播完。
  final FakeAudioBackend backend;

  /// 門面；不給就是只記警告以上、沒有 log 檔的記憶體門面。Debug 頁測試要 log 檔時給自己的。
  final Log log;
  late final PlaybackController controller;
  late final Toaster toaster;

  /// 根 Navigator 的 key（提示的「詳細」「回報」用它開錯誤詳細頁，和 `FmpApp` 一樣）。
  final navigatorKey = GlobalKey<NavigatorState>();

  /// 提示當成開發者模式開著（錯誤提示附「詳細」）。和設定裡的開發者模式無關：後者在 dev
  /// flavor 預設就開，這個預設關，只有要測提示的動作時才開。
  bool toastDeveloperMode = false;

  /// 由 [overrides] 的 `playbackControllerProvider` 接上 provider。
  late TemporaryReturnSettings Function() _readReturnSettings;
  late bool Function() _readSkipPreviewClips;
  late StreamPreferences Function() _readStreamPreferences;
  late NetworkStatus Function() _readNetworkStatus;
  // 裝置清單一建好就讀記住的裝置：可能早於 provider 把它們接上（清單在後端建構時就
  // 已就緒），所以有預設值。
  Future<String?> Function() _readPreferredOutputDevice = () async => null;
  Future<void> Function(OutputDevice? device) _saveOutputDevice = (_) async {};
  final _networkChanges = StreamController<NetworkStatus>.broadcast();
  final interfaces = FakeNetworkInterfaces();

  List<Override> get overrides => [
    appDatabaseProvider.overrideWithValue(database ?? memoryDatabase()),
    logProvider.overrideWithValue(log),
    toasterProvider.overrideWithValue(toaster),
    // 同 `FmpApp`：提示的「詳細」經根 Navigator 開頁面或對話框。
    rootNavigatorKeyProvider.overrideWithValue(navigatorKey),
    appFlavorProvider.overrideWithValue(flavor),
    buildLogLevelProvider.overrideWithValue(buildLogLevel),
    appInfoProvider.overrideWithValue(appInfo),
    dataDirectoryProvider.overrideWithValue(dataDirectory),
    if (!registrySources)
      searchSourcesProvider.overrideWithValue(AsyncData(sources)),
    if (registryOfSources)
      pluginRegistryProvider.overrideWithBuild(
        (ref, notifier) => {
          for (final source in sources) source.manifest.id: source,
        },
      ),
    networkInterfacesProvider.overrideWithValue(interfaces),
    fileDialogsProvider.overrideWithValue(fileDialogs),
    urlOpenerProvider.overrideWithValue(urlOpener),
    fileSharerProvider.overrideWithValue(fileSharer),
    if (redactor != null) redactorProvider.overrideWithValue(redactor!),
    if (dataReset != null) dataResetProvider.overrideWithValue(dataReset!),
    loginWebViewProvider.overrideWithValue(loginWebView),
    // 「網路」設定的預設上限讀平台宣告：128 MiB。
    platformCapabilitiesProvider.overrideWithValue(
      PlatformCapabilities(
        dataDirectory: true,
        singleInstance: false,
        secureStorage: secureStorage,
        fontFallback: FontFallback.none,
        fontChoices: fontChoices,
        playback: outputDeviceSelection
            ? const PlaybackSupport(
                backend: AudioBackendKind.mediaKit,
                formats: [PlayableFormat('mp4', 'aac')],
                outputDeviceSelection: true,
              )
            : null,
        networkInterfaces: false,
        files: fileDialogs != null,
        urlOpener: urlOpener != null,
        shareFiles: fileSharer != null,
        pluginDevTools: pluginDevTools,
        restartsItself: restartsItself,
        loginWebView: loginWebView != null,
        cache: const CacheSizes(
          defaultLimitMebibytes: 128,
          memoryImages: 1,
          memoryImageMebibytes: 1,
        ),
      ),
    ),
    pluginNameProvider.overrideWith(
      (ref, pluginId) =>
          pluginId == plugin.manifest.id ? plugin.manifest.name : null,
    ),
    sourceUnavailableProvider.overrideWith(
      (ref, pluginId) => sourceUnavailable(ref, pluginId),
    ),
    if (artworkManager != null)
      artworkCacheManagerProvider.overrideWith((ref, _) => artworkManager),
    cacheStoreProvider.overrideWith(
      (ref) => cacheUnavailable
          ? Future<CacheStore>.error(StateError('no cache store in the test'))
          : cacheStore ?? Completer<CacheStore>().future,
    ),
    // 樹拆掉時停掉後端的計時器（測試結束時檢查沒有留下的計時器）。
    playbackControllerProvider.overrideWith((ref) {
      ref.listen(temporaryReturnSettingsProvider, (_, _) {});
      ref.listen(skipPreviewClipsProvider, (_, _) {});
      ref.listen(streamPreferencesProvider, (_, _) {});
      ref.listen(networkStatusProvider, (_, status) {
        _networkChanges.add(status);
      });
      _readReturnSettings = () => ref.read(temporaryReturnSettingsProvider);
      _readSkipPreviewClips = () => ref.read(skipPreviewClipsProvider);
      _readStreamPreferences = () => ref.read(streamPreferencesProvider);
      _readNetworkStatus = () => ref.read(networkStatusProvider);
      _readPreferredOutputDevice = () async =>
          (await ref.read(playbackPreferencesProvider.future)).outputDevice?.id;
      _saveOutputDevice = (device) => ref
          .read(playbackPreferencesProvider.notifier)
          .setOutputDevice(device);
      ref.onDispose(() {
        unawaited(controller.dispose());
        unawaited(backend.dispose());
      });
      return controller;
    }),
    ...extraOverrides,
  ];

  /// 以 [size] 的視窗開 App 的外殼（和 `FmpApp` 同一份 `MaterialApp` 設定），再點導覽的
  /// [at]（預設是搜尋：多數外殼測試從搜尋頁開始；App 本身開在首頁，給 `home` 就不點）。
  ///
  /// 視窗 >= 840 時外殼右側有「正在播放」面板，內容區因此變窄；測的是頁面本身的版面時給
  /// [collapsePanel]，就像使用者收起了面板。
  Future<void> pumpShell(
    WidgetTester tester, {
    Size size = const Size(1000, 700),
    Brightness brightness = Brightness.light,
    bool collapsePanel = false,
    ShellDestination at = ShellDestination.search,
  }) async {
    await pumpApp(tester, const AppShell(), size: size, brightness: brightness);
    if (at != ShellDestination.values.first) await open(tester, at);
    if (!collapsePanel) return;
    await tester.runAsync(
      () =>
          container(tester)
              .read(layoutStateRepositoryProvider)
              .write(panelExpanded: false),
    );
    await loadSettings(tester);
  }

  /// 點導覽的 [destination]（三種導覽元件都認得）。
  Future<void> open(WidgetTester tester, ShellDestination destination) async {
    await tester.tap(navigationItem(destination));
    await tester.pump();
  }

  /// 切到佇列目的地（Ctrl+Q 與導覽項是同一條路）。
  Future<void> openQueue(WidgetTester tester) async {
    await open(tester, ShellDestination.queue);
    await tester.pumpAndSettle();
  }

  /// 導覽元件裡 [destination] 那一項的文字（英文介面）。
  static Finder navigationItem(ShellDestination destination) => find.descendant(
    of: find.byWidgetPredicate(
      (widget) =>
          widget is NavigationBar ||
          widget is NavigationRail ||
          widget is NavigationDrawer,
    ),
    matching: find.text(switch (destination) {
      ShellDestination.home => 'Home',
      ShellDestination.search => 'Search',
      ShellDestination.library => 'Library',
      ShellDestination.queue => 'Queue',
      ShellDestination.radio => 'Radio',
      ShellDestination.settings => 'Settings',
    }),
  );

  /// 從音樂庫頂端的「歷史」開歷史頁（音樂庫的巢狀導覽裡）。
  Future<void> openHistory(WidgetTester tester) async {
    await open(tester, ShellDestination.library);
    await tester.tap(find.widgetWithText(ListTile, 'History'));
    await tester.pumpAndSettle();
  }

  /// 以 [size] 的視窗、App 的 `MaterialApp` 設定與 `ToastHost` 開 [home]。
  Future<void> pumpApp(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(1000, 700),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 測試失敗時 flutter_test 不拆樹（`_runTestBody` 只在沒有錯誤時換成空樹）：樹上的 provider
    // 還掛著資料庫的查詢，關資料庫（`memoryDatabase` 的 tearDown）就永遠等不到，測試卡到逾時。
    // tearDown 照登記的反序跑，這個在資料庫的之前：先拆樹。成功的測試樹已經拆了，這裡只是再換一次。
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      // 和 App 一樣關掉 Riverpod 的自動重試（appProviderScope）。
      appProviderScope(
        overrides: overrides,
        child: Consumer(
          builder: (context, ref, _) => fmpMaterialApp(
            title: 'FMP Dev',
            locale: LocaleSetting.en,
            themeMode: themeModeOf(switch (brightness) {
              Brightness.light => ThemeModeSetting.light,
              Brightness.dark => ThemeModeSetting.dark,
            }),
            fontFamilyFallback: const [],
            // 和 FmpApp 一樣讓主題跟著外觀設定的主題色與字型。
            seedColor: ref.watch(
              appearanceProvider.select((a) => a.value?.stored.seedColor),
            ),
            fontFamily: ref.watch(
              appearanceProvider.select((a) => a.value?.fontFamily),
            ),
            navigatorKey: navigatorKey,
            navigatorObservers: [ref.watch(toastRouteObserverProvider)],
            builder: (context, navigator) =>
                WindowClassScope(child: ToastHost(child: navigator!)),
            home: home,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 目前的 [ProviderContainer]（`pumpApp` 之後）。
  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ToastHost)));

  /// 把 [tracks] 加進佇列，從第 [index] 首開始播（像在佇列裡點了那一首）。
  Future<void> play(
    WidgetTester tester,
    List<TrackSummary> tracks, {
    int index = 0,
  }) async {
    expect(
      controller.addToQueue([for (final track in tracks) track.toTrackInfo()]),
      isTrue,
    );
    unawaited(controller.jumpTo(index));
    // 佇列發出兩次（加入、跳到），播放列看到第一次才開始訂閱播放狀態。
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  /// 把網路狀態帶到 [status]：`noInterface` 是系統回報介面消失，
  /// `unreachable` 是連續失敗到門檻，`online` 是介面回來。
  Future<void> setNetwork(WidgetTester tester, NetworkStatus status) async {
    switch (status) {
      case NetworkStatus.online:
        interfaces.change(available: true);
      case NetworkStatus.noInterface:
        interfaces.change(available: false);
      case NetworkStatus.unreachable:
        final notifier = container(tester).read(networkStatusProvider.notifier);
        for (var i = 0; i < unreachableFailures; i++) {
          notifier.report(RequestOutcome.networkError);
        }
    }
    await tester.pump();
    expect(container(tester).read(networkStatusProvider), status);
  }

  /// 外觀設定從記憶體資料庫讀出來（drift 的串流要真的事件迴圈）。
  Future<void> loadSettings(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}
