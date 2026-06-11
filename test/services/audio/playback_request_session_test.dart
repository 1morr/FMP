import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/services/audio/audio_playback_types.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/playback_media.dart';
import 'package:fmp/services/audio/playback_request_session.dart';

import '../../support/fakes/fake_audio_service.dart';

void main() {
  group('PlaybackSessionResult', () {
    test('completed result exposes track and stream metadata', () {
      final track = Track()
        ..sourceId = 'session-track'
        ..sourceType = SourceType.youtube
        ..title = 'Session Track';
      const streamResult = AudioStreamResult(
        url: 'https://example.com/session-track.m4a',
        container: 'm4a',
        codec: 'aac',
        streamType: StreamType.audioOnly,
      );

      final result = PlaybackSessionResult.completed(
        requestId: 7,
        track: track,
        attemptedUrl: 'https://example.com/session-track.m4a',
        streamResult: streamResult,
      );

      expect(result.kind, PlaybackSessionResultKind.completed);
      expect(result.requestId, 7);
      expect(result.track, same(track));
      expect(result.attemptedUrl, 'https://example.com/session-track.m4a');
      expect(result.streamResult, same(streamResult));
      expect(result.isCompleted, isTrue);
      expect(result.isSuperseded, isFalse);
    });

    test('superseded result is typed and carries no stale track', () {
      final result = PlaybackSessionResult.superseded(requestId: 8);

      expect(result.kind, PlaybackSessionResultKind.superseded);
      expect(result.requestId, 8);
      expect(result.track, isNull);
      expect(result.error, isNull);
      expect(result.isCompleted, isFalse);
      expect(result.isSuperseded, isTrue);
    });

    test('terminal media-open error carries track and visible message', () {
      final track = Track()
        ..sourceId = 'terminal-track'
        ..sourceType = SourceType.youtube
        ..title = 'Terminal Track';

      final result = PlaybackSessionResult.terminalMediaOpenError(
        requestId: 9,
        track: track,
        message: 'Cannot play Track A',
      );

      expect(result.kind, PlaybackSessionResultKind.terminalMediaOpenError);
      expect(result.requestId, 9);
      expect(result.track, same(track));
      expect(result.message, 'Cannot play Track A');
      expect(result.isTerminalMediaOpenError, isTrue);
    });

    test('failed result preserves original error and stack trace', () {
      final error = StateError('handoff failed');
      final stackTrace = StackTrace.current;
      final result = PlaybackSessionResult.failed(
        requestId: 10,
        error: error,
        stackTrace: stackTrace,
      );

      expect(result.kind, PlaybackSessionResultKind.failed);
      expect(result.requestId, 10);
      expect(result.error, same(error));
      expect(result.stackTrace, same(stackTrace));
      expect(result.isFailed, isTrue);
    });
  });

  group('PlaybackSessionCommand', () {
    test('normal play command keeps mode and side-effect flags explicit', () {
      final track = Track()
        ..sourceId = 'cmd-track'
        ..sourceType = SourceType.youtube
        ..title = 'Command Track';

      final command = PlaybackSessionCommand(
        track: track,
        mode: PlayMode.temporary,
        persist: false,
        recordHistory: false,
        prefetchNext: false,
        positionBeforeLoad: const Duration(seconds: 12),
        onPlaybackStarting: () async {},
      );

      expect(command.track, same(track));
      expect(command.mode, PlayMode.temporary);
      expect(command.persist, isFalse);
      expect(command.recordHistory, isFalse);
      expect(command.prefetchNext, isFalse);
      expect(command.positionBeforeLoad, const Duration(seconds: 12));
      expect(command.onPlaybackStarting, isNotNull);
    });

    test('restore command keeps seek and resume policy explicit', () {
      final track = Track()
        ..sourceId = 'restore-track'
        ..sourceType = SourceType.youtube
        ..title = 'Restore Track';

      final command = PlaybackRestoreCommand(
        track: track,
        mode: PlayMode.queue,
        position: const Duration(seconds: 42),
        shouldResume: true,
      );

      expect(command.track, same(track));
      expect(command.mode, PlayMode.queue);
      expect(command.position, const Duration(seconds: 42));
      expect(command.shouldResume, isTrue);
    });
  });

  group('FakeAudioService typed media support', () {
    test('playMedia records typed remote media and delegates to URL loader',
        () async {
      final audioService = FakeAudioService();
      final track = _track('typed-remote');
      final media = RemotePlaybackMedia(
        url: Uri.parse('https://example.com/typed-remote.m4a'),
        headers: const {'X-Typed': 'remote'},
        track: track,
      );

      await audioService.playMedia(media);

      expect(audioService.playMediaCalls.single.media, same(media));
      expect(audioService.playUrlCalls.single.url,
          'https://example.com/typed-remote.m4a');
      expect(audioService.playUrlCalls.single.headers, {'X-Typed': 'remote'});
      expect(audioService.playUrlCalls.single.track, same(track));
    });

    test('setMedia records typed local media and delegates to file loader',
        () async {
      final audioService = FakeAudioService();
      final track = _track('typed-local');
      final media = LocalPlaybackMedia(
        path: '/music/typed-local.m4a',
        track: track,
      );

      await audioService.setMedia(media);

      expect(audioService.setMediaCalls.single.media, same(media));
      expect(
          audioService.setFileCalls.single.filePath, '/music/typed-local.m4a');
      expect(audioService.setFileCalls.single.track, same(track));
    });
  });

  group('PlaybackRequestSession handoff', () {
    late FakeAudioService audioService;
    late _HarnessPlaybackRequestStreamAccess streamManager;
    late PlaybackRequestSession session;
    late List<int> loadingStarted;

    setUp(() {
      audioService = FakeAudioService();
      streamManager = _HarnessPlaybackRequestStreamAccess();
      loadingStarted = [];
      session = PlaybackRequestSession(
        audioService: audioService,
        audioStreamManager: streamManager,
        getNextTrack: () => null,
        onLoadingStarted: loadingStarted.add,
        onLoadingFinished: (_, __) {},
        terminalMediaOpenMessage: (track) => 'Cannot play ${track.title}',
        delay: (_) async {},
      );
    });

    tearDown(() {
      session.dispose();
    });

    test('start stops backend and plays selected stream', () async {
      final track = _track('session-start');

      final result = await session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );

      expect(result.isCompleted, isTrue);
      expect(result.track?.sourceId, 'session-start');
      expect(result.attemptedUrl, 'https://example.com/session-start.m4a');
      expect(audioService.stopCallCount, 1);
      expect(audioService.playMediaCalls.single.media,
          isA<RemotePlaybackMedia>());
      expect(audioService.playUrlCalls.single.url,
          'https://example.com/session-start.m4a');
      expect(loadingStarted, [1]);
    });

    test('start plays local selections with playFile', () async {
      final track = _track('local-session');
      streamManager.onSelectPlayback = (track, persist) async {
        expect(persist, isTrue);
        return PlaybackSelection(
          media: LocalPlaybackMedia(
            path: '/music/local-session.m4a',
            track: track,
          ),
          streamResult: null,
        );
      };

      final result = await session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );

      expect(result.isCompleted, isTrue);
      expect(result.attemptedUrl, '/music/local-session.m4a');
      expect(audioService.playFileCalls.single.filePath,
          '/music/local-session.m4a');
      expect(audioService.playUrlCalls, isEmpty);
    });

    test('start passes manager-owned selection headers to backend', () async {
      final track = _track('headers-owned');
      streamManager.onPrepareNetworkPlayback = (track, url) async {
        return RemotePlaybackMedia(
          url: Uri.parse(url),
          headers: const {'X-Test-Header': 'owned-by-manager'},
          track: track,
        );
      };

      final result = await session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );

      expect(result.isCompleted, isTrue);
      expect(audioService.playUrlCalls.single.url,
          'https://example.com/headers-owned.m4a');
      expect(audioService.playUrlCalls.single.headers, {
        'X-Test-Header': 'owned-by-manager',
      });
      expect(streamManager.selectionRequests, ['headers-owned']);
    });

    test('start uses manager fallback and preserves fallback metadata',
        () async {
      final track = _track('fallback-session')
        ..sourceType = SourceType.bilibili;
      audioService.enqueuePlayUrlError(Exception('primary failed'));
      streamManager.onSelectFallbackPlayback = (track, failedUrl) async {
        expect(failedUrl, 'https://example.com/fallback-session.m4a');
        return PlaybackSelection(
          media: RemotePlaybackMedia(
            url: Uri.parse(
              'https://example.com/fallback-session-fallback.m3u8',
            ),
            headers: const {'X-Fallback': 'yes'},
            track: track,
          ),
          streamResult: const AudioStreamResult(
            url: 'https://example.com/fallback-session-fallback.m3u8',
            container: 'm3u8',
            codec: 'aac',
            streamType: StreamType.muxed,
          ),
        );
      };

      final result = await session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );

      expect(result.isCompleted, isTrue);
      expect(result.attemptedUrl,
          'https://example.com/fallback-session-fallback.m3u8');
      expect(result.streamResult?.streamType, StreamType.muxed);
      expect(audioService.playUrlCalls.map((call) => call.url), [
        'https://example.com/fallback-session.m4a',
        'https://example.com/fallback-session-fallback.m3u8',
      ]);
      expect(audioService.playUrlCalls.first.headers, {
        'Referer': 'https://example.com',
      });
      expect(audioService.playUrlCalls.last.headers, {'X-Fallback': 'yes'});
    });

    test('start preserves original handoff error when fallback fails',
        () async {
      final track = _track('fallback-fails');
      final primaryError = Exception('primary failed');
      audioService.enqueuePlayUrlError(primaryError);
      streamManager.onSelectFallbackPlayback = (_, __) async {
        throw Exception('fallback failed');
      };

      final result = await session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );

      expect(result.isFailed, isTrue);
      expect(result.error, same(primaryError));
      expect(streamManager.fallbackSelectionTracks, ['fallback-fails']);
      expect(streamManager.fallbackSelectionFailedUrls,
          ['https://example.com/fallback-fails.m4a']);
    });

    test('start preserves original handoff error when manager has no fallback',
        () async {
      final track = _track('no-fallback');
      final primaryError = Exception('playback handoff failed');
      audioService.enqueuePlayUrlError(primaryError);

      final result = await session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );

      expect(result.isFailed, isTrue);
      expect(result.error, same(primaryError));
      expect(streamManager.selectionRequests, ['no-fallback']);
      expect(streamManager.fallbackSelectionTracks, ['no-fallback']);
      expect(streamManager.fallbackSelectionFailedUrls,
          ['https://example.com/no-fallback.m4a']);
      expect(audioService.playUrlCalls.map((call) => call.url), [
        'https://example.com/no-fallback.m4a',
      ]);
    });

    test('start prefetches a copied next track when requested', () async {
      final currentTrack = _track('prefetch-current');
      final nextTrack = _track('prefetch-next')
        ..audioUrl = 'https://stale.example/prefetch-next.m4a';
      session.dispose();
      session = PlaybackRequestSession(
        audioService: audioService,
        audioStreamManager: streamManager,
        getNextTrack: () => nextTrack,
        onLoadingStarted: loadingStarted.add,
        onLoadingFinished: (_, __) {},
        terminalMediaOpenMessage: (track) => 'Cannot play ${track.title}',
        delay: (_) async {},
      );

      final result = await session.start(
        PlaybackSessionCommand(
          track: currentTrack,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );

      expect(result.isCompleted, isTrue);
      expect(streamManager.prefetchRequests, ['prefetch-next']);
      expect(streamManager.prefetchedTracks.single, isNot(same(nextTrack)));
      expect(streamManager.prefetchedTracks.single.audioUrl,
          'https://stale.example/prefetch-next.m4a');
    });

    test('start skips next-track prefetch when disabled', () async {
      final currentTrack = _track('prefetch-disabled-current');
      final nextTrack = _track('prefetch-disabled-next');
      session.dispose();
      session = PlaybackRequestSession(
        audioService: audioService,
        audioStreamManager: streamManager,
        getNextTrack: () => nextTrack,
        onLoadingStarted: loadingStarted.add,
        onLoadingFinished: (_, __) {},
        terminalMediaOpenMessage: (track) => 'Cannot play ${track.title}',
        delay: (_) async {},
      );

      final result = await session.start(
        PlaybackSessionCommand(
          track: currentTrack,
          mode: PlayMode.queue,
          prefetchNext: false,
          positionBeforeLoad: Duration.zero,
        ),
      );

      expect(result.isCompleted, isTrue);
      expect(streamManager.prefetchRequests, isEmpty);
      expect(streamManager.prefetchedTracks, isEmpty);
    });

    test('start stop failure fails before stream selection or fallback',
        () async {
      final track = _track('stop-fails');
      final stopError = Exception('stop failed before playback');
      audioService.enqueueStopError(stopError);

      final result = await session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );

      expect(result.isFailed, isTrue);
      expect(result.error, same(stopError));
      expect(audioService.stopCallCount, 1);
      expect(streamManager.selectionRequests, isEmpty);
      expect(streamManager.ensureAudioStreamRequests, isEmpty);
      expect(streamManager.fallbackSelectionTracks, isEmpty);
      expect(audioService.playUrlCalls, isEmpty);
      expect(audioService.playFileCalls, isEmpty);
      expect(audioService.setUrlCalls, isEmpty);
      expect(audioService.setFileCalls, isEmpty);
    });

    test('restore prepares URL, seeks, and resumes when requested', () async {
      final track = _track('restore-session');

      final result = await session.restore(
        PlaybackRestoreCommand(
          track: track,
          mode: PlayMode.queue,
          position: const Duration(seconds: 35),
          shouldResume: true,
        ),
      );

      expect(result.isCompleted, isTrue);
      expect(audioService.stopCallCount, 1);
      expect(audioService.setUrlCalls.single.url,
          'https://example.com/restore-session.m4a');
      expect(audioService.seekCalls, [const Duration(seconds: 35)]);
      expect(audioService.isPlaying, isTrue);
    });

    test('restore skips seek and resume when restore state is idle', () async {
      final track = _track('restore-idle');

      final result = await session.restore(
        PlaybackRestoreCommand(
          track: track,
          mode: PlayMode.queue,
          position: Duration.zero,
          shouldResume: false,
        ),
      );

      expect(result.isCompleted, isTrue);
      expect(audioService.setUrlCalls.single.url,
          'https://example.com/restore-idle.m4a');
      expect(audioService.seekCalls, isEmpty);
      expect(audioService.isPlaying, isFalse);
    });

    test('restore uses prepared network URL and headers', () async {
      final track = _track('restore-prepared');
      streamManager.onPrepareNetworkPlayback = (track, url) async {
        expect(track.sourceId, 'restore-prepared');
        expect(url, 'https://example.com/restore-prepared.m4a');
        return RemotePlaybackMedia(
          url: Uri.parse('https://cdn.example.com/restore-prepared.m4a'),
          headers: const {'X-Prepared': 'yes'},
          track: track,
        );
      };

      final result = await session.restore(
        PlaybackRestoreCommand(
          track: track,
          mode: PlayMode.queue,
          position: Duration.zero,
          shouldResume: false,
        ),
      );

      expect(result.isCompleted, isTrue);
      expect(
          result.attemptedUrl, 'https://cdn.example.com/restore-prepared.m4a');
      expect(audioService.setUrlCalls.single.url,
          'https://cdn.example.com/restore-prepared.m4a');
      expect(audioService.setUrlCalls.single.headers, {'X-Prepared': 'yes'});
      expect(streamManager.selectionRequests, contains('restore-prepared'));
    });

    test('start aborts after async media preparation when superseded',
        () async {
      final firstTrack = _track('first-headers');
      final secondTrack = _track('second-headers');
      final secondPlayGate = audioService.enqueuePendingPlayUrl();
      final preparationGate = Completer<void>();
      streamManager.onPrepareNetworkPlayback = (track, url) async {
        if (track.sourceId == firstTrack.sourceId) {
          await preparationGate.future;
        }
        return RemotePlaybackMedia(
          url: Uri.parse(url),
          headers: {'Referer': 'https://example.com/${track.sourceId}'},
          track: track,
        );
      };

      final firstPlay = session.start(
        PlaybackSessionCommand(
          track: firstTrack,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );
      await streamManager.waitForPrepareNetworkPlayback(firstTrack.sourceId);

      final secondPlay = session.start(
        PlaybackSessionCommand(
          track: secondTrack,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );
      await audioService.waitForPlayUrlCallCount(1);

      preparationGate.complete();
      expect((await firstPlay).isSuperseded, isTrue);
      expect(audioService.playUrlCalls.length, 1);
      expect(audioService.playUrlCalls.single.url,
          'https://example.com/second-headers.m4a');

      secondPlayGate.complete();
      final secondResult = await secondPlay;
      expect(secondResult.isCompleted, isTrue);
      expect(secondResult.track?.sourceId, 'second-headers');
      expect(streamManager.selectionRequests, [
        'first-headers',
        'second-headers',
      ]);
      expect(streamManager.prepareNetworkPlaybackRequests, [
        'first-headers',
        'second-headers',
      ]);
    });

    test('superseded start does not stop or error newer request', () async {
      final firstTrack = _track('first-session');
      final secondTrack = _track('second-session');
      final firstGate = audioService.enqueuePendingPlayUrl();
      final secondGate = audioService.enqueuePendingPlayUrl();

      final first = session.start(
        PlaybackSessionCommand(
          track: firstTrack,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );
      await audioService.waitForPlayUrlCallCount(1);

      final second = session.start(
        PlaybackSessionCommand(
          track: secondTrack,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );
      await audioService.waitForPlayUrlCallCount(2);

      firstGate.complete();
      expect((await first).isSuperseded, isTrue);

      expect(audioService.stopCallCount, 2);
      expect(audioService.playUrlCalls.map((call) => call.url), [
        'https://example.com/first-session.m4a',
        'https://example.com/second-session.m4a',
      ]);

      secondGate.complete();
      expect((await second).isCompleted, isTrue);
    });

    test('media-open error recovers when backend advances', () async {
      final track = _track('media-open-recovers');
      final playGate = audioService.enqueuePendingPlayUrl();

      final play = session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );
      await audioService.waitForPlayUrlCallCount(1);

      final mediaOpen = session.onMediaOpenError(
        error: 'Failed to open https://example.com/media-open-recovers.m4a.',
        track: track,
        positionAtError: Duration.zero,
      );
      audioService.setPlayingValue(true);
      audioService.setPositionValue(const Duration(seconds: 2));
      await mediaOpen;

      playGate.complete();
      final result = await play;
      expect(result.isCompleted, isTrue);
      expect(audioService.stopCallCount, 1);
    });

    test('media-open error becomes terminal when backend does not advance',
        () async {
      final track = _track('media-open-terminal');
      final playGate = audioService.enqueuePendingPlayUrl();

      final play = session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );
      await audioService.waitForPlayUrlCallCount(1);

      await session.onMediaOpenError(
        error: 'Failed to open https://example.com/media-open-terminal.m4a.',
        track: track,
        positionAtError: Duration.zero,
      );

      playGate.complete();
      final result = await play;
      expect(result.isTerminalMediaOpenError, isTrue);
      expect(result.track?.sourceId, 'media-open-terminal');
      expect(result.message, 'Cannot play media-open-terminal');
      expect(audioService.stopCallCount, 2);
    });

    test('new request makes active media-open terminal stale while stop waits',
        () async {
      final firstTrack = _track('media-open-stale-first');
      final secondTrack = _track('media-open-stale-second');
      final firstPlayGate = audioService.enqueuePendingPlayUrl();

      final first = session.start(
        PlaybackSessionCommand(
          track: firstTrack,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );
      await audioService.waitForPlayUrlCallCount(1);

      final stopGate = audioService.enqueuePendingStop();
      final mediaOpen = session.onMediaOpenError(
        error: 'Failed to open https://example.com/media-open-stale-first.m4a.',
        track: firstTrack,
        positionAtError: Duration.zero,
      );
      firstPlayGate.complete();
      await pumpEventQueue(times: 5);

      final secondPlayGate = audioService.enqueuePendingPlayUrl();
      final second = session.start(
        PlaybackSessionCommand(
          track: secondTrack,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );
      await audioService.waitForPlayUrlCallCount(2);

      stopGate.complete();
      await mediaOpen;
      final firstResult = await first;
      expect(firstResult.isSuperseded, isTrue);

      secondPlayGate.complete();
      final secondResult = await second;
      expect(secondResult.isCompleted, isTrue);
      expect(secondResult.track?.sourceId, 'media-open-stale-second');
    });

    test('media-open error terminalizes the active handoff', () async {
      final track = _track('task-two-media-open-placeholder');
      final playGate = audioService.enqueuePendingPlayUrl();

      final play = session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );
      await audioService.waitForPlayUrlCallCount(1);

      await session.onMediaOpenError(
        error:
            'Failed to open https://example.com/task-two-media-open-placeholder.m4a.',
        track: track,
        positionAtError: Duration.zero,
      );

      playGate.complete();
      final result = await play;

      expect(result.isTerminalMediaOpenError, isTrue);
      expect(audioService.stopCallCount, 2);
    });

    test('dispose supersedes pending handoff without reporting completion',
        () async {
      final finishedResults = <PlaybackSessionResult>[];
      final localAudioService = FakeAudioService();
      final localStreamManager = _HarnessPlaybackRequestStreamAccess();
      final localSession = PlaybackRequestSession(
        audioService: localAudioService,
        audioStreamManager: localStreamManager,
        getNextTrack: () => null,
        onLoadingStarted: (_) {},
        onLoadingFinished: (_, result) => finishedResults.add(result),
        terminalMediaOpenMessage: (track) => 'Cannot play ${track.title}',
        delay: (_) async {},
      );
      addTearDown(localSession.dispose);
      addTearDown(localAudioService.dispose);

      final playGate = localAudioService.enqueuePendingPlayUrl();
      final play = localSession.start(
        PlaybackSessionCommand(
          track: _track('dispose-pending-handoff'),
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );
      await localAudioService.waitForPlayUrlCallCount(1);

      localSession.dispose();
      final result = await play;

      expect(result.isSuperseded, isTrue);
      expect(finishedResults, isEmpty);

      playGate.complete();
      await pumpEventQueue(times: 5);
    });

    test('PlaybackRequestSession opens typed media instead of raw URL methods',
        () {
      final source = File('lib/services/audio/playback_request_session.dart')
          .readAsStringSync();

      expect(source, contains('_audioService.playMedia('));
      expect(source, contains('_audioService.setMedia('));
      expect(source, isNot(contains('_audioService.playUrl(')));
      expect(source, isNot(contains('_audioService.setUrl(')));
      expect(source, isNot(contains('_audioService.playFile(')));
      expect(source, isNot(contains('_audioService.setFile(')));
      expect(source, isNot(contains('headers: selection.headers')));
      expect(source, isNot(contains('headers: networkRequest.headers')));
    });
  });
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = sourceId;
}

class _HarnessPlaybackRequestStreamAccess
    implements PlaybackRequestStreamAccess {
  final List<String> selectionRequests = [];
  final List<String> fallbackSelectionTracks = [];
  final List<String?> fallbackSelectionFailedUrls = [];
  final List<String> ensureAudioStreamRequests = [];
  final List<String> prepareNetworkPlaybackRequests = [];
  final List<String> prefetchRequests = [];
  final List<Track> prefetchedTracks = [];
  final Map<String, Completer<void>> _prepareNetworkPlaybackWaiters = {};

  Future<PlaybackSelection> Function(Track track, bool persist)?
      onSelectPlayback;
  Future<PlaybackSelection?> Function(Track track, String? failedUrl)?
      onSelectFallbackPlayback;
  Future<RemotePlaybackMedia> Function(Track track, String url)?
      onPrepareNetworkPlayback;
  Future<(Track, String?, AudioStreamResult?)> Function(
    Track track,
    bool persist,
  )? onEnsureAudioStream;

  Future<void> waitForPrepareNetworkPlayback(String sourceId) {
    return (_prepareNetworkPlaybackWaiters[sourceId] ??= Completer<void>())
        .future;
  }

  @override
  Future<PlaybackSelection> selectPlayback(
    Track track, {
    bool persist = true,
  }) async {
    selectionRequests.add(track.sourceId);
    final custom = await onSelectPlayback?.call(track, persist);
    if (custom != null) return custom;
    final (trackWithUrl, localPath, streamResult) =
        await ensureAudioStream(track, persist: persist);
    final url = localPath ?? trackWithUrl.audioUrl;
    if (url == null) {
      throw StateError('No playback URL available for ${track.sourceId}');
    }
    final media = localPath == null
        ? await prepareNetworkPlayback(trackWithUrl, url)
        : LocalPlaybackMedia(path: localPath, track: trackWithUrl);
    return PlaybackSelection(
      media: media,
      streamResult: streamResult,
    );
  }

  @override
  Future<PlaybackSelection?> selectFallbackPlayback(
    Track track, {
    String? failedUrl,
  }) {
    fallbackSelectionTracks.add(track.sourceId);
    fallbackSelectionFailedUrls.add(failedUrl);
    return onSelectFallbackPlayback?.call(track, failedUrl) ??
        Future.value(null);
  }

  @override
  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  }) async {
    ensureAudioStreamRequests.add(track.sourceId);
    final custom = await onEnsureAudioStream?.call(track, persist);
    if (custom != null) return custom;
    track.audioUrl = 'https://example.com/${track.sourceId}.m4a';
    return (
      track,
      null,
      AudioStreamResult(
        url: track.audioUrl!,
        container: 'm4a',
        codec: 'aac',
        streamType: StreamType.audioOnly,
      ),
    );
  }

  @override
  Future<RemotePlaybackMedia> prepareNetworkPlayback(
    Track track,
    String url,
  ) async {
    prepareNetworkPlaybackRequests.add(track.sourceId);
    final waiter = _prepareNetworkPlaybackWaiters[track.sourceId];
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
    final custom = await onPrepareNetworkPlayback?.call(track, url);
    if (custom != null) return custom;
    return RemotePlaybackMedia(
      url: Uri.parse(url),
      headers: const {'Referer': 'https://example.com'},
      track: track,
    );
  }

  @override
  Future<void> prefetchTrack(Track track) async {
    prefetchRequests.add(track.sourceId);
    prefetchedTracks.add(track);
  }
}
