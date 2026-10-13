import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/endpoints.dart';
import 'package:fmp/core/errors/error_report.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/platform/app_info/app_info.dart';
import 'package:fmp/platform/url_opener/url_opener.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/settings/developer_settings.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 在 [navigator] 上開 [record] 的錯誤詳細頁。提示的動作與 Debug 頁的「詳細」共用。
Future<void> openErrorDetail(NavigatorState navigator, LogRecord record) =>
    navigator.push<void>(
      MaterialPageRoute<void>(builder: (_) => ErrorDetailPage(record: record)),
    );

/// 錯誤詳細頁（ADR 0023 §決定 4）：全螢幕路由，顯示 [ErrorReport] 的欄位，文字可選取；
/// 「複製」把 Markdown 放進剪貼簿，「在 GitHub 回報」先複製、再開新增 issue 的網址。
///
/// [record] 是 `Log.report` 寫的那筆錯誤歷史（已遮蔽）。提示的「詳細」「回報」與 Debug 頁
/// 的錯誤紀錄開的是同一頁。
class ErrorDetailPage extends ConsumerStatefulWidget {
  const ErrorDetailPage({super.key, required this.record});

  final LogRecord record;

  @override
  ConsumerState<ErrorDetailPage> createState() => _ErrorDetailPageState();
}

class _ErrorDetailPageState extends ConsumerState<ErrorDetailPage> {
  late final ErrorReport _report;

  /// 開瀏覽器失敗之後也要顯示網址，讓使用者自己開。
  var _openFailed = false;

  @override
  void initState() {
    super.initState();
    final history = ref.read(logProvider).history;
    final info = ref.read(appInfoProvider);
    final pluginId = widget.record.fields['pluginId'];
    _report = ErrorReport.fromRecord(
      widget.record,
      redactor: ref.read(redactorProvider),
      appVersion: info.version,
      flavor: ref.read(appFlavorProvider).name,
      platform: info.platform,
      osVersion: info.osVersion,
      pluginVersion: pluginId is String ? _installedVersion(pluginId) : null,
      // 請求 id 只在同一次執行裡唯一：log 檔讀回來的前幾次紀錄不對網路紀錄。
      networkHistory: history.any((record) => identical(record, widget.record))
          ? history
          : const [],
    );
  }

  String? _installedVersion(String pluginId) {
    final plugins = ref.read(pluginRegistryProvider).value;
    return plugins == null ? null : plugins[pluginId]?.manifest.version;
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _report.toMarkdown()));
    if (!mounted) return;
    ref
        .read(toasterProvider)
        .info(ref.read(translationsProvider).errorReport.copied);
  }

  Future<void> _reportOnGitHub() async {
    final t = ref.read(translationsProvider).errorReport;
    final toaster = ref.read(toasterProvider);
    // 設定還沒載入完時當成沒關過提醒：多問一次，比沒問就把內容送去公開的 repo 好。
    final dismissed = ref
        .read(developerProvider)
        .value
        ?.stored
        .reportReminderDismissed;
    if (dismissed != true) {
      // true：繼續並不再提醒；false：只繼續；null：取消，什麼都不做。
      final answer = await showDialog<bool>(
        context: context,
        builder: (context) => const _ReminderDialog(),
      );
      if (answer == null) return;
      if (answer) {
        await ref.read(developerProvider.notifier).dismissReportReminder();
      }
      if (!mounted) return;
    }
    await Clipboard.setData(ClipboardData(text: _report.toMarkdown()));
    final opener = ref.read(urlOpenerProvider);
    if (opener == null) {
      toaster.info(t.reportCopied);
      return;
    }
    // 內容不進網址：報告已在剪貼簿，使用者貼到範本的欄位。
    final opened = await opener.open(Uri.parse(newIssueUrl));
    if (!mounted) return;
    if (opened) {
      toaster.info(t.reportCopied);
    } else {
      setState(() => _openFailed = true);
      toaster.warning(t.openFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).errorReport;
    final spacing = AppTokens.of(context).spacing;
    final opener = ref.watch(urlOpenerProvider);
    // `_reportOnGitHub` 讀「不再提醒」要靠這裡聽著：Riverpod 3 會暫停沒有人聽的 provider
    // （`ref.read` 不算聽），drift 的串流跟著暫停，`.value` 拿不到值、`.future` 不會完成。
    ref.watch(developerProvider);
    final report = _report;
    final request = report.request;
    return Scaffold(
      appBar: AppBar(title: Text(t.title)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.errorDetailMaxWidth,
            ),
            child: ListView(
              padding: EdgeInsets.all(spacing.x4),
              children: [
                Wrap(
                  spacing: spacing.x2,
                  runSpacing: spacing.x2,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy_outlined),
                      label: Text(t.copy),
                      onPressed: () => unawaited(_copy()),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.bug_report_outlined),
                      label: Text(t.reportOnGitHub),
                      onPressed: () => unawaited(_reportOnGitHub()),
                    ),
                  ],
                ),
                if (opener == null || _openFailed) ...[
                  SizedBox(height: spacing.x3),
                  SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          opener == null ? t.manualHint : t.openFailed,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Text(newIssueUrl),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: spacing.x4),
                SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Field(t.time, report.timestamp),
                      _Field(t.type, report.type),
                      _Field(t.reason, report.reason),
                      _Field(
                        t.source,
                        [?report.pluginId, ?report.pluginVersion].join(' '),
                      ),
                      _Field(t.action, report.operation),
                      _Field(t.module, report.tag),
                      if (request != null) ...[
                        _Field(t.request, '${request.method} ${request.url}'),
                        _Field(t.status, request.status?.toString()),
                        _Field(
                          t.duration,
                          request.ms == null ? null : '${request.ms} ms',
                        ),
                        _Field(t.requestError, request.error),
                      ] else
                        _Field(t.request, t.noRequest),
                      _Field(t.app, '${report.appVersion} (${report.flavor})'),
                      _Field(
                        t.system,
                        '${report.platform}, ${report.osVersion}',
                      ),
                      _Field(t.cause, report.cause, code: true),
                      _Field(t.stackTrace, report.stackTrace, code: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 標籤加內容；沒有內容的欄位不畫。[code] 用等寬字與底色區塊（原因與 stack trace）。
class _Field extends StatelessWidget {
  const _Field(this.label, this.value, {this.code = false});

  final String label;
  final String? value;
  final bool code;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final spacing = tokens.spacing;
    final style = code
        ? theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (code)
            Container(
              width: double.infinity,
              margin: EdgeInsets.only(top: spacing.x1),
              padding: EdgeInsets.all(spacing.x3),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(tokens.radius.small),
              ),
              child: Text(value, style: style),
            )
          else
            Text(value, style: style),
        ],
      ),
    );
  }
}

/// 第一次「在 GitHub 回報」前的提醒（repo 是公開的）。回傳 `true`：繼續並不再提醒；
/// `false`：只繼續；`null`（取消、點外面）：什麼都不做。
class _ReminderDialog extends ConsumerStatefulWidget {
  const _ReminderDialog();

  @override
  ConsumerState<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends ConsumerState<_ReminderDialog> {
  var _dontAsk = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).errorReport;
    return AlertDialog(
      title: Text(t.reminderTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.reminderBody),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _dontAsk,
            title: Text(t.reminderDontAsk),
            onChanged: (value) => setState(() => _dontAsk = value ?? false),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_dontAsk),
          child: Text(t.reminderContinue),
        ),
      ],
    );
  }
}
