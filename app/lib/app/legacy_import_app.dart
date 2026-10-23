import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/app/app_material.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/data/import/legacy_import_failed.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/settings/appearance_settings.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 首次啟動匯入舊版資料時的畫面（M5 design §3.1、§7.1、§7.2）：進度，失敗時是失敗頁。
///
/// 獨立的小 App（同 `DatabaseErrorApp`）：此時資料庫還沒開，沒有外觀設定，語言與主題跟隨
/// 系統。匯入不可取消（一般幾秒；中途結束不留半套資料：暫存檔下次啟動清掉）。
class LegacyImportApp extends ConsumerStatefulWidget {
  const LegacyImportApp({
    super.key,
    required this.flavor,
    required this.fontFallback,
    required this.run,
    required this.onStartBlank,
    required this.onExport,
  });

  final AppFlavor flavor;
  final FontFallback fontFallback;

  /// 跑一次匯入（讀、轉換、寫、驗證、換上）。成功就返回（呼叫端接手換成正式 App）；失敗拋
  /// 例外：[LegacyImportFailed] 帶步驟，其他例外只顯示型別。[progress] 回報目前的步驟。
  final Future<void> Function(void Function(LegacyImportStep step) progress)
  run;

  /// 「以空白資料啟動」：呼叫端建空庫、照舊啟動。
  final Future<void> Function() onStartBlank;

  /// 「匯出診斷」；使用者取消回 `false`。`null` 時（平台沒有檔案對話框）不顯示按鈕。
  final Future<bool> Function(Object error, LegacyImportStep? step)? onExport;

  @override
  ConsumerState<LegacyImportApp> createState() => _LegacyImportAppState();
}

class _LegacyImportAppState extends ConsumerState<LegacyImportApp> {
  var _step = LegacyImportStep.read;
  Object? _failure;

  /// 匯出診斷的結果提示；`null` 是還沒匯出或使用者取消。
  bool? _exported;
  var _busy = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _step = LegacyImportStep.read;
      _failure = null;
      _exported = null;
      _busy = true;
    });
    try {
      await widget.run((step) {
        if (mounted) setState(() => _step = step);
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = error;
          _busy = false;
        });
      }
    }
  }

  Future<void> _startBlank() async {
    setState(() => _busy = true);
    try {
      await widget.onStartBlank();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = error;
          _busy = false;
        });
      }
    }
  }

  Future<void> _export() async {
    final failure = _failure;
    final export = widget.onExport;
    if (failure == null || export == null) return;
    setState(() => _busy = true);
    // 取消（`false`）不顯示任何提示；例外是失敗。
    bool? exported;
    try {
      final saved = await export(
        failure,
        failure is LegacyImportFailed ? failure.step : null,
      );
      exported = saved ? true : null;
    } on Object {
      exported = false;
    }
    if (mounted) {
      setState(() {
        _exported = exported;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = localeForSystem(ref.watch(systemLocalesProvider));
    final t = appLocaleOf(locale).buildSync();
    return fmpMaterialApp(
      title: widget.flavor.displayName,
      locale: locale,
      themeMode: ThemeMode.system,
      fontFamilyFallback: fontFamilyFallbackOf(widget.fontFallback, locale),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: EdgeInsets.all(AppTokens.of(context).spacing.x4),
                child: _failure == null
                    ? _Progress(t: t, step: _step)
                    : _Failure(
                        t: t,
                        failure: _failure!,
                        exported: _exported,
                        busy: _busy,
                        onRetry: _run,
                        onExport: widget.onExport == null ? null : _export,
                        onStartBlank: _startBlank,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 進度清單的五項；換檔與寫憑證都算「完成」那一項。
enum _Item { read, convert, write, verify, done }

_Item _itemOf(LegacyImportStep step) => switch (step) {
  LegacyImportStep.read => _Item.read,
  LegacyImportStep.convert => _Item.convert,
  LegacyImportStep.write => _Item.write,
  LegacyImportStep.verify => _Item.verify,
  LegacyImportStep.swap || LegacyImportStep.credentials => _Item.done,
};

String _itemLabel(Translations t, _Item item) => switch (item) {
  _Item.read => t.startup.legacyImport.stepRead,
  _Item.convert => t.startup.legacyImport.stepConvert,
  _Item.write => t.startup.legacyImport.stepWrite,
  _Item.verify => t.startup.legacyImport.stepVerify,
  _Item.done => t.startup.legacyImport.stepDone,
};

class _Progress extends StatelessWidget {
  const _Progress({required this.t, required this.step});

  final Translations t;
  final LegacyImportStep step;

  @override
  Widget build(BuildContext context) {
    final current = _itemOf(step);
    final spacing = AppTokens.of(context).spacing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            t.startup.legacyImport.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        SizedBox(height: spacing.x4),
        for (final item in _Item.values)
          Padding(
            padding: EdgeInsets.symmetric(vertical: spacing.x1),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: item.index < current.index
                      ? const Icon(Icons.check_circle, size: 20)
                      : item == current
                      ? const Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radio_button_unchecked, size: 20),
                ),
                SizedBox(width: spacing.x3),
                Text(_itemLabel(t, item)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({
    required this.t,
    required this.failure,
    required this.exported,
    required this.busy,
    required this.onRetry,
    required this.onExport,
    required this.onStartBlank,
  });

  final Translations t;
  final Object failure;
  final bool? exported;
  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback? onExport;
  final VoidCallback onStartBlank;

  @override
  Widget build(BuildContext context) {
    final l = t.startup.legacyImport;
    final spacing = AppTokens.of(context).spacing;
    final failure = this.failure;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            l.failedTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        SizedBox(height: spacing.x3),
        if (failure is LegacyImportFailed)
          Text(l.failedStep(step: _itemLabel(t, _itemOf(failure.step)))),
        // 原因（`LegacyImportFailed.reason`）是英文，只進 log 與診斷包；畫面只寫翻譯過的步驟。
        Text(l.detailsHint),
        SizedBox(height: spacing.x3),
        Text(l.safeNote),
        SizedBox(height: spacing.x4),
        Wrap(
          spacing: spacing.x2,
          runSpacing: spacing.x2,
          children: [
            FilledButton(
              onPressed: busy ? null : onRetry,
              child: Text(t.startup.retry),
            ),
            if (onExport != null)
              OutlinedButton(
                onPressed: busy ? null : onExport,
                child: Text(t.startup.exportDiagnostics),
              ),
            TextButton(
              onPressed: busy ? null : onStartBlank,
              child: Text(l.startBlank),
            ),
          ],
        ),
        if (exported != null) ...[
          SizedBox(height: spacing.x3),
          Text(exported! ? t.startup.exportDone : t.startup.exportFailed),
        ],
      ],
    );
  }
}
