import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/search_history_repository.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 搜尋歷史，最新的在前（ADR 0035 §決定 9）；表一變動就重讀。讀失敗時當作沒有歷史：
/// 這是搜尋框的輔助，不值得一個錯誤畫面。
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
                onPressed: () => unawaited(repository.clear()),
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
                title: Text(entry.query, maxLines: 1),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: t.historyDelete,
                  onPressed: () => unawaited(repository.delete(entry.query)),
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
