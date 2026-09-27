# Research: 快取與離線策略 — 同類開源專案 Prior Art

- **Query**: FMP（Flutter 音樂播放器，串流 Bilibili / YouTube / NetEase）重寫時的快取與離線策略設計，需要參考同類專案在：串流網址過期處理（YouTube `expire`／Bilibili `deadline` 類參數）、圖片快取上限與清理、漸進式音訊快取、離線模式（自動/手動、功能可用性、已下載曲目辨識）、可調整設定 六個面向的實作方式。
- **Scope**: external（開源專案原始碼閱讀）
- **Date**: 2026-09-27
- **驗證方法**: 本機以 `git clone --depth 1` 取得下列專案原始碼後直接閱讀原始碼與設定檔逐行驗證；未使用 web search 工具（環境中未提供），亦未憑訓練記憶臆測版本相關細節。每個結論均附帶以下對應 commit SHA 建立的 GitHub permalink：

  | 專案 | Repo | HEAD SHA（複製當下） |
  |---|---|---|
  | Spotube | `team-spotube/spotube` | `69a310c78f5ceaf4eab7dfee98f187d38211c9ba` |
  | Namida | `namidaco/namida` | `e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5` |
  | Finamp | `jmshrv/finamp` | `0aae9d5ed530ffdf3d62ab12dab4f475a67687dc` |
  | NewPipe | `TeamNewPipe/NewPipe` | `7e5df38aad4b2c035332b3f71aee3064d4fdaae4` |
  | NewPipeExtractor | `TeamNewPipe/NewPipeExtractor` | `4818304b90fc9b6a3497d7e40b43aedb9a3f7074` |
  | MusicFree | `maotoumao/MusicFree` | `d118b18b3d0c904400f7eea7bf99c0ceec6c1aee` |

  找不到或無法確認的項目一律明確標註「查不到」並附上已嘗試的搜尋方式，不依記憶猜測。

---

## Findings

### Spotube（`team-spotube/spotube`）

架構：Flutter，播放走內建 `shelf` HTTP server 代理（見 `lib/provider/server/routes/playback.dart`），前端一律向本機 server 要串流。

- **快取分類與 TTL**：
  - 音訊快取：以 track 為單位寫入磁碟檔案（見下）。目錄由 `getMusicCacheDir()` 依平台決定：
    https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/provider/user_preferences/user_preferences_provider.dart#L97-L113
  - 圖片快取：透過 `cached_network_image` + `flutter_cache_manager`（`pubspec.yaml` 依賴，未見任何自訂 `CacheManager`/`Config`）：
    https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/pubspec.yaml#L24-L52
    實際使用處為 `CachedNetworkImageProvider`，沒有覆寫 TTL 或容量：
    https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/components/image/universal_image.dart#L33-L52
  - 未見獨立的「metadata TTL」快取層（除歌詞、`sourceMatchTable` 之外，見下）。
  - **查不到**：`flutter_cache_manager` 的預設 `stalePeriod`/`maxNrOfCacheObjects` 是否被 Spotube 用某個全域設定覆寫——已在整個 repo 搜尋 `CacheManager(` 建構呼叫，僅找到 `flutter_cache_manager` 套件本身；判定 Spotube 對圖片使用套件預設值。

- **串流網址過期處理**：**純被動重試（reactive）**。播放代理先對串流網址發 `HEAD` 請求探測，若失敗則呼叫 `refreshStreamingUrl()` 重新解析來源並重試：
  ```dart
  ).catchError((e, stack) async {
    final sourcedTrack = await ref.read(sourcedTrackProvider(track.query).notifier).refreshStreamingUrl();
    url = sourcedTrack.url!;
    return dio.head(url, options: options);
  });
  ```
  https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/provider/server/routes/playback.dart#L177-L191
  未見任何對 URL 內 `expire`/`deadline` 等參數的主動解析或預先判斷過期時間的邏輯——策略完全依賴「用了才知道」。

- **圖片快取上限與清理**：無自動清理／無容量上限程式碼；僅提供手動「Clear Cache」按鈕（顯示資料夾目前大小）：
  https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/pages/library/user_local_tracks/local_folder.dart#L150-L250

- **漸進式音訊快取**：**存在**，且與「明確下載」是分開機制。播放代理在串流的同時，若 `userPreferences.cacheMusic` 為真，會把位元組寫入 `<file>.part`，完成後改名為正式快取檔；下次播放時若快取檔存在則直接讀本機檔案、完全略過網路：
  https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/provider/server/routes/playback.dart#L89-L92
  （讀取快取）與
  https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/provider/server/routes/playback.dart#L217-L265
  （寫入 `.part` 再 rename）。未見容量上限設定——快取會無限增長直到使用者手動清除。

- **離線模式**：**沒有明確的「離線模式」開關或狀態**，而是靠一個獨立的 `ConnectionCheckerService` 持續偵測連線（含 VPN 介面偵測、對 `google.com`/`www.baidu.com` 做 DNS 探測、斷線時每 30 秒輪詢）：
  https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/services/connectivity_adapter.dart#L24-L111
  斷線時的行為僅止於暫停播放並跳 toast 通知，**未見任何功能因離線而被停用/隱藏**：
  https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/modules/root/use_global_subscriptions.dart#L30-L115
  已下載/已快取曲目的辨識：`local_tracks_provider.dart` 把「明確下載目錄」「音訊快取目錄」「使用者本機音樂庫目錄」三者掃描結果合併為同一份「本機曲目」清單，未見對播放優先序做特殊標記：
  https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/provider/local_tracks/local_tracks_provider.dart#L1-L90

- **使用者可調整設定**：僅「Cache Music」開關（是否啟用漸進式音訊快取）+「開啟快取資料夾」連結：
  https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/pages/settings/sections/playback.dart#L130-L165
  另有獨立的「明確下載」功能（`DownloadTask`/`DownloadManagerNotifier`），與上述漸進快取為兩套機制：
  https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/provider/download_manager_provider.dart#L1-L80

---

### Namida（`namidaco/namida`）

架構：Flutter，內建 `MusicWebServer` 自架 HTTP 伺服器橋接 YouTube 串流與播放器；同時支援訂閱「伺服器」音樂來源。是五個專案中快取子系統最完整、參數最豐富的一個。

- **快取分類與 TTL（有精確容量上限，非 TTL 制）**：`SettingsController` 定義四個獨立容量上限（單位 MB），各自對應一種快取類別：
  ```dart
  final videosMaxCacheInMB = (8 * 1024).obs; // 8GB
  final audiosMaxCacheInMB = (4 * 1024).obs; // 4GB
  final serversMaxCacheInMB = (4 * 1024).obs; // 4GB
  final imagesMaxCacheInMB = (8 * 32).obs; // 256 MB
  ```
  https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/settings_controller.dart#L183-L186
  另提供「精簡」（影片/音訊/伺服器快取皆關閉，圖片 2GB）與「積極」（24GB/12GB/12GB/2GB）兩組預設組合：
  https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/settings_controller.dart#L405-L461
  圖片快取內部再依 90%/10% 比例切分「影片縮圖」與「頻道圖片」兩個子預算（見 `storage_cache_manager.dart` 的 `_ImageTrimmer`）。

- **串流網址過期處理**：**主動 TTL 檢查 + 被動重試併存**。播放前呼叫 `hasExpired()` 判斷快取的串流結果是否過期，過期則強制重新請求：
  ```dart
  final bool expired = mainStreams?.hasExpired() ?? true;
  ```
  https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/base/audio_handler.dart#L1197
  （另見 L1335、L1521、L1938 同一模式重複出現）
  過期或播放失敗時會呼叫 `fetchVideoStreams(videoId)` 重新取流：
  https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/base/audio_handler.dart#L1284
  字幕/CC 檔另有自己的過期防護，註解直接說明原因：
  > "caption urls expire after a few hours, so the fetched file is kept around"
  https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/class/subtitle_track.dart#L150-L181
  **查不到**：`hasExpired()` 內部究竟是解析 YouTube 串流網址中的 `expire` 參數、還是純粹用固定 TTL 判斷——此邏輯實作於外部套件 `namidaco/youtipie`，但該 repo 無法存取（`git clone` 回傳 "Repository not found"，`gh api repos/namidaco/youtipie` 回傳 404，`gh api "search/repositories?q=youtipie"` 亦回傳 0 筆結果），判定為私有或已下架，僅能確認 App 端「呼叫端會先查過期再決定要不要重打」這個介面行為，內部判斷方式查不到。

- **圖片快取上限與清理**：`imagesMaxCacheInMB` 控制總量，清理由共用的 `_Trimmer`/`_ImageTrimmer` 類別執行，依「存取時間（`stat.accessed`）由舊到新」的 LRU 順序刪除，並排除標記為 `isKept`（VIP/釘選）與正在下載中的檔案：
  https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/storage_cache_manager.dart#L1-L990
  觸發時機：App 啟動（`_secondaryAppInitialization`）、每 30 分鐘一次的 `Timer.periodic`（但受 24 小時的 `_timeAwareRecheckInterval` 節流）、以及 App 回到前景：
  https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/main.dart#L320-L360

- **漸進式音訊快取**：**存在**，由 `ServerCacheController` 負責，最多 3 個並行下載工，每 100ms 更新一次進度：
  ```dart
  static const _kMaxParallelDownloads = 3;
  static const _kProgressUpdateIntervalMs = 100;
  ```
  https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/music_web_server/server_cache_controller.dart#L8-L9
  容量超過 `serversMaxCacheInMB`/`audiosMaxCacheInMB` 時由 `trimExcessCache()` 觸發同一套 LRU+VIP 排除邏輯清理：
  https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/music_web_server/server_cache_controller.dart#L203

- **離線模式**：**無獨立「離線模式」開關**，而是逐檔在播放時判斷「本機是否已有可用快取/下載檔」。核心邏輯：若快取檔存在，且（該檔被標記為 `isKept()`，即使用者釘選保留 **或** 檔案大小與伺服器記錄相符），就直接用本機檔案播放，完全不連網；否則刪除失效快取後才回退連網：
  ```dart
  if (ServerCacheController.inst.isKept(tr) || await cacheFile.fileSize() == tr.size) {
    onFetched(cacheFile);
    return AudioVideoSource.file(cacheFile.path);
  } else {
    await cacheFile.tryDeleting();
  }
  ```
  https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/base/audio_handler.dart#L3050-L3057
  另有獨立的 `isAvailableOffline(videoId)`，同時查「音訊快取表」與「本機曲庫索引」兩個來源：
  https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/audio_cache_controller.dart#L1-L45
  以及一個手動限定「只搜尋已快取/已下載內容」的 Offline Search 功能：
  https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/youtube/pages/yt_local_search_results.dart#L1-L70
  連線偵測（`connectivity.dart`）額外區分 `hasConnection`/`hasHighConnection` 兩級，後者用於驅動「省流量模式」：
  https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/connectivity.dart#L1-L130

- **使用者可調整設定**：四個容量上限皆有對應的滑桿 UI（影片/音訊/伺服器/圖片快取各自可調）：
  https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/ui/widgets/settings/advanced_settings.dart#L540-L568

---

### Finamp（`jmshrv/finamp`）

架構：Flutter，對接 Jellyfin 伺服器（非簽章網址、無到期時間概念的認證模型）。1.0 版做過一次下載子系統大改（Hive→Isar、`flutter_downloader`→`background_downloader`），動機記錄於：
https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/DOWNLOADS_PLAN.md

- **快取分類與 TTL**：Finamp 是五者中唯一**沒有隱式/漸進式音訊快取**的專案——已針對 `lib/services/` 全目錄以 `cache`/`Cache` 關鍵字搜尋，僅發現「明確下載」（`DownloadStub`/Isar 持久化）與圖片快取（`DefaultCacheManager()`，未覆寫任何設定）兩種：
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/album_image_provider.dart#L72
  **查不到**：`DefaultCacheManager()` 的實際 disk 容量上限——Finamp 未覆寫 `flutter_cache_manager` 預設 `Config`，故沿用套件本身預設值（套件原始碼未在本次研究範圍內深入）。

- **串流網址過期處理**：**結構性不適用**。Jellyfin 的媒體串流網址走伺服器端 API Key 驗證，不含如 YouTube `expire`/Bilibili `deadline` 的簽章到期參數；`jellyfin_api_helper.dart` 中對 401 的處理僅用於「登出/重新登入」情境，並非串流網址到期重試：
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/jellyfin_api_helper.dart#L1070-L1105

- **圖片快取上限與清理**：未見任何自動清理或容量上限程式碼（沿用 `flutter_cache_manager` 套件預設值，同上）。

- **漸進式音訊快取**：**不存在**。所有離線可播放內容都必須經過使用者明確觸發的「下載」流程，沒有「邊播邊存」機制。

- **離線模式**：**自動＋手動並存，且有明確的四態自動化列舉**：
  ```dart
  enum AutoOfflineOption {
    disabled,
    network,
    disconnected,
    unreachable,
  }
  ```
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/models/finamp_models.dart#L3125-L3131
  四態的精確定義（取自英文語系檔）：`network` = 沒連上 WiFi/有線網路時自動開啟離線模式；`disconnected` = 完全沒有任何網路連線時開啟；`unreachable` = 切換網路後 ping 不到伺服器時開啟：
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/l10n/app_en.arb#L2208-L2218
  使用者也可以手動切換離線模式開關，此舉會**暫停自動化直到重新啟用**（"pauses the automation until you reenable it"）：
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/l10n/app_en.arb#L2224
  對應的手動開關 UI 元件：
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/components/MusicScreen/offline_mode_switch_list_tile.dart#L12
  **功能可用性**：離線時多處明確停用需要伺服器運算的功能，例如首頁改顯示「未下載/離線模式下不可用」訊息而非嘗試連網：
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/components/HomeScreen/home_screen_content.dart#L298-L343
  「Instant Mix」（伺服器端生成的接續播放清單）離線時停用：
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/components/MusicScreen/music_screen_tab_view.dart#L344
  「Most Played」等需伺服器統計資料的篩選器離線時停用：
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/components/curated_item_filter_row.dart#L20-L26
  離線期間的播放記錄改寫入本機 Hive box + JSON-lines 檔案，供之後同步或手動分享匯出，而非即時上報伺服器：
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/offline_listen_helper.dart#L16-L94
  已下載曲目的辨識：透過 Isar 持久化的 `DownloadStub` 記錄判斷，`queue_service.dart` 多處以 `isOffline` 旗標門控電台/Instant Mix 等需連網功能，未見「下載優先於串流」的排序邏輯（因為沒有漸進快取可比較，下載是唯一的本機來源）。

- **使用者可調整設定**：`downloads_settings_screen.dart` 提供一組完整的下載相關設定（皆為明確下載範疇，非漸進快取）：`RequireWifiSwitch`（僅 WiFi 下載）
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/screens/downloads_settings_screen.dart#L107
  `SyncFavoritesSwitch`（收藏自動同步下載）
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/screens/downloads_settings_screen.dart#L120
  `SyncOnStartupSwitch`
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/screens/downloads_settings_screen.dart#L154
  `ConcurentDownloadsSelector`（併發下載數，1-25 滑桿）
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/screens/downloads_settings_screen.dart#L181
  `DownloadWorkersSelector`（下載執行緒數，1-5 滑桿）
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/screens/downloads_settings_screen.dart#L223
  `DownloadSizeWarningCutoffTile`（超過此 MB 數時跳出下載體積警告，數值輸入框）
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/screens/downloads_settings_screen.dart#L284
  以及前述的四態自動離線模式選單。

---

### NewPipe（`TeamNewPipe/NewPipe` + `TeamNewPipe/NewPipeExtractor`）

架構：Android 原生（Java/Kotlin），抽取邏輯獨立於 `NewPipeExtractor` 函式庫，播放走 ExoPlayer，圖片走 Coil。是唯一非 Flutter 的參考對象。

- **快取分類與 TTL（固定 TTL 制，非解析網址參數）**：核心是一個記憶體內 `LruCache`（`InfoCache`），容量上限 60 筆、超量清到 30 筆：
  ```java
  private static final int MAX_ITEMS_ON_CACHE = 60;
  private static final int TRIM_CACHE_TO = 30;
  ```
  https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/util/InfoCache.java#L38-L44
  每筆項目的過期時間由 `ServiceHelper.getCacheExpirationMillis()` 依服務決定，是**寫死的固定時長**，非解析串流網址內任何到期參數：
  ```kotlin
  fun getCacheExpirationMillis(serviceId: Int): Long {
      return if (serviceId == ServiceList.SoundCloud.serviceId) {
          TimeUnit.MILLISECONDS.convert(5, TimeUnit.MINUTES)
      } else {
          TimeUnit.MILLISECONDS.convert(1, TimeUnit.HOURS)
      }
  }
  ```
  https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/util/ServiceHelper.kt#L138-L144
  即 YouTube 固定 1 小時、SoundCloud 固定 5 分鐘，與 YouTube 串流網址本身的 `expire` 參數無關。已在 `NewPipeExtractor/extractor/src/main` 全目錄搜尋關鍵字 "expire"，**零筆命中**，可確認抽取器本身完全不解析網址內的到期參數。

- **串流網址過期處理**：**播放走固定 TTL、下載走被動重試（403 觸發）——兩套獨立機制**。
  播放端：ExoPlayer 的媒體來源包裝物件持有與 `InfoCache` 相同語意的 `expireTimestamp`，過期後才允許被替換：
  ```java
  private boolean isExpired() {
      return System.currentTimeMillis() >= expireTimestamp;
  }
  ```
  https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/player/mediasource/LoadedMediaSource.java#L44-L58
  下載端：偵測到 HTTP 403 時視為「網址已過期」，觸發 `doRecover()` 重新取流，三處下載執行緒（一般/回退路徑/初始化）皆用同一常數判斷：
  ```java
  if (e instanceof HttpError && ((HttpError) e).statusCode == ERROR_HTTP_FORBIDDEN) {
      mMission.doRecover(ERROR_HTTP_FORBIDDEN);
  ```
  https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/us/shandian/giga/get/DownloadRunnable.java#L133-L139
  另見
  https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/us/shandian/giga/get/DownloadRunnableFallback.java#L116-L119
  與
  https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/us/shandian/giga/get/DownloadInitializer.java#L178-L181

- **圖片快取上限與清理**：圖片走 Coil 的 `SingletonImageLoader`，**未見任何自訂容量設定**（沿用 Coil 預設值）；使用者變更「圖片畫質」偏好時，程式會主動清空 Coil 的記憶體與磁碟快取：
  ```java
  loader.getMemoryCache().clear();
  loader.getDiskCache().clear();
  ```
  https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/settings/ContentSettingsFragment.java#L71-L83
  另有手動「清除中繼資料快取」設定項，直接呼叫 `InfoCache.getInstance().clearCache()`：
  https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/settings/HistorySettingsFragment.java#L61-L63

- **漸進式音訊快取**：**不存在**。NewPipe 僅有「明確下載」（`DownloadMission`/`us.shandian.giga.get`），沒有邊播邊存的隱式快取層。

- **離線模式**：**沒有應用層級的「離線模式」概念**，也沒有針對離線的功能停用/降級邏輯——NewPipe 定位為串流優先的用戶端，已下載的影片/音訊僅能透過各自的下載清單頁面存取，不會被優先匹配進正常瀏覽/搜尋流程。

- **使用者可調整設定**：圖片畫質偏好（連帶觸發快取清空）、手動清除中繼資料快取兩項，皆為前述已列出的 preference 項目；對應 UI 文案：
  https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/res/values/strings.xml#L105-L108

---

### MusicFree（`maotoumao/MusicFree`）

架構：React Native，播放邏輯集中於 `RNTrackPlayer`，來源解析走「外掛（plugin）」模式——每個外掛實作 `getMediaSource(musicItem, quality)`，與 FMP 自身的 source-adapter 架構在概念上相近。

- **快取分類與 TTL**：
  - Metadata 快取（`MediaCache`）：MMKV 儲存，容量上限 800 筆，超量時做「刪掉一半」的清理（程式碼自己標註為臨時方案）：
    ```ts
    // 最多缓存800条数据
    const maxCacheCount = 800;
    ...
    // TODO: 随机删一半
    for (let i = 0; i < maxCacheCount / 2; ++i) { ... }
    ```
    https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/core/mediaCache.ts#L10-L41
  - 音訊快取：委派給原生播放器本身（見下）。
  - 圖片：`react-native-fast-image`（`package.json` 依賴），未見自訂容量設定。
  - **查不到**：MMKV `MediaCache` 是否有依時間的 TTL 過期機制——已讀完整份 `mediaCache.ts`（84 行），僅有容量上限與「刪一半」清理，未見任何時間戳比對邏輯，判定沒有 TTL，僅有容量驅逐。

- **串流網址過期處理**：**結構性迴避——每次播放都重新呼叫外掛解析，並由外掛自行宣告快取策略**。核心是外掛可選擇性宣告的 `cacheControl` 欄位，對應列舉：
  ```ts
  export const CacheControl = {
      Cache: "cache",
      NoCache: "no-cache",
      NoStore: "no-store",
  };
  ```
  https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/constants/commonConst.ts#L44-L48
  `getMediaSource()` 依此欄位決定是否重用上次解析出的網址：`Cache` = 一律重用已快取網址；`NoCache` = 僅離線時退回使用快取網址，其餘一律重新解析；未宣告時預設 `no-cache`：
  ```ts
  const pluginCacheControl = this.plugin.instance.cacheControl ?? "no-cache";
  if (mediaCache && mediaCache?.source?.[quality]?.url &&
      (pluginCacheControl === CacheControl.Cache ||
       (pluginCacheControl === CacheControl.NoCache && Network.isOffline))) {
  ```
  https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/core/pluginManager/plugin.ts#L225-L243
  若外掛宣告 `NoStore`，新解析出的網址則完全不寫回快取：
  https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/core/pluginManager/plugin.ts#L292
  由於解析網址這件事本身被下放給各外掛，MusicFree 核心完全不需要知道任何特定平台的 `expire`/`deadline` 參數語意。

- **圖片快取上限與清理**：設定頁提供「清除圖片快取」按鈕（顯示目前佔用大小），屬手動觸發，未見自動清理：
  https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/pages/setting/settingTypes/basicSetting.tsx#L498-L509
  另有對應的「清除音樂快取」「清除歌詞快取」按鈕：
  https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/pages/setting/settingTypes/basicSetting.tsx#L471-L490

- **漸進式音訊快取**：**存在，但完全委派給原生播放器**，應用層僅在啟動時傳入一個容量上限給 `RNTrackPlayer.setupPlayer()`，預設 512MB：
  ```ts
  await RNTrackPlayer.setupPlayer({
      maxCacheSize: Config.getConfig("basic.maxCacheSize") ?? 1024 * 1024 * 512,
  ```
  https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/entry/bootstrap/bootstrap.ts#L152-L154
  此上限可在設定頁調整（100MB-8GB 區間，UI 顯示已格式化大小）：
  https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/pages/setting/settingTypes/basicSetting.tsx#L118

- **離線模式**：**沒有獨立的「離線模式」開關，完全自動判斷**。`Network` 是一個基於 `@react-native-community/netinfo` 的單例，區分 `Offline`/`Wifi`/`Cellular` 三態，全自動更新，無手動覆寫入口：
  https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/utils/network.ts#L1-L61
  行動網路下的播放限制：若目前是行動網路、使用者未開啟「行動網路可播放」設定、且該曲目「不是本機音樂」且「沒有本機路徑」，則直接擋下播放：
  ```ts
  const localPath = getLocalPath(musicItem);
  if (Network.isCellular &&
      !this.configService.getConfig("basic.useCelluarNetworkPlay") &&
      !LocalMusicSheet.isLocalMusic(musicItem) &&
      !localPath) {
      await ReactNativeTrackPlayer.reset();
      throw new Error(PlayFailReason.FORBID_CELLUAR_NETWORK_PLAY);
  }
  ```
  https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/core/trackPlayer/index.ts#L405-L418
  **已下載曲目的辨識與優先播放**：`getLocalPath()` 依序檢查（1）曲目網址本身是否為 `file://`/`content://` 開頭、（2）舊版序列化欄位中的 `localPath`、（3）附加資訊（media extra）中的 `localPath`：
  ```ts
  export function getLocalPath(mediaItem: ICommon.IMediaBase) {
      if (mediaItem.url && (mediaItem.url.startsWith("file://") || mediaItem.url.startsWith("content://"))) {
          return mediaItem.url;
      }
      const legacyLocalPath = mediaItem?.[internalSerializeKey]?.localPath;
      if (legacyLocalPath && typeof legacyLocalPath === "string") {
          return legacyLocalPath;
      }
      const localPathInMediaExtra = getMediaExtraProperty(mediaItem, "localPath");
      return localPathInMediaExtra ?? null;
  }
  ```
  https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/utils/mediaUtils.ts#L89-L109
  此檢查在 `getMediaSource()` 的**最開頭**（優先於 metadata 快取查詢、優先於呼叫任何外掛解析）就執行——只要找到本機路徑即直接回傳，完全跳過外掛解析流程：
  https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/core/pluginManager/plugin.ts#L200-L217
  即：本機/已下載曲目在架構上具有最高優先序，且此優先序判斷與快取策略（`cacheControl`）完全獨立。

- **使用者可調整設定**：「音樂快取上限」（100MB-8GB 滑桿/選項）、「清除音樂快取」「清除歌詞快取」「清除圖片快取」三個獨立按鈕、「行動網路下可播放」「行動網路下可下載」兩個獨立開關：
  https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/pages/setting/settingTypes/basicSetting.tsx#L400-L510

---

## 對照表（僅列事實，不含建議）

| 面向 | Spotube | Namida | Finamp | NewPipe | MusicFree |
|---|---|---|---|---|---|
| 技術棧 | Flutter | Flutter | Flutter | Android 原生 (Java/Kotlin) | React Native |
| 圖片快取上限 | 套件預設（未覆寫） | 可調（預設 256MB，含 90/10 子分配） | 套件預設（未覆寫） | 套件預設（未覆寫），畫質變更時全清 | 未見容量上限，僅手動清除按鈕 |
| 串流網址過期策略 | 純被動：HEAD 探測失敗才重新解析 | 主動 `hasExpired()` 檢查 + 過期/失敗雙重觸發重新取流 | 不適用（Jellyfin 無簽章到期網址） | 播放走固定 TTL（YouTube 1hr／SoundCloud 5min）；下載走被動 HTTP 403 觸發重試 | 每次播放重新呼叫外掛解析；外掛可用 `cacheControl`（`cache`/`no-cache`/`no-store`）宣告是否重用網址 |
| 是否解析網址內 `expire`/`deadline` 參數 | 查不到（未見相關程式碼） | 查不到（判斷邏輯在無法存取的外部套件 `youtipie` 內） | 不適用 | 否，確認為固定 TTL（已對 extractor 原始碼搜尋 "expire" 零命中） | 不適用（不持久判斷單一網址壽命，改用外掛宣告的策略） |
| 漸進式（隱式）音訊快取 | 有，無容量上限，需手動清除 | 有，`serversMaxCacheInMB`/`audiosMaxCacheInMB` 可調並自動 LRU 清理 | 無（僅明確下載） | 無（僅明確下載） | 有，容量委派給原生播放器（預設 512MB，可調） |
| 離線模式切換 | 無獨立模式，僅連線偵測+暫停播放 | 無獨立模式開關，逐曲目判斷本機檔案可用性 | 有：4 態自動化列舉（`disabled`/`network`/`disconnected`/`unreachable`）+ 手動開關（手動會暫停自動化） | 無離線模式概念 | 無獨立模式，全自動依 `Network` 單例狀態判斷 |
| 離線時功能停用 | 未見（僅暫停播放） | 未見整頁功能停用，僅提供「離線搜尋」限定範圍搜尋 | 有：首頁部分區塊、Instant Mix、Most Played 等伺服器運算功能明確停用 | 不適用（無離線模式） | 有：行動網路（非離線）下非本機曲目被擋下播放，需開關放行 |
| 已下載/本機曲目辨識機制 | 三個目錄（下載/快取/本機庫）合併掃描，無特殊優先標記 | 檢查快取檔存在 + (`isKept()` 或檔案大小相符) 才視為可離線播放本機檔 | Isar 持久化 `DownloadStub` 記錄 | 各自獨立的下載清單，不併入一般瀏覽/搜尋 | `getLocalPath()` 檢查 URL scheme/legacy 欄位/media extra，且在 `getMediaSource()` 最前面短路，優先於外掛解析與 metadata 快取 |
| 代表性使用者可調快取設定 | 「Cache Music」開關 + 開啟快取資料夾 | 4 組獨立容量滑桿（影片/音訊/伺服器/圖片）+ 精簡/積極預設組合 | 下載相關：僅 WiFi 下載、收藏自動同步、併發數(1-25)、執行緒數(1-5)、體積警告門檻、4 態自動離線模式 | 圖片畫質偏好（連動清快取）、手動清中繼資料快取 | 音樂快取容量(100MB-8GB)、三個獨立清快取按鈕、行動網路播放/下載開關 |

## Caveats / Not Found

- Namida：`hasExpired()` 的內部判斷方式（是否解析 YouTube 串流網址參數、或使用固定 TTL）——實作於外部套件 `namidaco/youtipie`，該 repo 目前無法存取（clone 404，`gh api repos/namidaco/youtipie` 404，`gh api search/repositories?q=youtipie` 0 筆），僅能從呼叫端行為推斷「有主動過期檢查」這一事實，內部機制查不到。
- Spotube：`flutter_cache_manager` 圖片快取的實際 `stalePeriod`/`maxNrOfCacheObjects` 數值——Spotube 未覆寫套件設定，本次研究未深入套件本身原始碼確認其確切預設值。
- Finamp：`DefaultCacheManager()` 的圖片快取實際容量上限——同上，未覆寫預設值，套件本身預設數值未在此次研究中查證。
- MusicFree：`MediaCache`（MMKV metadata 快取）除容量上限外是否有任何以時間為準的過期機制——已讀完整份 84 行原始碼確認沒有時間戳判斷，僅容量驅逐（`TODO: 随机删一半`），此點為確定結論而非「查不到」。
- 本次研究未涵蓋第五個可選專案 LX Music；改以 MusicFree 作為第五個對象，符合任務原始指示中「可選 MusicFree 或 LX Music 擇一」的要求。
