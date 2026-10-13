import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/database_inspector.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// Debug 頁的「資料庫」（ADR 0025 §決定 8）：唯讀。表清單與筆數，點進去看分頁的列（值已經
/// 由 [DatabaseInspector] 遮蔽），「檢查」只報告、不修。備份、還原、重設在 M3 PR 14b。
class DebugDatabase extends ConsumerStatefulWidget {
  const DebugDatabase({super.key});

  @override
  ConsumerState<DebugDatabase> createState() => _DebugDatabaseState();
}

class _DebugDatabaseState extends ConsumerState<DebugDatabase> {
  /// 畫面上一格最多顯示的字數；整格的值太長（manifest、腳本）時截斷。
  static const _cellLength = 120;

  late Future<List<TableCount>> _tables;
  String? _table;
  var _page = 0;
  Future<TablePage>? _rows;
  Future<DatabaseCheckReport>? _report;

  @override
  void initState() {
    super.initState();
    _tables = ref.read(databaseInspectorProvider).tables();
  }

  /// 開表 [table] 的第 [page] 頁；`null` 回到清單，筆數重讀（看表的期間 App 可能寫過）。
  void _open(String? table, [int page = 0]) {
    final inspector = ref.read(databaseInspectorProvider);
    setState(() {
      _table = table;
      _page = page;
      _rows = table == null ? null : inspector.rows(table, page);
      if (table == null) _tables = inspector.tables();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).debug;
    final spacing = AppTokens.of(context).spacing;
    final theme = Theme.of(context);
    final table = _table;
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
              if (table != null)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: t.dbBack,
                  onPressed: () => _open(null),
                ),
              Text(table ?? t.dbTables, style: theme.textTheme.titleMedium),
              OutlinedButton.icon(
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(t.dbCheck),
                onPressed: () {
                  final report = ref.read(databaseInspectorProvider).check();
                  setState(() {
                    _report = report;
                  });
                },
              ),
            ],
          ),
        ),
        if (_report case final report?)
          Padding(
            padding: EdgeInsets.fromLTRB(spacing.x4, spacing.x2, spacing.x4, 0),
            child: _CheckReport(report: report),
          ),
        Expanded(child: table == null ? _tableList(t) : _tableRows(t, table)),
      ],
    );
  }

  Widget _tableList(Translations$debug$zh_TW t) =>
      FutureBuilder<List<TableCount>>(
        future: _tables,
        builder: (context, snapshot) {
          final tables = snapshot.data;
          if (snapshot.hasError) {
            return EmptyState(icon: Icons.error_outline, title: t.dbLoadFailed);
          }
          if (tables == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: [
              for (final entry in tables)
                ListTile(
                  title: Text(entry.name),
                  trailing: Text(t.dbRowCount(count: entry.count)),
                  onTap: () => _open(entry.name),
                ),
            ],
          );
        },
      );

  Widget _tableRows(Translations$debug$zh_TW t, String table) {
    final spacing = AppTokens.of(context).spacing;
    return FutureBuilder<TablePage>(
      future: _rows,
      builder: (context, snapshot) {
        final page = snapshot.data;
        if (snapshot.hasError) {
          return EmptyState(icon: Icons.error_outline, title: t.dbLoadFailed);
        }
        if (page == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final pages = (page.total / DatabaseInspector.pageSize).ceil();
        final pageCount = pages < 1 ? 1 : pages;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.x4,
                vertical: spacing.x2,
              ),
              child: Wrap(
                spacing: spacing.x2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: t.dbPrevious,
                    onPressed: _page > 0 ? () => _open(table, _page - 1) : null,
                  ),
                  Text(
                    t.dbPage(
                      page: _page + 1,
                      pages: pageCount,
                      total: page.total,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: t.dbNext,
                    onPressed: _page + 1 < pageCount
                        ? () => _open(table, _page + 1)
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: page.rows.isEmpty
                  ? EmptyState(
                      icon: Icons.table_rows_outlined,
                      title: t.dbNoRows,
                    )
                  : _grid(t, page),
            ),
          ],
        );
      },
    );
  }

  Widget _grid(Translations$debug$zh_TW t, TablePage page) {
    String cell(String? value) {
      if (value == null) return t.dbNull;
      return value.length <= _cellLength
          ? value
          : '${value.substring(0, _cellLength)}…';
    }

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            for (final column in page.columns) DataColumn(label: Text(column)),
          ],
          rows: [
            for (final row in page.rows)
              DataRow(
                cells: [
                  for (final value in row)
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppLayout.debugCellWidth,
                        ),
                        child: Text(
                          cell(value),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 「檢查」的結果：三項各一列；整體沒問題時標題說沒有問題。
class _CheckReport extends ConsumerWidget {
  const _CheckReport({required this.report});

  final Future<DatabaseCheckReport> report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).debug;
    return FutureBuilder<DatabaseCheckReport>(
      future: report,
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (snapshot.hasError) return Text(t.dbCheckFailed);
        if (result == null) return Text(t.dbChecking);
        Widget item(String label, String value) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: SelectableText(value),
        );
        return Card(
          child: Padding(
            padding: EdgeInsets.all(AppTokens.of(context).spacing.x2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.hasProblems ? t.dbCheckProblems : t.dbCheckClean,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                item(
                  t.dbIntegrity,
                  result.integrityMessages.isEmpty
                      ? t.dbOk
                      : result.integrityMessages.join('\n'),
                ),
                item(
                  t.dbForeignKeys,
                  result.foreignKeyViolations.isEmpty
                      ? t.dbOk
                      : [
                          for (final violation in result.foreignKeyViolations)
                            t.dbViolation(
                              table: violation.table,
                              rowId: '${violation.rowId ?? '?'}',
                              parent: violation.parent,
                            ),
                        ].join('\n'),
                ),
                item(t.dbOrphans, t.dbOrphansValue(count: result.orphanTracks)),
              ],
            ),
          ),
        );
      },
    );
  }
}
