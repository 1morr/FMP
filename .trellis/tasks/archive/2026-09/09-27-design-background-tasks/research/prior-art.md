# 背景任務排程 — 先行研究（prior art）

- 查證日期：2026-09-27
- 查證方式：WebFetch / gh api 讀 GitHub 原始碼（raw 檔與 code search），未 clone 任何 repo。
- 涵蓋產品：Finamp、Namida、Spotube、Harmonoid（Flutter）；MusicFree（React Native，對照）；NewPipe（Android native，對照）。
- 所有 permalink 均釘在調查當下各 repo 預設分支的最新 commit SHA。

---

## Finamp（Jellyfin 播放器，Flutter）

- Repo：https://github.com/finamp-app/finamp（預設分支 `redesign`，SHA `0aae9d5`）
- 背景相關套件（[pubspec.yaml](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/pubspec.yaml)）：
  - `background_downloader: ^9.2.3`（[L29](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/pubspec.yaml#L29)）— 原生層背景下載
  - `audio_service: ^0.18.18`（[L63](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/pubspec.yaml#L63)）— 背景播放 foreground service
  - `connectivity_plus: ^7.0.0`（[L143](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/pubspec.yaml#L143)）
  - **沒有** workmanager / background_fetch / android_alarm_manager_plus / flutter_background_service。

**1. 集中排程器？** 沒有。timer 分散在各功能（Discord RPC 15 秒、播放歷史回報、下載總覽 UI 4 秒輪詢等，各開各的 `Timer.periodic`）。真正需要背景的下載整個外包給 `background_downloader` 的原生 service，Dart 側只收狀態更新（[downloads_service.dart L190](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/downloads_service.dart#L190) `FileDownloader().addTaskQueue(...)`）。

**2. 背景時刷新是否繼續？** Dart 側不做背景刷新；下載由原生 downloader 繼續。回前景時用 `AppLifecycleListener` 補跑（[L290–303](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/downloads_service.dart#L290)：`"App returning from background, restarting downloads."`，且註解寫明「背景超過 5 小時視同重啟，重新 resync」）。啟動時若 `resyncOnStartup` 設定開啟則跑一次 sync（[L367](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/downloads_service.dart#L367)）。

**3. 離線與網路恢復。** 單一 `network_manager.dart` 統一聽 `Connectivity().onConnectivityChanged`（[L34](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/network_manager.dart#L34)），在 `_onConnectivityChange`（[L84](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/network_manager.dart#L84)）一次處理：auto-offline 模式切換（等 7 秒二次確認避免誤觸發）、local/public server URL 切換、PlayOn 重連、對暫停下載跳 snackbar。連線錯誤連續 10 次會主動暫停下載（[downloads_service.dart L351](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/downloads_service.dart#L351)）；解除離線模式後呼叫 `restartDownloads()` 補跑（[L499](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/downloads_service.dart#L499)）。

**4. 使用者可調項目。** `autoOffline`（off / network / disconnected）、`requireWifiForDownloads`、`resyncOnStartup`（[downloads_settings_screen.dart L161](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/screens/downloads_settings_screen.dart#L161)）。**沒有任何「刷新間隔」設定** — library metadata 沒有定時刷新。

**5. 開 App 刷新 vs 定時刷新。** 完全走「開 App 時（可開關的 resync）+ 手動同步按鈕（SyncDownloadsButton）」，不定時。

---

## Namida（YouTube/本地播放器，Flutter）

- Repo：https://github.com/namidaco/namida（預設分支 `main`，SHA `e8363db`）
- 背景相關套件（[pubspec.yaml](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/pubspec.yaml)）：
  - `connectivity_plus: ^7.0.0`（[L56](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/pubspec.yaml#L56)）
  - `audio_service`（git fork，[L124](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/pubspec.yaml#L124)）
  - **沒有** workmanager / background_fetch / flutter_background_service；下載也是前景實作（`rhttp`），無背景下載套件。

**1. 集中排程器？** 半集中。全 App 只有一個 app 級的定期 timer：`_timeAwareRecheckTimer`，30 分鐘 tick 一次、但距上次未滿 24 小時就直接 return（[main.dart L587](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/main.dart#L587) `Duration(hours: 24)`、[L629–630](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/main.dart#L629) `Timer.periodic(const Duration(minutes: 30)...)`、[L645](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/main.dart#L645) due 判斷），tick 到期的話統一跑一批每日級雜務 `_recheckTimeAwareEssentials()`（account 支援資訊、auto-backup、cache trim、版本檢查、intent cache 清理，[L350](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/main.dart#L350)）。其餘 timer 仍是分散的（SyncSender、party reconcile、各 UI 進度條等各自開）。

**2. 背景時刷新是否繼續？** 不繼續 — Flutter timer 在 isolate 被系統暫停後自然停，Namida 不抵抗這件事，改用回前景補跑：`NamidaChannel.inst.addOnResume(_recheckTimeAwareEssentialsIfDue)`（[main.dart L633](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/main.dart#L633)）。背景播放靠 audio_service。

**3. 離線與網路恢復。** 有單一 `ConnectivityController`（[connectivity.dart](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/connectivity.dart)），全 App 共用 `hasConnection` / `hasHighConnection`（還分級成 data-saver 依據）。關鍵設計是 `executeOrRegister`（[L93–104](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/connectivity.dart#L93)）：有網路就立刻執行，沒網路就登記到 `_onConnectionRestored` 佇列，連線恢復時全部觸發一次後清空 — 例如 `VersionController` 用它延後版本檢查。Linux 上另有 D-Bus portal fallback。

**4. 使用者可調項目。** `settings.sync.autoSyncIntervalMinutes`（[sync_sender.dart L169](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/sync_manager/sync_sender.dart#L169)，`Timer.periodic(Duration(minutes: intervalMinutes))`；`<= 0` 即不建 timer，等於關閉），是少數真的開間隔給使用者的功能。另有 `settings.refreshOnStartup` 開關控制開 App 時是否重建媒體索引（[indexer_controller.dart L228](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/indexer_controller.dart#L228)）。

**5. 開 App 刷新 vs 定時刷新。** 媒體庫走「開 App 時刷新（可開關）+ 手動 refresh 按鈕」；定時只留給每日級維護雜務與使用者明確開啟的裝置同步。

---

## Spotube（Spotify/YouTube 播放器，Flutter）

- Repo：https://github.com/team-spotube/spotube（預設分支 `master`，SHA `69a310c`）
- 背景相關套件（[pubspec.yaml](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/pubspec.yaml)）：
  - `connectivity_plus: ^6.1.2`（[L25](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/pubspec.yaml#L25)）
  - `audio_service: ^0.18.13`（[L18](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/pubspec.yaml#L18)）
  - **沒有** workmanager / background_fetch / flutter_background_service / 背景下載套件。

**1. 集中排程器？** 沒有。全 repo 唯一的 `Timer.periodic` 在 [connectivity_adapter.dart L24](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/services/connectivity_adapter.dart#L24)：斷線後每 30 秒主動重探一次。

**2. 背景時刷新是否繼續？** 前景才跑。30 秒重探在 `AppLifecycleState.paused` 時直接跳過（[L26](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/services/connectivity_adapter.dart#L26)）；回前景時 `didChangeAppLifecycleState` 立刻重查（[L46–47](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/services/connectivity_adapter.dart#L46)）。

**3. 離線與網路恢復。** 雙層偵測：被動聽 `Connectivity().onConnectivityChanged`（[L40](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/services/connectivity_adapter.dart#L40)）+ 斷線期間主動輪詢。`_isConnected()` 用實際連線驗證（DNS lookup google.com / baidu.com + Dio HTTPS HEAD fallback + VPN 介面偵測，[L109](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/services/connectivity_adapter.dart#L109)），不只信 OS 回報的介面狀態；結果以 broadcast stream 給消費端（[L126](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/services/connectivity_adapter.dart#L126)）。查不到連線恢復後有統一的補跑佇列（推測：由各消費端自行對 stream 反應）。

**4. 使用者可調項目。** 查不到任何間隔設定；30 秒是寫死的常數。

**5. 開 App 刷新 vs 定時刷新。** 內容刷新（首頁 feed、歌單）查不到任何定時機制 — 走進頁面時載入 / 手動刷新（推測，未找到定期內容刷新的程式碼）。

---

## Harmonoid（本地檔案播放器，Flutter）

- Repo：https://github.com/harmonoid/harmonoid（預設分支 `master`，SHA `2b021f7`）
- 背景相關套件（[pubspec.yaml](https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/pubspec.yaml)）：
  - `audio_service: ^0.18.18`（[L16](https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/pubspec.yaml#L16)）
  - `media_library`（自家索引套件，[L84](https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/pubspec.yaml#L84)）
  - **沒有** connectivity_plus、workmanager、任何背景執行套件。

**1. 集中排程器？** 沒有，也幾乎沒有 timer — 純本地播放器，沒有需要定期拉的遠端資源。

**2. 背景時刷新是否繼續？** 無背景工作可言。媒體庫在 `ensureInitialized` 裡只跑一次：先從 DB 快取載入（[filesystem_media_library.dart L95](https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/core/filesystem_media_library.dart#L95) `refresh(insert: false, delete: false)`），**只有 library 是空的（首次啟動）才做完整檔案系統掃描**（[L99–104](https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/core/filesystem_media_library.dart#L99)）。

**3. 離線與網路恢復。** 不適用 — 沒有 connectivity 監聽，內容全是本地的。

**4. 使用者可調項目。** 無間隔設定。

**5. 開 App 刷新 vs 定時刷新。** 典型案例：開 App 從快取載入 + 手動刷新按鈕（`lib/features/media_library/media_library_refresh_button.dart`），完全沒有定時刷新。

---

## MusicFree（插件式播放器，React Native — 對照）

- Repo：https://github.com/maotoumao/MusicFree（預設分支 `master`，SHA `d118b18`）
- 注意：不是 Flutter，是 React Native。背景相關套件（[package.json](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/package.json)）：
  - `@react-native-community/netinfo`（[L27](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/package.json#L27)）
  - `react-native-background-timer`（[L60](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/package.json#L60)）— 但只用於 `delay` 工具與睡眠定時（scheduleClose），**不是**背景排程
  - `react-native-track-player`（[L80](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/package.json#L80)）背景播放

**1. 集中排程器？** 沒有。

**2. 背景時刷新是否繼續？** 不繼續；所有「更新」都發生在開 App 時。bootstrap 的 `extraMakeup()`（[bootstrap.ts L206–212](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/entry/bootstrap/bootstrap.ts#L206)）：若 `basic.autoUpdatePlugin` 開啟且距上次超過 86400000 ms（寫死 24 小時），逐一從來源 URL 靜默重裝啟用中的插件。App 自身更新檢查 `useCheckUpdate` 在 hook 掛載時跑一次（[useCheckUpdate.ts L35–39](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/hooks/useCheckUpdate.ts#L35)），尊重使用者跳過的版本。

**3. 離線與網路恢復。** NetInfo 包成全域 `Network` 狀態（Offline / Wifi / Cellular，[src/utils/network.ts](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/utils/network.ts)），供各處查詢；查不到連線恢復後的補跑機制（推測：無，下次操作自然重試）。

**4. 使用者可調項目。** `basic.autoUpdatePlugin` 開關；間隔寫死 24 小時，不可調。

**5. 開 App 刷新 vs 定時刷新。** 完全走「開 App 時 + 距上次超過 threshold」模式，無任何定時。

---

## NewPipe（YouTube 客戶端，Android native — 對照）

- Repo：https://github.com/TeamNewPipe/NewPipe（預設分支 `dev`，SHA `7e5df38`）
- 背景相關套件（[gradle/libs.versions.toml](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/gradle/libs.versions.toml)）：
  - `androidx.work:work-runtime` / `work-rxjava3` 2.11.2（[L79](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/gradle/libs.versions.toml#L79)、[L110–111](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/gradle/libs.versions.toml#L110)）

**1. 集中排程器？** 有 — 用系統級 WorkManager。而且全 App 只有**一個**定期背景工作：`NotificationWorker`（訂閱頻道新影片檢查＋發通知）。

**2. 背景時刷新是否繼續？** 會 — `PeriodicWorkRequest`（[NotificationWorker.kt L131](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/local/feed/notifications/NotificationWorker.kt#L131)）App 關閉也照跑；執行期間掛 foreground notification（`FOREGROUND_SERVICE_TYPE_DATA_SYNC`）。用 `enqueueUniquePeriodicWork` 保證唯一（[L140–145](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/local/feed/notifications/NotificationWorker.kt#L140)，設定變更時 `CANCEL_AND_REENQUEUE`，否則 `KEEP`）。注意：feed 列表本身仍是打開頁面/下拉才刷新，定期工作只用於「通知」這個真有背景需求的功能。

**3. 離線與網路恢復。** 不自己寫 — 把網路條件宣告為 WorkManager constraint（[L123–127](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/local/feed/notifications/NotificationWorker.kt#L123)：`NetworkType.CONNECTED`，勾選後升級為 `UNMETERED`），離線時工作自動延後到約束滿足，由系統負責補跑。

**4. 使用者可調項目。** 間隔完全開給使用者（`streams_notifications_interval` 設定，[ScheduleOptions.kt L23–26](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/local/feed/notifications/ScheduleOptions.kt#L23)），外加「只在非計費網路執行」開關；設定頁變更後 force reschedule。另有 `runNow()` 單次立即執行（[L158](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/local/feed/notifications/NotificationWorker.kt#L158)）。

**5. 開 App 刷新 vs 定時刷新。** 兩者並存但分工明確：內容瀏覽 = 開 App/手動；背景通知 = 系統排程、間隔與網路條件都可調。

---

## 橫向比較與對本專案的啟示

### 集中排程 vs 分散 timer

- **Flutter 陣營沒有人做真正的集中排程器**。分散的 `Timer.periodic` 是常態（Finamp、Namida 都是十來個各開各的）。
- 最接近集中式的是 **Namida 的「一個 30 分鐘 tick + 24 小時 due 判斷」**：一個 app 級 timer 統一派發每日級雜務（backup、cache trim、版本檢查），到期才做、沒到期就 return。成本極低、涵蓋面剛好是「不需要準時、但需要定期」的工作。
- 唯一有系統級集中排程的是 native 的 NewPipe（WorkManager），而且只用在一個功能上。

### 背景繼續 vs 前景才跑

- **Flutter 播放器一致選「前景才跑」**，沒有任何人用 workmanager / background_fetch 在背景做內容刷新（Finamp、Namida、Spotube、Harmonoid 的 pubspec 都沒有這類套件）。原因顯而易見：Flutter timer 在 isolate 被暫停後本就停跑，與其對抗平台，不如：
  1. **回前景時補跑** — Finamp `AppLifecycleListener` → `restartDownloads()`（背景逾 5 小時視同重啟 resync）；Namida `addOnResume` → `recheckIfDue`。
  2. **記住 due 時間，醒來再判斷** — Namida 的 24h due-check、MusicFree 的 24h plugin 更新，都是「時間到了才做」而非「每 N 時間做一次」，天然容忍 App 被殺。
  3. **原生層代跑** — 真有背景需求的工作（下載、播放）交給原生 service（background_downloader、audio_service），Dart 側只收事件。

### 離線與網路恢復

兩種成熟模式：
- **一次性補跑佇列**（Namida `executeOrRegister`）：離線時把想做的事登記起來，連線恢復時全部觸發一次後清空。適合版本檢查這類「做過就好」的事。
- **狀態驅動重啟**（Finamp / Spotube）：連線恢復後重啟下載、重查狀態。適合持續性工作。
- Spotube 額外教訓：OS 的 connectivity 事件不可靠時，斷線期間加一個 30 秒主動輪詢（真打 google.com / baidu.com 驗證）作為補充。
- 共同點：**connectivity 都是單一 controller 統一管理**（Namida `ConnectivityController`、Finamp `network_manager.dart`、Spotube `ConnectionCheckerService`），沒有人讓各功能各自聽 `connectivity_plus`。

### 可調間隔的常見做法

- 間隔**只**在真正有定期需求的功能上開放（Namida 裝置同步的分鐘數、NewPipe 通知間隔），且都有「0 / 關閉 = 不排」的語義。
- 其餘一律是 **threshold 模式**：「開 App / 回前景時，若距上次超過 X 才做」（Harmonoid 首次掃描、MusicFree 24h 插件更新、Namida 24h 雜務、Finamp 5 小時 resync），X 寫死或給個 on/off 開關，很少給自由間隔。
- 「只在打開 App 時刷新」本身就是常見的正式設計（Namida `refreshOnStartup`、Finamp `resyncOnStartup` 都是使用者可開關的設定項），不是偷懶。

### 對本專案（FMP）五項工作的對應建議

| 工作 | 各家做法對應 | 建議方向 |
|------|-------------|---------|
| 連線偵測 | Namida / Finamp / Spotube 都是單一 controller | 一個 connectivity controller，提供 `hasConnection` + `executeOrRegister` 式的一次性補跑；不要各功能自聽 |
| 排行榜背景刷新 | 無人做背景刷新；threshold 模式為主流 | 開 App / 回前景時距上次超過 threshold 才刷新，間隔 per-feature 可調、0 = 只手動 |
| 匯入歌單自動刷新 | 同上；MusicFree 插件 24h 模式 | 同上，threshold 模式 |
| 電台直播狀態輪詢 | 播放中 UI timer（Finamp/Namida 慣例） | 前景 timer，功能存活期間才跑；回前景補一次 |
| 快取清理 | Namida 的每日級 due-check | 併入一個 app 級「每日雜務」timer（30 分 tick + 24h due），不單獨開排程 |
| （若未來要背景下載同步） | NewPipe WorkManager / Finamp background_downloader | Android 上才考慮原生排程，且只給真正有背景需求的功能 |

核心結論：**不對抗 Flutter 背景限制、用「回前景 + due 時間判斷」取代定時背景刷新、connectivity 單一入口、間隔只開給真有定期需求的功能** — 這是五個成熟專案收斂出來的共同答案。
