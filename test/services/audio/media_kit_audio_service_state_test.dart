import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/audio_types.dart';
import 'package:fmp/services/audio/media_kit_audio_service.dart';
import 'package:fmp/services/audio/playback_media.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../../support/pump_until.dart';

/// 桌面後端的暫停與緩衝狀態，跑在真的 [MediaKitAudioService] 上。
///
/// `flutter test` 裡沒有 libmpv，所以把 media_kit 的 [PlatformPlayer] 換成
/// [_FakePlatformPlayer]：服務本身的狀態合成與開流流程照樣執行，只有引擎是假的。
void main() {
  late _FakePlatformPlayer engine;
  late MediaKitAudioService service;

  setUp(() async {
    engine = _FakePlatformPlayer();
    service = MediaKitAudioService(platformPlayer: engine);
    await service.initialize();
  });

  tearDown(() => service.dispose());

  group('a pause pressed while the stream is opening', () {
    test('holds while the engine is still filling its cache', () async {
      final opening = service.playUrl('https://example.com/a.m4a');
      await pumpUntil(
        () => engine.opened,
        reason: 'playUrl has handed the medium to the engine',
      );
      engine
        ..emitDuration(const Duration(minutes: 3))
        ..emitBuffering(true);
      await pumpUntil(
        () => service.processingState == FmpAudioProcessingState.buffering,
        reason: 'the engine is still filling its cache after open()',
      );

      // 媒體鍵按兩下：第一下把 `play: false` 開的流叫起來，第二下暫停。
      await service.togglePlayPause();
      await service.togglePlayPause();
      engine.emitBuffering(false);
      await opening;

      expect(engine.state.playing, isFalse);
      expect(service.isPlaying, isFalse);
    });

    test('holds when it lands before the duration arrives', () async {
      final opening = service.playUrl('https://example.com/a.m4a');
      await pumpUntil(
        () => engine.opened,
        reason: 'playUrl has handed the medium to the engine',
      );

      // 還在等時長，`_ensurePlayback` 根本還沒開始。
      await service.togglePlayPause();
      await service.togglePlayPause();
      engine.emitDuration(const Duration(minutes: 3));
      await opening;

      expect(engine.state.playing, isFalse);
      expect(service.isPlaying, isFalse);
    });

    test('an untouched open still starts playing', () async {
      final opening = service.playUrl('https://example.com/a.m4a');
      await pumpUntil(
        () => engine.opened,
        reason: 'playUrl has handed the medium to the engine',
      );
      engine.emitDuration(const Duration(minutes: 3));
      await opening;

      expect(engine.state.playing, isTrue);
    });
  });

  group('processing state while playing', () {
    test('mpv buffering mid-playback reports buffering, not ready', () async {
      engine
        ..emitDuration(const Duration(minutes: 3))
        ..emitPlaying(true);
      await pumpUntil(
        () => service.processingState == FmpAudioProcessingState.ready,
        reason: 'playing with a known duration is ready',
      );

      // mpv 的 `paused-for-cache`：還在「播放」，但沒有聲音。
      engine.emitBuffering(true);
      await pumpUntil(
        () => service.processingState == FmpAudioProcessingState.buffering,
        reason: 'the cache ran dry while playing',
      );
      expect(service.isPlaying, isTrue);

      engine.emitBuffering(false);
      await pumpUntil(
        () => service.processingState == FmpAudioProcessingState.ready,
        reason: 'the cache refilled',
      );
    });
  });

  group('gapless handover', () {
    test('asks mpv to open the next playlist entry ahead of time', () {
      // mpv 的 `prefetch-playlist` 預設是 `no`，media_kit 從不設它。少了這個
      // 屬性，前瞻項目要等到交界才開流 —— 不會有任何錯誤，只是不再 gapless。
      expect(engine.properties, containsPair('prefetch-playlist', 'yes'));
      // 純音訊設定跟它走同一段，一起確認有送到引擎。
      expect(engine.properties, containsPair('vid', 'no'));
      expect(
        engine.properties,
        containsPair(
          'network-timeout',
          '${MediaKitAudioService.desktopNetworkTimeoutSeconds}',
        ),
      );
    });

    test('an engine that moves to the next entry hands it over', () async {
      final opening = service.playUrl('https://example.com/a.m4a');
      await pumpUntil(
        () => engine.opened,
        reason: 'playUrl has handed the medium to the engine',
      );
      engine.emitDuration(const Duration(minutes: 3));
      await opening;

      final next = RemotePlaybackMedia(
        url: Uri.parse('https://example.com/b.m4a'),
        headers: const {'Referer': 'https://example.com/'},
        track: Track()
          ..sourceType = SourceIds.bilibili
          ..sourceId = 'b'
          ..title = 'b',
      );
      await service.setNextMedia(next);
      expect(engine.state.playlist.medias, hasLength(2));

      // 第一首播完時 mpv 不發 `completed`（那是整串播完才有），只把索引往前推。
      final handedOver = <PreparedPlaybackMedia>[];
      final subscription = service.advancedToNext.listen(handedOver.add);
      addTearDown(subscription.cancel);
      engine.advance();

      await pumpUntil(
        () => handedOver.isNotEmpty,
        reason: 'the index change is reported as a handover',
      );
      expect(handedOver.single, same(next));
      await pumpUntil(
        () => engine.state.playlist.medias.length == 1,
        reason: 'the finished entry is trimmed off the front',
      );
    });
  });

  // 簽名串流網址會落盤到 log 檔（#163）。三個來源的簽章分別在 query（Bilibili）
  // 與中間的 path 段（YouTube HLS、網易雲），只去掉 query 不夠。
  group('signed stream URLs stay out of the log', () {
    const bilibili =
        'https://upos-sz-mirror.bilivideo.com/upgcxcode/30/12/123/'
        '123-1-30280.m4s?e=ig8eux&deadline=1758800000&upsig=0123abcdef';
    const youtube =
        'https://manifest.googlevideo.com/api/manifest/hls_playlist/'
        'expire/1758800000/ei/abc/sig/SECRETSIG/file/index.m3u8';
    const netease =
        'http://m701.music.126.net/20260925120000/'
        '0123456789abcdef0123456789abcdef/jdymusic/obj/abc/123/file.flac';

    String logText() => AppLogger.logs.map((e) => e.message).join('\n');

    setUp(AppLogger.clearLogs);

    test('opening and playing a URL logs only its label', () async {
      final opening = service.playUrl(bilibili);
      await pumpUntil(
        () => engine.opened,
        reason: 'playUrl has handed the medium to the engine',
      );
      engine.emitDuration(const Duration(minutes: 3));
      await opening;

      final text = logText();
      expect(text, contains('upos-sz-mirror.bilivideo.com'));
      expect(text, contains('123-1-30280.m4s'));
      // 舊的 80 字元截斷剛好切在 query 開頭之後，所以比對 `?e=` 而不是整段簽章。
      expect(text, isNot(contains('?e=')));
      expect(text, isNot(contains('deadline')));
      expect(text, isNot(contains('0123abcdef')));
    });

    test('setting a URL logs only its label', () async {
      final setting = service.setUrl(netease);
      await pumpUntil(
        () => engine.opened,
        reason: 'setUrl has handed the medium to the engine',
      );
      engine.emitDuration(const Duration(minutes: 3));
      await setting;

      final text = logText();
      expect(text, contains('m701.music.126.net'));
      expect(text, isNot(contains('20260925120000')));
      expect(text, isNot(contains('0123456789abcdef')));
    });

    test(
      'arming and advancing to the next medium log only its label',
      () async {
        final opening = service.playUrl('https://example.com/a.m4a');
        await pumpUntil(
          () => engine.opened,
          reason: 'playUrl has handed the medium to the engine',
        );
        engine.emitDuration(const Duration(minutes: 3));
        await opening;

        final next = RemotePlaybackMedia(
          url: Uri.parse(youtube),
          headers: const {},
          track: Track()
            ..sourceType = SourceIds.youtube
            ..sourceId = 'b'
            ..title = 'b',
        );
        await service.setNextMedia(next);
        final handedOver = <PreparedPlaybackMedia>[];
        final subscription = service.advancedToNext.listen(handedOver.add);
        addTearDown(subscription.cancel);
        engine.advance();
        await pumpUntil(
          () => handedOver.isNotEmpty,
          reason: 'the index change is reported as a handover',
        );

        final messages = AppLogger.logs.map((e) => e.message).toList();
        final armed = messages.where((m) => m.contains('Next medium armed'));
        final advanced = messages.where(
          (m) => m.contains('Backend advanced to next medium'),
        );
        expect(armed.single, contains('manifest.googlevideo.com'));
        expect(advanced.single, contains('index.m3u8'));

        final text = logText();
        expect(text, isNot(contains('SECRETSIG')));
        expect(text, isNot(contains('expire/1758800000')));
      },
    );
  });
}

/// 只做開流與播放控制，其餘由測試直接推事件，就像 libmpv 回報屬性變化。
class _FakePlatformPlayer extends PlatformPlayer {
  _FakePlatformPlayer() : super(configuration: const PlayerConfiguration());

  bool opened = false;

  /// 服務透過 `(platform as dynamic).setProperty` 送給 libmpv 的屬性。
  final properties = <String, String>{};

  Future<void> setProperty(String property, String value) async {
    properties[property] = value;
  }

  /// 像 mpv 播完當前項目、接上下一個那樣把索引往前推一格。
  void advance() {
    final playlist = state.playlist.copyWith(index: state.playlist.index + 1);
    state = state.copyWith(playlist: playlist);
    playlistController.add(playlist);
  }

  @override
  Future<void> add(Media media) async {
    final playlist = state.playlist.copyWith(
      medias: [...state.playlist.medias, media],
    );
    state = state.copyWith(playlist: playlist);
    playlistController.add(playlist);
  }

  @override
  Future<void> remove(int index) async {
    final medias = [...state.playlist.medias]..removeAt(index);
    final current = state.playlist.index;
    final playlist = Playlist(
      medias,
      index: index < current ? current - 1 : current,
    );
    state = state.copyWith(playlist: playlist);
    playlistController.add(playlist);
  }

  void emitPlaying(bool playing) {
    state = state.copyWith(playing: playing);
    playingController.add(playing);
  }

  void emitBuffering(bool buffering) {
    state = state.copyWith(buffering: buffering);
    bufferingController.add(buffering);
  }

  void emitDuration(Duration duration) {
    state = state.copyWith(duration: duration);
    durationController.add(duration);
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final playlist = playable is Playlist
        ? playable
        : Playlist([playable as Media]);
    state = state.copyWith(playlist: playlist);
    playlistController.add(playlist);
    opened = true;
    if (play) emitPlaying(true);
  }

  @override
  Future<void> stop() async {
    if (state.playing) emitPlaying(false);
  }

  @override
  Future<void> play() async => emitPlaying(true);

  @override
  Future<void> pause() async => emitPlaying(false);

  @override
  Future<void> playOrPause() => state.playing ? pause() : play();
}
