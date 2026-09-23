/// `lib/` 裡每一個 `Timer.periodic` / `Stream.periodic` 都要在 [_timers] 上有名字。
///
/// 週期性 timer 是這個 app 在使用者什麼都沒按的時候自己做事的地方：DNS 輪詢、
/// 電台輪詢、排行榜與歌單刷新都是這樣長出來的，而新增一個不需要任何人同意，
/// 也沒有任何東西會紅。這條規則把「加一個」變成「改這份名單並回答兩個問題」：
/// 誰要的（需求來源），使用者關不關得掉。
///
/// **比的是集合，不是字串存在。** 每個檔案的呼叫次數要等於名單上那個檔案的列數，
/// 多一個、少一個都紅；改變數名、重排名單、`dart format` 斷行都不紅 —— 兩個方向
/// 都由本檔最後兩條測試示範。以檔案計次而不是認變數名，是因為變數名會被重新
/// 命名，而重新命名不該要求任何人重新回答「誰要的」。
///
/// 看不到的：套件自己開的 timer，以及用 `Future.delayed` 自己排下一輪的迴圈。
/// 後者目前沒有；出現的話把它改成 `Timer.periodic`，或在這裡加上它的形狀。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_source.dart';

/// 一個週期性 timer 做什麼、誰要的、使用者關不關得掉。
///
/// 需求來源寫 issue / PR；沒有的就寫引入它的 commit，並照實寫「沒有 issue / PR」
/// —— 那一欄空著的樣子本身就是資訊。
class _Periodic {
  const _Periodic(this.what, {required this.source, required this.canTurnOff});

  final String what;
  final String source;
  final String canTurnOff;
}

const _timers = <String, List<_Periodic>>{
  'lib/services/network/connectivity_service.dart': [
    _Periodic(
      '對三個公共 DNS 做解析，判斷有沒有網路；恢復時通知排行榜重抓',
      source: '`512fc470` 換掉 connectivity_plus 時引入，沒有 issue / PR',
      canTurnOff: '不能。2026-09 決定不改行為，只列在這裡與對外主機清單上',
    ),
  ],
  'lib/services/cache/ranking_cache_service.dart': [
    _Periodic(
      '重抓首頁排行榜',
      source: '`c7a77242` 引入、`92c249d2` 加間隔設定，沒有 issue / PR',
      canTurnOff: '不能；設定 > 排行榜刷新間隔可調',
    ),
  ],
  'lib/services/library/auto_refresh_service.dart': [
    _Periodic(
      '檢查哪些匯入歌單到了刷新時間並刷新',
      source: '`d5ddd7e7` 引入，沒有 issue / PR',
      canTurnOff: '每個匯入歌單各自設定，預設不刷新；timer 本身只讀資料庫，不能關',
    ),
  ],
  'lib/services/radio/radio_refresh_service.dart': [
    _Periodic(
      '輪詢每個電台的直播狀態（Bilibili）',
      source: '`c4fc940b` 引入；風控退避與背景暫停是 #95',
      canTurnOff: '能：設定 > 電台刷新間隔 > 關閉；App 在背景時暫停',
    ),
  ],
  'lib/services/radio/radio_controller.dart': [
    _Periodic(
      '收聽電台時每秒更新已播放時長',
      source: '`0dfc33a9` 電台功能本身',
      canTurnOff: '不適用：本機計時，只在收聽時跑',
    ),
    _Periodic(
      '收聽電台時刷新直播間資訊（Bilibili）',
      source: '`0dfc33a9` 電台功能本身',
      canTurnOff: '停止收聽就停',
    ),
  ],
  'lib/services/audio/audio_provider.dart': [
    _Periodic(
      '播放中檢查位置，後台漏掉 completed 事件時補切下一首',
      source: '`e9f07c3d` 背景播放不會接下一首',
      canTurnOff: '不適用：本機，只在播放時跑',
    ),
  ],
  'lib/services/audio/queue_manager.dart': [
    _Periodic(
      '定期把播放位置寫進資料庫',
      source: '`4f140894` 播放功能本身',
      canTurnOff: '不適用：本機',
    ),
  ],
  'lib/services/download/download_service.dart': [
    _Periodic(
      '把下載 isolate 回報的進度彙整後一次發佈',
      source: '`9d885bfd` isolate 下載',
      canTurnOff: '不適用：本機',
    ),
    _Periodic('排程下一個待下載任務', source: '`c98a1cbb` 下載功能本身', canTurnOff: '不適用：本機'),
  ],
  'lib/ui/widgets/panels/comment_pager.dart': [
    _Periodic(
      '評論區在畫面內時自動翻到下一則',
      source: '詳情面板的熱評輪播',
      canTurnOff: '不適用：本機，只在面板開著時跑',
    ),
  ],
};

/// `Stream<int>.periodic(...)` 的型別參數寫在類別名後面，也要認得。
final _periodicCall = RegExp(
  r'\b(?:Timer|Stream)\s*(?:<[^<>()]*>)?\s*\.\s*periodic\s*[(<]',
);

/// 每個檔案裡有幾個週期性 timer 的呼叫。沒有的檔案不列。
Map<String, int> periodicCallCounts(Map<String, String> sourcesByPath) => {
  for (final MapEntry(key: path, value: source) in sourcesByPath.entries)
    if (_periodicCall.allMatches(stripDartComments(source)).length
        case final count when count > 0)
      path: count,
};

Map<String, int> _expectedCounts(Map<String, List<_Periodic>> timers) => {
  for (final MapEntry(key: path, value: entries) in timers.entries)
    path: entries.length,
};

void main() {
  group('periodic timers', () {
    test('every periodic timer in lib/ is on the list', () {
      final sources = <String, String>{};
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (!path.endsWith('.dart') || path.endsWith('.g.dart')) continue;
        sources[path] = entity.readAsStringSync();
      }

      // 掃描本身要有作用 —— 路徑寫錯時兩邊都會是空的。
      expect(sources.length, greaterThan(300));
      expect(
        periodicCallCounts(sources),
        equals(_expectedCounts(_timers)),
        reason:
            'A periodic timer was added, removed or moved. Update _timers in '
            'this file, and for a new one say who asked for it and whether '
            'the user can turn it off.',
      );
    });

    test('every entry answers both questions', () {
      for (final entries in _timers.values) {
        for (final entry in entries) {
          expect(entry.what, isNotEmpty);
          expect(entry.source, isNotEmpty, reason: entry.what);
          expect(entry.canTurnOff, isNotEmpty, reason: entry.what);
        }
      }
    });

    test('an unlisted timer turns the rule red', () {
      const listed = '''
void start() {
  _poll = Timer.periodic(interval, (_) => poll());
}
''';
      const withExtra = '''
void start() {
  _poll = Timer.periodic(interval, (_) => poll());
  _extra = Stream<void>.periodic(interval).listen((_) => ping());
}
''';
      final expected = {'lib/a.dart': 1};

      expect(periodicCallCounts({'lib/a.dart': listed}), equals(expected));
      expect(
        periodicCallCounts({'lib/a.dart': withExtra}),
        isNot(equals(expected)),
      );
      expect(
        periodicCallCounts({'lib/a.dart': listed, 'lib/b.dart': listed}),
        isNot(equals(expected)),
        reason: 'the same timer in a new file is a new timer',
      );
    });

    test('renaming, reformatting and reordering do not', () {
      const reformatted = '''
/// 以前寫成 `Timer.periodic(interval, poll)`，註解不算。
void start() {
  // Timer.periodic(interval, (_) => legacy());
  _renamedPollingTimer =
      Timer
          .periodic(
        interval,
        (_) => poll(),
      );
}
''';
      const oneShot = 'void f() => Timer(delay, g);';

      expect(
        periodicCallCounts({'lib/b.dart': oneShot, 'lib/a.dart': reformatted}),
        equals({'lib/a.dart': 1}),
      );
      expect(
        _expectedCounts(Map.fromEntries(_timers.entries.toList().reversed)),
        equals(_expectedCounts(_timers)),
      );
    });
  });
}
