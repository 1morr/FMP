/// 音訊層三條「介面收窄」規則，只有讀源碼驗得到。
///
/// 三條原本各自藏在一支行為測試裡。共同點是：把收窄的介面放寬回去不會有編譯
/// 錯誤，也不會有任何測試變紅 —— 只會讓上一次拆分想擋掉的東西悄悄回來。
///
/// 三條都解析宣告、比集合，不比字串：改名一個不相關的欄位、換行、加註解都
/// 不紅；長回一個重疊的欄位、介面多一個成員、多一個檔案拿寬的型別就紅。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/dart_source.dart';

const _playerState = 'lib/services/audio/player_state.dart';
const _queueState = 'lib/services/audio/queue_state.dart';
const _streamManager = 'lib/services/audio/audio_stream_manager.dart';

/// 引用寬的 `SourceAuthContext` 的檔案。其他模組只拿自己那一份窄介面
/// （`SourcePlaybackAuthContext`、`DownloadSourceAuthContext` 等），
/// 看不到別人的認證入口。
const _wideAuthContextOwners = <String>{
  'lib/services/account/source_auth_context.dart',
  'lib/providers/account/source_auth_context_provider.dart',
};

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('audio seam static rules', () {
    test('PlayerState and QueueState share no field', () {
      // 這兩個型別曾經各存一份同樣的 12 個欄位，靠 controller 每次逐欄位抄過去
      // 維持一致。抄漏一個就是一個看不見的 bug，而消費端會因為問了不同的
      // provider 拿到不同的答案。長回來的話這條會先掛。
      final player = stateFields(_read(_playerState), 'PlayerState');
      final queue = stateFields(_read(_queueState), 'QueueState');

      // 解析本身要有作用 —— 類別名寫錯時交集也會是空的。
      expect(player, contains('position'));
      expect(queue, contains('currentIndex'));
      expect(player.intersection(queue), isEmpty);
    });

    test(
      'PlaybackRequestStreamAccess exposes only session-level operations',
      () {
        expect(
          classMembers(_read(_streamManager), 'PlaybackRequestStreamAccess'),
          {'selectPlayback', 'selectFallbackPlayback', 'prefetchTrack'},
          reason:
              'The playback session reaches the stream manager through this '
              'interface only; resolution internals stay behind it.',
        );
      },
    );

    test('only the auth context and its provider name the wide type', () {
      final sources = {
        for (final entity in Directory('lib').listSync(recursive: true))
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              !entity.path.endsWith('.g.dart'))
            entity.path.replaceAll(r'\', '/'): entity.readAsStringSync(),
      };

      expect(sources.length, greaterThan(300));
      expect(filesNamingWideAuthContext(sources), _wideAuthContextOwners);
    });
  });

  group('the audio seam parsers', () {
    test('an overlapping field, a new member or a new user is caught', () {
      const player = '''
class PlayerState {
  final Duration position;
  final int? currentIndex;
}
''';
      const queue = '''
class QueueState {
  final int? currentIndex;
}
''';
      const widened = '''
abstract class PlaybackRequestStreamAccess {
  Future<PlaybackSelection> selectPlayback(Track track, {bool persist = true});
  Future<void> ensureAudioStream(Track track);
}
''';

      expect(
        stateFields(
          player,
          'PlayerState',
        ).intersection(stateFields(queue, 'QueueState')),
        {'currentIndex'},
      );
      expect(classMembers(widened, 'PlaybackRequestStreamAccess'), {
        'selectPlayback',
        'ensureAudioStream',
      });
      expect(
        filesNamingWideAuthContext({
          'lib/services/download/download_service.dart':
              'final SourceAuthContext _auth;',
        }),
        {'lib/services/download/download_service.dart'},
      );
    });

    test('renames, line breaks, getters and comments are read correctly', () {
      const player = '''
class PlayerState {
  const PlayerState({this.position = Duration.zero});

  // final int? currentIndex; 以前在這裡，已經搬到 QueueState。
  final Duration
      position;
  final Map<String, List<int>> renamedField;

  Track? get currentTrack => playingTrack;
  PlayerState copyWith({Duration? position}) => PlayerState(position: position);
}
''';
      const access = '''
abstract class PlaybackRequestStreamAccess {
  /// 會呼叫 ensureAudioStream(track)，但不在介面上。
  Future<PlaybackSelection> selectPlayback(
    Track track, {
    bool persist = true,
    Duration timeout = const Duration(seconds: 5),
  });
}
''';

      expect(stateFields(player, 'PlayerState'), {
        'position',
        'renamedField',
        'currentTrack',
      });
      expect(classMembers(access, 'PlaybackRequestStreamAccess'), {
        'selectPlayback',
      });
      expect(
        filesNamingWideAuthContext({
          'lib/a.dart':
              '// 見 SourceAuthContext.authForPlay\n'
              'final DefaultSourceAuthContext c;\n'
              'final p = sourceAuthContextProvider;',
        }),
        isEmpty,
      );
    });
  });
}

/// [className] 的欄位與 getter 名稱 —— 狀態型別對外呈現的形狀。
Set<String> stateFields(String source, String className) => {
  for (final (name, kind) in _declarations(source, className))
    if (kind != _Kind.method) name,
};

/// [className] 的所有成員名稱（建構子除外）。
Set<String> classMembers(String source, String className) => {
  for (final (name, _) in _declarations(source, className)) name,
};

final _wideAuthContext = RegExp(r'\bSourceAuthContext\b');

/// 在註解之外引用 `SourceAuthContext` 這個型別的檔案。
Set<String> filesNamingWideAuthContext(Map<String, String> sourcesByPath) => {
  for (final MapEntry(key: path, value: source) in sourcesByPath.entries)
    if (_wideAuthContext.hasMatch(stripDartComments(source))) path,
};

enum _Kind { field, getter, method }

/// 把類別本體切成頂層宣告：括號、方括號與方法本體裡的東西全部略過，
/// 所以預設值、參數與區域變數都不會被當成成員。
List<(String, _Kind)> _declarations(String source, String className) {
  final code = stripDartComments(source);
  final header = RegExp(
    r'\bclass\s+' + RegExp.escape(className) + r'\b[^{]*\{',
  ).firstMatch(code);
  if (header == null) throw StateError('class $className not found');

  final declarations = <(String, _Kind)>[];
  final current = StringBuffer();
  var depth = 0;

  void flush() {
    final text = current.toString().trim();
    current.clear();
    if (text.isEmpty) return;
    final declaration = _classify(text, className);
    if (declaration != null) declarations.add(declaration);
  }

  for (var i = header.end; i < code.length; i++) {
    final ch = code[i];
    if (ch == '{' || ch == '(' || ch == '[') {
      // 只留下開頭的括號當記號，內容不收。
      if (depth == 0) current.write(ch == '{' ? ' { ' : ch);
      depth++;
      continue;
    }
    if (ch == '}' || ch == ')' || ch == ']') {
      if (depth == 0) break; // 類別本體結束。
      depth--;
      if (depth == 0 && ch == '}') flush(); // 方法本體結束。
      continue;
    }
    if (depth > 0) continue;
    if (ch == ';') {
      flush();
      continue;
    }
    current.write(ch);
  }
  return declarations;
}

(String, _Kind)? _classify(String declaration, String className) {
  // `==`、`hashCode`、`toString` 這類覆寫是 Object 的形狀，不是這個類別的。
  if (declaration.contains('@override') ||
      RegExp(r'\boperator\b').hasMatch(declaration)) {
    return null;
  }
  final text = declaration.replaceAll(RegExp(r'@[\w.]+\s*\(?'), '');

  final getter = RegExp(r'\bget\s+(\w+)').firstMatch(text);
  if (getter != null) return (getter.group(1)!, _Kind.getter);

  final paren = text.indexOf('(');
  final assign = text.indexOf('=');
  if (paren != -1 && (assign == -1 || paren < assign)) {
    final name = RegExp(r'([\w.]+)\s*$').firstMatch(text.substring(0, paren));
    if (name == null) return null;
    final value = name.group(1)!;
    // 建構子（含具名建構子與 factory）不是成員。
    if (value == className || value.startsWith('$className.')) return null;
    return (value, _Kind.method);
  }

  final end = assign == -1 ? text.length : assign;
  final name = RegExp(r'(\w+)\s*$').firstMatch(text.substring(0, end));
  return name == null ? null : (name.group(1)!, _Kind.field);
}
