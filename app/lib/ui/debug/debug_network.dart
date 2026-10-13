import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/debug/debug_log_state.dart';
import 'package:fmp/ui/debug/debug_network_state.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/format/byte_size.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// Debug 頁的「網路」（ADR 0025 §決定 4）：這次執行的網路紀錄（log 門面裡 tag `network`
/// 的那些，不另存一份），最新的在最上面。點一筆開單筆詳細。
class DebugNetwork extends ConsumerStatefulWidget {
  const DebugNetwork({super.key});

  @override
  ConsumerState<DebugNetwork> createState() => _DebugNetworkState();
}

class _DebugNetworkState extends ConsumerState<DebugNetwork> {
  var _filter = const NetworkFilter();

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).debug;
    final spacing = AppTokens.of(context).spacing;
    final history = ref.watch(logHistoryProvider).value ?? const <LogRecord>[];
    final all = networkEntries(history);
    if (all.isEmpty) {
      return EmptyState(
        icon: Icons.swap_vert,
        title: t.netEmpty,
        body: t.netEmptyHint,
      );
    }
    final sources = {
      for (final entry in all) entry.source,
      ?_filter.source,
    }.toList()..sort();
    final shown = [
      for (final entry in all)
        if (_filter.matches(entry)) entry,
    ];
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
                  decoration: InputDecoration(
                    hintText: t.netSearchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (text) =>
                      setState(() => _filter = _filter.copyWith(text: text)),
                ),
              ),
              SizedBox(
                width: AppLayout.debugFilterWidth,
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: _filter.source,
                  items: [
                    DropdownMenuItem(child: Text(t.netSourceAll)),
                    for (final source in sources)
                      DropdownMenuItem(
                        value: source,
                        child: Text(source.isEmpty ? t.netSourceApp : source),
                      ),
                  ],
                  onChanged: (source) => setState(
                    () => _filter = _filter.copyWith(source: () => source),
                  ),
                ),
              ),
              SizedBox(
                width: AppLayout.debugFilterWidth,
                child: DropdownButton<StatusClass?>(
                  isExpanded: true,
                  value: _filter.statusClass,
                  items: [
                    DropdownMenuItem(child: Text(t.netStatusAll)),
                    for (final statusClass in StatusClass.values)
                      DropdownMenuItem(
                        value: statusClass,
                        child: Text(_className(t, statusClass)),
                      ),
                  ],
                  onChanged: (statusClass) => setState(
                    () => _filter = _filter.copyWith(
                      statusClass: () => statusClass,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(spacing.x4, spacing.x2, spacing.x4, 0),
          child: Text(
            t.netCount(shown: shown.length, total: all.length),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? EmptyState(icon: Icons.filter_alt_off, title: t.netNoMatch)
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final entry = shown[shown.length - 1 - index];
                    return ListTile(
                      key: ObjectKey(entry.record),
                      title: Text(
                        '${entry.method} ${entry.host}${entry.path}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        _summary(t, entry),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => unawaited(_showDetail(entry)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showDetail(NetworkEntry entry) {
    final t = ref.read(translationsProvider).debug;
    final history = ref.read(logHistoryProvider).value ?? const <LogRecord>[];
    return showDialog<void>(
      context: context,
      builder: (context) => _NetworkDetail(
        t: t,
        entry: entry,
        errors: matchingErrors(entry, history),
      ),
    );
  }
}

String _className(Translations$debug$zh_TW t, StatusClass statusClass) =>
    switch (statusClass) {
      StatusClass.success => '2xx',
      StatusClass.redirect => '3xx',
      StatusClass.clientError => '4xx',
      StatusClass.serverError => '5xx',
      StatusClass.failed => t.netStatusFailed,
    };

String _statusText(Translations$debug$zh_TW t, NetworkEntry entry) =>
    entry.status?.toString() ?? t.netStatusFailed;

String _sourceText(Translations$debug$zh_TW t, NetworkEntry entry) =>
    entry.source.isEmpty ? t.netSourceApp : entry.source;

String _durationText(Translations$debug$zh_TW t, NetworkEntry entry) =>
    entry.ms == null ? t.netUnknown : t.netDuration(ms: entry.ms!);

String _sizeText(Translations$debug$zh_TW t, NetworkEntry entry) =>
    entry.bytes == null ? t.netUnknown : formatByteSize(entry.bytes!);

/// 清單上一列的第二行：時間、狀態、耗時、大小、音源。
String _summary(Translations$debug$zh_TW t, NetworkEntry entry) => [
  formatLogTime(entry.time),
  _statusText(t, entry),
  _durationText(t, entry),
  _sizeText(t, entry),
  _sourceText(t, entry),
].join(' · ');

/// 單筆詳細：遮過的 query、錯誤類型，與以 `networkRecordId` 對應的錯誤紀錄。
class _NetworkDetail extends StatelessWidget {
  const _NetworkDetail({
    required this.t,
    required this.entry,
    required this.errors,
  });

  final Translations$debug$zh_TW t;
  final NetworkEntry entry;
  final List<LogRecord> errors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    Widget fact(String label, String value) => Padding(
      padding: EdgeInsets.only(bottom: spacing.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          SelectableText(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
    return AlertDialog(
      title: Text('${entry.method} ${entry.host}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            fact(t.netDetailTime, formatLogTime(entry.time)),
            fact(t.netDetailUrl, '${entry.host}${entry.path}'),
            fact(t.netDetailQuery, entry.query ?? t.netDetailNoQuery),
            fact(t.netDetailStatus, _statusText(t, entry)),
            fact(t.netDetailError, entry.error ?? t.netDetailNoError),
            fact(t.netDetailDuration, _durationText(t, entry)),
            fact(t.netDetailSize, _sizeText(t, entry)),
            fact(t.netDetailSource, _sourceText(t, entry)),
            fact(t.netDetailClient, entry.client),
            fact(t.netDetailCredentials, entry.credentials ? t.yes : t.no),
            fact(t.netDetailRetry, '${entry.retry}'),
            Text(t.netDetailRelated, style: theme.textTheme.labelMedium),
            if (errors.isEmpty)
              Text(t.netDetailNoRelated, style: theme.textTheme.bodyMedium)
            else
              for (final record in errors)
                Padding(
                  padding: EdgeInsets.only(top: spacing.x1),
                  child: SelectableText(
                    formatLogRecord(record),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.close),
        ),
      ],
    );
  }
}
