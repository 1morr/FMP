/// `audio_provider.dart` 不准再長大。
///
/// 路線圖的 Phase 4 有一條「`AudioController` ≤ 800 行」驗收線。它被正確地退休了
/// —— 剩下的行是投影與 transport 命令，也就是這個類別的定義本身，再抽協作者只會
/// 把定義搬到別處。但退休之後**沒有任何東西接手**：同一節預言「`Notifier` 改寫會
/// 降到 800 行」，改寫做完檔案是 2,561 → 2,906，預言被自己的執行推翻。
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

const _path = 'lib/services/audio/audio_provider.dart';

/// 2026-09-09 的實測值。
const _maxCodeLines = 2184;

/// 低於上限多少行就要求把上限調下來。
const _slack = 50;

int _codeLines(String source) => source
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty && !line.startsWith('//'))
    .length;

void main() {
  group('AudioController size ratchet', () {
    test('audio_provider.dart does not grow', () {
      final actual = _codeLines(File(_path).readAsStringSync());

      expect(
        actual,
        lessThanOrEqualTo(_maxCodeLines),
        reason:
            '$_path grew to $actual code lines (limit $_maxCodeLines). Move the '
            'new rule into a collaborator, or raise the limit in this same '
            'commit and say in the body why those lines belong on the '
            'controller.',
      );

      expect(
        actual,
        greaterThan(_maxCodeLines - _slack),
        reason:
            '$_path is down to $actual code lines. Lower _maxCodeLines to that '
            'number so the gate keeps its grip.',
      );
    });

    test('the counter skips blank lines and comments', () {
      expect(
        _codeLines('''
int a = 1;

// a comment
  /// dartdoc
int b = 2;
'''),
        2,
      );
    });
  });
}
