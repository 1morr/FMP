import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/account.dart';
import 'package:fmp/data/models/play_history.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/models/track.dart';
import 'package:isar_community/isar.dart';

import '../../support/isar_test_harness.dart';

/// 音源 id 從封閉 enum 改成字串之前，Isar 生成的 reader 在**五個 collection**
/// 裡各有一句 `?? SourceType.bilibili`，會把認不得的字串靜默改寫成 B 站 ——
/// 別人的備份帶著第四個音源進來就會壞掉，而且是不可逆的。
///
/// 這幾條測試釘住「原值保留」，並且證明字串索引對任意值都還能用。
void main() {
  const unknown = 'soundcloud';

  late Isar isar;
  late Directory tempDir;

  setUpAll(initializeIsarForTests);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('unknown_source_id_');
    isar = await Isar.open(
      [
        TrackSchema,
        PlayHistorySchema,
        RadioStationSchema,
        PlaylistSchema,
        AccountSchema,
      ],
      directory: tempDir.path,
      name: 'unknown_source_id',
    );
  });

  tearDown(() async {
    if (isar.isOpen) await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 關閉再開啟，確保讀到的是真的從磁碟反序列化出來的值，
  /// 而不是還留在記憶體裡的同一個物件。
  Future<void> reopen() async {
    await isar.close();
    isar = await Isar.open(
      [
        TrackSchema,
        PlayHistorySchema,
        RadioStationSchema,
        PlaylistSchema,
        AccountSchema,
      ],
      directory: tempDir.path,
      name: 'unknown_source_id',
    );
  }

  test(
    'Track keeps an unknown source id and stays queryable by index',
    () async {
      await isar.writeTxn(
        () => isar.tracks.put(
          Track()
            ..sourceId = 'x1'
            ..sourceType = unknown
            ..title = 'Unknown source track',
        ),
      );

      await reopen();

      expect((await isar.tracks.where().findAll()).single.sourceType, unknown);
      expect(await isar.tracks.where().sourceTypeEqualTo(unknown).count(), 1);
    },
  );

  test('PlayHistory keeps an unknown source id', () async {
    await isar.writeTxn(
      () => isar.playHistorys.put(
        PlayHistory()
          ..sourceId = 'x2'
          ..sourceType = unknown
          ..title = 'Unknown source play',
      ),
    );

    await reopen();

    final stored = (await isar.playHistorys.where().findAll()).single;
    expect(stored.sourceType, unknown);
    // trackKey 是被索引的 getter，也要跟著原值走。
    expect(stored.trackKey, startsWith('$unknown:'));
    expect(
      await isar.playHistorys.where().sourceTypeEqualTo(unknown).count(),
      1,
    );
  });

  test('RadioStation keeps an unknown source id', () async {
    await isar.writeTxn(
      () => isar.radioStations.put(
        RadioStation()
          ..url = 'https://example.invalid/live/1'
          ..title = 'Unknown source station'
          ..sourceId = 'x3'
          ..sourceType = unknown,
      ),
    );

    await reopen();

    expect(
      (await isar.radioStations.where().findAll()).single.sourceType,
      unknown,
    );
  });

  test('Playlist keeps an unknown import source id', () async {
    await isar.writeTxn(
      () => isar.playlists.put(
        Playlist()
          ..name = 'Imported from somewhere else'
          ..importSourceType = unknown,
      ),
    );

    await reopen();

    expect(
      (await isar.playlists.where().findAll()).single.importSourceType,
      unknown,
    );
  });

  test('Account keeps an unknown platform id', () async {
    await isar.writeTxn(() => isar.accounts.put(Account()..platform = unknown));

    await reopen();

    expect((await isar.accounts.where().findAll()).single.platform, unknown);
  });
}
