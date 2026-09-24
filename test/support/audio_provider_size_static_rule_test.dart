/// `audio_provider.dart` 不准再長大。
///
/// 控制器拆分那一輪有一條「`AudioController` ≤ 800 行」驗收線。它被正確地退休了
/// —— 剩下的行是投影與 transport 命令，也就是這個類別的定義本身，再抽協作者只會
/// 把定義搬到別處。但退休之後**沒有任何東西接手**：同一份驗收表預言「`Notifier`
/// 改寫會降到 800 行」，改寫做完檔案是 2,561 → 2,906，預言被自己的執行推翻。
///
/// 這條測試不是要把檔案變小，是要讓「又長大了」變成一次明確的決定，而不是
/// 十七個 commit 各加二十行的結果。
///
/// **量的是程式碼行，不是總行數** —— 空行與純註解行不算。抄 ESLint `max-lines`
/// 的 `skipBlankLines` / `skipComments`
/// (<https://eslint.org/docs/latest/rules/max-lines>)。理由是這棵樹剛把一批
/// `AGENTS.md` 規則搬進 dartdoc：用總行數當閘門等於處罰寫文檔。
///
/// 兩個方向都會紅，這是刻意的：
///
/// - **超過上限** —— 把新規則搬進協作者，或在同一個 commit 裡調高上限並在 body
///   說明為什麼這些行必須留在控制器裡。
/// - **低於上限超過 [_slack]** —— 抽取成功了，把上限跟著調下來，否則閘門會慢慢
///   鬆掉。棘輪只往一個方向走（`betterer` 的做法，
///   <https://github.com/phenomnomnominal/betterer>）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_source.dart';

const _path = 'lib/services/audio/audio_provider.dart';

/// 2026-09-24：暫停中斷線不再排重試，等按播放才重新開流。「暫停著就不重試」
/// 這個決定已放在 `PlaybackEventRouter`（`DeferTransportFailureUntilPlay`）；
/// 留在控制器的是「哪一首斷過」這個欄位、兩個播放請求入口清掉它、按播放時
/// 重新開流的那一條路 —— 都是播放路徑上的狀態與副作用。
///
/// 上一格 2,169 是 2026-09-23 第三次調整：放棄時清掉「已經救過一次」的記號，
/// 使用者重播同一首才有自己的一次救援。記號是控制器的欄位，清它的地方只能在
/// 控制器。
///
/// 再上一格 2,168 是同一天第二次調整：第二次緩衝逾時改成跟媒體開啟失敗一樣收尾
/// —— 停後端、補發通知欄 / SMTC。停後端與發佈都是副作用，路由那邊只負責說
/// 「該失敗了」，沒有可以搬出去的決定。
///
/// 再上一格 2,161 是同一天稍早的值：離開載入時把後端當下狀態補走一次路由，緩衝
/// 看門狗才等得到開流時就進入的 buffering（Windows 零位元組串流）。只有控制器
/// 知道載入何時結束，後端在 `playUrl` 返回前補發的事件會先到、照樣被抑制。
///
/// 再上一格 2,155 是 2026-09-17 的值：Mix 補歌邊界不再在套用端做決定（等完就交回
/// router 重判），加上 `readOptional` 只剩 `playback_side_effects.dart` 那一份。
///
/// 再上一格 2,167 是 2026-09-16 後端事件路由抽成 `playback_event_router.dart`
/// 之後的值；再上一格是 2,178（issue #106 的輸出裝置重試抑制）。那一輪**只降了
/// 十一行**，而那不是抽取失敗：搬走的一百多行路由條件，換回來的是一張快照建構
/// 子（協作者一律在那裡問完）與一個二十格的 `switch`。買的是「每一條路由決定
/// 都變成純斷言」，不是行數 —— 決定住在 `PlaybackEventRouter`，控制器只剩下
/// 副作用本身。
const _maxCodeLines = 2184;

/// 低於上限多少行就要求把上限調下來。
const _slack = 50;

/// 非空、非註解的行數。`/* */` 區塊註解也不算 —— 以前只跳過 `//` 開頭的行，
/// 區塊註解裡 ` * ` 開頭的每一行都被算成程式碼。
int codeLines(String source) => stripDartComments(
  source,
).split('\n').where((line) => line.trim().isNotEmpty).length;

/// 行數出了棘輪的範圍時說明是哪一邊，在範圍內回 null。
String? ratchetProblem(int actual, {int max = _maxCodeLines}) {
  if (actual > max) return 'grew';
  if (actual <= max - _slack) return 'shrank';
  return null;
}

void main() {
  group('AudioController size ratchet', () {
    test('audio_provider.dart does not grow', () {
      final actual = codeLines(File(_path).readAsStringSync());

      expect(
        ratchetProblem(actual),
        isNull,
        reason: switch (ratchetProblem(actual)) {
          'grew' =>
            '$_path grew to $actual code lines (limit $_maxCodeLines). Move '
                'the new rule into a collaborator, or raise the limit in this '
                'same commit and say in the body why those lines belong on the '
                'controller.',
          _ =>
            '$_path is down to $actual code lines. Lower _maxCodeLines to '
                'that number so the gate keeps its grip.',
        },
      );
    });

    test('growing past the limit or shrinking past the slack is red', () {
      expect(ratchetProblem(1000, max: 1000), isNull);
      expect(ratchetProblem(1001, max: 1000), 'grew');
      expect(ratchetProblem(1000 - _slack, max: 1000), 'shrank');
      expect(ratchetProblem(1000 - _slack + 1, max: 1000), isNull);
    });

    test('comments, dartdoc and blank lines do not move the count', () {
      const code = '''
int a = 1;
int b = 2;
''';
      const documented = '''
/// dartdoc
int a = 1;

// a comment
/*
 * a block comment
 */
  int b = 2; // trailing
''';

      expect(codeLines(code), 2);
      expect(codeLines(documented), 2);
      expect(codeLines('${code}int c = 3;\n'), 3);
    });
  });
}
