import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';
import 'package:fmp/data/database/repository_providers.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_service.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/mix_playlist_types.dart';
import 'package:fmp/services/audio/now_playing_publisher.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/lyrics/lyrics_auto_match_service.dart';
import 'package:fmp/services/network/connectivity_service.dart';

/// `AudioController` 以前用一個十個具名參數的建構子接收協作者；`Notifier.new`
/// 不吃參數，所以它們全部改由 `build()` 從 `ref` 取。
///
/// 這個 helper 把同一組參數翻譯成 provider override，讓測試維持一行一個
/// 協作者的寫法。沒有傳的協作者**刻意不覆寫**：它們的 provider 需要資料庫，
/// 在測試容器裡會拋，而 `build()` 對這四個可缺席的協作者本來就會吞掉例外並
/// 當成 null —— 與舊建構子的預設值相同。
AudioController buildTestAudioController({
  required FmpAudioService audioService,
  required QueueManager queueManager,
  required AudioStreamManager audioStreamManager,
  required NowPlayingPublisher nowPlayingPublisher,
  ToastService? toastService,
  SettingsRepository? settingsRepository,
  QueuePersistenceManager? queuePersistenceManager,
  LyricsAutoMatchService? lyricsAutoMatchService,
  MixTracksFetcher? mixTracksFetcher,
  PlaybackTimeoutBudget budget = const PlaybackTimeoutBudget(),
}) => buildTestAudioControllerIn(
  audioService: audioService,
  queueManager: queueManager,
  audioStreamManager: audioStreamManager,
  nowPlayingPublisher: nowPlayingPublisher,
  toastService: toastService,
  settingsRepository: settingsRepository,
  queuePersistenceManager: queuePersistenceManager,
  lyricsAutoMatchService: lyricsAutoMatchService,
  mixTracksFetcher: mixTracksFetcher,
  budget: budget,
).controller;

/// 需要拿到 container 時用這個 —— 例如要在同一個容器裡讀 `queueStateProvider`。
({AudioController controller, ProviderContainer container})
buildTestAudioControllerIn({
  required FmpAudioService audioService,
  required QueueManager queueManager,
  required AudioStreamManager audioStreamManager,
  required NowPlayingPublisher nowPlayingPublisher,
  ToastService? toastService,
  SettingsRepository? settingsRepository,
  QueuePersistenceManager? queuePersistenceManager,
  LyricsAutoMatchService? lyricsAutoMatchService,
  MixTracksFetcher? mixTracksFetcher,
  PlaybackTimeoutBudget budget = const PlaybackTimeoutBudget(),
}) {
  final overrides = <Override>[
    audioServiceProvider.overrideWith((ref) => audioService),
    queueManagerProvider.overrideWith((ref) => queueManager),
    audioStreamManagerProvider.overrideWith((ref) => audioStreamManager),
    nowPlayingPublisherProvider.overrideWithValue(nowPlayingPublisher),
    toastServiceProvider.overrideWith((ref) => toastService ?? ToastService()),
    mixTracksFetcherProvider.overrideWith((ref) => mixTracksFetcher),
    // 真的那個會做 DNS 查詢並開一個輪詢計時器。
    connectivityProvider.overrideWith(_SilentConnectivityNotifier.new),
    audioControllerProvider.overrideWith(() => AudioController(budget: budget)),
  ];
  if (settingsRepository != null) {
    overrides.add(
      settingsRepositoryProvider.overrideWith((ref) => settingsRepository),
    );
  }
  if (queuePersistenceManager != null) {
    overrides.add(
      queuePersistenceManagerProvider.overrideWith(
        (ref) => queuePersistenceManager,
      ),
    );
  }
  // 一律覆寫（可能是 null）：不覆寫的話它會去建整條歌詞／設定鏈，那條鏈碰
  // secure storage，在測試環境沒有實作。
  overrides.add(
    optionalLyricsAutoMatchServiceProvider.overrideWith(
      (ref) => lyricsAutoMatchService,
    ),
  );

  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  return (
    controller: container.read(audioControllerProvider.notifier),
    container: container,
  );
}

class _SilentConnectivityNotifier extends ConnectivityNotifier {
  @override
  ConnectivityState build() => ConnectivityState.initial;
}
