/// 幾個「狀態很寬、變動很頻繁」的 provider 不准被整包 `ref.watch`。
///
/// 整包 watch 一樣會顯示正確的資料，只是任何一個欄位變動都重建整個 widget：
/// 播放控制器每次進度更新、排行榜任一音源回來、選取模式裡點一列、下載進度
/// 每一筆回報。沒有錯誤訊息，只有掉幀 —— 所以只有讀源碼抓得到。該用
/// `.select(...)` 取自己要的欄位，或用已經收窄的衍生 provider（例如下載管理頁的
/// 每一列用 `downloadTaskProgressProvider(task.id)`）。
///
/// **比的是集合。** 全 `lib/` 裡整包 watch 這些 provider 的 (檔案, provider) 要是
/// 空集合；換行、尾逗號都認得，`.select` / `.notifier` / `ref.read` 與註解不算 ——
/// 兩個方向都由本檔最後兩條測試示範。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/dart_source.dart';

/// provider → 為什麼不能整包 watch。
const _narrowOnly = <String, String>{
  'audioControllerProvider': '播放進度每秒更新好幾次',
  'rankingCacheServiceProvider': '三個音源的排行榜各自回來，每回一個就變一次',
  'searchSelectionProvider': '選取模式裡每點一列就變一次，整頁搜尋結果跟著重建',
  'playlistDetailSelectionProvider': '同上，整頁歌單詳情跟著重建',
  'downloadProgressStateProvider': '所有下載任務的進度都在這一份 map 裡，每筆回報都變',
};

final _broadWatch = RegExp(
  r'\bref\s*\.\s*watch\s*\(\s*(' + _narrowOnly.keys.join('|') + r')\s*,?\s*\)',
);

/// 整包 watch 了 [_narrowOnly] 裡某個 provider 的地方，格式是 `檔案: provider`。
Set<String> broadWatches(Map<String, String> sourcesByPath) => {
  for (final MapEntry(key: path, value: source) in sourcesByPath.entries)
    for (final match in _broadWatch.allMatches(stripDartComments(source)))
      '$path: ${match.group(1)}',
};

void main() {
  group('watch scope', () {
    test('no widget or provider watches a wide provider whole', () {
      final sources = {
        for (final entity in Directory('lib').listSync(recursive: true))
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              !entity.path.endsWith('.g.dart'))
            entity.path.replaceAll(r'\', '/'): entity.readAsStringSync(),
      };

      // 掃描本身要有作用 —— 路徑寫錯時結果也會是空集合。
      expect(sources.length, greaterThan(300));
      expect(
        broadWatches(sources),
        isEmpty,
        reason:
            'Select the fields you need instead: ${_narrowOnly.entries.map((e) => '${e.key} (${e.value})').join('; ')}',
      );
    });

    test('a whole watch turns the rule red, however it is formatted', () {
      const offender = '''
final state = ref.watch(audioControllerProvider);
final rankings = ref
    .watch(
      rankingCacheServiceProvider,
    );
''';

      expect(broadWatches({'lib/ui/a.dart': offender}), {
        'lib/ui/a.dart: audioControllerProvider',
        'lib/ui/a.dart: rankingCacheServiceProvider',
      });
    });

    test('selects, notifiers, reads, lookalikes and comments do not', () {
      const narrow = '''
// 以前寫成 ref.watch(audioControllerProvider)，整頁跟著進度重建。
final volume = ref.watch(
  audioControllerProvider.select((state) => state.volume),
);
final notifier = ref.watch(searchSelectionProvider.notifier);
final snapshot = ref.read(downloadProgressStateProvider);
final progress = ref.watch(downloadTaskProgressProvider(task.id));
final other = ref.watch(myAudioControllerProvider);
''';

      expect(broadWatches({'lib/ui/a.dart': narrow}), isEmpty);
    });
  });
}
