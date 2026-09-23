/// 三份共用規則只准有一份，而且三個後端都得真的轉呼叫它。
///
/// `backend_contract_test.dart` 驗的是規則本身；規則之所以能代表三個後端，
/// 前提是後端沒有各自留一份。複製一份關鍵字表回後端不會編譯錯誤，也不會讓任何
/// 行為測試變紅 —— 兩個真後端在 `flutter test` 裡根本建不起來，第二份表要到實機
/// 上才分岔得出來（issue #41 就是這樣長出來的）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/dart_source.dart';

const _rules = 'lib/services/audio/playback_end_reason_rules.dart';
const _justAudio = 'lib/services/audio/just_audio_service.dart';
const _mediaKit = 'lib/services/audio/media_kit_audio_service.dart';
const _fake = 'test/support/fakes/fake_audio_service.dart';

/// 搬進 `playback_end_reason_rules.dart` 的關鍵字，連同引號一起比對 ——
/// 只找字串常量，不會被同名的識別符誤傷。
const _movedKeywords = <String>[
  "'audio device'",
  "'audio output'",
  "'audio driver'",
  "'[ao]'",
  "'ao:'",
  "'ffurl_read'",
  "'unreachable'",
  "'timed out'",
  "'failed to open'",
  "'cannot open'",
  "'could not open'",
  "'no such file'",
  "'could not decode'",
  "'audio track'",
  "'audio sink'",
  "'audiotrack'",
  "'source error'",
  "'unable to connect'",
  "'unexpected end of stream'",
  "'response code: 40'",
  "'response code: 41'",
  "'unrecognized input format'",
  "'none of the available extractors'",
  "'failed host lookup'",
  "'name resolution'",
  "'certificate'",
];

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('audio backend shared rules', () {
    test('both real backends and the fake delegate to the shared units', () {
      for (final path in const [_justAudio, _mediaKit, _fake]) {
        final source = _read(path);
        expect(source, contains('classifyCompletion('), reason: path);
        expect(source, contains('liveEdgeCandidates('), reason: path);
        expect(source, contains('seekTookEffect('), reason: path);
      }

      // 引擎專屬的那一半各自只有一個後端會用到。
      expect(_read(_justAudio), contains('classifyExoPlayerFailure('));
      expect(_read(_mediaKit), contains('classifyMpvMessage('));

      // 假替身沒有播放清單，所以只轉呼叫三份規則裡的兩份。
      for (final path in const [_justAudio, _mediaKit]) {
        final source = _read(path);
        expect(source, contains('NextMediaPlan.of('), reason: path);
        expect(
          source,
          contains('NextMediaPlan.shouldTrimPlayedEntry('),
          reason: path,
        );
      }
    });

    test('no second keyword table lives under lib/services/audio', () {
      final files = Directory('lib/services/audio')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => file.path.replaceAll(r'\', '/') != _rules);
      expect(files, isNotEmpty);

      final offenders = <String>[];
      for (final file in files) {
        final code = stripDartComments(file.readAsStringSync());
        for (final keyword in _movedKeywords) {
          if (code.contains(keyword)) {
            offenders.add('${file.path.replaceAll(r'\', '/')}: $keyword');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'These keywords belong to $_rules alone. A second copy diverges '
            'silently: neither backend can be instantiated in flutter test, so '
            'only a device finds the drift.',
      );
    });
  });
}
