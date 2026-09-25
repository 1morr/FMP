/// 共用規則只准有一份，而且用得到它的後端都得真的轉呼叫它。
///
/// `backend_contract_test.dart` 驗的是規則本身；規則之所以能代表三個後端，
/// 前提是後端沒有各自留一份。複製一份關鍵字表回後端不會編譯錯誤，也不會讓任何
/// 行為測試變紅 —— `JustAudioService` 在 `flutter test` 裡建不起來，
/// `MediaKitAudioService` 也只接得上假引擎，第二份表要到實機上才分岔得出來
/// （issue #41 就是這樣長出來的）。
///
/// 串流網址寫進 log 的形狀（`redactStreamUrl`，#163）也釘在這裡：
/// `MediaKitAudioService` 有假引擎的行為測試讀 log，`JustAudioService` 建不起來，
/// 它有沒有轉呼叫只有這裡看得到。
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

/// 共用規則。
const _sharedUnits = <String>[
  _rules,
  'lib/services/audio/live_edge_seek_policy.dart',
  'lib/services/audio/next_media_plan.dart',
  'lib/services/audio/playback_media.dart',
];

/// 每個後端轉呼叫哪些共用入口。
///
/// 引擎專屬的那一半各自只有一個後端會用到；假替身沒有播放清單，所以不碰
/// `NextMediaPlan`，也不寫 log，所以不碰 `redactStreamUrl`。
const _delegation = <String, Set<String>>{
  _justAudio: {
    'classifyCompletion',
    'liveEdgeCandidates',
    'seekTookEffect',
    'classifyExoPlayerFailure',
    'NextMediaPlan.of',
    'NextMediaPlan.shouldTrimPlayedEntry',
    'redactStreamUrl',
  },
  _mediaKit: {
    'classifyCompletion',
    'liveEdgeCandidates',
    'seekTookEffect',
    'classifyMpvMessage',
    'NextMediaPlan.of',
    'NextMediaPlan.shouldTrimPlayedEntry',
    'redactStreamUrl',
  },
  _fake: {'classifyCompletion', 'liveEdgeCandidates', 'seekTookEffect'},
};

/// 共用檔對外的入口：頂層公開函式，以及公開類別的 factory 與 static 方法
/// （寫成 `類別.方法`）。
Set<String> sharedEntryPoints(Map<String, String> sourcesByPath) {
  final entries = <String>{};
  for (final source in sourcesByPath.values) {
    final code = stripDartComments(source);
    entries.addAll(
      RegExp(
        r'^[A-Za-z][\w<>?, ]*\s+([a-z]\w*)\s*\(',
        multiLine: true,
      ).allMatches(code).map((m) => m.group(1)!),
    );
    for (final type in RegExp(
      r'^class\s+([A-Z]\w*)',
      multiLine: true,
    ).allMatches(code)) {
      final name = type.group(1)!;
      for (final member in RegExp(
        r'(?:factory\s+' + name + r'\.|static\s+[\w<>?, ]+\s+)([a-z]\w*)\s*\(',
      ).allMatches(code)) {
        entries.add('$name.${member.group(1)}');
      }
    }
  }
  return entries;
}

/// [source] 在註解之外呼叫了 [entries] 裡的哪些入口。
Set<String> entryPointsCalled(String source, Set<String> entries) {
  final code = stripDartComments(source);
  return {
    for (final entry in entries)
      if (RegExp(
        r'(?<![\w.])' +
            entry.split('.').map(RegExp.escape).join(r'\s*\.\s*') +
            r'\s*\(',
      ).hasMatch(code))
        entry,
  };
}

/// [source] 去掉註解後，含有哪些搬走了的關鍵字字串常量。單雙引號都算。
List<String> duplicatedKeywords(String source) {
  final code = stripDartComments(source);
  return [
    for (final keyword in _movedKeywords)
      if (RegExp(
        '([\'"])${RegExp.escape(keyword.substring(1, keyword.length - 1))}\\1',
      ).hasMatch(code))
        keyword,
  ];
}

void main() {
  group('audio backend shared rules', () {
    test('both real backends and the fake delegate to the shared units', () {
      final entries = sharedEntryPoints({
        for (final path in _sharedUnits) path: _read(path),
      });
      // 解析本身要有作用 —— 共用檔改名時入口會是空的，每個後端也就「都對」。
      expect(entries, containsAll(_delegation.values.expand((e) => e).toSet()));

      expect(
        {
          for (final path in _delegation.keys)
            path: entryPointsCalled(_read(path), entries),
        },
        equals(_delegation),
        reason:
            'A backend stopped delegating to a shared unit (it probably grew '
            'its own copy), or started calling a new one. Update _delegation '
            'in this file.',
      );
    });

    test('no second keyword table lives under lib/services/audio', () {
      final files = Directory('lib/services/audio')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => file.path.replaceAll(r'\', '/') != _rules);
      expect(files, isNotEmpty);

      final offenders = [
        for (final file in files)
          for (final keyword in duplicatedKeywords(file.readAsStringSync()))
            '${file.path.replaceAll(r'\', '/')}: $keyword',
      ];

      expect(
        offenders,
        isEmpty,
        reason:
            'These keywords belong to $_rules alone. A second copy diverges '
            'silently: JustAudioService cannot be instantiated in flutter '
            'test and MediaKitAudioService only runs on a fake engine, so only '
            'a device finds the drift.',
      );
    });

    test('a copied keyword turns the check red, in either quote style', () {
      const copied = '''
bool isTimeout(String m) => m.contains('timed out');
bool isDns(String m) => m.contains("failed host lookup");
''';

      expect(duplicatedKeywords(copied), [
        "'timed out'",
        "'failed host lookup'",
      ]);
    });

    test('entry points are parsed and a dropped call is caught', () {
      const unit = '''
PlaybackEndReason classifyCompletion({required Duration position}) => x;
const Duration liveEdgeMargin = Duration(seconds: 1);
class NextMediaPlan {
  factory NextMediaPlan.of({required int itemCount}) => x;
  static bool shouldTrimPlayedEntry(int itemCount) => itemCount > 1;
  bool get isEmpty => false;
}
''';
      final entries = sharedEntryPoints({'lib/unit.dart': unit});
      expect(entries, {
        'classifyCompletion',
        'NextMediaPlan.of',
        'NextMediaPlan.shouldTrimPlayedEntry',
      });

      // 後端自己抄了一份判斷，不再呼叫共用入口。
      const copied = '''
PlaybackEndReason _classify(Duration position) =>
    position > Duration.zero ? completed : failed;
final plan = NextMediaPlan.of(itemCount: 2);
''';
      expect(entryPointsCalled(copied, entries), {'NextMediaPlan.of'});
    });

    test('line breaks, comments and lookalike names keep the call set', () {
      const backend = '''
// 以前自己算，現在交給 classifyCompletion(...)。
final reason = classifyCompletion(
  position: position,
);
final plan = NextMediaPlan
    .of(itemCount: count);
final trim = _myNextMediaPlan.shouldTrimPlayedEntry(1);
final other = reclassifyCompletion();
''';

      expect(
        entryPointsCalled(backend, {
          'classifyCompletion',
          'NextMediaPlan.of',
          'NextMediaPlan.shouldTrimPlayedEntry',
        }),
        {'classifyCompletion', 'NextMediaPlan.of'},
      );
    });

    test('comments, identifiers and longer messages do not', () {
      const unrelated = '''
// 以前這裡有 'timed out' 的比對，已搬到 playback_end_reason_rules.dart。
final timedOut = reason is PlaybackTimedOut;
const hint = 'the request timed out twice';
''';

      expect(duplicatedKeywords(unrelated), isEmpty);
    });
  });
}
