import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/library/playlist_service.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/playback/playback_controller.dart';
import 'package:fmp/playback/playback_events.dart';
import 'package:fmp/playback/playback_session.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/playback/stream_resolver.dart';

import '../playback/fake_audio_backend.dart';
import '../playback/fake_source_plugin.dart';
import '../support/memory_database.dart';
import '../support/pump_until.dart';

TrackInfo _track(String id) =>
    TrackInfo(sourceTypeId: 'fmp-test', sourceId: id, title: 'Song $id');

void main() {
  late PlaylistRepository repository;
  late PlaybackController controller;
  late List<PlaybackEvent> events;

  PlaylistService service({Random? random}) => PlaylistService(
    repository: repository,
    controller: controller,
    random: random,
  );

  setUp(() {
    repository = PlaylistRepository(memoryDatabase());
    final log = Log(redactor: Redactor(), minimumLevel: LogLevel.warning);
    final plugin = FakeSourcePlugin((_) => [candidate('a.m4a')]);
    final backend = FakeAudioBackend(
      durationOf: (_) => const Duration(minutes: 3),
    );
    controller = PlaybackController(
      session: PlaybackSession(
        backend: backend,
        resolver: StreamResolver(
          plugin: (_) => plugin,
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
      pluginChanges: const Stream.empty(),
      preferredOutputDevice: () async => null,
      saveOutputDevice: (_) async {},
      registerLiveInfoJob: (_, _) {},
      unregisterLiveInfoJob: () {},
    );
    events = [];
    final subscription = controller.events.listen(events.add);
    addTearDown(subscription.cancel);
    addTearDown(controller.dispose);
    addTearDown(backend.dispose);
  });

  Future<int> playlistOf(List<String> ids) async {
    final id = await repository.create(name: 'P');
    await repository.addTracks(id, [for (final id in ids) _track(id)]);
    return id;
  }

  List<String> queued() => [
    for (final entry in controller.queue.entries) entry.track.sourceId,
  ];

  group('editing', () {
    test('create trims the name and drops an empty description', () async {
      await service().create(name: '  Mix  ', description: '   ');
      await service().create(name: 'B', description: ' notes ');

      final all = await repository.watchAll().first;
      expect([for (final p in all) p.name], ['Mix', 'B']);
      expect([for (final p in all) p.description], [null, 'notes']);
    });

    test('edit renames and keeps the cover', () async {
      final id = await repository.create(name: 'A');
      final cover = [TrackArtwork(url: Uri.parse('https://fmp.test/c.jpg'))];
      await repository.update(id, name: 'A', artwork: cover);
      final playlist = (await repository.watchAll().first).single;

      await service().edit(playlist, name: ' B ', description: 'd');

      final edited = (await repository.watchAll().first).single;
      expect(edited.name, 'B');
      expect(edited.description, 'd');
      expect(edited.artwork, cover);
    });

    test('reorder and delete go to the repository', () async {
      final a = await repository.create(name: 'A');
      final b = await repository.create(name: 'B');

      await service().reorder([b, a]);
      expect([for (final p in await repository.watchAll().first) p.id], [b, a]);
      await service().delete(b);
      expect([for (final p in await repository.watchAll().first) p.id], [a]);
    });
  });

  group('adding to the queue', () {
    test('adds every song in the playlist order', () async {
      final id = await playlistOf(['a', 'b', 'a', 'c']);

      expect(await service().addToQueue(id), 4);

      expect(queued(), ['a', 'b', 'a', 'c']);
    });

    test('shuffle adds the same songs in a shuffled order', () async {
      final ids = [for (var i = 0; i < 20; i++) '$i'];
      final id = await playlistOf(ids);

      expect(
        await service(random: Random(7)).addToQueue(id, shuffle: true),
        20,
      );

      expect(queued(), unorderedEquals(ids));
      expect(queued(), isNot(orderedEquals(ids)));
      // 打亂的是加入的順序，佇列本身的隨機播放不動（D2：只加入）。
      expect(controller.queue.shuffleEnabled, isFalse);
    });

    test(
      'past the queue limit nothing is added and QueueFull is sent',
      () async {
        expect(
          controller.addToQueue([
            for (var i = 0; i < QueueModel.maxLength - 1; i++) _track('q$i'),
          ]),
          isTrue,
        );
        final id = await playlistOf(['a', 'b']);

        expect(await service().addToQueue(id), isNull);

        expect(controller.queue.entries, hasLength(QueueModel.maxLength - 1));
        await pumpUntil(() => events.isNotEmpty);
        expect(events.single, isA<QueueFull>());
      },
    );
  });
}
