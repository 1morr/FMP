import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
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

    test(
      'create and edit write the custom cover; an empty one clears it',
      () async {
        final cover = [TrackArtwork(url: Uri.parse('https://fmp.test/c.jpg'))];
        await service().create(name: 'A', artwork: cover);
        final playlist = (await repository.watchAll().first).single;
        expect(playlist.artwork, cover);

        await service().edit(
          playlist,
          name: ' B ',
          description: 'd',
          artwork: playlist.artwork,
        );
        final edited = (await repository.watchAll().first).single;
        expect(edited.name, 'B');
        expect(edited.description, 'd');
        expect(edited.artwork, cover);

        await service().edit(edited, name: 'B', artwork: const []);
        expect((await repository.watchAll().first).single.artwork, isEmpty);
      },
    );

    test('reorder and delete go to the repository', () async {
      final a = await repository.create(name: 'A');
      final b = await repository.create(name: 'B');

      await service().reorder([b, a]);
      expect([for (final p in await repository.watchAll().first) p.id], [b, a]);
      await service().delete(b);
      expect([for (final p in await repository.watchAll().first) p.id], [a]);
    });
  });

  group('editing an imported playlist', () {
    final remoteCover = [
      TrackArtwork(url: Uri.parse('https://fmp.test/remote.jpg')),
    ];

    Future<(Playlist, PlaylistRemote)> imported() async {
      final id = (await repository.createImported(
        pluginId: 'fmp-test',
        remoteId: 'r',
        info: RemotePlaylistInfo(
          name: 'Remote',
          description: 'Remote text',
          artwork: remoteCover,
        ),
      ))!;
      return ((await repository.find(id))!, (await repository.remote(id))!);
    }

    Future<List<bool>> flags(int id) async {
      final remote = (await repository.remote(id))!;
      return [
        remote.nameOverridden,
        remote.descriptionOverridden,
        remote.artworkOverridden,
      ];
    }

    test('an unchanged save overrides nothing', () async {
      final (playlist, remote) = await imported();

      await service().editImported(
        playlist,
        remote,
        name: ' Remote ',
        description: 'Remote text',
        artwork: remoteCover,
      );

      expect(await flags(playlist.id), [false, false, false]);
    });

    test('remote text with surrounding spaces is not an edit', () async {
      final id = (await repository.createImported(
        pluginId: 'fmp-test',
        remoteId: 'r',
        info: const RemotePlaylistInfo(
          name: ' Remote ',
          description: 'Remote text\n',
        ),
      ))!;
      final playlist = (await repository.find(id))!;

      // 對話框的欄位是遠端的原文，送出時去掉空白。
      await service().editImported(
        playlist,
        (await repository.remote(id))!,
        name: ' Remote ',
        description: 'Remote text\n',
        artwork: const [],
      );

      expect(await flags(id), [false, false, false]);
      final stored = (await repository.find(id))!;
      expect(stored.name, ' Remote ');
      expect(stored.description, 'Remote text\n');
    });

    test('only the changed fields are overridden', () async {
      final (playlist, remote) = await imported();

      await service().editImported(
        playlist,
        remote,
        name: 'Mine',
        description: 'Remote text',
        artwork: const [],
      );

      expect(await flags(playlist.id), [true, false, true]);
      final stored = (await repository.find(playlist.id))!;
      expect(stored.name, 'Mine');
      expect(stored.artwork, isEmpty);
    });

    test(
      'a flag that was set stays set when the field is left alone',
      () async {
        final (playlist, remote) = await imported();
        await service().editImported(
          playlist,
          remote,
          name: 'Mine',
          description: 'Remote text',
          artwork: remoteCover,
        );
        final edited = (await repository.find(playlist.id))!;
        final editedRemote = (await repository.remote(playlist.id))!;

        await service().editImported(
          edited,
          editedRemote,
          name: 'Mine',
          description: 'New text',
          artwork: remoteCover,
        );

        expect(await flags(playlist.id), [true, true, false]);
      },
    );

    test('useRemote clears the flag even when the field changed', () async {
      final (playlist, remote) = await imported();
      await service().editImported(
        playlist,
        remote,
        name: 'Mine',
        description: 'Mine',
        artwork: remoteCover,
      );
      final edited = (await repository.find(playlist.id))!;
      final editedRemote = (await repository.remote(playlist.id))!;

      await service().editImported(
        edited,
        editedRemote,
        name: 'Mine',
        description: 'Mine',
        artwork: remoteCover,
        useRemote: {ImportedField.name},
      );

      expect(await flags(playlist.id), [false, true, false]);
      // 值先留著，下一次刷新才寫回遠端的。
      expect((await repository.find(playlist.id))!.name, 'Mine');
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

  group('the songs of a playlist', () {
    Future<int> imported() async => (await repository.createImported(
      pluginId: 'fmp-test',
      remoteId: 'r1',
      info: const RemotePlaylistInfo(name: 'Remote'),
    ))!;

    List<String> ids(List<PlaylistEntry> entries) => [
      for (final entry in entries) entry.track.sourceId,
    ];

    test(
      'addTracks appends to every playlist, the same song again too',
      () async {
        final a = await playlistOf(['x']);
        final b = await playlistOf([]);

        await service().addTracks([a, b], [_track('y'), _track('x')]);
        await service().addTracks([a], [_track('y')]);

        expect(ids(await repository.entries(a)), ['x', 'y', 'x', 'y']);
        expect(ids(await repository.entries(b)), ['y', 'x']);
      },
    );

    test('removeEntries and moveEntries change a local playlist', () async {
      final id = await playlistOf(['a', 'b', 'c']);
      final entries = await repository.entries(id);

      await service().moveEntries(id, [
        entries[2].id,
        entries[0].id,
        entries[1].id,
      ]);
      expect(ids(await repository.entries(id)), ['c', 'a', 'b']);
      await service().removeEntries(id, [entries[0].id]);
      expect(ids(await repository.entries(id)), ['c', 'b']);
    });

    // ADR 0019 §決定 4：匯入歌單的曲目不能在本地增刪或重排。
    test('an imported playlist is refused and left alone', () async {
      final local = await playlistOf([]);
      final remote = await imported();
      await repository.addTracks(remote, [_track('r'), _track('s')]);
      final entries = await repository.entries(remote);

      await expectLater(
        service().addTracks([local, remote], [_track('x')]),
        throwsStateError,
      );
      await expectLater(
        service().removeEntries(remote, [entries.first.id]),
        throwsStateError,
      );
      await expectLater(
        service().moveEntries(remote, [entries[1].id, entries[0].id]),
        throwsStateError,
      );

      expect(ids(await repository.entries(remote)), ['r', 's']);
      expect(
        await repository.entries(local),
        isEmpty,
        reason: 'nothing is added when one of the playlists is refused',
      );
      expect((await repository.find(remote))!.kind, PlaylistKind.imported);
    });

    // 檢查的是 [playlistId] 的種類：別張（匯入）歌單的項目 id 掛在本機歌單名下也刪不到。
    test('entries of another playlist are not removed or moved', () async {
      final local = await playlistOf(['a']);
      final remote = await imported();
      await repository.addTracks(remote, [_track('r'), _track('s')]);
      final foreign = await repository.entries(remote);

      await service().removeEntries(local, [foreign.first.id]);
      await service().moveEntries(local, [foreign[1].id, foreign[0].id]);

      expect(ids(await repository.entries(remote)), ['r', 's']);
      expect(ids(await repository.entries(local)), ['a']);
    });

    test('a deleted playlist is refused', () async {
      final id = await playlistOf([]);
      await repository.delete(id);

      await expectLater(
        service().addTracks([id], [_track('x')]),
        throwsStateError,
      );
    });
  });
}
