import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';
import 'package:fmp/platform/media_controls/media_controls_windows.dart';
import 'package:smtc_windows/smtc_windows.dart' as smtc;

import '../support/pump_until.dart';

NowPlaying nowPlaying({
  String id = 'a',
  String? uploader = 'Uploader a',
  MediaPhase phase = MediaPhase.ready,
  bool playing = true,
  Duration position = const Duration(seconds: 12),
  Duration? duration = const Duration(minutes: 3),
  Uri? artworkUrl,
  List<MediaControl> controls = const [
    MediaControl.previous,
    MediaControl.pause,
    MediaControl.next,
  ],
}) => NowPlaying(
  id: 'fmp-test:$id',
  title: 'Song $id',
  uploader: uploader,
  duration: duration,
  artworkUrl: artworkUrl,
  phase: phase,
  playing: playing,
  position: position,
  controls: controls,
);

/// 記下 [WindowsSystemMediaControls] 對 SMTC 的每次呼叫（不載入 Rust 端）。
final class _FakeSmtc implements smtc.SMTCWindows {
  final calls = <String>[];
  final buttons = StreamController<smtc.PressedButton>.broadcast();

  @override
  Stream<smtc.PressedButton> get buttonPressStream => buttons.stream;

  @override
  Future<void> enableSmtc() async => calls.add('enable');

  @override
  Future<void> disableSmtc() async => calls.add('disable');

  @override
  Future<void> clearMetadata() async => calls.add('clear');

  @override
  Future<void> updateMetadata(smtc.MusicMetadata metadata) async =>
      calls.add('metadata ${metadata.title} ${metadata.artist}');

  @override
  Future<void> updateConfig(smtc.SMTCConfig config) async =>
      calls.add('config');

  @override
  Future<void> updateTimeline(smtc.PlaybackTimeline timeline) async =>
      calls.add('timeline ${timeline.positionMs}');

  @override
  Future<void> setPlaybackStatus(smtc.PlaybackStatus status) async =>
      calls.add('status ${status.name}');

  @override
  Future<void> dispose() async => calls.add('dispose');

  @override
  Object? noSuchMethod(Invocation invocation) =>
      fail('unexpected call: ${invocation.memberName}');
}

void main() {
  group('the adapter', () {
    late _FakeSmtc fake;
    late WindowsSystemMediaControls controls;

    setUp(() {
      fake = _FakeSmtc();
      controls = WindowsSystemMediaControls(fake);
    });

    test('stays disabled while idle', () async {
      await controls.publish(
        nowPlaying(phase: MediaPhase.idle, playing: false),
      );

      expect(fake.calls, isEmpty);
    });

    test('enables before the first track and pushes every part', () async {
      await controls.publish(nowPlaying());

      expect(fake.calls, [
        'enable',
        'metadata Song a Uploader a',
        'config',
        'timeline 12000',
        'status playing',
      ]);
    });

    test('pushes only the parts that changed', () async {
      await controls.publish(nowPlaying());
      fake.calls.clear();

      await controls.publish(nowPlaying(position: const Duration(seconds: 17)));

      expect(fake.calls, ['timeline 17000']);
    });

    test(
      'going idle clears and disables, coming back pushes everything',
      () async {
        await controls.publish(nowPlaying());
        await controls.publish(
          nowPlaying(phase: MediaPhase.idle, playing: false),
        );
        await controls.publish(
          nowPlaying(phase: MediaPhase.idle, playing: false),
        );
        expect(fake.calls.skip(5), ['clear', 'disable']);
        fake.calls.clear();

        await controls.publish(nowPlaying());

        expect(fake.calls, [
          'enable',
          'metadata Song a Uploader a',
          'config',
          'timeline 12000',
          'status playing',
        ]);
      },
    );

    test(
      'a next track without an uploader does not keep the old one',
      () async {
        await controls.publish(nowPlaying());
        fake.calls.clear();

        await controls.publish(nowPlaying(id: 'b', uploader: null));

        expect(fake.calls.take(2), ['clear', 'metadata Song b null']);
      },
    );

    test(
      'a next track with every field replaces them without clearing',
      () async {
        await controls.publish(nowPlaying());
        fake.calls.clear();

        await controls.publish(nowPlaying(id: 'b', uploader: 'Uploader b'));

        expect(fake.calls.first, 'metadata Song b Uploader b');
        expect(fake.calls, isNot(contains('clear')));
      },
    );

    test('key presses become commands until disposed', () async {
      final commands = <MediaCommand>[];
      controls.commands.listen(commands.add);

      fake.buttons
        ..add(smtc.PressedButton.stop)
        ..add(smtc.PressedButton.fastForward);
      await settle();
      await controls.dispose();
      fake.buttons.add(smtc.PressedButton.play);
      await settle();

      expect(commands, [isA<MediaStop>()]);
      expect(fake.calls, ['dispose']);
      expect(fake.buttons.hasListener, isFalse);
    });
  });

  group('metadata', () {
    test('carries the title and the uploader', () {
      final metadata = smtcMetadataOf(nowPlaying());

      expect(metadata.title, 'Song a');
      expect(metadata.artist, 'Uploader a');
      expect(metadata.thumbnail, isNull);
    });

    test('an https artwork url goes out as is', () {
      final url = Uri.parse('https://i0.hdslb.com/bfs/a.jpg?x=1');
      final metadata = smtcMetadataOf(nowPlaying(artworkUrl: url));

      expect(metadata.thumbnail, url.toString());
    });

    test('an artwork that is not a usable https url is left out', () {
      // smtc_windows unwraps CreateUri / CreateFromUri: a bad string panics.
      // file:/// is not readable by an unpackaged app's SMTC (2026-10-07).
      expect(smtcThumbnailOf(null), isNull);
      expect(smtcThumbnailOf(Uri.parse('http://example.com/a.jpg')), isNull);
      expect(smtcThumbnailOf(Uri.parse('file:///C:/cache/a.jpg')), isNull);
      expect(smtcThumbnailOf(Uri.parse('relative/path.jpg')), isNull);
      expect(smtcThumbnailOf(Uri.parse('https:///a.jpg')), isNull);
      expect(smtcThumbnailOf(Uri.parse('https:')), isNull);
    });

    test('a port WinRT rejects is left out', () {
      // Uri.tryParse accepts any port; Windows.Foundation.Uri.CreateUri fails
      // with E_INVALIDARG above 65535 (checked with windows 0.58, 2026-10-07).
      expect(smtcThumbnailOf(Uri.parse('https://x.test:99999/a.jpg')), isNull);
      expect(
        smtcThumbnailOf(Uri.parse('https://x.test:65535/a.jpg')),
        'https://x.test:65535/a.jpg',
      );
    });

    test('odd characters go out percent-encoded', () {
      // Spaces, non-ASCII and brackets come out of Uri as %XX, which CreateUri
      // accepts (checked with windows 0.58, 2026-10-07).
      expect(
        smtcThumbnailOf(Uri.parse('https://x.test/a b/封面[1].jpg')),
        'https://x.test/a%20b/%E5%B0%81%E9%9D%A2%5B1%5D.jpg',
      );
    });
  });

  group('clearing before an update', () {
    // updateMetadata only sets the fields that are not null; SMTC keeps the
    // rest from the previous track until ClearAll.
    const full = smtc.MusicMetadata(
      title: 'Song a',
      artist: 'Uploader a',
      thumbnail: 'https://x.test/a.jpg',
    );

    test('happens when a field the previous track had is now missing', () {
      expect(
        smtcClearsMetadata(
          full,
          const smtc.MusicMetadata(title: 'b', thumbnail: 'https://x.test/b'),
        ),
        isTrue,
        reason: 'no uploader',
      );
      expect(
        smtcClearsMetadata(
          full,
          const smtc.MusicMetadata(title: 'b', artist: 'Uploader b'),
        ),
        isTrue,
        reason: 'no artwork',
      );
    });

    test('does not happen when every field is replaced', () {
      expect(smtcClearsMetadata(null, full), isFalse);
      expect(
        smtcClearsMetadata(
          full,
          const smtc.MusicMetadata(
            title: 'b',
            artist: 'Uploader b',
            thumbnail: 'https://x.test/b.jpg',
          ),
        ),
        isFalse,
      );
      expect(
        smtcClearsMetadata(
          const smtc.MusicMetadata(title: 'a'),
          const smtc.MusicMetadata(title: 'b', artist: 'Uploader b'),
        ),
        isFalse,
      );
    });
  });

  group('timeline', () {
    test('has the position and the duration', () {
      final timeline = smtcTimelineOf(nowPlaying());

      expect(timeline.startTimeMs, 0);
      expect(timeline.endTimeMs, 180000);
      expect(timeline.positionMs, 12000);
    });

    test('an unknown duration is zero and the position is kept', () {
      final timeline = smtcTimelineOf(nowPlaying(duration: null));

      expect(timeline.endTimeMs, 0);
      expect(timeline.positionMs, 12000);
    });

    test('the position never passes the duration', () {
      final timeline = smtcTimelineOf(
        nowPlaying(position: const Duration(minutes: 4)),
      );

      expect(timeline.positionMs, 180000);
    });
  });

  group('status', () {
    test('follows the phase and whether it plays', () {
      expect(
        smtcStatusOf(nowPlaying(phase: MediaPhase.idle, playing: false)),
        smtc.PlaybackStatus.closed,
      );
      expect(
        smtcStatusOf(nowPlaying(phase: MediaPhase.loading)),
        smtc.PlaybackStatus.changing,
      );
      expect(
        smtcStatusOf(nowPlaying(phase: MediaPhase.buffering)),
        smtc.PlaybackStatus.changing,
      );
      expect(smtcStatusOf(nowPlaying()), smtc.PlaybackStatus.playing);
      // Android 為了留住前景服務才有的階段（對系統是在播）：SMTC 照實顯示暫停。
      expect(
        smtcStatusOf(nowPlaying(phase: MediaPhase.interrupted)),
        smtc.PlaybackStatus.paused,
      );
      expect(
        smtcStatusOf(nowPlaying(playing: false)),
        smtc.PlaybackStatus.paused,
      );
    });
  });

  group('buttons', () {
    test('are enabled by the controls', () {
      final playing = smtcConfigOf(nowPlaying());
      expect(playing.prevEnabled, isTrue);
      expect(playing.pauseEnabled, isTrue);
      expect(playing.playEnabled, isFalse);
      expect(playing.nextEnabled, isTrue);

      final last = smtcConfigOf(
        nowPlaying(
          playing: false,
          controls: const [MediaControl.previous, MediaControl.play],
        ),
      );
      expect(last.playEnabled, isTrue);
      expect(last.pauseEnabled, isFalse);
      expect(last.nextEnabled, isFalse);
    });

    test(
      'stop is enabled whenever there is a track, so it reaches the app',
      () {
        for (final phase in [
          MediaPhase.loading,
          MediaPhase.buffering,
          MediaPhase.ready,
        ]) {
          expect(
            smtcConfigOf(nowPlaying(phase: phase)).stopEnabled,
            isTrue,
            reason: phase.name,
          );
        }
        expect(smtcConfigOf(nowPlaying(playing: false)).stopEnabled, isTrue);
        expect(
          smtcConfigOf(nowPlaying(phase: MediaPhase.idle, playing: false))
              .stopEnabled,
          isFalse,
        );
      },
    );

    test('fast forward and rewind are never enabled', () {
      final config = smtcConfigOf(nowPlaying());

      expect(config.fastForwardEnabled, isFalse);
      expect(config.rewindEnabled, isFalse);
    });
  });

  group('key presses', () {
    test('map to media commands, stop included', () {
      expect(mediaCommandOf(smtc.PressedButton.play), isA<MediaPlay>());
      expect(mediaCommandOf(smtc.PressedButton.pause), isA<MediaPause>());
      expect(mediaCommandOf(smtc.PressedButton.next), isA<MediaNext>());
      expect(mediaCommandOf(smtc.PressedButton.previous), isA<MediaPrevious>());
      expect(mediaCommandOf(smtc.PressedButton.stop), isA<MediaStop>());
    });

    test('keys without a command are ignored', () {
      for (final button in [
        smtc.PressedButton.fastForward,
        smtc.PressedButton.rewind,
        smtc.PressedButton.record,
        smtc.PressedButton.channelUp,
        smtc.PressedButton.channelDown,
      ]) {
        expect(mediaCommandOf(button), isNull, reason: button.name);
      }
    });
  });
}
