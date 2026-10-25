import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/library/import_progress.dart';
import 'package:fmp/library/playlist_importer.dart';
import 'package:fmp/library/playlist_refresher.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 從網址匯入歌單的對話框（M4 design §10.8）：一個文字欄、「匯入」。
///
/// 匯入進行中顯示「已匯入 n／M 首」（M 不明時「已讀 n 首」）與目前的曲名，對話框不能關，只能按「取消」
/// （ADR 0035 §決定 11）：已寫入的頁留著，一頁都沒寫就什麼都不留，兩者都關閉並回傳 `null`、跳提示。成功（建好或重新匯入同一張）
/// 關閉並回傳 [ImportedPlaylist]（Mix 網址是 [CreatedMix]），由呼叫端開詳情；不認得的網址與
/// 第一頁（Mix 是 `mix`）失敗都留在對話框裡寫原因、不建歌單，輸入留著。取消回 `null`。
///
/// 要交給匯入預覽的（僅元資料來源，或選了「配對到其他音源」）關閉並回傳 [ImportForMatching]，
/// 由呼叫端開預覽頁（§17 第 19 條）。輸入停下 [_recognizeDelay] 後先辨識網址（`playlistFromUrl`，
/// 不取頁）：認出是能播的插件的歌單時多一個選擇，預設「匯入為平台歌單」（原本的行為）。辨識失敗
/// 不顯示，等按「匯入」時照原本的流程報錯。
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

/// 輸入停下多久才辨識網址（貼上就是一次停下；打字時不每個字問一次插件）。
const _recognizeDelay = Duration(milliseconds: 300);

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  final _url = TextEditingController();
  var _running = false;
  Timer? _recognizeTimer;

  /// [_recognized] 是哪一段輸入（去頭尾空白）的辨識結果；輸入改了就不算數。
  String? _recognizedFor;
  RecognizedUrl? _recognized;

  /// 正在等（或正在辨識）的那一段輸入；[_recognizing] 讓過時的結果丟掉。
  String? _pendingFor;
  var _recognizing = 0;

  /// 選了「配對到其他音源」（只在 [RecognizedUrl.canPair] 時有這個選擇）。
  var _pair = false;

  /// 這次匯入的進度；第一頁還沒寫入之前是 `null`。
  ImportProgress? _progress;
  ImportCancel? _cancel;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url.addListener(_urlChanged);
  }

  @override
  void dispose() {
    _recognizeTimer?.cancel();
    _url.dispose();
    super.dispose();
  }

  void _urlChanged() {
    final text = _url.text.trim();
    if (text == _recognizedFor || text == _pendingFor || _running) return;
    _recognizeTimer?.cancel();
    _recognizing++;
    _pendingFor = text.isEmpty ? null : text;
    if (_recognized != null || _pair) {
      setState(() {
        _recognized = null;
        _recognizedFor = null;
        _pair = false;
      });
    }
    if (text.isEmpty) return;
    _recognizeTimer = Timer(_recognizeDelay, () => unawaited(_recognize(text)));
  }

  Future<void> _recognize(String text) async {
    final attempt = ++_recognizing;
    final RecognizedUrl? recognized;
    try {
      recognized = await ref.read(playlistImporterProvider).recognize(text);
    } on Object {
      // 按「匯入」時會再問一次，錯誤在那時照原本的流程提示。
      return;
    }
    if (!mounted || attempt != _recognizing || _running) return;
    _pendingFor = null;
    setState(() {
      _recognizedFor = text;
      _recognized = recognized;
      _pair = false;
    });
  }

  /// 目前的輸入已經辨識好的結果；還沒辨識（或輸入改了）是 `null`。
  RecognizedUrl? get _current =>
      _recognizedFor == _url.text.trim() ? _recognized : null;

  Future<void> _submit() async {
    if (_running || _url.text.trim().isEmpty) return;
    final t = ref.read(translationsProvider);
    final importer = ref.read(playlistImporterProvider);
    final log = ref.read(logProvider);
    final toaster = ref.read(toasterProvider);
    final recognized = _current;
    if (recognized != null && recognized.canPair && _pair) {
      final found = recognized.ref as PlaylistIdRef;
      Navigator.of(context).pop(
        ImportForMatching(
          pluginId: recognized.pluginId,
          playlistId: found.playlistId,
        ),
      );
      return;
    }
    _recognizeTimer?.cancel();
    final cancel = ImportCancel();
    setState(() {
      _running = true;
      _progress = null;
      _cancel = cancel;
      _error = null;
    });
    void onProgress(ImportProgress progress) {
      if (mounted) setState(() => _progress = progress);
    }

    try {
      final result = recognized == null
          ? await importer.importUrl(
              _url.text,
              onProgress: onProgress,
              cancel: cancel,
            )
          : await importer.importRecognized(
              recognized,
              onProgress: onProgress,
              cancel: cancel,
            );
      if (!mounted) return;
      switch (result) {
        // 還沒寫任何東西就回來的（Mix 還沒建、要交給預覽的）：取消了就不再往下做。
        case ImportMixSeed() || ImportForMatching() when cancel.isCancelled:
          toaster.info(t.library.importCancelledNone);
          Navigator.of(context).pop();
        case ImportedPlaylist() || CreatedMix() || ImportForMatching():
          Navigator.of(context).pop(result);
        case ImportCancelled():
          toaster.info(t.library.importCancelledNone);
          Navigator.of(context).pop();
        case ImportUnrecognized():
          _fail(t.library.importUnrecognized);
        case ImportMixSeed():
          // Mix 只有一次請求：進度區照舊顯示「正在辨識」。
          final created = await importer.createMix(result);
          if (!mounted) return;
          Navigator.of(context).pop(created);
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

  void _requestCancel() {
    final cancel = _cancel;
    if (cancel == null || cancel.isCancelled) return;
    // 取消在下一頁寫入之前生效：按鈕先停用，結果回來時對話框才關。
    setState(cancel.cancel);
  }

  void _fail(String message) => setState(() {
    _running = false;
    _error = message;
    // 匯入期間回來的辨識結果被丟掉了（`_running`）：同一段輸入之後要能再辨識。
    _pendingFor = null;
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).library;
    final spacing = AppTokens.of(context).spacing;
    final progress = _progress;
    final cancelling = _cancel?.isCancelled ?? false;
    final error = _error;
    final pairable = _current?.canPair ?? false;
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
              if (pairable && !_running) ...[
                SizedBox(height: spacing.x2),
                _ImportChoice(
                  pluginId: _current!.pluginId,
                  pair: _pair,
                  onChanged: (pair) => setState(() => _pair = pair),
                ),
              ],
              if (_running) ...[
                SizedBox(height: spacing.x4),
                _ImportProgressView(progress: progress),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: !_running
                ? () => Navigator.of(context).pop()
                : cancelling
                ? null
                : _requestCancel,
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

/// 匯入進行中的進度區（匯入對話框）：第一頁寫入前是「正在辨識網址」加不定長的進度條；之後
/// 「已匯入 n／M 首」加確定長度的進度條（M 不明時「已讀 n 首」、不定長）與目前的曲名。
class _ImportProgressView extends ConsumerWidget {
  const _ImportProgressView({required this.progress});

  final ImportProgress? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).library;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final value = progress;
    final total = value?.displayTotal;
    final title = value?.currentTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 進度念給螢幕閱讀器：第一頁回來前是「正在辨識網址」，之後是已匯入幾首。
        Semantics(
          liveRegion: true,
          child: Text(
            value == null
                ? t.importLooking
                : total == null
                ? t.importProgress(count: value.count)
                : t.importProgressOf(count: value.count, total: total),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        SizedBox(height: spacing.x2),
        LinearProgressIndicator(
          value: value == null || total == null ? null : value.count / total,
        ),
        if (title != null) ...[
          SizedBox(height: spacing.x2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// 能播的插件的歌單：匯入為平台歌單（預設）或配對到其他音源（§17 第 19 條）。
class _ImportChoice extends ConsumerWidget {
  const _ImportChoice({
    required this.pluginId,
    required this.pair,
    required this.onChanged,
  });

  final String pluginId;
  final bool pair;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).library;
    final source = ref.watch(pluginNameProvider(pluginId)) ?? pluginId;
    return RadioGroup<bool>(
      groupValue: pair,
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<bool>(
            value: false,
            contentPadding: EdgeInsets.zero,
            title: Text(t.importAsPlatform),
            subtitle: Text(t.importAsPlatformHint(source: source)),
          ),
          RadioListTile<bool>(
            value: true,
            contentPadding: EdgeInsets.zero,
            title: Text(t.importAsMatch),
            subtitle: Text(t.importAsMatchHint),
          ),
        ],
      ),
    );
  }
}
