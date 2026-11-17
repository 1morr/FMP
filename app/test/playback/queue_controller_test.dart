import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';

import '../support/fake_audio_backend.dart';
import '../support/fake_http.dart';
import '../support/fjs.dart';

/// 佇列接上播放（brief〈播放〉）：經 [queueProvider] 與 [playbackProvider]
/// 測，插件跑在真的引擎裡，音訊後端換成 [FakeAudioBackend]。零聯網。
void main() {
  late Directory logDir;
  late Log log;
  late PluginHost host;
  late FakeAudioBackend backend;
  late ProviderContainer container;

  Track track(String id) => Track(
    ref: TrackRef(pluginId: 'songs', trackId: id),
    title: id,
    author: 'A',
  );

  setUpAll(loadFjsForTests);
  setUp(() async {
    logDir = Directory.systemTemp.createTempSync('fmp_queue_');
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
    container = ProviderContainer(
      overrides: [
        logProvider.overrideWithValue(log),
        pluginHostProvider.overrideWith((_) => host),
        audioBackendProvider.overrideWithValue(backend),
      ],
      retry: (_, _) => null,
    );
  });
  tearDown(() async {
    container.dispose();
    await host.close();
    await log.close();
    logDir.deleteSync(recursive: true);
  });

  QueueController queue() => container.read(queueProvider.notifier);
  String? playing() => container.read(playbackProvider)?.track.ref.trackId;
  String? currentInQueue() =>
      container.read(queueProvider).current?.track.ref.trackId;
  List<String> loaded() => [
    for (final stream in backend.loaded) stream.url.pathSegments.last,
  ];

  /// 等插件解析、後端開始播（真的引擎要真的時間）。
  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      final status = container.read(playbackProvider)?.status;
      if (status != PlaybackStatus.resolving &&
          status != PlaybackStatus.loading) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void finishCurrent() => backend.emit(
    backend.state.copyWith(
      status: AudioBackendStatus.completed,
      playing: false,
    ),
  );

  test(
    'adding to an empty queue starts playing the first added track',
    () async {
      await queue().add([track('a'), track('b')]);

      expect(playing(), 'a');
      expect(container.read(playbackProvider)!.status, PlaybackStatus.playing);
      expect(loaded(), ['a.m4a']);
    },
  );

  test('adding while playing only queues the tracks', () async {
    await queue().add([track('a')]);
    await queue().add([track('b')]);
    await queue().playNext([track('c')]);

    expect(playing(), 'a');
    expect(loaded(), ['a.m4a']);
    expect(
      [
        for (final e in container.read(queueProvider).entries)
          e.track.ref.trackId,
      ],
      ['a', 'c', 'b'],
    );
  });

  test('a finished track moves on to the next one', () async {
    await queue().add([track('a'), track('b')]);

    finishCurrent();
    await settle();

    expect(currentInQueue(), 'b');
    expect(playing(), 'b');
    expect(loaded(), ['a.m4a', 'b.m4a']);
  });

  test('the last finished track stops there', () async {
    await queue().add([track('a')]);

    finishCurrent();
    await settle();

    expect(currentInQueue(), 'a');
    expect(container.read(playbackProvider)!.status, PlaybackStatus.completed);
    expect(loaded(), ['a.m4a']);
  });

  test('next and previous play the neighbouring tracks', () async {
    await queue().add([track('a'), track('b')]);

    await queue().next();
    expect(playing(), 'b');
    await queue().previous();
    expect(playing(), 'a');
    expect(loaded(), ['a.m4a', 'b.m4a', 'a.m4a']);
  });

  test('next on the last track does nothing', () async {
    await queue().add([track('a')]);

    await queue().next();
    expect(playing(), 'a');
    expect(loaded(), ['a.m4a']);
  });

  test('playNow inserts after the current track and plays it', () async {
    await queue().add([track('a'), track('b')]);

    await queue().playNow(track('x'));

    expect(playing(), 'x');
    expect(
      [
        for (final e in container.read(queueProvider).entries)
          e.track.ref.trackId,
      ],
      ['a', 'x', 'b'],
    );
  });

  test('playAt plays the chosen entry', () async {
    await queue().add([track('a'), track('b'), track('c')]);

    await queue().playAt(2);
    expect(playing(), 'c');
  });

  test('moving tracks does not interrupt playback', () async {
    await queue().add([track('a'), track('b'), track('c')]);

    queue().move(2, 0);

    expect(playing(), 'a');
    expect(currentInQueue(), 'a');
    expect(loaded(), ['a.m4a']);
  });

  group('remove', () {
    test('removing the current track plays the next one', () async {
      await queue().add([track('a'), track('b')]);

      await queue().remove(0);

      expect(playing(), 'b');
      expect(loaded(), ['a.m4a', 'b.m4a']);
    });

    test('removing another track keeps playing', () async {
      await queue().add([track('a'), track('b')]);

      await queue().remove(1);

      expect(playing(), 'a');
      expect(loaded(), ['a.m4a']);
    });

    test('removing the current last track stops playback', () async {
      await queue().add([track('a'), track('b')]);
      await queue().next();

      await queue().remove(1);

      expect(container.read(playbackProvider), isNull);
      expect(backend.calls.last, 'pause');
      expect(currentInQueue(), isNull);
    });
  });

  test('after the playing last track is removed, adding plays the added '
      'track', () async {
    await queue().add([track('a'), track('b')]);
    await queue().next();
    await queue().remove(1);
    expect(container.read(queueProvider).current, isNull);
    expect(container.read(playbackProvider), isNull);

    await queue().add([track('c')]);

    expect(currentInQueue(), 'c');
    expect(playing(), 'c');
  });

  test('with a current track that is paused, adding neither moves nor starts '
      'it', () async {
    await queue().add([track('a')]);
    await container.read(playbackProvider.notifier).pause();

    await queue().add([track('b')]);
    await queue().playNext([track('c')]);

    expect(currentInQueue(), 'a');
    expect(container.read(playbackProvider)!.status, PlaybackStatus.paused);
    expect(loaded(), ['a.m4a']);
  });

  test(
    'after the last track finished, adding neither moves nor starts it',
    () async {
      await queue().add([track('a')]);
      finishCurrent();
      await settle();

      await queue().add([track('b')]);

      expect(currentInQueue(), 'a');
      expect(
        container.read(playbackProvider)!.status,
        PlaybackStatus.completed,
      );
      expect(loaded(), ['a.m4a']);
    },
  );

  test('clearing the queue stops playback', () async {
    await queue().add([track('a'), track('b')]);

    await queue().clear();

    expect(container.read(queueProvider).isEmpty, isTrue);
    expect(container.read(playbackProvider), isNull);
    expect(backend.calls.last, 'pause');
  });
}
