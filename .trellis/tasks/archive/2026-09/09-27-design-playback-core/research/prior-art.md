# 成熟 Flutter 播放器的播放核心（prior art）

- 查證日期：2026-09-28
- 查證方式：`git clone --depth 1` 各 repo，逐檔讀原始碼。**沒有跑他們的 App、沒有跑他們的測試、沒有打任何 API。**
- Permalink 一律固定到 clone 當下的 commit SHA（`--depth 1` 的 HEAD），行號範圍以該 SHA 為準。
- 選樣：Namida（本地優先、功能最廣的同類 App）、Finamp（Jellyfin 客戶端，audio_service 標準路線）、Spotube（與本專案最像 —— 平台服務商串流）、Harmonoid（老牌、桌面優先）。
- 問題集對齊 `current-state.md`：佇列與狀態建模、臨時／插播、隨機、無限／電台、預取與 gapless、錯誤跳過策略、系統媒體控制、每平台後端、直播處理。

---

## 1. Finamp

- repo：<https://github.com/finamp-app/finamp>
- commit：`0aae9d5ed530ffdf3d62ab12dab4f475a67687dc`（2026-09-26，merge #1709）
- 定位：Jellyfin 音樂客戶端；Flutter/Dart（SDK ^3.9），flutter_riverpod 2.6 ＋ rxdart BehaviorSubject ＋ get_it DI，持久化 hive_ce / isar。

### a. 佇列與播放狀態建模

- 走 **audio_service 的 `AudioHandler`**：單一類別 `MusicPlayerBackgroundTask extends BaseAudioHandler with SeekHandler, QueueHandler`，直接持有 just_audio `AudioPlayer`，全 app 一個實例。
  [music_player_background_task.dart#L129](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L129)、[#L381](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L381)
- **不是單一 controller，是兩層**：`MusicPlayerBackgroundTask`（transport、媒體通知、fade、音量、media browser）＋ `QueueService`（自持佇列語意模型，經 get_it 取 handler）。
  [queue_service.dart#L38](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L38)
- **沒有 enum 狀態機**。狀態就是 audio_service 的 `PlaybackState`（`idle/loading/buffering/ready/completed` ＋ `playing`），由 just_audio `ProcessingState` 一對一映射。
  [music_player_background_task.dart#L1285-L1320](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L1285-L1320)
- 佇列是**四段式**而非單一 list：`_queuePreviousTracks` / `_currentTrack` / `_queueNextUp` / `_queue`；對外快照 `FinampQueueInfo(previousTracks, currentTrack, nextUp, queue)`，每項帶 `QueueItemQueueType`。
  [queue_service.dart#L55-L60](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L55-L60)、[finamp_models.dart#L2431](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/models/finamp_models.dart#L2431)
- **關鍵設計 —— 雙真值 ＋ 單向反推**：just_audio 的 AudioSource 清單與四段 list 並存，靠 `_buildQueueFromNativePlayerQueue()` 從 `sequenceState.effectiveSequence` 反推內部四段；原始碼自承是 just_audio 限制下的產物。
  [queue_service.dart#L185-L285](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L185-L285)、[#L540-L541](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L540-L541)
- 上限 `maxQueueItems` 1500（iOS/macOS）/ 5000（存檔）；`maxInitialQueueItems = 1000` 有定義但**無呼叫點**。
  [queue_service.dart#L101-L107](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L101-L107)

### b. 臨時播放／插播

- 三個入口，都收 `PlayableSlice`：
  - `addToQueue` — append 到佇列尾。[#L932](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L932)
  - `addNext`（Play Next）— 插在當前曲之後，`insertFinampQueueItems(currentIndex + 1, …)`，type = nextUp。[#L967-L1001](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L967-L1001)
  - `addToNextUp` — 插到整個 Next Up 區塊尾（offset = `_queueNextUp.length + 1`）。[#L1003-L1039](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L1003-L1039)
- 索引換算靠 `getActualIndexByLinearIndex()`：把 shuffle 後的邏輯索引轉回 AudioSource 線性索引。[#L1393](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L1393)
- **Next Up 是一次性區塊**：播過之後在反推時被改標成 `formerNextUp` 併入一般 queue。
  [#L203-L250](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L203-L250)
- 沒有「臨時播放」概念（不存在離開佇列播一首再回來的模式）；點歌一律進佇列。

### c. 隨機（shuffle）

- 是**索引排列**，不是打散來源清單：用 just_audio fork 的 `_player.shuffleIndices`。[#L162](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L162)
- 以 `ShuffleOrder` 抽象注入：`NextUpShuffleOrder extends ShuffleOrder`，經 `setAudioSources(shuffleOrder: _shuffleOrder)` 傳入。
  [queue_service.dart#L1526](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L1526)、[#L828-L834](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L828-L834)
- 巧思：`shuffle()` 先全體洗牌，再把 current ＋ 整個 Next Up 區塊抽出移到最前，**保證插播曲仍緊接當前曲**；`insert()` / `removeRange()` 被覆寫成維護索引偏移。
  [#L1535-L1600](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L1535-L1600)、[#L1602-L1675](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L1602-L1675)
- 佇列重建分兩種語意：`SliceShuffleState.preShuffled`（自己先洗，順序送播放器）vs `playerShuffled`（交給播放器洗）。[music_slices.dart#L193](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/models/music_slices.dart#L193)

### d. 無限／自動電台

- 有，功能名 "radio"，五種 `RadioMode`：reshuffle / random / similar / continuous / albumMix。[finamp_models.dart#L3791](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/models/finamp_models.dart#L3791)
- 補歌觸發**不是單一定時器**，而是三來源齊發：(1) 每 10 秒 periodic timer、(2) queue stream 每次變動、(3) radioEnabled / radioMode / isOffline / currentUser provider 變動 → 全部呼叫 `maybeAddRadioTracks()`。
  [queue_service.dart#L148-L172](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L148-L172)
- 需求量 `calculateRadioTracksNeeded() = max(10, bufferDuration/2 分鐘) − 未播曲數`。[radio_service_helper.dart#L32-L46](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/radio_service_helper.dart#L32-L46)
- 補歌方式是 `addToQueue(...)` → **append 到尾巴**（非插入）。[#L128-L150](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/radio_service_helper.dart#L128-L150)
- similar / continuous 走 Jellyfin server 端 `/Items/{id}/InstantMix`；continuous 逐首以「上一首」為 seed 迴圈抓，模擬真連續。[#L780-L855](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/radio_service_helper.dart#L780-L855)、[#L514-L550](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/radio_service_helper.dart#L514-L550)
- 防競態：`_radioCacheStateStream` 帶 generating/queueing 旗標 ＋ BehaviorSubject identity 檢查，另有 20 秒內最多 4 次的 rate limit。[#L47-L52](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/radio_service_helper.dart#L47-L52)、[#L67-L80](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/radio_service_helper.dart#L67-L80)
- **佇列播完但 radio 開著時：只 pause ＋ 往回 seek 500ms**，避免觸發 queue-complete 造成整串重置。[music_player_background_task.dart#L790-L811](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L790-L811)

### e. 預取與無縫播放

- **沒有** `ConcatenatingAudioSource`；用 fork 過的扁平 `setAudioSources(list, preload:, shuffleOrder:)`。[#L546-L563](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L546-L563)
- gapless 靠 just_audio playlist 機制；桌面額外靠 `JustAudioMediaKit.prefetchPlaylist = true`（原始碼註解寫 "cache upcoming tracks, enable gapless playback"）；Android 另要求 `isGaplessSupportRequired: true` 的 offload 設定。
  [#L307](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L307)、[#L388](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L388)
- 緩衝用 `AudioLoadConfiguration`：`minBufferDuration` 90s、`bufferForPlaybackDuration` 5s、re-buffer 後 10s、設定值 `bufferDuration` 600s 作 maxBufferDuration。[#L324-L420](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L324-L420)
- **大型佇列不一次載完**：`PreCachedPlayableSlice`（cachedTracks 先播 ＋ `fetchTracks` future 後補）→ 先 `_replaceWholeQueue(cachedTracks)` 起播，再 `_insertFollowupItems()` 插剩餘曲；插入點有 clamp 保護。
  [music_slices.dart#L130](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/models/music_slices.dart#L130)、[queue_service.dart#L648-L704](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L648-L704)

### f. 錯誤跳過策略

- **幾乎沒有自動策略**：`AudioPlayer(maxSkipsOnError: 0)`，just_audio 語意為「整個 skip / pause-on-error 機制關閉」。[#L381-L382](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L381-L382)
- `errorStream` 只寫 log（severe），不重試、不跳過。[#L503-L505](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L503-L505)
- `setQueueItems` 只 catch `PlayerException` / `PlayerInterruptedException` → log ＋ `GlobalSnackbar.error`。[#L560-L578](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L560-L578)
- 離線保護：`isOffline == true` 且找不到已下載檔時直接 `Future.error`，避免誤連網。[#L1349-L1360](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L1349-L1360)
- **查不到**播放錯誤 UI、重試或自動跳過（grep `playbackError` / `playerError` / `retry` 全 `lib/` 無結果）。

### g. 系統媒體控制

- 用 **audio_service**（不是 `just_audio_background`）：`AudioService.init(...)`，Android channel `com.unicornsonlsd.finamp.audio`、`preloadArtwork: false`、`StubImageCache`。[main.dart#L430-L465](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/main.dart#L430-L465)
- Android / iOS / macOS 交給 audio_service 內建；Android Auto 另有 `AndroidAutoHelper` 覆寫 media browser 的 `getChildren` / `playFromMediaId` / `search`；iOS 有 `CarPlayHelper`。[#L981-L1130](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L981-L1130)
- **Windows 自寫平台實作**：`AudioServiceSMTC extends AudioServicePlatform` 換掉 audio_service 的 Windows 實作，用 `smtc_windows`（Rust/FRB），play/pause/next/prev/stop/ff/rew 全映射。[audio_service_smtc.dart#L5-L60](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/audio_service_smtc.dart#L5-L60)
- **Linux** 用 `audio_service_mpris` 的 federated plugin（`lib/` 內零引用，靠 pubspec 自動註冊）→ MPRIS。
- Discord Rich Presence 是獨立一份 `DiscordRpc`，與系統媒體控制無關。

### h. 每平台後端

- 後端**只有 just_audio 一套**，而且是 fork：`LennartEnns/just_audio_fork`（等 upstream PR #1555，加的就是 queue / `shuffleIndices` 能力）。[pubspec.yaml#L33-L39](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/pubspec.yaml#L33-L39)
- **沒有共同介面抽象層**：桌面不是換後端，是換 just_audio 的 *platform implementation* —— `just_audio_media_kit`（又是 fork，`Komodo5197/just_audio_media_kit` 的 `feat/queue-shuffle`）在 Windows/Linux 以 media_kit 為底；Windows 另換成自訂 media_kit fork。[pubspec.yaml#L40-L56](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/pubspec.yaml#L40-L56)
- 因此 `AudioPlayer` 的 API 是唯一切面，app 程式碼**完全不感知平台差異**（除設定項）。[music_player_background_task.dart#L381](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L381)
- 串流 URI：轉碼走 HLS `Audio/{id}/main.m3u8`，否則直連 `Items/{id}/File`；token 以 query param 帶。[#L1380-L1437](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/music_player_background_task.dart#L1380-L1437)

### i. 直播處理

- **沒有**。`isLive` 只存在於產生的 Jellyfin DTO，播放路徑零引用；`HlsAudioSource` 只剩一行被註解的可能用法。[jellyfin_models.dart#L1991](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/models/jellyfin_models.dart#L1991)
- §d 的電台是「無限自動播放清單」，與直播串流是兩件事。

### Finamp 最值得借鏡的三點

1. **雙真值反推**（[queue_service.dart#L185-L285](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L185-L285)）：不逃避「播放器有自己的清單」這個現實，而是指定**單一方向**（native → 內部模型）去同步，避免雙向寫入打架。
2. **NextUpShuffleOrder**（[#L1526](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/queue_service.dart#L1526)）：把「插播」的語意編進 shuffle 演算法，而不是事後補救 —— 直接解掉本專案 `addNext` 在隨機模式下失效的問題。
3. **PreCachedPlayableSlice**（[music_slices.dart#L130](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/models/music_slices.dart#L130)）：先播已快取的一段、其餘 lazy 補進播放器，是大佇列不必一次灌進播放器清單的作法。

---

## 2. Spotube

- repo：<https://github.com/KRTirtho/spotube>
- commit：`69a310c78f5ceaf4eab7dfee98f187d38211c9ba`（5.1.2+45，2026-06-05）
- 定位：Spotify 前端 ＋ 第三方音源（YouTube/Bilibili）；Flutter，Riverpod（Notifier ＋ freezed state），持久化 drift，後端 media_kit（作者 KRTirtho 也是 `smtc_windows` 作者）。
- 核心特色：**本機 shelf HTTP server 當串流代理**，media_kit 播 `http://host:port/stream/<trackId>`。
- **本節所有 `path:line` 都可用前綴 `https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/` 解析。**

### a. 佇列與播放狀態建模

- 單一 Riverpod `Notifier<AudioPlayerState>`（`lib/provider/audio_player/audio_player.dart:18`）。
- state 是 freezed class，**只有 6 欄**：`playing / loopMode / shuffled / collections / currentIndex / tracks`（`lib/provider/audio_player/state.dart:8-19`）。
- **佇列真相在 media_kit 的 `Playlist`**，不是 Dart 端 list；state 只是投影。`build()` 訂閱 media_kit 的 playing/loopMode/shuffled/playlist 四條 stream 回寫 state（`audio_player.dart:104-182`）。
- 狀態機只是粗粒度列舉 `AudioPlaybackState {playing, paused, completed, buffering, stopped}`（`lib/services/audio_player/playback_state.dart:4-9`），由 `CustomPlayer` 把 media_kit 多條 stream 折成一條 `playerStateStream`（`lib/services/audio_player/custom_player.dart:11-49`）。
- `collections`＝「這條佇列來自哪個 album/playlist」的 id 清單，決定點歌時該 replace 還是 jump（`audio_player.dart:185-218`、`lib/components/track_presentation/use_track_tile_play_callback.dart:71-88`）。
- 佇列與 loop/shuffle 持久化在 drift 單列表（`lib/models/database/tables/audio_player_state.dart`）；啟動 `_syncSavedState()` 回填並 `openPlaylist(autoPlay: false)`（`audio_player.dart:38-91`）。
- 底層包一層 `AudioPlayerInterface`（getter ＋ command），早年的 just_audio 分支已全被註解（`lib/services/audio_player/audio_player.dart:44-126`、`audio_players_streams_mixin.dart` 整檔）。

### b. 臨時播放／插播

- `addTracksAtFirst`（語意＝插在當前曲後面）：對每首 `addTrackAt(SpotubeMedia(track), max(currentIndex,0) + i + 1)`（`audio_player.dart:220-257`）；使用者入口是 track options 的 `PlayNext`（`lib/provider/track_options/track_options_provider.dart:166-167`）。
- 底層 `addTrackAt` → `_mkPlayer.insert(index, media)`（`lib/services/audio_player/audio_player_impl.dart:107-109`）。
- **關鍵坑**：`CustomPlayer.insert` 不用 media_kit 的 `insert`，而是 `add()` 後等 playlist stream 確認新元素 index、再 `move()` 到位（`custom_player.dart:123-141`）；pubspec 註解說明原因是上游 `.move()` after `.add()` 不回應（`pubspec.yaml:148-152`）。
- 插播不進 `collections`，所以不影響「播放來源」判定。

### c. 隨機

- 完全交給 media_kit（`setShuffle` → `_mkPlayer.setShuffle`，`audio_player_impl.dart:123-125`；讀值 `_mkPlayer.state.shuffle`，`custom_player.dart:85`）；**沒有自製順序表**。
- next/previous/loop 的邊界直接讀 `_mkPlayer.state.playlist.index` 自己算（`audio_player_impl.dart:67-87`）。

### d. 無限／電台式佇列

- 有，做成 hook `useEndlessPlayback(ref)` 掛在 app 層（`lib/hooks/configurators/use_endless_playback.dart:9-65`）。
- 觸發：`currentIndexChangedStream` 的 index 等於 `tracks.length - 1`（進到最後一首）才呼叫 metadata plugin 的 `track.radio(track.id)`（`:20-42`）。
- 補法：`playback.addTracks(...)`，先 `removeWhere` 掉自己與已在佇列中的重複 id（`:31-38`）。是「**最後一首才補**」，不是滾動視窗預留。由偏好開關控制。

### e. 預取與 gapless

- **預取**：監聽 `positionStream`，進度超過 **80%** 且非最後一首時，先 `await ref.read(sourcedTrackProvider(nextTrack).future)` 把下一首 URL 解析完（`lib/provider/audio_player/audio_player_streams.dart:135-167`）；第一首載入時也先 boost 再 `openPlaylist`，避免 media_kit 因 timeout 跳過（`audio_player.dart:366-375`）。
- 伺服器端磁碟快取：GET 完成後把 `.part` rename 成正式快取檔（`lib/provider/server/routes/playback.dart:217-253`）。
- **gapless 沒有顯式設定**：`PlayerConfiguration` 只給 title/logLevel/async（`lib/services/audio_player/audio_player.dart:48-54`）；media_kit 本身沒有 gapless 屬性（查證 `media_kit` `native/player/real.dart` 只有 `playlist-next` / `eof-reached` / `loop-file`）。接續是 mpv internal playlist 行為，Spotube 只負責「URL 先備好」。
- buffer 依音質切（無損 6MB / 有損 4MB），寫 `demuxer-max-bytes`、`demuxer-max-back-bytes`（`lib/provider/metadata_plugin/audio_source/quality_presets.dart:49-51`、`custom_player.dart:151-157`）；網路 timeout 放寬到 120 秒（`custom_player.dart:24`）。

### f. 錯誤跳過／重試

- **player 層幾乎沒有策略**：錯誤只送 logger（`lib/services/audio_player/audio_player.dart:55-57`、`custom_player.dart:46-48`）；`subscribeToPlayerError` 是空 listener（`audio_player_streams.dart:169-171`）。沒有壞軌自動跳下一首（查不到）。
- **真正的重試在 shelf 代理層**：
  - `track.url == null` → 先 `swapWithNextSibling()` 換下一個候選音源（`lib/provider/server/routes/playback.dart:106-110`，GET 路徑同理 `:159-163`）。
  - HEAD 失敗 → catch 後 `refreshStreamingUrl()` 重解析改打新 URL（`:177-192`）。
  - `refreshStream` 逐一對候選 URL 發 HEAD，只留 status < 400，全掛才重新 `streams()`（`lib/services/sourced_track/sourced_track.dart:254-299`）；候選由 YouTube 搜尋結果評分排序（官方標記 ＋ 標題含曲名/藝人加權，`:105-152`）。
  - 換源會覆寫 DB 的 source match，下次直接命中（`:219-238`）。

### g. 系統媒體控制

- 統一入口 `AudioServices`，依平台建兩個實作（`lib/services/audio_services/audio_services.dart:12-46`）。
- Android / iOS / macOS / Linux：`audio_service` 的 `AudioService.init`（Linux 走 `audio_service_mpris`）；channel id 依 stable/nightly 分（`:24-35`）。`MobileAudioService extends BaseAudioHandler`（`lib/services/audio_services/mobile_audio_service.dart:14`）。
- Windows：`smtc_windows`（同作者）；`WindowsAudioService` 監聽 `buttonPressStream` 分派 play/pause/next/previous/stop，回寫 `setPlaybackStatus` / `setPosition` / `setEndTime` / `updateMetadata`（`lib/services/audio_services/windows_audio_service.dart:10-93`）。
- **音訊焦點**：`InterruptionEventStream`（duck→降到 0.5 音量；pause/unknown→暫停並記住以恢復）＋ `becomingNoisyEventStream`→pause（`mobile_audio_service.dart:22-61`）。

### h. 後端與直播

- **全平台同一套 media_kit**，不分 Android/桌面：`static const bool _mkSupportedPlatform = true;`（`lib/services/audio_player/audio_player.dart:61`）；依平台只差 `media_kit_libs_*_audio` 依賴（Linux 用 full libs，`pubspec.yaml:150-212`）。
- 專屬 patch 集中 `CustomPlayer`：Android 產生 audio session id、設 `ao=audiotrack,opensles`、廣播 `OPEN_AUDIO_EFFECT_CONTROL_SESSION`（`custom_player.dart:53-83`）。
- 共同介面切在 `AudioPlayerInterface` ＋ `SpotubeAudioPlayersStreams` mixin（`audio_player.dart:44-126`、`audio_players_streams_mixin.dart:3-150`）。
- 直播：GET 時若上游 `content-type` 是 HLS → 直接 **301 redirect** 讓播放端吃 m3u8（`playback.dart:194-207`）；metadata 層有 `isLive` 欄位但**播放端無任何特判**（查不到）。

---

## 3. Harmonoid

- repo：<https://github.com/harmonoid/harmonoid>
- commit：`2b021f7b0b5dbcbe027aec010580977a2939a28d`（0.3.34+9045，2026-09-03）
- 定位：本機音樂庫播放器（非線上串流），media_kit 原作者作品；Flutter，狀態管理是 **`ChangeNotifier` 單例 ＋ mixin registry**（不是 Riverpod/Bloc），持久化 drift。
- **本節所有 `path:line` 都可用前綴 `https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/` 解析。**

### a. 佇列與播放狀態建模

- `final class MediaPlayer extends ChangeNotifier`，`static final instance` 單例（`lib/core/media_player/media_player.dart:40,47`）。
- 單一 state 物件（freezed，18 欄），含 `index/playables/rate/pitch/volume/shuffle/loop/exclusiveAudio/replayGain/crossfadeDuration/position/duration/playing/buffering/completed/audioBitrate/audioParams/mixOffset`（`lib/core/media_player/models/media_player_state.dart:11-32`）。
- **佇列真相同樣在 media_kit `Playlist`**：`_player.stream.playlist` → `_applyPlayerPlaylistToState`（`media_player.dart:341, 496-525`）。值得借鏡的細節：用 `_comparePlayableListAndMediaList` 淺比較避免重建（`:527-533`）、重建走 `compute()` 丟 isolate（`:511`）、**只有 uri 換了才重置 position**（`:509, :513-524`）。
- 大量批次操作時用 `disablePlayerPlaylistUpdates()` / `enablePlayerPlaylistUpdates()` 把回寫關掉再開（`media_player.dart:480-494`）。
- playback 只持久化子集（去掉 position/duration/playing 等易變欄位，`lib/core/media_player/models/playback_state.dart:11-23`）；恢復時逐項重套，**`setShuffle` 必須在 `open` 之後**（`media_player.dart:301-338`）。
- **平台功能靠 8 個 mixin 由 registry 依平台註冊**（AudioService / AudioSession / DiscordRpc / HistoryPlaylist / LastFm / Mpris / SMTC / WindowsTaskbar，`lib/core/media_player/media_player_mixin_registry.dart:22-36`）；介面只有 4 個方法（`lib/core/media_player/mixin/media_player_mixin.dart:10-18`），且每次呼叫都包 `_runCatching` 吞例外（`media_player_mixin_registry.dart:61-68`）。

### b. 臨時播放／插播

- `insert(index, playable)`：`add()` 後 `move(playlist.medias.length - 1, index + 1)`（`media_player.dart:230-245`），呼叫端傳「當前 index」、函式內部 `+1`。
- 單曲 play next → `insert(_mediaPlayer.state.index, track)`（`lib/features/media_library/media_library_menus.dart:77-79`）。
- **多選 play next 用 `disablePlayerPlaylistUpdates()` 包住並反向逐首 insert**，才不會彼此插隊（`media_library_menus.dart:270-275`）；insert 後同步修正 `mixOffset`（`media_player.dart:240-244`）。
- 「add to now playing」是 `add()`（附尾），與插播分開（`media_library_menus.dart:81-83`）。

### c. 隨機

- **兩套並存**：(1) `setShuffle` 交 media_kit（內部重排 playlist）再回寫 state（`media_player.dart:124-126`）；(2) `open(..., shuffle: true)` 是 Dart 端先 `medias.shuffle()` 打亂再 open（`:158-160`），UI 的「隨機播放」走這條（`media_library_menus.dart:266-268`）。
- `open()` 時一律先 `copyWith(shuffle: false, ...)` 歸零，由呼叫端之後再設（`media_player.dart:169`）。
- 上/下一首可用性交給 extension `isFirst` / `isLast`（loop=all 時永遠 false，`lib/extensions/media_player_state.dart:11-15`），SMTC/MPRIS/工作列都吃這兩個值。

### d. 無限／電台式佇列

- 有，叫 **Mix**，補法與電台不同：**在 `open()` 當下就把整個媒體庫打亂接在後面**，不是等播到最後才抓推薦。
- `open()`：若 `nowPlayingStartMixAfterEnding` 且曲數 < `kMixThreshold`(=100) → `mixOffset = medias.length`，再把整個媒體庫轉 Media 後 `shuffle()` 追加（`media_player.dart:44, 162-167`）。
- `mixOffset` 是「使用者的歌到哪為止」的分界，move/remove/add/insert 都要維護它（`media_player.dart:179-203` 等）。
- 開關 `setMix` / `mixOrUnmix`，關閉時把 playlist 裁回 `sublist(0, mixOffset)`；`_mixLock` 防重入（`:128-146`）。**預設 true**（`lib/core/configuration/configuration.g.dart:463`）。

### e. 預取與 gapless

- **沒有 prefetch 實作**（全庫 grep `prefetch` / `preload` / `demuxer` 只命中 drift 產物）。
- gapless：`PlayerConfiguration` 只有 `title` 與 `pitch`（`media_player.dart:428-433`）；同樣靠 mpv internal playlist（**推測**與 Spotube 同機制）。有為接續鋪路的設定：非 iOS 設 `audio-stream-silence=yes`（註解說為了讓 crossfade 順，`:457-461`）、Android `ao=audiotrack,opensles`、iOS `audiounit`、macOS `coreaudio`（`:443-456`）。
- **Crossfade 是自製 platform player**：把 media_kit 的 `platformPlayer` 換成 `CrossfadePlayer`（雙播放器交叉淡入），預設 5 秒、範圍 2–30 秒（`media_player.dart:41-43, 415-425, 284-299`）；與獨佔音訊互斥（`:247-270, :284-292`）；切換開關會**整個 dispose ＋ 重建 Player**（`:395-468`）。
  - **查不到**：`CrossfadePlayer` 原始碼在 `lib/private` **submodule（`github.com/harmonoid/private`，私有 repo）**，本次未取得。
- buffer 無顯式設定（`kKeyMpvOptions` 預設空 map，使用者可自行加 mpv 參數，`configuration.g.dart:458`）。

### f. 錯誤跳過／重試

- **沒有策略**：`_player.stream.error.listen` 只 `debugPrint`，原本的 `mediaPlayerOnError(e)` 被**註解掉**（`media_player.dart:353-356`）；`completed` 只寫進 state 不觸發補救（`:350`）。
- 唯一韌性是 registry 的 `_runCatching`，把 8 個 mixin 的例外吞掉，避免單一平台整合炸掉播放（`media_player_mixin_registry.dart:61-68`）。

### g. 系統媒體控制

- 靠 mixin registry 分派，每個平台一個 mixin、各自 `supported` getter：
  - Android / iOS / macOS：`audio_service`（`lib/core/media_player/mixin/audio_service_mixin.dart:21-49`）；`_AudioServiceImpl extends BaseAudioHandler with QueueHandler, SeekHandler`（`:196`）；`skipToQueueItem` → `jump(i)`（`:241`）。
  - Windows SMTC：`system_media_transport_controls` 套件，`supported => Platform.isWindows`（`system_media_transport_controls_mixin.dart:20-93`）；套件本身來自自家 submodule（`pubspec.yaml:103-104`）。
  - Linux：`mpris_service`（`mpris_mixin.dart:22-70`）。Windows 工作列縮圖按鈕另用 `windows_taskbar`（`:19-86`）。
  - 加碼：Discord RPC、Last.fm scrobble、history playlist。
- **值得借的去重模式**：每個 mixin 持一組 `_flag*` 欄位，只在值真的變了才推更新（position 容差 1 秒），並用 `Lock` 序列化（`audio_service_mixin.dart:70-175`、`mpris_mixin.dart:90-153`）。
- 音訊焦點：`audio_session` mixin **只註冊 Android/iOS**（macOS 沒有，`audio_session_mixin.dart:19-48`）；中斷恢復較粗暴（begin→pause、end→play，無 duck）。`play()`/`pause()` 另外手動 `setActive`，註解說明為何不在 `notifyState` 做（iOS index 切換時會炸，`audio_session_mixin.dart:60-69`）。

### h. 後端與直播

- 後端同樣 media_kit，釘在 git ref `c533e446755f51cf53c7e57aea873f2aa5355f81`（`pubspec.yaml:54-84`）；平台只差 libs（Linux 用 full）。
- Android 與桌面**同一套 Player API**，差異只在建立時的 `platformPlayer` / `configuration` 與 `ao` 屬性（`media_player.dart:411-434, 443-456`）。共同介面切成三層：`MediaPlayer`（facade）＋ `MediaPlayerMixin`（平台整合）＋ `Playable`（模型）。
- **直播沒有處理**：無 `isLive`、無 duration==0 特判、無 HLS/續傳邏輯（查不到）；HTTP URI 甚至被標為未完成（`history_playlist_mixin.dart:44` 的 `// TODO: Add support for HTTP URIs`）。mpv 本身能播，但 App 層不管。

---

## 4. Namida

- repo：<https://github.com/namidaco/namida>
- commit：`e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5`（2026-09-26）
- 定位：Flutter 音樂播放器（Android / Windows / Linux / iOS / macOS），多來源（YouTube、Bilibili、本地檔、Jellyfin）。狀態管理是作者自製的 **nampack**（類 GetX 的 `.obs` / `Rx<T>` / `Obx`），不是 riverpod / bloc。
- **證據限制（重要）**：播放引擎的基底類別 `BasicAudioHandler` 來自套件 `basic_audio_handler`，**該 repo 不公開**（`gh api repos/namidaco/basic_audio_handler` → 404，本次獨立複核確認）。因此 shuffle 演算法、gapless 機制、`CustomAudioPlayer`、`PlayerRepeatMode` 的定義**查不到原始碼**，只能由 namida 端呼叫點推論 —— 這些地方在本節標「推測」。
- **本節所有 `path:line` 都可用前綴 `https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/` 解析。**

### a. 佇列與播放狀態建模

- 三層 facade：`Player`（單例）→ `NamidaAudioVideoHandler<Q extends Playable> extends BasicAudioHandler<Q>`（真正的引擎，[audio_handler.dart#L69](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/base/audio_handler.dart#L69)）→ `AVPlayer` 後端。
- **沒有自寫狀態機**；就是 just_audio 的 `ProcessingState`（idle/loading/buffering/ready/completed），mpv 後端把 mpv 狀態映射進同一組枚舉（`lib/class/custom_mpv_player.dart:73, :210`）。
- 佇列模型：持久化的 `Queue`（`lib/class/queue.dart`）；記憶體播放清單由套件內 `BasicAudioHandler.currentQueue` 持有（推測為 `Rx<List<Playable>>`）。
- **多個 controller 分工**：`QueueController.inst`（持久化佇列，`lib/controller/queue_controller.dart:32`，`Rx<SplayTreeMap<int, Queue>>`）、`Player.inst`（facade，`lib/controller/player_controller.dart`）、`SMTCController.instance`、`ArtworkPrefetcher.inst`；彼此靠 nampack 的 Rx 監聽串接（`audio_handler.dart` constructor，[#L106-L213](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/base/audio_handler.dart#L106-L213)）。

### b. 臨時播放／插播

- 臨時播放叫 **`gentlePlay`**：「插到下一首再跳過去」，**不取代佇列但會改佇列內容** —— 兩行 `await addToQueue(queue, insertNext: true, showSnackBar: false); await next();`，doc 註解寫「add items next and play them instead of assigning them as a new queue」（[player_controller.dart#L815-L832](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/player_controller.dart#L815-L832)）。
- play-next 家族：`insertNext` / `insertAfterLatest` ＋ `latestInsertedIndex`（`:155`）、`moveToNext`（`:563`）、`moveToAfterLatestInserted`（`:569`）、`moveToLast`。
- `addToQueue(...)`（`:494-551`）把「往哪插」與「插什麼」都參數化（`QueueInsertionType` / `insertNext` / `insertAfterLatest` / `withLimit(maxCount)`）。
- `createTempPlayer(...)`（`:987`）另建一個一次性 player。

### c. 隨機

- **是索引排列，不是打散原清單**，且分兩層：
  1. `settings.player.shuffleQueue` → 實體置換佇列順序，原順序另存 `originalIndices`（`originalIndices[i]` ＝ 排在第 i 位者在原始清單的索引）；**排列寫進持久化二進位檔**（`_QueueSerializer` 有 `_kFlagOriginalIndices` / `_kOriginalIndex = 'o'`）。
     [queue_controller.dart#L167-L168](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/queue_controller.dart#L167-L168)、[\#L406-L411](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/queue_controller.dart#L406-L411)
  2. `PlayerRepeatMode.shuffle` / `allShuffle`（播放順序，**查不到**定義）。
- UI 入口 `Player.shuffleTracks(bool allTracks)`（`player_controller.dart:478-486`）。

### d. 無限／電台式佇列

- **沒有真正的自動無限補歌**。最接近的兩件：
  1. YouTube 自動電台 `tryAddingMixPlaylist(videoId)`，條件是 `settings.youtube.autoStartRadio` **且 `currentQueue.length == 1`** → 只在「單曲起播」時自動補一次，抓 mix playlist 後 `addToQueue`（[audio_handler.dart#L1815-L1845](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/base/audio_handler.dart#L1815-L1845)）。
  2. `infiniyQueueOnNextPrevious`（預設 true）只在佇列頭尾 wrap，**不補歌**。
- 「加同類曲」是**使用者觸發**（`QueueInsertionType` ＋ generators，`lib/base/generator_base.dart`、`lib/controller/generators_controller.dart`）。

### e. 預取與 gapless

- **音訊沒有做下一首預取**；唯一的 prefetch 是封面 `ArtworkPrefetcher.inst.prefetchAround(newIndex)`，掛在 `onIndexChanged`（`audio_handler.dart:627-644`）。
- 有「預先備妥下一首」的 hook `prepareItem(...) → ItemPrepareConfig`（`audio_handler.dart:860`）；**推測**基底會在當前曲播放中先 prepare 下一首，但呼叫時機在套件內、無法查證。
- **gapless 預設 false**（`enableGaplessPlayback`，`settings.player.dart:28`）；且 `InternalPlayerType.getInfoForAndroid()`（`lib/core/enums.dart:1067`）載明 **Android 的 mpv 後端缺 gapless** → gapless 由 exoplayer（just_audio）路線提供。crossfade 另計（`enableCrossFade` 等，`settings.player.dart:29-31`）。
- 串流用 `http_cache_stream` 的 lock-caching；另有「下一首 seek 時換成新抓好的快取檔」機制（`audio_handler.dart:1388-1444, 2982-2997`）。

### f. 錯誤跳過策略（四者中最完整的）

- 判斷是否真失敗，再 **7 秒倒數**（`playErrorRemainingSecondsToSkip = 7`）才 `skipItem()`，且要 `currentQueue.length > 1` 才跳，同時彈錯誤框；本地檔只在「誤判」分支重試一次（[audio_handler.dart#L1064-L1108](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/base/audio_handler.dart#L1064-L1108)）。
- YouTube 串流過期 → catch 後重抓一次 streams 再 `setVideoLockCache(sameStream, positionToRestore)`（`:1278-1299`）；完全失敗則退回快取，無快取就 `skipItem()`（`:2086-2132`）；無效 video id 直接跳（`:1851-1880`）；mpv 開啟失敗 3 秒後重試一次（`lib/class/custom_mpv_player.dart:337-347`）。

### g. 系統媒體控制

- **Android 通知 ＝ `audio_service`**（`AudioService.init`，channel `com.msob7y.namida`、`androidStopForegroundOnPause: false`；[player_controller.dart#L219-L310](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/player_controller.dart#L219-L310)）；非 Android/iOS 只建純 handler、不進 media session。`_MediaSessionAudioHandler extends CompositeAudioHandler`（`:1159-1198`）。
- **桌面**：`SMTCController.instance` → `NamidaSMTCManager.platform()`（Windows → `smtc_windows`、Linux → `anni_mpris_service`、android/ios → null）。
- 更新觸發：`refreshNotification` → `mediaItem.add` ＋ `playbackState.add`，再 `_refreshPlatformStatusDependers` → SMTC / home widget / Windows taskbar / tray（`audio_handler.dart:349-453`）。

### h. 後端

- 共同介面是 **`AVPlayer`**（抽象類別，來自 `basic_audio_handler`，**原始碼查不到**），**兩套實作**：
  1. `CustomMPVPlayer implements AVPlayer` —— namida 自寫，基於 **media_kit（mpv）**（[custom_mpv_player.dart#L14](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/class/custom_mpv_player.dart#L14)），桌面路線。
  2. `CustomAudioPlayer`（套件內，包作者 fork 的 just_audio）—— Android / iOS 路線。
- 工廠 `NamidaAudioVideoHandler.createPlayer` switch `InternalPlayerType { auto, exoplayer, exoplayer_sw, mpv }`（[audio_handler.dart#L2822-L2838](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/base/audio_handler.dart#L2822-L2838)）；`platformDefault` ＝ Android/iOS `exoplayer`、Windows/macOS/Linux `mpv`。
- 切法不是「按平台分兩份」，而是**同一介面 ＋ 使用者可切換的後端 enum**（Android 上 mpv 是實驗選項）。`_createAndroidPlayer` 建 `AudioPlayer(handleInterruptions: false, androidApplyAudioAttributes: false, audioPipeline: AudioPipeline(androidAudioEffects: [equalizer, loudnessEnhancer]))`（`:2847-2865`）。

### i. 直播處理（四者中唯一有實作的）

- `_resolveYTNetworkSources`（[audio_handler.dart#L1575-L1599](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/base/audio_handler.dart#L1575-L1599)）：`isLive == true` 時優先 `HlsSource(hlsManifestUrl)`，否則 `DashSource(dashManifestUrl)`；原始碼註解說明 live 結束後 fallback 回一般 mixed streams。
- mpv 端 live 判斷：`_checkIsSourceLive(source) => source is HlsSource || source is DashSource`（`custom_mpv_player.dart:349`）。
- live 的 duration / seek / 續播處理多數在套件內（**查不到**）。

---

## 5. 跨專案對照

| 面向 | Finamp | Spotube | Harmonoid | Namida |
|---|---|---|---|---|
| 後端（Android / 桌面） | just_audio fork（桌面換 platform impl 成 media_kit） | media_kit 全平台 | media_kit 全平台 | just_audio fork / media_kit（**同一介面 + 可切換 enum**） |
| 共同介面 | 無抽象層，只有 `AudioPlayer` API | `AudioPlayerInterface` ＋ streams mixin | `MediaPlayer` facade ＋ `MediaPlayerMixin` ＋ `Playable` | `AVPlayer`（套件內，**不公開**） |
| 狀態建模 | audio_service `PlaybackState`；**無自寫狀態機** | 粗粒度 5 態列舉，由 `CustomPlayer` 折疊 | 18 欄 state ＋ mixin registry | just_audio `ProcessingState` 直用 |
| 佇列真相 | 四段 list ＋ **反向同步** native 清單 | media_kit `Playlist`，Dart 只投影 | media_kit `Playlist`（淺比較 + isolate 重建） | 套件 `currentQueue` ＋ 自持久化 `Queue` |
| 臨時／插播 | `addNext` / `addToNextUp`（無臨時播放） | `addTracksAtFirst` → add+move | `insert` → add+move | `gentlePlay` ＝ insert-next ＋ next |
| 隨機 | 索引排列 ＋ `NextUpShuffleOrder` | 交給 media_kit | 交給 media_kit ＋ Dart 端先洗 | 索引排列 ＋ `originalIndices` **持久化** |
| 無限佇列 | 伺服器 InstantMix，10 秒 ＋ 事件驅動補 | 到最後一首才抓 radio 逐批補 | `open()` 當下把全庫洗進佇列 | **無**（僅 YouTube 單曲起播時補一次） |
| 預取 | 有（slice lazy 補） | 進度 80% 先解析下一首 URL | **無** | **無**（只預取封面） |
| gapless | just_audio playlist ＋ 桌面 `prefetchPlaylist` | 無顯式設定（靠 mpv） | 無顯式設定（靠 mpv） | 預設 **關**；Android mpv 不支援 |
| 錯誤跳過 | **幾乎沒有**（`maxSkipsOnError: 0`） | player 層沒有，重試全在 HTTP 代理層 | **沒有**（處理整段被註解掉） | **7 秒倒數後跳**，重試一次 |
| 系統媒體控制 | audio_service ＋ 自寫 AudioServiceSMTC ＋ MPRIS plugin | audio_service ＋ smtc_windows | audio_service ＋ 自家 SMTC ＋ mpris_service | audio_service ＋ smtc_windows ＋ anni_mpris_service |
| 直播 | **無** | 只做 m3u8 301 redirect | **無** | **有**（HLS/DASH source，isLive 分支） |

### 對本專案（FMP）的意涵

1. **「一個介面、兩後端」在四者中只有 Namida 真的做**（`AVPlayer` ＋ 可切換 enum），而且它的介面原始碼還不公開 —— FMP 現有的 `FmpAudioService` 抽象 ＋ dartdoc 記錄不可收斂差異，是這批專案裡最完整的一種。重寫時值得原樣保留這個形狀（見 `current-state.md` §5）。
2. **佇列真相的兩種路線**：Finamp 明講「native 清單是唯一真相、單向反推」；Spotube/Harmonoid 則是「native `Playlist` 是真相、Dart 只投影」。兩者都**不試圖維持 Dart 端獨立真相**——本專案 `QueueManager` 是獨立真相（含 shuffle 排列、Mix、persist），這是重寫時最需要重新決定的一點。
3. **插播在 shuffle 下會壞，是共通坑**：Finamp 用 `NextUpShuffleOrder`、Harmonoid 用「反向 insert ＋ 關閉回寫」、Spotube 用 `add+move`。本專案 `addNext` 把新索引插到隨機位置（`current-state.md` §3）正是同一類問題，且四者都給了可直接抄的解法。
4. **媒體 `.add()` 後 `.move()` 回寫不即時**：Spotube 與 Harmonoid 都踩到（前者改用 git 版 media_kit、後者用 `playlist.medias.length - 1` 繞開）。FMP 若在桌面後端做插入，要注意同一處。
5. **錯誤跳過只有 Namida 有產品化設計**（7 秒倒數 ＋ 佇列長度 > 1 才跳）。本專案現在的「300ms 後跳下一首」比它激進，且 Mix 模式因條件寫死而完全不跳 —— 若要對齊已定的 D3，Namida 的「先給使用者看到再跳」是可參考的折衷。
6. **直播是差異化能力**：四者只有 Namida 有 isLive 分支（HLS/DASH），且它自己也不完整。FMP 的電台（Bilibili 直播）＋ `resolveStream` 的 live capability 屬於**沒有現成可抄**的部分，設計要自負。
7. **四者都沒有把「臨時播放」做成獨立的播放模式**（Finamp/Spotube/Harmonoid 都只是插播/加佇列；Namida 的 `gentlePlay` 最接近但會改佇列）。FMP 現有的 `PlayMode.temporary`（離開佇列播一首再還原）在開源同類中是少見設計 —— 與 audit §3.10 的觀察一致。

