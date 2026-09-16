/// 播放結束原因只准在一個地方被拆開。
///
/// `PlaybackEventRouter` 之前，`AudioController._onPlaybackEnded` 自己 switch
/// 每一種 `PlaybackEndReason`，於是「電台例外」「載入中忽略」「裝置失敗過就不
/// 重試」這些規則散在處理函式裡，只能靠架一整個控制器反推。把它們搬進純函數
/// 之後，唯一會讓它們悄悄長回來的方式就是有人在控制器裡再加一個
/// `case EndedPrematurely(...)` —— 那不會編譯錯誤，也不會讓任何行為測試變紅，
/// 只會讓路由變成兩處，而第二處沒有測試。
///
/// 規則因此是位置：**拆開 `PlaybackEndReason` 的型樣比對只准出現在
/// `playback_event_router.dart`**。後端那三個檔案是**建構**這些變體，不是比對
/// 它們，所以不受影響。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/dart_source.dart';

const _controller = 'lib/services/audio/audio_provider.dart';
const _router = 'lib/services/audio/playback_event_router.dart';

/// `PlaybackEndReason` 的全部變體。少一個這條規則就漏一格，所以它是寫死的清單
/// 而不是掃出來的 —— 新增變體時這裡跟著加一行。
const _endReasonVariants = <String>[
  'EndedNaturally',
  'EndedPrematurely',
  'TransportFailed',
  'OutputDeviceFailed',
  'MediaUnopenable',
  'DecoderFailed',
  'UnclassifiedFailure',
];

/// 這份原始碼裡「拆開結束原因」的每一處。
///
/// 只認型樣比對（`case X(...)`、`x case X(...)`、`is X`）與 `switch (reason)`：
/// **建構一個變體不算**。位置檢查備援必須造得出 `const EndedNaturally()` 來補
/// 後端弄丟的那一次完成事件，那是發事件，不是做決定。
List<String> endReasonPatternMatches(String source) {
  final code = stripDartComments(source);
  final matches = <String>[];

  if (RegExp(r'switch\s*\(\s*reason\s*\)').hasMatch(code)) {
    matches.add('switch (reason)');
  }
  for (final variant in _endReasonVariants) {
    if (RegExp('case\\s+$variant\\b').hasMatch(code)) {
      matches.add('case $variant');
    }
    if (RegExp('is\\s+$variant\\b').hasMatch(code)) {
      matches.add('is $variant');
    }
  }
  return matches;
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('playback end reason routing lives in one file', () {
    test('the controller never pattern-matches an end reason', () {
      expect(
        endReasonPatternMatches(_read(_controller)),
        isEmpty,
        reason:
            'Routing decisions belong to $_router. Add a PlaybackAction '
            'variant and a router test instead of a case in the controller.',
      );
    });

    test('the router still holds the switch it is supposed to hold', () {
      // 沒有這一條，整批規則被改名或搬走時上面那條會安靜地全綠。
      final matches = endReasonPatternMatches(_read(_router));
      expect(matches, contains('switch (reason)'));
      for (final variant in _endReasonVariants) {
        expect(
          matches,
          contains('case $variant'),
          reason: '$variant lost its row in the router',
        );
      }
    });

    test('nothing else under lib/ pattern-matches an end reason', () {
      final offenders = <String>[];
      var scanned = 0;
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (path == _router) continue;
        scanned++;
        if (endReasonPatternMatches(entity.readAsStringSync()).isNotEmpty) {
          offenders.add(path);
        }
      }

      // 掃描本身要有作用 —— 路徑寫錯時 offenders 也會是空的。
      expect(scanned, greaterThan(200));
      expect(offenders, isEmpty);
    });
  });

  group('the routing detector', () {
    test('catches a violation put back into the controller', () {
      const switched = '''
void _onPlaybackEnded(PlaybackEndReason reason) {
  switch (reason) {
    case EndedNaturally():
      _onTrackCompleted();
    case EndedPrematurely(:final at):
      _recoverFromPrematureCompletion(at);
  }
}
''';
      const ifCase = '''
void _onPlaybackEnded(PlaybackEndReason reason) {
  if (reason case OutputDeviceFailed(:final raw)) {
    _reportOutputDeviceFailure(raw);
  }
}
''';
      const typeTest = '''
void _onPlaybackEnded(PlaybackEndReason reason) {
  if (reason is DecoderFailed) _reopenAfterMediaFailure('');
}
''';

      expect(endReasonPatternMatches(switched), contains('switch (reason)'));
      expect(
        endReasonPatternMatches(switched),
        contains('case EndedNaturally'),
      );
      expect(
        endReasonPatternMatches(ifCase),
        contains('case OutputDeviceFailed'),
      );
      expect(endReasonPatternMatches(typeTest), contains('is DecoderFailed'));
    });

    test('an unrelated rename still passes', () {
      // 把處理函式改名、把動作型別改名，都不該讓這條規則變紅。
      const renamed = '''
void _handleBackendEnd(PlaybackEndReason stopReason) {
  unawaited(_apply(PlaybackEventRouter.routeEnd(stopReason, _eventContext())));
}

void _reportOutputDeviceFailure(ReportOutputDeviceFailure action) {
  logError(action.raw);
}

void _recoverTransportFailure(RecoverTransportFailure action) {
  _onTransportFailure(action.failure);
}
''';

      expect(endReasonPatternMatches(renamed), isEmpty);
    });

    test('constructing a variant is not a routing decision', () {
      const synthesized = '''
void _synthesizeCompletion(Duration position, Duration duration) {
  _onPlaybackEnded(const EndedNaturally());
}

void _onTransportFailure(TransportFailed failure) {
  logError('\$failure');
}
''';

      expect(endReasonPatternMatches(synthesized), isEmpty);
    });

    test('a violation written in a comment does not count', () {
      const commented = '''
// 這裡曾經是 `case OutputDeviceFailed(:final raw)`，現在交給路由決定。
void _onPlaybackEnded(PlaybackEndReason reason) {
  unawaited(_apply(PlaybackEventRouter.routeEnd(reason, _eventContext())));
}
''';

      expect(endReasonPatternMatches(commented), isEmpty);
    });
  });
}
