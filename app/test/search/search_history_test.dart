import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/search/search_history.dart';

/// 搜尋紀錄（brief〈搜尋〉）：在 [ProviderContainer] 裡記錄、刪除，關掉再用
/// 同一個資料庫檔開第二個 container，像重開 App。
void main() {
  late Directory dir;
  late Log log;
  late AppDatabase? database;
  late ProviderContainer container;

  File databaseFile() => File('${dir.path}/fmp.sqlite');

  /// 開 container；[withDatabase] 為 false 時像資料庫開不了。
  ProviderContainer launch({bool withDatabase = true}) {
    database = withDatabase ? AppDatabase.open(databaseFile()) : null;
    return container = ProviderContainer(
      overrides: [
        logProvider.overrideWithValue(log),
        appDatabaseProvider.overrideWithValue(database),
      ],
    );
  }

  Future<void> quit() async {
    container.dispose();
    await database?.close();
  }

  SearchHistory history() => container.read(searchHistoryProvider.notifier);
  Future<List<String>> items() => container.read(searchHistoryProvider.future);

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fmp_search_history_test');
    final logDir = Directory('${dir.path}/log')..createSync();
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
  });
  tearDown(() async {
    await quit();
    await log.close();
    dir.deleteSync(recursive: true);
  });

  test('lists the newest search first', () async {
    launch();
    await items();
    await history().record('lemon');
    await history().record('yoasobi');

    expect(await items(), ['yoasobi', 'lemon']);
  });

  test('a search made while the history is still loading is kept', () async {
    launch();
    await history().record('lemon');
    await quit();

    launch();
    // 不等讀完就記。
    await history().record('yoasobi');

    expect(await items(), ['yoasobi', 'lemon']);
  });

  test('searching the same text again moves it to the front once', () async {
    launch();
    await items();
    await history().record('lemon');
    await history().record('yoasobi');
    await history().record('lemon');

    expect(await items(), ['lemon', 'yoasobi']);
  });

  test('trims the text and ignores blank searches', () async {
    launch();
    await items();
    await history().record('  lemon ');
    await history().record('lemon');
    await history().record('   ');
    await history().record('');

    expect(await items(), ['lemon']);
  });

  test('keeps the newest 100 and drops the oldest', () async {
    launch();
    await items();
    for (var i = 0; i < 101; i++) {
      await history().record('q$i');
    }

    final shown = await items();
    expect(shown, hasLength(100));
    expect(shown.first, 'q100');
    expect(shown.last, 'q1');

    await quit();
    launch();
    final restored = await items();
    expect(restored, shown);
  });

  test('removes one entry', () async {
    launch();
    await items();
    await history().record('lemon');
    await history().record('yoasobi');
    await history().remove('lemon');

    expect(await items(), ['yoasobi']);
    await quit();
    launch();
    expect(await items(), ['yoasobi']);
  });

  test('clears everything', () async {
    launch();
    await items();
    await history().record('lemon');
    await history().record('yoasobi');
    await history().clear();

    expect(await items(), isEmpty);
    await quit();
    launch();
    expect(await items(), isEmpty);
  });

  test('survives a restart in the same order', () async {
    launch();
    await items();
    await history().record('lemon');
    await history().record('yoasobi');
    await history().record('lemon');
    await quit();

    launch();

    expect(await items(), ['lemon', 'yoasobi']);
  });

  test('works in memory only when there is no database', () async {
    launch(withDatabase: false);
    await items();
    await history().record('lemon');
    await history().record('yoasobi');
    await history().remove('lemon');

    expect(await items(), ['yoasobi']);
  });

  test('logs a failed write without the query and keeps the list', () async {
    launch();
    await items();
    await database!.close();

    await history().record('secret-query');
    await log.close();

    expect(await items(), ['secret-query']);
    final text = File('${dir.path}/log/${Log.fileName}').readAsStringSync();
    expect(text, contains('Saving the search history failed'));
    expect(text, isNot(contains('secret-query')));
  });
}
