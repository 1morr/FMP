import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app_material.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/playback/playback_controller.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_session.dart';
import 'package:fmp/playback/stream_resolver.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/player/queue_tracks.dart';
import 'package:fmp/ui/search/search_state.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:fmp/ui/toast/toast_host.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_audio_backend.dart';
import '../../playback/fake_source_plugin.dart';
import '../../support/fake_network_interfaces.dart';
import '../../support/memory_database.dart';

/// 一首搜尋結果（插件 `fmp-test`）。
TrackSummary summary(String id, {Duration? duration}) => TrackSummary(
  sourceTypeId: 'fmp-test',
  sourceId: id,
  title: 'Song $id',
  uploader: 'Uploader $id',
  duration: duration ?? const Duration(minutes: 3, seconds: 5),
);

/// 外殼與頁面的測試環境：可以搜尋、可以解析的假插件，假後端上的真
/// `PlaybackController`，記憶體資料庫、[Toaster] 與有介面的假網路介面
/// （[interfaces]）。介面語言是英文（測試的系統語言 `en_US`）。
final class ShellHarness {
  ShellHarness({
    FutureOr<SearchPage> Function(SearchQuery query)? onSearch,
    List<SourcePlugin>? sources,
    this.cacheStore,
  }) : plugin = FakeSourcePlugin(
         (request) => [candidate('${request.sourceId}.m4a')],
         name: 'Test Source',
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
          log: log,
        ),
        log: log,
      ),
      log: log,
    );
    toaster = Toaster(
      log: log,
      translations: AppLocale.en.buildSync,
      sourceName: (_) => null,
    );
    addTearDown(toaster.dispose);
  }

  /// 設定頁「網路」組用的快取庫；不給就是還沒開好（用量不顯示）。
  final CacheStore? cacheStore;

  final FakeSourcePlugin plugin;
  late final List<SourcePlugin> sources;

  /// 曲目長 3 分鐘：測試期間不會自己播完。
  final backend = FakeAudioBackend(
    durationOf: (_) => const Duration(minutes: 3),
  );
  final log = Log(redactor: Redactor(), minimumLevel: LogLevel.warning);
  late final PlaybackController controller;
  late final Toaster toaster;
  final interfaces = FakeNetworkInterfaces();

  List<Override> get overrides => [
    appDatabaseProvider.overrideWithValue(memoryDatabase()),
    logProvider.overrideWithValue(log),
    toasterProvider.overrideWithValue(toaster),
    searchSourcesProvider.overrideWithValue(AsyncData(sources)),
    networkInterfacesProvider.overrideWithValue(interfaces),
    // 「網路」設定的預設上限讀平台宣告：128 MiB。
    platformCapabilitiesProvider.overrideWithValue(
      const PlatformCapabilities(
        dataDirectory: true,
        singleInstance: false,
        fontFallback: FontFallback.none,
        playback: null,
        networkInterfaces: false,
        cache: CacheSizes(
          defaultLimitMebibytes: 128,
          memoryImages: 1,
          memoryImageMebibytes: 1,
        ),
      ),
    ),
    cacheStoreProvider.overrideWith(
      (ref) => cacheStore ?? Completer<CacheStore>().future,
    ),
    // 樹拆掉時停掉後端的計時器（測試結束時檢查沒有留下的計時器）。
    playbackControllerProvider.overrideWith((ref) {
      ref.onDispose(() {
        unawaited(controller.dispose());
        unawaited(backend.dispose());
      });
      return controller;
    }),
  ];

  /// 以 [size] 的視窗開 App 的外殼（和 `FmpApp` 同一份 `MaterialApp` 設定）。
  Future<void> pumpShell(
    WidgetTester tester, {
    Size size = const Size(1000, 700),
    Brightness brightness = Brightness.light,
  }) => pumpApp(tester, const AppShell(), size: size, brightness: brightness);

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
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: fmpMaterialApp(
          title: 'FMP Dev',
          locale: LocaleSetting.en,
          themeMode: themeModeOf(switch (brightness) {
            Brightness.light => ThemeModeSetting.light,
            Brightness.dark => ThemeModeSetting.dark,
          }),
          fontFamilyFallback: const [],
          builder: (context, navigator) =>
              WindowClassScope(child: ToastHost(child: navigator!)),
          home: home,
        ),
      ),
    );
    await tester.pump();
  }

  /// 目前的 [ProviderContainer]（`pumpApp` 之後）。
  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ToastHost)));

  /// 從 [tracks] 的第 [index] 首開始播，像搜尋頁點了一首。
  Future<void> play(
    WidgetTester tester,
    List<TrackSummary> tracks, {
    int index = 0,
  }) async {
    container(tester).read(queueTracksProvider.notifier).replace(tracks);
    unawaited(
      controller.playQueue([
        for (final track in tracks)
          TrackKeyParts(
            sourceTypeId: track.sourceTypeId,
            sourceId: track.sourceId,
          ),
      ], startIndex: index),
    );
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
