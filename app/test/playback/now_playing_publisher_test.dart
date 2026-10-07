import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';
import 'package:fmp/playback/now_playing_publisher.dart';
import 'package:fmp/playback/playback_controller.dart';
import 'package:fmp/playback/playback_session.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/stream_resolver.dart';

import 'fake_audio_backend.dart';
import 'fake_media_controls.dart';
import 'fake_source_plugin.dart';

TrackInfo track(String id) => TrackInfo(
  sourceTypeId: 'fmp-test',
  sourceId: id,
  title: 'Song $id',
  uploader: 'Uploader $id',
);

final class PublisherHarness {
  PublisherHarness(
    this.async, {
    Future<Uri?> Function(TrackInfo track)? artwork,
  }) : plugin = FakeSourcePlugin(
         (request) => [candidate('${request.sourceId}.m4a')],
       ),
       backend = FakeAudioBackend(
         durationOf: (_) => const Duration(minutes: 5),
       ) {
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
          (rememberPosition: true, rewind: Duration.zero),
      skipPreviewClips: () => true,
      networkStatus: () => NetworkStatus.online,
      networkStatusChanges: const Stream.empty(),
      preferredOutputDevice: () async => null,
      saveOutputDevice: (_) async {},
    );
    publisher = NowPlayingPublisher(
      controls: controls,
      artworkFile: artwork ?? (_) async => null,
      log: log,
    )..attach(controller);
  }

  final FakeAsync async;
  final FakeSourcePlugin plugin;
  final FakeAudioBackend backend;
  final controls = FakeMediaControls();
  final log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
  late final PlaybackController controller;
  late final NowPlayingPublisher publisher;

  List<NowPlaying> get published => controls.published;
  NowPlaying get last => published.last;

  void settle() => async.flushMicrotasks();
  void elapse(Duration duration) => async.elapse(duration);

  void queue(List<TrackInfo> tracks) {
    controller.addToQueue(tracks);
    settle();
  }

  /// 開始播第 [index] 首並等它出聲。
  void playAt(int index) {
    unawaited(controller.jumpTo(index));
    elapse(const Duration(milliseconds: 100));
  }
}

void main() {
  void harness(
    String description,
    void Function(PublisherHarness h) body, {
    Future<Uri?> Function(TrackInfo track)? artwork,
  }) {
    test(description, () {
      fakeAsync((async) {
        final h = PublisherHarness(async, artwork: artwork);
        body(h);
        h.publisher.dispose();
      });
    });
  }

  group('what is pushed', () {
    harness('an empty queue pushes the idle nothing', (h) {
      h.settle();

      expect(h.published, [NowPlaying.nothing]);
      expect(h.last.phase, MediaPhase.idle);
      expect(h.last.controls, isEmpty);
    });

    harness('a queue that has not been played yet is idle but can play', (h) {
      h.queue([track('a'), track('b')]);

      expect(h.last.phase, MediaPhase.idle);
      expect(h.last.playing, isFalse);
      expect(h.last.title, 'Song a');
      expect(h.last.uploader, 'Uploader a');
      expect(h.last.id, 'fmp-test:a');
      expect(h.last.controls, [
        MediaControl.previous,
        MediaControl.play,
        MediaControl.next,
      ]);
    });

    harness('a restored queue that was not played stays idle', (h) {
      expect(
        h.controller.restore(
          tracks: [track('a'), track('b')],
          currentIndex: 0,
          loopMode: LoopMode.off,
          shuffle: false,
          position: const Duration(seconds: 30),
          volume: 1,
          muted: false,
        ),
        isTrue,
      );
      h.settle();

      expect(h.controller.state, isA<Idle>());
      expect(h.last.phase, MediaPhase.idle);
      expect(h.last.title, 'Song a');
      expect(h.last.controls, contains(MediaControl.play));
    });

    harness('playing shows a pause button and the duration', (h) {
      h.queue([track('a'), track('b')]);
      h.playAt(0);

      expect(h.last.phase, MediaPhase.ready);
      expect(h.last.playing, isTrue);
      expect(h.last.controls, contains(MediaControl.pause));
      expect(h.last.controls, isNot(contains(MediaControl.play)));
      expect(h.last.duration, const Duration(minutes: 5));
    });

    harness('Loading keeps the pause button', (h) {
      final gate = Completer<void>();
      h.plugin.respond = (request) async {
        await gate.future;
        return [candidate('${request.sourceId}.m4a')];
      };
      h.queue([track('a')]);
      unawaited(h.controller.jumpTo(0));
      h.settle();

      expect(h.controller.state, isA<Loading>());
      expect(h.last.phase, MediaPhase.loading);
      expect(h.last.playing, isTrue);
      expect(h.last.controls, contains(MediaControl.pause));
    });

    harness('paused shows the play button at the paused position', (h) {
      h.queue([track('a'), track('b')]);
      h.playAt(0);
      h.elapse(const Duration(seconds: 3));
      unawaited(h.controller.pause());
      h.settle();

      expect(h.last.playing, isFalse);
      expect(h.last.controls, contains(MediaControl.play));
      expect(h.last.position, h.controller.position);
      expect(h.last.position, greaterThan(Duration.zero));
    });

    harness('next only exists when there is a next track or loop all', (h) {
      h.queue([track('a'), track('b')]);
      h.playAt(1);
      expect(h.last.controls, isNot(contains(MediaControl.next)));
      expect(h.last.controls, contains(MediaControl.previous));

      h.controller.cycleLoopMode();
      h.settle();
      expect(h.controller.queue.loopMode, LoopMode.all);
      expect(h.last.controls, contains(MediaControl.next));
    });

    harness('Retrying keeps the pause button', (h) {
      h.plugin.respond = (_) => throw NetworkError();
      h.queue([track('a'), track('b')]);
      unawaited(h.controller.jumpTo(0));
      h.settle();

      expect(h.controller.state, isA<Retrying>());
      expect(h.last.phase, MediaPhase.buffering);
      expect(h.last.playing, isTrue);
      expect(h.last.controls, contains(MediaControl.pause));
    });

    harness('Failed is ready, not playing, with the play button', (h) {
      h.plugin.respond = (_) => throw NotFound();
      h.queue([track('a')]);
      unawaited(h.controller.jumpTo(0));
      h.settle();

      expect(h.controller.state, isA<Failed>());
      expect(h.last.phase, MediaPhase.ready);
      expect(h.last.playing, isFalse);
      expect(h.last.controls, [MediaControl.previous, MediaControl.play]);
    });

    harness('a temporary play can always go next (back to the queue)', (h) {
      unawaited(h.controller.playTemporary(track('t')));
      h.elapse(const Duration(milliseconds: 100));

      expect(h.controller.queue.temporary, isNotNull);
      expect(h.last.title, 'Song t');
      expect(h.last.controls, contains(MediaControl.next));
    });

    harness('a track change pushes the new media item', (h) {
      h.queue([track('a'), track('b')]);
      h.playAt(0);
      unawaited(h.controller.next());
      h.elapse(const Duration(milliseconds: 100));

      expect(h.last.id, 'fmp-test:b');
      expect(h.last.title, 'Song b');
      expect(h.last.controls, isNot(contains(MediaControl.next)));
    });
  });

  group('artwork', () {
    harness('arrives after the other fields and does not block them', (h) {
      h.queue([track('a')]);
      h.settle();

      final first = h.published.firstWhere((p) => p.hasTrack);
      expect(first.title, 'Song a');
      expect(first.artworkFile, isNull);
      expect(h.last.title, 'Song a');
      expect(h.last.artworkFile, Uri.file('/cache/a.jpg'));
    }, artwork: (_) async => Uri.file('/cache/a.jpg'));

    harness('failing to get it leaves the other fields alone', (h) {
      h.queue([track('a')]);
      h.playAt(0);

      expect(h.last.title, 'Song a');
      expect(h.last.artworkFile, isNull);
      expect(h.last.playing, isTrue);
    }, artwork: (_) async => throw StateError('no network'));

    harness(
      'a late result for the previous track is dropped',
      (h) {
        final first = Completer<Uri?>();
        h.queue([track('a'), track('b')]);
        h.playAt(1);
        first.complete(Uri.file('/cache/stale.jpg'));
        h.settle();

        expect(h.last.id, 'fmp-test:b');
        expect(h.last.artworkFile, isNull);
      },
      artwork: (track) => track.sourceId == 'a'
          ? Future.delayed(
              const Duration(seconds: 1),
              () => Uri.file('/cache/stale.jpg'),
            )
          : Future.value(null),
    );
  });

  group('when it pushes', () {
    harness('a new speed is pushed so the system extrapolates correctly', (h) {
      h.queue([track('a'), track('b')]);
      h.playAt(0);
      expect(h.last.speed, 1.0);
      final count = h.published.length;

      unawaited(h.controller.setSpeed(1.5));
      h.settle();
      expect(h.published, hasLength(count + 1));
      expect(h.last.speed, 1.5);

      unawaited(h.controller.setSpeed(3));
      h.settle();
      expect(h.last.speed, 2.0);
    });

    harness('an unchanged value is not pushed again', (h) {
      h.queue([track('a'), track('b')]);
      h.playAt(0);
      final count = h.published.length;

      h.controller.setShuffle(false); // 佇列發出一樣的值
      h.settle();
      h.elapse(const Duration(seconds: 2)); // 進度 stream 持續前進

      expect(h.published, hasLength(count));
    });

    harness('the position is only pushed on a state change or a seek', (h) {
      h.queue([track('a'), track('b')]);
      h.playAt(0);
      final count = h.published.length;

      h.elapse(const Duration(seconds: 20));
      expect(h.published, hasLength(count));

      unawaited(h.controller.seek(const Duration(minutes: 2)));
      h.settle();
      expect(h.published, hasLength(count + 1));
      expect(h.last.position, const Duration(minutes: 2));
      expect(h.last.playing, isTrue);

      unawaited(h.controller.pause());
      h.settle();
      expect(h.published, hasLength(count + 2));
      expect(h.last.playing, isFalse);
    });

    harness('pushes are queued one at a time, in order', (h) {
      final gate = Completer<void>();
      h.controls.gate = gate;
      h.queue([track('a'), track('b')]);
      h.playAt(0);

      // 第一次推送還沒完成，之後的都在排隊。
      expect(h.published, hasLength(1));
      expect(h.controls.maxRunning, 1);

      gate.complete();
      h.settle();

      expect(h.controls.maxRunning, 1);
      expect(h.published.length, greaterThan(1));
      expect(h.published.first, NowPlaying.nothing);
      expect(h.last.playing, isTrue);
    });

    harness('a failing push is logged and the next one still goes out', (h) {
      h.controls.failWith = StateError('platform');
      h.queue([track('a'), track('b')]);
      h.playAt(0);

      expect(h.last.playing, isTrue);
    });
  });

  group('system commands go through the controller', () {
    harness('play starts the queue', (h) {
      h.queue([track('a'), track('b')]);
      h.controls.send(const MediaPlay());
      h.elapse(const Duration(milliseconds: 100));

      expect(h.controller.state, isA<Playing>());
    });

    harness('pause pauses', (h) {
      h.queue([track('a'), track('b')]);
      h.playAt(0);
      h.controls.send(const MediaPause());
      h.settle();

      expect(h.controller.state, isA<Paused>());
    });

    harness('next and previous move through the queue', (h) {
      h.queue([track('a'), track('b'), track('c')]);
      h.playAt(0);

      h.controls.send(const MediaNext());
      h.elapse(const Duration(milliseconds: 100));
      expect(h.controller.queue.current?.sourceId, 'b');

      h.controls.send(const MediaPrevious());
      h.elapse(const Duration(milliseconds: 100));
      expect(h.controller.queue.current?.sourceId, 'a');
    });

    harness('seek seeks', (h) {
      h.queue([track('a')]);
      h.playAt(0);
      h.controls.send(const MediaSeek(Duration(minutes: 1)));
      h.settle();

      expect(h.controller.position, const Duration(minutes: 1));
    });

    harness('stop is a pause: position and queue are kept', (h) {
      h.queue([track('a'), track('b')]);
      h.playAt(0);
      h.elapse(const Duration(seconds: 5));
      final position = h.controller.position;

      h.controls.send(const MediaStop());
      h.settle();

      expect(h.controller.state, isA<Paused>());
      expect(h.controller.queue.entries, hasLength(2));
      expect(h.controller.queue.current?.sourceId, 'a');
      expect(h.controller.position, position);

      h.controls.send(const MediaPlay());
      h.elapse(const Duration(milliseconds: 100));
      expect(h.controller.state, isA<Playing>());
      expect(h.controller.position, greaterThanOrEqualTo(position));
    });
  });
}
