import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/endpoints.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/repository/plugin_downloader.dart';
import 'package:fmp/plugins/repository/plugin_index.dart';
import 'package:fmp/plugins/repository/plugin_updates.dart';

// 插件頁讀的資料（ADR 0030 §決定 6、7、9、11）：已安裝的插件（本機，離線照常）、
// 自訂插件庫的清單，以及每一份 index 讀到的內容（打開插件頁或按「檢查更新」時才讀，
// ADR 0014 §決定 7）。

/// 已安裝的插件（含停用的），依 id 排序；`installed_plugins` 每次變動就重讀。
final installedPluginsProvider =
    StreamProvider.autoDispose<List<InstalledPlugin>>((ref) async* {
      final repository = ref.watch(pluginRepositoryProvider);
      yield await repository.list();
      await for (final _ in repository.changes()) {
        yield await repository.list();
      }
    });

/// 使用者加的自訂插件庫，依加入時間；`plugin_indexes` 每次變動就重讀。
final customIndexesProvider =
    StreamProvider.autoDispose<List<PluginIndexRecord>>((ref) async* {
      final repository = ref.watch(pluginIndexRepositoryProvider);
      yield await repository.list();
      await for (final _ in repository.changes()) {
        yield await repository.list();
      }
    });

/// 插件頁要讀的 index 網址：官方的在前，之後是自訂的。自訂清單還沒讀出來時只有官方的。
final indexUrlsProvider = Provider.autoDispose<List<String>>(
  (ref) => [
    officialPluginIndexUrl,
    for (final record in ref.watch(customIndexesProvider).value ?? const [])
      if (record.url != officialPluginIndexUrl) record.url,
  ],
);

/// 讀一份 index 的結果。失敗不丟出（[IndexFailed]）：讀不到是畫面上的一個狀態，而
/// Riverpod 對丟出錯誤的 provider 會自己重試。
sealed class IndexOutcome {
  const IndexOutcome();
}

final class IndexLoaded extends IndexOutcome {
  const IndexLoaded(this.index);

  final PluginIndex index;
}

/// `indexVersion` 太新：需要更新 FMP（ADR 0030 §決定 1）。
final class IndexTooNew extends IndexOutcome {
  const IndexTooNew();
}

final class IndexFailed extends IndexOutcome {
  const IndexFailed(this.error);

  final AppError error;
}

/// [url] 這份 index 讀到的內容。沒有人看時丟掉，下次打開插件頁重讀；「檢查更新」以
/// `ref.invalidate(indexOutcomeProvider)` 全部重讀。失敗經 `log.report` 記一次。
final indexOutcomeProvider = FutureProvider.autoDispose
    .family<IndexOutcome, String>((ref, url) async {
      final downloader = ref.watch(pluginDownloaderProvider);
      try {
        return switch (await downloader.readIndex(Uri.parse(url))) {
          IndexRead(:final index) => IndexLoaded(index),
          IndexRejected() => const IndexTooNew(),
        };
      } on AppError catch (error) {
        ref
            .read(logProvider)
            .report('Failed to read a plugin index', error, tag: 'plugins');
        return IndexFailed(error);
      }
    });

/// 一個已安裝插件在它的來源 index 裡的那一筆，與更新狀態。
typedef PluginUpdate = ({
  PluginIndexEntry entry,
  String indexUrl,
  PluginUpdateStatus status,
});

/// [installed] 的更新（ADR 0030 §決定 6、9）：只看它的來源 index，而且那一份要在目前
/// 讀的清單裡（自訂的被刪掉就不再檢查）、讀到了、有同 id 的一筆。沒有就是 `null`
/// （含從檔案或網址安裝的）。
PluginUpdate? updateOf(
  InstalledPlugin installed,
  List<String> indexUrls,
  IndexOutcome? Function(String url) outcomeOf,
) {
  final url = installed.sourceIndexUrl;
  if (url == null || !indexUrls.contains(url)) return null;
  if (outcomeOf(url) case IndexLoaded(:final index)) {
    for (final entry in index.plugins) {
      if (entry.id == installed.id) {
        return (
          entry: entry,
          indexUrl: url,
          status: updateStatus(installed, url, entry),
        );
      }
    }
  }
  return null;
}

/// 已安裝插件的 manifest；資料庫裡的原文壞了（理論上不會：安裝時驗過）是 `null`，
/// 畫面只顯示 id 與版本。
PluginManifest? manifestOf(InstalledPlugin installed) {
  try {
    return PluginManifest.parse(installed.manifestJson);
  } on AppError {
    return null;
  }
}
