# 02 — 播放核心與音源層審查

- **審查日期**：2026-08-30（第二輪實機驗證同日補做，見 §12.8–§12.12）
- **HEAD**：`b93f72c7`（工作樹只有上一輪的 `docs/review/01-...md` 已 staged，本輪未修改任何專案檔案）
- **範圍**：C（播放核心）＋ D（音源層與插件化）＋ issue #40 / #41 / #42
- **環境**：Flutter 3.47.1 / Dart 3.13.1 / Windows 11 主機；Android 模擬器 `Medium_Phone`（SDK 37, x86_64）debug build；Windows desktop debug build
- **本輪只做審查與規劃**，未改碼、未刪文檔、未動 git 歷史、未關 issue。

> 標記約定：**【事實】**＝有 `file:line`、指令輸出或實機 log 佐證；**【推論】**＝由事實推導；**【建議】**＝行動提案，附成本（S/M/L）、風險、可逆性；**【未驗證】**＝查不到或被阻塞。

---

## 目錄

1. [摘要](#摘要)
2. [現況：播放管線](#1-現況播放管線)
3. [現況：音源層](#2-現況音源層)
4. [四個症狀的根因定位](#3-四個症狀的根因定位)
5. [問題清單 P0–P3](#4-問題清單-p0p3)
6. [成熟做法對照](#5-成熟做法對照)
7. [建議方案與目標架構](#6-建議方案與目標架構)
8. [插件化可行性研究](#7-插件化可行性研究)
9. [重寫 vs 漸進重構](#8-重寫-vs-漸進重構)
10. [需要你決策的點](#9-需要你決策的點)
11. [Quick wins](#10-quick-wins)
12. [issue #40 / #41 / #42 的裁決](#11-issue-40--41--42-的裁決)
13. [驗證記錄](#12-驗證記錄)
14. [附錄：本輪未完成的部分](#附錄本輪未完成的部分)

---

## 摘要

> **第二輪補做的實機驗證改寫了其中兩條，並新增一條 P0**（摘要已按最新證據更新；被推翻的舊歸因保留在 §3.a 並標明）。
> **第三輪**（使用者暫停手邊工作後）在 Windows 上完成 #40 的兩個症狀，並發現「兩個無法作用的控制項」其實是**四個**（next/prev、seek、shuffle、repeat）；同時推翻了 #40 症狀二的機制推論 —— `IsPlaybackPositionEnabled` 本來就是 `False`。見 §11 的 #40 段與 §12.13。
> **第五輪**把附錄剩下的五項全部做完：P1-8 的 preflight 量到了（零 redirect 仍要 186ms，且整套被 https scheme 閘控）、#41 根因定位（mpv 的 `Could not open/initialize audio device` 撞上 `'could not open'` 關鍵字）、AOT 對照（結論是 AOT 下**沒有任何觀測手段**，並更正上一輪的錯誤說法）、`flutter_js` 插件原型**實際跑通**（並推翻 §7.2 兩條假設）、以及 `AudioController` 拆分的六個具體介面（§8.1）。
> **第八輪**做完剩下三項，其中兩項是**實際改碼**（範圍由你選定）：#41 用「把 mpv 的 `ao` 設成不存在的驅動」完整實機重現並修好（歌曲不再背鍋）；AOT 觀測手段的結論**被推翻** —— `Flutter.Frame`、`getVMTimeline`、`dart:io` HTTP profiling 在 profile build 下全部可用，據此量到 debug 對 UI build 的灌水是 **3.4–4.6 倍**；`PlaybackEndReason`（§8.1A）與排行榜快取的註冊表化（§7.4 步驟 3）已落地並通過 1242 條測試 + 兩平台實機驗證。見 §12.20、§12.21。
> **第七輪**（使用者登入 Netease 後）把最後兩項做完：已登入的 eapi **同樣回 `http://`**，且實測生產路徑上 preflight 2ms 跳過、Cookie 被剝掉、真實簽名 URL **0 跳轉** —— P1-8 三個問號全部關閉，處置確定是「刪」。插件化的 Android 側也驗了：JS 行為與沙箱邊界跟 Windows **完全相同**，但 `flutter_js` 0.8.7 在 Android 上**開箱即壞**（Kotlin 1.7.20 + jvmTarget 1.8），是一筆維護債。同時**更正 §7.2**：Flutter 音樂 app 的插件化已經有人做完了 —— **Spotube v5.0.0（2025-09-11）**，本報告改以它為主要對照。見 §12.19。
> **第六輪**（遠端歷史被改寫後重新對基準）確認 10 個新 commit 沒有推翻任何一條結論（`d61e602d` 只是 InnerTube 常數去重，值逐字未變），並校正了 37 條因 `dart format` 位移的行號引用。過程中用新增的 `test/live/` 發現第五輪的一個前提是錯的：**Netease 匿名路徑其實拿得到串流 URL**，而 eapi 回的是 `http://` —— 這把 P1-8 從「要優化的 186ms」改判為「生產環境跑不到的死碼」，也證明 `flag & 4` 根本不是 VIP 訊號（P1-10 的根據更硬了）。見 §12.18。
> **第四輪**改用 Dart VM Service 的表達式求值（`evaluate`，必須走 WebSocket），在**不改任何一行程式碼、不送任何輸入事件**的前提下，於兩個平台跑了同一組受控網路實驗。結果更正了症狀 b 與 c 的兩處機制推論、新增一條 P0（P0-5：「開了流但零位元組」被記成播放成功，之後直接跳歌）與一條 P1（P1-10：Netease 未登入被誤判成需要 VIP）。見 §12.14。

**0.（第二輪新增，最嚴重）YouTube 每次播放要 20 秒，而且退化成含影片的串流。**
兩首曲目各測一次：audio-only 在 +2.0s / +2.2s 被 YouTube 擋下（`Reason: Sign in to confirm you're not a bot`），接著 muxed 分別在 **+19.7s / +21.5s** 才拿到，串流是 **719 kbit/s / 436 kbit/s 的 mp4（含視訊軌）**。點擊到出聲 22.2s / 23.6s，全程沒有任何逾時。而且 `getAudioStream`（`youtube_source.dart:387-415`）是「先把三種 streamType 用**匿名** youtube_explode 跑一輪，全失敗才用帶 auth 的 InnerTube」—— 只要 muxed 匿名成功，帶登入的 InnerTube audio-only 路徑**結構上永遠到不了**。詳見 §3.a-YouTube。

五件原本最重要的發現：

**1. 「播放載入慢」的主因不是 CDN，是 app 自己每次都重跑一次完整的串流解析，而且預取的結果 100% 被丟棄。**
實測同一首歌連播三次，每次都重打 Bilibili API（1.25s / 1.42s / 1.43s），零重用（§3.a）。原因有兩個獨立的 bug 疊在一起：`DefaultStreamResolutionService.resolvePrimary()` 從頭到尾**沒有讀過** `track.audioUrl` / `hasValidAudioUrl`（`stream_resolution_service.dart:106-135`）；而預取是對 `nextTrack.copy()` 做 `persist: false` 的解析（`playback_request_session.dart:734` + `:219-240`），結果寫進一個馬上被丟掉的物件。**兩個都修才有效果。**

**2. Bilibili 海外 CDN 加速在你這台機器上沒有優化空間 —— API 已經直接發 Akamai 海外節點，實測 3.08 MB/s。**
直接打 `playurl` 拿到的三條音軌 baseUrl 全部是 `upos-hz-mirrorakam.akamaized.net`，backup 是 `upos-sz-mirrorcosov.bilivideo.com`（騰訊雲海外）；`curl` 抓 1MB 用 0.34s、TTFB 300ms、支援 Range（206）。整首 218kbps × 125s ≈ 3.4MB 只要約 1.1 秒下載完（§12.4）。**mirror host 替換這條路對現況幾乎沒有收益**，該做的是消滅那 1.4 秒的 API 往返與加上位元組快取。

**3. 播放載入路徑上沒有任何逾時上限。**
`PlaybackRequestSession._waitForRequestOperation()`（`playback_request_session.dart:692-728`）只把後端操作跟「被新請求取代」賽跑，沒有 `.timeout()`；`JustAudioService` 的 `setAudioSource` 與 `MediaKitAudioService` 的 `player.open()` 都是裸 `await`。第四輪用本機伺服器把「連得上但一個位元組都不送」量出來了：Android 阻塞 **37.7 秒**才拋出，Windows 更糟 —— **6.1 秒就「成功」返回**（`duration: null`、`playing: true`），12.4 秒後再發一個假的 `completed`，然後直接跳下一首。等待時間完全由引擎內部策略決定，FMP 這一側沒有任何上界 —— 這正是症狀 b（§12.14e）。

**4. 後端錯誤分類是照 libmpv 的詞彙寫的字串比對，在 Android 上幾乎全部落空 —— 已在實機上完整重現。**
`_isStringNetworkError`（`audio_provider.dart:2435-2448`）比對 `'tcp:'`、`'ffurl_read'` 這些純 libmpv/FFmpeg 詞彙，但 Android 走 `JustAudioService`。斷網實測（§12.9）拿到的是：

```
[ERROR] [JustAudioService] Playback error: PlatformException(0, Source error, {index: 0}, null)
[ERROR] [AudioController] Audio error from service: Playback error: PlatformException(...)
[DEBUG] [AudioController] Non-network error, ignoring: Playback error: PlatformException(...)
```

沒有重試、沒有「播放網路異常」橫幅、沒有 toast；網路恢復後 `_onNetworkRecovered called, recoveryTrack: null` —— 因為錯誤被丟掉，恢復目標從未被登記，**音樂再也不會自己回來**，UI 停在無限轉圈。

**5. 驗證方法本身有一個陷阱要記進 skill：Android 模擬器的音訊播放比實際時間快約 1.68 倍。**
一首 API 權威時長 125,056ms 的曲子，在模擬器上 74.3 秒就播完；21.7 秒的曲子播 13.0 秒。裝置時鐘與主機時鐘實測比值 1.000，所以不是時鐘漂移。**這不是 FMP 的缺陷**，但它讓「曲目長度／曲間銜接／緩衝耗盡」這類 wall-clock 相關的驗證在這台 AVD 上全部無效（§12.5）。

---

## 1. 現況：播放管線

### 1.1 管線全圖【事實】

```text
 UI (mini_player / player_page / 列表項)
   │  只呼叫 AudioController，lib/ui/ 內 FmpAudioService 零命中（rg 驗證）
   ▼
 AudioController                                   audio_provider.dart:219-3217（2998 行，90 個欄位）
   ├─ _executePlayRequest()          :2193         模式：queue / temporary / detached / mix
   │    └─ _createPlaybackRequestTrack() :1494     ← track.copy()（每次都是新物件）
   ▼
 PlaybackRequestSession.start()      playback_request_session.dart:208
   ├─ _stopForRequest()  → audioService.stop()             :501
   ├─ _execute()                                            :506
   │    ├─ selectPlayback()  ──────────────┐
   │    └─ _playSelection() → playMedia()  │  ← 這兩段都沒有 timeout
   └─ _prefetchNextIfRequested()            │     :730  ← 結果被丟棄，見 §3.a
                                            │
   ┌────────────────────────────────────────┘
   ▼
 AudioStreamManager.selectPlayback()  audio_stream_manager.dart:72
   ├─ ensureAudioStream() → StreamResolutionService.resolvePrimary()
   └─ prepareNetworkPlayback() → SourceAuthContext.playbackNetworkRequest()
                                        └─ MediaHandoff.preparePlayback()
   ▼
 DefaultStreamResolutionService       stream_resolution_service.dart:106
   ├─ _inspectLocalFiles()      ← 有下載檔就直接用（唯一的「快取」）
   └─ _resolveRemotePrimary()   ← ★ 從不檢查 track.audioUrl / hasValidAudioUrl ★
        ├─ _buildRequestContext() → SettingsRepository.get() + authForPlay()
        ├─ fetchAudioStreamWithQualityFallback()  → SourceX.getAudioStream()
        │       Bilibili: /x/web-interface/view（拿 cid）→ /x/player/playurl
        │       YouTube : youtube_explode → (失敗才) InnerTube /player
        │       Netease : eapi /song/enhance/player/url
        └─ retryCount < 1 時重試一次，延遲用 AppConstants.queueSaveRetryDelay（命名錯置）
   ▼
 DefaultMediaHandoff                  media_handoff.dart:64
   └─ Netease 才走：最多 5 跳 HEAD/GET 預檢重導向（:142-197），每跳 30s receive timeout
   ▼
 FmpAudioService (abstract)           audio_service.dart:8-68  errorStream 是 Stream<String>
   ├─ JustAudioService  (Android)  ExoPlayer  10s/20s/3s/2MB LoadControl（:140-149）
   └─ MediaKitAudioService (Windows) libmpv    32MB buffer / 24MB demuxer / 7200s cache（:20-31, :250-307）
   ▼
 錯誤回流：errorStream(String) → AudioController._onAudioError()  :2897
   ├─ isRadioPlaying == true → 直接 return（電台全吞，RadioController 沒訂閱 errorStream）
   ├─ _isStringNetworkError()   :2434  ← 字串比對，libmpv 詞彙
   ├─ _isStringMediaOpenError() :2974  ← 字串比對
   └─ PlaybackRecoveryCoordinator → 1s/2s/4s/8s/16s 退避，最多 5 次
```

### 1.2 狀態機、逾時、重試、快取的實際落點【事實】

| 面向 | 現況 | 證據 |
|---|---|---|
| **狀態機** | 沒有單一狀態機。播放狀態散在四個地方：`PlayerState`（`player_state.dart`，24 個欄位的資料類別）、`_PlaybackContext`（`audio_provider.dart:121`）、`PlaybackSessionResultKind`（4 值 enum）、`PlaybackRecoveryState`（4 個布林/計數）。轉移靠散落的 `copyWith` 與 `if` | `audio_provider.dart:121-182`、`playback_request_session.dart:11-16`、`playback_recovery_coordinator.dart:76-94` |
| **載入逾時** | **無**。`_waitForRequestOperation` 只 `Future.any([operation, lock.completer])`；後端 `setAudioSource` / `player.open()` 都是裸 await | `playback_request_session.dart:692-728`；`just_audio_service.dart:523,554,581,602`；`media_kit_audio_service.dart:746,789,835,872` |
| **HTTP 逾時** | 只有音源 API 層有：connect 10s / receive 30s | `app_constants.dart:112,115`；`http_client_factory.dart:36-37` |
| **後端層唯一的等待上限** | just_audio `_waitForIdle` 500ms（`:465-472`）；media_kit `_ensurePlayback` 50×100ms = 5s，超過就拋 `StreamOpenFailedException`（`:659-680`） | 同左 |
| **重試** | 三層各自為政：① 音源解析內層 `retryCount < 1`（`stream_resolution_service.dart:169`）② 品質降級 ladder（`audio_stream_quality_fallback.dart:28-83`）③ 後端錯誤退避 1/2/4/8/16s ×5（`app_constants.dart:176-192`）。三層沒有共同預算 | 同左 |
| **音訊位元組快取** | **完全沒有**。`rg 'LockCachingAudioSource\|HttpServer\|cache-on-disk'` 在音訊路徑零命中。唯一的本地檔案來源是「下載」功能 | `stream_resolution_service.dart:287-300`（只查下載路徑） |
| **URL 快取** | 欄位存在（`track.audioUrl` / `audioUrlExpiry`）且會被寫入，但**播放路徑從不讀** | `stream_resolution_service.dart:106-135` 全文無 `hasValidAudioUrl` |
| **預抓下一首** | 有呼叫，但結果被丟棄（§3.a）。且**佇列恢復路徑完全不預抓** | `playback_request_session.dart:730-736`；`_executeQueueRestore`（`:595-668`）沒有 `_prefetchNextIfRequested` |
| **gapless / crossfade** | **完全沒有**。`rg -i 'gapless\|crossfade\|ConcatenatingAudioSource\|setAudioSources'` 在 `lib/` 零命中 | — |

### 1.3 後端抽象的洩漏【事實】

`FmpAudioService`（`audio_service.dart:8-68`）有 11 條 stream、9 個 getter、約 20 個方法。兩個實作的落差：

| 能力 | JustAudioService (Android) | MediaKitAudioService (Windows) |
|---|---|---|
| `audioDevices` | 硬編碼 `[]`（`:113-114`） | 完整實作（`:392-422`） |
| `audioDevice` | 硬編碼 `null`（`:115-116`） | 完整實作 |
| `setAudioDevice` / `setAudioDeviceAuto` | **空方法體**（`:446-454`） | `:616-630` |
| `audioDevicesStream` / `audioDeviceStream` | **死流**，全檔無 `.add()` | 有事件 |
| `processingState == buffering` | ExoPlayer 真的會發 | 合成器 `_isPlaying` 優先，**播放中緩衝永遠回 `ready`**（`:435-450`） |
| `processingState == loading` | 後端會發（`:123-124`） | 合成器**永遠不會回** `loading`，只在 4 個開媒體方法手動 push |
| `seekToLive` | 兩條策略（duration + bufferedPosition，`:376-422`） | 只有 duration 一條，`duration < 5s` 直接 false（`:556-588`） |
| `errorStream` 內容 | 型別分支後格式化的字串；`PlayerInterruptedException` 被吞掉（`:272-274`） | **raw libmpv log 原文，零過濾**（`:383-390`） |
| `StreamOpenFailedException` | **從不拋出** | `:672-676` |

【推論】洩漏的後果有三個：
1. `RadioController` 用 `e is StreamOpenFailedException` 做「重取 URL 重連」（`radio_controller.dart:534-538`），這條路在 Android 上是死的。
2. UI 用 `isDesktopPlatform && hasSelectableDevices` 判斷要不要顯示裝置選擇器（`player_page.dart:177`、`radio_player_page.dart:60`）—— 但 `hasSelectableDevices`（`audio_player_selectors.dart:18`，`audioDevices.length > 1`）自己就足夠，因為 Android 恆為 `[]`。**介面缺 `supportsAudioDeviceSwitching` 這種能力查詢，於是靠 `Platform` 補**。
3. `audio_provider.dart` 內有 5 處裸 `Platform.isWindows`（`:409, 1644, 1728, 2846, 2887`），全部圍繞 SMTC，而 `WindowsSmtcHandler` 自己已經有守衛（`:76`）。

---

## 2. 現況：音源層

### 2.1 抽象已經是 capability-based，而且做得不錯【事實】

- **`BaseSource` 不存在。** `base_source.dart` 只有 DTO；抽象換成 `source_capabilities.dart` 的 **11 個窄介面**（`SourceCapability` / `DisposableSource` / `TrackInfoSource` / `AudioStreamSource` / `TrackDetailSource` / `PagedVideoSource` / `DynamicPlaylistSource` / `RankingSource` / `LiveSource` / `SearchSource` / `PlaylistParsingSource` / `AvailabilitySource`）。
- 這個狀態**被測試鎖定**：`test/data/sources/source_capabilities_test.dart:62-65` 斷言 `base_source.dart` 不得出現 `abstract class BaseSource`。
- `SourceManager` 本體幾乎沒有 switch：`_capability<T>(SourceType)` 是泛型線性掃描（`source_provider.dart:38-45`），`dispose()` 用 `whereType<DisposableSource>()`（`:192-197`），建構子接受注入（`:14-22`）。
- 三個 adapter **沒有任何 `UnsupportedError` / `UnimplementedError`** —— 能力缺席一律用「不 implements」表達，這一點三源一致。

【推論】音源層的抽象品質**明顯高於播放層**。上一輪重構顯然已經處理過這裡。

### 2.2 但三個地方讓它離「可插拔」還很遠【事實】

1. **`SourceType` 是封閉 enum**（`track.dart:8-11`），而且被 Isar 持久化 + i18n `displayName` 綁定。外部插件無法擴充。
2. **`Settings` 每源一組具名欄位**：`bilibiliStreamPriority` / `youtubeStreamPriority` / `neteaseStreamPriority`（`settings.dart:187-194, 271-278`）、`useBilibiliAuthForPlay` 等三個布林 + `useAuthForPlay(SourceType)` 的 switch（`:591-610`）、`defaultHomeRankingSourcePriority = 'bilibili,youtube,netease'`（`:81`）。
3. **`ranking_cache_service.dart` 有 49 處硬編碼三源**（`:70-80, 168-170, 185-187, 200-202, 222-228, 242-244, 262-274, 300-302, 389-399, 442-444, 452, 465-467, 492-498`）：三源各自的 getter、各自的 refresh、switch 決定請求參數與標題。**這是插件化最大的單點阻塞。**

其他硬編碼熱點：`source_http_policy.dart` 有 3 個三分支 switch（`:40-55, :76-88, :158-176`）＋ Netease 專屬 allowlist（`:135-147`）；`popular_provider.dart` 每源一組 provider；三個獨立的 `add_to_*_playlist_dialog.dart` 與三個 `*_login_page.dart`。

### 2.3 已知的不一致與死碼【事實】

| 類型 | 具體 |
|---|---|
| 宣告有能力、實作是空的 | `NeteaseSource.getAlternativeAudioStream` 整個 body 只有 `return null;`（`netease_source.dart:203-208`）。共用備援器對 Netease 只剩「降品質重打」一條路（`audio_stream_quality_fallback.dart:73`） |
| 有實作、沒宣告能力（拿不到） | `BilibiliSource.getHotComments`（`:861`）、`getLiveRoomInfo`（`:1121`）、`NeteaseSource.getHotRankingTracks`（`:354`）、`YouTubeSource.getTrendingVideos`（`:1619`） |
| 整條能力鏈是死碼 | `AvailabilitySource` 三源都實作，生產零呼叫；`SourceManager.parseUrl/parsePlaylist/refreshAudioUrl/isPlaylistUrl/needsRefresh`（`:103-146`）只被 `parseUrlProvider`/`parsePlaylistProvider`（`:210-221`）用，而這兩個 provider 在 `lib/` 與 `test/` 都零引用 |
| 不是真的 capability-driven | `dynamicPlaylistSource(SourceType.youtube)`（`playlist_provider.dart:370`、`audio_provider.dart:3290`）、`liveSource(SourceType.bilibili)`（`search_provider.dart:741`）—— 呼叫端先假設哪一源有能力 |
| 平行的第二套抽象 | `playlist_import/playlist_import_source.dart:113-125` 的 `PlaylistImportSource` + 自己的 `enum PlaylistSource {netease, qqMusic, spotify}`，不進 `SourceManager` |
| 層級違規 | `netease_source.dart:8` 從 `lib/data/` 反向 import `lib/services/library/remote_playlist_id_parser.dart` —— `lib/data/` 下唯一一筆 |
| 錯誤分類跨源不對等（第四輪新增） | 三源都有各自的 `_handleDioError` / `_classify*`，但沒有共同的「這個失敗屬於哪一類」契約。實測後果：Netease 未登入（`fee=0, code=404, url=NULL`）被 `flag & 4` 這條規則判成 `-10` vipRequired，而同一個失敗在 `flag=256` 的曲目上又變成 `-404` unavailable —— **同一種失敗、兩種使用者訊息**（`netease_source.dart:877-931, 958`；§12.14g）。已經存在的 `SourceErrorKind.loginRequired` 只綁在 `code==301` 上，實際永遠不會被選到 |

### 2.4 三源的 URL 有效期與備援【事實】

| | Bilibili | YouTube | Netease |
|---|---|---|---|
| `AudioStreamResult.expiry` | 2h（`app_constants.dart:26`，`bilibili_source.dart:416,459`） | 1h（`youtube_source.dart:50-51`，8 處） | 16min（`netease_source.dart:40,192`） |
| API 有回報過期時間？ | 有（URL query `deadline`），**沒讀** | 否 | 有（`expi`），**讀了只寫 log 就丟**（`:173,184,192`） |
| 實測 TTL | **7178s = 1.99h**，與常數吻合（§12.4） | 未驗證 | **伺服器回報 `expi=1200s`（20 min）**，匿名與已登入、Dart 與 QuickJS 四次觀測一致（§12.18b、§12.16、§12.19a）。FMP 的常數是 16 min，比伺服器值保守 4 分鐘 —— 方向安全，但那是碰巧，因為回報值被丟掉了。**URL 真正失效的時點仍未實測** |
| 同源備援 | `_resolveAlternativeAudioStreamForCid`（`:760-795`），可換 DASH backupUrl 或另一 durl | 三種 streamType 全走一遍再走 InnerTube（`:634-691`） | **無** |
| 降品質備援觸發條件 | 只在 `unavailable` / `vipRequired`（`source_exception.dart:24-26`），而 `vipRequired` **只有 Netease 會產生**（`netease_exception.dart:41`） | 同左 | 同左 |

【推論】Bilibili 的 `deadline` 就在 URL 裡、精度到秒，卻用寫死的 2 小時常數近似；Netease 更直接 —— API 回了 `expi` 卻丟掉。這兩處把「URL 何時過期」從精確資訊降級成猜測。

---

## 3. 四個症狀的根因定位

### 3.a 播放載入慢（即使已預取音訊 URL）—— 根因確認，有實測

**根因一：`resolvePrimary()` 從不重用已解析的 URL。**【事實】

```dart
// stream_resolution_service.dart:106-135
Future<StreamResolutionResult> resolvePrimary(Track track, {...}) async {
  if (purpose != StreamResolutionPurpose.download) {
    final localFileState = _inspectLocalFiles(track);      // 只查下載檔
    ...
  }
  return _resolveRemotePrimary(track, ...);                // 一律重打網路
}
```

全函式沒有出現過 `track.audioUrl` 或 `hasValidAudioUrl`。`rg 'hasValidAudioUrl' lib/` 在播放路徑上唯二命中是 `stream_resolution_service.dart:220`（預取用來「跳過」）與 `audio_provider.dart:2681`（`_resumeWithFreshUrlIfNeeded`，用來判斷「要不要重取」）。

**根因二：預取是對一個丟棄物件做的。**【事實】

```dart
// playback_request_session.dart:730-736
void _prefetchNextIfRequested(bool prefetchNext) {
  final nextTrack = _getNextTrack();
  if (nextTrack != null) {
    unawaited(_audioStreamManager.prefetchTrack(nextTrack.copy()));   // ← copy
  }
}
```
`prefetchTrack` → `resolvePrimary(purpose: prefetch, persist: false)` → `_applyStreamResult(..., persist: false)` 的第一句就是 `if (!persist) return track;`（`stream_resolution_service.dart:273`）。**URL 寫進 `nextTrack.copy()` 這個馬上被 GC 的物件。** 網路請求照發、風控額度照燒、快取零收穫。

**實測（Android 模擬器，裝置時間戳）**【事實】

| 情境 | 解析耗時 | 說明 |
|---|---|---|
| 首播 `BV1zrtc63E7u` | 03:01:36.889 → 38.627 = **1.738s** | cold |
| **13 秒後重播同一首** | 03:01:49.915 → 51.557 = **1.642s** | 零重用 |
| 佇列恢復 `BV1o58Q6UEik` | 03:02:06.249 → 07.703 = **1.454s** | 其中 cid 查詢 1.305s |
| 同曲第 3 次（110s 後） | 03:03:55.160 → 56.413 = **1.253s** | |
| 同曲第 4 次 | 03:05:13.819 → 15.238 = **1.419s** | |
| 同曲第 5 次 | 03:10:00.701 → 02.135 = **1.434s** | |

單次點擊到出聲的完整拆解（03:01:49.672 → 53.013 = **3.34s**）：
- 1.64s 串流解析（**可省**）
- 1.45s 後端開流到 ready（真正的網路 I/O + 解碼器初始化）
- 其餘為 UI/狀態

佇列切歌的靜默期實測 **2.893s**（03:02:06.031 `_restoreSavedState started` → 08.924 `completed successfully`）。

**根因三（Bilibili 專屬）：每次播放多一次 `/x/web-interface/view` 只為拿 cid，而且解析出的 cid 從不回寫。**【事實】

`getAudioStream` 的第一句是 `request.cid ?? await _getCid(bvid)`（`bilibili_source.dart:264-268`），`_getCid` 打的是回傳完整影片詳情的重量級端點 `/x/web-interface/view`（`:472-476`）。`AudioStreamResult` **沒有 cid 欄位**（`base_source.dart:101-127`），`track.cid` 的唯一寫入點是播放清單解析（`bilibili_source.dart:720, 819`）。→ 搜尋／熱門榜來的曲目每播一次就多一次往返。

**⚠️ 這一段的絕對數字是模擬器假象，第二輪已查明並更正。**

第一輪寫的是「差額主要是 debug build 的 JSON 解析」——**這個歸因是錯的**，第二輪三個實驗推翻它（§12.8）：

| 實驗 | 結果 | 推翻了什麼 |
|---|---|---|
| 兩首**不同**曲目間隔 5.2s 連播（連線仍在 15s idle 內） | 第二次 cid 仍 **1.19s**，同一個 Dio 緊接著的 playurl 只 **0.086s** | 不是連線建立成本 |
| 主機用 FMP 完整 header（含隨機 buvid cookie）重打 | view **0.089–0.105s**、playurl 0.100–0.121s，兩者都快；而且 view 回應只有 2.1 KB、playurl 28.6 KB —— **大的那個反而快** | 不是 JSON 解析、不是伺服器慢 |
| 模擬器內 `ping api.bilibili.com` ×6 | **497–1145 ms，重複執行也不變快**；主機 `time_namelookup` 僅 **0.010–0.013s** | ✅ 真正原因：**AVD 的 DNS 每次查詢約 1 秒且無有效快取** |

【事實】`view` 是每次播放對 `api.bilibili.com` 的第一個請求，要新建連線 → 付一次 ~1s 的 DNS；緊接著的 `playurl` 重用該連線 → 0.09s。

**修正後的結論**：**「每播一次多打一支 `/x/web-interface/view` 只為拿 cid」這個結構浪費是真的、可修的**（cid 是不變值，存下來就永遠不用再查）；但**省下的時間在真實裝置上是「一次 API 往返」（主機量到約 0.1s，行動網路或高延遲下更多），不是模擬器上看到的 1.4 秒**。第一輪報告中所有「省 1.4 秒」的表述都應按此校正。

**同時，§12.2 所有解析耗時（1.25–1.74s）都含這 ~1s 的 AVD DNS**，真實裝置上整段解析約 0.2–0.5s。這不影響「零快取」這個結論本身（快取命中可同時省掉 DNS＋兩支 API），但會改變優先順序：在網路良好的真實裝置上，**後端開流（實測 1.15–1.45s）才是點擊到出聲的最大單一項**。

**根因四（Netease 專屬）：播放前的重導向預檢串在關鍵路徑上。**【事實】`DefaultMediaHandoff.preparePlayback` 對 Netease 會做最多 5 跳的 HEAD（405 時退回 Range GET）預檢（`media_handoff.dart:142-242`），每跳 `.timeout(AppConstants.networkReceiveTimeout)` = 30s。**最壞情況 150 秒**才輪到播放器開始開流。

【第五輪已實測，見 §12.15(a)】150 秒的上界在程式碼上成立，零 redirect 的 preflight 本身也要 186ms。**但第六輪推翻了這條根因的前提（§12.18d）**：eapi 回的媒體 URL 是 `http://m801.music.126.net/...`（實測），而 preflight 的閘門 `canAttachNeteaseMediaCredentials` 硬性要求 https —— **所以這段預檢在生產環境一次都不會執行**。根因四不成立，改列為死碼問題；186 秒與 186 毫秒都不會發生在真實播放上。

---

### 3.a-YouTube 每次播放 20 秒，而且拿到含影片的串流（第二輪新增，P0）

**實測兩首，行為一致**【事實，log 見 §12.10】：

| | Cardi B `I-5e_J3LWS8` | JENNIE `s466YCiHfKw` |
|---|---|---|
| audio-only 嘗試失敗 | +2.04s | +2.20s |
| 失敗原因 | `VideoUnplayableException` / `Reason: Sign in to confirm you're not a bot` | 同上，逐字相同 |
| muxed 取得 | **+19.66s** | **+21.55s** |
| 取得的串流 | **719.31 Kbit/s, mp4** | **436.28 Kbit/s, mp4** |
| 點擊→出聲 | **22.21s** | **23.59s** |

**三個疊加的問題：**

1. **audio-only 被 YouTube 的 bot 檢查擋死。** `lib/data/sources/AGENTS.md:50-51` 記載「只有 `androidVr` 客戶端會產生可用的 audio-only」（`youtube_source.dart:448, 718`）。androidVr 被擋 ⇒ **完全沒有 audio-only**，一律退到 muxed。

2. **muxed 是含視訊軌的串流，位元率 3–5.5 倍。** 一般 YouTube audio-only 約 130 kbit/s；實測拿到 436 與 719 kbit/s。對一個音樂播放器來說，這是白白多下載 3–5 倍的資料 —— 也直接惡化症狀 c（同樣頻寬下更容易緩衝耗盡）。

3. **帶登入的 InnerTube audio-only 路徑結構上到不了。**【事實】`getAudioStream`（`youtube_source.dart:387-415`）的流程是：

   ```dart
   for (final streamType in config.streamPriority) {        // audioOnly → muxed → hls
     final result = await _tryGetStream(videoId, streamType, config);  // ← 沒有 authHeaders，全程匿名
     if (result != null) return result;                     // ← muxed 成功就直接返回
   }
   if (authHeaders != null) { ... _getAudioStreamViaInnerTube(...) }   // ← 只有整個迴圈都失敗才走到
   ```

   auth 升級掛在**整個 streamType 迴圈之後**，而不是掛在「audio-only 失敗」之後。**只要匿名 muxed 成功，帶登入的 audio-only 就永遠不會被嘗試**，即使使用者已登入且開了 `useYoutubeAuthForPlay`。而該旗標預設還是 `false`（`settings.dart:274`）。

【推論】正確的順序應該是「**同一個 streamType 先匿名、失敗再帶 auth**」，而不是「**所有 streamType 都匿名試完、再全部帶 auth 試**」。現在的順序把「音質/頻寬」讓位給了「哪種取法先成功」。

**第四輪補上的對照組（Windows，未登入，直接呼叫 `YouTubeSource().getAudioStream`）**【事實，見 §12.14(f)】：

| 影片 | 結果 | 耗時 | 取得的串流 |
|---|---|---|---|
| `dQw4w9WgXcQ` | audio-only 成功 | **1,486 ms** | opus, 136,544 bps |
| `kJQP7kiw5Fk` | audio-only 失敗 → 退到 **muxed** | **9,901 ms** | **mp4a.40.2, 666,320 bps** |
| `dQw4w9WgXcQ`（同一首再跑一次） | audio-only 成功 | 827 ms | 同上 |

這組數字把成本切乾淨了：**audio-only 命中時只要 1.5 秒**；audio-only 一失敗，光是退到 muxed 就多花 **8.9 秒**，拿到的是 **4.9 倍位元率的含視訊串流**。第二輪在 Android 上量到的 20 秒是同一個機制在較差網路下的樣子，不是另一個問題。順帶也再次證實 P0-1：同一首連續解析兩次，第二次仍然打了完整 API（827ms），沒有任何快取。

**另外，這 9–20 秒完全沒有逾時上限** —— 這是症狀 b 在真實資料上的最強例證。

---

### 3.b 載入很久卻不逾時跳過，造成音樂空窗 —— 根因確認

**【事實】整條載入路徑沒有任何逾時上限。**

```dart
// playback_request_session.dart:724-727
return Future.any([
  operationCompleter.future,          // 後端操作，本身無 timeout
  lock.completer.future.then<T?>((_) => null),   // 只有「被新請求取代」才會完成
]);
```

- `_audioService.playMedia(media)` 內部：`JustAudioService` 是 `await _player.setAudioSource(source)`（`:523`）、`MediaKitAudioService` 是 `await _player.open(media, play: false)`（`:746`）—— 兩邊都沒有 `.timeout()`。
- `selectPlayback()` 也是裸 await，只有底下的 dio 有 10s connect / 30s receive。
- `_execute()` 的 catch 會嘗試 fallback（`:528-577`），fallback 本身又是一次無逾時的完整解析。

**【事實・第四輪實測】開流階段的行為已經量到了，而且兩個後端完全不同**（完整數據與逐字 log 見 §12.14(d)(e)）。用本機伺服器製造「連得上但一個位元組都不送」：

| | Windows / media_kit | Android / just_audio |
|---|---|---|
| `playUrl` 的結果 | **6.111 秒正常返回**，`duration: null`、`playing: true` | **阻塞 37.711 秒後拋出** `(0) Source error` |
| 之後 | 12.4 秒後發 `completed` → premature 保護被 `duration == null` 繞過 → 直接換下一首 | 錯誤同時也進 `errorStream`，但字串不被分類器接受（§12.14(c)）→ 靜默丟棄 |

**更正**：第一輪寫的「`open()` 可以永遠不返回，使用者只看到轉圈」在 Windows 上不成立 —— 問題不是「不返回」，而是**返回了而且宣稱成功**。`media_kit_audio_service.dart:717-770` 等 duration 只等 `10 × 50ms = 500ms`，逾時就把 `resultDuration` 設成 null 繼續往下，`_ensurePlayback()` 只看 mpv 的 `playing` 旗標 —— 而 mpv 在零位元組時確實會翻成 true。上層因此收到「播放成功、時長未知」，沒有任何理由認為出事了。

【推論】最壞情況的無聲時間：
- 解析階段可界定但很長：`(10s connect + 30s receive) × 2 次（內層 retry）` ＋ 品質降級 ladder 每級再一輪 ＋ fallback 再一輪。
- 開流階段**由引擎決定，FMP 這一側沒有任何上界**：實測到的 6.1s / 12.4s / 16.4s / 37.7s 全部來自引擎內部的重試與逾時策略，FMP 既不設定也不知道。

這也解釋了為什麼症狀是「不逾時跳過」而不是「報錯」：**沒有任何地方把「載入太久」或「開了流但沒有資料」定義成一種失敗。**

---

### 3.c 播放中一卡一卡，頂部顯示「播放網路異常」—— 根因確認，兩平台成因不同

「播放網路異常」= `t.networkStatus.playbackNetworkError`（`lib/i18n/zh-TW/networkStatus.i18n.json:3`），由 `state.isNetworkError` 驅動（`network_status_banner.dart:30-31`），而 `isNetworkError` **只有 `PlaybackRecoveryCoordinator` 會設**（`:168, 197, 325`）。

**Windows（media_kit）路徑 —— 第四輪已完整實機重現，並更正了第一輪的機制描述**【事實，完整數據見 §12.14(d)】：

第一輪寫的是「mpv 吐出含 `tcp:` 的錯誤 → `_onAudioError` → `stop()` + 退避」。實測**播到一半連線被 RST** 時：

```
[srv] conn 1  sent 708652B of 21168044B -> RST
[srv] conn 2..7  GET Range: bytes=708652-  → refusing          ← mpv 自己重連了 6 次
14:37:07.486  Playback started, duration: 0:02:00.000000, playing: true
14:37:11.242  Track completed                                   ← 3.756 秒後
```

**`errorStream` 全程零輸出。** 也就是說：

1. media_kit 的 `stream-lavf-o` reconnect 設定**是有效的** —— mpv 在 3.5 秒內自行重連 6 次，帶正確的 `Range`。
2. 重連耗盡後 libmpv 把它報成 **EOF（`completed`）而不是 error**，所以 `_onAudioError` 這條路**根本不會被走到**。
3. 實際接手的是 `_onTrackCompleted` → `_shouldHandleTrackCompleted()`（`:2991-3013`）。`duration=2:00`、`position≈4s`，`remaining` 遠大於 tolerance（`positionCheckInterval 1s + positionCheckThreshold 500ms = 1.5s`）→ 判定 premature → `_recoverFromPrematureCompletion`（`:3016-3031`）→ `PlaybackRecoveryCoordinator.scheduleRetry`（`:276-282`）→ 設 `isNetworkError: true, isRetrying: true`。

**「播放網路異常」橫幅的真正來源就是這裡。** 退避序列是 `NetworkRetryConfig` 的 1s/2s/4s/8s/16s、上限 5 次（`app_constants.dart:176-185`），約 31 秒後 `retryExhausted`。

【推論】結論不變 —— 這仍然是一個放大迴圈：一次網路抖動 → 引擎重連失敗 → 被當成 premature 完成 → 排一次重試 → 每次重試都是**一次完整的重新解析**（§3.a）→ 又一次抖動 → 退避拉長。**使用者體感就是「一卡一卡」加上頂部橫幅，而每一「卡」實際上是一次完整重載。** 只是觸發路徑不是錯誤分類，而是「假的曲目結束」。

【事實】另外還有一個更糟的變體：如果 duration 拿不到（`null`），`_shouldHandleTrackCompleted()` 的 `duration == null` 分支會直接 `return true`（`:2998-3000`），premature 保護**完全失效**，於是不是重試而是**直接換下一首**。實測見 §12.14(e)。

**Android（just_audio）路徑 —— 第二輪已完整實機重現**【事實，完整 log 見 §12.9】：

播放中切斷網路（飛航模式 + `svc wifi/data disable`），ExoPlayer 耗盡緩衝後：

```
08:16:38.221 [DEBUG] [AudioController] PlayerState changed: playing=true, processingState=buffering
08:16:44.890 [ERROR] [JustAudioService] Playback error: PlatformException(0, Source error, {index: 0}, null)
08:16:44.893 [ERROR] [AudioController] Audio error from service: Playback error: PlatformException(0, Source error, {index: 0}, null)
08:16:44.894 [DEBUG] [AudioController] Non-network error, ignoring: Playback error: PlatformException(0, Source error, {index: 0}, null)
```

該字串小寫後為 `playback error: platformexception(0, source error, {index: 0}, null)` —— 對 `_isStringNetworkError` 的 11 個關鍵字（socket / tcp: / ffurl_read / connection / network / timeout / unreachable / host / dns / errno / failed host lookup）**一個都不命中**。

後續三個觀察，逐一都是缺陷：

1. **沒有任何播放層回饋。** 沒有重試、沒有「播放網路異常」橫幅、沒有 toast。畫面上只有 ConnectivityNotifier 的通用 `No network` 橫幅（截圖 §12.9），那是「裝置沒網路」不是「這首歌播不下去」。
2. **網路恢復後不會續播。**
   ```
   08:18:22.094 [INFO] [AudioController] _onNetworkRecovered called, recoveryTrack: null
   ```
   因為 `_onAudioError` 提前 return，`PlaybackRecoveryCoordinator._recoveryTrack` 從未被設定 → 網路回來時無事可做。排行榜快取照常刷新了，音樂沒有。
3. **UI 永久卡在轉圈。** `processingState` 停在 `buffering` 再也沒變，mini player 的播放鍵維持 spinner 超過 2 分半（截圖 §12.9）。

**外加一個獨立缺陷**：斷網期間 `just_audio` 自己的本機代理伺服器每 ~10 秒丟出一次未捕捉的非同步錯誤，共 3 次：

```
[ERROR] [Zone] Uncaught async error
  Error: SocketException: Failed host lookup: 'upos-hz-mirrorakam.akamaized.net' (errno = 7)
  StackTrace: ... #10 _getUrl (package:just_audio/just_audio.dart:4057)
              #11 _proxyHandlerForUri.handler (package:just_audio/just_audio.dart:3369)
              #12 _ProxyHttpServer.start.<anonymous closure> (package:just_audio/just_audio.dart:2159)
```

【事實】這也順帶證實了一件對 §9-D3 決策很重要的事：**FMP 在 Android 上其實已經跑著一個本機 HTTP 代理**（just_audio 只要收到自訂 headers 就會啟用 `_ProxyHttpServer`，而 FMP 每次都傳 Referer + User-Agent）。「要不要自建本機代理來做快取」這個問題的前提因此改變 —— 代理已經在那裡了，`LockCachingAudioSource` 用的正是同一套。

**兩平台同條件對照（第四輪，同一組本機伺服器、同一組 URL）**【事實，逐字 log 見 §12.14(d)(e)】：

| | Windows / media_kit（libmpv） | Android / just_audio（ExoPlayer） |
|---|---|---|
| **播到一半連線被 RST** | 自行重連 6 次；`errorStream` 零輸出；**3.756s 後發 `completed`** → premature 保護 → 橫幅 + 退避重試 | 自行重連 3 次；**16.4s 後發 `Source error`** → 分類器不認 → **靜默丟棄**，狀態永遠停在 buffering |
| **連得上但零位元組** | `playUrl` **6.111s 正常返回**（`duration: null`、`playing: true`）；**12.4s 後發 `completed`** → premature 保護被 `duration == null` 繞過 → **直接換下一首** | `playUrl` **阻塞 37.711s 後拋出** `(0) Source error` → 進 `_execute` 的 catch → fallback 再一次完整解析 |

【推論】所以症狀 c 在兩個平台是兩件相反的事：Windows 是**過度反應**（把可恢復的抖動當成曲目結束而 teardown + 重載，或更糟，直接跳歌），Android 是**反應不足**（真的網路錯誤被丟掉，連狀態都沒清）。

**共同根因比原本寫的更深一層。** 原本歸因於 `errorStream` 的型別是 `Stream<String>`（`audio_service.dart:24`），錯誤語意在抽象邊界上被抹掉。實測顯示還要再加一條：**兩個後端在同一個網路條件下，連「哪一個事件通道會響」都不一致** —— 一邊發 `completed`、一邊發 `error`、一邊直接從 `playMedia` 拋出。任何寫在 `AudioController` 裡的字串比對，結構上都不可能同時涵蓋這三種。抽象需要的是**由後端回報的具結構錯誤／結束原因**（見 §6.1），而不是更長的關鍵字表。

---

### 3.d 曲目切換無過渡（gapless / crossfade）—— 現況確認

**【事實】兩者都完全沒有實作**，而且比「沒做過渡」更嚴重：**曲間有實測 2.893 秒的靜默**（§3.a）。

原因是架構性的：FMP **一次只餵一個媒體給後端**。`FmpAudioService` 的開媒體介面是 `playMedia` / `setMedia` / `playUrl` / `setUrl` / `playFile` / `setFile`（`audio_service.dart:61-68`），**沒有任何「佇列」或「下一首」概念**。切歌流程是 `stop()` → 解析 → `playMedia()`，中間必然出現靜默。

這跟四個對照專案的做法都相反（§5）：Auxio / Finamp / Spotube 都是**把整條佇列交給引擎**（`setMediaItems` / `setAudioSources(preload:true)` / `mk.Playlist`），gapless 是引擎的免費副產品；Symphony 沒有引擎佇列，就自己手刻雙 `MediaPlayer` 提前 prepare。

**【推論】在現有架構下 gapless 不是「加個 flag」，而是要先讓後端抽象具備佇列語意。** 這是 §6 目標架構的一部分。

---

## 4. 問題清單 P0–P3

### P0

| # | 問題 | 證據 | 影響 |
|---|---|---|---|
| **P0-1** | **串流解析零快取 ＋ 預取結果被丟棄**（兩個獨立缺陷） | `stream_resolution_service.dart:106-135`；`playback_request_session.dart:734` + `:219-240, 273` | 每次播放固定多付 1.25–1.74s；單曲循環每圈重打 API；重試時在網路最差的時候還要多一次往返 |
| **P0-2** | **播放載入路徑無任何逾時上限**（等待時間完全由引擎內部策略決定，FMP 既不設定也不知道） | `playback_request_session.dart:692-728`；`just_audio_service.dart:523`；`media_kit_audio_service.dart:746`；實測 YouTube 9.9–20s（§3.a-YouTube）、零位元組串流 6.1s／37.7s（§12.14(e)） | 症狀 b：CDN 卡住 = 靜默轉圈或假成功，沒有任何機制把它判定成失敗 |
| **P0-3**<br>（第二輪新增） | **YouTube audio-only 被 bot 檢查擋死 → 每次退化成 20 秒 + 含視訊的 muxed 串流；且帶登入的 InnerTube audio-only 路徑結構上到不了** | `youtube_source.dart:387-415`（auth 升級掛在整個 streamType 迴圈之後）、`:447, 718`（只有 androidVr 產生 audio-only）；實測兩首見 §3.a-YouTube | 點擊→出聲 22–24s；下載量 3–5.5 倍；直接惡化症狀 a 與 c |
| **P0-4**<br>（第二輪新增） | **Android 端播放期間的網路錯誤被完全丟棄**：不重試、不提示、不清狀態，網路恢復也不續播，UI 永久轉圈 | 實機 log §12.9；`audio_provider.dart:2906-2918, 2434-2447` | 使用者體感是「播一播就死了，只能自己重點」 |
| **P0-5**<br>（第四輪新增） | **「開了流但一個位元組都沒有」被記成播放成功**：`playUrl` 6.1s 正常返回、`duration: null`、`playing: true`；12.4s 後的 `completed` 又因 `duration == null` 繞過 premature 保護，直接 `moveToNext()` | `media_kit_audio_service.dart:717-770`（等 duration 只等 10×50ms）；`audio_provider.dart:2999-3001`；實測 §12.14(e) | 網路半死時**每首歌響 0 秒就跳掉、一路刷完佇列**，且沒有橫幅、沒有 toast、release build 連 log 都沒有 |

### P1

| # | 問題 | 證據 | 影響 |
|---|---|---|---|
| **P1-3** | **後端錯誤靠字串比對，且詞彙表只對 media_kit 有效** | `audio_provider.dart:2435-2448, 2974-2979`；`just_audio_service.dart:267-278` vs `media_kit_audio_service.dart:383-390` | 兩平台的錯誤恢復行為完全不對等；Android 的網路錯誤被靜默丟棄；#41 的誤判也源於此 |
| **P1-4** | **把可恢復的緩衝抖動當成曲目結束：premature 判定 → 退避 → 完整重解析** | `audio_provider.dart:2992-3014, 3016-3031`；`playback_recovery_coordinator.dart:153-205, 276-282`；實測 §12.14(d)。註：第一輪歸因的 `_onAudioError` 路徑在「播到一半斷線」時**不會被走到**，mpv 發的是 `completed` 不是 error | 症狀 c 的放大迴圈；每一「卡」是一次完整重載，退避 1/2/4/8/16s 共 ~31s |
| **P1-5** | **Bilibili 每播一次多一次 `/x/web-interface/view`，解析出的 cid 從不回寫** | `bilibili_source.dart:264-268, 472-476`；`base_source.dart:101-127`（無 cid 欄位） | 每次播放多一次可完全避免的 API 往返（主機量到 ~0.1s，行動網路更多）。註：模擬器上看到的 1.2s 是 AVD DNS 假象，見 §3.a 更正 |
| **P1-6** | **`AudioController` 是 2998 行、90 欄位的單一類別** | `audio_provider.dart:219-3217` | 已經拆出 5 個協作者（Session / Recovery / StreamResolution / Queue / Persistence），但控制器本身仍同時擁有 UI 狀態、通知、SMTC、歌詞、歷史、Mix、seek 穩定化、錯誤分類 |
| **P1-7** | **`FmpAudioService` 抽象洩漏**：Android 側裝置三件套是空實作＋死流；上層用 `Platform` 而非能力查詢 | `just_audio_service.dart:113-116, 446-454`；`audio_provider.dart:410,1644,1728,2846,2887`；`player_page.dart:177` | 新增後端／統一後端時要改的地方遠多於必要 |
| **P1-8**<br>→ **改判 P2**（第六輪） | **Netease 的播放前預檢與媒體憑證附帶，在生產環境一次都不會執行**：eapi 回的是 `http://m801.music.126.net/...`（實測），而閘門要求 https。約 150 行預檢 + 一個注入點 + 一整組測試全是死碼；`media_handoff_test.dart` 的每條 happy path 都用 eapi 不會產生的 `https://` URL 形狀 | `source_http_policy.dart:135-147`（https 閘）、`media_handoff.dart:100-106, 108-121, 142-242`、`source_http_policy.dart:57-67`；eapi 實測與三層解讀見 §12.18(d)；**已登入帳號的生產路徑實測見 §12.19(a)**（preflight 2ms 跳過、Cookie 被剝掉、真實簽名 URL 0 跳轉）；第五輪的 186ms 量測見 §12.15(a) | 效能面的急迫性消失（它根本不跑）。真正的代價是**假覆蓋率**：若哪天需要用帳號憑證取媒體位元組，這條路是斷的而測試不會告訴你。**不可用「放寬 https 檢查」修 —— 那是正確的防護** |
| **P1-9** | **`errorStream` 型別是 `Stream<String>`，而且兩個後端連「哪個事件通道會響」都不一致**（一邊 `completed`、一邊 `error`、一邊從 `playMedia` 拋出） | `audio_service.dart:24`；四格對照 §12.14(d)(e) | P1-3/P1-4/P0-5/#41 的共同上游根因。加關鍵字治不好，需要後端回報具結構的結束原因 |
| **P1-10**<br>（第四輪新增） | **Netease 未登入被誤判成「需要 VIP 或付費播放權限」**，而且同一個失敗因為 `flag` 位元不同會給出兩種不同訊息；正確的「需要登入後播放」字串存在但永遠不可達 | `netease_source.dart:877-931`（`_isVipRequiredStreamError` 排在 `code` 分支之前）、`:958`（`flag & 4`）；實測五首 `fee=0, code=404, url=NULL` 見 §12.14(g)；**第六輪再證 `flag & 4` 在「能播」的曲目上也成立**（`139774`：`flag=6, code=200`，匿名拿到 320kbps URL），所以該判準本身就是錯的，見 §12.18(e)；`netease_exception.dart:37`、`lib/i18n/zh-TW/audio.i18n.json:15` | 未登入使用者被引導到錯誤的結論（以為要付費，其實只要登入或換一首）。**更正**：Netease 匿名**有**可播路徑（免費曲目），所以誤判影響的是「這首剛好被擋」而非「全站不可播」 |

### P2

| # | 問題 | 證據 |
|---|---|---|
| **P2-10** | 無 gapless / crossfade，且曲間必有 ~2.9s 靜默；後端抽象沒有佇列語意 | `audio_service.dart:61-68`；實測 §3.a |
| **P2-11** | 音源能力宣告與實作不一致（Netease `getAlternativeAudioStream` 恆 null 等，見 §2.3） | `netease_source.dart:203-208` |
| **P2-12** | 大量死碼：`SourceManager` 5 個方法 + 2 個 provider、`AvailabilitySource` 全鏈、`WindowsSmtcHandler.enable/disable/dispose`、`onSeek` | §2.3、#40 |
| **P2-13**<br>**（第八輪縮小範圍）** | 依賴落後 —— **只有 `just_audio` 一個**：`^0.9.40` 實際解析到 **0.9.46**，而最新是 0.10.6；caret 擋住了 0.10.x，要手動放寬才升得上去。~~`media_kit`~~ 與 ~~`audio_service`~~ **不落後**：`^1.1.11` 已解析到 **1.2.6（最新）**、`^0.18.15` 已解析到 **0.18.18**（最新 0.18.19，差一個 patch）。原本用 `pubspec.yaml` 的**約束**去比 pub.dev 最新版，那是錯的比法 | `pubspec.lock`（實際解析版本）vs `pubspec.yaml:30,31,34`（約束）；pub.dev API（§12.7） |
| **P2-14** | URL 過期資訊被丟棄：Bilibili 的 `deadline`（實測 1.99h）不讀、Netease 的 `expi` 讀了只寫 log | `netease_source.dart:173,184,192`；§12.4 |
| **P2-15** | 三層重試沒有共同預算（解析內層 ×1、品質 ladder、後端退避 ×5），最壞可疊乘 | §1.2 |
| **P2-16** | `SourceType` 封閉 enum + `Settings` 每源具名欄位 + `ranking_cache_service.dart` 49 處硬編碼 | §2.2 |

### P3

| # | 問題 | 證據 |
|---|---|---|
| **P3-17** | `lib/data/sources/AGENTS.md:122-125` 只列 5 個 capability，實際 11 個 | §2.1 |
| **P3-18** | `lib/services/audio/AGENTS.md` 的 buffer profile 描述有落差：宣稱是「desktop profile」，但 `_configureForAudioOnly()`（`:250-307`）無平台判斷、無條件套用；另有 4 項（`cache=yes`、`cache-pause-initial=no`、`demuxer-donate-buffer=no`、`demuxer-lavf-o=icy=0`）文檔未提；7200s 實際是兩個 property 共用同一常數 | `media_kit_audio_service.dart:250-307` |
| **P3-19** | `mobilePlayerBufferSizeBytes = 2MB` 與其平台分支在生產不可達（Android 走 `JustAudioService`） | `media_kit_audio_service.dart:20, 160-162`；`audio_provider.dart:3219-3225` |
| **P3-20** | `_isStringNetworkError` 含 `'host'` 這種過寬的子字串；同時兩張關鍵字表各有一個字面近失 —— 有 `connection` 但 ExoPlayer 寫 `Unable to **connect** to`，有 `cannot open` 但 mpv 寫 `Can **not** open external file` | `audio_provider.dart:2438-2448, 2974-2979`；實測分類表 §12.14(c) |
| **P3-21** | `_resolveRemotePrimary` 的重試延遲借用 `AppConstants.queueSaveRetryDelay`（命名錯置） | `stream_resolution_service.dart:170` |
| **P3-22** | `netease_source.dart:8` 從 `lib/data/` 反向 import `lib/services/` | §2.3 |

---

## 5. 成熟做法對照

四個對照專案的實際做法（逐檔案考據，來源見 §12.7）：

| 維度 | Auxio | Symphony | Finamp | Spotube | **FMP 現況** |
|---|---|---|---|---|---|
| 引擎 | Media3 ExoPlayer 1.11.0（vendored fork） | 原生 `android.media.MediaPlayer`（**非** Media3，維護者於 issue #93 承認） | just_audio + `just_audio_media_kit`（桌面） | **media_kit 全平台**（換過 3 次後端） | just_audio(A) / media_kit(W) 雙後端 |
| 平台策略 | 純本地，不適用 | 純本地，不適用 | **單一 `AudioPlayer` API + 平台後端切換**，非雙 Service 類別 | **單一 `CustomPlayer`，無平台分支**（`_mkSupportedPlatform = true`） | 雙實作類別 + 上層 `Platform` 判斷 |
| 載入逾時 | 無（無網路 I/O） | 無 | 串流層無；HTTP API 層 10s / 3s | **有明確值**：libmpv `network-timeout=120` | **無** |
| 重試 | 無退避，`onPlayerError` 直接跳下一首（作者留 TODO 承認簡陋） | 無退避，移除歌曲跳下一首 | 播放層**明確關閉**（`maxSkipsOnError: 0`），只通知使用者；下載層才有 `retries:3` + age 退避 | 兩個一次性補救（換候選來源 / 重新解析 URL），播放器 `errorStream` 監聽是空實作 | 1/2/4/8/16s ×5，且每次重試都重解析 |
| 串流 URL 過期 | 不適用 | 不適用 | Jellyfin URL 內嵌長效 ApiKey，不自然過期 | **反應式**：`dio.head()` 檢查失敗才 `refreshStreamingUrl()`，不追蹤 TTL | 有 TTL 欄位但播放路徑不讀 |
| 位元組快取 | 不適用 | 不適用 | Isar `DownloadItem` DAG（PR #568）取代 5 個 Hive box | **本機 shelf 代理邊播邊快取**（`cacheMusic` 預設 true，寫 `.part` 再改名） | **無** |
| 預抓 | 整條佇列丟給 ExoPlayer Timeline | 手刻 `prepareNextPlayer()` 提前 prepare 下一個 MediaPlayer | `setAudioSources(preload: true)` + 桌面 `JustAudioMediaKit.prefetchPlaylist=true` | 播放進度 **80%** 觸發下一首來源解析 | 有呼叫，結果丟棄 |
| gapless | 有（ExoPlayer 佇列免費） | 手刻雙 player（開放 bug #720 稱效果不佳） | 有（`androidAudioOffloadPreferences` + `prefetchPlaylist`） | 有（libmpv 原生） | **無** |
| crossfade | **明確不做**（Wiki：ExoPlayer timeline 模型不支援） | 未實作（#187 / #338 開放中） | 只有 play/pause 淡入淡出，切歌**明確 `disableFade`** | **確認不存在** | 無 |

**幾條可以直接借的具體做法**：

1. **Spotube 的本機代理**（`lib/provider/server/routes/playback.dart`，我實抓過原始碼核對：`shelf` + `dio.head()` 檢查 + `refreshStreamingUrl()` 補救 + `.part` 暫存檔改名）—— 這是四者中唯一同時解決「URL 過期」與「位元組快取」的設計，而且場景（第三方串流 + 跨平台）跟 FMP 最像。
2. **Finamp 的單一 `AudioPlayer` + 平台後端切換**（Finamp repo 的 `main.dart:304-309`，用 `JustAudioMediaKit.ensureInitialized()` 而非兩個 Service 類別；**注意這不是 FMP 的 `lib/main.dart`**）—— 這是「保留雙後端但不讓平台知識外洩」的可行證明。
3. **Spotube 的 `network-timeout=120`**（`custom_player.dart`）與它的暖身手法（`load()` 先觸發首曲解析，避免 mpv 等解析而觸發逾時跳過）—— 直接對應 FMP 的 P0-2。
4. **Finamp 播放層 `maxSkipsOnError: 0`** —— 一個明確的反面參考：他們選擇「不自動重試、只通知使用者」，而 FMP 選了 5 次退避重試。兩種都合理，但 FMP 的問題是**重試代價太高**（每次都重解析）。
5. **Auxio 的取捨聲明**（Wiki「Why Are These Features Missing?」明說 crossfade 在 ExoPlayer timeline 模型下不可行）—— 值得學的是「把做不到的事寫進文檔」這個習慣。

---

## 6. 建議方案與目標架構

### 6.1 目標狀態機

現況的播放狀態散在四處（§1.2）。建議收斂成一個顯式的載入狀態機，**每個狀態都有逾時預算**：

```text
        ┌──────────────────────────────────────────────────────────┐
        │                        idle                              │
        └───────────────┬──────────────────────────────────────────┘
                        │ play(track)
                        ▼
        ┌───────────────────────────────┐  預算 T1（建議 8s）
        │ resolving                     │  快取命中則直接跳過
        │  ├─ cacheHit ────────────────►│
        │  └─ network → source adapter  │
        └───────┬───────────────┬───────┘
                │ ok            │ timeout / SourceApiException
                ▼               ▼
        ┌───────────────┐  ┌──────────────────────────────┐
        │ opening       │  │ failed(reason)                │
        │ 預算 T2 (10s) │  │  ├─ retryable → backoff       │
        └───┬───────┬───┘  │  └─ terminal  → 通知 + 停     │
            │ ready │ timeout / open error                 │
            ▼       └──────────────────►                   │
        ┌───────────────┐                                  │
        │ playing       │◄─────────────────────────────────┘
        │  ├─ rebuffering（不 teardown，只顯示指示器）      │
        │  └─ fatal → failed                                │
        └───────────────────────────────────────────────────┘
```

關鍵差異：**`rebuffering` 是 `playing` 的子狀態，不會觸發 stop 或重解析**。只有連續緩衝超過預算 T3（建議 20s）才升級成 `failed(network)`。這直接消滅症狀 c 的放大迴圈。

### 6.2 責任邊界（目標）

| 元件 | 職責 | 相對現況的變動 |
|---|---|---|
| `AudioController` | 只做「使用者意圖 → 播放請求」與「播放狀態 → UI 狀態」的翻譯 | **移出**：SMTC/通知協調、歌詞自動比對、播放歷史、Mix 載入更多、錯誤字串分類 |
| `PlaybackSession`（現 `PlaybackRequestSession`） | 載入狀態機 + 逾時預算 + supersede | **新增**：每階段逾時；**移出**：media-open 錯誤的復原推測（改由型別化錯誤驅動） |
| `PlaybackSourceResolver`（現 `StreamResolutionService`） | 解析 + **URL 快取查詢與寫回** + 品質降級 | **新增**：快取查詢是第一步 |
| `MediaCache`（新） | 位元組級本地快取 + Range 服務 | 全新 |
| `FmpAudioService` | 只管「開一個媒體、播、停、seek、報型別化事件」 | **改**：`errorStream` 改成 `Stream<PlaybackFault>`；**新增**：`setQueue` / `supportsQueue` 等能力查詢 |
| `MediaControlSurface`（新，收斂 `FmpAudioHandler` + `WindowsSmtcHandler`） | 系統媒體控制的統一介面，含能力宣告（可否 seek、可否上下首） | 全新，直接解掉 #40 |

### 6.3 分階段方案（tracer bullet 順序）

**階段 0 — 止血（成本 S，風險低，完全可逆）**

1. `resolvePrimary()` 開頭加一段：本地檔 → **`track.hasValidAudioUrl` 且未進入 5 分鐘安全邊界 → 直接回傳** → 才走網路。安全邊界沿用既有的 `SourceManager.needsRefresh` 語意（`source_provider.dart:140-146`，目前是死碼，正好復活它）。
2. 預取改為 `persist: true`，並把 `_prefetchNextIfRequested` 的 `nextTrack.copy()` 改成傳入佇列中的實例（或在解析完成後 `_queueManager.replaceTrack`）。
3. `AudioStreamResult` 加 `cid` 欄位，`_applyStreamResult` 回寫 `track.cid`。
4. 佇列恢復路徑（`_executeQueueRestore`）補上預取。

**預期效果**：曲間靜默從實測 2.9s 降到約 1.2–1.5s（只剩開流）；快取命中時降到約 1.2s。單曲循環與重試不再重打 API。

**階段 1 — 逾時預算（成本 S–M，風險中，可逆）**

5. `_waitForRequestOperation` 加 `timeout` 參數，`playMedia`/`setMedia` 用 T2；`selectPlayback` 用 T1。逾時視為 `PlaybackFault.timeout`，走既有的 fallback → 退避 → 通知鏈。
6. media_kit 側同步設 `network-timeout`（對照 Spotube 的 120s，FMP 建議更短，例如 30s）。
7. 三層重試改成共用一個「總預算」而非各自計數。

**階段 2 — 型別化錯誤（成本 M，風險中，可逆）**

8. `errorStream` 改成 `Stream<PlaybackFault>`，`PlaybackFault` 是 sealed class：`networkStall` / `networkFatal` / `mediaOpenFailed` / `audioDeviceUnavailable` / `decodeFailed` / `unknown(raw)`。
9. 字串比對**下沉到各後端實作內部**（每個後端只認得自己的詞彙），`AudioController` 只認型別。repo 內已有同型前例：`StreamOpenFailedException`（`audio_types.dart:54-58` 的註解明說它就是為了取代子字串比對）。
10. `audioDeviceUnavailable` 直接解掉 #41；`networkStall` 對應 6.1 的 `rebuffering`，不觸發 teardown。

**階段 3 — 位元組快取（成本 M–L，風險中，可逆但有資料面）**

11. 兩條路可選，見 §9 決策點 D3。

**階段 4 — 佇列語意與 gapless（成本 L，風險中高）**

12. `FmpAudioService` 加 `setQueue(List<PreparedPlaybackMedia>)` + `bool get supportsQueue`。just_audio 0.10.x 用 `setAudioSources(preload: true)`（Finamp redesign 的做法），media_kit 用 `mk.Playlist`（Spotube 的做法）。
13. gapless 隨之而來；crossfade **建議明確放棄**並寫進文檔 —— 四個對照專案裡三個明說不做，Auxio 的理由（timeline 模型）同樣適用於 ExoPlayer 路線。

### 6.4 統一為單一後端？—— 建議**不統一**，但要把平台知識收乾淨

**【建議】保留 just_audio(Android) + media_kit(Windows) 的雙後端，成本 S（維持現狀），風險低。**

理由（都有出處）：
- **media_kit 在 Android 快速切歌場景有已知的 dispose 效能問題**：issue #266 有留言稱單一 mpv instance 釋放記憶體可能等 40+ 秒。音樂播放器切歌頻繁，這是直接命中的風險。
- **二進位代價**：`media_kit_libs_android_audio` 每個 ABI 約 2.9–3.1 MB（v1.1.9 release asset 實測值），universal APK 粗估 +12MB。`pubspec.yaml:28` 的註解說當初選 just_audio 就是為了「更輕量，省 ~10-15MB 內存」—— 這個理由仍然成立。
- **反例存在且權威**：`namida`（⭐5.5K，跨平台音樂播放器，場景與 FMP 最接近）**音訊走自維護的 just_audio fork**，media_kit 只做影片渲染。不是所有人都往 media_kit 靠。
- **橋接方案風險更高**：`just_audio_media_kit` 由第三方 `Pato05` 維護，pub.dev 最新 2.1.0（2025-04-13）而 GitHub 最後 push 是 2026-04-27 —— **一整年的修正沒發版**；橋接後還會損失 ICY metadata、電話中斷處理、equalizer 等原生能力。

**但要做的是**：把「後端差異」從 `Platform.isX` 改成介面上的能力查詢（`supportsAudioDeviceSwitching` / `supportsQueue` / `emitsBufferingWhilePlaying`），並讓 `errorStream` 型別化。這樣「將來要不要統一」變成一個可以隨時再評估的局部決定，而不是一次性豪賭。

**替代方案（供決策）**：全面轉 media_kit（Harmonoid / Spotube / bili_you / pilipala 路線）。成本 **L**，風險中高，可逆性差（要改 `pubspec` + 一整套 Android 音訊焦點/通知整合）。收益是單一程式碼路徑、免費 gapless、Windows 裝置切換與 Android 對齊。**只有在階段 2 完成、錯誤已型別化之後才值得重新評估。**

### 6.5 Bilibili 海外加速 —— 建議**不做 mirror host 替換**

**【事實】實測反對這個方向**：本機打 `playurl` 拿到的三條音軌 baseUrl 全是 `upos-hz-mirrorakam.akamaized.net`（Akamai 海外），backup 是 `upos-sz-mirrorcosov.bilivideo.com`（騰訊雲海外）；1MB Range 下載 0.34s、3.08 MB/s、TTFB 300ms、connect 11ms（§12.4）。**API 已經在做地理調度，沒有可搶的餘量。**

**【推論】只有在以下情況才需要重新考慮**：使用者在中國大陸境內、或拿到 PCDN/MCDN 節點（`*.mcdn.bilivideo.cn:4483` / 純 IP:Port）。這時 BBDown（`Program.Methods.cs` 的 `HandlePcdn()`，預設 `ForceReplaceHost=true`）與 BiliRoamingX（`UposReplacer.kt`，只換 authority、query 不動、且**動態探測存活 mirror 而非寫死**）是可參照的實作。

**【建議】現階段做的是「觀測」而不是「替換」（成本 S，風險低，完全可逆）**：把解析出的 baseUrl host 記進 log/診斷頁，累積真實使用者的 CDN 分布，再決定要不要投入。已知風險：MCDN 特化連結缺 `trid` 參數不能簡單換 host；寫死的 mirror host 會隨時間失效。

---

## 7. 插件化可行性研究

### 7.1 法律面 —— 這是決定性因素，而且結論跟直覺相反

**【事實】把音源移出主 repo 並沒有保護到主 repo。** Tachiyomi 的時間線：

- 2024-01-02 Kakao Entertainment 發法律通知，要求刪除 app 全部版本與 GitHub 上所有 fork —— **儘管 app 本身不託管任何第三方內容，且 extension 早已在獨立 repo**。
- 2024-01-05 提供侵權站點清單，Tachiyomi 移除對應 extension，完全配合。
- 2024-01-09 移除 app 內建 extension 清單連結。
- 2024-01-13 核心貢獻者發布停止開發聲明，主 repo（含主 app 本體）與整個 org 數日內自願下架。

**【事實】Aniyomi 的對照組結果不同**：2024-06-17 Sony Pictures 一次 DMCA 移除 200+ extension，官方 extension repo 被清空，但 **app 本體未下架**。

**【推論】兩案的差別在於「出廠是否為空殼」**：Mihon 現行做法是 app 出廠不附帶任何 extension、也不內建任何官方 repo URL，使用者必須自行貼上第三方 repo。這讓 app 主體在架構論述上站得住腳，但**保護不了維護者個人與官方組織**。

**對 FMP 的意義【推論】**：FMP 的三個源都是版權敏感平台。如果插件化的動機是降低法律風險，那麼**有效的措施是「出廠空殼 + 不內建 repo URL」，而不是「把程式碼搬到另一個 repo」**。而「出廠空殼」意味著新使用者要自己找源才能用 —— 這是產品決策，不是技術決策。

### 7.2 技術路線比較

Flutter 無法動態載入 Dart 程式碼。五條可行路線（2026-08-30 快照）：

| 路線 | 現況 | 能力上限 | 對 FMP 三源的覆蓋 |
|---|---|---|---|
| **Mihon 式獨立 APK** | 成熟、API 演進無斷裂 | 完整 Kotlin | **不適用**：無 Windows 對應物，且與 Dart 單一程式碼庫不相容 |
| **`flutter_js`（QuickJS）**<br>**spike 見 §12.16（Windows）與 §12.19b（Android）**<br>**⚠ 第七輪下修** | 0.8.7，約 2026-01，⭐540 | fetch/XHR 橋接回 Dart（實測 452ms 搜尋 / 384ms 取流）；**沒有 WebCrypto，但插件可自帶加密庫**（實測 CryptoJS 4.2.0 在 QuickJS 內產出與 .NET 逐字元相同的 eapi params，0.47ms/次）；**Windows 桌面不需要額外建置任何東西**（`pub get` + `run -d windows` 即可）；沙箱乾淨（`require`/`process`/`std`/`os`/`WebAssembly` 全 undefined）。**Android 實測：JS 行為與沙箱邊界與 Windows 完全相同、加密輸出逐字相同、QuickJS `.so` 每 ABI 僅 0.72–1.05 MB；但套件本身開箱即壞** —— `android/build.gradle:34` 寫死 `jvmTarget = 1.8`、`:5` 是 Kotlin 1.7.20，Flutter 3.47 另警告 KGP 未來會被拒（§12.19b） | 已實測覆蓋 Netease 的 search + getAudioStream。`youtube_explode` 這類重依賴仍必須由宿主提供（處置見 §12.19d）。**上游停滯是本路線最大的風險** |
| **`hetu_script`** | pub.dev 停在 0.4.2+1（約 4 年），GitHub 更新到 2026-05 | 雙向 Dart 呼叫是主打 | async/HTTP 支援細節**未找到**；pub.dev 版本落後是風險 |
| **`dart_eval`** | 0.8.5（2026-05），⭐400 | **唯一有正式權限沙箱**（`runtime.grant()` + Filesystem/Network/ProcessRun）；不支援 extension methods / generators / mixins；**官方不建議載入外部 pub 套件** | 「不能用 pub 套件」直接卡死 DASH XML 解析與 HTTP —— 除非全部由宿主注入 |
| **WASM（`wasm_run` 0.2.0+2, 2026-07）** | Android + Windows 都支援 | 插件必須用 Rust/C/Zig 寫 | 整合門檻最高，且要求插件作者會寫 Rust —— 與「讓使用者用 AI agent 生插件」的目標直接衝突 |
| **外部程序 / HTTP sidecar** | **未找到任何已上線的 Flutter app 案例** | 完整（任何語言） | 跨平台分發與生命週期管理成本高 |

**【事實】Flutter 生態唯一已上線的可參照先例是 Mangayomi**（`kodjodevf/mangayomi`），而且它是**三引擎並存**：`flutter_qjs`（git ref，非 pub 版號）跑 JS、`d4rt ^0.2.4` 跑 Dart 直譯、外加 Mihon 相容橋接層。它的宿主**主動把加密原語暴露給插件**（`encryptAESCryptoJS` / `cryptoHandler`，近期 PR #732 加了 AES-GCM），而不是讓插件自己 import 加密庫。

【第四輪更正】§12.16 的 spike 證明「插件自帶加密庫」在 QuickJS 裡是**可行的**（CryptoJS 4.2.0，60KB，0.47ms/次，結果與 .NET 逐字元相同）。所以 Mangayomi 的做法是**設計選擇**（統一實作、省下每個插件 60KB、宿主能審計用了什麼演算法），不是技術限制。真正非留在宿主不可的是**網路策略**，見 §12.16 的但書。

**【事實】官方 extension repo `kodjodevf/mangayomi-extensions` 已於 2025-12-03 被作者本人 archive**，維護轉移到社群 fork。

~~**【事實】四個候選的 Flutter 音樂 app（Namida / BlackHole / Harmony-Music / Vibe）都沒有外掛式音源架構。** 若 FMP 走這條路，是該細分領域的先行者。~~

> **【第七輪更正 —— 這條是錯的】** 上一輪的候選名單漏了 **Spotube**，而它在 **v5.0.0（2025-09-11）** 就上線了完整的插件系統：Cash App 的 **Zipline**（Kotlin/JS → QuickJS）、`plugin.json` 宣告 capabilities、宿主提供 `HttpClientAPI` / `PersistedStorageAPI` / `CryptoAPI` / `WebviewAPI` / `SystemInfoAPI`、插件提供 `CoreAPI` / `MetadataSearchAPI` / **`AudioAPI`** / `LyricsAPI` / `ScrobbleAPI`、打包成 `.smplug`。**FMP 不是先行者，而且有一個同語言、同領域、已上線一年的對照組可以抄。** 完整拆解與三個專案的分發／信任模型對照見 §12.19(c)。

### 7.3 插件介面草案與「必須留在宿主」的清單

**【事實】必須是宿主原生 Dart/Flutter 的部分**（依 §2 的取證）：

| 項目 | 位置 | 為什麼不能下放 |
|---|---|---|
| Netease eapi（AES-ECB + MD5）/ weapi（AES-CBC ×2 + 手刻 RSA） | `netease_crypto.dart:51-89, 124-131` | 依賴 `crypto` + `encrypt` |
| Netease linux forum AES-ECB | `netease_playlist_service.dart:396-412` | pointycastle |
| Bilibili RSA-OAEP correspondPath | `bilibili_crypto.dart:14-60` | pointycastle + 手刻 DER |
| YouTube SAPISIDHASH | `youtube_credentials.dart:97-102` | `crypto` sha1 |
| **YouTube cipher / n-sig 解密** | 全在 `youtube_explode_dart` 內部（FMP 側零程式碼） | **唯一無法拆解的整體依賴** |
| WebView 登入 | `flutter_inappwebview`，三個 `*_login_page.dart` | platform channel |
| 憑證持久化 | `flutter_secure_storage` + Isar | platform channel |
| Netease 播放前逐跳重導向探測 | `media_handoff.dart:142-242` | `dart:io` HttpClient，需要 `followRedirects=false` + Range probe |

**【事實】可以宣告式描述的部分**：URL 辨識（Bilibili `parseId` 只是 `RegExp(r'BV[a-zA-Z0-9]{10}')`）、API 端點與 query（三源端點都是常數）、JSON → Track 的 path 映射、錯誤碼 → `SourceErrorKind` 的映射表（三源都是純數字/字串表）、品質等級映射、header 預設值、URL TTL、分頁規則。

**【事實】無法宣告式表達的複雜控制流**（不只是加密）：YouTube InnerTube continuation 分頁 + 防迴圈（`youtube_source.dart:2097-2231`）、新舊 schema 雙路徑分派（`:1699-1744`）、三層備援（`:386-414`）、Bilibili `-352` 換指紋重試（`:915-930`）。

**【推論】插件介面草案**：如果要做，最小可行的形狀是「腳本 + 宿主能力注入」：

```text
插件必須實作（對應生產真正用到的 8 個 capability）：
  meta:            { id, name, iconUrl, version, minAppVersion }
  urls:            parseTrackId(url) / isPlaylistUrl(url) / parsePlaylistId(url)
  search(query, page, pageSize)              -> SearchResult
  getTrackInfo(id, auth)                     -> Track
  getAudioStream(id, {cid, quality, auth})   -> AudioStreamResult
  getTrackDetail(id, auth)                   -> VideoDetail        [可選]
  getRanking(request)                        -> List<Track>        [可選]
  parsePlaylist(url, page, auth)             -> PlaylistParseResult[可選]
  mapError(rawResponse)                      -> SourceErrorKind

宿主注入給插件（插件不得自帶）：
  http.get/post(url, headers, body)          ← 走 SourceHttpPolicy，插件不碰 cookie 原文
  crypto.aesEcb / aesCbc / rsaOaep / sha1 / md5
  webviewLogin({url, successCookieNames})    ← 回傳 opaque token，插件看不到憑證
  storage.get/set(key)                       ← 命名空間隔離
  log.debug/warn
```

**「讓使用者用 AI agent 生插件」的可行性【推論】**：可行的前提是介面**小且穩定**。上面這個形狀約 10 個必實作方法 + 6 個注入能力，規模跟 Mihon 的 `HttpSource` 同級，是 AI 能穩定生成的量級。但要注意兩件事：
1. **必須有 schema 驗證與沙箱**（`dart_eval` 是唯一有正式權限模型的，但它不能用 pub 套件；`flutter_js` 沒有沙箱但能力更完整）—— 這是一個真實的取捨，沒有兩全的選項。
2. **prompt 範本必須附「宿主注入能力的完整簽章 + 3 個真實範例插件 + 一組可跑的驗證測試」**，否則 AI 生出來的插件會自己 import 不存在的套件。

### 7.4 建議順序

**【建議】先做「統一內建三源介面」的 tracer bullet，暫不外掛化。成本 M，風險低，完全可逆。**

具體是把 §2.2 的三個阻塞逐一解掉：
1. `SourceType` 從 enum 改成「內建常數 + 字串 id」的雙軌（Isar 存字串，i18n 有 fallback）。
2. `Settings` 的每源具名欄位改成 `Map<String, SourceSettings>`（**這是持久化格式的破壞性變更，需要 migration，要先問**）。
3. `ranking_cache_service.dart` 的 49 處硬編碼改成對 `registeredSourceTypes` 的迴圈。

做完這三件事之後，「要不要外掛化」才是一個能被單獨評估的問題 —— 而且不做外掛化，這三件事本身也讓「新增第四個內建源」從「改 20 個檔案」變成「加一個 adapter」。

**【第七輪補充】** 若之後真的要做外掛化，順序上要先釘死三件事（依據見 §12.19c/d）：

1. **YouTube 不進插件系統**，明說留在宿主。理由是 `youtube_explode_dart` 解的 signature cipher / n-param 會隨 YouTube 改版而變，而 §3.a 顯示這一段**現在就已經在退化**（P0-3）；把它交給插件作者維護只會讓壞掉時沒人能修。
2. **信任模型抄 Mihon**（repo 級簽章金鑰 + 逐版本 TOFU + 可撤銷），不抄 Spotube／Mangayomi 的「靠使用者自己小心」—— FMP 的插件會拿到帳號憑證（SESSDATA、MUSIC_U），風險等級不同。
3. **音源介面抄 Spotube 的兩段式**（先回候選 + confidence，再解析 URL）。這個形狀剛好就是 P0-3 需要的結構：把「有哪些候選」與「挑哪一個」分開。

---

## 8. 重寫 vs 漸進重構

**【建議】播放核心：漸進重構，不重寫。**

理由：
1. **拆分工作已經做了一半而且做得對**。`PlaybackRequestSession` / `PlaybackRecoveryCoordinator` / `StreamResolutionService` / `QueueManager` / `QueuePersistenceManager` 的邊界是清楚的，`lib/services/audio/AGENTS.md` 的 Ownership 段落與程式碼吻合。剩下的問題不是「結構錯了」，而是「三個具體的機制缺了」（快取、逾時、型別化錯誤）。
2. **這三個機制都能獨立加上**，而且每一步結束時 repo 都可運作 —— 符合 tracer bullet。
3. 重寫的風險極高：`audio_provider.dart` 承載了大量非顯而易見的邊界處理（seek 穩定化視窗、supersede 世代、premature completion、Mix load-more 競態），這些是踩過坑才有的程式碼，`test/services/audio` 也圍繞它建立。重寫會把這些全部變成未知數。

**唯一值得考慮「局部重寫」的是 `AudioController` 本體**（2998 行）：把 SMTC/通知協調、歌詞自動比對、播放歷史、Mix load-more 抽成獨立協作者。這是**搬移而非重寫**，成本 M，風險低（有測試網），可逆。

### 8.1 `AudioController` 拆分的具體切法（第四輪補上）

前面只說了「搬移而非重寫」，沒有給介面。這裡把它落到可以直接開工的粒度。

**先量現況**（`rg -c`，`audio_provider.dart`）：

| 責任叢集 | 出現次數 | 說明 |
|---|---|---|
| `state = state.copyWith(...)` | 55 | UI 狀態投影，散在每一個方法裡 |
| `_context`（`_PlaybackContext`） | 65 | 載入狀態機：`activeRequestId`、`isInLoadingState`、臨時播放上下文 |
| `_mix*`（Mix 無限歌單） | 33 | load-more 排程與競態守衛 |
| `_pendingSeek` / `_seekStabilization` / `_stabilizeSeek` | 22 | seek 穩定化視窗 |
| `_audioHandler.*`（Android 通知） | 15 | |
| `_windowsSmtcHandler.*`（Windows SMTC） | 10 | |
| `_usesMobileAudioHandler`（平台分支） | 8 | 這 8 處就是 P1-7 說的抽象洩漏 |
| `_playHistoryRepository` | 3 | |
| `_lyricsAutoMatchService` | 3 | |

**目標：`AudioController` 只留「命令轉發 + `PlayerState` 投影 + 接線」，其餘各自成為協作者。** 下面六個介面按「該不該現在做」排序。

---

#### A. `PlaybackEndReason` / `PlaybackTransportEvent` —— 最該先做，也是本輪所有實測的收斂點

這是 P0-5 / P1-3 / P1-4 / P1-9 / #41 的共同修法。現在 `FmpAudioService` 對上層只吐三種東西：`Stream<String> errorStream`、`Stream<void> completedStream`、`playerStateStream`。§12.14 的四格實測證明這不夠 —— 同一個網路條件下，兩個後端連「哪個通道會響」都不同。

```dart
/// 播放為什麼停下來。由「後端」負責把原生訊息翻譯成這個型別，
/// 而不是讓 AudioController 去比對字串。
sealed class PlaybackEndReason {
  const PlaybackEndReason();
}

/// 正常播完（position 已到 duration 附近）
final class EndedNaturally extends PlaybackEndReason {
  const EndedNaturally();
}

/// 引擎宣告結束，但明顯還沒播完（含 duration 未知的情況）
final class EndedPrematurely extends PlaybackEndReason {
  const EndedPrematurely({required this.at, this.expected, required this.bytesReceived});
  final Duration at;
  final Duration? expected;   // null = 引擎從未回報 duration（§12.14e 的情況）
  final int? bytesReceived;   // 0 = 開了流但沒有資料
}

/// 傳輸層失敗：連線中斷、逾時、DNS、TLS
final class TransportFailed extends PlaybackEndReason {
  const TransportFailed({required this.kind, this.httpStatus, required this.raw});
  final TransportFailureKind kind;  // reset / timeout / dns / tls / refused
  final int? httpStatus;            // 403 = URL 過期，見 §12.14c
  final String raw;                 // 保留原文供 log，但不再是判斷依據
}

/// 音訊「輸出」失敗 —— 跟媒體本身無關。這一條就是 #41。
final class OutputDeviceFailed extends PlaybackEndReason {
  const OutputDeviceFailed({required this.raw});
  final String raw;
}

/// 媒體本身開不起來（格式、解碼器、404）
final class MediaUnopenable extends PlaybackEndReason { ... }
final class DecoderFailed extends PlaybackEndReason { ... }
```

對應改 `FmpAudioService`：

```dart
// 取代 errorStream + completedStream
Stream<PlaybackEndReason> get endReasons;
```

**兩個後端各自負責翻譯**，而且翻譯規則寫在它自己旁邊（有本輪的實測當測試案例）：

- `MediaKitAudioService`：`completed` + `position` 遠小於 `duration` → `EndedPrematurely`；`duration == null` 且 `bytesReceived == 0` → `EndedPrematurely(expected: null, bytesReceived: 0)`；含 `could not open/initialize audio device` → `OutputDeviceFailed`（**這一行就修掉 #41**）；`tcp:` / `ffurl_*` → `TransportFailed`。
- `JustAudioService`：`PlatformException(0, Source error, ...)` → `TransportFailed(kind: reset)`；`Loading interrupted` → 忽略（是 supersede 不是錯誤）。

【建議・成本 M・風險低・可逆】這一項可以獨立完成、獨立測試，而且它把 `audio_provider.dart` 的 `_isStringNetworkError` / `_isStringMediaOpenError` / `_isRetryableError` / `_syntheticSourceDiagnostics`（合計約 120 行）整段刪掉。

---

#### B. `NowPlayingPublisher` —— 收掉 8 處平台分支，順便修 #40

```dart
/// 對外（系統通知列 / SMTC / 媒體鍵）發佈「現在在播什麼、能做什麼」。
abstract interface class NowPlayingPublisher {
  /// 綁定命令入口。實作把系統送來的媒體鍵轉成這些呼叫。
  void bind(PlaybackCommandSink sink);

  void publishMetadata(Track track, {Duration? duration, String? artworkUrl});
  void publishState({
    required bool playing,
    required Duration position,
    required LoopMode loopMode,
    required bool shuffleEnabled,
  });

  /// #40 的修法：能力隨模式變動，而不是建構時寫死。
  /// 電台模式下 next/previous 應為 false；後端不支援 seek 時 canSeek 為 false。
  void publishCapabilities(PlaybackCapabilities capabilities);

  Future<void> dispose();
}

class PlaybackCapabilities {
  const PlaybackCapabilities({
    required this.canSkipNext,
    required this.canSkipPrevious,
    required this.canSeek,
    required this.canShuffle,
    required this.canRepeat,
  });
}
```

兩個實作：`AudioServiceNowPlaying`（包 `FmpAudioHandler`）、`WindowsSmtcNowPlaying`（包 `WindowsSmtcHandler`）。`AudioController` 只持有 `NowPlayingPublisher`，`_usesMobileAudioHandler` 的 8 處分支消失；`main.dart` 依平台注入哪一個實作。

**與 §11 #40 的關係**：`publishCapabilities` 是「電台時 next/prev 死鍵」的正解 —— 進電台時發 `canSkipNext: false`，離開時發 `true`。而 `canSeek/canShuffle/canRepeat` 在 Windows 實作裡目前只能一律 false（`smtc_windows` 1.1.0 沒 export 那些事件，§12.13），但介面上先誠實宣告，等上游支援時只改一個實作。

【建議・成本 S–M・風險低・可逆】

---

#### C. `PlaybackSessionCoordinator` —— 把 `_context`（65 處）整包搬走

`PlaybackRequestSession` 已經擁有「請求世代 / supersede / 鎖」，但**載入狀態**（`_PlaybackContext.activeRequestId`、`isInLoadingState`、`_startSessionLoadingState` / `_exitLoadingState` / `_resetLoadingState` / `_resetSourceErrorLoadingState` / `_clearMatchingSessionLoadingContext`）還留在 controller，兩邊靠回呼互相拉扯（見建構子裡的 `onLoadingFinished` 閉包）。

```dart
abstract interface class PlaybackSessionCoordinator {
  /// 唯一的播放入口。逾時、supersede、fallback 都在裡面。
  Future<PlaybackOutcome> start(PlaybackIntent intent, {required Duration budget});
  Future<void> cancel();
  Stream<PlaybackSessionState> get states;  // idle / resolving / opening / ready / failed
}
```

**順便把 P0-2 的逾時放在這裡**：`budget` 是唯一一個「多久算太久」的定義點，解析、開流、fallback 共用同一份預算（也就解掉 P2-15 的三層重試無共同預算）。

`_pendingSeek` / `_seekStabilizationWindow`（22 處）跟著搬 —— 它們本來就只在「一次播放請求的生命週期內」有意義。

【建議・成本 M–L・風險中・可逆但需要測試同步更新】

> **【第十輪執行 —— 介面未採用，逾時那一項早已完成】** 開工查證推翻了這一節的三個
> 前提，見 05 §6.7：
>
> 1. **「順便把 P0-2 的逾時放在這裡」已經做完了。** `PlaybackTimeoutBudget`
>    （`app_constants.dart`）就是這裡說的單一定義點，`PlaybackRequestSession`
>    的 `_requestDeadline` / `_withBudget` / `_remainingBudget` 已經把解析、開流與
>    fallback 綁在同一份預算上（commit `262657bc` + `591cb2b0`），四條測試釘住。
> 2. **上面這個介面就是 `PlaybackRequestSession`。** 它已經有 `start` / `restore` /
>    `cancelActive` / `isSuperseded` 與逾時，再造一個叫 `PlaybackSessionCoordinator`
>    的類別只會變成「兩個都叫 session 的東西」；而 `Stream<PlaybackSessionState>`
>    只有一個消費者（controller 自己）。
> 3. **`_context` 不是一包東西。** `_PlaybackContext` 裝的是播放模式、載入閂存、
>    臨時播放快照三件無關的事，整包搬會把另外兩件拖進去。
>
> 落地的是：`PlayMode` 變成 `AudioController` 的普通欄位；臨時播放快照交給既有的
> `TemporaryPlayHandler`；**載入閂存與延後 seek 合成 `PlaybackHandoffGate`** ——
> 這兩者在既有程式碼裡的 11 個寫入點沒有一次是分開改的。

---

#### D. `PlaybackObserver` —— 把副作用從播放路徑上摘下來（歷史 / 歌詞 / Mix）

現在 `_updatePlayingTrack(track, recordHistory: true)` 在播放路徑上同步觸發播放歷史寫入與歌詞自動比對；Mix 的 load-more 也掛在 `_triggerMixLoadMoreIfNearQueueEnd`。這些都不該讓播放等它們。

```dart
abstract interface class PlaybackObserver {
  void onTrackStarted(Track track);
  void onTrackEnded(Track track, PlaybackEndReason reason);
  void onQueuePositionChanged({required int index, required int length});
}
```

三個實作：`PlayHistoryObserver`、`LyricsAutoMatchObserver`（帶自己的 requestId 去重，把 `_lyricsAutoMatchRequestId` 搬走）、`MixPrefetchObserver`（把 33 處 `_mix*` 搬走）。`AudioController` 只保留一個 `List<PlaybackObserver>` 並在狀態轉換時廣播。

【建議・成本 M・風險低・可逆】

> **【第九輪執行 —— 介面未採用，三個具體協作者取而代之】** 開工查證推翻了這一節的兩個前提，見 05 §6.6：
>
> 1. **「這些都不該讓播放等它們」的前提已經成立。** 三者當時都已是非阻塞（`Future.microtask` / `unawaited` ×2）。唯一 `await` 的是 `_advanceAfterPendingMixLoadMore()`，那是刻意的且被測試鎖住，**不能**拿掉。
> 2. **上面這個介面三個方法只有一個有人實作。** 三者都只掛「播放請求成功」一個事件，`onTrackEnded` / `onQueuePositionChanged` 零實作；而且 Mix 必須對外曝露進行中的 `Future` 供隊尾等待，回傳 `void` 的 observer 做不到。
>
> 落地的是 `PlayHistoryRecorder`、`LyricsAutoMatchCoordinator`、`MixSessionCoordinator` 三個具體類別，無共用介面、無廣播清單，形狀照 `QueueCommands` / `NowPlayingPublisher`。

---

#### E. `QueueCommands` —— 佇列命令從 controller 分離

`addToQueue` / `addAllToQueue` / `addNext` / `removeFromQueue` / `moveInQueue` / `shuffleQueue` / `clearQueue` / `playAt` 目前是 controller 的方法，內部都是「呼叫 `QueueManager` → 更新 state → 通知 persistence → 發 `onQueueStateChanged`」的同一套樣板。抽成一個 façade 後，controller 只轉發。

【建議・成本 S・風險低・可逆】—— 這是六項裡最容易先做的一項，可當熱身。

---

#### F. 拆完之後的 `AudioController`

只剩四件事：
1. 把 `PlaybackSessionState` + `QueueState` + `PlaybackEndReason` 投影成 `PlayerState`（55 處 `copyWith` 收斂到一個 `_project()`）。
2. 轉發 transport 命令。
3. 轉發 queue 命令。
4. 接線（誰訂閱誰）。

**估計 400–600 行**，相對現在的 2998 行。

**建議順序（tracer bullet，每一步結束 repo 都可運作）**：E（暖身）→ A（收斂本輪所有實測）→ B（修 #40、收平台分支）→ D（摘副作用）→ C（最大、最後做，因為它會動到 seek 與逾時語意）。

**不建議一次做完。** A 完成後就該重跑 §12.14 的兩個受控實驗當回歸測試 —— 那兩個腳本（`stallsrv.py` / `holdsrv.py`）本身值得收進 repo 的 `test/manual/` 或 `scripts/`，因為它們是目前唯一能穩定重現症狀 b/c 的手段。

---

**【建議】音源層：漸進重構，而且優先級低於播放核心。**

音源層的抽象品質已經不錯（§2.1），問題集中在「registry 外圍的硬編碼」而不是 registry 本身。§7.4 的三件事是有界的工作。

---

## 9. 需要你決策的點

> 先列出，本輪不問。

**D1 — 逾時預算的具體數值。** 解析階段 T1、開流階段 T2、緩衝耗盡 T3 各設多少？Spotube 用 libmpv `network-timeout=120`（偏保守）；Finamp 的 HTTP 層是 10s。我的傾向是 T1=8s / T2=10s / T3=20s，但這直接影響「網路差時是等還是跳」的體感，需要你定調。

**D2 — 逾時之後做什麼？** 三個選項：(a) 跳下一首（Auxio/Symphony 做法）(b) 停下並通知使用者（Finamp `maxSkipsOnError:0`）(c) 換 fallback 串流再試一次才放棄。三種語意差很多。

**D3 — 位元組快取走哪條路？**
> 第二輪的新事實改變了這題的前提：**FMP 在 Android 上其實已經跑著一個本機 HTTP 代理**。只要傳自訂 header，just_audio 就會啟用 `_ProxyHttpServer`，而 FMP 每次都傳 Referer + User-Agent —— 斷網實測的 stack trace 直接證明了這一點（§12.9）。所以 (a) 和 (b) 的差別不是「要不要引入代理」，而是「用上游那個、還是自己寫一個」。
- **(a) just_audio `LockCachingAudioSource`**：成本 S，用的正是已經在跑的那個 proxy；但只有 Android 有；仍標 `@experimental`；有未解的 Range/恢復類 issue（#1425/#1435 來源缺 `accept-ranges` 時 position 歸零、#594 網路錯誤後無法恢復）。另外實測顯示上游那個 proxy 的錯誤處理不完整（`SocketException` 會逃逸成未捕捉的非同步錯誤）。
- **(b) 自建 loopback HTTP 代理**（Spotube 路線，`HttpServer.bind(loopbackIPv4, 0)`）：成本 M–L，跨平台一致，同時解掉「URL 過期」與「快取」；坑是 Android process 被殺後 server 消失（需 foreground service）、cleartext 需配置 `network_security_config.xml`。
- **(c) 先不做快取，只做 URL 快取（階段 0）**：成本 S，收益已經很大（實測省 1.25–1.74s/次），但不解決「同一首歌重播要重下位元組」。

**D4 — 是否升級 just_audio 0.9.40 → 0.10.6？** 0.10.x 才有 `setAudioSources(preload:)`（gapless 的前提，Finamp redesign 用的就是它）。但這是 pre-1.0 的破壞性升級，且 0.10.x 目前有 open issue #1486（release build 無聲音，維護者本人在處理）。**建議先讀 0.10.0 的 CHANGELOG 評估破壞面，再決定要不要在階段 4 之前升。**

**D5 — 插件化的動機是什麼？** 如果是「降低法律風險」，§7.1 的證據顯示有效措施是「出廠空殼」這個產品決策，而不是技術架構。如果是「讓使用者自己加源」，那 §7.4 的內建介面統一是必要前置。這兩個動機導向的方案完全不同。

**D6 — `Settings` 每源欄位改成 map 是持久化格式的破壞性變更**，需要 migration，且 `backup_service` 的格式也要跟著改。要不要做、什麼時候做。

**D7 — crossfade 要不要明確放棄並寫進文檔？** 四個對照專案裡三個明說不做。我傾向放棄，但這是你的產品決定。

**D8（第六輪新增）— Netease 的播放前預檢／媒體憑證機制要刪還是要修？** 第六輪實測 eapi 回的是 `http://`，而閘門要求 https，所以這整套（`media_handoff.dart:142-242` 的 preflight 迴圈、`NeteasePlaybackRedirectResolver` 注入點、`mediaHeaders` 的 Cookie 分支）在生產環境一次都不會執行，而測試把它們全測成會執行（§12.18d）。三個選項：**(a) 刪掉**——若確認媒體位元組不需要 Cookie（音質已在 eapi 解析當下由帳號決定，那一步的 Cookie 有送），成本 S，收益是少 ~150 行死碼與一組假覆蓋率；**(b) 保留但把測試改成用真實的 `http://` URL 形狀**，讓測試誠實反映「這段不會跑」，成本 S；**(c) 改成在 http 上也能運作**——**不建議**，那等於允許把工作階段 Cookie 送上明文連線。**不可以用「放寬 https 檢查」當作修法。**

> **【第八輪已執行 —— 選了 (a) 刪除，commit `c09aec10`】** 實際刪掉的範圍比原本估的大：preflight 迴圈、`NeteasePlaybackRedirectResolver` 注入點（連同 `source_auth_context.dart` 那一層的轉接）、`canAttachNeteaseMediaCredentials`、`mediaHeaders` 的 `authHeaders` / `requestUrl` / `includeCredentials` 三個參數、`MediaHandoffResult.credentialsIncluded`（只寫不讀）、以及零呼叫端的 `downloadMediaHeaders`。**淨刪 547 行**（20 檔，+205/−752），其中 10 條測試隨機制一起消失 —— 它們測的正是那段跑不到的程式碼。
>
> `mediaHeaders` 現在只收 `SourceType`：**憑證邊界由函式簽章保證，不再是執行期檢查**，沒有任何參數可以讓呼叫端把 Cookie 傳進來。
>
> 實機複驗（Windows，已登入 Netease）：Netease `playing=true pos=0:00:05.940843 err=null`、YouTube `playing=true pos=0:00:07.950194 err=null`，兩者的 header 都是 `Origin, Referer, User-Agent`。1234 條測試全過。
>
> **【第七輪傾向 (a)】** 已登入帳號的實測（§12.19a）補齊了最後一塊：真實簽名 URL **0 跳轉**（preflight 就算跑也找不到東西可跟），且**登入狀態下 Cookie 一樣被剝掉而播放正常** —— 也就是媒體位元組確實不需要憑證。三個問號都指向刪除。

---

## 10. Quick wins

只記錄，本輪不動手。全部成本 S、風險低、完全可逆。

| # | 事項 | 位置 |
|---|---|---|
| Q1 | `resolvePrimary` 加 `hasValidAudioUrl` 短路（復活死掉的 `SourceManager.needsRefresh` 語意） | `stream_resolution_service.dart:106-135`；`source_provider.dart:140-146` |
| Q2 | 預取改 `persist: true` 且不傳 `copy()` | `playback_request_session.dart:734`；`stream_resolution_service.dart:219-240` |
| Q3 | `AudioStreamResult` 加 `cid`，`_applyStreamResult` 回寫 `track.cid` | `base_source.dart:101-127`；`stream_resolution_service.dart:262-285` |
| Q4 | `_executeQueueRestore` 補上預取呼叫 | `playback_request_session.dart:595-668` |
| Q5 | Netease 讀 API 回的 `expi` 當 `expiry`，別只寫 log | `netease_source.dart:173, 184, 192` |
| Q6 | Bilibili 從 URL query 的 `deadline` 算 expiry（實測精確：7178s ≈ 1.99h） | `bilibili_source.dart:416, 459` |
| Q7 | `_isStringNetworkError` 移除過寬的 `'host'` | `audio_provider.dart:2442` |
| Q8 | `_resolveRemotePrimary` 的重試延遲換成專屬常數（現在借 `queueSaveRetryDelay`） | `stream_resolution_service.dart:170` |
| Q9 | 刪死碼：`SourceManager.parseUrl/parsePlaylist/refreshAudioUrl/isPlaylistUrl/needsRefresh` + `parseUrlProvider`/`parsePlaylistProvider`（若 Q1 不復活 `needsRefresh`）；`WindowsSmtcHandler.enable/disable/dispose` | `source_provider.dart:103-146, 210-221`；`windows_smtc_handler.dart:299-329` |
| Q10 | 刪 `mobilePlayerBufferSizeBytes` 與其不可達的平台分支 | `media_kit_audio_service.dart:20, 160-162` |
| Q11 | `AudioController.dispose()` 補 `_windowsSmtcHandler.dispose()`（目前沒呼叫） | `audio_provider.dart:497-520` |
| Q12 | `lib/data/sources/AGENTS.md:122-125` 補齊 11 個 capability | 文檔 |
| Q13 | `lib/services/audio/AGENTS.md` 的 buffer profile 段更正：`_configureForAudioOnly` 無平台判斷；補上未記載的 4 項 property | 文檔 |
| Q14 | `.claude/skills/verify-on-device/SKILL.md` 加**四條**限制：① 模擬器音訊播放約 1.68x 快於實際時間（§12.5）② AVD 的 DNS 每次查詢約 1 秒且不快取，任何 per-request 延遲量測都被它污染（§12.8）③ `adb emu network speed` 只作用於行動網路介面，裝置在 Wi-Fi 上時無效，要斷網用飛航模式 + `svc wifi/data disable`（§12.9）④ Windows 端 run terminal 被 AXTree spam 洗到不可讀（600 行只剩 1 行有效），只能靠 UI 截圖；且必須「先抬前景（ALT + `AttachThreadInput` + `SetForegroundWindow`）→ 驗證 `GetForegroundWindow()` → 才送動作」，否則點擊會落到使用者其他視窗（§12.11、§12.13e）⑤ **驗證 Windows 媒體控制不要截系統浮出視窗**，用 WinRT 的 `GlobalSystemMediaTransportControlsSessionManager` 直接讀寫 FMP 自己的 session（§12.13），既精確又不碰使用者其他視窗；需用 `powershell.exe` 5.1，PS7 的 WinRT 投影不完整⑥ **Windows 端優先用 VM Service `evaluate`（走 WebSocket）而不是截圖**：可以把 `AppLogger` 的毫秒級 log 整包取出、對活著的物件呼叫私有方法、在進程內起獨立後端做受控實驗，全程不動程式碼也不送輸入事件（§12.14a）。第四輪的 Windows 驗證幾乎全部靠這個完成，比前三輪的截圖流程快一個量級且沒有誤擊風險 | 文檔 |
| Q15 | `netease_source.dart:8` 的反向 import（`lib/data/` → `lib/services/`）搬到 `lib/data/sources/` 下 | `netease_source.dart:8` |
| Q16 | `AppLogger.setMinLevel()`（`logger.dart:129`）全 repo 零呼叫點 —— 要嘛接到開發者選項上（順便讓 profile/release 可觀測），要嘛刪掉 | `logger.dart:56, 129` |
| Q17 | YouTube 的 auth 升級改成「同一 streamType 先匿名、失敗再帶 auth」，而非現在的「所有 streamType 匿名跑完再整批帶 auth」 | `youtube_source.dart:387-415` |
| Q18 | `just_audio` 的 `_ProxyHttpServer` 在網路失效時把 `SocketException` 洩漏成未捕捉的非同步錯誤（§12.9）。FMP 側可加 `AudioSource` 層的錯誤處理，或升級 just_audio 後複測 | 上游 `just_audio.dart:3369, 2159` |
| Q19 | SMTC timeline 宣告與能力自相矛盾：`IsPlaybackPositionEnabled=False` 卻發佈 `MaxSeekTime = EndTime`（§12.13a）。把 `_updateTimeline()` 的 `minSeekTimeMs`/`maxSeekTimeMs` 收成 0，或等能接 seek 事件時再放出來 | `windows_smtc_handler.dart:267-285` |
| Q20 | `WindowsSmtcHandler` 完全沒有 shuffle / repeat 處理（`rg` 零命中），但 SMTC 宣告 `IsShuffleEnabled=True` / `IsRepeatEnabled=True`，實測請求是 no-op。Android 的 `FmpAudioHandler` 有完整實作可對照 | `windows_smtc_handler.dart`（缺）；`audio_handler.dart:41-42, 199-208`（對照） |
| Q21 | 加一份 `scripts/smtc_probe.ps1`（本輪 `scratchpad/smtc.ps1` 的整理版）到 repo：讀 SMTC 旗標與 timeline 不需要截圖、不碰使用者其他視窗，是驗證 Windows 媒體控制最乾淨的手段 | 新檔 |
| Q22 | `_isVipRequiredStreamError` 的 `flag & 4` 規則把 Netease 的 `code=404`（未登入）誤判成付費歌曲。最小修法：`fee == 0` 時不採信 `flag`，並把 `code` 分支提到 VIP 判斷之前；順便讓「未登入且拿不到 URL」對應到已存在的 `SourceErrorKind.loginRequired` | `netease_source.dart:877-931, 952-972` |
| Q23 | `_shouldHandleTrackCompleted()` 的 `duration == null` 直接 `return true`，等於在「時長未知」時關掉 premature 保護 —— 而「時長未知」正是串流開不起來的典型徵狀。改成：duration 未知時以「實際播放時間 < N 秒」判定為異常結束 | `audio_provider.dart:2998-3001` |
| ~~Q24~~<br>**（第八輪已修）** | ~~`MediaKitAudioService.playUrl` 在拿不到 duration 時仍記 `URL loaded successfully`~~ —— **已降級為 warning**（commit `ecbaeb91`）。實機以本機零位元組伺服器觸發確認：`[W] URL opened but the engine never reported a duration` | `media_kit_audio_service.dart`；實測見 §12.22 |
| Q25 | `StreamResolutionService` 與 `AudioStreamManager` **一行 log 都沒有**（`rg` 零命中），而它們正是整條路徑上最慢的一段。補上「開始解析／解析完成／耗時」三行，`AppLogger` 的毫秒時間戳就能直接量出各階段成本 | `stream_resolution_service.dart`、`audio_stream_manager.dart` |
| Q26 | `docs/debugging-with-vm-service.md` 補一節「表達式求值」：`evaluate` 走 HTTP 會回 `No compilation service available`，必須走 WebSocket；並記下三個用法（倒 `AppLogger.logs`、用 `getInstances` 對活物件呼叫私有方法、在進程內起獨立後端做受控實驗）。可直接收錄 `scratchpad/vmsws.js` / `vmeval.js` | 文檔 + 新檔 |
| Q27 | Bilibili 被風控（HTTP 412 / `-412 request was banned`）時，`view` 與 `playurl` 兩個請求相隔 3ms 連打、完全沒有退避 | `bilibili_source.dart:264-268`；實測 §12.14(b) |
| ~~Q28~~ | ~~log 一次 URL scheme 來判斷 preflight 會不會被觸發~~ **第六輪已直接得到答案（`http://`），此項作廢**；該做的變成一個決策：把死掉的 preflight／憑證機制**刪掉**，還是改成在 http 上也能用的形式（見 §12.18d 的三層解讀） | 實測見 §12.18(d) |
| Q29 | `MediaKitAudioService` 對 mpv 的 audio-output 失敗沒有專屬處理：`Could not open/initialize audio device` 被 `_isStringMediaOpenError` 當成媒體錯誤（#41），而 `AO: [wasapi] init failed` / `Failed to initialize audio device` 兩邊都不中、直接消失 | `audio_provider.dart:2975-2980`；實測 §12.15(b) |
| Q30 | `.claude/skills/verify-on-device/SKILL.md` 再加一條：**Windows 上任何要跑 CMake/MSVC 的暫存專案不能放在深層 scratchpad 路徑**（實測 CMake TryCompile 直接 `DirectoryNotFoundException ... .tlog`），改用 `%TEMP%\<短名>`；另外**跑 `flutter build/run --profile` 前要先確認沒有其他 `fmp.exe` 在跑**，否則 INSTALL 步驟會因為檔案被鎖而以 `MSB3073` 失敗（§12.17a） | 文檔 |
| Q31 | `stallsrv.py` / `holdsrv.py`（本輪唯一能穩定重現症狀 b/c 的手段）收進 repo，例如 `test/manual/` 或 `scripts/`，並在 `lib/services/audio/AGENTS.md` 指向它們 | 新檔 |
| ~~Q32~~<br>**（第八輪已修）** | ~~修掉 `AGENTS.md` 與 `docs/debugging-with-vm-service.md` §3.5–3.6 那句「`dart:io` HTTP profiling 對 FMP 不能用，不要浪費時間」** —— 實測在 profile build 上完全可用，而且給到逐階段時間軸 + 完整 header/body（§12.20d）。這條敘述現在正在主動阻止 agent 使用本專案最需要的觀測工具~~ —— **已修**（commit `d0282a25`）。改寫前補驗了 socket 與檔案兩項：先啟用再產生流量後，`getSocketProfile` 回 2 條 tcp 連線含收發位元組數，`getOpenFiles` 在刻意持有一個 `File` 後也正確列出 —— 三項全部可用 | `AGENTS.md`、`docs/debugging-with-vm-service.md` §3.5–3.6 |
| ~~Q34~~<br>**（第八輪已修）** | ~~隊列播到最後一首（`LoopMode.none`）之後，`Track completed` 每秒重複觸發（Android 實測 82 次）~~ —— **已修**（commit `ecbaeb91`）：隊列耗盡時暫停。Windows 實機複驗 `completedCount=1 noNext=1`，位置保留在結尾 | `audio_provider.dart` 的 `_checkPositionForAutoNext` 與 `_onTrackCompleted` 的 `No next track available` 分支；實測 §12.21(d) |
| ~~Q33~~<br>**（第八輪已實作）** | ~~`MediaKitAudioService` 目前只訂閱 `player.stream.error`，而 media_kit 的 `errorController` 有 prefix 白名單（`real.dart:2085-2117`），**`ao` 不在名單裡** —— 音訊輸出層的失敗訊息有一半根本到不了 FMP。改成同時訂閱 `player.stream.log` 並自己判斷 prefix~~ —— **已隨 §8.1(A) 一起做掉**（§12.21b） | `media_kit_audio_service.dart`；實測 §12.20(a) |

---

## 11. issue #40 / #41 / #42 的裁決

### #40 — Windows SMTC 兩個無法作用的控制項

**根因描述：大部分證實，一處需修正。**

| 子論點 | 判定 | 證據 |
|---|---|---|
| `SMTCConfig` 建構時寫死、之後從不更新 | **證實** | `windows_smtc_handler.dart:96-104`；`rg 'updateConfig\|setIsNextEnabled\|setIsPrevEnabled' lib/ test/` **零命中** |
| `radio_controller.dart` 的 `_updateSmtc()` 只設 callback = null | **證實**（實際行號 `:362-377`） | `:370-372` 設三個 callback 為 null，無 config 更新；分發在 `windows_smtc_handler.dart:117-138`，null 時靜默 no-op |
| `_updateTimeline()` 發佈完整 seek 範圍 | **證實** | `:279-280` `minSeekTimeMs: 0, maxSeekTimeMs: durationMs` |
| 「smtc_windows 收不到 seek 請求」 | **部分證實 —— 表述要改** | smtc_windows 1.1.0 的 Rust FFI **有** `smtcPositionChangeRequestEvent`（`lib/src/rust/api/api.dart:58-61`），但 `lib/smtc_windows.dart` 只 `export 'src/smtc_windows_base.dart' show SMTCWindows;`，`api.dart` **未被 export**，且 `PressedButton` enum 沒有 seek 成員。正確表述是：**套件底層支援，1.1.0 的 Dart wrapper 沒接出來** |
| `onSeek` 是死碼 | **證實** | 賦值僅 `audio_provider.dart:1603` 與 `radio_controller.dart:372`；**呼叫點零**；`_setupButtonListener`（`:116-138`）的 switch 無對應分支 |
| `enable()`/`disable()`/`dispose()` 無呼叫點 | **證實** | 定義於 `:299-329`；全域 grep 零命中；`AudioController.dispose()`（`:496-519`）也沒呼叫 |

**額外發現（issue 未提）**：`restoreMediaControlOwnership()`（`audio_provider.dart:986-989`）無條件呼叫 `_setupAudioHandler()` **和** `_setupWindowsSmtc()`，繞過了 `initialize()` 時的平台守衛 —— Windows 上電台停止後會執行整套 Android `FmpAudioHandler` 的綁定。

**另外**：`WindowsSmtcHandler` 完全沒有處理 shuffle / repeat，儘管 smtc_windows 提供 `shuffleChangeStream` / `repeatModeChangeStream` 與 `setShuffleEnabled` / `setRepeatMode`（`smtc_windows_base.dart:102-103, 261-275`），而 Android 的 `FmpAudioHandler` 有（`audio_handler.dart:203-213`）。**Windows 與 Android 的系統媒體控制能力不對等，與 seek 缺口同源。**

**【裁決：併入重構】** —— 目標架構的 `MediaControlSurface`（§6.2）本來就要求「系統媒體控制介面帶能力宣告」，#40 的兩個症狀都是「能力宣告與實際能力不符」的實例，會被自然解決。但 `enable/disable/dispose` 三個死方法與 `onSeek` 死碼可以現在就刪（Q9）。

**第三輪：兩個症狀都已在 Windows 上實機證實，而且「兩個」其實是「四個」。**（完整記錄見 §12.13）

不靠截系統浮出視窗，改用 WinRT 的 `GlobalSystemMediaTransportControlsSessionManager` 直接讀 FMP 對外發佈的 SMTC session，並主動送控制請求 —— 這比看畫面更精確，而且完全只讀使用者的 FMP session。

**症狀一（電台上／下一首是死鍵）—— 證實。** 在暫時新增的 B 站直播間播放中（測完已刪除，見 §12.13）：

```
PlaybackStatus            = Playing
Controls.IsNextEnabled    = True     ← 電台中仍宣告可用
Controls.IsPreviousEnabled= True     ← 同上
TrySkipNextAsync()      → True，4 秒後 title/artist/status 完全未變
TrySkipPreviousAsync()  → True，4 秒後 title/artist/status 完全未變
```

對照組：一般佇列播放時同樣送 `VK_MEDIA_NEXT_TRACK`，曲目確實從 `TV NCOP` 切換（§12.11）。**所以通道是活的，死的是電台模式下的 callback，而 config 沒有跟著關。** 而 FMP **自己的** UI 在電台模式下是正確的 —— mini player 已把上／下一首換成循環/重新整理（截圖 §12.13），只有 SMTC 沒跟上。

**症狀二（進度條）—— 機制推論被推翻，但結論仍然成立。**

```
Controls.IsPlaybackPositionEnabled = False      ← ★ 與 issue 的推論相反
Timeline.EndTime      = 00:04:06.131
Timeline.MaxSeekTime  = 00:04:06.131            ← 仍發佈完整 seek 範圍
TryChangePlaybackPositionAsync(00:03:00) → True
   position 前 00:00:30.100 → 後 00:00:30.100（3 秒後）
```

- issue 推測「發佈完整 timeline ⇒ Windows 畫出可拖曳的條」。**實際上 `IsPlaybackPositionEnabled` 是 `False`** —— 那才是 Windows 用來決定進度條能不能拖的旗標，而 `smtc_windows` 1.1.0 根本沒有把它打開的手段。所以 Windows **本來就不會**畫可拖曳的條。
- 但「送出 seek 請求會被靜默丟棄」**證實了**：OS 回傳 `True`（請求已送達），位置紋風不動。`onSeek` 是死碼這件事因此從讀碼推論升級為行為事實。
- 仍然存在的不一致：**宣告「不支援 seek」卻發佈完整的 `MinSeekTime`/`MaxSeekTime`**。這是該收掉的（issue 提的第二條路徑）；而「送 upstream PR 讓套件轉發事件」那條路的前提（Windows 已經畫了可拖曳的條）並不成立。

**新增：其實是四個死控制項，不是兩個。**

```
Controls.IsShuffleEnabled = True
Controls.IsRepeatEnabled  = True
TryChangeShuffleActiveAsync(true) → True，FMP 的 shuffle 按鈕仍是關閉狀態（截圖 §12.13）
GetPlaybackInfo().IsShuffleActive = （空值，FMP 從未回報）
```

【事實】`rg 'shuffle|repeat' lib/services/audio/windows_smtc_handler.dart` **零命中**，而 Android 的 `FmpAudioHandler` 有完整實作（`audio_handler.dart:41-42, 199-208`）。`smtc_windows` 提供 `shuffleChangeStream` / `repeatModeChangeStream` 與 `setShuffleEnabled` / `setRepeatMode`（`smtc_windows_base.dart:102-103, 261-275`），FMP 一個都沒用。

**四個死控制項其實分成兩類，成因不同 —— 這一點靠 app 自己的 log 才分得出來。**【事實】`WindowsSmtcHandler._setupButtonListener`（`:116-138`）的第一句就是 `logDebug('SMTC button pressed: $event')`，所以任何抵達 `buttonPressStream` 的事件都會留下一行。實測（§12.13c）：

```
[DEBUG] [WindowsSmtcHandler] SMTC updated radio station: 【金牌点唱 】全麦颜值歌手
[INFO]  [RadioController] watchAll 觸發: 1 個電台
[DEBUG] [WindowsSmtcHandler] SMTC button pressed: PressedButton.next        ← 我送的 TrySkipNextAsync
[DEBUG] [WindowsSmtcHandler] SMTC button pressed: PressedButton.previous    ← 我送的 TrySkipPreviousAsync
```

而我送出的 `TryChangePlaybackPositionAsync` 與 `TryChangeShuffleActiveAsync` **完全沒有留下任何一行**。

| 類別 | 事件有沒有到 FMP | 成因 | 該怎麼修 |
|---|---|---|---|
| **next / previous（電台時）** | **到了**（有 log），`onSkipToNext?.call()` 因 `radio_controller.dart:370-371` 設為 null 而 no-op | FMP 自己的 config 沒跟著關 | FMP 側可修：進電台時 `setIsNextEnabled(false)` / `setIsPrevEnabled(false)`，`restoreMediaControlOwnership()` 時開回 |
| **seek / shuffle / repeat** | **沒到**（無 log） | `smtc_windows` 1.1.0 的 Dart wrapper 沒把這些事件 export 出來 | FMP 側只能「不要宣告」：收掉 timeline 的 seek 範圍、不宣告 shuffle/repeat；要真正支援得等上游 |

**修正 issue 標題的建議**：「兩個無法作用的控制項」實際上是 **next / previous（電台時）、seek、shuffle、repeat** 共四項；而且只有第一項是 FMP 能自己修好的，其餘三項只能改成「不要對外宣稱有」。

---

### #41 — 音訊輸出裝置失效被誤判成「播放失敗」

> **【第四輪更新】裁決改為「保留，且根因已定位」。** 第三輪寫的是「無法非侵入式重現」；第四輪用兩步把它定位完成（§12.15b）：①`setAudioDevice` 對「找不到裝置」已有防禦，會退回 auto 且播放正常（實測），所以症狀**不是**從裝置選擇來的；②mpv 在 audio output 初始化失敗時輸出的 `Could not open/initialize audio device -> no sound.` 命中了 `_isStringMediaOpenError` 的 `'could not open'` 關鍵字（對活著的 `AudioController` 實測），因而被當成「**媒體**開啟失敗」→ `onMediaOpenError` → `stop()` → 「播放失敗: <歌名>」，與 issue 描述逐字吻合。修法見 §8.1(A) 的 `OutputDeviceFailed`。

**根因描述：全部證實。**

| 子論點 | 判定 | 證據 |
|---|---|---|
| libmpv AO 失敗訊息會抵達 `errorStream` | **證實（機制層面）** | media_kit `real.dart:2085-2119` 的前綴白名單含 `cplayer`；`PlayerConfiguration.logLevel` 預設 `MPVLogLevel.error` 且 FMP 未覆寫（`media_kit_audio_service.dart:163-167` 只設 `bufferSize`）；`:383-390` 零過濾轉發 |
| 被 `'could not open'` 誤判成 media-open | **證實** | `audio_provider.dart:2979`；目標訊息小寫化後為 `could not open/initialize audio device -> no sound.`，**包含**該子字串。且先過的 `_isStringNetworkError`（`:2434-2447`）逐項比對 11 個關鍵字，該訊息一項都不含 |
| 行號 2897 / 2974-2979 | **證實**（精確） | 同上 |
| 誤判後果 | **證實** | `:2907-2915` → `onMediaOpenError` → 等 2s（`playback_request_session.dart:164`）→ 檢查 `isPlaying && hasAdvanced`（`:372-379`）→ AO 掛掉時位置不推進 → 必然判定未恢復 → `t.audio.playbackFailedTrack` |
| 電台路徑完全吞掉 | **證實** | `audio_provider.dart:2901` 首句 return；`radio_controller.dart` 的三個訂閱是 `_repository.watchAll()`（`:297`）、`playerStateStream`（`:304-306`）、`RadioRefreshService.stateChanges`（`:309-310`）—— **`errorStream` 在整個 `lib/services/radio/` 零命中**，全 repo 唯一訂閱者是 `audio_provider.dart:396` |

**額外推論**：電台播放期間**任何**後端錯誤（含網路中斷）都無人處理 —— `AudioController` 提前 return，`RadioController` 沒訂閱。電台的錯誤恢復只剩 `playerStateStream` 與 `StreamOpenFailedException`，後者只在 `playUrl()` 呼叫當下拋出，涵蓋不到執行期。

**【裁決：併入重構】** —— issue 的建議修法（在 `MediaKitAudioService` 攔下、用 `current-ao` 複核、切回 auto 重試、經型別化訊號通知上層）**與 §6.3 階段 2 完全一致**：`PlaybackFault.audioDeviceUnavailable` 就是它要的那個型別化訊號。**不建議單獨修**，因為單獨修只會再加一條特例路徑；等 `errorStream` 型別化時一併處理，順帶把「電台不訂閱 errorStream」這個更大的洞補上。

**【仍未驗證 —— 三個裝置全試過，都起得來】** 第三輪把使用者機器上列出的**全部三個**輸出裝置逐一切換過（§12.13）：

| 裝置 | 結果 |
|---|---|
| `Steam Streaming Speakers`（Steam Remote Play 未啟用的虛擬端點） | 正常初始化，播放未中斷，無錯誤 |
| `Creative Stage SE` | 同上 |
| `Realtek(R) Audio` | 同上 |

三個都能開，所以**沒有任何一個能觸發 AO 初始化失敗**。要重現只剩「停用使用者正在使用的音訊裝置」或「以 WASAPI 獨佔模式占住端點」這類會干擾對方的操作，本輪不做。issue 內附的 libmpv C 探針證據（`current-ao` 為 `(null)` 時 `time-pos` 取不到值）仍是目前最強的支撐；而分類錯誤本身（`'could not open'` 子字串命中）是純程式碼事實、不需要實機。

---

### #42 — `preferredAudioDevice*` 是死欄位

**根因描述：全部證實。**

| 子論點 | 判定 | 證據 |
|---|---|---|
| 欄位位置 | **證實**（精確） | `settings.dart:196-197, 199-200` |
| 全 repo 只有 3 處引用 | **證實** | 排除生成檔 `settings.g.dart` 後：`backup_service.dart:767-769`、`database_catalog.dart:464-465`、`backup_service_test.dart:150-151, 265-266`。**無讀取後套用、無寫入點** |
| 選擇路徑不碰持久化 | **證實** | `fmp_audio_device_selector.dart:78` → `audio_provider.dart:1451-1454`（函式體只有一行 `await _audioService.setAudioDevice(device)`）→ `media_kit_audio_service.dart:616-630`（查表 + fallback auto，無持久化）→ Android 側是空方法（`just_audio_service.dart:446-454`） |

**額外取證**：`MediaKitAudioService.initialize()`（`:154-235`）與 `_setupMediaKitListeners()`（`:309-416`）都不呼叫 `setAudioDevice`，只被動接收後端當前裝置（`:408-415`）→ **啟動時不套用先前選擇**。而且欄位命名為 `...DeviceId`，但 media_kit 的查找鍵是 `device.name`（`:622`），`FmpAudioDevice` 根本沒有 `id` 欄位（`audio_types.dart:38-52` 只有 `name` / `description`）—— 即使接上，欄位語意也對不齊。

**【裁決：保留，可獨立修】** —— 這是三個 issue 裡唯一**不需要等重構**的：它是一個完整的功能缺口，修法有界（選裝置時寫 Settings、啟動時讀回並套用、找不到就 fallback auto 且不報錯），且 issue 已經把三個設計決定（Auto 要不要記、裝置消失的 fallback、存 name 還是 description）列清楚了。

**唯一的耦合**：「裝置消失時 fallback 到 Auto 且不出錯」依賴 #41 的錯誤分類 —— 如果先修 #42 而 #41 未修，套用一個已消失的裝置會觸發 #41 的誤判 toast。**建議修 #42 時把「套用失敗即靜默 fallback auto」寫在 `MediaKitAudioService.setAudioDevice` 內部**（它已經有 fallback 邏輯，`:626-629`），這樣不依賴 #41。

**【已於第二輪實機證實】**（§12.12）：在 Windows 上開啟輸出裝置選單 → 目前勾選「自動（跟隨系統）」→ 改選 `Steam Streaming Speakers`（選單重開確認勾選已移動、播放未中斷、無錯誤）→ 熱重啟 app → 重開選單，**勾選回到「自動（跟隨系統）」**。選擇確實只存在於 session 內。

---

## 12. 驗證記錄

### 12.1 環境

```
Flutter 3.47.1 / Dart 3.13.1
Android: AVD Medium_Phone, SDK 37 x86_64, debug build, emulator-5554
Windows: flutter run -d windows, debug build, pid 59480
```

Android 首次啟動出現 16KB page size 對齊警告對話框（`libisar.so` LOAD segment not aligned，對應 issue #44），以「Don't Show Again」關閉。

**程式碼基準**：第一～五輪為 `b93f72c7`；遠端歷史改寫後該 commit 對應 `395305bd`（內容相同）。**本文件所有 `file:line` 引用已於第六輪校正到 `598fce27`（`origin/main`）**，校正方法與逐條結果見 §12.18(a)。

### 12.2 串流解析零重用（症狀 a 的核心證據）

同一首 `BV1o58Q6UEik`（東京真中，2:05）在 8 分鐘內被播放 5 次，**每一次都完整重打 Bilibili API**：

```
03:02:06.249 [BilibiliSource] Getting audio stream for bvid: BV1o58Q6UEik
03:02:07.554 [BilibiliSource] Got cid: 41276998283 for bvid: BV1o58Q6UEik      (+1.305s)
03:02:07.703 [BilibiliSource] Got DASH audio stream ... bandwidth: 217981       (+0.149s)

03:03:55.160 Getting audio stream → 03:03:56.319 Got cid (+1.159s) → 56.413 Got DASH
03:05:13.819 Getting audio stream → 03:05:15.141 Got cid (+1.322s) → 15.238 Got DASH
03:10:00.701 Getting audio stream → 03:10:02.040 Got cid (+1.339s) → 02.135 Got DASH
```

另一首 `BV1zrtc63E7u` 在 13 秒內連播兩次，第二次同樣完整重解析（03:01:49.915 → 51.557 = 1.642s）。

Windows 端啟動時也可見同一模式：佇列恢復 `TV NCOP` 之後，**立刻對下一首 `BV1KN411n79t` 發起完整解析**（`Getting audio stream` → `Got cid` → `Got DASH audio stream ... bandwidth: 203883`）—— 這就是被丟棄的預取。

### 12.3 曲間靜默實測

```
03:02:05.992 [JustAudioService] Track completed
03:02:06.031 [AudioController] _restoreSavedState started
03:02:06.249 [BilibiliSource] Getting audio stream           ← 解析開始
03:02:07.703 [BilibiliSource] Got DASH audio stream          ← 解析結束 (1.454s)
03:02:07.759 [JustAudioService] Setting URL: https://upos-hz-mirrorakam.akamaized.net/...
03:02:08.911 processingState → ready                          ← 開流 (1.152s)
03:02:08.924 [AudioController] _restoreSavedState completed successfully
```
**總靜默 2.893 秒**，其中 50% 是可省的解析。

### 12.4 Bilibili CDN 與 API 實測（主機直接量）

```bash
$ curl -s -H "Referer: https://www.bilibili.com" ".../x/player/playurl?bvid=BV1o58Q6UEik&cid=41276998283&fnval=16&fourk=1"
code 0 OK
timelength(ms)= 125056
audio id 30216 bw 65726  codecs mp4a.40.2   host: upos-hz-mirrorakam.akamaized.net
audio id 30232 bw 117011 codecs mp4a.40.2   host: upos-hz-mirrorakam.akamaized.net
audio id 30280 bw 217981 codecs mp4a.40.2   host: upos-hz-mirrorakam.akamaized.net
deadline TTL from now: 7178s (1.99 h)
backup count: 1  →  upos-sz-mirrorcosov.bilivideo.com
```

```bash
# 1MB Range 下載
http=206 size=1048576 time=0.339942s speed=3084618 B/s ttfb=0.300388s connect=0.010972s

# API 延遲（各 3 次）
view    : total=0.099s / 0.106s / 0.087s
playurl : total=0.103s / 0.121s / 0.123s
```

**結論**：CDN 已是 Akamai 海外節點、3.08 MB/s、支援 Range；兩支 API 各 ~0.10s。app 內 cid 查詢的 1.16–1.34s **不是網路造成的**。

### 12.5 模擬器音訊時脈偏快（環境陷阱，非 FMP 缺陷）

| 曲目 | API/媒體時長 | 實際播放 wall time | 比值 |
|---|---|---|---|
| BV1o58Q6UEik | 125.056s（API `timelength` 與 just_audio 一致） | 03:06:52.194 → 03:08:06.489 = **74.30s** | **1.683** |
| BV1zrtc63E7u | 21.733s | 03:01:53.013 → 03:02:05.992 = **12.98s** | **1.674** |

排除時鐘漂移：
```
host delta = 60.30s / device delta = 60.29s / ratio = 1.000
```
兩首長度差 6 倍的曲子比值一致（1.674 / 1.683），排除「串流被截斷」（截斷應與頻寬相關而非固定比例）。API 權威時長 125,056ms 與 just_audio 讀到的 `0:02:05.056000` 完全吻合，所以媒體 metadata 也正確。

【推論】是 AVD 音訊 HAL 消耗音訊 frame 快於實際時間，ExoPlayer 的位置追蹤跟著音訊時鐘走。**影響：任何依賴播放時長的驗證（gapless、曲間銜接、緩衝耗盡、premature completion）在這台 AVD 上都不可信。網路 I/O 的時間戳不受影響。** 建議寫進 skill（Q14）。

**Windows 對照組（第五輪補上，證實這是模擬器專屬）**【事實】：§12.15(b) 的 #41 探測順帶量到了 —— 播放本機產生的 30 秒靜音 WAV，`Future.delayed(12s)` 之後讀到的位置是 `0:00:11.940313`，比值 **0.995**。

| 平台 | 播放引擎 | 實際經過 | 播放器位置 | 比值 |
|---|---|---|---|---|
| Android AVD `Medium_Phone` | just_audio / ExoPlayer | 74.30s | 125.06s | **1.68** |
| Windows 11 主機 | media_kit / libmpv | 12.00s | 11.94s | **0.995** |

所以 1.68x **只出現在模擬器上**，Windows 的音訊時鐘是準的。這也表示 §3.d 那個「曲間 2.893 秒靜默」的實測值（在 AVD 上量的）若換算回真實時間會更長，不是更短。

### 12.6 Windows 端驗證（第一輪）：**曾被阻塞，第二輪已解除**

> 以下是第一輪的紀錄，保留以說明阻塞的性質；解除方式與後續結果見 §12.11。

Windows debug build 成功啟動（`orca computer list-apps` → `{'name': 'fmp', 'pid': 59480}`，視窗 `FMP - Flutter Music Player` 1920×1200 @ (960,444)），並從 run terminal 讀到完整啟動 log（佇列恢復 1194 首、media_kit `URL set, duration: 0:01:32.138166`、`WindowsSmtcHandler` 已註冊）。

**但 UI 驗證無法進行，阻塞有兩層：**

1. **主機上有一個全螢幕前景應用（CJK 標題）壓在 FMP 視窗上。** `orca computer get-app-state --app pid:59480 --restore-window` 兩次都無法把 FMP 抬到前景，截圖抓到的是那個應用的畫面。Windows Flutter build 又不暴露語意樹（`treeText` 只有 `window > pane FLUTTERVIEW`，`elementCount: 2`），所以「trust the tree over occluded pixels」這條退路也不存在。
2. **全域媒體鍵送不到 FMP。** 用 `keybd_event(VK_MEDIA_PLAY_PAUSE)` 送了兩次（含 extended-key 變體），FMP 的 log cursor 完全沒有前進。無法判定是前景應用攔截還是 SMTC session 未被選中 —— 兩種可能都不能歸咎於 FMP。

我沒有嘗試最小化或關閉那個前景應用，也沒有嘗試盲點擊 FMP 視窗（一個載入了 1194 首佇列的音樂 app，盲點擊有破壞資料的風險）。

**因此第一輪把以下項目標記【未驗證】**：#40 的進度條拖曳症狀、#41 的裝置失效實機重現、#42 的重啟後回到 Auto、症狀 c 在 media_kit 上的實機重現、以及 §12.5 的 1.68x 在 Windows 上的對照。

> **後續進度（讀本節時請以此為準）**：#40 進度條 → 第三輪完成（§12.13b）；#42 → 第二輪完成（§12.12）；症狀 c 的 media_kit 實機重現 → 第四輪完成（§12.14d）；#41 → 第五輪定位到根因但**裝置失效本身仍未實機重現**（§12.15b）；§12.5 的 1.68x 在 Windows 上的對照 → **仍未做**。

**解除阻塞需要**：把那個全螢幕應用最小化（或在沒有它的時候重跑）。#41 另外還需要一個可安全停用的音訊輸出裝置。

### 12.7 外部研究的抽驗

依規則抽驗了 6 條關鍵結論（5 條內部 + 1 條外部），全部通過：

| # | 結論 | 抽驗方式 | 結果 |
|---|---|---|---|
| 1 | `NeteaseSource.getAlternativeAudioStream` 恆回 null | `sed -n '200,210p'` | ✅ body 只有 `return null;` |
| 2 | `JustAudioService` 裝置三件套是空實作 | `sed -n '110,118p;444,456p'` | ✅ `=> []` / `=> null` / 兩個空方法體 |
| 3 | `SMTCConfig` 寫死且無 `updateConfig` 呼叫 | `sed` + `rg` | ✅ `:96-104` 寫死；grep 零命中 |
| 4 | `base_source.dart` 無抽象類別 | `rg '^abstract\|^class\|^enum'` | ✅ 只有 4 個 class + 1 個 enum，全是 DTO |
| 5 | media_kit 錯誤訂閱零過濾 | `sed -n '383,392p'` | ✅ 無 `.where`、無前綴檢查 |
| 6 | Spotube 用 shelf 本機代理 + 快取 + `refreshStreamingUrl` | 抓 `raw.githubusercontent.com/KRTirtho/spotube/master/lib/provider/server/routes/playback.dart`（358 行） | ✅ `import 'package:shelf/shelf.dart'`（:11）、`cacheMusic`（:91,139,217）、`.part`（:223）、`refreshStreamingUrl()`（:187） |

依賴版本獨立核對（pub.dev API，2026-08-30）：

| 套件 | FMP 約束 | **實際解析**（`pubspec.lock`） | pub.dev latest | 發布日 |
|---|---|---|---|---|
| `just_audio` | `^0.9.40` | 0.9.46 | **0.10.6** | 2026-06-29 |
| `media_kit` | `^1.1.11` | **1.2.6** | 1.2.6 | 2025-12-13 |
| `audio_service` | `^0.18.15` | 0.18.18 | 0.18.19 | 2026-06-29 |
| `smtc_windows` | `^1.1.0` | 1.1.0 | 2025-08-18 |
| `youtube_explode_dart` | `^3.1.0` | 3.1.0 | 2026-05-09 |

`smtc_windows` 已是最新 —— **#40 的 seek 缺口無法靠升級解決**，只能送 upstream PR 或收掉 timeline 的 `maxSeekTimeMs`。

> **【第八輪更正】** 上面「FMP pin」那一欄原本填的是 `pubspec.yaml` 的**約束**，然後拿它去比 pub.dev 最新版 —— 那會把 caret 能自動吃到的更新算成「落後」。查 `pubspec.lock` 之後：**`media_kit` 實際已經是 1.2.6（最新），`audio_service` 是 0.18.18（差一個 patch）**。真正落後的只有 `just_audio`（0.9.46 vs 0.10.6），而且那是 caret 擋住的 minor 躍遷 —— 也就是 D4 那一題。P2-13 已據此縮小範圍。
>
> 順帶一提，這也意味著**本報告所有針對 media_kit 行為的實測都是對 1.2.6 做的**，不是 pubspec 上寫的 1.1.11。

---

### 12.8 更正：1.2 秒的 cid 查詢是 AVD 的 DNS，不是 debug build

**實驗 1 — 連線重用（推翻「連線建立成本」）**：兩首**不同**曲目間隔 5.2 秒連播，遠在 Dart `HttpClient.idleTimeout`（預設 15s）之內。

```
08:12:38.252 Getting audio stream for bvid: BV1VJ8Q6jEgv   ┐ cid = 1.519s（冷）
08:12:39.771 Got cid: 41274180287                          ┘
08:12:39.864 Got DASH audio stream                           playurl = 0.093s

08:12:44.965 Getting audio stream for bvid: BV1zrtc63E7u   ┐ cid = 1.193s（暖，仍然慢）
08:12:46.158 Got cid: 41352824654                          ┘
08:12:46.244 Got DASH audio stream                           playurl = 0.086s
```

**實驗 2 — 主機用 FMP 完整 header 重打**（UA/Referer/Origin/Accept + 隨機 buvid3/buvid4/b_nut/_uuid/buvid_fp cookie）：

```
  view    total=0.104893s ttfb=0.104807s size=2113
  playurl total=0.106862s ttfb=0.099123s size=28647
  view    total=0.089339s ...            size=2113
  playurl total=0.121091s ...            size=28647
  view    total=0.089201s ...            size=2113
  playurl total=0.099960s ...            size=28647
```
兩者都快，而且**回應較大的 playurl 反而不慢** → 排除「JSON 解析成本」與「伺服器慢」。

**實驗 3 — DNS**：

```
模擬器內  ping api.bilibili.com ×3 : 1145 ms / 1015 ms / 497 ms
再跑一輪（若有快取應變快）        : 956 ms / 992 ms / 1017 ms
主機 curl time_namelookup ×3      : 0.011248s / 0.012741s / 0.009992s
```

【事實】AVD 的 DNS 每次約 1 秒且無有效快取，主機約 11 毫秒，差 100 倍。`view` 是每次播放對 `api.bilibili.com` 的第一個請求（要新建連線 → 付一次 DNS），`playurl` 重用該連線（免 DNS）。這完整解釋了 1.2s vs 0.09s 的落差。

**連帶**：`api.bilibili.com` 回應含 `Connection: keep-alive`，所以連線本身可重用；問題純粹在跨播放時連線未存活 + DNS 昂貴。

**對報告的影響**：§12.2 所有解析耗時都含這 ~1s；真實裝置上該段約 0.2–0.5s。結構性結論（零快取、多一次往返）不受影響。

### 12.9 症狀 c 的 Android 半邊：完整重現

程序：播放 5:13 的 `BV1VJ8Q6jEgv` → 8 秒後 `cmd connectivity airplane-mode enable` + `svc wifi disable` + `svc data disable` → 觀察 → 恢復網路。

```
08:15:26.827  Play requested, duration: 0:05:13.834000
08:15:36.920  [INFO] [ConnectivityNotifier] Connectivity changed: wasConnected=true, isConnected=false
08:16:17.866  [ERROR] [Zone] Uncaught async error
              SocketException: Failed host lookup: 'upos-hz-mirrorakam.akamaized.net' (errno = 7)
              #10 _getUrl (package:just_audio/just_audio.dart:4057)
              #11 _proxyHandlerForUri.handler (package:just_audio/just_audio.dart:3369)
              #12 _ProxyHttpServer.start.<anonymous closure> (package:just_audio/just_audio.dart:2159)
08:16:26.860  [ERROR] [Zone] Uncaught async error   （同上，第 2 次）
08:16:36.864  [ERROR] [Zone] Uncaught async error   （同上，第 3 次）
08:16:38.221  PlayerState changed: playing=true, processingState=buffering
08:16:44.890  [ERROR] [JustAudioService] Playback error: PlatformException(0, Source error, {index: 0}, null)
08:16:44.893  [ERROR] [AudioController] Audio error from service: Playback error: PlatformException(...)
08:16:44.894  [DEBUG] [AudioController] Non-network error, ignoring: Playback error: PlatformException(...)
--- 網路恢復 ---
08:18:22.092  [INFO] [ConnectivityNotifier] Network recovered! Broadcasting recovery event...
08:18:22.093  [DEBUG] [AudioController] Network recovery event received from stream
08:18:22.094  [INFO] [AudioController] _onNetworkRecovered called, recoveryTrack: null
08:18:22.095  [INFO] [RankingCacheService] 網絡恢復，重新獲取排行榜緩存
```

截圖（`scratchpad/and1.png`、`and2.png`）：頂部只有 ConnectivityNotifier 的 `No network` 橫幅（無「播放網路異常」）；mini player 播放鍵從 08:16:44 起變成 spinner，到 08:19 仍是 spinner —— 超過 2 分 30 秒，網路已恢復也沒有復原。

排行榜快取在網路恢復後 2 秒內全部刷新（Bilibili 100 首 / YouTube 50 首 / Netease 50 首），**只有播放沒有恢復**。

### 12.10 YouTube 播放路徑實測

```
--- Cardi B  I-5e_J3LWS8 ---
08:19:47.727  Updated playing track
08:19:47.806  Getting audio stream ... streamPriority=[audioOnly, muxed, hls]
08:19:49.846  Audio-only stream failed: VideoUnplayableException: Video 'I-5e_J3LWS8' is unplayable.
              Reason: Sign in to confirm you're not a bot
08:20:07.470  Got muxed stream for I-5e_J3LWS8: 719.31 Kbit/s, mp4      ← +17.62s
08:20:07.474  Playing track ... https://rr7---sn-juh-h4hs.googlevideo.com/videoplayback?expire=...
08:20:09.933  Updated playing track                                      ← 點擊→出聲 22.21s

--- JENNIE  s466YCiHfKw ---
08:20:56.312  Getting audio stream
08:20:58.509  Audio-only stream failed ... Reason: Sign in to confirm you're not a bot
08:21:17.861  Got muxed stream: 436.28 Kbit/s, mp4                       ← +19.35s
08:21:19.806  Updated playing track                                      ← 點擊→出聲 23.59s
```

註：這 20 秒**不能**用 AVD 的 DNS 解釋（每次查詢約 1 秒，即使 muxed 路徑做 5 次查詢也只有 5 秒）。

### 12.11 Windows 端：阻塞解除方式、實機結果，與一則紀律說明

**阻塞解除**：第一輪的全螢幕前景應用已不在前景。但 `orca computer get-app-state --restore-window` 仍抬不起 FMP（Windows 的前景鎖定），需要用 Win32 的 `AttachThreadInput` + 先送一次 ALT 的標準手法才能奪回前景；FMP 的 HWND 為 `593080`。

**紀律說明（必須記錄）**：在確認前景之前就送出點擊，會讓點擊落到當時真正的前景視窗。本輪發生過一次：一次 `orca computer get-app-state` 截到的是使用者桌面該區域（一份含個人證件號/電話/Email 的線上申請表），另一次點擊落進同一個瀏覽器視窗、打開了表單上的一個 `<select>`。已即時告知使用者、未再對該視窗操作、該截圖內容不進入本報告。**後續所有動作改為「先抬前景 → 驗證 `GetForegroundWindow() == FMP HWND` → 才送出動作，否則中止」**（腳本 `scratchpad/raise_fmp.ps1`）。這一條建議寫進 skill。

**Windows log 被 AXTree spam 稀釋（但不是完全不可讀）**：run terminal 被 `Failed to update ui::AXTree` 洗版（`docs/troubleshooting.md` 記載的已知 Flutter engine bug）。第三輪量到的比例是 **226 行取回、過濾後剩 25 行有效（約 89% 是 spam）**，而且 cursor 推進極快（一段操作內從 159 跳到 3894）。第二輪一度出現「600 行只剩 1 行」的極端情況。**結論：Windows 端的 log 要用「大 limit + 過濾 AXTree」才讀得到，不能直接 tail；但關鍵事件（如 `SMTC button pressed`）確實會出來，值得撈。**

**媒體鍵（SMTC transport）實測有效**：
- `VK_MEDIA_PLAY_PAUSE` → mini player 的播放鍵變成暫停鍵。
- `VK_MEDIA_NEXT_TRACK` → 曲目由 `TV NCOP` 切到 `【原创曲】希望还有很多第一次，和你们一起。`。

（第一輪同樣的按鍵完全沒有反應，差別就是 FMP 是否在前景 —— 這不能歸咎於 FMP。）

### 12.12 #42 的實機驗證

1. 開輸出裝置選單 → 清單為 `自動（跟隨系統）`✓ / `Creative Stage SE` / `Realtek(R) Audio` / `Steam Streaming Speakers`。
2. 選 `Steam Streaming Speakers` → 播放**未中斷**、無錯誤 toast、進度條持續前進（順帶說明 #41 未被觸發）。
3. 重開選單 → ✓ 已移到 `Steam Streaming Speakers`，**執行期套用成功**。
4. `flutter run` 送 `R` 熱重啟（會重跑 `main()` 並重讀磁碟上的 Isar）。
5. 重開選單 → **✓ 回到 `自動（跟隨系統）`**。

結論：裝置選擇在執行期有效、跨啟動不保留，與程式碼證據（無寫入點、無讀取點）一致。

### 12.13 第三輪：使用者暫停手邊工作後的 Windows 完整驗證

**方法上的關鍵改進**：不再靠截取系統媒體浮出視窗（會拍到使用者其他視窗），改用 WinRT 直接讀寫 FMP 自己的 SMTC session：

```powershell
[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()
  → GetSessions() | ? { $_.SourceAppUserModelId -eq 'com.personal.fmp' }
  → GetPlaybackInfo().Controls / GetTimelineProperties()
  → TryChangePlaybackPositionAsync / TrySkipNextAsync / TrySkipPreviousAsync / TryChangeShuffleActiveAsync
```

腳本：`scratchpad/smtc.ps1`、`smtc_seek.ps1`、`smtc_next.ps1`（需用 `powershell.exe` 5.1，PS7 的 WinRT 投影不完整）。

**(a) 一般佇列播放時的 SMTC 快照**

```
session count = 1
AppUserModelId = com.personal.fmp
PlaybackStatus = Paused
Controls.IsNextEnabled             = True
Controls.IsPreviousEnabled         = True
Controls.IsPlaybackPositionEnabled = False     ← 關鍵
Controls.IsShuffleEnabled          = True
Controls.IsRepeatEnabled           = True
Controls.IsPlayPauseToggleEnabled  = True
Controls.IsStopEnabled             = True
Controls.IsFastForwardEnabled      = False
Controls.IsRewindEnabled           = False
Timeline.StartTime   = 00:00:00
Timeline.EndTime     = 00:04:06.1310000
Timeline.Position    = 00:00:30.1000000
Timeline.MinSeekTime = 00:00:00
Timeline.MaxSeekTime = 00:04:06.1310000       ← 與上面的 False 互相矛盾
```

**(b) seek 與 shuffle 請求（暫停狀態，位置不會自然前進）**

```
BEFORE  position=00:00:30.1000000  status=Paused
TryChangePlaybackPositionAsync(00:03:00) returned: True
AFTER   position=00:00:30.1000000              ← 3 秒後仍未變
TryChangeShuffleActiveAsync(true) returned: True
AFTER   shuffle=（空值）                        ← FMP 從不回報 shuffle 狀態
```
截圖確認 FMP 的 shuffle 按鈕仍為關閉。

**(c) 電台播放中的 SMTC 快照與 next/prev 請求**

暫時以 `https://live.bilibili.com/27632810`（一個當下在線的 B 站點唱直播間）新增電台 → 播放（畫面顯示「直播中 · 22 觀眾」，FMP 自己的 mini player 已把上／下一首換成循環與重新整理）：

```
PlaybackStatus             = Playing
Controls.IsNextEnabled     = True      ← 電台中仍宣告可用
Controls.IsPreviousEnabled = True
Timeline.EndTime           = 00:00:00  ← 直播沒有長度，這一項是對的
TrySkipNextAsync()     returned: True → 4 秒後 title/artist/status 完全未變
TrySkipPreviousAsync() returned: True → 4 秒後 title/artist/status 完全未變
```

**同一段 log 也證明了兩類死控制項的差別**：`PressedButton.next` / `PressedButton.previous` 各留下一行 `SMTC button pressed`，而 seek 與 shuffle 請求一行都沒有 —— 見 §11 的 #40 段。

**清理**：測試完成後在 FMP 內右鍵該電台 →「刪除電台」→ 確認，畫面回到「還沒有電台」（截圖），log 亦顯示 `[RadioController] watchAll 觸發: 0 個電台`。使用者的資料庫回復原狀，整個過程只新增並刪除了這一筆電台，沒有動任何其他資料。

**收尾時的一個未解事件**：刪除完成之後，log 出現
```
[DEBUG] [WindowsDesktopService] Right mouse down on tray icon
[DEBUG] [WindowsDesktopService] Menu item clicked: quit
Lost connection to device.
```
FMP 是**經由自己的系統匣選單「結束」正常退出的，不是崩潰**。這一下右鍵是誰送的無法確認（我在該時間點只送了 `raise_fmp.ps1` 的 ALT 按鍵，沒有送點擊；但先前曾用 `SetCursorPos` 把游標停在系統匣區域），故不歸因。因為 Netease 播放路徑的量測還沒開始，該項仍未完成。

**(d) #41 的三個裝置逐一嘗試**

`自動（跟隨系統）` → `Steam Streaming Speakers` → `Creative Stage SE` → `Realtek(R) Audio` → 還原 `自動`。每一次切換後播放都持續、進度條持續前進、沒有任何錯誤 toast。**三個端點都能被 libmpv 開啟，無法觸發 #41 的 AO 失敗。**

**(e) 前景競爭的處理**

FMP 在這台機器上守不住前景（`ControlCenterWindow` / 其他應用會搶走），`orca computer get-app-state --restore-window` 無效。可行做法是 Win32 的「先送一次 ALT 解除前景鎖 → `AttachThreadInput` → `SetForegroundWindow`」，並在每次動作前重新驗證 `GetForegroundWindow() == FMP HWND`，不通過就中止（`scratchpad/raise_fmp.ps1`）。即使如此仍發生過一次「guard 通過、動作送出前又被搶走」，所以**任何盲點擊都必須假設可能落到別的視窗**。

---

### 12.14 第四輪：改用 VM Service 表達式求值，兩平台同條件對照

本輪最重要的不是某一條結論，而是**換掉了觀測手段**。前三輪在 Windows 上受制於「沒有 semantics tree ⇒ 只能截圖 + 盲點座標」，既慢又有誤擊風險（§12.11）。第四輪改用 Dart VM Service 的 `evaluate`，**全程沒有改任何一行程式碼、沒有送任何一次滑鼠／鍵盤事件**，也因此第一次能在兩個平台上跑「完全相同的受控實驗」。

#### (a) 方法：`evaluate` 只能走 WebSocket，不能走 HTTP

`docs/debugging-with-vm-service.md` 目前只寫了 HTTP 端點。實測 HTTP 端點呼叫 `evaluate` 一律失敗：

```
GET http://127.0.0.1:55251/<token>=/evaluate?isolateId=...&targetId=...&expression=1%2B1
→ {"error":{"code":113,"message":"Expression compilation error",
             "data":{"details":"_compileExpression: No compilation service available; cannot evaluate from source."}}}
```

同一個 isolate、同一個表達式，改走 `ws://127.0.0.1:55251/<token>=/ws` 就正常回 `2`。原因是表達式編譯服務是 `flutter run` 這個 client 註冊到 VM Service 上的，只在 WebSocket 連線上被轉發。Node 24 內建 global `WebSocket`，不需要任何額外套件（腳本：`scratchpad/vmsws.js`、`vmeval.js`、`vmfind.js`）。

由此解鎖三件事：

1. **把 `AppLogger` 的環形緩衝（500 筆）連同毫秒時間戳整包取出。** `LogEntry.toString()` 本來就帶 `[I] hh:mm:ss.mmm [Tag] message`（`logger.dart:44-49`），所以拿到的是現成的毫秒級時間軸 —— 不必 OCR，也不必去讀被 `Failed to update ui::AXTree` 洗版的 Windows run terminal。

   ```dart
   // Windows：targetId = media_handoff.dart（同時 import 了 dart:io 與 logger.dart）
   File(r'...\fmplog.txt').writeAsStringSync(
       AppLogger.logs.map((e) => e.toString()).join(String.fromCharCode(10)))
   // Android：targetId = logger.dart，直接回傳字串，再用 getObject(offset,count) 分頁取回全文
   ```

2. **對活著的物件求值，包含私有成員。** `getInstances(classId)` 拿到唯一一個 `AudioController` 實例後，以該實例當 `targetId`，就能直接呼叫 `_isStringNetworkError` / `_isStringMediaOpenError`（見 (c)）。

3. **在 app 進程內起一個獨立的後端實例**（`MediaKitAudioService` / `JustAudioService`）做受控實驗，完全不碰使用者正在用的播放器、不寫播放歷史、不動佇列。

> 【建議・S・可逆】把這段補進 `docs/debugging-with-vm-service.md`（新增一節「表達式求值」），並在 `verify-on-device` skill 註明「Windows 端優先用 VM Service evaluate，不要截圖」。

#### (b) 兩台裝置啟動即撞上 Bilibili 風控 —— 症狀 a 的代價不只是慢

Windows 端啟動、還原佇列（1194 首、index 946）時自動對當前曲目重新解析串流：

```
14:26:54.889 [D] [BilibiliSource] Getting audio stream for bvid: BV1j64y1C7Up ...
14:26:55.093 [E] [BilibiliSource] Bilibili Dio error: statusCode=412, response={code: -412, message: request was banned, ttl: 1}
14:26:55.094 [W] [BilibiliSource] Bilibili rate limited (HTTP 412)
14:26:55.096 [E] [BilibiliSource] Bilibili Dio error: statusCode=412, ... (第二次)
14:26:55.098 [E] [AudioController] Failed to prepare track: 【原创曲】hanstar~
14:26:55.100 [I] [AudioController] AudioController initialized successfully
```

Android 端（不同裝置、不同佇列，只有 4 首）在同一段時間獨立出現同一件事：

```
06:42:58.236 [E] [AudioController] Failed to prepare track: 【朱志鑫】DAY-1原创SOLO...
             Error: BilibiliApiException(-429): Too many requests, please try again later
```

三個觀察：

1. **【事實】「每次都重新解析」不只是延遲，還會直接失敗。** 同一時間 `RankingCacheService` 的排行榜請求是成功的（`14:26:54.983 Bilibili 音樂排行榜 緩存已刷新: 100 首`），被擋的只有 `view` / `playurl` 這一組。啟動還原因此留下一個**沒有可播 URL 的 playingTrack**，使用者按下播放才會再撞一次。
2. **【事實】一次還原打了兩個 412。** 對照 `bilibili_source.dart:264-268` 的 `request.cid ?? await _getCid(bvid)`：`view` 一次、`playurl` 一次。§3.a 說的「多一趟 round trip」在被風控時代價加倍。
3. **【事實】被風控時沒有退避** —— 兩次請求間隔 3 毫秒。

【未驗證】這次風控是否與前幾輪的實驗流量有關無法區分；但「還原路徑必然重新解析」這個結構事實與觸發原因無關。

#### (c) 錯誤字串分類表 —— 對活著的 `AudioController` 直接求值

```dart
// targetId = getInstances(AudioController) 取得的唯一實例
[...].map((s) => (_isStringNetworkError(s) ? 'N' : '-') + (_isStringMediaOpenError(s) ? 'O' : '-')).join(',')
```

| 錯誤字串（實際會出現的樣子） | `_isStringNetworkError` | `_isStringMediaOpenError` | 結果 |
|---|---|---|---|
| `tcp: ffurl_seek failed`（mpv） | ✅ | — | 走網路錯誤 |
| `Failed to open https://...`（mpv） | — | ✅ | 走 media open 錯誤 |
| `Can not open external file`（mpv 原文） | — | ❌ | **靜默丟棄** |
| `Source error`（ExoPlayer，實測會出現，見 (d)(e)） | ❌ | — | **靜默丟棄** |
| `(0) Source error` | ❌ | — | **靜默丟棄** |
| `PlatformException(abort, Loading interrupted, null, null)` | ❌ | — | **靜默丟棄** |
| `java.net.UnknownHostException: Unable to resolve host x` | ✅ | — | 走網路錯誤 |
| `Unable to connect to https://x` | ❌ | — | **靜默丟棄** |
| `javax.net.ssl.SSLException: Read error` | ❌ | — | **靜默丟棄** |
| `Response code: 403`（串流 URL 過期的典型樣子） | ❌ | ❌ | **靜默丟棄** |
| `ExoPlaybackException: MediaCodecAudioRenderer error` | ❌ | ❌ | **靜默丟棄** |
| `Decoder init failed` | ❌ | ❌ | **靜默丟棄** |

兩個具體的字面近失：

- 關鍵字表有 `connection`，但 ExoPlayer 寫的是 `Unable to **connect** to` —— 差一個字尾就不命中。
- media open 關鍵字表有 `cannot open`（一個字），但 mpv 寫的是 `Can **not** open external file`（兩個字）。

「靜默丟棄」的落點是 `audio_provider.dart:2906-2919`：兩個分類都不中就 `logDebug('Non-network error, ignoring: ...')` 然後 `return`。DEBUG 級在 release build 連 log 都不會留（`logger.dart:56`）。

**最值得注意的是 `Response code: 403` 兩邊都不中。** 串流 URL 過期（Bilibili `deadline`、Netease 16 分鐘）在傳輸層就是以 403 呈現，而 FMP 對它沒有任何反應路徑。

> 【範圍說明】表中的字串分成兩類：`Source error`、`(0) Source error`、`tcp: ffurl_seek failed` 是本輪或第二輪**實際從 FMP log 觀察到**的原文；其餘（含 `Response code: 403`）是引擎會產生、但本輪沒有實際觸發到的形式，用來測試關鍵字表的覆蓋範圍。值得注意的是 Android 實測顯示：**不管底層是什麼原因，just_audio 交給 FMP 的字串都是 `Source error`** —— 也就是說在 Android 上，403 這類細節連字串都到不了 `AudioController`，比「關鍵字沒命中」更早一步就丟失了。

#### (d)(e) 兩個受控實驗 × 兩個平台

用本機伺服器製造兩種確定的網路病態，兩個平台跑同一組 URL（Windows 走 `127.0.0.1`，Android 走 `10.0.2.2`）。腳本：`scratchpad/stallsrv.py`（送 4 秒音訊後 `SO_LINGER=0` 硬斷，之後所有重連立刻關閉）、`scratchpad/holdsrv.py`（回 200 + `Content-Length` + WAV header 之後**永遠不送資料也不關閉**）。播放用的是**獨立建立的後端實例**，音量設 0，不接 `AudioController`。

> **證據等級說明（重要）**：下面表格裡「引擎發了什麼事件、隔多久」全部是**實測**。而「`AudioController` 收到之後會怎麼做」是**讀碼推導** —— 因為探測用的是獨立後端實例，沒有接到使用者正在用的控制器（接上去會寫播放歷史、動到 1194 首的佇列索引，本輪不做）。兩者在下文分別標示，請不要把後半段當成實機觀察。

**結果矩陣 —— 四個格子，四種不同的行為，沒有一格相同：**

| | Windows / media_kit（libmpv） | Android / just_audio（ExoPlayer） |
|---|---|---|
| **播到一半連線被 RST** | 引擎自行重連 **6 次**（帶正確 `Range: bytes=708652-`）；`errorStream` **零輸出**；**3.756 秒**後發 **`completed`** | 引擎自行重連 **3 次**；**16.4 秒**後發 **`Source error`**（→ 分類器不認 → 靜默丟棄） |
| **連得上但零位元組** | `_player.open()` **658ms 返回**；`playUrl` **6.111 秒正常返回**，`duration: null`、`playing: true`；**12.4 秒**後發 **`completed`** | `playUrl` **阻塞 37.711 秒**後**拋出** `(0) Source error`；同時 `errorStream` 也發一次 |

逐字證據：

```
── Windows，播到一半被 RST ──────────────────────────────
[srv] conn 1  sent 708652B of 21168044B -> RST
[srv] conn 2..7  GET Range: bytes=708652-  → refusing        ← mpv 自己重連 6 次
14:37:07.486 [D] [MediaKitAudioService] Playback started, duration: 0:02:00.000000, playing: true
14:37:11.242 [D] [MediaKitAudioService] Track completed                    ← 3.756s，errorStream 全程零輸出
14:37:11.242 [I] [PROBE] PROBE-STATE playing=false, processingState=completed

── Windows，連得上但零位元組 ────────────────────────────
14:39:09.389 [D] [MediaKitAudioService] Playing URL: http://127.0.0.1:8732/b.wav...
14:39:10.047 [D] [MediaKitAudioService] URL loaded successfully, duration: null (may update later)   ← 658ms，被記成成功
14:39:10.047 [D] [MediaKitAudioService] _ensurePlayback called, current state: buffering
14:39:15.500 [D] [MediaKitAudioService] _ensurePlayback completed, playing: true                     ← 宣稱在播
14:39:15.501 [I] [PROBE] PROBE-PLAY returned after 6111ms dur=null
14:39:27.902 [D] [MediaKitAudioService] Track completed                                              ← 再 12.4s

── Android，播到一半被 RST ──────────────────────────────
06:45:23.620 [D] [JustAudioService] Playing URL: http://10.0.2.2:8741/a.wav...
06:45:25.030 [I] [PROBE] ACUT-PLAY ok 1412ms dur=0:02:00.000000
06:45:41.472 [E] [JustAudioService] Playback error: PlatformException(0, Source error, {index: 0}, null)  ← 16.4s
[srv] conn 3/5/7 帶 Range 重連（另有 conn 4/6/8 是 just_audio 本機代理的成對請求）

── Android，連得上但零位元組 ────────────────────────────
06:46:22.612 [D] [JustAudioService] Playing URL: http://10.0.2.2:8742/b.wav...
06:47:00.313 [E] [JustAudioService] Playback error: PlatformException(0, Source error, {index: 0}, null)
06:47:00.322 [E] [JustAudioService] Failed to play URL
06:47:00.322 [I] [PROBE] AHOLD-PLAY threw 37711ms (0) Source error                                    ← 37.7s
```

**這組數據更正了報告先前的兩處推論，也升級了兩處結論：**

1. **更正 §3.b。** 原本寫「CDN 接受連線但不送資料時，`open()` 可以永遠不返回，使用者只看到轉圈」。Windows 上**不是這樣**：`playUrl` 6.1 秒就**正常返回**（不是拋例外）。真正的問題是 `media_kit_audio_service.dart:717-770` 把「拿不到 duration」當成可接受的結果 —— 等 duration 的迴圈只有 `10 × audioServicePollingDelay(50ms) = 500ms`，逾時就 `resultDuration = null` 往下走，寫 `logDebug('URL loaded successfully, duration: null')`，然後 `_ensurePlayback()` 只看 mpv 的 `playing` 旗標，而 mpv 在零位元組時確實會翻成 true。**上層收到的是「播放成功、時長未知」。** Android 那一半（37.7 秒才拋出）則確實符合原本的推論方向，只是有界。

2. **升級：premature-completion 保護在 `duration == null` 時被完全繞過。** Windows 的零位元組情境 12.4 秒後發 `completed`，此時 `_shouldHandleTrackCompleted()`（`audio_provider.dart:2992-3014`）走的是 `duration == null || duration.inMilliseconds <= 0` → **`return true`**（`:2998-3000`）→ `_onTrackCompleted` 直接 `moveToNext()`。【推論】使用者體感是**每首歌響 0 秒就跳掉、一路往下刷佇列**，而且沒有橫幅、沒有 toast（因為走的不是 recovery 路徑）。這比「卡住轉圈」難診斷得多。

3. **更正 §3.c 對 Windows 側的機制描述。** 原本寫的是「Windows 過度反應：mpv 吐 `tcp:` 錯誤 → `_onAudioError` → stop + 退避」。實測「播到一半斷線」時 **mpv 根本不發 error**，這條路走不到。實際接手的是 `_onTrackCompleted` → `_shouldHandleTrackCompleted()`（`duration=2:00`、`position≈4s`、`remaining` 遠大於 `positionCheckInterval 1s + positionCheckThreshold 500ms`）→ 判定 premature → `_recoverFromPrematureCompletion` → `PlaybackRecoveryCoordinator.scheduleRetry`（`:276-282`）→ `isNetworkError: true, isRetrying: true`。**「播放網路異常」橫幅的真正來源是這裡**，退避序列 1s/2s/4s/8s/16s、上限 5 次（`app_constants.dart:176-185`），約 31 秒後 `retryExhausted`；每次重試都是一次完整的重新解析。結論（過度反應 + 放大迴圈）不變，路徑不同。

4. **升級 P1-9（`errorStream` 是 `Stream<String>`）。** 原本的論點是「錯誤語意被抹成字串」。實測顯示比那更嚴重：**兩個後端在同一個網路條件下連「哪個事件通道會響」都不一致** —— 一邊發 `completed`、一邊發 `error`、一邊直接從 `playMedia` 拋出。任何寫在 `AudioController` 裡的字串比對都不可能同時涵蓋這三種。

5. **【事實】FMP 自己沒有任何一個逾時。** 3.756s / 16.4s / 12.4s / 37.711s 全部是引擎內部的行為，FMP 這一側對它們沒有上界也沒有下界的保證。P0-2 成立，但「無限期」要改成「由引擎決定、FMP 不可預期」。

#### (f) YouTube 解析實測（Windows，未登入）

在 app 進程內直接呼叫 `YouTubeSource().getAudioStream(...)`：

| 影片 | 結果 | 耗時 | 取得的串流 |
|---|---|---|---|
| `dQw4w9WgXcQ` | audio-only 成功 | **1,486 ms** | opus, 136,544 bps |
| `kJQP7kiw5Fk` | audio-only 失敗（`VideoUnplayableException: Video is unplayable`，+953ms）→ 退到 **muxed** | **9,901 ms** | **mp4a.40.2, 666,320 bps** |
| `dQw4w9WgXcQ`（重複） | audio-only 成功 | 827 ms | 同上 |

這組數字補上了 §3.a-YouTube 缺的對照組：**audio-only 命中時只要 1.5 秒**；一旦 audio-only 失敗，光是退到 muxed 就多花 **8.9 秒**，而且拿到的是 **4.9 倍位元率的含視訊串流**。第二輪在 Android 上量到的 20 秒是同一個機制在較差網路下的樣子，不是另一個問題。同時也證實「重複解析同一首完全沒有快取」（827ms 那次仍然打了完整 API）。

#### (g) Netease：這台 Windows 上沒有登入，而未登入的錯誤訊息是錯的

```dart
NeteaseAccountService(isar: Isar.getInstance('fmp_database')!).getAuthHeaders()
  .then((h) => AppLogger.info('hasAuth=${h != null} keys=${h?.keys.toList()}', 'PROBE'))
→ 14:30:28.951 [PROBE] PROBE hasAuth=false keys=[]
```

**所以 P1-8（`MediaHandoff` 的 Netease redirect preflight）本輪仍無法實測** —— preflight 的進入條件是 `request.streamResolutionAuth != null`（`media_handoff.dart:100-106`），未登入時**根本不會執行**。這一項需要一個已登入的 Netease 帳號。

但同一組探測意外證實了另一件事。未登入時呼叫 `NeteaseSource().getAudioStream(...)`：

```
PROBE-NE 347230     FAIL 306ms  err=NeteaseApiException(-10): VIP song, payment required
PROBE-NE 1824020871 FAIL  89ms  err=NeteaseApiException(-10): VIP song, payment required
PROBE-NE 2058263032 FAIL  90ms  err=NeteaseApiException(-10): VIP song, payment required
```

直接把 eapi 的原始回應打出來（同一個 dio、同一組 header）：

| songId | fee | flag | code | url | FMP 判定 | 使用者看到 |
|---|---|---|---|---|---|---|
| 347230 | **0** | 4 | **404** | NULL | `-10` vipRequired | 需要 VIP 或付費播放權限 |
| 1824020871 | **0** | 260 | **404** | NULL | `-10` vipRequired | 需要 VIP 或付費播放權限 |
| 2058263032 | **0** | 260 | **404** | NULL | `-10` vipRequired | 需要 VIP 或付費播放權限 |
| 29814898 | **0** | 4 | **404** | NULL | `-10` vipRequired | 需要 VIP 或付費播放權限 |
| 5261821 | **0** | **256** | **404** | NULL | `-404` unavailable | 無可用音源 |

**【事實】五首 `fee = 0`（非付費）、`code = 404`、`url = NULL` 的曲目，只因為 `flag` 的第 2 位不同，被分成兩種完全不同的使用者訊息。** 成因是 `_classifyStreamUnavailable`（`netease_source.dart:877-931`）的判斷順序：`_isVipRequiredStreamError` 排在最前面，而它的規則之一是 `if (flag != null && (flag & 4) != 0) return true`（`:958`）。`flag & 4` 一命中就直接回 `-10`，後面針對 `code` 的 301 / 403 / 404 分支永遠碰不到。

- `fee = 0` 明確表示不是付費歌曲，卻仍被判為 VIP —— 判斷依據自相矛盾。
- `netease_source.dart:22` 的註釋自己就寫著「`/eapi/*` —— eapi 加密（音頻流獲取，**需登入**）」。「未登入」是已知且預期內的狀態，卻沒有對應的錯誤碼。
- `SourceErrorKind.loginRequired` 與 i18n 字串 `sourceErrorLoginRequired`（「需要登入後播放」）**都已經存在**（`netease_exception.dart:37`、`lib/i18n/zh-TW/audio.i18n.json:15`），但只掛在 `numericCode == 301` 上 —— 而網易在這個情境回的是 404。**正確的字串就在 repo 裡，只是永遠不會被選到。**

【推論】對一個沒登入 Netease 的使用者：搜尋照樣出結果、點下去等 0.1–0.3 秒、然後被告知「需要 VIP 或付費播放權限」。他不會知道其實只要登入就能播。

補充【事實】：匿名註冊（`/eapi/register/anonimous`，`scratchpad/ne_anon.ps1`）拿到的帳號在**我當時挑的那 10 首**上同樣全部 `url = NULL`。

> **【第六輪更正】** 由此推出的「Netease 播放**沒有可用的匿名路徑**，登入是硬性前提」**是錯的** —— 那 10 首是有偏樣本（熱門曲）。免費曲目（如 `139774`）匿名就能拿到 320kbps 的 URL 並實際播放，見 §12.18(d)。正確的說法是：**Netease 匿名可播，但可播的比例低**，所以未登入使用者踩到 P1-10 那條錯誤訊息的機率很高。

#### (h) 本輪對使用者環境的影響

- 沒有修改任何程式碼、設定或資料庫內容；`git status` 只有本報告一個未追蹤檔案。
- 兩台裝置上各建立過額外的後端播放器實例（音量 0，播放本機產生的靜音 WAV），實驗結束後 `dispose()`。
- 沒有登入／登出任何帳號，沒有新增或刪除任何歌單、電台、下載。
- 本機測試伺服器只綁在 loopback（Windows）與 `0.0.0.0`（供模擬器經 `10.0.2.2` 連入），只回傳程式產生的靜音 WAV，實驗結束後關閉。

---

### 12.15 P1-8 的 preflight 實測，與 #41 的根因定位

#### (a) `MediaHandoff` 的 Netease redirect preflight —— 終於量到了，但不是用登入帳號

先前卡在「沒有已登入的 Netease 帳號 ⇒ 拿不到 eapi 簽名 URL ⇒ preflight 不會執行」。繞過方式：preflight 的進入條件不是「URL 來自 eapi」，而是 `SourceHttpPolicy.canAttachNeteaseMediaCredentials(url)`（`source_http_policy.dart:135-147`），它只要求 **scheme 是 https** 且 host 屬於 `music.163.com` / `*.music.163.com` / `music.126.net` / `*.music.126.net`。所以拿一個公開的 Netease https URL 就能驅動**真正的** `DefaultMediaHandoff.preparePlayback`。

在 app 進程內直接呼叫（`targetId = media_handoff.dart`，auth 用一組假的 `Cookie: PROBE=1`）：

```
[I] 15:09:48.159 [PROBE] MH 216ms in=https://music.163.com      out=http://music.163.com       creds=false hdrs=[Origin, Referer, User-Agent]
[I] 15:09:48.347 [PROBE] MH 186ms in=https://m701.music.126.net out=https://m701.music.126.net creds=true  hdrs=[Origin, Referer, User-Agent, Cookie]
[I] 15:09:48.347 [PROBE] MH   0ms in=http://m701.music.126.net  out=http://m701.music.126.net  creds=false hdrs=[Origin, Referer, User-Agent]
```

三個結論：

1. **【事實】preflight 在「完全沒有 redirect」的情況下仍然要 186ms。** 第二行的 URL 是 `m701.music.126.net` 上一個不存在的路徑，一次 HEAD 直接拿到非 3xx 就結束 —— 這 186ms 是**每一次 Netease 播放都要先付的固定串行成本**，加在 §3.a 的解析成本之上。P1-8 原本寫的是「最壞 5×30s」，那個上界（5 hop × 30s receive timeout，`media_handoff.dart:142-242` + `AppConstants.networkReceiveTimeout`）依然成立，但**日常成本是 ~190ms/次**，這才是真正會被使用者感覺到的數字。

2. **【事實】credential 剝除邏輯是對的。** 第一行的 `https://music.163.com/song/media/outer/url?id=...` 被 302 導到 **`http://`**（scheme 降級），preflight 正確判定不可附帶憑證，回傳的 header 裡沒有 `Cookie`。這一段設計沒有問題。

   主機端獨立追蹤同一條鏈（PowerShell，`-MaximumRedirection 0` 逐跳）：三首曲目都是 `https://music.163.com` → **`http://music.163.com`** → `https://music.163.com` → 200，總耗時 819 / 578 / 588 ms。

3. **【事實】整個機制是 scheme 閘控的。** 第三行：同一個 host、同一組 auth，只把 scheme 改成 `http`，`preparePlayback` **0ms 返回**，preflight 完全不執行、Cookie 也不附帶。

   > **【第六輪已解答】** eapi 回的是 **`http://m801.music.126.net/...`**（實測，§12.18d）。所以上面那句「如果 eapi 回的也是 http，那 preflight 與 Cookie 附帶這整套機制在生產環境根本不會被觸發」**成立**：本節量到的 186ms 是一個**在真實播放路徑上不會發生**的成本。repo 內的測試（`test/services/media/media_handoff_test.dart:56, 105`）用 `https://m701.music.126.net/...`，是一個 eapi 不會產生的 URL 形狀。P1-8 已由「要優化的 190ms」改判為「一段死碼」。

> 【建議・S・可逆】在 `NeteaseSource.getAudioStream` 拿到 URL 時 log 一次 scheme（不 log URL 本身），就能在下次有帳號時零成本回答這個問題。

#### (b) #41 —— 從「無法重現」升級為「根因確認」

第三輪的結論是「三個輸出裝置全部試過都正常，無法非侵入式重現」。第四輪用兩步把它定位完成，全程沒有動使用者的音訊裝置。

**第一步：排除「裝置選擇」路徑。** 用一個不存在的裝置名驅動獨立的 `MediaKitAudioService`：

```
15:10:27.956 [I] [MediaKitAudioService] Setting audio device: wasapi/{00000000-0000-0000-0000-000000000000} (nonexistent probe device)
15:10:27.956 [W] [MediaKitAudioService] Audio device not found: wasapi/{0000...}, falling back to auto
15:10:28.042 [I] [PROBE] DEV-PLAY ok 84ms dur=0:00:30.000000 playing=true
15:10:40.044 [I] [PROBE] DEV after 12s: playing=true state=ready pos=0:00:11.940313
```

**【事實】`setAudioDevice` 已經有防禦**（`media_kit_audio_service.dart:617-630`）：在 `_player.state.audioDevices` 裡找不到就 `logWarning` 並退回 `AudioDevice.auto()`，播放完全正常（12 秒實際前進 11.94 秒）。所以 #41 描述的症狀**不是**從「裝置選擇」來的。

**第二步：定位真正的觸發點 —— mpv 的 audio output 初始化失敗訊息。** 把 mpv 在 ao 層失敗時會輸出的字串丟給活著的 `AudioController` 分類：

| mpv / ao 錯誤字串 | `_isStringNetworkError` | `_isStringMediaOpenError` | 結果 |
|---|---|---|---|
| `Could not open/initialize audio device -> no sound.` | ❌ | **✅** | 判定為「媒體開啟失敗」 |
| `[ao] Could not open/initialize audio device -> no sound.` | ❌ | **✅** | 同上 |
| `AO: [wasapi] init failed` | ❌ | ❌ | **靜默丟棄** |
| `Failed to initialize audio device` | ❌ | ❌ | **靜默丟棄** |
| `audio device not found` | ❌ | ❌ | **靜默丟棄** |

第一行命中的原因是 `_isStringMediaOpenError` 的關鍵字表含 `'could not open'`（`audio_provider.dart:2975-2980`）—— 它想抓的是「**媒體**開不起來」，卻抓到了「**音訊輸出裝置**開不起來」。

**完整因果鏈（後半段為讀碼）**：

```
mpv ao 初始化失敗
  → errorStream 收到 'Could not open/initialize audio device -> no sound.'
  → _isStringMediaOpenError = true                        (audio_provider.dart:2975-2980)
  → PlaybackRequestSession.onMediaOpenError               (:338-400)
      → 等 _mediaOpenRecoveryDelay 後檢查 position 是否前進
      → 沒有音訊輸出 ⇒ position 不會前進 ⇒ 判定「未恢復」
      → cancelActive() + _audioService.stop()
      → terminalMessage = t.audio.playbackFailedTrack(title:)
  → 使用者看到「播放失敗: <歌名>」，歌被停掉
```

`playbackFailedTrack` 的中文字串是 `"播放失敗: $title"`（`lib/i18n/zh-TW/audio.i18n.json:6`）—— **與 issue #41 的描述逐字吻合**。

【推論】issue 標題說的「音訊輸出裝置失效被誤判成『播放失敗』」是準確的，而且比原本以為的更具體：不是分類邏輯「沒有考慮裝置錯誤」，而是**裝置錯誤的字串剛好落進了媒體錯誤的關鍵字表**。同時另外兩種可能的 ao 失敗訊息會被完全丟棄 —— 所以同一個硬體問題，使用者可能看到「播放失敗」，也可能什麼都看不到、音樂就是不出聲。

**這也說明為什麼加關鍵字治不好**：`could not open` 這個子字串在兩種語意上都成立。正解是 §8.1(A) 的 `OutputDeviceFailed` —— 由後端在知道自己是 ao 錯誤的當下就標好型別，而不是讓上層猜字串。

**仍未做的**：真正讓音訊裝置失效的實機重現。剩下的做法（停用使用者正在使用的輸出裝置、或用 WASAPI 獨佔模式占住端點）都會干擾使用者，本輪不做。上面的鏈條中，「mpv 會輸出這個字串」是 mpv 的既有行為（`ao.c` 的標準訊息），「FMP 收到後會怎麼做」是本輪對活物件實測 + 讀碼確認。

---

### 12.16 `flutter_js` 插件原型 —— 跑起來了，而且推翻了 §7.2 的兩條假設

第二輪的 §7.2 是純文獻調查。本輪做了實際的 spike：一個獨立的 Flutter Windows 專案（**不碰 FMP 的 repo**），用 `flutter_js: ^0.8.7` 載入一個**完全用 JavaScript 寫的 Netease 音源插件**，實作 `search` 與 `getAudioStream` 兩個 capability。

專案位置（實驗用，跑完刪除）：`%TEMP%\jss`。插件本體 4,132 bytes JS + 60,819 bytes 的 CryptoJS 4.2.0。

> 註：一開始把 spike 放在 session scratchpad 下，CMake configure 直接失敗（`DirectoryNotFoundException ... cmTC_xxx.tlog`）—— 那個路徑深度已經超過 MSVC 的 tlog 路徑上限。換成 `%TEMP%\jss`（36 字元）就正常。**這一條值得記進 skill**：Windows 上任何要跑 CMake/MSVC 的暫存專案都不能放在深層 scratchpad。

#### 執行結果（逐字）

```
SPIKE engine=QuickJsRuntime2 init=…
SPIKE crypto-js load=7ms bytes=60819 err=false
SPIKE plugin load=0ms bytes=4132 err=false
SPIKE manifest={"id":"netease.spike","name":"Netease (JS spike)","capabilities":["search","audioStream"],"apiVersion":1}
SPIKE cryptoSelfTest=0ms len=288 head48=FA90B329E9614F79E79598F37DC2EDB487F00D1BC4C9B24C tail32=AAC9A105624D96449F79D15BA05FA39A
SPIKE crypto x100=47ms (0.47ms each)
SPIKE search=452ms err=false -> [{"sourceId":"5257138","title":"屋顶","artist":"周杰伦, 温岚, 吴宗宪","durationMs":319039,…}, …]
SPIKE getAudioStream=384ms err=false -> {"url":null,"bitrate":null,"container":null,"expirySeconds":1200,
                                          "raw":{"fee":0,"flag":4,"code":404,"message":null}}
SPIKE probe typeof globalThis.fetch = function
SPIKE probe typeof XMLHttpRequest  = function
SPIKE probe typeof setTimeout      = function
SPIKE probe typeof console         = object
SPIKE probe typeof require         = undefined
SPIKE probe typeof process         = undefined
SPIKE probe typeof crypto          = undefined
SPIKE probe typeof WebAssembly     = undefined
SPIKE probe typeof std             = undefined     (QuickJS 的 std 模組)
SPIKE probe typeof os              = undefined     (QuickJS 的 os 模組)
SPIKE TOTAL=1185ms
```

#### 兩條被推翻的假設

**1. §7.2 寫「`flutter_js`⋯**無內建加密**（需宿主提供）」—— 這是對的但結論下錯了。**

QuickJS 確實沒有 WebCrypto（`typeof crypto = undefined` 已證實），但**插件可以自帶加密庫**。spike 把 CryptoJS 4.2.0 min 當成插件資產一起載入，用它做網易 eapi 的 `MD5 + AES-128-ECB/PKCS7`，產出的 `params`：

| 來源 | 長度 | 前 48 字元 |
|---|---|---|
| QuickJS + CryptoJS（插件內） | 288 | `FA90B329E9614F79E79598F37DC2EDB487F00D1BC4C9B24C` |
| .NET `System.Security.Cryptography`（主機端獨立計算） | 288 | `FA90B329E9614F79E79598F37DC2EDB487F00D1BC4C9B24C` |

**逐字元相同**（tail 32 也相同）。速度：**0.47 ms/次**，在一次 300ms 的網路請求面前可以忽略。

所以「宿主必須提供加密原語」不是技術限制，而是**設計選擇**。Mangayomi 選擇由宿主提供（`encryptAESCryptoJS`）有它的理由 —— 統一實作、避免每個插件各自打包 60KB、也讓宿主能審計用了什麼演算法 —— 但 FMP 不是非這樣不可。這改變了 §7.3「必須留在宿主」清單的組成。

**2. §7.2 寫「桌面需額外建置 `quickjs-c-bridge`」—— 在 Windows 上不需要。**

實測流程只有 `flutter pub get` → `flutter run -d windows`，`flutter_js` 0.8.7 自己把 Windows 的 QuickJS 產物帶進來了，沒有任何額外步驟、沒有手動編譯。

> **【第七輪補充】Android 不是這樣。** 同一份 spike 在 Android 上**開箱即壞**（`:flutter_js:compileDebugKotlin` 的 JVM-target 衝突），要在宿主的 `android/build.gradle.kts` 加 5 行才過。所以「不需要額外建置」只對 Windows 成立，對 Android 不成立。見 §12.19(b)。（Linux 仍未驗證。）

#### 三條被證實的

**1. 非同步 HTTP 橋接可用，而且是宿主控制的。** `getJavascriptRuntime(xhr: true)` + `enableFetch()`（在 `package:flutter_js/extensions/fetch.dart`，**沒有**被 `flutter_js.dart` re-export，必須顯式 import）讓 JS 側的 `fetch()` 走 Dart 的 http。搜尋 452ms、取流 384ms，跟 FMP 原生 Dart 路徑同一個量級（§12.14g 的原生量測是 89–306ms，外部 PowerShell 是 226–554ms）。CJK 查詢字串與回應（「屋顶 / 周杰伦, 温岚, 吴宗宪」）完整無誤。

**2. 沙箱邊界很乾淨。** `require` / `process` / `std` / `os` / `WebAssembly` **全部 undefined** —— 插件拿不到檔案系統、拿不到子程序、載不了原生模組。它唯一的對外能力就是宿主給的 `fetch`/`XHR`。這是插件化在**安全面**最重要的一條，而且不需要 FMP 自己實作沙箱。

> 【重要的但書】`fetch` 走宿主不等於宿主有在管。spike 裡的插件自己塞了 `Cookie` / `Referer` / `Origin` header 而且**全部生效**。所以若要上線，`SourceHttpPolicy` 必須擋在橋接層：插件只能宣告「我要用某個帳號的憑證」，由宿主決定實際附什麼 header、能打哪些 host。**這一條應該取代 §7.3 裡「加密留在宿主」成為第一條約束。**

**3. 錯誤分類該留在宿主，而且插件介面天然支援。** spike 的 `getAudioStream` 刻意回傳 `raw: {fee, flag, code, message}` 而不自己判斷 —— 拿到的正是 §12.14(g) 那組 `fee=0, flag=4, code=404`。這證明「插件負責取資料、宿主負責判斷語意」在介面上是自然的，而 P1-10 那個 bug 恰好就是**把判斷寫在音源實作裡**造成的。插件化如果做，應該順手把這個邊界立對。

#### 對 §7.4 順序的影響

原本的建議順序不變（先統一內建三源，再談插件），但 spike 把「插件路線可行性」從「文獻上看起來可行」推進到「**在 Windows 上跑通了一個真的能搜到歌的 JS 插件，1185ms 端到端**」。~~剩下沒有驗證的是：Android 上的 `flutter_js`、插件的安裝／更新／簽章流程、以及 `youtube_explode_dart` 這種**必須留在宿主**的重依賴要怎麼透過介面暴露給插件。~~ **這三項第七輪都做完了，見 §12.19(b)(c)(d)。**

---

### 12.17 AOT／profile build 對照 —— 做了，結論是「在 AOT 下沒有任何觀測手段」

附錄第 3 項先前寫「`evaluate` 可以在執行期呼叫 `AppLogger.setMinLevel`，所以這一項技術上已無阻塞」。**這句話是錯的，本輪已證實。**

#### (a) profile build 本身是好的

`flutter build windows --profile` 成功，154.5s，產出 `build/windows/x64/runner/Profile/data/app.so`（22,414,216 bytes 的 AOT snapshot，且 `flutter_assets` 下**沒有** `kernel_blob.bin`）—— 是真正的 AOT。

> 【自我更正】本輪稍早有一次 `flutter run --profile` 在 584 秒後以 `error MSB3073 ... INSTALL.vcxproj` 失敗。原因是**我自己造成的**：當時另一個 debug 的 `fmp.exe` 還在執行，鎖住了 INSTALL 步驟要覆寫的輸出檔。把它關掉之後重跑就成功了。**FMP 的 profile build 沒有問題**，不要把它當成 repo 的缺陷。（順帶：`smtc_windows/cargokit/cmake/resolve_symlinks.ps1` 那個 `Get-Item : 找不到 C:\Users\Roxy\AppData 項目` 的 PowerShell 錯誤在 debug 與 profile 兩種模式下都會出現，而兩種模式都能成功建置，所以它是噪音不是故障。）

#### (b) AOT 下 DEBUG log 全部消失 —— 實測

直接執行 AOT 的 `fmp.exe`，完整啟動流程的 stdout 共 67 行，**`[DEBUG]` 行數 = 0**；以 `flutter run --profile` 附掛執行則是 82 行（去掉 AXTree spam 後），**`[DEBUG]` 行數同樣 = 0**。也沒有 Isar Connect 橫幅。

這正是 `logger.dart:56` 的 `_minLevel = kDebugMode ? LogLevel.debug : LogLevel.info` 的預期行為 —— 但它意味著 §12.14 那套「倒 `AppLogger.logs` 拿毫秒時間軸」的方法在 AOT 下**只能拿到 INFO 以上**，而播放路徑的分段時間戳全部是 `logDebug`。

#### (c) `evaluate` 在 AOT 下不可用 —— 有明確的錯誤訊息

在 `flutter run --profile` 附掛（也就是 `compileExpression` 服務有註冊）的情況下求值：

```
evaluate(isolateId=…, targetId=libraries/@25281243, expression="1+1")
→ {"code":113,"message":"Expression compilation error",
   "data":{"details":"Debugger is disabled in AOT mode."}}
```

跟 §12.14(a) 在 debug 下遇到的 `No compilation service available`（那是走錯協定）**不是同一件事**：這一次是 AOT runtime 本身拒絕。因此：

- 不能在 AOT 進程裡呼叫 `AppLogger.setMinLevel(LogLevel.debug)`；
- 不能倒 log buffer、不能對活物件呼叫私有方法、不能起獨立後端做受控實驗。

**結論：Q16（把 `setMinLevel` 接到開發者選項）不是「錦上添花」，而是 profile/release 下唯一可能的觀測入口。** 附錄第 3 項的「技術上已無阻塞」更正為「仍然阻塞，而且原因比原本寫的更硬」。

#### (d) 那麼 debug build 的數字有沒有被灌水？

無法用 AOT 直接對照（見上），但有兩組獨立證據指向「沒有實質灌水，因為這些數字是網路主導的」：

| 同一個 Netease eapi 請求 | 環境 | 耗時 |
|---|---|---|
| FMP 內部（**debug** Dart + dio） | §12.14(g) | **89 / 90 / 306 ms** |
| 主機 PowerShell（完全沒有 Dart） | §12.14 前置量測 | **226 / 554 ms** |
| QuickJS 插件 + Dart http（**debug** Flutter） | §12.16 | **384 ms** |

**debug 的 Dart 路徑反而是三者中最快的。** 若 JIT 開銷是主導項，不可能出現這個排序。同理，§12.14(e) 的 6.111s / 12.4s / 37.7s 是引擎與伺服器行為，§12.14(f) 的 8.9 秒 muxed 退化是 YouTube 端的往返 —— 這些都不會因為換成 AOT 而改變量級。

【未驗證】UI 相關的量測（例如點擊→出聲的**畫面**部分、frame 時間）在 AOT 下確實會明顯不同，本輪沒有量。要量的話唯一路徑是先做 Q16，或改用 `getVMTimeline`（在 AOT 下仍可用）。

---

### 12.18 第六輪：對齊改寫後的遠端歷史 —— 並在過程中把懸而未決的那一項做完了

本輪審查的基準 `b93f72c7` 在遠端被整段改寫成 `395305bd`（內容相同），其後多了 10 個 commit，`origin/main` 現在是 `598fce27`。本節記錄重新對基準的結果。

#### (a) 先把 `dart format` 的雜訊切掉 —— 落在本輪地盤的語意改動只有一處

`0089fe45` 對全樹跑了 `dart format`，光看 `git diff --stat 395305bd origin/main` 會以為本輪的核心檔案全被動過。把歷史從那個 commit 切開分別比對（`395305bd..0089fe45^` 與 `0089fe45..origin/main`）之後，真相如下：

| 檔案 | 原始 diff 行數 | 扣掉 format 後的**語意**改動 |
|---|---|---|
| `lib/data/sources/youtube_source.dart` | 63 | **6 行**：四個 InnerTube 常數改指向 `InnerTubeUtils`，值逐字相同；另 +1 行 import |
| `lib/core/utils/innertube_utils.dart` | 19 | 新增 `apiBase` / `apiKey` / `clientName` / `clientVersion` 四個常數 + 說明註解 |
| `lib/services/account/youtube_account_service.dart` | 11 | 同上，改指向 `InnerTubeUtils` |
| `lib/services/audio/audio_handler.dart` | 11 | **0**（三元運算子換行） |
| `lib/services/audio/audio_provider.dart` | 3 | **0**（一行 `subscribe(...)` 折行） |
| `lib/services/audio/audio_types.dart` | 4 | **0**（enum 成員之間插空行） |
| `lib/services/audio/temporary_play_handler.dart` | 5 | **0** |
| `lib/data/sources/playlist_import/qq_music_sign.dart` | 37 | **0**（常數陣列每個元素一行） |
| `test/services/radio/radio_controller_phase2_import_test.dart` | 74 | **0** |
| `test/services/audio/queue_persistence_manager_test.dart` | 37 | **0** |
| `test/data/sources/youtube_source_test.dart` | 12 | **0** |
| `test/bilibili_source_test.dart` | 7 | 兩條測試加上 `tags: 'live'` |
| `test/live/sources_live_test.dart` | +143 | 全新檔案 |

**所以本報告的結論一條都沒有被上游改動推翻。** 唯一實質變更是 InnerTube 常數去重（`d61e602d`），而四個常數的值逐字未變，`getAudioStream` 的控制流也未變 —— **P0-3 完全不受影響**。

**行號校正（做完了）**：本報告共 198 條 `file:line` 引用。逐條拿 `395305bd` 與 `origin/main` 的同一行內容對比後，**37 條因為 format 位移需要改號**，涉及 5 個檔（`audio_provider.dart` +1、`youtube_source.dart` +1 或 −1、`audio_types.dart` +4、`audio_handler.dart` +5、`playlist_import_source.dart` +3）。全部已改成新行號，並逐條確認新行號指到的原始碼與舊行號**逐字相同**。其餘 161 條原地成立。

> 【方法備忘】直接用 `git diff -w` **不足以**濾掉 `dart format` —— 它會折行與併行，`-w` 只忽略空白量而不管換行位置。可靠做法是把 format commit 當分界，分兩段比對。

#### (b) 新增的 `test/live/` 獨立重現了本報告的兩條結論

`flutter test test/live/sources_live_test.dart` 實跑（2026-09-01，Windows，未登入任何帳號），14 秒，`+2 ~1`：

```
00:00 +0: bilibili: search resolves to playable audio
[ERROR] [BilibiliSource] Bilibili Dio error: type=DioExceptionType.badResponse,
        statusCode=412, response={code: -412, message: request was banned, ttl: 1}
[WARN]  [BilibiliSource] Bilibili rate limited (HTTP 412)
  Bilibili refused the anonymous request (-429). ...
00:00 +0 ~1: youtube: search resolves to playable audio
[DEBUG] [YouTubeSource] Audio-only stream failed for FtutLA63Cp8: VideoUnplayableException
        ... Reason: Sign in to confirm you're not a bot
[DEBUG] [YouTubeSource] Got muxed stream for FtutLA63Cp8: 290.80 Kbit/s, mp4
00:11 +1 ~1: netease: search resolves to playable audio
[DEBUG] [NeteaseSource] Got audio stream for 139774: 320kbps, type: mp3, expi: 1200s
00:14 +2 ~1: All tests passed!
```

兩條獨立重現：

1. **Bilibili 匿名請求撞風控**（HTTP 412 → `-412 request was banned` → 對外變成 `-429`）—— 與 §12.14(b) 完全一致，這次是 repo 自己的測試在報。
2. **P0-3 的第三次獨立重現**：audio-only 被 `Sign in to confirm you're not a bot` 擋下，退化成 **290.80 Kbit/s 的 muxed mp4**（含視訊軌）。前兩次分別是 §3.a-YouTube（Android 實機）與 §12.14(f)（Windows VM Service）。

> **但要注意這個測試不會讓 P0-3 變紅。** 它 assert 的是「`stream.url` 拿得到、位元組拿得到」，muxed 退化在它眼裡是**通過**。所以 P0-3 仍然沒有任何自動化守門 —— 這反而強化了 §4 對 P0-3 的定級。

#### (c) CI 的 tag 佈局：三件必查的對照結果

- `flutter test --coverage --exclude-tags live` + `dart_test.yaml` 宣告 `live`，屬實。
- **補一條清單沒提到的**：`test/bilibili_source_test.dart:668` 與 `:798` 也各有一個**逐測試**的 `tags: 'live'`（不是檔案級 `@Tags`），一樣會被 `--exclude-tags live` 排除。檔案級 `@Tags` 全庫確實只有 `test/live/sources_live_test.dart`。
- **一個我自己排掉的假陽性**：`rg "tags: '"` 會命中 `test/services/radio/radio_source_live_client_test.dart:33` 的 `tags: 'music'` —— 那不是測試 tag，是 `BilibiliLiveRoomDetails` 的欄位值。
- **本報告（02）沒有任何一條結論建立在「音源測試打真實網路」上**，所以這一項對 02 沒有改寫。它落在第 01 輪的地盤，而 01 已經自己對照過了（`01-docs-structure-tests.md:87`），結論是「方向正確但沒蓋到原本那個檔」。我抽驗了這一條：`test/demo/bilibili_info_test.dart` 至今**沒有任何 tag**（全檔唯一的 `tags` 字樣在 `:35`，是 `print('tags: ...')`），`main()` 開頭仍是無 try/catch 的 `dio.get('https://api.live.bilibili.com/room/v1/Room/room_init')`（`:17-20`），檔名仍符合 `*_test.dart` —— **`--exclude-tags live` 排不掉它**。01 的說法成立。
- 另外 `ce100d32` 刪掉了 `Verify generated files are committed`、`c1fc0b4b` 新增 `dart format --set-exit-if-changed lib test` 閘門、所有 job 補上 `timeout-minutes`、actions 全部釘 SHA —— 都落在 01 的 P1-7 / issue #38 上，01 已記錄。

#### (d) **eapi 回的是 `http://`：P1-8 從「要優化的 186ms」改判為「跑不到的程式碼」**

這是本輪最重要的一條，而且**不需要登入帳號就做完了** —— 是新的 `test/live/` 讓我發現前提錯了。

第五輪我寫「匿名帳號實測拿不到任何 URL（10 首全 `url = NULL`）」，因此認定必須登入才能看到真實的媒體 URL。**那個結論來自一個有偏的樣本**（我當時挑的是熱門曲）。`test/live/` 用「純音樂」這種免費曲目去問，匿名路徑**拿得到 URL**：

```
[DEBUG] [NeteaseSource] Got audio stream for 139774: 320kbps, type: mp3, expi: 1200s
```

而匿名與登入走的是**同一個 eapi 端點、同一個 `data[0].url` 欄位**（`netease_source.dart:132-200`，差別只在 `_withAuth(authHeaders)` 有沒有塞 Cookie），URL 原樣回傳，全 repo 沒有任何 scheme 改寫（`rg` 查無 `replaceFirst('http` / `.replace(scheme` / 任何 `http://` 字面量）。

主機端直接打同一個 eapi（PowerShell + .NET 的 MD5/AES-128-ECB，**無 Cookie**，與 §12.16 逐字元驗證過的同一組加密）：

```
id=139774   fee=8 flag=6   code=200  SCHEME=http  host=m801.music.126.net  br=320000 type=mp3
id=347230   fee=0 flag=4   code=404  url=<null>
id=5257138  fee=0 flag=260 code=404  url=<null>
```

**【事實】eapi 回的媒體 URL 是 `http://m801.music.126.net/...`。** 而 `canAttachNeteaseMediaCredentials`（`source_http_policy.dart:135-147`）第一件事就是 `uri.scheme != 'https' → return false`。串起來：

- `_shouldPreflightNeteasePlayback`（`media_handoff.dart:100-106`）永遠回 false → **那 186ms 的 HEAD 預檢、以及「最壞 5×30s」的上界，在生產環境從來不會執行**。
- `_prepareHeaders` 的 `credentialsMayAttach`（`media_handoff.dart:108-121`）永遠 false → `SourceHttpPolicy.mediaHeaders` 的 Cookie 分支（`source_http_policy.dart:57-67`）**永遠不會把 Netease 的 Cookie 附到媒體位元組請求上**。
- 這一條**播放與下載都適用**：`prepareDownloadHop` 走的是同一個 `_prepareHeaders`（`media_handoff.dart:95-98`），唯一的下載端呼叫點在 `download_service.dart:1709`。

這件事要分三層看，三層的結論不同：

1. **【事實】安全上這道閘是對的。** 拒絕把工作階段 Cookie 送上明文 http 是正確防護。**所以不該用「放寬 https 檢查」來讓這段程式碼活過來。**
2. **【事實】一整組機制在生產環境跑不到**：preflight 迴圈（`media_handoff.dart:142-242`）、`NeteasePlaybackRedirectResolver` 這個注入點、以及 `mediaHeaders` 的憑證分支。而 repo 的測試把它們全部測成「會執行」—— `test/services/media/media_handoff_test.dart` 的每一條 happy path 都用 `https://m701.music.126.net/...`（`:56, 102, 105, 112, 116, 134, 154, 158`），一個 eapi 不會產生的 URL 形狀。**測試全綠，生產零命中。**
3. **【推論】它很可能本來就不需要。** 音質是在 **eapi 解析當下**由帳號決定的，而那一步的 Cookie 是有送的（`netease_source.dart:156` 的 `_withAuth(authHeaders)`）。媒體位元組拿的是已簽名的 CDN URL，帶不帶 Cookie 大機率無關。若是如此，正解是**刪掉**這套機制，而不是修好它。

**因此 P1-8 重新定級**：從「每次播放固定 186ms 的串行成本」改成「**約 150 行的預檢機制 + 一個注入點 + 一整組測試，在生產環境一次都不會執行**」。它不傷害使用者，效能面的急迫性消失；但它是**死碼 + 假覆蓋率**，而且掩蓋了一個真問題：如果 FMP 哪天真的需要用帳號憑證去取媒體位元組，現在這條路是斷的，**沒有任何測試會告訴你**。

~~【推論・未驗證】已登入路徑仍無法直接量。~~ **【第七輪已實測，見 §12.19(a)】已登入的 eapi 同樣回 `http://`**，而且在真實生產路徑上量到：preflight 2ms 跳過、Cookie 被剝掉、真實簽名 URL **0 跳轉**。本節的推論全部被實測證實，不再有未驗證成分。

> 這也讓 Quick win **Q28 失效**：它原本是「log 一次 scheme 來回答這個問題」，現在問題已經有答案，該做的變成 §9 的一個決策（刪或修）。

#### (e) `flag & 4` 不是 VIP 訊號 —— P1-10 的證據再強化

上面三筆的 `flag` 值順帶回答了 §12.14(g) 沒問完的問題：

| song id | `fee` | `flag` | `flag & 4` | `code` | 實際結果 |
|---|---|---|---|---|---|
| 139774 | 8 | 6 | **≠0** | 200 | **拿到 320kbps URL，匿名可播** |
| 347230 | 0 | 4 | ≠0 | 404 | `url = null` |
| 5257138 | 0 | 260 | ≠0 | 404 | `url = null` |

**【事實】`flag & 4` 在「能播」與「不能播」的曲目上都成立**，它不帶任何 VIP 資訊。而 `_isVipRequiredStreamError`（`netease_source.dart:958`）把 `flag & 4 != 0` 當成「需要 VIP」的判準，並且排在 `code == 404` 分支之前（`:877-931`）。P1-10 的定級不變，但根據從「未登入時 `flag` 剛好是 4」變成「**`flag & 4` 這個判準本身就是錯的**」。

#### (f) 本輪對環境的影響

- 只跑了既有測試（`flutter test test/live/sources_live_test.dart`）與一個主機端 PowerShell 探測腳本（`scratchpad/eapi_scheme.ps1`），**沒有改動 `lib/`、`test/`、`.github/`，沒有 git 操作**。
- Netease eapi 探測是唯讀查詢，未附任何憑證，未下載媒體位元組。

### 12.19 第七輪：Netease 已登入路徑實測，與插件化的 Android／分發面

本輪把附錄剩下的兩項有實質內容的做完：使用者登入 Netease 之後的實測，以及 §12.16 只驗了 Windows 的插件路線。

#### (a) 已登入的 eapi 也回 `http://` —— P1-8 的最後一個【未驗證】關掉

方法與第四／五輪相同：`flutter run -d windows`（debug），VM Service over WebSocket（本機 port 56810），對活著的 `DefaultStreamResolutionService` 實例求值。**沒有改任何一行程式碼、沒有送任何輸入事件**，也沒有把使用者的工作階段憑證取出到進程外。

**第一步，確認登入狀態與 header 形狀：**

```
[I] 19:22:18.935 [PROBE] NE-AUTH keys=[Cookie, Origin, Referer, User-Agent] hasCookie=[REDACTED]
```

> **順帶一條【事實】**：我原本想印 `hasCookie=true cookieLen=<N>`，整段被 `AppLogger` 的敏感詞遮蔽成 `[REDACTED]`。這個機制是對的，而且有守門測試（`test/core/logger/redaction_test.dart`）。值得記一筆 —— 它讓「在 log 裡做憑證相關的排查」天然安全。

**第二步，用真實帳號解析三首**（`_sourceAuthContext.authForPlay(SourceType.netease)` → `_sourceManager.audioStreamSource(...)!.getAudioStream(...)`）：

```
[PROBE] NEURL id=347230  ERR=NeteaseApiException NeteaseApiException(-10): VIP song, payment required
[PROBE] NEURL id=5257138 ERR=NeteaseApiException NeteaseApiException(-10): VIP song, payment required
[PROBE] NEURL id=139774  ms=98 scheme=http host=m701.music.126.net br=320000 type=mp3 pathSegs=10 queryKeys=[vuutv]
```

**【事實】已登入的 eapi 回的一樣是 `http://`。** 第六輪對匿名路徑的結論，在登入路徑上原樣成立。

（另外：347230 與 5257138 在這個帳號下**確實**是 VIP 曲，`-10 VIP song, payment required` 是正確訊息。P1-10 講的是**未登入**時同一個 `flag & 4` 分支給出錯誤結論，兩者不衝突。）

**第三步，把真實簽名 URL 丟進生產路徑**（`playbackNetworkRequest` → `DefaultMediaHandoff.preparePlayback`，`source_auth_context.dart:283-304`），並獨立追一次 redirect：

```
[PROBE] MH ms=2 inScheme=http outScheme=http outHost=m801.music.126.net unchanged=true
        hdrKeys=[Origin, Referer, User-Agent]
[PROBE] MHREDIR hops=0 ms=232 chain=http=200 finalScheme=http finalHost=m801.music.126.net
```

三條【事實】：

1. **preflight 沒有執行**：2ms 返回，URL 原封不動。
2. **Cookie 沒有附上去**：進去的 auth **有** `Cookie`（第一步），出來的 header 只有 `[Origin, Referer, User-Agent]`。**即使使用者已登入，Netease 的憑證也不會到達媒體位元組請求。**
3. **真實簽名 URL 是 0 跳轉**：HEAD 直接 200（232ms）。所以就算 preflight 跑起來，它也**什麼都不會找到** —— 第五輪量到的那 186ms 會是純粹的浪費。

**結論**：P1-8 的三個問號（登入後的 scheme、憑證是否附得上、真實跳數）現在全部有答案，而且三個答案指向同一個處置 —— **這套機制該刪，不該修**（§9 的 D8 選項 (a)）。附錄第 1 項關閉，本報告不再有與 Netease 播放路徑相關的【未驗證】。

#### (b) 插件化的 Android 側：JS 完全一致，卡住的是 Gradle

同一份插件（4,132 bytes JS + CryptoJS 4.2.0 60,819 bytes）、同一份 `main.dart`，在 AVD `Medium_Phone`（Android SDK 37 x86_64）上跑：

| 量測 | Windows（§12.16） | Android（本輪） |
|---|---|---|
| 引擎 | `QuickJsRuntime2` | `QuickJsRuntime2` |
| CryptoJS 載入 | 7 ms | 6 ms |
| 插件載入 | 0 ms | 0 ms |
| eapi params 自我測試 | len=288，`FA90B329…` / `…A05FA39A` | **逐字元相同** |
| 加密吞吐 ×100 | 47 ms（0.47 ms/次） | **23 ms（0.23 ms/次）** |
| `search('周杰伦')` | 452 ms | 2,383 ms |
| `getAudioStream('347230')` | 384 ms，`fee=0 flag=4 code=404` | 1,606 ms，**同樣的 `fee=0 flag=4 code=404`** |
| 端到端 | 1,185 ms | 4,266 ms |
| 沙箱探測 | require/process/crypto/WebAssembly/std/os 全 undefined；fetch/XHR/setTimeout/console 可用 | **完全相同** |

三條【事實】：

1. **加密輸出三方一致** —— QuickJS on Android ＝ QuickJS on Windows ＝ .NET `System.Security.Cryptography`。
2. **沙箱邊界完全相同** —— §12.16 對安全邊界的結論在 Android 上原樣成立，不需要另外驗證。
3. **加密吞吐 Android 反而快一倍**。網路慢 4–5 倍是模擬器的既知問題（§12.8 已查明是 AVD 的 DNS），不是 QuickJS 的成本。

**但 `flutter_js` 0.8.7 在 Android 上開箱即壞。** 第一次建置在 4m18s 後失敗：

```
Execution failed for task ':flutter_js:compileDebugKotlin'.
> Inconsistent JVM-target compatibility detected for tasks
  'compileDebugJavaWithJavac' (11) and 'compileDebugKotlin' (1.8).
```

根因在套件自己：`flutter_js-0.8.7/android/build.gradle:34` 寫死 `jvmTarget = JavaVersion.VERSION_1_8`，而 `:5` 是 `ext.kotlin_version = '1.7.20'`（2022 年的 Kotlin）。同一次建置 Flutter 3.47 還給了一條警告：

```
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): flutter_js
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
```

繞法是宿主端 5 行（本 spike 實際用的）：

```kotlin
subprojects {
    if (project.name == "flutter_js") {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }
}
```

> 一個踩過的坑：第一次我把這段套在**所有** subproject 上，結果 `:app` 變成 Java 17 vs Kotlin 11 再次衝突。必須只針對 `flutter_js`。

**【推論】這是一筆真實的長期維護債。** `flutter_js` 的最新版就是 0.8.7（2026-01-27 發佈，pub.dev API 查得），Android 端仍停在 Kotlin 1.7.20 + KGP，而 Flutter 已明確宣告未來版本會拒絕這類插件。走 `flutter_js` 路線等於把一個**上游停滯、且與 Flutter 演進方向相反**的元件放進建置關鍵路徑 —— 這比 §12.16 在 Windows 上得到的「零摩擦」印象嚴重得多，**§7.2 對這條路線的評分應該下修**。

**APK 體積代價【事實】**（從 spike 的 `app-debug.apk` 直接讀）：`libfastdev_quickjs_runtime.so` arm64-v8a **1,050,688 B**、armeabi-v7a **722,576 B**、x86_64 1,182,032 B。對照 §5 記的 `media_kit_libs_android_audio` 每 ABI 2.9–3.1 MB —— QuickJS 大約是它的三分之一，體積不是阻礙。

#### (c) **更正 §7.2：Flutter 音樂 app 已經有人做完插件化了 —— Spotube**

§7.2 寫「四個候選的 Flutter 音樂 app（Namida / BlackHole / Harmony-Music / Vibe）都沒有外掛式音源架構。若 FMP 走這條路，是該細分領域的先行者。」**這句話已經不成立**：上一輪的候選名單裡漏了 Spotube，而 Spotube 在 **v5.0.0（2025-09-11，GitHub releases API）** 就上線了完整的插件系統，最新版 v5.1.2（2026-06-05）。它是本報告能找到的**最直接可參照的先例**：同樣是 Flutter、同樣是音樂、同樣要處理「音源」而不只是「內容目錄」。

Spotube 的具體做法（來源：`docs.spotube.cc`）：

- **執行時**：Cash App 的 **Zipline**（`app.cash.zipline` 1.13.0），插件用 **Kotlin/JS** 寫、編譯成 JS 在沙箱裡跑。底層一樣是 QuickJS。
- **服務綁定模型**：插件在 `main()` 裡 `zipline.take(<HostAPI>_SERVICE_NAME)` 取得宿主能力、`zipline.bind(<PluginAPI>_SERVICE_NAME, impl)` 註冊自己實作的能力。
- **宿主提供的能力**：`HttpClientAPI`（**文檔明文要求「絕不可直接呼叫，必須包在 `SpotrClient` 裡」**）、`PersistedStorageAPI`、`CryptoAPI`（雜湊／MAC／金鑰對／簽章／加密）、`SystemInfoAPI`、`WebviewAPI`。
- **插件提供的能力**：`CoreAPI`、`MetadataSearchAPI`、**`AudioAPI`**、`LyricsAPI`、`ScrobbleAPI` —— 只綁自己實作的，缺的宿主會優雅處理。
- **能力宣告**：`plugin.json` 裡列 capabilities（例如網路要宣告 `"NETWORK_REQUESTS"`）與 abilities（音源要 `"AUDIO"`），宿主按宣告發服務。
- **登入**：`plugin.json` 的 `requiresAuthentication` 為 true 時宿主顯示登入按鈕 → 呼叫插件的 `login()` → 插件用**宿主的 WebView** 開 OAuth 頁、監看 redirect 取 code。
- **音源介面是兩段式**：`getStreamsByTrack()` 先回一組候選 `AudioSource` 並各帶一個 **confidence 分數（0.0–1.0）**，宿主按信心與可用音質挑；選中的若還沒有 URL，再呼叫 `getStreamsOfAudioSource()` 取真正的 `AudioStream`。
- **打包與分發**：Gradle plugin 把 Zipline 產物 + `plugin.json` 打成 **`.smplug`**；安裝來源有三種 —— 從 GitHub/Codeberg 的**非策展**清單、本機檔案、或直接貼 URL。

**三個成熟做法的分發／信任模型對照：**

| | Spotube | Mangayomi | Mihon（Tachiyomi 後繼） |
|---|---|---|---|
| 插件形式 | `.smplug`（Zipline 產物 + `plugin.json`） | 從 `index.json` 的 `sourceCodeUrl` 直接抓 `.dart` / `.js` 原始碼 | 獨立 **APK** |
| 目錄 | GitHub/Codeberg 清單，**非策展** | `index.json`（實測 363 個條目），欄位含 `version` / `appMinVerReq` / `sourceCodeLanguage` / `isNsfw` / `hasCloudflare` | 使用者自行加的 extension repo |
| 完整性驗證 | **無**。文檔明說：「這是非策展清單⋯惡意插件可以輕易竊取你的憑證，請小心」，只建議認 `Official` 標籤 | **無**。只靠 HTTPS 到 `raw.githubusercontent.com` | **有**。`ExtensionLoader.kt:369-381` 取 APK 簽章的 **SHA256**，`TrustExtension.isTrusted()` 比對「repo 宣告的 signingKey」或使用者明確信任過的 `pkg:versionCode:sigHash`；升版會重新驗（`:82-83` 要求新簽章集合包含舊的），且有 `revokeAll()` |
| 更新 | 重新下載 `.smplug` | index 裡的 `version` 變了就重抓原始碼 | 走 Android 套件安裝流程 |

**【推論】對 FMP 的建議**：如果插件化真的要做，信任模型應該抄 **Mihon**（repo 級簽章金鑰 + 逐版本 TOFU + 可撤銷），而不是 Spotube／Mangayomi 的「靠使用者自己小心」。理由是 FMP 的插件會拿到**帳號憑證**（Bilibili SESSDATA、Netease MUSIC_U），風險等級比漫畫來源高一個檔次。而介面形狀可以直接抄 Spotube —— 特別是兩段式音源解析（候選 + confidence，再解析 URL），它剛好對上 §3.a 那個「三種 streamType 全跑一遍」的問題：**把「有哪些候選」與「挑哪一個」分開，正是 P0-3 需要的結構。**

#### (d) 重依賴（`youtube_explode_dart`）要怎麼暴露

Spotube 的答案是**不暴露**：宿主只給通用能力（HTTP / 儲存 / crypto / WebView / 系統資訊），平台協定的活由插件自己用 HTTP 幹。這對 Bilibili 與 Netease 完全夠用 —— §12.16 的 spike 已經證明了 Netease 那一半。

**但 YouTube 不同**，而且差異是本質的：`youtube_explode_dart` 幫 FMP 解的是 signature cipher 與 n-param 這類**會隨 YouTube 前端改版而變**的東西，那需要在執行期抓 player JS 並求值。三個選項：

1. **YouTube 永遠留在宿主**（不做成插件）。成本 **S**，風險最低，代價是「插件化」名不副實 —— 三個內建源只有兩個能被取代。
2. **宿主暴露一個窄介面**（例如 `resolveYouTubeStream(videoId, clients)`）給插件呼叫。成本 **M**。壞處是介面洩漏了實作：一旦換掉 `youtube_explode_dart`，插件全部要改。
3. **宿主給 JS 求值能力**，插件自己實作 cipher 解析（NewPipe / yt-dlp 路線）。成本 **L**，而且很諷刺 —— 插件跑在 QuickJS 裡，卻要再開一個 JS 求值環境給 YouTube 的 player JS。

**【建議・傾向 1】**，並在 §7.4 的順序裡明說「YouTube 不進插件系統」，而不是留一個含糊的「重依賴由宿主提供」。理由：選項 2 的介面一定會漂移（`youtube_explode_dart` 本身就在追 YouTube 的變動），選項 3 把最脆弱的一段交給插件作者維護，而 §3.a 的實測顯示這一段**現在就已經在退化**（P0-3）。把它留在宿主，至少壞掉時是 FMP 自己修。

#### (e) 本輪對環境的影響

- FMP 只以 debug 模式在 Windows 上跑過一次（VM Service 觀測，無 UI 操作），結束後已 `orca terminal close`。
- 插件 spike 在 `%TEMP%\jsa`（獨立專案，**不在 FMP 的 worktree**），APK 已從模擬器 `adb uninstall`，模擬器已 `adb emu kill`。
- 使用者的 Netease 工作階段憑證**沒有**離開 app 進程，也沒有寫進任何檔案；相關 log 被 `AppLogger` 自己遮蔽。

### 12.20 第八輪：#41 的完整實機重現，與「AOT 下沒有觀測手段」的更正

#### (a) #41 —— 讓 mpv 的音訊輸出真的失敗，全程沒有碰使用者的系統裝置

前幾輪一直卡在「剩下的做法都會干擾使用者正在用的音訊裝置」。本輪找到第三條路：**不動系統裝置，改在進程內把 mpv 的 `ao` 設成一個不存在的驅動**。用的是 media_kit 的 `NativePlayer.setProperty`（`media_kit-1.2.6/lib/src/player/native/player/real.dart:1223`）—— FMP 自己就是用同一個入口設 `vid=no` / `sid=no` 的（`media_kit_audio_service.dart:250-262`），所以這不是外掛手段，是既有介面。

**第一步：獨立 `Player` 實例，播本機 30 秒靜音 WAV**（`logLevel: MPVLogLevel.warn` 以便看到完整 log）：

```
AOPROBE playing=false pos=0:00:00.000000 dur=0:00:30.000000 completed=true errCount=1 logCount=6
AOPROBE ERR> Could not open/initialize audio device -> no sound.
AOPROBE LOG> error|ao|Audio output fmp-nonexistent-ao not found!
AOPROBE LOG> error|ao|Failed to initialize audio driver 'fmp-nonexistent-ao'
AOPROBE LOG> error|cplayer|Could not open/initialize audio device -> no sound.
```

三條【事實】：

1. **mpv 真的會吐出第五輪推測的那個字串**，而且它的 prefix 是 **`cplayer`**。
2. **另外兩條 `ao` prefix 的訊息是被 media_kit 自己丟掉的，不是被 FMP 的分類器丟掉。** `media_kit-1.2.6/lib/src/player/native/player/real.dart:2085-2117` 只把 `level == 'error'` **且** prefix 屬於 `file` / `ffmpeg`（限 `tcp:` 開頭）/ `vd` / `ad` / `cplayer` / `stream` 的訊息轉進 `errorController` —— **`ao` 不在名單裡**。
   > **這修正了第五輪的歸因。** §12.15(b) 的表格把 `AO: [wasapi] init failed` 之類標成「FMP 靜默丟棄」，實際上它們**根本到不了 FMP** —— 丟棄點在 media_kit 的 prefix 白名單。含意是：**在 `audio_provider.dart` 加關鍵字完全治不好這一半**，只能改成訂閱 `player.stream.log` 並自己看 prefix，或走 §8.1(A) 讓後端在 log 層就翻譯成型別。
3. **音訊裝置失敗時 mpv 回報 `completed = true` 而 position 停在 0** —— 又一個「引擎宣稱完成、實際沒播」的實例，與 P0-5 同族。

**第二步：真實 end-to-end**（把**活著的** `MediaKitAudioService` 的 `ao` 設成同一個壞值，再用真的 `AudioController.playSingle` 播一首真的 Netease 串流）：

```
21:08:16.182 [MediaKitAudioService] Playing URL: http://m801.music.126.net/...
21:08:16.460 [AudioController]      PlayerState changed: ... FmpAudioProcessingState.ready
21:08:16.462 [MediaKitAudioService] media_kit error: Could not open/initialize audio device -> no sound.
21:08:16.462 [AudioController]      Audio error from service: Could not open/initialize audio device -> no sound.
21:08:16.463 [MediaKitAudioService] URL loaded successfully, duration: 0:03:43.512000 (may update later)
21:08:16.465 [MediaKitAudioService] Playback started, duration: 0:03:43.512000, playing: true
21:08:18.467 [PlaybackRequestSession] Media open error did not recover: Could not open/initialize audio device -> no sound.
21:08:18.472 [AudioController]      ... result: PlaybackSessionResultKind.terminalMediaOpenError
```

**畫面證據**：`scratchpad/issue41_toast.png` —— FMP 視窗底部的紅色橫幅「**播放失敗: AO probe track**」，與 `lib/i18n/zh-TW/audio.i18n.json:6` 的 `playbackFailedTrack` 逐字吻合。

**#41 至此完整重現，附錄第 1 項關閉。** 第五輪讀碼推出的因果鏈每一步都被實機證實，而且多了兩個當時沒看到的細節：

- **`URL loaded successfully` 這行 log 是在已經知道裝置失敗之後才印的**（16.462 收到錯誤 → 16.463 印「成功」）。這不只是 log 難看 —— 它說明 `playUrl` 的回傳值完全不參考 `errorStream`，兩條路徑各走各的。
- `_ensurePlayback()` 回報 `playing: true`，是 mpv 在沒有輸出裝置的情況下仍然把 `playing` 翻成 true。**Q24 的優先度應該調高**：`playUrl` 的「成功」語意目前不包含「聲音真的出得來」。

#### (b) 更正：AOT 下**有**觀測手段，而且相當完整 —— §12.17(c) 的結論是錯的

§12.17(c) 寫「Q16 不是錦上添花，而是 profile/release 下唯一可能的觀測入口」。**這句話錯了。**

`evaluate` 確實在 AOT 下不可用（本輪再次確認，同樣回 `Debugger is disabled in AOT mode.`），但 VM Service 的 **RPC 面與擴充事件面幾乎完好**。profile build 實跑，`getIsolate` 回報 **29 個 extensionRPC**：

| 在 AOT/profile 下 | 狀態（實測） |
|---|---|
| `evaluate` / `getInstances` 後求值 | ❌ `Debugger is disabled in AOT mode.` |
| `AppLogger` 的 DEBUG 行 | ❌ 全部消失（§12.17b，本輪未變） |
| `ext.flutter.debugDumpRenderTree` | ⚠️ 有註冊但**回傳空字串** |
| `ext.flutter.debugDumpApp` | ⚠️ 只回 `WidgetsFlutterBinding - PROFILE MODE`，沒有樹 |
| **`Flutter.Frame` 擴充事件**（`streamListen('Extension')`） | ✅ **完全可用** —— 每幀的 `build` / `raster` / `elapsed` / `vsyncOverhead` |
| `getVMTimeline` | ✅ 可用（單次抓到 4.83 MB） |
| `getMemoryUsage` / `getAllocationProfile` | ✅ 可用（後者 5.34 MB） |
| `ext.dart.io.httpEnableTimelineLogging` / `getHttpProfile` / `getHttpProfileRequest` | ✅ **可用**，見 (d) |
| `ext.flutter.profileWidgetBuilds` / `profileRenderObjectLayouts` / `profileRenderObjectPaints` | ✅ 可開啟（事件進 timeline） |

**所以 Q16 不是「唯一入口」，只是「拿 FMP 自己的分段時間戳」的唯一入口。** 引擎層的量測（frame、記憶體、HTTP）在 AOT 下本來就拿得到，而且不需要改任何一行程式碼。§12.17 的結論據此更正。

#### (c) 有了觀測手段之後：debug 到底把 UI 灌水多少

同一組操作（左側導覽列依序點 首頁→音樂庫→佇列→搜尋→首頁→搜尋，各停 1.6 秒），各收集 `Flutter.Frame` 事件 14 秒：

| 指標（ms） | debug（n=2578） | profile／AOT（n=1392） | debug ÷ profile |
|---|---|---|---|
| build p50 | 0.93 | **0.27** | **3.42×** |
| build p90 | 2.22 | **0.59** | **3.78×** |
| build mean | 1.74 | **0.38** | **4.57×** |
| build max | 247.88 | **13.92** | **17.8×** |
| raster p50 | 1.60 | 0.95 | 1.68× |
| raster p90 | 3.41 | 1.64 | 2.08× |
| elapsed p50 | 3.57 | 2.27 | 1.57× |
| elapsed p90 | 15.60 | 3.59 | 4.34× |
| 掉幀率（elapsed > 16.7ms） | **6.4%** | **1.7%** | 3.8× |

**【事實】debug 對 UI 的灌水是真的，而且集中在 Dart 端的 build**（3.4–4.6 倍，最壞值差 17.8 倍）。raster 只差 1.6–2.1 倍 —— 那一段是 GPU/Skia，受 JIT 影響小，符合預期。

**這正好補上 §12.17(d) 留下的【未驗證】。** 該節的結論「播放路徑的數字沒有被灌水，因為它們是網路主導的」**仍然成立**（三組獨立量測的排序沒有改變）；但它當時把 UI 的部分標成未驗證。現在有答案了：

> 本報告裡凡是「點擊→出聲」這種**跨越 UI 與網路**的端到端數字，UI 那一段（毫秒到數十毫秒）在 release 下會小 3–5 倍，網路那一段（秒級）不變。**對任何一條結論的定級都沒有影響**，因為主導項從頭到尾都是網路 —— 但這一點現在是實測而不是推測。

#### (d) 更正：`dart:io` 的 HTTP profiling 對 FMP 是**可用的**

根 `AGENTS.md` 寫著：「The `dart:io` HTTP/socket profiling in §3.5–3.6 is marked non-functional for FMP; **do not spend time there**.」**這條實測不成立**（至少在 profile build 上）。

在 profile build 上呼叫 `ext.dart.io.httpEnableTimelineLogging`（回 `{"enabled":true}`）後做一次搜尋，`ext.dart.io.getHttpProfile` 抓到 15 筆，涵蓋三個音源的 API 與圖片 CDN：

```
GET  www.youtube.com    status=200
GET  api.bilibili.com   status=200
POST music.163.com      status=200
POST www.youtube.com    status=200
GET  i.ytimg.com / i0.hdslb.com / p2.music.126.net / i2.hdslb.com ...
```

而 `ext.dart.io.getHttpProfileRequest` 給的是**完整的逐階段時間軸 + 完整 header + request/response body**（單筆 117 KB）：

```json
{"method":"POST","uri":"https://music.163.com/api/cloudsearch/pc",
 "events":[{"event":"Connection established"},{"event":"Request sent"},
           {"event":"Waiting (TTFB)"},{"event":"Content Download"}],
 "startTime":1788268638982691,"endTime":1788268639123871,
 "request":{"headers":{...}},"requestBody":...,"responseBody":...}
```

換算：連線建立 141ms、TTFB 260ms。**這正是本報告前幾輪要靠外部 PowerShell 對照才拿得到的東西，而且它連 request body 都給。**

FMP 的 dio 沒有安裝任何自訂 `httpClientAdapter`（`rg "httpClientAdapter|IOHttpClientAdapter"` 在 `lib/` 查無），所以走的就是 `dart:io HttpClient`，理所當然會被攔到。

> 【建議・S・可逆】**`AGENTS.md` 與 `docs/debugging-with-vm-service.md` §3.5–3.6 的這條敘述應該修掉。** 它現在正在主動叫 agent 不要用一個可用、而且是本專案最需要的工具（三個音源全部是 HTTP 主導）。列為 Quick win **Q32**。這一條我本輪沒有動手改 —— 它不在你交代的三項裡。

### 12.21 第八輪（下半）：把 §8.1(A) 與 §7.4 第 3 步落地成程式碼

前面七輪只審不改。這一節記錄實際動手的部分 —— 範圍由你選定：**§8.1 只做 A（`PlaybackEndReason`）、§7.4 只做第 3 步（不動持久化格式）**。

#### (a) §7.4 第 3 步：排行榜快取改成註冊表驅動

**改法**：把「每個音源的排行榜設定」從快取層搬到 adapter 自己身上。

`RankingSource`（`source_capabilities.dart`）新增兩個成員：

```dart
SourceRankingRequest get defaultRankingRequest;  // 該源的預設請求參數
String get rankingLabel;                          // 榜單名稱（日誌用）
```

並在契約上寫明「回傳的榜單必須已經排好序」—— 排序屬於各平台自己的語意。原本寫在快取層的 YouTube 依播放數降序特判，已移入 `YouTubeSource.getRankingTracks`，並在 `youtube_source_test.dart` 補了一條以 mock InnerTube 回應驅動的排序測試。

`RankingCacheService` 因此變成對音源完全無知：

| 原本 | 現在 |
|---|---|
| 建構子三個具名參數 `bilibiliRankingSource` / `youtubeRankingSource` / `neteaseRankingSource` | `required Map<SourceType, RankingSource> rankingSources` |
| Provider 逐一 lookup 三個源，缺任何一個就 throw | 對 `manager.registeredSourceTypes` 迴圈，取得有 `RankingSource` 能力的就收；**一個都沒有**才 throw |
| `_rankingRequestFor` 的三分支 switch | `source.defaultRankingRequest` |
| `_sourceLabel` 的三分支 switch | `source.rankingLabel` |
| `_normalizeRankingTracks` 的 YouTube 特判 | 刪除（移入 adapter） |
| `refreshBilibili()` / `refreshYouTube()` / `refreshNetease()` | 只剩 `refreshSource(SourceType)` |
| `RankingCacheState` 的 12 個具名參數 + 9 個具名 getter + 6 個 `_build*`/`_merge*` helper | 只剩 map 建構子與 `tracksFor` / `isLoaded` / `errorFor` |
| 初始加載完成的日誌硬寫三個名字 | 對 `rankedSourceTypes` 迴圈組字串 |

**檔案**：`ranking_cache_service.dart` 520 → 279 行。呼叫端只改了兩處存取器（`explore_page.dart` 的三個 tab、`developer_options_page.dart` 的三個計數），沒有動版面。

> **範圍說明（我沒有偷偷縮小，也沒有偷偷擴大）**：§7.4 第 3 步寫的是「`ranking_cache_service.dart` 的硬編碼改成對 `registeredSourceTypes` 的迴圈」，所以**探索頁仍然是寫死的三個分頁**（含各自的 i18n 標籤）。要讓分頁本身也由註冊表產生，需要「每個音源的顯示名稱」進 i18n，那是 UI 層的決定，不在這一步裡。快取層現在已經不需要為第四個音源改動。

**踩到的一個坑（值得記）**：改寫時我把凍結邏輯寫成

```dart
Map.unmodifiable({ for (...) entry.key: List.unmodifiable(...) })
```

在 map literal 裡 `List.unmodifiable(...)` **沒有向下推導的目標型別**，會被推成 `List<dynamic>`，編譯照過、`flutter analyze` 也過，直到執行期讀取才炸 `type 'List<dynamic>' is not a subtype of type 'List<Track>'`。測試抓到了。修法是把型別參數寫出來（`List<Track>.unmodifiable`）並先組成有型別的中間變數。

#### (b) §8.1(A)：`PlaybackEndReason` —— 把「這是哪一種結束」的判斷交還給後端

**新型別**（`audio_types.dart`）：`sealed class PlaybackEndReason` 及七個變體 —— `EndedNaturally` / `EndedPrematurely(at, expected)` / `TransportFailed(kind, raw)` / `OutputDeviceFailed(raw)` / `MediaUnopenable(raw)` / `DecoderFailed(raw)` / `UnclassifiedFailure(raw)`。

**介面**（`audio_service.dart`）：`Stream<void> completedStream` + `Stream<String> errorStream` **兩條流合併成** `Stream<PlaybackEndReason> endReasons`。理由就是 §12.14(d)(e) 的四格對照 —— 兩個後端對同一個網路條件連「哪條通道會響」都不一致，分成兩條流等於逼上層去猜。

**兩個後端各自翻譯**：

- `MediaKitAudioService`：`_classifyMpvMessage` 把 mpv 訊息映成型別，**音訊裝置的判斷排在媒體開啟之前** —— 這一行就是 #41 的修法。另外新增對 `player.stream.log` 的訂閱，補上 media_kit 自己在 prefix 白名單擋掉的 `ao` 訊息（§12.20a 的發現）。
- `JustAudioService`：`_classifyPlayerException` 以 `PlayerException` 的訊息分類；分不出來的一律 `UnclassifiedFailure`，不猜。
- 兩者共用 `AppConstants.completionTolerance`，避免 Android 與 Windows 對「算不算播完」給出不同答案。

**`AudioController` 只剩分派**：`_onPlaybackEnded(PlaybackEndReason)` 一個 switch。刪掉 `_isStringMediaOpenError`（#41 的成因）與 `_shouldHandleTrackCompleted`（P0-5 的旁路）。

> **一處更正 §8.1(A) 的說法**：該節寫「這一項把 `_isStringNetworkError` / `_isRetryableError` / `_syntheticSourceDiagnostics` 合計約 120 行整段刪掉」。**做下去才發現只刪得掉一半**：`_isStringNetworkError` 還有另一個呼叫者 `_isRetryableError`，而那個處理的是**串流解析階段拋出的 Dart 例外**（dio / socket），不是後端播放器事件 —— 兩者是不同的領域，型別化後端事件並不會讓解析層的例外自動變成型別。那一半要另外處理，已在原地加註。

**P0-5 順帶被修掉**：`duration == null` 現在是 `EndedPrematurely(expected: null)`，不再是「當作播完、直接跳下一首」。

#### (c) 驗證

- `flutter analyze`：乾淨。
- `dart format lib test`：乾淨（CI 現在有這道閘）。
- `flutter test --exclude-tags live`：**1242 passed**。
- 新增 / 改寫的測試：
  - `audio_controller_phase1_test.dart` 新增 **#41 的回歸守門** —— 送進 `OutputDeviceFailed`，斷言 toast **不含歌名**、而且訊息談的是裝置。
  - `audio_error_kind_structure_test.dart` 的結構斷言改寫：原本要求 `_onAudioError(String error)` 內必須呼叫 `_isStringNetworkError`（正是舊設計），現在改成斷言 `_onPlaybackEnded` 以型別分派、且 `_isStringMediaOpenError` / `_shouldHandleTrackCompleted` **必須已經不存在**。
  - `fake_audio_service.dart` 的 `emitCompleted()` 改成**依 position/duration 自行分類**，跟真實後端一樣；另加 `emitNaturalCompletion()` / `emitMediaOpenError()` / `emitOutputDeviceFailure()`。
  - `youtube_source_test.dart` 新增榜單排序測試。

**Windows 實機（debug，`flutter run -d windows`）** —— 用 §12.20(a) 的手法把 mpv 的 `ao` 設成不存在的驅動：

```
[E] [MediaKitAudioService] media_kit ao error: Audio output fmp-nonexistent-ao not found!
[E] [AudioController]      Audio output device failed: Audio output fmp-nonexistent-ao not found!
[E] [MediaKitAudioService] media_kit ao error: Failed to initialize audio driver 'fmp-nonexistent-ao'
[E] [AudioController]      Audio output device failed: Failed to initialize audio driver ...
[E] [MediaKitAudioService] media_kit error: Could not open/initialize audio device -> no sound.
[E] [AudioController]      Audio output device failed: Could not open/initialize audio device -> no sound.
[D] [AudioController]      Pausing: audio output device failed moments ago
→ state: isPlaying=false isLoading=false error=null
```

對照改動前（§12.20a 的同一個實驗）：`result: PlaybackSessionResultKind.terminalMediaOpenError`、紅色 toast「**播放失敗: AO probe track**」。現在 **`error=null`** —— 歌曲不再背鍋，訊息改成「音訊輸出裝置無法使用，播放已停止」。而且原本被 media_kit 丟掉的兩條 `ao` 訊息現在都收得到。

還原 `ao`（要用空字串，`'auto'` 不是合法的 mpv driver 名）之後：`playing=true pos=0:00:05.940 dur=0:03:43.512 err=null` —— 正常播放不受影響。Seek 到結尾前 4 秒：`Track completed: EndedNaturally()`，走正常的隊列完成路徑。

**Android 實機（AVD `Medium_Phone`，SDK 37）**：

- 註冊表驅動的快取正常：`[RankingCache] 初始加載完成（bilibili: true, youtube: true, netease: true）`（這串現在是迴圈產生的）。
- 播放：`AND1 playing=true pos=0:00:05.927986 dur=0:03:43.512000 err=null`。
- 探索頁三個分頁都渲染、切到網易雲分頁正常出資料（accessor 換掉沒有影響版面）。
- 首頁 YouTube 榜單依播放數降序（16.0M → 5.1M …），確認排序移進 adapter 之後仍生效。

#### (d) 驗證過程中發現的一個**既有**缺陷（不是這次改動造成的）

在 Android 上把單曲隊列 seek 到結尾後，`Track completed` **每秒重複觸發**，實測 82 次，每次都落在 `No next track available`：

```
[D] [AudioController] Track completed, loopMode: LoopMode.none, ...
[D] [AudioController] No next track available
（每 1 秒重複，直到手動 stop()）
```

成因：`_checkPositionForAutoNext` 每 `positionCheckInterval`（1 秒）檢查一次，條件是 `remaining <= positionCheckThreshold` 且後端仍回報 `isPlaying`。隊列播到最後一首且 `LoopMode.none` 時，完成處理器什麼都不做（沒有下一首），也不停止播放 —— 於是條件永遠成立。

**這一段程式碼本次沒有被改動**：計時器與完成處理器的邏輯與改動前逐行相同，唯一差別是計時器現在傳 `EndedNaturally()` 而不是 `null`，兩者都會走到同一個 `_onTrackCompleted()`。列為 Quick win **Q34**。

> 【誠實說明】我沒有跑「改動前 vs 改動後」的 A/B 對照來證明它是既有的 —— 我的依據是這條路徑上的程式碼逐行未變。要完全確定的話需要 stash 之後重跑一次。

### 12.22 第八輪（收尾）：Q32 / Q34 / Q24 與解析層例外的型別化

#### (a) Q32 —— 改寫前先把另外兩項補驗完

`AGENTS.md` 與 `docs/debugging-with-vm-service.md` §3.5–3.6 的原文把 `dart:io` 的 HTTP、socket、檔案 profiling **一併**判為「對 FMP 無效，不要花時間」。§12.20(d) 只推翻了 HTTP 那一項，socket 與檔案還沒驗 —— 直接改寫等於用一個未驗證的說法換掉另一個。所以先補驗。

方法：**先啟用、再產生流量**（原文自己就懷疑過順序問題）。

```
OK  ext.dart.io.httpEnableTimelineLogging -> {"enabled":true}
OK  ext.dart.io.socketProfilingEnabled    -> {"enabled":true}
   ↓ 之後才觸發一次 Netease eapi + 一次 Bilibili 搜尋
getHttpProfile:   2
   POST interface3.music.163.com 200
   GET  api.bilibili.com 200
getSocketProfile: 2
   tcp 198.18.0.107:443 r=7380  w=14246
   tcp 198.18.0.166:443 r=7886  w=14774
getOpenFiles:     0
```

`getOpenFiles` 回 0 —— 但那不是壞掉。刻意在 app 內開一個 `File` 並持有之後再查：

```
getOpenFiles: 1
   C:\Users\Roxy\AppData\Local\Temp\fmp_iofile_probe.txt
```

**【事實】三項全部可用。** 原文的成因分兩種：HTTP 與 socket 是啟用時機錯了（原文自己標注過這個可能性，事後證明它就是唯一原因）；檔案那一項是把「當下沒有 `dart:io` 檔案握柄存活」誤讀成「功能無效」——Isar 透過原生程式碼開檔，本來就不會出現在這個清單裡。

已改寫兩份文檔並在原地保留歷史更正（commit `d0282a25`）。

#### (b) Q34 —— 隊列尾端的重複觸發

`_checkPositionForAutoNext` 每秒檢查一次，條件是「剩餘時間在門檻內」且後端仍回報 `isPlaying`。隊列最後一首播完時，完成處理器走到 `No next track available` 就什麼都不做 —— 條件因此永遠成立。Android 實測 **82 次**且還在增加。

修法：隊列耗盡時 `pause()`。播完就不該再宣稱在播。

Windows 實機複驗（同樣是單曲隊列 seek 到結尾）：

```
completedCount=1  noNext=1
playing=false  pos=0:03:43.398024   （時長 0:03:43.512，位置保留在結尾）
```

從 82 降到 1。位置沒有被重置，UI 仍停在該首歌 —— 只是不再假裝在播放。

#### (c) Q24 —— `playUrl` 的「成功」語意

`playUrl` 在容忍窗內拿不到時長時，仍記 `URL loaded successfully, duration: null`。§12.20(a) 顯示這行甚至是在**已經知道音訊裝置失敗之後**才印的。已降級為 warning 並改寫措辭。

以本機零位元組伺服器（`scratchpad/holdsrv.py`）實測觸發：

```
[W] [MediaKitAudioService] URL opened but the engine never reported a duration;
    treating playback as started with unknown length
```

正常播放的對照組仍走 debug 分支：`[D] URL loaded successfully, duration: 0:03:43.512000`。

> 這只解決了 log 的誠實度。Quick win 原本還提到「在回傳值上區分成功但時長未知」—— 那需要改 `playUrl` 的回傳型別與所有呼叫端，屬於 §8.1 的範圍，本輪沒做。

#### (d) 解析層例外的型別化 —— §8.1(A) 的另一半

§12.21(b) 說明過：`_isRetryableError` 對非 `SourceApiException` 的例外仍在比對字串（`'socket'` / `'connection'` / `'host'` / `'errno'` …）。這是 #41 同一類的隱患 —— 一個訊息裡剛好有 `host` 的 `StateError` 會被判成可重試。

先確認邊界，再動手：

- 三個音源 adapter 合計 **22 處 `on DioException catch`**，全部包成 `SourceApiException`；
- `rg DioException lib/services/audio lib/services/media` **查無** —— dio 的例外不會逃到播放層；
- 會逃到這裡的是 `MediaHandoff` 直接用 `dart:io HttpClient` 拋的那幾種。

因此改成純型別判斷：`SourceApiException`（看 `kind`）、`SocketException`、`HttpException`、`TlsException`、`TimeoutException`，**其餘一律不重試並記一行 warning**。

```dart
// 沒有列舉到的型別一律不重試，但要留下痕跡 —— 靜默地「猜它是網路錯誤」
// 正是 issue #41 那類 bug 的來源。看到這行就把該型別補進上面的清單。
logWarning('Unclassified playback error, not retrying: ${error.runtimeType} $error');
```

**這是刻意的行為變更**：過去未列舉的型別只要 `toString()` 撞到關鍵字就會重試，現在不會。代價是可能少重試某些情況，換來的是「為什麼重試 / 為什麼不重試」變成可讀的型別清單，而且漏掉的型別會自己在 log 裡現身。實機正常播放全程沒有出現這行 warning。

`audio_provider.dart` 至此**不再有任何字串比對的錯誤分類器** —— 結構測試已加上 `expect(source, isNot(contains('_isStringNetworkError')))` 守住。

#### (e) 驗證與提交

`flutter analyze` 乾淨、`dart format` 乾淨、**1244 條測試全過**（新增 Q34 的回歸守門）。Windows 實機複驗 Q34、Q24 兩條路徑與正常播放。

本輪的 commit（分支 `refactor/playback-end-reasons`）：

```
afecf91e  docs: drop the removed ranking refresh wrappers and map review/
82d9cc27  docs(review): add round 02 audit of playback and source adapters
ecbaeb91  fix(audio): stop re-firing completion after the queue ends
d0282a25  docs(agents): correct the dart:io profiling claim
056f20c3  fix(audio): stop blaming the track when the audio output fails
583eef90  refactor(sources): drive ranking cache from the source registry
```

> **【自我更正】** `afecf91e` 是補洞的：§7.4 第 3 步刪掉了
> `refreshBilibili()` / `refreshYouTube()` / `refreshNetease()`，但我當時只更新了
> `lib/data/sources/AGENTS.md`，漏掉 `lib/providers/AGENTS.md` —— 那裡還寫著這三個
> 方法是「compatibility wrappers」，指向一組已經不存在的 API。根 `AGENTS.md` 要求
> 「Update the relevant instruction file in the same change as the code」，我沒做到，
> 事後補上。同一個 commit 也把 `docs/review/` 收進 `docs/README.md` 的文件地圖。

## 附錄：本輪未完成的部分

第二輪已補完的（原第 1、3、5 項）：

- ✅ **Windows UI 驗證** —— 阻塞解除，#42 完成、#40 的 transport 通道確認，見 §12.11–12.12。
- ✅ **YouTube 播放路徑實測** —— 見 §3.a-YouTube 與 §12.10，結果升級為 P0-3。
- ✅ **症狀 c 的實機重現（Android 半邊）** —— 見 §12.9，升級為 P0-4。第一輪用 `adb emu network speed` 節流無效的原因也查明了：裝置在 Wi-Fi 上，該指令只作用於行動網路介面；改用飛航模式 + `svc wifi/data disable` 才有效。
- ✅ **釐清 1.2s cid 查詢的真正原因** —— 是 AVD 的 DNS，不是 debug build，見 §12.8（並已更正第一輪的錯誤歸因）。

第三輪（使用者暫停手邊工作後）再補完：

- ✅ **#40 症狀一（電台上／下一首死鍵）** —— 以 WinRT 讀 SMTC 旗標 + 主動送 `TrySkipNextAsync` 證實，見 §12.13(c)。測試用電台已刪除。
- ✅ **#40 症狀二（seek）** —— 機制推論被推翻（`IsPlaybackPositionEnabled = False`），但「seek 請求被靜默丟棄」以 `TryChangePlaybackPositionAsync` 證實，見 §12.13(b)。
- ✅ **新發現：shuffle / repeat 也是死控制項** —— 「兩個」實為四個。
- ⚠️ **#41** —— 三個輸出裝置全部試過，都能正常初始化，**無法非侵入式重現**（§12.13(d)）。

第四輪（改用 VM Service 表達式求值）再補完：

- ✅ **Windows/media_kit 側的症狀 c** —— 不需要防火牆規則也不需要提升權限：用本機伺服器製造「播到一半 RST」與「連得上但零位元組」兩種病態，兩個平台各跑一次，得到四格對照表（§12.14d,e）。原本推測的 `_onAudioError` 路徑被推翻，實際走的是 premature-completion。
- ✅ **症狀 b 的開流階段量化** —— 6.1s（Windows 假成功）/ 12.4s（假 completed）/ 16.4s / 37.7s（Android 阻塞後拋出），並更正了「`open()` 可能永遠不返回」的推論（§12.14e）。
- ✅ **錯誤字串分類表** —— 對活著的 `AudioController` 直接呼叫私有方法，12 個真實錯誤字串逐一驗證，其中 8 個會被靜默丟棄（§12.14c）。
- ✅ **YouTube 的對照組** —— audio-only 命中 1.5s vs 退到 muxed 9.9s / 4.9 倍位元率（§12.14f）。
- ✅ **新發現：Netease 未登入被誤判為 VIP**（P1-10、Q22，§12.14g）。
- ⚠️ **Netease 播放路徑實測** —— 當時未完成。**第六輪更正**：括號裡「匿名帳號拿不到任何 URL」是有偏樣本造成的錯誤結論，匿名對免費曲目是可播的（§12.18d）。

第五輪（「繼續所有」）把上一輪列的五項全部處理完：

- ✅ **P1-8 的 preflight 實測** —— 不需要登入帳號也量得到：preflight 的閘門是「https + Netease host」而不是「URL 來自 eapi」。實測**零 redirect 也要 186ms**（每次播放的固定成本），並發現整套機制被 scheme 閘控，`http://` 會 0ms 直接跳過。見 §12.15(a)。
- ✅ **#41 根因定位** —— 從「無法重現」升級為「根因確認」：`setAudioDevice` 對未知裝置已有防禦（實測），真正的觸發點是 mpv 的 `Could not open/initialize audio device` 命中 `_isStringMediaOpenError` 的 `'could not open'`。見 §12.15(b)。
- ✅ **AOT / profile 對照** —— 做了，結論是**在 AOT 下沒有任何觀測手段**：DEBUG log 全部消失（67 行 0 筆），`evaluate` 明確回 `Debugger is disabled in AOT mode.`。上一輪寫的「技術上已無阻塞」**是錯的，已更正**。見 §12.17。
- ✅ **`flutter_js` 插件原型** —— 真的跑起來了：純 JS 的 Netease 插件，search 452ms、getAudioStream 384ms、端到端 1185ms，插件自帶的 CryptoJS 產出與 .NET 逐字元相同的 eapi params。順帶推翻了 §7.2 的兩條假設。見 §12.16。
- ✅ **`AudioController` 拆分的具體介面** —— §8.1，六個介面 + 建議順序 + 現況量測。
- ✅ **§12.5 的 1.68x 在 Windows 上的對照** —— 順帶補上：Windows 比值 0.995，證實 1.68x 是模擬器專屬（§12.5 表格）。

第六輪（遠端歷史被改寫後重新對基準）：

- ✅ **基準遷移與雜訊過濾** —— 10 個新 commit 逐一比對，把 `0089fe45` 的全樹 `dart format` 切開之後，落在本輪地盤的語意改動只有 InnerTube 常數去重（值逐字未變）。清單裡的 `audio_provider` / `audio_types` / `audio_handler` / `temporary_play_handler` / `qq_music_sign` 與三個 test 檔**全是 format-only**。見 §12.18(a)。
- ✅ **行號校正** —— 198 條 `file:line` 引用逐條驗證，37 條改號並確認新行號指到逐字相同的原始碼。
- ✅ **`test/live/` 實跑** —— 獨立重現 Bilibili 風控（412 → −429）與 **P0-3**（audio-only 被 bot 檢查擋下 → muxed 290.80 Kbit/s）。同時指出這個測試**不會**讓 P0-3 變紅。見 §12.18(b)。
- ✅ **eapi 的媒體 URL scheme —— 不需要登入帳號就解決了** —— 是 `http://`。**P1-8 改判**：從「每次播放 186ms 的固定成本」變成「約 150 行預檢 + 一個注入點 + 一整組測試在生產環境跑不到」。Quick win Q28 作廢。見 §12.18(d)。
- ✅ **`flag & 4` 不是 VIP 訊號** —— 在「能播」的曲目上同樣成立（`139774`：`flag=6, code=200`，匿名拿到 320kbps）。P1-10 的根據從「未登入時 flag 剛好是 4」升級為「判準本身錯誤」。見 §12.18(e)。
- ✅ **更正第五輪的一條事實** —— 「Netease 播放沒有可用的匿名路徑」是錯的（有偏樣本）。已在 §12.14(g) 原地標註。

第七輪（使用者登入 Netease 之後）：

- ✅ **Netease 已登入路徑 —— 關閉** —— 已登入的 eapi 同樣回 `http://`；在真實生產路徑（`playbackNetworkRequest` → `DefaultMediaHandoff.preparePlayback`）上量到 preflight **2ms 跳過**、Cookie **被剝掉**、真實簽名 URL **0 跳轉**（HEAD → 200，232ms）。P1-8 的三個問號全部有答案，處置確定為「刪」（D8 選項 a）。見 §12.19(a)。
- ✅ **插件化的 Android 側** —— 同一份 JS 插件在 AVD 上跑通：加密輸出與 Windows／.NET **逐字元相同**，沙箱邊界**完全相同**，加密吞吐反而快一倍（0.23 vs 0.47 ms/次）。QuickJS `.so` 每 ABI 0.72–1.05 MB。**但 `flutter_js` 0.8.7 開箱即壞**（`android/build.gradle:34` 的 `jvmTarget = 1.8` + `:5` 的 Kotlin 1.7.20 + KGP 棄用警告），需要宿主端 5 行繞過 —— §7.2 對這條路線的評分已下修。見 §12.19(b)。
- ✅ **插件的分發／更新／簽章流程** —— 三個成熟做法對照完成（Spotube `.smplug`、Mangayomi `index.json` + `sourceCodeUrl`、Mihon APK 簽章 SHA256 + TOFU）。建議信任模型抄 Mihon，介面形狀抄 Spotube。見 §12.19(c)。
- ✅ **重依賴（`youtube_explode_dart`）的處置** —— 三個選項評估完，建議「YouTube 不進插件系統」，並寫進 §7.4 的順序。見 §12.19(d)。
- ✅ **更正 §7.2 的一條事實** —— 「Flutter 音樂 app 都沒有外掛式音源架構、FMP 會是先行者」**是錯的**：Spotube v5.0.0（2025-09-11）已經做完，本報告改以它為主要對照。
- ✅ **順帶記錄** —— `AppLogger` 有敏感詞遮蔽（`test/core/logger/redaction_test.dart` 守門），我的探測 log 被它自動 `[REDACTED]`。

第八輪（「繼續剩下三項」）：

- ✅ **#41 完整實機重現並修好** —— 找到不干擾使用者系統裝置的重現法（把 mpv 的 `ao` 設成不存在的驅動，走 FMP 自己在用的 `NativePlayer.setProperty` 入口）。順帶更正第五輪的歸因：`ao` prefix 的訊息是被 **media_kit 自己**的白名單丟掉的，不是 FMP 的分類器。見 §12.20(a)、§12.21(b)(c)。
- ✅ **AOT 觀測 —— 結論被推翻** —— §12.17(c) 說「Q16 是唯一入口」是錯的。`Flutter.Frame` 擴充事件、`getVMTimeline`、`getAllocationProfile`、以及 `dart:io` 的 HTTP profiling 在 profile build 下**全部可用**。據此量到 debug 對 UI 的灌水：build p50 **3.42×**、mean **4.57×**、最壞 17.8×，掉幀率 6.4% → 1.7%。見 §12.20(b)(c)。
- ✅ **`AGENTS.md` 的一條敘述被推翻** —— 「`dart:io` HTTP profiling 對 FMP 不能用」實測不成立：抓到三個音源的 API 呼叫，含逐階段時間軸與完整 header/body。列為 Quick win Q32。見 §12.20(d)。
- ✅ **§8.1(A) `PlaybackEndReason` 落地** —— 兩條流合併成一條型別化的 `endReasons`，翻譯責任移到後端，`_isStringMediaOpenError` 與 `_shouldHandleTrackCompleted` 刪除（順帶修掉 P0-5 的旁路）。見 §12.21(b)。
- ✅ **§7.4 第 3 步落地** —— 排行榜快取改成註冊表驅動，`ranking_cache_service.dart` 520 → 279 行。見 §12.21(a)。
- ✅ **驗證** —— `flutter analyze` 乾淨、`dart format` 乾淨、**1242 條測試全過**、Windows 與 Android 兩平台實機驗證（含 #41 的前後對照）。見 §12.21(c)。
- ✅ **更正 P2-13** —— 原本拿 `pubspec.yaml` 的**約束**去比 pub.dev 最新版，那會把 caret 已經吃到的更新算成落後。查 `pubspec.lock`：`media_kit` 實際已是 1.2.6（最新）、`audio_service` 0.18.18。真正落後的只有 `just_audio`。見 §12.7 的更正註記。
- ✅ **Q32 / Q34 / Q24 三個 Quick win 收尾做掉** —— 改寫 `dart:io` profiling 的錯誤敘述前，先補驗了 socket 與檔案兩項（三項全部可用）；隊列尾端的重複觸發從 82 次降到 1 次；`playUrl` 的假成功 log 降級為 warning。見 §12.22。
- ✅ **解析層例外也型別化了** —— §8.1(A) 的另一半：`_isRetryableError` 改成純型別判斷，未列舉的型別不重試並記 warning。`audio_provider.dart` 至此沒有任何字串比對的錯誤分類器。見 §12.22(d)。
- ✅ **提交** —— 四個 commit 在分支 `refactor/playback-end-reasons`，1244 條測試全過。報告本身未提交（依原本的約定）。

仍未完成（第八輪之後）：

0. ~~**D8 —— Netease 死碼的處置**~~ —— 第八輪已執行刪除，見 §9 的 D8。

1. **§8.1 的 B–F 五個介面** —— 你這輪只要 A，B（`NowPlayingPublisher`，收掉 8 處平台分支並修 #40）、C（載入狀態機）、D（Mix）、E（seek 穩定化）、F（周邊服務）仍是規劃。
2. **§7.4 的第 1、2 步** —— `SourceType` 的字串雙軌與 `Settings` 的 map 化都會動到持久化格式，你這輪選擇不做。做的時候需要 Isar migration + `backup_service` 格式同步（對應 D6）。
3. **`playUrl` 的回傳型別** —— Q24 只修了 log 的誠實度。要在**回傳值**上區分「成功且時長已知」與「成功但時長未知」，需要改 `playUrl` 的型別與所有呼叫端，那落在 §8.1 的範圍。

> 另有兩處刻意保留的次要空白：`flutter_js` 在 **Linux** 上的建置（§12.19b 只驗了 Windows 與 Android），以及 §12.5 的 1.68x 音訊時脈偏差在**實體 Android 裝置**上的對照（目前只有 AVD 與 Windows 兩組）。兩者都不影響任何結論的定級。
