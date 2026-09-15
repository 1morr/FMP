import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/services/audio/audio_types.dart';
import 'package:fmp/services/audio/live_edge_seek_policy.dart';
import 'package:fmp/services/audio/next_media_plan.dart';
import 'package:fmp/services/audio/playback_end_reason_rules.dart';

import '../../support/fakes/fake_audio_service.dart';

/// 兩個後端在 `flutter test` 裡都建不起來 —— just_audio 要 platform channel，
/// media_kit 要 libmpv。所以「同一份斷言跑在三個後端上」不是靠實例化三個後端
/// 做到的，是靠把判斷抽成純規則、三個後端各留三行轉呼叫做到的。這份契約測的
/// 就是那三份規則，加上 `FakeAudioService` 真的答同一張表。
///
/// 真後端有沒有照著轉呼叫、有沒有偷偷留第二份關鍵字表，由
/// `test/services/static_rules/audio_backend_shared_rules_static_rule_test.dart`
/// 釘住。
void main() {
  group('seekToLive ladder', () {
    test('prefers duration when it is long enough', () {
      final candidates = liveEdgeCandidates(
        duration: const Duration(seconds: 30),
        buffered: const Duration(seconds: 20),
      );

      expect(candidates.first.strategy, LiveEdgeSeekStrategy.duration);
      expect(candidates.first.edge, const Duration(seconds: 30));
      // 緩衝那一步仍然留著當後備 —— duration seek 沒有效果時要接得下去。
      expect(candidates.last.strategy, LiveEdgeSeekStrategy.buffered);
    });

    test('falls back to the buffered edge when duration is null', () {
      // 直播流的 duration 幾乎永遠是 null。media_kit 原本在這裡就回 false 了。
      final candidates = liveEdgeCandidates(
        duration: null,
        buffered: const Duration(seconds: 30),
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.strategy, LiveEdgeSeekStrategy.buffered);
      expect(candidates.single.target, const Duration(seconds: 29));
    });

    test(
      'falls back to the buffered edge when the duration seek had no effect',
      () async {
        final service = FakeAudioService();
        addTearDown(service.dispose);
        service.setDurationValue(const Duration(seconds: 30));
        service.setBufferedPositionValue(const Duration(seconds: 45));
        // 位置已經在 duration 那一步的目標上：跳過去位置不會動，那一步不算成功。
        service.setPositionValue(const Duration(seconds: 29));

        expect(await service.seekToLive(), isTrue);
        expect(service.seekCalls, const [
          Duration(seconds: 29),
          Duration(seconds: 44),
        ]);
      },
    );

    test('refuses when neither span reaches five seconds', () {
      expect(
        liveEdgeCandidates(
          duration: const Duration(seconds: 4),
          buffered: const Duration(seconds: 4),
        ),
        isEmpty,
      );
    });

    test('targets one second before the edge', () {
      final candidates = liveEdgeCandidates(
        duration: const Duration(seconds: 5),
        buffered: const Duration(seconds: 5),
      );

      expect(candidates, hasLength(2));
      for (final candidate in candidates) {
        expect(candidate.target, candidate.edge - liveEdgeMargin);
      }
    });

    test('a sub-second position change counts as no effect', () {
      // 不可 seek 的串流上位置照樣往前走 —— 一秒以內分不出是 seek 還是播放。
      expect(
        seekTookEffect(
          const Duration(seconds: 10),
          const Duration(seconds: 10, milliseconds: 900),
        ),
        isFalse,
      );
      expect(
        seekTookEffect(
          const Duration(seconds: 10),
          const Duration(seconds: 11, milliseconds: 1),
        ),
        isTrue,
      );
    });
  });

  group('playback end reasons', () {
    test('duration == null is EndedPrematurely', () {
      final reason = classifyCompletion(
        duration: null,
        position: const Duration(seconds: 3),
      );

      expect(reason, isA<EndedPrematurely>());
      expect((reason as EndedPrematurely).expected, isNull);
      expect(reason.at, const Duration(seconds: 3));
    });

    test('duration == zero is EndedPrematurely', () {
      expect(
        classifyCompletion(duration: Duration.zero, position: Duration.zero),
        isA<EndedPrematurely>(),
      );
    });

    test('within completionTolerance is EndedNaturally', () {
      const duration = Duration(minutes: 4);
      expect(
        classifyCompletion(
          duration: duration,
          position: duration - AppConstants.completionTolerance,
        ),
        isA<EndedNaturally>(),
      );
    });

    test('one millisecond past the tolerance is EndedPrematurely', () {
      const duration = Duration(minutes: 4);
      final reason = classifyCompletion(
        duration: duration,
        position:
            duration -
            AppConstants.completionTolerance -
            const Duration(milliseconds: 1),
      );

      expect(reason, isA<EndedPrematurely>());
      expect((reason as EndedPrematurely).expected, duration);
    });

    test(
      'mpv could-not-open-audio-device is OutputDeviceFailed, not MediaUnopenable',
      () {
        // issue #41：`could not open` 同時落在媒體與裝置兩張表裡，裝置必須排前面。
        const raw = 'Could not open/initialize audio device -> no sound.';

        expect(classifyMpvMessage(raw), isA<OutputDeviceFailed>());
      },
    );

    test('ao-prefixed mpv log is OutputDeviceFailed', () {
      // media_kit 的 errorController 不轉發 `ao` prefix，所以這條走 log 流進來。
      expect(
        classifyMpvMessage('ao: [wasapi] init failed'),
        isA<OutputDeviceFailed>(),
      );
      expect(
        classifyMpvMessage('AO: [wasapi] Device lost'),
        isA<OutputDeviceFailed>(),
      );
    });

    test('ExoPlayer audio-track failure is OutputDeviceFailed', () {
      expect(
        classifyExoPlayerFailure(
          code: 5001,
          message: 'AudioTrack init failed',
          raw: 'PlayerException: code=5001, message=AudioTrack init failed',
        ),
        isA<OutputDeviceFailed>(),
      );
    });

    test('ExoPlayer code 0 source error is TransportFailed(reset)', () {
      // 實測形狀：整族網路失敗都被壓成 code=0 + `Source error`，code 分不出東西。
      final reason = classifyExoPlayerFailure(
        code: 0,
        message: 'Source error',
        raw: 'PlayerException: code=0, message=Source error',
      );

      expect(reason, isA<TransportFailed>());
      expect((reason as TransportFailed).kind, TransportFailureKind.reset);
    });

    test('response code 404 is MediaUnopenable', () {
      expect(
        classifyExoPlayerFailure(
          code: 2004,
          message: 'Response code: 404',
          raw: 'PlayerException: code=2004, message=Response code: 404',
        ),
        isA<MediaUnopenable>(),
      );
    });

    test('unmatched text is UnclassifiedFailure and keeps raw', () {
      const mpvRaw = 'something nobody has a table for';
      const exoRaw = 'PlayerException: code=7, message=???';

      final mpv = classifyMpvMessage(mpvRaw);
      final exo = classifyExoPlayerFailure(
        code: 7,
        message: '???',
        raw: exoRaw,
      );

      expect((mpv as UnclassifiedFailure).raw, mpvRaw);
      expect((exo as UnclassifiedFailure).raw, exoRaw);
    });

    test('transport kind covers timeout, dns, tls, refused, reset', () {
      expect(
        transportKindOf('operation timed out'),
        TransportFailureKind.timeout,
      );
      expect(
        transportKindOf('failed host lookup: upos-hz-mirrorakam.akamaized.net'),
        TransportFailureKind.dns,
      );
      expect(transportKindOf('tls handshake failed'), TransportFailureKind.tls);
      expect(
        transportKindOf('connection refused'),
        TransportFailureKind.refused,
      );
      expect(
        transportKindOf('connection reset by peer'),
        TransportFailureKind.reset,
      );
      expect(transportKindOf('no idea'), TransportFailureKind.unknown);
    });
  });

  group('setNextMedia playlist plan', () {
    test('arming with an empty playlist is a no-op', () {
      // 沒有東西在播就沒有可以接上去的位置 —— 追加會變成「開始播放」。
      final plan = NextMediaPlan.of(
        itemCount: 0,
        currentIndex: 0,
        hasMedia: true,
      );

      expect(plan.removeIndices, isEmpty);
      expect(plan.shouldAppend, isFalse);
    });

    test(
      'arming trims everything after the current index before appending',
      () {
        final plan = NextMediaPlan.of(
          itemCount: 3,
          currentIndex: 0,
          hasMedia: true,
        );

        // 由尾往前，否則移一個之後剩下的索引就位移了。
        expect(plan.removeIndices, [2, 1]);
        expect(plan.shouldAppend, isTrue);
      },
    );

    test('arming twice leaves exactly one lookahead item', () {
      final first = NextMediaPlan.of(
        itemCount: 1,
        currentIndex: 0,
        hasMedia: true,
      );
      expect(first.removeIndices, isEmpty);
      var itemCount = 1 + (first.shouldAppend ? 1 : 0);
      expect(itemCount, 2);

      final second = NextMediaPlan.of(
        itemCount: itemCount,
        currentIndex: 0,
        hasMedia: true,
      );
      itemCount -= second.removeIndices.length;
      itemCount += second.shouldAppend ? 1 : 0;

      expect(itemCount, 2);
    });

    test('null disarms without appending', () {
      final plan = NextMediaPlan.of(
        itemCount: 2,
        currentIndex: 0,
        hasMedia: false,
      );

      expect(plan.removeIndices, [1]);
      expect(plan.shouldAppend, isFalse);
    });

    test('trimming the played entry returns the current index to zero', () {
      // 後端接上第二個項目之後清單是 [播完的, 正在播的]，index 是 1。
      expect(NextMediaPlan.shouldTrimPlayedEntry(2), isTrue);
      // 移完只剩正在播的那一個，index 回到 0，下一次 arm 因此不必移任何東西。
      expect(NextMediaPlan.shouldTrimPlayedEntry(1), isFalse);
      expect(
        NextMediaPlan.of(
          itemCount: 1,
          currentIndex: 0,
          hasMedia: true,
        ).removeIndices,
        isEmpty,
      );
    });
  });

  group('the fake answers the same table', () {
    test('completion classification matches the shared rule', () async {
      final service = FakeAudioService();
      addTearDown(service.dispose);

      service.setDurationValue(null);
      service.setPositionValue(const Duration(seconds: 7));
      final premature = service.endReasons.first;
      service.emitCompleted();
      expect(await premature, isA<EndedPrematurely>());

      service.setDurationValue(const Duration(minutes: 4));
      service.setPositionValue(const Duration(minutes: 4));
      final natural = service.endReasons.first;
      service.emitCompleted();
      expect(await natural, isA<EndedNaturally>());
    });

    test('seekToLive runs the ladder instead of refusing outright', () async {
      final service = FakeAudioService();
      addTearDown(service.dispose);

      // 兩段都太短：跟真後端一樣回 false，呼叫端去重連。
      expect(await service.seekToLive(), isFalse);
      expect(service.seekCalls, isEmpty);

      service.setBufferedPositionValue(const Duration(seconds: 30));
      expect(await service.seekToLive(), isTrue);
      expect(service.seekCalls, const [Duration(seconds: 29)]);
      expect(service.position, const Duration(seconds: 29));
    });
  });
}
