import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/search/search.dart';
import 'package:material_ui/material_ui.dart';

/// 搜尋欄的文字。欄位依寬度放在不同地方（手機的 dock、中寬度的搜尋頁頂端、
/// 桌面的側欄），同一時間只有一個；它們共用這一份，離開搜尋再回來或換寬度
/// 時打過的字還在。
final searchQueryProvider = Provider<TextEditingController>((ref) {
  final controller = TextEditingController();
  ref.onDispose(controller.dispose);
  return controller;
});

/// 要搜尋欄取得焦點（例如桌面按 ⌘K）。中寬度的欄位在搜尋頁裡，按下時可能
/// 還沒建出來，所以這是一個待辦：顯示著的欄位、或下一個建出來的欄位接手並
/// 清掉它。
final searchFocusRequestProvider = NotifierProvider<SearchFocusRequest, bool>(
  SearchFocusRequest.new,
);

class SearchFocusRequest extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;

  void consume() => state = false;
}

/// 用搜尋欄目前的文字搜尋（也記進搜尋紀錄）。
void submitSearch(WidgetRef ref) => ref
    .read(searchProvider.notifier)
    .search(ref.read(searchQueryProvider).text);

/// 用 [query] 搜尋並把它填進搜尋欄（點搜尋紀錄時）。
void searchFor(WidgetRef ref, String query) {
  ref.read(searchQueryProvider).text = query;
  ref.read(searchProvider.notifier).search(query);
}

/// 音源篩選：只看哪個插件的結果，null 是全部。換搜尋時留著（設計稿：篩選
/// 記住上一次的選擇），App 重開回到全部。
final searchFilterProvider = NotifierProvider<SearchFilter, String?>(
  SearchFilter.new,
);

class SearchFilter extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? pluginId) => state = pluginId;
}
