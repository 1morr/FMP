import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/source_ids.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/playback_media.dart';

import '../../support/fakes/fake_audio_service.dart';

/// 前瞻媒體在假替身上的契約。
///
/// 兩個真後端的行為只有實機驗得到（ExoPlayer 的播放清單、mpv 的
/// `prefetch-playlist`），源碼層面由 `audio_backend_static_test.dart` 釘住。
/// 這裡釘的是 `FakeAudioService` —— B2 的 arm/disarm 條件表整份都靠它斷言，
/// 假替身自己壞掉的話，上面那一整批測試會全部變成假的通過。
void main() {
  Track trackOf(String id) => Track()
    ..sourceType = SourceIds.bilibili
    ..sourceId = id
    ..title = id;

  PreparedPlaybackMedia mediaOf(String id) => RemotePlaybackMedia(
    url: Uri.parse('https://example.com/$id.m4s'),
    headers: const {'Referer': 'https://www.bilibili.com/'},
    track: trackOf(id),
  );

  test('setNextMedia records the arm and the clear in order', () async {
    final service = FakeAudioService();
    addTearDown(service.dispose);

    final armed = mediaOf('BV1');
    await service.setNextMedia(armed);
    await service.setNextMedia(null);

    // null 也要進清單：disarm 是條件表裡一半的斷言，漏記等於驗不到。
    expect(service.setNextMediaCalls, [armed, null]);
  });

  test('emitAdvancedToNext delivers the medium that was handed over', () async {
    final service = FakeAudioService();
    addTearDown(service.dispose);

    final armed = mediaOf('BV2');
    final received = service.advancedToNext.first;
    service.emitAdvancedToNext(armed);

    expect(await received, same(armed));
    // 後端接上去之後位置從頭開始，而且還在播 —— 跟隨路徑會讀這兩個值。
    expect(service.position, Duration.zero);
    expect(service.isPlaying, isTrue);
  });

  test('playing a medium does not arm anything by itself', () async {
    final service = FakeAudioService();
    addTearDown(service.dispose);

    await service.playMedia(mediaOf('BV3'));

    expect(service.setNextMediaCalls, isEmpty);
  });
}
