import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/media_controls.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';

import '../support/fake_audio_backend.dart';
import '../support/fake_http.dart';
import '../support/fjs.dart';

/// 系統媒體控制接上播放（brief〈播放〉）：經 [mediaControlsBindingProvider]
/// 測，媒體控制換成 [_FakeMediaControls]，插件跑在真的引擎裡，音訊後端是
/// [FakeAudioBackend]。零聯網。
void main() {
  late Directory logDir;
  late Log log;
  late PluginHost host;
  late FakeAudioBackend backend;
  late _FakeMediaControls controls;
  late ProviderContainer container;

  Track track(String id) => Track(
    ref: TrackRef(pluginId: 'songs', trackId: id),
    title: 'Title $id',
    author: 'Author $id',
    duration: const Duration(minutes: 3),
    coverUrl: 'https://img.example.com/$id.webp',
  );

  setUpAll(loadFjsForTests);
  setUp(() async {
    logDir = Directory.systemTemp.createTempSync('fmp_media_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
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
    backend = FakeAudioBackend();
    controls = _FakeMediaControls();
    container = ProviderContainer(
      overrides: [
        logProvider.overrideWithValue(log),
        pluginHostProvider.overrideWith((_) => host),
        audioBackendProvider.overrideWithValue(backend),
        queueRandomProvider.overrideWithValue(Random(1)),
        mediaControlsProvider.overrideWithValue(controls),
      ],
      retry: (_, _) => null,
    );
    container.read(mediaControlsBindingProvider);
  });
  tearDown(() async {
    container.dispose();
    await controls.close();
    await host.close();
    await log.close();
    logDir.deleteSync(recursive: true);
  });

  QueueController queue() => container.read(queueProvider.notifier);
  Playback playback() => container.read(playbackProvider.notifier);
  NowPlaying? shown() => controls.shown.last;

  /// 等插件解析、後端開始播（真的引擎要真的時間）。
  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      final status = container.read(playbackProvider)?.status;
      if (status != PlaybackStatus.resolving &&
          status != PlaybackStatus.loading) {
        await Future<void>.delayed(Duration.zero);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void playedTo(Duration position) =>
      backend.emit(backend.state.copyWith(position: position));

  test('a playing track shows its title, author, cover and length', () async {
    await queue().add([track('a')]);
    await settle();

    final now = shown()!;
    expect(now.track.title, 'Title a');
    expect(now.track.author, 'Author a');
    expect(now.track.coverUrl, 'https://img.example.com/a.webp');
    expect(now.duration, const Duration(minutes: 3));
    expect(now.status, PlaybackStatus.playing);
    expect(now.playing, isTrue);
  });

  test('pausing shows paused at the position it stopped', () async {
    await queue().add([track('a')]);
    await settle();
    playedTo(const Duration(seconds: 42));

    await playback().pause();

    expect(shown()!.status, PlaybackStatus.paused);
    expect(shown()!.playing, isFalse);
    expect(shown()!.position, const Duration(seconds: 42));
  });

  test('moving to the next track shows that track from the start', () async {
    await queue().add([track('a'), track('b')]);
    await settle();
    playedTo(const Duration(seconds: 30));

    await queue().next();
    await settle();

    expect(shown()!.track.title, 'Title b');
    expect(shown()!.position, Duration.zero);
    expect(shown()!.status, PlaybackStatus.playing);
  });

  test('seeking shows the new position', () async {
    await queue().add([track('a')]);
    await settle();

    await playback().seek(const Duration(minutes: 2));

    expect(shown()!.position, const Duration(minutes: 2));
  });

  test('playing on is not sent every tick, but at least every 5 seconds '
      'for systems that do not move the position themselves', () async {
    await queue().add([track('a')]);
    await settle();
    final sent = controls.shown.length;

    for (var ms = 200; ms < 5000; ms += 200) {
      playedTo(Duration(milliseconds: ms));
    }
    expect(controls.shown.length, sent);

    playedTo(const Duration(milliseconds: 5000));
    expect(controls.shown.length, sent + 1);
    expect(shown()!.position, const Duration(milliseconds: 5000));
  });

  test('stopping clears Now Playing', () async {
    await queue().add([track('a')]);
    await settle();

    await queue().clear();

    expect(controls.shown.last, isNull);
  });

  test('previous and next follow what the queue can do', () async {
    await queue().add([track('a'), track('b')]);
    await settle();
    expect(shown()!.canPrevious, isFalse);
    expect(shown()!.canNext, isTrue);

    await queue().next();
    await settle();
    expect(shown()!.canPrevious, isTrue);
    expect(shown()!.canNext, isFalse);
  });

  group('commands from the system', () {
    PlaybackStatus? status() => container.read(playbackProvider)?.status;
    String? playing() => container.read(playbackProvider)?.track.ref.trackId;

    Future<void> send(MediaCommand command) async {
      controls.send(command);
      await Future<void>.delayed(Duration.zero);
      await settle();
    }

    test('pause and play pause and resume the track', () async {
      await queue().add([track('a')]);
      await settle();

      await send(const PauseCommand());
      expect(status(), PlaybackStatus.paused);
      await send(const PauseCommand());
      expect(status(), PlaybackStatus.paused);

      await send(const PlayCommand());
      expect(status(), PlaybackStatus.playing);
      await send(const PlayCommand());
      expect(status(), PlaybackStatus.playing);
      expect(backend.calls.where((c) => c == 'load'), hasLength(1));
    });

    test('play on a finished track plays it again', () async {
      await queue().add([track('a')]);
      await settle();
      backend.emit(
        backend.state.copyWith(
          status: AudioBackendStatus.completed,
          playing: false,
        ),
      );
      await settle();
      expect(status(), PlaybackStatus.completed);

      await send(const PlayCommand());
      expect(status(), PlaybackStatus.playing);
      expect(backend.calls.where((c) => c == 'load'), hasLength(2));
    });

    test('next and previous move through the queue', () async {
      await queue().add([track('a'), track('b')]);
      await settle();

      await send(const NextCommand());
      expect(playing(), 'b');
      await send(const PreviousCommand());
      expect(playing(), 'a');
    });

    test('next during a temporary play goes back to the queue', () async {
      await queue().add([track('a')]);
      await settle();
      await queue().playTemporarily(track('t'));
      await settle();

      await send(const NextCommand());
      expect(playing(), 'a');
      expect(container.read(temporaryPlayProvider), isNull);
    });

    test('seek moves the playing track', () async {
      await queue().add([track('a')]);
      await settle();

      await send(const SeekCommand(Duration(seconds: 75)));
      expect(backend.calls, contains('seek 75000'));
      expect(
        container.read(playbackProvider)!.position,
        const Duration(seconds: 75),
      );
    });

    test('commands before anything has played do nothing', () async {
      await send(const PlayCommand());
      await send(const NextCommand());
      expect(container.read(playbackProvider), isNull);
      expect(backend.calls, isEmpty);
    });
  });
}

class _FakeMediaControls implements MediaControls {
  final _commands = StreamController<MediaCommand>.broadcast();

  /// 依序收到的 [show]。
  final shown = <NowPlaying?>[];

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  @override
  void show(NowPlaying? nowPlaying) => shown.add(nowPlaying);

  /// 系統送來 [command]。
  void send(MediaCommand command) => _commands.add(command);

  Future<void> close() => _commands.close();
}
