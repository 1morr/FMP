import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/app/app_material.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/settings/appearance_settings.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 資料庫開不起來時的畫面（ADR 0010 §決定 3）：App 不在半開的資料庫上啟動，
/// 只顯示錯誤，附「重試」與「匯出診斷」。
///
/// 讀不到外觀設定，所以語言與主題都跟隨系統。
class DatabaseErrorApp extends ConsumerStatefulWidget {
  const DatabaseErrorApp({
    super.key,
    required this.flavor,
    required this.error,
    required this.fontFallback,
    required this.onRetry,
    required this.onExport,
  });

  final AppFlavor flavor;

  /// 開啟時拋出的錯誤，原樣顯示供回報問題。
  final Object error;

  /// 平台的 CJK 字型 fallback（`PlatformCapabilities.fontFallback`）。
  final FontFallback fontFallback;

  /// 「重試」：重新跑開庫。成功就返回（呼叫端接手換成正式 App）；失敗拋例外，畫面換成新的錯誤。
  final Future<void> Function() onRetry;

  /// 「匯出診斷」；使用者取消回 `false`。`null` 時（平台沒有檔案對話框）不顯示按鈕。
  final Future<bool> Function(Object error)? onExport;

  @override
  ConsumerState<DatabaseErrorApp> createState() => _DatabaseErrorAppState();
}

class _DatabaseErrorAppState extends ConsumerState<DatabaseErrorApp> {
  late Object _error = widget.error;
  var _busy = false;

  /// 匯出診斷的結果提示；`null` 是還沒匯出或使用者取消。
  bool? _exported;

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _exported = null;
    });
    try {
      await widget.onRetry();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _busy = false;
        });
      }
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    // 取消（`false`）不顯示任何提示；例外是失敗。
    bool? shown;
    try {
      shown = await widget.onExport!(_error) ? true : null;
    } on Object {
      shown = false;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _exported = shown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = localeForSystem(ref.watch(systemLocalesProvider));
    final t = buildTranslations(appLocaleOf(locale));
    return fmpMaterialApp(
      title: widget.flavor.displayName,
      locale: locale,
      themeMode: ThemeMode.system,
      fontFamilyFallback: fontFamilyFallbackOf(widget.fontFallback, locale),
      home: Builder(
        builder: (context) {
          final spacing = AppTokens.of(context).spacing;
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.startup.databaseError,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  SelectableText('$_error'),
                  SizedBox(height: spacing.x4),
                  Wrap(
                    spacing: spacing.x2,
                    runSpacing: spacing.x2,
                    children: [
                      FilledButton(
                        onPressed: _busy ? null : _retry,
                        child: Text(t.startup.retry),
                      ),
                      if (widget.onExport != null)
                        OutlinedButton(
                          onPressed: _busy ? null : _export,
                          child: Text(t.startup.exportDiagnostics),
                        ),
                    ],
                  ),
                  if (_exported != null) ...[
                    SizedBox(height: spacing.x3),
                    Text(
                      _exported!
                          ? t.startup.exportDone
                          : t.startup.exportFailed,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
