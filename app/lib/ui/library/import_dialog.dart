import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/library/playlist_importer.dart';
import 'package:fmp/library/playlist_refresher.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 從網址匯入歌單的對話框（M4 design §10.8）：一個文字欄、「匯入」。
///
/// 匯入進行中顯示「已讀 n 首」，對話框不能關（匯入不能中途取消）。成功（建好或重新匯入同一張）
/// 關閉並回傳 [ImportedPlaylist]（Mix 網址是 [CreatedMix]），由呼叫端開詳情；不認得的網址、
/// 第一頁（Mix 是 `mix`）失敗與僅元資料來源（PR 19 才接上）都留在對話框裡寫原因、不建歌單，
/// 輸入留著。取消回 `null`。
Future<ImportResult?> showImportDialog(BuildContext context) =>
    showDialog<ImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ImportDialog(),
    );

class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog();

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  final _url = TextEditingController();
  var _running = false;

  /// 這次匯入已讀的項目數；第一頁還沒回來之前是 `null`。
  int? _count;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_running || _url.text.trim().isEmpty) return;
    final t = ref.read(translationsProvider);
    final importer = ref.read(playlistImporterProvider);
    final log = ref.read(logProvider);
    setState(() {
      _running = true;
      _count = null;
      _error = null;
    });
    try {
      final result = await importer.importUrl(
        _url.text,
        onProgress: (count) {
          if (mounted) setState(() => _count = count);
        },
      );
      if (!mounted) return;
      switch (result) {
        case ImportedPlaylist() || CreatedMix():
          Navigator.of(context).pop(result);
        case ImportUnrecognized():
          _fail(t.library.importUnrecognized);
        case ImportMixSeed():
          // Mix 只有一次請求：進度區照舊顯示「正在辨識」。
          final created = await importer.createMix(result);
          if (!mounted) return;
          Navigator.of(context).pop(created);
        case ImportMetadataOnly():
          _fail(t.library.importUnsupported);
      }
    } on Object catch (error, stackTrace) {
      final appError = AppError.wrap(error, stackTrace);
      log.report('Failed to import a playlist', appError, tag: libraryLogTag);
      if (!mounted) return;
      final pluginId = appError.pluginId;
      final reason = switch (ref.read(networkStatusProvider)) {
        NetworkStatus.noInterface => t.offline.noInterface,
        NetworkStatus.unreachable => t.offline.unreachable,
        NetworkStatus.online => errorMessage(
          t,
          appError,
          sourceName: pluginId == null
              ? null
              : ref.read(pluginNameProvider(pluginId)) ?? pluginId,
        ),
      };
      _fail(t.library.importFailed(reason: reason));
    }
  }

  void _fail(String message) => setState(() {
    _running = false;
    _error = message;
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).library;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final count = _count;
    final error = _error;
    return PopScope(
      canPop: !_running,
      child: AlertDialog(
        title: Text(t.importTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _url,
                autofocus: true,
                enabled: !_running,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => unawaited(_submit()),
                decoration: InputDecoration(
                  labelText: t.importUrlLabel,
                  errorText: error,
                  errorMaxLines: 3,
                ),
              ),
              if (_running) ...[
                SizedBox(height: spacing.x4),
                // 進度念給螢幕閱讀器：第一頁回來前是「正在辨識網址」，之後是已讀幾首。
                Semantics(
                  liveRegion: true,
                  child: Text(
                    count == null
                        ? t.importLooking
                        : t.importProgress(count: count),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                SizedBox(height: spacing.x2),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _running ? null : () => Navigator.of(context).pop(),
            child: Text(t.cancel),
          ),
          ListenableBuilder(
            listenable: _url,
            builder: (context, _) => FilledButton(
              onPressed: _running || _url.text.trim().isEmpty
                  ? null
                  : () => unawaited(_submit()),
              child: Text(t.importAction),
            ),
          ),
        ],
      ),
    );
  }
}
