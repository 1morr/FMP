/// 播放歷史時間軸的惰性建構。
///
/// 展開成一整串 widget 的寫法在幾百筆歷史上就會卡住捲動，而它不會有任何錯誤 ——
/// 只是慢。行為那一半（`buildHistoryTimelineRows` 的排序與收合）在
/// `test/ui/pages/history/play_history_page_test.dart`。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _pagePath = 'lib/ui/pages/history/play_history_page.dart';

void main() {
  group('history page lazy timeline structure', () {
    test('timeline list does not expand grouped histories with spread map', () {
      final source = File(_pagePath).readAsStringSync();
      final timelineBody = _methodBody(source, '_buildTimelineList');
      final dateGroupBody = _methodBody(source, '_buildDateHeader');

      expect(timelineBody, contains('ListView.builder'));
      expect(dateGroupBody, isNot(contains('...histories.map')));
      expect(timelineBody, contains('HistoryTimelineRow'));
    });

    test('timeline rows are keyed by stable date and history ids', () {
      final source = File(_pagePath).readAsStringSync();
      final timelineBody = _methodBody(source, '_buildTimelineList');

      expect(timelineBody, matches(RegExp(r"ValueKey\(\s*'history-date-")));
      expect(timelineBody, matches(RegExp(r"ValueKey\(\s*'history-track-")));
      expect(timelineBody, contains('key:'));
    });
  });
}

String _methodBody(String source, String name) {
  final match = RegExp(
    '(?:^|\\n)\\s*[\\w<>?]+\\s+$name'
    r'\s*\(',
  ).firstMatch(source);
  expect(match, isNotNull, reason: 'method $name should exist');
  final firstBrace = source.indexOf('{', match!.start);
  var depth = 0;
  for (var i = firstBrace; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}') depth--;
    if (depth == 0) return source.substring(firstBrace, i + 1);
  }
  fail('method $name body did not close');
}
