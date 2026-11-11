import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/plugins/plugins.dart';

/// 一個插件的搜尋結果：曲目，或失敗時的錯誤分類。
class SourceResults {
  const SourceResults(this.pluginName, {this.tracks = const [], this.error});

  final String pluginName;
  final List<Track> tracks;
  final AppError? error;
}

/// 佔位畫面的搜尋（M0）：用每個宣告了 search 的插件各搜一次。還沒搜過是
/// null；一個插件失敗不影響其他插件。
final placeholderSearchProvider =
    NotifierProvider<PlaceholderSearch, AsyncValue<List<SourceResults>>?>(
      PlaceholderSearch.new,
    );

class PlaceholderSearch extends Notifier<AsyncValue<List<SourceResults>>?> {
  /// 每次搜尋加一；慢的舊搜尋回來時不蓋掉新的。
  int _generation = 0;

  @override
  AsyncValue<List<SourceResults>>? build() => null;

  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final generation = ++_generation;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final host = await ref.read(pluginHostProvider.future);
      return Future.wait([
        for (final plugin in host.plugins)
          if (plugin.manifest.capabilities.contains(PluginCapability.search))
            _searchOne(plugin, q),
      ]);
    });
    if (!ref.mounted) return;
    if (result case AsyncError(:final error, :final stackTrace)) {
      // 錯誤分類以外的例外是程式錯誤，畫面只說搜尋失敗，細節留在 log。
      ref
          .read(logProvider)
          .error('Search failed', error: error, stackTrace: stackTrace);
    }
    if (generation == _generation) state = result;
  }

  Future<SourceResults> _searchOne(Plugin plugin, String query) async {
    try {
      return SourceResults(
        plugin.manifest.name,
        tracks: await plugin.search(query),
      );
    } on AppError catch (error) {
      return SourceResults(plugin.manifest.name, error: error);
    }
  }
}
