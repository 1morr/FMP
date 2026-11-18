import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/platform/windows_media_controls.dart';
import 'package:fmp/playback/media_controls.dart';
import 'package:fmp/playback/playback.dart';

/// Windows 的系統媒體控制在 Dart 這一端：[NowPlaying] 轉成 `fmp/media` 頻道
/// 的呼叫，runner（`windows/runner/media_controls.cpp`）送回的指令轉成
/// [MediaCommand]。原生端換成 mock 的頻道。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fmp/media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory logDir;
  late Log log;
  var logClosed = false;
  late List<MethodCall> calls;
  late WindowsMediaControls controls;
  late List<MediaCommand> commands;

  Track track(String id, {String? cover}) => Track(
    ref: TrackRef(pluginId: 'songs', trackId: id),
    title: 'Title $id',
    author: 'Author $id',
    coverUrl: cover,
  );

  NowPlaying nowPlaying(
    Track track, {
    PlaybackStatus status = PlaybackStatus.playing,
    Duration position = const Duration(seconds: 12),
    Duration? duration = const Duration(minutes: 3),
  }) => NowPlaying(
    track: track,
    status: status,
    position: position,
    duration: duration,
    canPrevious: false,
    canNext: true,
  );

  setUp(() async {
    logDir = Directory.systemTemp.createTempSync('fmp_smtc_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    logClosed = false;
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    controls = WindowsMediaControls(log);
    commands = [];
    controls.commands.listen(commands.add);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    controls.dispose();
    if (!logClosed) await log.close();
    logDir.deleteSync(recursive: true);
  });

  Future<void> fromRunner(String name, [int? positionMs]) async {
    await messenger.handlePlatformMessage(
      'fmp/media',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('command', {'name': name, 'positionMs': ?positionMs}),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  test('a new track sends its metadata, then the playback state', () async {
    controls.show(
      nowPlaying(track('a', cover: 'https://img.example.com/a.webp')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(calls.map((c) => c.method), ['metadata', 'state']);
    expect(calls[0].arguments, {
      'title': 'Title a',
      'artist': 'Author a',
      'thumbnail': 'https://img.example.com/a.webp',
    });
    expect(calls[1].arguments, {
      'status': 'playing',
      'positionMs': 12000,
      'durationMs': 180000,
      'canPrevious': false,
      'canNext': true,
    });
  });

  test('the same track only sends the playback state again', () async {
    controls.show(nowPlaying(track('a')));
    controls.show(
      nowPlaying(
        track('a'),
        status: PlaybackStatus.paused,
        position: const Duration(seconds: 20),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(calls.map((c) => c.method), ['metadata', 'state', 'state']);
    expect(calls[2].arguments['status'], 'paused');
    expect(calls[2].arguments['positionMs'], 20000);
  });

  test('a track without a cover sends no thumbnail; another track sends '
      'its metadata again', () async {
    controls.show(nowPlaying(track('a', cover: 'https://img.example.com/a')));
    controls.show(nowPlaying(track('b')));
    await Future<void>.delayed(Duration.zero);

    expect(calls.map((c) => c.method), [
      'metadata',
      'state',
      'metadata',
      'state',
    ]);
    expect(calls[2].arguments, {'title': 'Title b', 'artist': 'Author b'});
  });

  test('loading and buffering are "changing", finished and failed are '
      '"paused", an unknown length is left out', () async {
    String status(PlaybackStatus s) {
      controls.show(nowPlaying(track('a'), status: s, duration: null));
      return calls.last.arguments['status'] as String;
    }

    expect(status(PlaybackStatus.resolving), 'changing');
    expect(status(PlaybackStatus.loading), 'changing');
    expect(status(PlaybackStatus.buffering), 'changing');
    expect(status(PlaybackStatus.completed), 'paused');
    expect(status(PlaybackStatus.failed), 'paused');
    expect(calls.last.arguments.containsKey('durationMs'), isFalse);
  });

  test('nothing playing clears the controls', () async {
    controls.show(nowPlaying(track('a')));
    controls.show(null);
    controls.show(nowPlaying(track('a')));
    await Future<void>.delayed(Duration.zero);

    expect(calls.map((c) => c.method), [
      'metadata',
      'state',
      'clear',
      'metadata',
      'state',
    ]);
  });

  test('buttons and seeks from the runner become commands', () async {
    await fromRunner('play');
    await fromRunner('pause');
    await fromRunner('next');
    await fromRunner('previous');
    await fromRunner('seek', 61000);
    await fromRunner('record');

    expect(commands, const [
      PlayCommand(),
      PauseCommand(),
      NextCommand(),
      PreviousCommand(),
      SeekCommand(Duration(seconds: 61)),
    ]);
  });

  test('a failing runner call is logged, not thrown', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'smtc', message: 'unavailable');
    });

    controls.show(nowPlaying(track('a')));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await log.close();
    logClosed = true;

    final text = File('${logDir.path}/${Log.fileName}').readAsStringSync();
    expect(text, contains('Updating the Windows media controls failed'));
  });
}
