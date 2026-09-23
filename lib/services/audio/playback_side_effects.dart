import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:fmp/core/logger.dart';
import 'package:fmp/data/database/repository_providers.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';
import 'package:fmp/services/audio/audio_types.dart';
import 'package:fmp/services/audio/lyrics_auto_match_coordinator.dart';
import 'package:fmp/services/audio/now_playing_publisher.dart';
import 'package:fmp/services/audio/play_history_recorder.dart';
import 'package:fmp/services/lyrics/lyrics_auto_match_service.dart';

/// 一次播放狀態發佈要送出去的全部值。
///
/// 六個值在 `AudioController._publishPlaybackState` 裡本來就已經湊齊（其中三個
/// 是現讀 `FmpAudioService` 的）。收成一個快照，是為了讓 [PlaybackSideEffect]
/// 的簽名不必跟著任何一個消費者的參數表走 —— 多一個消費者要的值，改的是這裡，
/// 不是每一個扇出站點。
class PlaybackStateSnapshot {
  const PlaybackStateSnapshot({
    required this.isPlaying,
    required this.position,
    required this.bufferedPosition,
    required this.processingState,
    this.duration,
    this.speed = 1.0,
  });

  final bool isPlaying;
  final Duration position;
  final Duration bufferedPosition;
  final FmpAudioProcessingState processingState;
  final Duration? duration;
  final double speed;
}

/// 播放發生了什麼事，要通知誰。
///
/// 「開始播一首歌」以前在控制器裡有兩個扇出站點（正常播放請求的成功路徑、
/// 跟隨後端 gapless 交界的路徑），各自逐一呼叫三個消費者。兩份清單靠人維持
/// 一致，而它們已經不一致過：跟隨路徑的歌詞比對是後來補上的，補之前交界之後
/// 的那一首永遠配不到歌詞。
///
/// 它刻意**不擁有**：節流（位置一秒數次、狀態轉換一次都不能丟，兩者不能共用
/// 同一個節流器，留在 `AudioController`）、「這次算不算一次新播放」的判斷
/// （只有控制器知道這是使用者切歌、重試、還是啟動還原）、以及任何會讓播放等
/// 它的東西 —— 見 [PlaybackSideEffectRegistry] 的失敗語意。
abstract interface class PlaybackSideEffect {
  /// 開始播 [track]。
  ///
  /// [countsAsNewPlay] 為 false 代表這是同一次播放的再次投影（先更新 UI、
  /// 拿到 URL 後再補記）、重試、或啟動還原。只在意「新的一次播放」的消費者
  /// 自己閘掉它。
  void onTrackStarted(Track track, {required bool countsAsNewPlay});

  void onPlaybackStateChanged(PlaybackStateSnapshot snapshot);

  void onStopped();

  void dispose();
}

/// 把一次通知扇出給每一個 [PlaybackSideEffect]。
///
/// **副作用失敗不是播放失敗。** 每一次呼叫各自包在 try-catch 裡：只記 log，
/// 不 rethrow，也不中斷後面還沒收到通知的消費者。寫歷史失敗是統計少一筆，
/// 配歌詞失敗是這首沒有歌詞 —— 兩者都不該讓歌停下來，而在 for 迴圈裡直接
/// 逐一呼叫的話，第一個拋出來的就會把後面全部吃掉。
///
/// [dispose] 反著註冊順序走，並且會閂住：之後的呼叫靜默丟棄。反序是為了讓
/// 系統媒體控制最後才交還 —— 任何一個「還在飛」的發佈都已經落地了才解綁。
class PlaybackSideEffectRegistry with Logging implements PlaybackSideEffect {
  PlaybackSideEffectRegistry(List<PlaybackSideEffect> effects)
    : _effects = List.of(effects);

  final List<PlaybackSideEffect> _effects;

  @override
  void onTrackStarted(Track track, {required bool countsAsNewPlay}) {
    _fanOut(
      'onTrackStarted',
      (effect) =>
          effect.onTrackStarted(track, countsAsNewPlay: countsAsNewPlay),
    );
  }

  @override
  void onPlaybackStateChanged(PlaybackStateSnapshot snapshot) {
    _fanOut(
      'onPlaybackStateChanged',
      (effect) => effect.onPlaybackStateChanged(snapshot),
    );
  }

  @override
  void onStopped() => _fanOut('onStopped', (effect) => effect.onStopped());

  @override
  void dispose() {
    // 先清空再逐一 dispose：清空即閂住，之後的通知（含 dispose 自己再進來一次）
    // 都在空清單上迭代，什麼都不會發生。
    final effects = _effects.reversed.toList();
    _effects.clear();
    for (final effect in effects) {
      _guard('dispose', effect, effect.dispose);
    }
  }

  void _fanOut(String what, void Function(PlaybackSideEffect effect) call) {
    for (final effect in _effects) {
      _guard(what, effect, () => call(effect));
    }
  }

  void _guard(String what, PlaybackSideEffect effect, void Function() call) {
    try {
      call();
    } catch (e, stack) {
      logError(
        'Playback side effect ${effect.runtimeType}.$what failed',
        e,
        stack,
      );
    }
  }
}

/// 通知欄／SMTC。
///
/// [dispose] 交還系統媒體控制，刻意**不** dispose 原生控制代碼：需要跟著
/// controller 一起消失的是回呼繫結，不是 SMTC 本身 —— 原生 session 只在
/// `main.dart` 建立一次，dispose 掉之後沒有任何程式碼會重建它。按鈕訂閱留著，
/// 解綁後它派發到 null，正是 app 啟動時的狀態。
class NowPlayingSideEffect implements PlaybackSideEffect {
  NowPlayingSideEffect(this._publisher);

  final NowPlayingPublisher _publisher;

  @override
  void onTrackStarted(Track track, {required bool countsAsNewPlay}) {
    _publisher.publishTrack(NowPlayingOwner.music, track);
  }

  @override
  void onPlaybackStateChanged(PlaybackStateSnapshot snapshot) {
    _publisher.publishPlaybackState(
      NowPlayingOwner.music,
      isPlaying: snapshot.isPlaying,
      position: snapshot.position,
      bufferedPosition: snapshot.bufferedPosition,
      processingState: snapshot.processingState,
      duration: snapshot.duration,
      speed: snapshot.speed,
    );
  }

  @override
  void onStopped() => _publisher.publishStopped(NowPlayingOwner.music);

  @override
  void dispose() => _publisher.release(NowPlayingOwner.music);
}

/// 播放歷史。只認新的一次播放。
class PlayHistorySideEffect implements PlaybackSideEffect {
  PlayHistorySideEffect(this._recorder);

  final PlayHistoryRecorder _recorder;

  @override
  void onTrackStarted(Track track, {required bool countsAsNewPlay}) {
    if (!countsAsNewPlay) return;
    _recorder.record(track);
  }

  @override
  void onPlaybackStateChanged(PlaybackStateSnapshot snapshot) {}

  @override
  void onStopped() {}

  @override
  void dispose() {}
}

/// 歌詞自動比對。只認新的一次播放 —— 重試與啟動還原再配一次只是重複打來源。
class LyricsAutoMatchSideEffect implements PlaybackSideEffect {
  LyricsAutoMatchSideEffect(this._coordinator);

  final LyricsAutoMatchCoordinator _coordinator;

  @override
  void onTrackStarted(Track track, {required bool countsAsNewPlay}) {
    if (!countsAsNewPlay) return;
    _coordinator.onTrackStarted(track);
  }

  @override
  void onPlaybackStateChanged(PlaybackStateSnapshot snapshot) {}

  @override
  void onStopped() {}

  @override
  void dispose() => _coordinator.dispose();
}

/// 歌詞自動比對協作者。
///
/// 它有自己的 provider 而不是由 [playbackSideEffectsProvider] 現場 new，是因為
/// `AudioController` 還要拿同一個實例轉接 `onLyricsAutoMatchStateChanged`
/// —— 兩個實例的話 UI 的比對指示器會接到一個永遠不動的那個。放在這個檔案而不是
/// 協作者自己的檔案，是為了讓那個協作者維持成不認識 Riverpod 的純類別。
final lyricsAutoMatchCoordinatorProvider = Provider<LyricsAutoMatchCoordinator>(
  (ref) => LyricsAutoMatchCoordinator(
    // 明寫型別參數：`service` 的型別本身可為 null，推斷會把 T 收成非 null。
    service: readOptional<LyricsAutoMatchService?>(
      ref,
      optionalLyricsAutoMatchServiceProvider,
    ),
    settingsRepository: readOptional(ref, settingsRepositoryProvider),
  ),
);

/// 播放要通知的那一組消費者，註冊順序即通知順序。
///
/// 通知欄排第一：它是唯一一個使用者當場看得到的表面，另外兩個都是背景工作。
/// [PlaybackSideEffectRegistry.dispose] 反著走，於是系統媒體控制也就成了最後
/// 才交還的那一個 —— 任何一則還在飛的發佈都已經落地了才解綁。
///
/// `MixSessionCoordinator` **刻意不在這裡**：佇列最後一首播完時若 Mix 的
/// load-more 還在跑，完成事件要**等**它 —— 那是播放唯一一處等待副作用的地方
/// （`audio_controller_mix_boundary_test.dart` 守著），而這個 registry 吞掉每個
/// 失敗、也不給消費者被等待的方式。另外 Mix 被告知的是 `PlayMode` 而不是
/// track，`initialize()` 通知它時根本沒有 track。
final playbackSideEffectsProvider = Provider<PlaybackSideEffect>((ref) {
  return PlaybackSideEffectRegistry([
    NowPlayingSideEffect(ref.watch(nowPlayingPublisherProvider)),
    PlayHistorySideEffect(
      PlayHistoryRecorder(
        repository: readOptional(ref, playHistoryRepositoryProvider),
        settingsRepository: readOptional(ref, settingsRepositoryProvider),
      ),
    ),
    LyricsAutoMatchSideEffect(ref.watch(lyricsAutoMatchCoordinatorProvider)),
  ]);
});

/// 資料庫還沒開的時候這些 provider 會拋 `StateError`。拿它的每一處（這個檔案
/// 裡的協作者，與 `AudioController` 自己的兩個可缺席協作者）都把 null 當成
/// 「這件事整個靜默略過」，所以這裡吞掉例外而不是讓播放器建不起來。
///
/// 吞的是所有例外而不只 `StateError`：Riverpod 3 把 provider 建構時拋出的例外
/// 包成 `ProviderException` 再丟出來（3.0 migration guide），而依賴鏈上游先
/// 壞掉時包的層數不只一層；只接 `StateError` 會讓兩個協作者一起建不起來。真
/// 正的建構錯誤因此會變成「這個協作者不存在」，播放照走 —— 這是已知的代價，
/// 不是疏漏。
///
/// 用 `read` 不是 `watch`：拋出來的那一次若留下訂閱，資料庫就緒時會重建整組
/// 消費者，而 `AudioController` 手上握著的還是舊的那一組。`AudioController`
/// 對它的協作者是同樣的取捨，理由寫在它的 `build()` 上。
T? readOptional<T>(Ref ref, ProviderListenable<T> provider) {
  try {
    return ref.read(provider);
  } catch (_) {
    return null;
  }
}
