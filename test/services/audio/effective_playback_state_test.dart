import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/audio/audio_types.dart';
import 'package:fmp/services/audio/effective_playback_state.dart';

/// `AGENTS.md` 的 Platform Split 一節寫著「控制器擁有的載入階段，後端 idle
/// 事件不得覆蓋 loading 狀態」。這條規則在抽出來之前只存在於
/// `_onPlayerStateChanged` 的區域變數裡，沒有任何測試守著。
void main() {
  EffectivePlaybackState effectiveOf(
    bool playing,
    FmpAudioProcessingState processingState, {
    required bool loading,
    Duration position = const Duration(seconds: 42),
  }) {
    return EffectivePlaybackState.from(
      backend: FmpPlayerState(
        playing: playing,
        processingState: processingState,
      ),
      controllerIsLoading: loading,
      backendPosition: position,
    );
  }

  group('while the controller owns a load phase', () {
    test('a backend idle is read as loading, not as stopped', () {
      // 換歌時控制器自己呼叫 stop()，後端就送 idle 回來。直接投影會讓 UI 閃
      // 一下「已停止」。
      final effective = effectiveOf(
        false,
        FmpAudioProcessingState.idle,
        loading: true,
      );

      expect(effective.processingState, FmpAudioProcessingState.loading);
      expect(effective.isLoading, isTrue);
      expect(effective.isPlaying, isFalse);
    });

    test('a backend that claims to be playing is still not playing', () {
      final effective = effectiveOf(
        true,
        FmpAudioProcessingState.idle,
        loading: true,
      );

      expect(effective.isPlaying, isFalse);
    });

    test('a backend that is genuinely ready still reads as loading', () {
      // 串流已經開好但控制器還在收尾，這一段仍屬於載入。
      final effective = effectiveOf(
        true,
        FmpAudioProcessingState.ready,
        loading: true,
      );

      expect(effective.isLoading, isTrue);
      expect(effective.processingState, FmpAudioProcessingState.ready);
      // idle 才是控制器造成的假象；ready 的 playing 是真的。
      expect(effective.isPlaying, isTrue);
    });

    test('the published position is zero, never the previous track', () {
      final effective = effectiveOf(
        false,
        FmpAudioProcessingState.idle,
        loading: true,
        position: const Duration(minutes: 3),
      );

      expect(effective.position, Duration.zero);
    });
  });

  group('when the controller owns nothing', () {
    test('the backend is passed through unchanged', () {
      final effective = effectiveOf(
        false,
        FmpAudioProcessingState.idle,
        loading: false,
      );

      expect(effective.processingState, FmpAudioProcessingState.idle);
      expect(effective.isLoading, isFalse);
      expect(effective.isPlaying, isFalse);
      expect(effective.position, const Duration(seconds: 42));
    });

    test('the backend loading still counts as loading', () {
      final effective = effectiveOf(
        false,
        FmpAudioProcessingState.loading,
        loading: false,
      );

      expect(effective.isLoading, isTrue);
    });

    test('buffering is derived from the effective processing state', () {
      expect(
        effectiveOf(
          true,
          FmpAudioProcessingState.buffering,
          loading: false,
        ).isBuffering,
        isTrue,
      );
      // 載入中把 idle 改寫成 loading，不會意外變成 buffering。
      expect(
        effectiveOf(
          false,
          FmpAudioProcessingState.idle,
          loading: true,
        ).isBuffering,
        isFalse,
      );
    });
  });
}
