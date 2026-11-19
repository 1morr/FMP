import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/chart_store.dart';
import 'package:fmp/domain/chart.dart';
import 'package:fmp/plugins/plugins.dart';

/// 現在幾點；排行榜多舊、該不該重抓看它。測試換成假的時鐘。
final chartsClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// 榜比這個舊就在背景重抓（ARCHITECTURE〈快取〉）；固定值，設定不能調
/// （brief〈之後的里程碑〉的不做清單）。
const chartStaleAfter = Duration(hours: 1);

/// 首頁的榜取前幾名（`docs/design/DESIGN.md`〈首頁〉）。
const chartLength = 10;

/// 一個音源的排行榜（`docs/design/home.html`）：各自抓、各自失敗、各自重試。
class SourceChart {
  const SourceChart({
    required this.manifest,
    this.chart,
    this.loading = false,
    this.error,
  });

  /// 這個音源的插件；畫面用它的名稱、音源標識與榜名。
  final PluginManifest manifest;

  /// 最後一份抓到的榜（這次抓的，或資料庫裡上次的）；從沒抓到過是 null。
  final Chart? chart;

  /// 正在讀快取或抓榜；有 [chart] 時是背景重抓，畫面照常顯示它。
  final bool loading;

  /// 最近一次抓榜失敗的原因；下一次抓到時清掉。有 [chart] 時畫面照樣顯示
  /// 它，並寫明它是多久以前的（2026-11-20 擁有者同意）。
  final AppError? error;

  SourceChart _copyWith({
    Chart? chart,
    bool? loading,
    AppError? Function()? error,
  }) => SourceChart(
    manifest: manifest,
    chart: chart ?? this.chart,
    loading: loading ?? this.loading,
    error: error == null ? this.error : error(),
  );
}

/// 首頁「近期熱門」：每個宣告 `charts` 的插件一張榜，依插件的順序。
class ChartsState {
  const ChartsState({this.starting = false, this.sources = const []});

  /// 插件還沒載入完，還不知道有哪些音源（畫面照載入中畫）。
  final bool starting;

  final List<SourceChart> sources;

  /// 每個音源都從沒抓到過、這次又都連不上：畫面把它們合成一張錯誤卡
  /// （`docs/design/DESIGN.md`〈首頁〉）。
  bool get neverLoadedOffline =>
      sources.isNotEmpty &&
      sources.every((s) => s.chart == null && s.error is NetworkError);
}

final chartsProvider = NotifierProvider<Charts, ChartsState>(Charts.new);

/// 排行榜與它的快取（ARCHITECTURE〈快取〉）：每個音源最後一份榜存資料庫，
/// 先顯示它；比 [chartStaleAfter] 舊（或沒有）才在背景重抓；[refresh] 不管
/// 新舊都重抓（下拉刷新、重試）。抓不到時留著上次的榜。
class Charts extends Notifier<ChartsState> {
  /// 這一輪 [build] 讀快取的工作；抓榜前等它，免得讀回的舊榜蓋掉新抓的。
  Future<void> _restored = Future.value();

  /// 每次 [build] 加一；上一輪留下的非同步結果不寫進這一輪的狀態。
  int _generation = 0;

  /// 正在抓的音源與它的抓榜工作；再要抓同一個音源時等這個，不重複抓。
  final _inFlight = <String, Future<void>>{};

  @override
  ChartsState build() {
    final generation = ++_generation;
    _inFlight.clear();
    _restored = Future.value();
    final hostValue = ref.watch(pluginHostProvider);
    final host = hostValue.value;
    if (host == null) {
      // 插件載入不了（log 由宿主那邊寫）時沒有音源，整區不出現。
      return ChartsState(starting: !hostValue.hasError);
    }
    final sources = [
      for (final plugin in host.plugins)
        if (plugin.manifest.capabilities.contains(PluginCapability.charts))
          SourceChart(manifest: plugin.manifest, loading: true),
    ];
    _restored = _restore(generation);
    return ChartsState(sources: sources);
  }

  /// 讀回存著的榜；讀不了只寫 log，當成沒有快取。
  Future<void> _restore(int generation) async {
    // 先讓 build 回傳：沒有資料庫時下面不會等任何東西，就會在 build 裡讀 state。
    await Future<void>.value();
    final store = ref.read(chartStoreProvider);
    var saved = const <String, Chart>{};
    if (store != null) {
      try {
        saved = await store.load();
      } on Object catch (error, stackTrace) {
        ref
            .read(logProvider)
            .error(
              'Loading the saved charts failed',
              error: error,
              stackTrace: stackTrace,
            );
      }
    }
    if (!ref.mounted || generation != _generation) return;
    state = ChartsState(
      sources: [
        for (final s in state.sources)
          SourceChart(
            manifest: s.manifest,
            chart: saved[s.manifest.id],
            error: s.error,
          ),
      ],
    );
    // 首頁可能在插件載入完之前就叫過 [refreshStale]（那時還沒有音源），這裡
    // 補抓一次；之後首頁再叫時，正在抓的不會重複抓。
    unawaited(_fetchStale());
  }

  /// 首頁每次出現時叫：沒有榜、或榜比 [chartStaleAfter] 舊的音源在背景重抓。
  /// 正在抓的不重複抓。插件還沒載入完時不用再叫：載入完、讀回快取後自己會
  /// 抓一次。
  Future<void> refreshStale() async {
    await _restored;
    await _fetchStale();
  }

  Future<void> _fetchStale() async {
    final now = ref.read(chartsClockProvider)();
    await _fetchWhere(
      (s) => switch (s.chart) {
        null => true,
        final chart => now.difference(chart.fetchedAt) > chartStaleAfter,
      },
    );
  }

  /// 不管新舊都重抓：[only] 給了只抓那個音源（重試），沒給抓全部（下拉
  /// 刷新）。正在抓的不重複抓，等它抓完。
  Future<void> refresh({String? only}) async {
    await _restored;
    await _fetchWhere((s) => only == null || s.manifest.id == only);
  }

  Future<void> _fetchWhere(bool Function(SourceChart) which) {
    final generation = _generation;
    return Future.wait([
      for (final s in state.sources.where(which))
        if (_inFlight[s.manifest.id] case final running?)
          running
        else
          _inFlight[s.manifest.id] = _fetch(s.manifest.id, generation)
              .whenComplete(() {
                if (generation == _generation) _inFlight.remove(s.manifest.id);
              }),
    ]);
  }

  Future<void> _fetch(String pluginId, int generation) async {
    _update(pluginId, (s) => s._copyWith(loading: true));
    final Chart chart;
    try {
      final host = await ref.read(pluginHostProvider.future);
      final plugin = host.plugins.firstWhere((p) => p.manifest.id == pluginId);
      chart = Chart(
        tracks: await plugin.charts(limit: chartLength),
        fetchedAt: ref.read(chartsClockProvider)(),
      );
    } catch (error, stackTrace) {
      if (!ref.mounted || generation != _generation) return;
      final AppError reason;
      if (error is AppError) {
        reason = error;
      } else {
        // 錯誤分類以外的例外是程式錯誤，畫面說載入不了，細節留在 log。
        ref
            .read(logProvider)
            .error(
              'Fetching the $pluginId chart failed',
              error: error,
              stackTrace: stackTrace,
            );
        reason = const ParseFailure();
      }
      _update(
        pluginId,
        (s) => s._copyWith(loading: false, error: () => reason),
      );
      return;
    }
    if (!ref.mounted || generation != _generation) return;
    _update(
      pluginId,
      (s) => s._copyWith(chart: chart, loading: false, error: () => null),
    );
    await _save(pluginId, chart);
  }

  /// 存榜；失敗只寫 log，畫面照常顯示這次抓到的。
  Future<void> _save(String pluginId, Chart chart) async {
    try {
      await ref.read(chartStoreProvider)?.save(pluginId, chart);
    } on Object catch (error, stackTrace) {
      ref
          .read(logProvider)
          .error(
            'Saving the $pluginId chart failed',
            error: error,
            stackTrace: stackTrace,
          );
    }
  }

  void _update(String pluginId, SourceChart Function(SourceChart) f) {
    state = ChartsState(
      sources: [
        for (final s in state.sources) s.manifest.id == pluginId ? f(s) : s,
      ],
    );
  }
}
