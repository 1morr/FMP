import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/playback/playback_controller.dart';
import 'package:fmp/playback/playback_session.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/playback/queue_store.dart';
import 'package:fmp/playback/stream_resolver.dart';

import '../support/memory_database.dart';
import 'fake_audio_backend.dart';
import 'fake_source_plugin.dart';

TrackInfo track(String id) =>
    TrackInfo(sourceTypeId: 'fmp-test', sourceId: id, title: 'Song $id');

/// 一個控制器加它的 [QueueStore]，接在同一個資料庫上，全部在 [async] 的假時間裡。
/// [open] 可以對同一個資料庫再建一個（模擬重新啟動）。
final class StoreHarness {
  StoreHarness(
    this.async,
    this.database, {
    this.settings = (rememberPosition: true, rewind: Duration.zero),
  }) : repository = QueueRepository(database);

  final FakeAsync async;
  final AppDatabase database;
  final QueueRepository repository;
  RestartSettings settings;

  final log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
  final lifecycle = StreamController<AppLifecycleState>.broadcast();

  /// 設了它，插件的解析就停著，直到完成：留在 `Loading`。
  Completer<void>? resolveGate;
  late FakeAudioBackend backend;
  late FakeSourcePlugin plugin;
  late PlaybackController controller;
  late QueueStore store;

  /// 新的控制器與 store 接上資料庫，等恢復完成。[beforeAttach] 在 store 讀完
  /// 資料庫之前對控制器做事（恢復完成前使用者就動了佇列）。
  void open({void Function(PlaybackController controller)? beforeAttach}) {
    plugin = FakeSourcePlugin((request) async {
      await resolveGate?.future;
      return [candidate('${request.sourceId}.m4a')];
    });
    backend = FakeAudioBackend(durationOf: (_) => const Duration(minutes: 5));
    controller = PlaybackController(
      session: PlaybackSession(
        backend: backend,
        resolver: StreamResolver(
          plugin: (id) => id == plugin.manifest.id ? plugin : null,
          formats: const [PlayableFormat('mp4', 'aac')],
          preferences: () => (
            quality: AudioQuality.high,
            formatPriority: AudioFormatPriority.opusFirst,
          ),
          log: log,
        ),
        log: log,
      ),
      log: log,
      temporaryReturnSettings: () =>
          (rememberPosition: true, rewind: const Duration(seconds: 10)),
      skipPreviewClips: () => true,
      networkStatus: () => NetworkStatus.online,
      networkStatusChanges: const Stream.empty(),
      preferredOutputDevice: () async => null,
      saveOutputDevice: (_) async {},
    );
    store = QueueStore(repository: repository, log: log);
    beforeAttach?.call(controller);
    unawaited(
      store.attach(
        controller,
        lifecycle: lifecycle.stream,
        restartSettings: () async => settings,
      ),
    );
    settle();
  }

  /// 已排定的非同步工作（含資料庫）跑完，不前進時間。
  void settle() {
    for (var i = 0; i < 20; i++) {
      async.flushMicrotasks();
    }
  }

  /// 前進 [duration]，再讓寫入跑完。
  void elapse(Duration duration) {
    async.elapse(duration);
    settle();
  }

  /// 等排隊中的寫入寫完。
  void flush() {
    unawaited(store.flush());
    settle();
  }

  T read<T>(Future<T> Function() read) {
    late T result;
    var done = false;
    unawaited(
      read().then((value) {
        result = value;
        done = true;
      }),
    );
    settle();
    expect(done, isTrue, reason: 'the read finished');
    return result;
  }

  StoredQueue get storedQueue => read(repository.readQueue);
  PlayerState? get storedPlayer => read(repository.readPlayerState);

  List<LogRecord> logged(String message) => [
    for (final record in log.history)
      if (record.message == message) record,
  ];

  Future<void> close() async {
    store.dispose();
    await controller.dispose();
    await backend.dispose();
    await lifecycle.close();
  }
}

/// 在 fakeAsync 裡建 [StoreHarness]、跑 [body]，結束時關掉。
void storeTest(
  String name,
  void Function(StoreHarness h) body, {
  RestartSettings? settings,
}) {
  test(name, () {
    fakeAsync((async) {
      final h = StoreHarness(
        async,
        memoryDatabase(),
        settings: settings ?? (rememberPosition: true, rewind: Duration.zero),
      )..open();
      body(h);
      unawaited(h.close());
      async.flushMicrotasks();
    });
  });
}

void main() {
  group('writing', () {
    storeTest('a queue operation is written right away', (h) {
      h.controller.addToQueue([track('a'), track('b')]);
      h.settle();

      expect(h.storedQueue.entries.map((t) => t.sourceId), ['a', 'b']);
      expect(h.storedPlayer?.currentPosition, 0);
      expect(h.storedPlayer?.position, Duration.zero);

      h.controller.cycleLoopMode();
      h.controller.setShuffle(true);
      h.settle();
      expect(h.storedPlayer?.loopMode, LoopMode.all);
      expect(h.storedPlayer?.shuffleEnabled, isTrue);
      expect(h.storedQueue.shuffleRanks, everyElement(isNotNull));

      h.controller.setShuffle(false);
      h.controller.move(0, 1);
      h.settle();
      expect(h.storedQueue.entries.map((t) => t.sourceId), ['b', 'a']);
      expect(h.storedQueue.shuffleRanks, [null, null]);
    });

    storeTest('moving a song to play next is written', (h) {
      h.controller.addToQueue([track('a'), track('b'), track('c')]);
      h.controller.setShuffle(true);
      h.controller.moveToNext(2);
      h.settle();

      expect(h.storedQueue.entries.map((t) => t.sourceId), ['a', 'c', 'b']);
      expect(h.storedPlayer?.currentPosition, 0);
      final ranks = h.storedQueue.shuffleRanks;
      expect(ranks[0], 0);
      expect(ranks[1], 1, reason: 'the moved song plays right after a');
    });

    storeTest('the position is written every 10 seconds only while playing', (
      h,
    ) {
      h.controller.addToQueue([track('a'), track('b')]);
      unawaited(h.controller.jumpTo(0));
      h.elapse(const Duration(milliseconds: 500));
      expect(h.controller.state, isA<Playing>());
      expect(h.storedPlayer?.position, Duration.zero);

      h.elapse(const Duration(seconds: 10));
      expect(
        h.storedPlayer!.position.inMilliseconds,
        closeTo(10000, 600),
        reason: 'the first tick, ten seconds after playing began',
      );

      h.elapse(const Duration(seconds: 10));
      expect(h.storedPlayer!.position.inMilliseconds, closeTo(20000, 600));

      unawaited(h.controller.pause());
      h.elapse(const Duration(milliseconds: 200));
      final paused = h.storedPlayer!.position;
      expect(paused.inMilliseconds, closeTo(20500, 700));

      h.elapse(const Duration(minutes: 2));
      expect(h.storedPlayer!.position, paused, reason: 'no timer while paused');
    });

    storeTest('pausing writes the position', (h) {
      h.controller.addToQueue([track('a')]);
      unawaited(h.controller.jumpTo(0));
      h.elapse(const Duration(seconds: 4));

      unawaited(h.controller.pause());
      h.elapse(const Duration(milliseconds: 100));

      expect(h.storedPlayer!.position.inMilliseconds, closeTo(4000, 400));
    });

    storeTest('seeking writes the target', (h) {
      h.controller.addToQueue([track('a')]);
      unawaited(h.controller.jumpTo(0));
      h.elapse(const Duration(seconds: 1));

      unawaited(h.controller.seek(const Duration(seconds: 42)));
      h.elapse(const Duration(milliseconds: 10));

      expect(h.storedPlayer!.position, const Duration(seconds: 42));
    });

    storeTest(
      'going to the background writes the position, coming back does not',
      (h) {
        h.controller.addToQueue([track('a')]);
        unawaited(h.controller.jumpTo(0));
        h.elapse(const Duration(seconds: 3));
        expect(h.storedPlayer!.position, Duration.zero, reason: 'not yet');

        h.lifecycle.add(AppLifecycleState.inactive);
        h.settle();
        expect(
          h.storedPlayer!.position,
          Duration.zero,
          reason: 'inactive is not hidden',
        );

        h.lifecycle.add(AppLifecycleState.hidden);
        h.settle();
        final hidden = h.storedPlayer!.position;
        expect(hidden.inMilliseconds, closeTo(3000, 400));

        h.elapse(const Duration(seconds: 2));
        h.lifecycle.add(AppLifecycleState.resumed);
        h.settle();
        expect(h.storedPlayer!.position, hidden);

        h.lifecycle.add(AppLifecycleState.paused);
        h.settle();
        expect(h.storedPlayer!.position.inMilliseconds, closeTo(5000, 500));
      },
    );

    storeTest('volume and mute are written when they change', (h) {
      h.controller.addToQueue([track('a')]);
      h.settle();

      unawaited(h.controller.setVolume(0.4));
      h.settle();
      expect(h.storedPlayer?.volume, 0.4);
      expect(h.storedPlayer?.muted, isFalse);

      unawaited(h.controller.toggleMute());
      h.settle();
      expect(h.storedPlayer?.volume, 0.4, reason: 'the volume before muting');
      expect(h.storedPlayer?.muted, isTrue);

      unawaited(h.controller.setVolume(0.7));
      h.settle();
      expect(h.storedPlayer?.volume, 0.7);
      expect(h.storedPlayer?.muted, isFalse, reason: 'dragging unmutes');
    });

    storeTest('a new song starts at 0 and a finished queue goes back to 0', (
      h,
    ) {
      h.controller.addToQueue([track('a'), track('b')]);
      unawaited(h.controller.jumpTo(0));
      h.elapse(const Duration(seconds: 12));
      expect(h.storedPlayer!.position.inMilliseconds, greaterThan(9000));

      unawaited(h.controller.next());
      h.elapse(const Duration(milliseconds: 100));
      expect(h.storedPlayer!.currentPosition, 1);
      expect(h.storedPlayer!.position, Duration.zero);

      h.elapse(const Duration(seconds: 15));
      expect(h.storedPlayer!.position.inMilliseconds, greaterThan(9000));

      h.elapse(const Duration(minutes: 6));
      expect(h.controller.state, isA<Idle>(), reason: 'the queue ended');
      expect(h.storedPlayer!.currentPosition, 1);
      expect(h.storedPlayer!.position, Duration.zero);
    });

    storeTest('dragging songs around the current one keeps its position', (h) {
      h.controller.addToQueue([track('a'), track('b'), track('c'), track('d')]);
      unawaited(h.controller.jumpTo(2));
      h.elapse(const Duration(seconds: 40));
      unawaited(h.controller.pause());
      h.elapse(const Duration(milliseconds: 100));
      final paused = h.storedPlayer!.position;
      expect(paused.inSeconds, 40);

      // d 拖到 c 前面、c 自己被拖：目前這首都還是 c，落在差量的中間段。
      h.controller.move(3, 1);
      h.settle();
      expect(h.storedPlayer!.currentPosition, 3);
      expect(h.storedPlayer!.position, paused);

      h.controller.move(3, 0);
      h.settle();
      expect(h.storedPlayer!.currentPosition, 0);
      expect(h.storedPlayer!.position, paused);
    });

    storeTest('a temporary play leaves the snapshot in the database', (h) {
      h.controller.addToQueue([track('a'), track('b')]);
      unawaited(h.controller.jumpTo(1));
      h.elapse(const Duration(seconds: 30));
      final snapshot = h.controller.position;
      expect(snapshot.inSeconds, 30);

      unawaited(h.controller.playTemporary(track('x')));
      h.elapse(const Duration(seconds: 5));
      expect(h.storedPlayer!.currentPosition, 1);
      expect(h.storedPlayer!.position, snapshot);

      // 臨時播放期間的存檔時機都不覆寫它。
      h.elapse(const Duration(seconds: 25));
      h.lifecycle.add(AppLifecycleState.hidden);
      unawaited(h.controller.seek(const Duration(seconds: 3)));
      unawaited(h.controller.pause());
      h.elapse(const Duration(seconds: 1));
      expect(h.storedPlayer!.currentPosition, 1);
      expect(h.storedPlayer!.position, snapshot);
      expect(h.storedQueue.entries.map((t) => t.sourceId), ['a', 'b']);
    });

    storeTest('a restart after a temporary play returns to the snapshot', (h) {
      h.controller.addToQueue([track('a'), track('b')]);
      unawaited(h.controller.jumpTo(0));
      h.elapse(const Duration(seconds: 30));
      final snapshot = h.controller.position;
      unawaited(h.controller.playTemporary(track('x')));
      h.elapse(const Duration(seconds: 5));
      h.store.dispose();
      unawaited(h.controller.dispose());
      h.settle();

      h.open();

      expect(h.controller.queue.mode, QueueMode.queue);
      expect(h.controller.queue.currentIndex, 0);
      expect(h.controller.queue.entries.map((e) => e.track.sourceId), [
        'a',
        'b',
      ]);
      expect(h.controller.position, snapshot);
    });

    storeTest('a failed write is reported and the next change writes what it '
        'missed', (h) {
      h.controller.addToQueue([track('a')]);
      h.settle();

      // 寫 b 的那一列時失敗：整個 transaction 回滾。
      h.read(
        () => h.database.customStatement(
          'CREATE TEMP TRIGGER refuse_b BEFORE INSERT ON queue_entries '
          "WHEN NEW.track_key = 'fmp-test:b' "
          "BEGIN SELECT RAISE(ABORT, 'refused'); END",
        ),
      );
      h.controller.addToQueue([track('b')]);
      h.settle();
      expect(h.logged('Failed to save the queue'), hasLength(1));
      expect(h.storedQueue.entries.map((t) => t.sourceId), ['a']);

      h.read(() => h.database.customStatement('DROP TRIGGER refuse_b'));
      unawaited(h.controller.setVolume(0.5));
      h.settle();
      expect(h.storedQueue.entries.map((t) => t.sourceId), ['a', 'b']);
      expect(h.storedPlayer?.volume, 0.5);
    });

    storeTest('a burst of edits ends with the last one in the database', (h) {
      for (var i = 0; i < 30; i++) {
        h.controller.addToQueue([track('t$i')]);
      }
      h.controller.move(0, 29);
      h.controller.setShuffle(true);
      h.controller.cycleLoopMode();
      h.flush();

      expect(
        h.storedQueue.entries.map((t) => t.sourceId),
        h.controller.queue.entries.map((e) => e.track.sourceId),
      );
      expect(h.storedPlayer?.loopMode, LoopMode.all);
    });
  });

  group('restoring', () {
    /// 存一份佇列（位置 [position]）後「重新啟動」。
    StoreHarness restart(
      StoreHarness h, {
      Duration position = const Duration(seconds: 83),
    }) {
      h.controller.addToQueue([track('a'), track('b'), track('c')]);
      unawaited(h.controller.jumpTo(1));
      h.elapse(const Duration(milliseconds: 100));
      unawaited(h.controller.seek(position));
      h.controller.cycleLoopMode();
      h.controller.setShuffle(true);
      unawaited(h.controller.setVolume(0.3));
      unawaited(h.controller.toggleMute());
      h.settle();
      h.store.dispose();
      unawaited(h.controller.dispose());
      h.settle();
      h.open();
      return h;
    }

    storeTest('brings back the queue, the shuffle order, the loop mode, the '
        'volume and the mute, idle and without resolving', (h) {
      h.controller.addToQueue([track('a'), track('b'), track('c'), track('d')]);
      unawaited(h.controller.jumpTo(2));
      h.controller.setShuffle(true);
      h.controller.cycleLoopMode();
      unawaited(h.controller.setVolume(0.3));
      unawaited(h.controller.toggleMute());
      h.settle();
      final before = h.controller.queue;
      h.store.dispose();
      unawaited(h.controller.dispose());
      h.settle();

      h.open();

      final queue = h.controller.queue;
      expect(queue.entries.map((e) => e.track.sourceId), ['a', 'b', 'c', 'd']);
      expect(queue.currentIndex, 2);
      expect(queue.loopMode, LoopMode.all);
      expect(queue.shuffleOrder, before.shuffleOrder);
      expect(h.controller.volume, 0.3);
      expect(h.controller.muted, isTrue);
      expect(h.backend.volume, 0, reason: 'muted: the backend is silent');
      expect(h.controller.state, isA<Idle>());
      expect(h.plugin.requests, isEmpty, reason: 'nothing was resolved');
      expect(h.backend.opened, isEmpty);
      expect(h.logged('Playback restored'), hasLength(1));
    });

    for (final (remember, rewind, expected) in [
      (true, 0, 83),
      (true, 10, 73),
      (false, 0, 0),
      (false, 10, 0),
    ]) {
      test('playing after a restart: remember $remember, rewind $rewind s '
          'starts at $expected s', () {
        fakeAsync((async) {
          final h = StoreHarness(
            async,
            memoryDatabase(),
            settings: (
              rememberPosition: remember,
              rewind: Duration(seconds: rewind),
            ),
          )..open();
          restart(h);
          expect(h.plugin.requests, isEmpty);

          unawaited(h.controller.play());
          h.elapse(const Duration(milliseconds: 100));

          expect(h.plugin.resolvedCount('b'), 1);
          expect(h.backend.openedAt.single.inSeconds, expected);
          expect(h.controller.queue.current?.sourceId, 'b');
          unawaited(h.close());
          async.flushMicrotasks();
        });
      });
    }

    storeTest('a rewind longer than the position starts from the beginning', (
      h,
    ) {
      h.settings = (
        rememberPosition: true,
        rewind: const Duration(seconds: 30),
      );
      restart(h, position: const Duration(seconds: 5));

      unawaited(h.controller.play());
      h.elapse(const Duration(milliseconds: 100));

      expect(h.backend.openedAt.single, Duration.zero);
    });

    storeTest('only the first play after a restart starts from the position', (
      h,
    ) {
      restart(h);
      unawaited(h.controller.play());
      h.elapse(const Duration(milliseconds: 100));
      expect(h.controller.startedFromRestore, isTrue);
      expect(
        h.logged('Track requested').last.fields,
        containsPair('restored', true),
      );

      unawaited(h.controller.next());
      h.elapse(const Duration(milliseconds: 100));

      expect(h.controller.startedFromRestore, isFalse);
      expect(h.backend.openedAt.last, Duration.zero);
    });

    storeTest('nothing is saved over the stored position while idle after a '
        'restart', (h) {
      h.settings = (
        rememberPosition: true,
        rewind: const Duration(seconds: 10),
      );
      restart(h, position: const Duration(seconds: 83));
      expect(h.controller.position, const Duration(seconds: 73));

      h.lifecycle.add(AppLifecycleState.hidden);
      h.controller.cycleLoopMode();
      h.settle();

      expect(h.controller.state, isA<Idle>());
      expect(h.storedPlayer!.position, const Duration(seconds: 83));
    });

    storeTest(
      'restarting twice without playing keeps the rewind from adding up',
      (h) {
        h.settings = (
          rememberPosition: true,
          rewind: const Duration(seconds: 10),
        );
        restart(h, position: const Duration(seconds: 83));
        h.store.dispose();
        unawaited(h.controller.dispose());
        h.settle();
        h.open();

        unawaited(h.controller.play());
        h.elapse(const Duration(milliseconds: 100));

        expect(h.backend.openedAt.single.inSeconds, 73);
      },
    );

    storeTest('a drag across the current song after a restart keeps the '
        'stored position', (h) {
      restart(h, position: const Duration(seconds: 83));
      expect(h.controller.queue.currentIndex, 1);

      h.controller.move(2, 0);
      h.settle();
      h.store.dispose();
      unawaited(h.controller.dispose());
      h.settle();
      h.open();

      expect(h.controller.queue.current?.sourceId, 'b');
      unawaited(h.controller.play());
      h.elapse(const Duration(milliseconds: 100));
      expect(h.backend.openedAt.single.inSeconds, 83);
    });

    storeTest('a queue built before the restore finished is kept and starts '
        'at 0', (h) {
      restart(h, position: const Duration(seconds: 83));
      h.store.dispose();
      unawaited(h.controller.dispose());
      h.settle();
      final restores = h.logged('Playback restored').length;

      h.open(beforeAttach: (controller) => controller.addToQueue([track('z')]));

      expect(h.logged('Playback restored'), hasLength(restores));
      expect(h.controller.queue.entries.map((e) => e.track.sourceId), ['z']);
      expect(h.storedQueue.entries.map((t) => t.sourceId), ['z']);
      expect(h.storedPlayer!.currentPosition, 0);
      expect(
        h.storedPlayer!.position,
        Duration.zero,
        reason: 'the stored position belonged to another song',
      );
    });

    /// 倒退 10 秒、存的位置 83 秒，重啟一次之後的狀態（還沒按播放）。
    StoreHarness restartRewinding(StoreHarness h) {
      h.settings = (
        rememberPosition: true,
        rewind: const Duration(seconds: 10),
      );
      restart(h, position: const Duration(seconds: 83));
      expect(h.controller.position, const Duration(seconds: 73));
      return h;
    }

    /// 不播就關掉再開一次。
    void reopen(StoreHarness h) {
      h.store.dispose();
      unawaited(h.controller.dispose());
      h.settle();
      h.open();
    }

    storeTest('a temporary play while idle after a restart does not store the '
        'rewound position', (h) {
      restartRewinding(h);

      unawaited(h.controller.playTemporary(track('x')));
      h.elapse(const Duration(seconds: 2));

      expect(h.controller.state, isA<Playing>());
      expect(h.storedPlayer!.position, const Duration(seconds: 83));
      h.lifecycle.add(AppLifecycleState.hidden);
      h.elapse(const Duration(seconds: 12));
      expect(h.storedPlayer!.position, const Duration(seconds: 83));
    });

    storeTest('closing before the restored song is audible keeps the stored '
        'position', (h) {
      restartRewinding(h);

      h.resolveGate = Completer<void>();
      unawaited(h.controller.play());
      h.settle();
      expect(h.controller.state, isA<Loading>());
      h.lifecycle.add(AppLifecycleState.paused);
      h.settle();
      expect(h.storedPlayer!.position, const Duration(seconds: 83));

      h.resolveGate = null;
      reopen(h);
      unawaited(h.controller.play());
      h.elapse(const Duration(milliseconds: 100));
      expect(h.backend.openedAt.last.inSeconds, 73);
    });

    storeTest('once the restored song plays, its real position is stored', (h) {
      restartRewinding(h);

      unawaited(h.controller.play());
      h.elapse(const Duration(seconds: 3));
      h.lifecycle.add(AppLifecycleState.hidden);
      h.settle();

      expect(h.storedPlayer!.position.inMilliseconds, closeTo(76000, 600));
    });

    storeTest('a seek before playing is a real position and is stored', (h) {
      restartRewinding(h);

      unawaited(h.controller.seek(const Duration(seconds: 30)));
      h.settle();

      expect(h.storedPlayer!.position, const Duration(seconds: 30));
    });

    storeTest('the restored position survives a temporary play: play starts '
        'the queue song from it', (h) {
      restartRewinding(h);
      unawaited(h.controller.playTemporary(track('x')));
      h.elapse(const Duration(seconds: 1));

      unawaited(h.controller.next());
      h.elapse(const Duration(milliseconds: 100));
      expect(h.controller.state, isA<Idle>());
      expect(h.controller.queue.current?.sourceId, 'b');

      unawaited(h.controller.play());
      h.elapse(const Duration(milliseconds: 100));

      expect(h.backend.openedAt.last.inSeconds, 73);
      expect(h.controller.startedFromRestore, isTrue);
      expect(
        h.logged('Track requested').last.fields,
        containsPair('restored', true),
      );
    });

    storeTest('the kept restored position is dropped when the queue song '
        'changes during the temporary play', (h) {
      restartRewinding(h);
      unawaited(h.controller.playTemporary(track('x')));
      h.elapse(const Duration(seconds: 1));

      unawaited(h.controller.removeAt(h.controller.queue.currentIndex!));
      unawaited(h.controller.next());
      h.elapse(const Duration(milliseconds: 100));
      expect(h.controller.state, isA<Idle>());
      unawaited(h.controller.play());
      h.elapse(const Duration(milliseconds: 100));

      expect(h.backend.openedAt.last, Duration.zero);
      expect(h.controller.startedFromRestore, isFalse);
    });

    storeTest('jumping to a song during the temporary play drops the kept '
        'restored position', (h) {
      restartRewinding(h);
      unawaited(h.controller.playTemporary(track('x')));
      h.elapse(const Duration(seconds: 1));

      unawaited(h.controller.jumpTo(0));
      h.elapse(const Duration(milliseconds: 100));
      expect(h.backend.openedAt.last, Duration.zero);
      expect(h.controller.startedFromRestore, isFalse);

      // 再停下來按播放也不會拿到舊的位置。
      unawaited(h.controller.clear());
      h.controller.addToQueue([track('q')]);
      unawaited(h.controller.play());
      h.elapse(const Duration(milliseconds: 100));
      expect(h.backend.openedAt.last, Duration.zero);
    });

    storeTest('restart, temporary play, it ends, restart again: the rewind is '
        'applied once', (h) {
      restartRewinding(h);
      unawaited(h.controller.playTemporary(track('x')));
      h.elapse(const Duration(seconds: 2));
      unawaited(h.controller.next());
      h.elapse(const Duration(milliseconds: 100));
      expect(h.controller.state, isA<Idle>());
      expect(h.storedPlayer!.position, const Duration(seconds: 83));

      reopen(h);

      expect(h.storedPlayer!.position, const Duration(seconds: 83));
      expect(h.controller.position, const Duration(seconds: 73));
      unawaited(h.controller.play());
      h.elapse(const Duration(milliseconds: 100));
      expect(h.backend.openedAt.last.inSeconds, 73);
    });

    storeTest('nothing stored: the controller is left alone', (h) {
      expect(h.controller.queue.entries, isEmpty);
      expect(h.logged('Playback restored'), isEmpty);
      expect(h.storedPlayer, isNull);
    });

    storeTest('a queue stored with an empty player state still restores the '
        'volume', (h) {
      unawaited(h.controller.setVolume(0.25));
      h.settle();
      h.store.dispose();
      unawaited(h.controller.dispose());
      h.settle();

      h.open();

      expect(h.controller.volume, 0.25);
      expect(h.controller.queue.entries, isEmpty);
    });

    storeTest('stored data that cannot be read is dropped and reported', (h) {
      h.controller.addToQueue([track('a')]);
      h.settle();
      h.read(
        () => h.database.customStatement(
          "UPDATE player_state SET loop_mode = 'x'",
        ),
      );
      h.store.dispose();
      unawaited(h.controller.dispose());
      h.settle();

      h.open();

      expect(h.controller.queue.entries, isEmpty);
      expect(
        h.logged('Stored playback could not be read; starting empty'),
        hasLength(1),
      );
      // 清掉之後可以照常寫。
      h.controller.addToQueue([track('z')]);
      h.settle();
      expect(h.storedQueue.entries.map((t) => t.sourceId), ['z']);
      expect(h.logged('Failed to save the queue'), isEmpty);
    });
  });

  group('the whole path against the queue model', () {
    /// 隨機的佇列操作，每一步之後資料庫讀回來都要等於控制器的佇列。
    test('a seeded run of operations reads back as the queue every step', () {
      fakeAsync((async) {
        final h = StoreHarness(async, memoryDatabase())..open();
        final random = Random(1407);
        var next = 0;
        TrackInfo fresh() => track('s${next++ % 25}');

        void expectStored(String step) {
          h.flush();
          final queue = h.controller.queue;
          final stored = h.storedQueue;
          final player = h.storedPlayer!;
          expect(
            stored.entries.map((t) => t.key.toString()),
            queue.entries.map((e) => e.track.key.toString()),
            reason: step,
          );
          expect(player.currentPosition, queue.currentIndex, reason: step);
          expect(player.loopMode, queue.loopMode, reason: step);
          expect(player.shuffleEnabled, queue.shuffleEnabled, reason: step);
          final ranks = stored.shuffleRanks;
          if (queue.shuffleOrder case final order?) {
            final restored = List<int>.generate(ranks.length, (i) => i)
              ..sort((a, b) => ranks[a]!.compareTo(ranks[b]!));
            expect(restored, order, reason: '$step: the shuffle order');
          } else {
            expect(ranks, everyElement(isNull), reason: step);
          }
        }

        for (var step = 0; step < 250; step++) {
          final length = h.controller.queue.entries.length;
          final String op;
          switch (random.nextInt(12)) {
            case 0 || 1:
              op = 'append';
              h.controller.addToQueue([
                for (var i = random.nextInt(3) + 1; i > 0; i--) fresh(),
              ]);
            case 2:
              op = 'playNext';
              h.controller.playNext([
                for (var i = random.nextInt(3) + 1; i > 0; i--) fresh(),
              ]);
            case 3 when length > 1:
              op = 'move';
              h.controller.move(random.nextInt(length), random.nextInt(length));
            case 4 when length > 0:
              op = 'remove';
              unawaited(h.controller.removeAt(random.nextInt(length)));
            case 5 when length > 0:
              op = 'jumpTo';
              unawaited(h.controller.jumpTo(random.nextInt(length)));
            case 6:
              op = 'shuffle';
              h.controller.setShuffle(!h.controller.queue.shuffleEnabled);
            case 7:
              op = 'loop';
              h.controller.cycleLoopMode();
            case 8 when length > 0:
              op = 'next';
              unawaited(h.controller.next());
            case 9 when length > 0:
              op = 'previous';
              unawaited(h.controller.previous());
            case 10 when random.nextInt(8) == 0:
              op = 'clear';
              unawaited(h.controller.clear());
            case 11 when length > 0:
              op = 'moveToNext';
              h.controller.moveToNext(random.nextInt(length));
            default:
              op = 'append';
              h.controller.addToQueue([fresh()]);
          }
          h.elapse(const Duration(milliseconds: 100));
          expectStored('step $step ($op)');
        }

        // 最後「重新啟動」：恢復的佇列等於關掉前的。
        final before = h.controller.queue;
        h.store.dispose();
        unawaited(h.controller.dispose());
        h.settle();
        h.open();
        final after = h.controller.queue;
        expect(
          after.entries.map((e) => e.track.key.toString()),
          before.entries.map((e) => e.track.key.toString()),
        );
        expect(after.currentIndex, before.currentIndex);
        expect(after.loopMode, before.loopMode);
        expect(after.shuffleOrder, before.shuffleOrder);
        unawaited(h.close());
        async.flushMicrotasks();
      });
    });
  });

  group('write planning', () {
    test('the ends that did not change are left out', () {
      expect(QueueStore.commonEnds(['a', 'b', 'c'], ['a', 'x', 'c']), (
        prefix: 1,
        suffix: 1,
      ));
      expect(QueueStore.commonEnds(['a', 'b'], ['a', 'b', 'c']), (
        prefix: 2,
        suffix: 0,
      ));
      expect(QueueStore.commonEnds(['a', 'b', 'c'], ['b', 'c']), (
        prefix: 0,
        suffix: 2,
      ));
      expect(QueueStore.commonEnds(['a'], ['b']), (prefix: 0, suffix: 0));
      expect(QueueStore.commonEnds([], []), (prefix: 0, suffix: 0));
    });

    test('the two ends never overlap', () {
      // [a, a] -> [a]：前綴吃掉那個 a，後綴就沒有東西可吃。
      expect(QueueStore.commonEnds(['a', 'a'], ['a']), (prefix: 1, suffix: 0));
    });

    test('the position after a restart: remember and rewind', () {
      const stored = Duration(seconds: 83);
      Duration at(bool remember, int rewind) => QueueStore.restoredPosition(
        stored,
        rememberPosition: remember,
        rewind: Duration(seconds: rewind),
      );

      expect(at(true, 0), stored);
      expect(at(true, 10), const Duration(seconds: 73));
      expect(at(false, 0), Duration.zero);
      expect(at(false, 10), Duration.zero);
      expect(at(true, 120), Duration.zero);
    });
  });
}
