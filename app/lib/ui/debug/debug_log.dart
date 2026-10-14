import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/ui/debug/debug_export.dart';
import 'package:fmp/ui/debug/debug_log_state.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/errors/error_detail_page.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// Debug 頁的「Log 與錯誤歷史」（ADR 0025 §決定 3）。
///
/// 預設看這次執行的記憶體歷史，最新的在最上面；「含之前的紀錄」把 log 檔讀回來合併進去
/// （`mergeLogRecords`）。「只看錯誤」就是錯誤歷史（警告以上）；點一筆在原地展開欄位、error 與
/// stackTrace；`Log.report` 寫的錯誤紀錄（有 `fields.type`）另有「詳細」，開 `ErrorDetailPage`。
class DebugLog extends ConsumerStatefulWidget {
  const DebugLog({super.key});

  @override
  ConsumerState<DebugLog> createState() => _DebugLogState();
}

class _DebugLogState extends ConsumerState<DebugLog> {
  var _filter = const LogFilter();
  var _earlier = false;
  final _search = TextEditingController();

  // 合併很貴（最多 6MB 的紀錄），輸入搜尋字時不重做：來源兩份清單沒換就沿用。
  List<LogRecord>? _mergedMemory;
  List<LogRecord>? _mergedStored;
  List<LogRecord> _merged = const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<LogRecord> _records(List<LogRecord> memory, List<LogRecord> stored) {
    if (!_earlier) return memory;
    if (!identical(memory, _mergedMemory) ||
        !identical(stored, _mergedStored)) {
      _mergedMemory = memory;
      _mergedStored = stored;
      _merged = mergeLogRecords(stored, memory);
    }
    return _merged;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).debug;
    final spacing = AppTokens.of(context).spacing;
    final hasFile = ref.watch(logProvider.select((log) => log.file != null));
    final capabilities = ref.watch(platformCapabilitiesProvider);
    final memory = ref.watch(logHistoryProvider).value ?? const <LogRecord>[];
    final stored = _earlier ? ref.watch(storedLogRecordsProvider) : null;
    final all = _records(memory, stored?.value ?? const <LogRecord>[]);
    final tags = {for (final record in all) record.tag, ?_filter.tag}.toList()
      ..sort();
    final shown = [
      for (final record in all)
        if (_filter.matches(record)) record,
    ];
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(spacing.x4, spacing.x2, spacing.x4, 0),
          child: Wrap(
            spacing: spacing.x2,
            runSpacing: spacing.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: AppLayout.debugFilterWidth,
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: t.logSearchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (text) =>
                      setState(() => _filter = _filter.copyWith(text: text)),
                ),
              ),
              SizedBox(
                width: AppLayout.debugFilterWidth,
                child: DropdownButton<LogLevel>(
                  isExpanded: true,
                  value: _filter.level,
                  items: [
                    for (final level in LogLevel.values)
                      DropdownMenuItem(
                        value: level,
                        child: Text(
                          level == LogLevel.debug
                              ? t.filterLevelAll
                              : t.filterLevelFrom(level: level.wireName),
                        ),
                      ),
                  ],
                  onChanged: (level) {
                    if (level == null) return;
                    setState(() => _filter = _filter.copyWith(level: level));
                  },
                ),
              ),
              SizedBox(
                width: AppLayout.debugFilterWidth,
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: _filter.tag,
                  items: [
                    DropdownMenuItem(child: Text(t.filterTagAll)),
                    for (final tag in tags)
                      DropdownMenuItem(value: tag, child: Text(tag)),
                  ],
                  onChanged: (tag) => setState(
                    () => _filter = _filter.copyWith(tag: () => tag),
                  ),
                ),
              ),
              FilterChip(
                label: Text(t.errorsOnly),
                selected: _filter.errorsOnly,
                onSelected: (on) =>
                    setState(() => _filter = _filter.copyWith(errorsOnly: on)),
              ),
              if (hasFile)
                FilterChip(
                  label: Text(t.includeEarlier),
                  selected: _earlier,
                  onSelected: (on) => setState(() => _earlier = on),
                ),
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: t.logCopy,
                onPressed: () => unawaited(_copy(shown)),
              ),
              if (hasFile && (capabilities.files || capabilities.shareFiles))
                PopupMenuButton<ExportAction>(
                  icon: const Icon(Icons.ios_share),
                  tooltip: t.logExport,
                  onSelected: (action) => unawaited(
                    exportBundle(
                      context,
                      ref,
                      kind: ExportKind.logs,
                      action: action,
                    ),
                  ),
                  itemBuilder: (_) => [
                    if (capabilities.files)
                      PopupMenuItem(
                        value: ExportAction.save,
                        child: Text(t.logExportSave),
                      ),
                    if (capabilities.shareFiles)
                      PopupMenuItem(
                        value: ExportAction.share,
                        child: Text(t.logExportShare),
                      ),
                  ],
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: t.logClear,
                onPressed: () => unawaited(_clear()),
              ),
            ],
          ),
        ),
        if (stored != null && stored.isLoading)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.x4),
            child: Semantics(
              label: t.earlierLoading,
              child: const LinearProgressIndicator(),
            ),
          ),
        if (stored != null && stored.hasError)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.x4),
            child: Text(
              t.earlierFailed,
              style: textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(spacing.x4, spacing.x2, spacing.x4, 0),
          child: Text(
            t.logCount(shown: shown.length, total: all.length),
            style: textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? EmptyState(
                  icon: all.isEmpty
                      ? Icons.article_outlined
                      : Icons.filter_alt_off,
                  title: all.isEmpty ? t.logEmpty : t.logNoMatch,
                )
              : ListView.builder(
                  itemCount: shown.length,
                  // 最新的在最上面。
                  itemBuilder: (context, index) {
                    final record = shown[shown.length - 1 - index];
                    return _LogRow(key: ObjectKey(record), record: record);
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _copy(List<LogRecord> shown) async {
    final t = ref.read(translationsProvider).debug;
    final toaster = ref.read(toasterProvider);
    if (shown.isEmpty) {
      toaster.info(t.logCopyNothing);
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: shown.map(formatLogRecord).join('\n')),
    );
    toaster.info(t.logCopied(count: shown.length));
  }

  Future<void> _clear() async {
    final t = ref.read(translationsProvider).debug;
    final toaster = ref.read(toasterProvider);
    final log = ref.read(logProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.logClearTitle),
        content: Text(t.logClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.logClear),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await log.clear();
      toaster.success(t.logCleared);
    } on FileSystemException catch (error, stackTrace) {
      // 記憶體歷史已經清掉了，只有檔案沒刪成。
      log.warning(
        'Clearing the log files failed',
        tag: 'debug',
        error: error,
        stackTrace: stackTrace,
      );
      toaster.warning(t.logClearFailed);
    }
    if (mounted && _earlier) ref.invalidate(storedLogRecordsProvider);
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({super.key, required this.record});

  final LogRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final (icon, color) = switch (record.level) {
      LogLevel.debug => (Icons.bug_report_outlined, theme.colorScheme.outline),
      LogLevel.info => (Icons.info_outline, theme.colorScheme.primary),
      LogLevel.warning => (Icons.warning_amber_outlined, tokens.warning.color),
      LogLevel.error => (Icons.error_outline, theme.colorScheme.error),
    };
    final title = Text(
      record.message,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final subtitle = Text(
      '${formatLogTime(record.time)} · ${record.level.wireName} · ${record.tag}',
    );
    final leading = ExcludeSemantics(child: Icon(icon, color: color));
    // `Log.report` 寫的錯誤紀錄才有類型欄位：開詳細頁（ADR 0023 §決定 4、ADR 0025 §決定 3）。
    final isError = record.fields['type'] is String;
    final hasDetail =
        record.fields.isNotEmpty ||
        record.error != null ||
        record.stackTrace != null;
    if (!hasDetail) {
      return ListTile(leading: leading, title: title, subtitle: subtitle);
    }
    return ExpansionTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: EdgeInsets.fromLTRB(
        tokens.spacing.x4,
        0,
        tokens.spacing.x4,
        tokens.spacing.x2,
      ),
      children: [
        // 可選取但不是 `SelectableText`：多行的 `SelectableText` 有長按動作，兩行高時過不了
        // 48dp 的點擊目標 guideline（`guidelines_test.dart` 的 `the Debug Log section`）。
        SelectionArea(
          child: Text(
            // 時間、層級、tag、訊息清單上已經有了。
            formatLogDetails(record).trimLeft(),
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (isError)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Consumer(
              builder: (context, ref, _) => TextButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: Text(ref.watch(translationsProvider).debug.logDetail),
                onPressed: () =>
                    unawaited(openErrorDetail(Navigator.of(context), record)),
              ),
            ),
          ),
      ],
    );
  }
}
