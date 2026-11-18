import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/storage.dart';
import 'package:fmp/app/storage_notice.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/playback/queue_saver.dart';
import 'package:fmp/plugins/plugins.dart';

import '../support/fake_audio_backend.dart';
import '../support/fake_http.dart';
import '../support/fjs.dart';

/// 佇列與進度跨重啟保存（brief〈播放〉）：在一個 [ProviderContainer] 裡排佇列、
/// 播放，關掉它與資料庫，再用同一個資料庫檔照 `main` 的做法讀回、開第二個
/// container，像重開 App。插件跑在真的引擎裡，音訊後端換成
/// [FakeAudioBackend]。零聯網。
void main() {
  late Directory dir;
  late Log log;
  late PluginHost host;
  late FakeAudioBackend backend;
  late AppDatabase database;
  late StorageNotice? notice;
  late ProviderContainer container;
  final startedAt = DateTime.utc(2026, 11, 18, 9, 30, 15);

  Track track(String id) => Track(
    ref: TrackRef(pluginId: 'songs', trackId: id),
    title: 'Title $id',
    author: 'Author $id',
    duration: const Duration(minutes: 3),
    coverUrl: 'https://img.example.com/$id.webp',
  );

  File databaseFile() => File('${dir.path}/fmp.sqlite');

  /// 照 `main`：開資料庫、讀回上次的佇列（[openStorage]），再開 container。
  Future<void> launch() async {
    final storage = await openStorage(
      databaseFile(),
      log,
      now: () => startedAt,
    );
    database = storage.database!;
    notice = storage.notice;
    final saved = storage.saved;
    backend = FakeAudioBackend();
    container = ProviderContainer(
      overrides: [
        logProvider.overrideWithValue(log),
        pluginHostProvider.overrideWith((_) => host),
        audioBackendProvider.overrideWithValue(backend),
        queueRandomProvider.overrideWithValue(Random(1)),
        appDatabaseProvider.overrideWithValue(database),
        savedQueueProvider.overrideWithValue(saved),
      ],
      retry: (_, _) => null,
    );
    // App 一開就有畫面讀佇列（迷你播放器的上一首、下一首），控制器跟著建起來。
    container.read(queueProvider);
  }

  /// 等寫入做完，關掉 App 與資料庫，再開一次。
  Future<void> restart() async {
    await container.read(queueSaverProvider)!.idle;
    container.dispose();
    await database.close();
    await launch();
  }

  setUpAll(loadFjsForTests);
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fmp_persist_');
    log = await Log.open(
      Directory('${dir.path}/logs'),
      minimumLevel: LogLevel.debug,
    );
    host = PluginHost(
      bundles: [
        PluginBundle(
          manifest: jsonEncode({
            'id': 'songs',
            'name': 'Songs',
            'version': '1.0.0',
            'capabilities': ['search', 'resolveStream'],
            'domains': ['api.example.com'],
          }),
          code: '''
            export async function search() { return { tracks: [] }; }
            export async function resolveStream({ trackId }) {
              return { url: 'https://cdn.example.com/' + trackId + '.m4a' };
            }
          ''',
        ),
      ],
      log: log,
      httpAdapter: FakeHttp((_) => const FakeResponse(404)),
    );
    await launch();
  });
  tearDown(() async {
    await container.read(queueSaverProvider)!.idle;
    container.dispose();
    await database.close();
    await host.close();
    await log.close();
    dir.deleteSync(recursive: true);
  });

  QueueController queue() => container.read(queueProvider.notifier);
  Queue current() => container.read(queueProvider);
  PlaybackState? playback() => container.read(playbackProvider);
  List<String> ids(Queue queue) => [
    for (final e in queue.entries) e.track.ref.trackId,
  ];
  List<String> loaded() => [
    for (final stream in backend.loaded) stream.url.pathSegments.last,
  ];

  /// 等插件解析、後端開始播（真的引擎要真的時間）。
  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      final status = playback()?.status;
      if (status != PlaybackStatus.resolving &&
          status != PlaybackStatus.loading) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// 後端回報播到 [position]。
  void playedTo(Duration position) =>
      backend.emit(backend.state.copyWith(position: position));

  test('the queue and its current track come back after a restart, paused '
      'where it was, without playing', () async {
    await queue().add([track('a'), track('b'), track('c')]);
    await queue().next();
    await settle();
    playedTo(const Duration(minutes: 1, seconds: 23));

    await restart();

    expect(ids(current()), ['a', 'b', 'c']);
    expect(current().current?.track, track('b'));
    expect(playback()?.track, track('b'));
    expect(playback()?.status, PlaybackStatus.paused);
    expect(playback()?.position, const Duration(minutes: 1, seconds: 23));
    expect(backend.calls, isEmpty);
  });

  test(
    'play after a restart resolves the track and starts where it was',
    () async {
      await queue().add([track('a'), track('b')]);
      await settle();
      playedTo(const Duration(seconds: 42));

      await restart();
      await container.read(playbackProvider.notifier).playPause();
      await settle();

      expect(loaded(), ['a.m4a']);
      expect(backend.calls, ['load', 'seek 42000', 'play']);
      expect(playback()?.status, PlaybackStatus.playing);
    },
  );

  test(
    'seeking a restored track before playing moves where it will start',
    () async {
      await queue().add([track('a')]);
      await settle();
      playedTo(const Duration(seconds: 42));

      await restart();
      await container
          .read(playbackProvider.notifier)
          .seek(const Duration(minutes: 2));

      expect(playback()?.position, const Duration(minutes: 2));
      expect(backend.calls, isEmpty);
      await container.read(playbackProvider.notifier).playPause();
      await settle();
      expect(backend.calls, ['load', 'seek 120000', 'play']);
    },
  );

  test('seeking saves the new position right away', () async {
    await queue().add([track('a')]);
    await settle();
    playedTo(const Duration(seconds: 10));
    await container
        .read(playbackProvider.notifier)
        .seek(const Duration(seconds: 13));

    await restart();

    expect(playback()?.position, const Duration(seconds: 13));
  });

  test('the left position stays saved while going back to the queue track '
      'until it plays again', () async {
    await queue().add([track('a')]);
    await settle();
    playedTo(const Duration(minutes: 2));
    await queue().playTemporarily(track('t'));
    await settle();
    // 回去那首卡在解析：重啟時還是離開的位置，不是 0。
    final hold = backend.holdLoad = Completer<void>();
    unawaited(queue().returnToQueue());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    hold.complete();
    await restart();

    expect(playback()?.position, const Duration(minutes: 2));
  });

  test('starting a restored track from its position never saves the start '
      'of the track on the way', () async {
    await queue().add([track('a')]);
    await settle();
    playedTo(const Duration(seconds: 42));
    await restart();
    // 載入完、還沒跳到 0:42 就失敗了。
    backend.failNextSeek = const AudioBackendError(NetworkError(), 'drop');
    await container.read(playbackProvider.notifier).playPause();
    await settle();

    await restart();

    expect(playback()?.position, const Duration(seconds: 42));
  });

  test(
    'after a save fails, the next save writes the whole queue again',
    () async {
      await queue().add([track('a'), track('b')]);
      await settle();
      await container.read(queueSaverProvider)!.idle;
      // 下一次寫佇列的位置失敗（整筆交易回滾）。
      await database.customStatement(
        'CREATE TEMP TRIGGER fail_once BEFORE INSERT ON queue_entries '
        "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
      );
      await queue().add([track('c')]);
      await container.read(queueSaverProvider)!.idle;
      await database.customStatement('DROP TRIGGER fail_once');

      // 只換目前那首；位置的順序和失敗那次一樣。
      await queue().playAt(2);
      await settle();
      await restart();

      expect(notice, isNull);
      expect(ids(current()), ['a', 'b', 'c']);
      expect(current().current?.track, track('c'));
    },
  );

  test('when the first play after a restart fails, playing again still '
      'starts from the saved position, which stays saved', () async {
    await queue().add([track('a')]);
    await settle();
    playedTo(const Duration(seconds: 42));
    await restart();

    // 沒有網路：載入失敗，重新解析一次也一樣。
    backend.failEveryLoad = const AudioBackendError(NetworkError(), 'offline');
    await container.read(playbackProvider.notifier).playPause();
    await settle();
    expect(playback()?.status, PlaybackStatus.failed);

    // 再按一次（播放鈕；Toast 的重試也是 play 同一首）：從 0:42 開始。
    backend.failEveryLoad = null;
    await container.read(playbackProvider.notifier).playPause();
    await settle();
    expect(backend.calls, ['load', 'load', 'load', 'seek 42000', 'play']);

    // 開始播之後才換成真的位置；一首別的歌播起來之前，失敗不會把它蓋成 0。
    backend.failEveryLoad = const AudioBackendError(NetworkError(), 'offline');
    await container.read(playbackProvider.notifier).play(track('a'));
    await settle();
    await restart();
    expect(playback()?.position, const Duration(seconds: 42));
  });

  test('shuffle, repeat and both orders come back after a restart', () async {
    await queue().add([for (final id in 'abcdef'.split('')) track(id)]);
    await settle();
    queue().toggleShuffle();
    queue().cycleRepeat();
    // 隨機時「下一首播放」與拖動過的，關掉隨機後不回原位。
    await queue().playNext([track('x')]);
    queue().move(5, 2);
    final before = current();

    await restart();

    final after = current();
    expect(ids(after), ids(before));
    expect(after.current?.id, before.current?.id);
    expect(after.shuffled, isTrue);
    expect(after.repeat, Repeat.all);
    // 原順序也留著：關掉隨機後和沒重啟的一樣。
    expect(ids(after.unshuffle()), ids(before.unshuffle()));
    // 之後加入的位置不和還原的撞號。
    queue().toggleShuffle();
    await queue().add([track('y')]);
    final entryIds = [for (final e in current().entries) e.id];
    expect(entryIds.toSet(), hasLength(entryIds.length));
  });

  test('a temporary track is not kept; the queue track comes back at the '
      'position it was left at', () async {
    await queue().add([track('a'), track('b')]);
    await settle();
    playedTo(const Duration(minutes: 2));
    await queue().playTemporarily(track('t'));
    await settle();
    playedTo(const Duration(seconds: 30));

    await restart();

    expect(container.read(temporaryPlayProvider), isNull);
    expect(playback()?.track, track('a'));
    expect(playback()?.status, PlaybackStatus.paused);
    expect(playback()?.position, const Duration(minutes: 2));
  });

  test(
    'while playing, the position is saved once it moved 5 seconds',
    () async {
      await queue().add([track('a')]);
      await settle();
      // 後端照著播放一秒一秒回報。
      for (var second = 1; second <= 9; second++) {
        playedTo(Duration(seconds: second));
      }

      await restart();

      expect(playback()?.position, const Duration(seconds: 5));
    },
  );

  test('pausing saves the position right away', () async {
    await queue().add([track('a')]);
    await settle();
    playedTo(const Duration(seconds: 3));
    await container.read(playbackProvider.notifier).pause();

    await restart();

    expect(playback()?.position, const Duration(seconds: 3));
  });

  test('a cleared queue comes back empty, with nothing to play', () async {
    await queue().add([track('a'), track('b')]);
    await settle();
    await queue().clear();

    await restart();

    expect(current().isEmpty, isTrue);
    expect(playback(), isNull);
  });

  test('a queue that has played to its end comes back at the start of its '
      'last track', () async {
    await queue().add([track('a')]);
    await settle();
    playedTo(const Duration(minutes: 3));
    backend.emit(
      backend.state.copyWith(
        status: AudioBackendStatus.completed,
        playing: false,
      ),
    );

    await restart();

    expect(playback()?.track, track('a'));
    expect(playback()?.position, Duration.zero);
  });

  test('saved data that cannot be read back is kept in a copy, the queue '
      'starts empty with a notice, and later saves leave the copy '
      'alone', () async {
    await queue().add([track('a'), track('b')]);
    await settle();
    await container.read(queueSaverProvider)!.idle;
    // 目前那首指向一個不存在的位置。
    await database.customStatement('DELETE FROM queue_entries');
    await database.customStatement(
      "INSERT INTO queue_entries VALUES (7, 0, NULL, 'songs', 'kept', "
      "'Kept', 'K', NULL, NULL)",
    );

    await restart();

    expect(notice, StorageNotice.queueUnreadable);
    expect(current().isEmpty, isTrue);
    expect(playback(), isNull);
    final backup = File('${databaseFile().path}.unreadable-20261118T093015Z');
    expect(backup.existsSync(), isTrue);
    final bytes = backup.readAsBytesSync();
    // 另存的那份有讀不回來時的資料。
    final copy = AppDatabase.open(backup);
    expect((await copy.select(copy.queueEntries).get()).single.trackId, 'kept');
    expect(await copy.select(copy.queueStates).get(), hasLength(1));
    await copy.close();

    // 之後照常保存，只寫原本的檔；下次開就讀回新的佇列、沒有提示。
    await queue().add([track('c')]);
    await settle();
    await restart();

    expect(notice, isNull);
    expect(ids(current()), ['c']);
    expect(backup.readAsBytesSync(), bytes);
  });
}
