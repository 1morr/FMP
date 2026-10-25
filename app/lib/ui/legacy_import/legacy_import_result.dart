import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

// 首次啟動匯入舊版資料之後的結果對話框（M5 design §7.3）。

// `ImportSummary.collections` 與 `notes` 的鍵：轉換器寫死的識別字
// （`SummaryCollection`、`SkipReason`，在封住的 `lib/legacy_import/`）。
// `legacy_import_result_test.dart` 對照轉換器的常數。
const _tracks = 'tracks';
const _playlists = 'playlists';
const _history = 'history';
const _radioStations = 'radioStations';
const _accounts = 'accounts';
const _remoteNotRecognized = 'remoteNotRecognized';
const _duplicateRemote = 'duplicateRemote';

/// 結果對話框的選擇。
enum _Choice { acknowledge, installSources }

/// 有未看過的匯入結果時顯示一次對話框；沒有就什麼都不做。兩個按鈕都把這筆標成看過了。
///
/// 匯入的資料參照到還沒安裝的插件時多一個「安裝音源」，按下去呼叫 [onInstallSources]（開首次
/// 引導）。provider 在第一個 `await` 之前讀好，`await` 之後先看 `context.mounted`。
Future<void> showLegacyImportResult(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onInstallSources,
}) async {
  final repository = ref.read(legacyImportsRepositoryProvider);
  final plugins = ref.read(pluginRepositoryProvider);
  final record = await repository.latestUnacknowledged();
  if (record == null) return;
  final referenced = await repository.referencedPluginIds();
  final installed = {for (final plugin in await plugins.list()) plugin.id};
  if (!context.mounted) return;
  final t = ref.read(translationsProvider);
  final registry = ref.read(pluginRegistryProvider).value;
  final summary = record.summary;
  final choice = await showDialog<_Choice>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ResultDialog(
      t: t,
      summary: summary,
      reloginNames: [
        for (final id in summary.reloginPlatforms)
          registry?[id]?.manifest.name ?? id,
      ],
      needsSources: referenced.difference(installed).isNotEmpty,
    ),
  );
  await repository.acknowledge(record.id);
  if (choice == _Choice.installSources) onInstallSources();
}

int _written(ImportSummary summary, String collection) =>
    summary.collections[collection]?.written ?? 0;

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({
    required this.t,
    required this.summary,
    required this.reloginNames,
    required this.needsSources,
  });

  final Translations t;
  final ImportSummary summary;
  final List<String> reloginNames;
  final bool needsSources;

  /// 設定的識別字 → 翻譯；不認得的識別字（以後新增而忘了補翻譯）原樣顯示。
  String _unimported(String id) => switch (id) {
    'streamPriority' => t.legacyResult.unimported.streamPriority,
    'cacheLimit' => t.legacyResult.unimported.cacheLimit,
    'homeRanking' => t.legacyResult.unimported.homeRanking,
    'searchHistory' => t.legacyResult.unimported.searchHistory,
    _ => id,
  };

  @override
  Widget build(BuildContext context) {
    final r = t.legacyResult;
    final spacing = AppTokens.of(context).spacing;
    final theme = Theme.of(context);
    final notes = summary.collections[_playlists]?.notes ?? const {};
    final localPlaylists =
        (notes[_remoteNotRecognized] ?? 0) + (notes[_duplicateRemote] ?? 0);
    return AlertDialog(
      title: Text(r.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.playlists(count: _written(summary, _playlists))),
            Text(r.tracks(count: _written(summary, _tracks))),
            Text(r.history(count: _written(summary, _history))),
            Text(r.radio(count: _written(summary, _radioStations))),
            Text(r.accounts(count: _written(summary, _accounts))),
            if (reloginNames.isNotEmpty) ...[
              SizedBox(height: spacing.x3),
              Text(r.relogin(platforms: reloginNames.join(', '))),
            ],
            if (localPlaylists > 0) ...[
              SizedBox(height: spacing.x3),
              Text(r.localPlaylists(count: localPlaylists)),
            ],
            if (summary.unimportedSettings.isNotEmpty) ...[
              SizedBox(height: spacing.x3),
              Text(r.unimportedTitle, style: theme.textTheme.titleSmall),
              for (final id in summary.unimportedSettings)
                Text('· ${_unimported(id)}'),
            ],
            if (needsSources) ...[
              SizedBox(height: spacing.x3),
              Text(r.needsSources),
            ],
          ],
        ),
      ),
      actions: [
        if (needsSources)
          TextButton(
            onPressed: () => Navigator.of(context).pop(_Choice.installSources),
            child: Text(r.installSources),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_Choice.acknowledge),
          child: Text(r.acknowledge),
        ),
      ],
    );
  }
}
