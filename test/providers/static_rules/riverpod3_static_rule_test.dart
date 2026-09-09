import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/dart_source.dart';

/// Riverpod 3 帶進來三個「測不到就會靜默壞掉」的規則，這裡用原始碼比對釘住它們。
/// 三條規則都寫在 `lib/providers/AGENTS.md` § Riverpod 3。
void main() {
  group('Riverpod 3 static rules', () {
    test('side-effect providers stay anchored above MaterialApp', () {
      // Riverpod 3 會暫停「被不透明路由蓋住」的 consumer 的 ref.watch 訂閱。
      // FMPApp.build 位於 MaterialApp 之上，沒有 TickerMode 祖先，所以掛在
      // 那裡的 provider 永遠不會被暫停。把某個 provider 搬去頁面上 watch，
      // 使用者一打開全螢幕播放頁它就停了 —— 這條測試就是防這件事。
      final source = stripDartComments(File('lib/app.dart').readAsStringSync());

      const anchoredProviders = <String>[
        'databaseProvider',
        'themeProvider',
        'localeProvider',
        'playbackSettingsProvider',
        'autoRefreshServiceProvider',
        'accountStatusCheckProvider',
        'startupDownloadSyncProvider',
        'windowsDesktopServiceProvider',
        'minimizeToTrayProvider',
        'globalHotkeysEnabledProvider',
        'launchAtStartupProvider',
        'hotkeyConfigProvider',
      ];

      for (final provider in anchoredProviders) {
        expect(
          source,
          contains('ref.watch($provider'),
          reason:
              '$provider must stay anchored in FMPApp.build (lib/app.dart); '
              'a page-level watch would be paused behind the full-screen player',
        );
      }
    });

    test('lib does not import the riverpod legacy barrel', () {
      // 整個可變狀態層已經改寫成 `Notifier`。legacy 家族仍然
      // 可用，所以漏改一個不會有任何編譯錯誤 —— 只會留下一個沒人記得的
      // `StateNotifier`，然後下一個人以為那是現行寫法。
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (importsLegacyRiverpod(entity.readAsStringSync())) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'lib/ is fully on Notifier; legacy providers must not '
            'come back without a decision recorded in AGENTS.md',
      );
    });

    test('every Equatable state lists all of its fields in props', () {
      // Riverpod 3 用 == 過濾更新。props 漏掉一個欄位，那個欄位的變更就
      // 再也不會觸發重建，而且不會有任何錯誤訊息。
      final offenders = <String>[];

      for (final entity in Directory(
        'lib/providers',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        offenders.addAll(equatablePropsOmissions(entity.readAsStringSync()));
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Equatable state fields left out of props stop propagating '
            'updates once Riverpod filters with ==',
      );
    });
  });

  group('the riverpod 3 detectors', () {
    test('a synthesised violation is caught', () {
      const legacy = '''
import 'package:flutter_riverpod/legacy.dart';

final counterProvider = StateNotifierProvider<Counter, int>((ref) => Counter());
''';
      const missingProp = '''
class SearchState extends Equatable {
  const SearchState({required this.query, required this.page});

  final String query;
  final int page;

  @override
  List<Object?> get props => [query];
}
''';

      expect(importsLegacyRiverpod(legacy), isTrue);
      expect(equatablePropsOmissions(missingProp), [
        'SearchState.page is missing from props',
      ]);
    });

    test('a violation written in a comment does not count', () {
      const legacy = '''
// 不要 import 'package:flutter_riverpod/legacy.dart'; —— 整層已經是 Notifier。
import 'package:flutter_riverpod/flutter_riverpod.dart';
''';
      const commentedField = '''
class SearchState extends Equatable {
  const SearchState({required this.query});

  final String query;
  // final int page; 之前漏在 props 外面，已經拿掉。

  @override
  List<Object?> get props => [query];
}
''';

      expect(importsLegacyRiverpod(legacy), isFalse);
      expect(equatablePropsOmissions(commentedField), isEmpty);
    });
  });
}

/// 這個檔案把 legacy 家族（`StateNotifier` 等）import 回來了。
bool importsLegacyRiverpod(String source) =>
    stripDartComments(source).contains('package:flutter_riverpod/legacy.dart');

/// `Equatable` 子類別裡沒有列進 `props` 的公開欄位。
List<String> equatablePropsOmissions(String source) {
  final code = stripDartComments(source);
  final offenders = <String>[];

  for (final match in RegExp(
    r'class\s+(\w+)\s+extends\s+Equatable\s*\{([\s\S]*?)\n\}',
  ).allMatches(code)) {
    final className = match.group(1)!;
    final body = match.group(2)!;

    final propsMatch = RegExp(
      r'get props =>\s*\[([\s\S]*?)\]',
    ).firstMatch(body);
    if (propsMatch == null) {
      offenders.add('$className has no props getter');
      continue;
    }
    final props = propsMatch
        .group(1)!
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    final fields =
        RegExp(r'^\s{2}final\s+[\w<>,?\s]+?\s+(\w+);', multiLine: true)
            .allMatches(body)
            .map((m) => m.group(1)!)
            .where((name) => !name.startsWith('_'));

    for (final field in fields) {
      if (!props.contains(field)) {
        offenders.add('$className.$field is missing from props');
      }
    }
  }

  return offenders;
}
