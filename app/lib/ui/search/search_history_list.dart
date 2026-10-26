import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/search_history_repository.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 搜尋歷史，最新的在前（ADR 0035 §決定 9）；表一變動就重讀。讀失敗時畫面當作沒有歷史
/// （這是搜尋框的輔助，不值得一個錯誤畫面），報告在搜尋頁的 `ref.listen`。
final searchHistoryProvider = StreamProvider<List<SearchHistoryEntry>>(
  (ref) => ref.watch(searchHistoryRepositoryProvider).watch(),
);

/// 搜尋框空白時顯示的歷史清單（舊版 `_buildSearchHistory`）：標題列加「清除」（不確認，同舊版），
/// 每列點一下再搜一次、尾端的叉叉刪掉這一筆。
class SearchHistoryList extends ConsumerWidget {
  const SearchHistoryList({
    required this.entries,
    required this.onSearch,
    super.key,
  });

  final List<SearchHistoryEntry> entries;

  /// 點了一筆：用它的關鍵字再搜一次。
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).search;
    final spacing = AppTokens.of(context).spacing;
    final repository = ref.read(searchHistoryRepositoryProvider);

    // 使用者的動作：失敗才提示。
    void run(Future<void> Function() write, String operation) {
      final toaster = ref.read(toasterProvider);
      unawaited(
        write().catchError(
          (Object error, StackTrace stackTrace) => toaster.error(
            AppError.wrap(error, stackTrace),
            operation: operation,
            tag: 'search',
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: spacing.x4, right: spacing.x2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t.historyTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton(
                onPressed: () =>
                    run(repository.clear, 'Failed to clear the search history'),
                child: Text(t.historyClear),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text(
                  entry.query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: t.historyDelete,
                  onPressed: () => run(
                    () => repository.delete(entry.query),
                    'Failed to remove a search history entry',
                  ),
                ),
                onTap: () => onSearch(entry.query),
              );
            },
          ),
        ),
      ],
    );
  }
}
