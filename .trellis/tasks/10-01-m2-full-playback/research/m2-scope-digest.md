# M2 完整播放：ADR 範圍摘要

> 目的：讓 planner 把 M2 拆成 PR 大小的 child task，並把「未定之處」整理成擁有者問題。本檔只彙整既有 ADR 與計畫的內容，不新增決定。
> 來源：`.trellis/tasks/09-26-fmp-rewrite/milestones.md` §M2（範圍與驗收的權威）、`phase2-plan.md` §5／§7／§8／§9、`docs/audit/questions.md` §7（E15、E19）、`docs/audit/playback.md`、`docs/adr/0009`–`0027`、M1 的 `implement.md` 與 `research/m1-acceptance.md`、`app/` 現況。
> 格式：每則 ADR 分四段——(a) M2 要做的、(b) M2 的驗證、(c) 不在 M2、(d) ADR 已固定的名稱。仿 M1 的 `m1-scope-digest.md`。
> 「現況」只列存在什麼（檔案加一行），不評論。查證日期 2026-10-01。

## 0. M2 的權威定義

- **做完**：`milestones.md:48`——「以單一音源像舊版一樣日常聽歌。」
- **一句話性質**（ADR 0026 §決定 3 的表）：M2 = 「完整播放」；「佇列、播放頁 B、系統媒體控制、快取、背景排程器與啟動維護清單」。依賴 M1；M3、M8 依賴 M2（`milestones.md:11,16`）。
- **範圍**（`milestones.md:49-54`）：
  1. 完整 `QueueModel` 與 `RecoveryPolicy`（ADR 0018）
  2. 播放頁方案 B、播放列三段、App 內快捷鍵全表、焦點三區（ADR 0024）
  3. 系統媒體控制；速度、音量、輸出裝置（E19）；播放歷史（E15）
  4. 統一快取庫與離線狀態（ADR 0016）
  5. 背景排程器與啟動維護清單（ADR 0017），含 log 保留 7 天（ADR 0025）
- **驗收**（`milestones.md:55-57`）：[ ] 兩平台端到端操作（Android 與 Windows 各做一次，ADR 0026 §決定 1）；[ ] ADR 0016、0017、0018 的測試。
- **不是 M2**：Linux、macOS、iOS 的實作（Linux 2026-10-01 改為 Mac 到貨後與 macOS、iOS 一起做，`milestones.md:132`、ADR 0026 §決定 4 修訂）。所以 M2 的系統媒體控制只做 Android（`audio_service`）與 Windows（`smtc_windows`）。
- **ADR 0026 §決定 2 的原文**：「每個新增資料表的里程碑，同時補上那張表的舊資料匯入（M5 起）」；「各組設定的欄位清單（ADR 0011），在引入該組設定的里程碑定案」。M5 範圍（`milestones.md:85`）寫明匯入「歌單、曲目、歷史、設定、帳號」，所以 M2 新增的資料表其舊資料匯入在 M5（見 §3 未定之處 21）。

---

## 1. 逐 ADR 摘錄

### ADR 0018 — 播放核心（M2 的主體）

**(a) M2 要做的**
- 元件（§決定 1）：`PlaybackController`（唯一入口）；協作者 `QueueModel`、`PlaybackSession`、`StreamResolver`、`PlaybackEventRouter`（純函數）、`RecoveryPolicy`（純函數）、`NowPlayingPublisher`，只回報、不寫狀態。系統媒體控制轉接器由平台層經 provider 注入。
- 狀態（§決定 2）：sealed 播放狀態 `Idle`、`Loading`、`Playing`、`Paused`、`Buffering`、`Retrying`、`Failed(AppError)`；位置等高頻資料走獨立 stream；`QueueState` 與播放狀態沒有共同欄位。
- 佇列與模式（§決定 4）：模式 `queue`、`temporary`（保留最早快照並回到佇列）、`mix`（已播超過 100 首刪最舊的已播項目）、`live`、`detached`；歌單「全部」只加入佇列（D2）；所有加入方式檢查 10,000 首上限；單曲循環每圈記一筆歷史（D6）、網址有效時 seek 回 0 不重解析。
- 隨機（§決定 5，D7）：隨機順序是位置的順序；拖曳只移動歌曲、不改位置順序，拖進本輪已播的位置本輪不再播；「下一首播放」插在目前這首之後，連續加入依加入順序排；其餘未播位置不變；隨機順序持久化。
- 串流解析（§決定 6）：本機下載檔 → 記憶體網址快取（ADR 0016）→ 插件 `resolveStream`；開流失敗換候選一次；恢復播放、長暫停後 seek、前瞻交接前檢查網址過期；被取代的請求經宿主 `http.request` 取消網路工作。
- 錯誤恢復（§決定 7）：
  - `NetworkError`、`RateLimited`、傳輸中斷、提前結束：從目前位置重試 1／3／9 秒共 3 次；不在 `Online` 時暫停計數；仍失敗就跳過並提示。
  - `Unavailable`、`NotFound`、需登入與驗證類、`Unsupported`：立即跳過並提示。
  - `Unavailable(只有試聽)`：新設定「跳過試聽片段」（預設開）決定跳過或標「試聽」後播放（D4）。
  - 開不起來或解碼失敗換候選一次；緩衝飢餓 15 秒重解析一次、同首第二次跳過；桌面輸出裝置失敗只暫停並提示。
  - 跳過在 `queue`、`mix` 走下一首（D3），在 `temporary` 回到佇列；連續跳過達佇列長度或 10 首就停止並提示一次。
  - 一首歌正常播放 10 秒後重試計數歸零。
- 系統媒體控制（§決定 8）：`NowPlayingPublisher` 唯一出口，按鈕依播放能力推導；只在值改變時推送並序列化。M2 範圍內的轉接器：Android `audio_service`、Windows `smtc_windows`。
- 持久化與設定（§決定 10）：佇列（曲目鍵、目前位置、播放位置、隨機位置順序、循環模式、模式、Mix 身分、音量）持久化，位置每 10 秒及暫停、seek、進背景時存；「記住播放位置」「臨時播放回佇列倒退秒數」沿用；播放速度不持久化（E19）。
- 計時器（§決定 11）：位置檢查（每秒）與位置存檔（每 10 秒）只在播放中開，屬 `fmp_periodic_timer_owner` 允許的播放模組。
- 後端（§決定 3）：M1 已有兩個實作與前瞻交接；M2 補契約案例（M1 follow-up，見 §2）。
- 直播（§決定 9）：`playLive`、取消進行中的音樂請求、直播快照——屬 E12，在 M3（`milestones.md:64`）。

**(b) M2 的驗證**（ADR 0018 §如何確認；milestones.md:57 要求「ADR 0016、0017、0018 的測試」）
- 單元測試：
  - `QueueModel`：隨機位置語意、拖曳、連續下一首播放、臨時播放快照、Mix 修剪、上限。
  - `RecoveryPolicy`：每類錯誤的處理、離線暫停計數、歸零、連續跳過停止。
  - 預取後播放只解析一次；單曲循環每圈一筆歷史且不重解析；開直播取消進行中的音樂請求（直播屬 M3，見未定之處 15）。
- 後端契約測試：同一份純規則斷言跑兩個實作與假後端（M1 已有 `test/playback/backends/audio_backend_contract.dart`、`integration_test/audio_backend_contract_test.dart`；真後端 CI 不跑，手動兩平台，`app/AGENTS.md:416-417`）。
- lint `fmp_layer_imports` 的依賴表：`just_audio`、`media_kit` 只在後端實作目錄（M1 已有）；**結束原因型別只給後端與路由器 import；串流存取的窄介面只給 `PlaybackSession` import**——這兩條 M1 沒做，`app/AGENTS.md:410-411` 寫明「等 M2 有路由器與 `PlaybackSession` 時再加」。
- 第一個里程碑實測（前瞻交接、Android 音訊焦點）已在 M1 完成（`research/m1-acceptance.md`）；M2 的後端改動照 `app/AGENTS.md:18` 在兩平台重跑真後端契約。

**(c) 不在 M2**
- `playLive`、直播狀態輪詢與重連（E12，M3；輪詢由 ADR 0017 排程器負責）。
- Mix 的插件 `mix` 能力（E13，M3）；`QueueModel` 的 Mix 模式與修剪屬 ADR 0018 §決定 4，是否在 M2 做見未定之處 15。
- 均衡器、響度、睡眠定時器、邊聽邊存（功能凍結待辦，ADR 0018 §後果）。
- Linux `audio_service_mpris`、iOS／macOS 的 `audio_service`、`JustAudioBackend` 在 iOS／macOS 的實作、AVPlayer 格式實測（平台任務，`milestones.md:138-144`）。
- 歌單「全部」加入佇列的歌單 UI（M4，ADR 0019）；本機下載檔解析（M6，ADR 0020）。

**(d) ADR 已固定的名稱**
- 類別：`PlaybackController`、`QueueModel`、`QueueState`、`PlaybackSession`、`StreamResolver`、`PlaybackEventRouter`、`RecoveryPolicy`、`NowPlayingPublisher`、`AudioBackend`、`JustAudioBackend`、`MediaKitBackend`、`AppError`（ADR 0013）。
- 模式值：`queue`、`temporary`、`mix`、`live`、`detached`。
- 設定名：「跳過試聽片段」（預設開）、「記住播放位置」、「臨時播放回佇列倒退秒數」（沿用，欄位名依舊版 `rememberPlaybackPosition`、`tempPlayRewindSeconds`，`docs/audit/data.md` §7）。
- 套件：`audio_service`、`smtc_windows`、`audio_service_mpris`（Linux，非 M2）。
- 計時：重試 1／3／9 秒、緩衝飢餓 15 秒、歸零 10 秒、位置存檔 10 秒、佇列上限 10,000、Mix 100、連續跳過 10。
- 舊行為錨點（ADR 0018 §背景引用 `docs/audit/playback.md`）：播放歷史 §3.9；臨時播放 §3.10；速度、音量、輸出裝置 §3.14；音訊焦點與輸出裝置 §3.7；系統媒體控制 §3.8；單曲循環 §3.1（`playback_event_router.dart:465`、`audio_provider.dart:2820-2823`、`2276`）；Mix 不跳 `audio_provider.dart:1955`；歷史寫入 `playback_side_effects.dart:166-175`、`play_history_repository.dart:21-52`、`play_history_recorder.dart:34-53`。

**現況（M1 已有）**

| 檔案 | 一行 |
|---|---|
| `app/lib/playback/playback_controller.dart`（700 行） | 唯一入口與 `PlaybackState` 寫入者；`playQueue`、`play`、`pause`、`next`、`previous`、`seek`、前瞻、恢復都在這裡；沒有隨機、循環、音量、速度 |
| `app/lib/playback/playback_state.dart` | sealed 播放狀態、`PlaybackProgress` |
| `app/lib/playback/queue_model.dart`（77 行） | 記憶體、依序、只有 `queue` 模式、不持久化；`replace`／`moveNext`／`movePrevious` |
| `app/lib/playback/recovery_policy.dart` | `decideRecovery` 純函數；檔頭寫明 M1 沒有連線偵測、試聽設定、緩衝飢餓、輸出裝置、10 秒歸零 |
| `app/lib/playback/stream_resolver.dart` | 直接呼叫插件；沒有網址快取；`ResolvedStream.expiryMargin` 30 秒用於前瞻重新解析 |
| `app/lib/playback/playback_providers.dart` | `audioBackendProvider`、`playbackControllerProvider` 與狀態／佇列／進度 stream |
| `app/lib/playback/backends/{audio_backend,backend_rules,audio_backends,just_audio_backend,media_kit_backend}.dart` | `AudioBackend` 介面（目前沒有音量、速度、輸出裝置的成員）、共用規則、兩個實作 |
| `app/lib/platform/audio/{audio,audio_android,audio_windows}.dart` | `AudioBackendKind`、`PlayableFormat`、`PlaybackSupport` 與兩個平台的宣告 |
| `app/lib/ui/player/{player_bar,queue_tracks}.dart` | 播放列（兩段以上寬度：播放、下一首、上一首）；`queueTracksProvider` 是記憶體的曲目顯示資料（M1 沒有曲目表） |
| `app/lib/ui/shell/{app_shell,shell_shortcuts}.dart` | 外殼（兩個導覽項：搜尋、設定）、`shellShortcuts` 表（空白、Ctrl+←／→、Shift+←／→、Ctrl+F、Ctrl+,、F6）、焦點三區 |
| `app/lib/data/database/tables.dart` | schema v1，三張表：`appearance_settings`、`installed_plugins`、`plugin_storage` |

---

### ADR 0016 — 快取與離線

**(a) M2 要做的**
- 統一快取庫（§決定 2）：一個快取模組擁有 `getApplicationCacheDirectory()` 之下的目錄，以**獨立的 drift 索引 `cache.db`**（與主資料庫分開）加檔案保存；索引記鍵、類別、所屬插件、大小、最後存取、期限；檔案被系統清掉視為未命中；移除插件時刪除其項目。
- 一個總上限（§決定 3）：使用者設定「快取上限」128MB／256MB／512MB／1GB，預設由平台層宣告（桌面 256MB、行動 128MB；未設定＝跟著預設，ADR 0011）；超過時不分類別依最後存取淘汰；設定頁顯示各類用量與一個「清除快取」（含 Flutter 記憶體 `ImageCache`）；舊版兩個快取設定不匯入。
- 圖片（§決定 4）：鍵為實際請求的 URL，經 ADR 0012 媒體 client；封面 DTO 為多尺寸 `artwork: [{url, width?}]`，宿主挑最接近且不小於顯示尺寸的一張（M1 的 `pickArtwork` 已做）；以 `cached_network_image` 的自訂 cache manager 接到快取庫，接不起來就保留它自己的索引、由統一淘汰器依檔案大小一起淘汰；記憶體 `ImageCache` 大小由平台層宣告、不開放設定。
- 串流網址（§決定 5）：DTO 的可空 `expiresAt`（插件從網址讀）；宿主只在記憶體保存，鍵為曲目鍵＋分 P＋音質偏好、上限 64 筆，有效到 `expiresAt − 5 分鐘`，為空時 5 分鐘內有效；播放失敗作廢該筆；下載一律重新解析；預取與播放共用同一份。
- 離線判定（§決定 6）：網路層擁有網路狀態——系統回報沒有網路介面（`connectivity_plus`，經平台層）即 `NoInterface`；30 秒內 3 次 `NetworkError` 且其間沒有成功即 `Unreachable`；任何請求成功或介面變化回到 `Online`；不輪詢；離線中不發背景請求、使用者操作照常發請求。
- 離線時各功能（§決定 7）：音樂庫、歌單、下載管理、設定完整可用；已下載曲目照常播放，未下載的淡化顯示、播放時自動跳過並提示一次，整個佇列不能播就停止；歌詞與排行顯示快取，沒有就顯示離線狀態；線上搜尋、電台與直播、插件安裝與更新、登入顯示離線狀態、不送請求；一個全域離線提示加共用的離線空狀態元件；離線期間背景產生的 `NetworkError` 不跳 toast。

**(b) M2 的驗證**（ADR 0016 §如何確認）
- 單元測試：串流網址快取的安全邊界、`expiresAt` 為空、作廢、下載不走快取；**預取後播放只解析一次**。
- 單元測試：快取庫跨類別淘汰到上限以下；檔案被刪視為未命中；清除後用量為 0；移除插件刪除其項目。
- 單元測試：網路狀態的轉換，且沒有計時器輪詢。
- widget 測試：各頁在離線時顯示離線狀態。
- 插件契約（ADR 0015）：播放類插件的 `resolveStream` 檢查案例斷言 `expiresAt` 與 fixture 網址內的期限參數一致（`app/test/plugins/contract/checks.dart:275` 目前只把 `expiresAt` 轉成值，是否已斷言與網址期限一致未查）。
- lint `fmp_layer_imports`：快取目錄只經快取模組取得。

**(c) 不在 M2**（ADR 0016 §考慮過的選項／§後果）
- 排行快取（E14，M4）、歌詞內容與 AI 標題解析快取（ADR 0021，M7）。
- 手動離線模式、邊聽邊存、已下載內容容量管理（功能凍結待辦）。
- 通用 HTTP 回應快取與搜尋結果快取（否決）。
- 排程器的背景刷新與離線時暫停、補跑（ADR 0017，同在 M2，見下）。
- 已下載曲目照常播放（下載屬 M6）。

**(d) ADR 已固定的名稱**
- `cache.db`（獨立 drift 索引）；`getApplicationCacheDirectory()`。
- 狀態：`NoInterface`、`Unreachable`、`Online`。
- 設定「快取上限」值：128MB／256MB／512MB／1GB；預設桌面 256MB、行動 128MB（平台層宣告）。
- 套件：`connectivity_plus`、`cached_network_image`（自訂 cache manager）。
- DTO：`artwork: [{url, width?}]`、`expiresAt`（可空）。
- 串流網址快取：上限 64 筆、安全邊界 5 分鐘、`expiresAt` 為空 5 分鐘。
- 離線規則：30 秒內 3 次 `NetworkError`。
- 舊版錨點：`lib/main.dart:156-164`、`network_image_cache_service.dart:127-140`（圖片三層）；`track.dart:68-71`、`stream_resolution_service.dart:299-304`（網址持久化使預取被跳過）。

**現況**：沒有 `cache.db`、沒有快取模組、沒有 `connectivity_plus`；程式中沒有 `NoInterface`／`Unreachable`／`Online` 型別（grep 無）；封面以 `Image.network` 讀（`app/AGENTS.md:532-534`，「磁碟快取與經媒體 client 讀圖在 M6」）；`app/lib/ui/artwork/artwork_image.dart` 已有 `pickArtwork`；`ResolvedStream` 沒有快取。

---

### ADR 0017 — 背景排程器與啟動維護清單

**(a) M2 要做的**
- service 層 `BackgroundScheduler`（§決定 1）：會發網路請求的週期工作的唯一擁有者（首頁排行、匯入歌單自動刷新、電台直播狀態、收聽中的直播間資訊固定 1 分鐘）。
- 工作宣告（§決定 2）：id、所屬插件（可空）、間隔（空＝關閉）、執行函式；「上次成功時間」存資料庫、重啟後照算；排程器只用一個計時器指向最早到期的工作。
- 何時跑（§決定 3）：只有 `AppLifecycleState.resumed` 或 `inactive` 且網路狀態 `Online` 才跑；`hidden`、`paused` 暫停（取消計時器、進行中的請求跑完）；變成可見或網路恢復時所有已到期工作各跑一次；App 啟動視同變成可見。
- 並行與失敗（§決定 4）：全域同時最多 2 個、同一插件依序；失敗依 1、2、4… 分鐘退避、上限為該工作的間隔，`RateLimited.retryAfter` 優先。
- 手動與取消（§決定 5）：手動刷新不看間隔、立即執行；插件停用或移除、榜單停用、歌單改為不啟用、間隔設為關閉時立即移除工作，以代際檢查丟掉過期結果。
- 設定（§決定 6）：排行刷新間隔 30／60／120／240 分或關閉（預設 60）；電台狀態間隔 關閉／1／3／5／10 分（預設 5）；匯入歌單每張 1／6／12／24／48／72／168 小時或不啟用（新匯入預設 24 小時）；舊值原樣匯入。
- **啟動維護清單**（§決定 1）：一次性啟動維護登記在清單，**第一個畫面後依序跑一次；「清單在 M2 實作，ADR 0026」**。ADR 0025 加入的項目：log 保留期限、診斷包暫存清理。ADR 0022 的更新檔清理、ADR 0019 的孤兒曲目也登記在這份清單。

**(b) M2 的驗證**（ADR 0017 §如何確認）
- 單元測試（假時鐘、假生命週期、假網路狀態）：看不見與離線時不跑；恢復後到期的工作各跑一次；只有一個計時器；手動刷新不看間隔；移除或停用後不再跑且丟掉過期結果；退避與 `retryAfter`；上次成功時間重啟後生效。
- lint `fmp_periodic_timer_owner`（加入 `fmp_lints`）：`Timer.periodic`、`Stream.periodic` 只准在排程器與播放核心模組；依 ADR 0015 寫雙向變異測試。現況 `app/AGENTS.md:567-579` 的規則表沒有這條，需新增；舊 `periodic_timer` static-rule 的登記表在舊專案 `test/support/periodic_timer_static_rule_test.dart:34-104`。
- 播放核心的 10 秒存檔、每秒位置檢查是這條 lint 的另一個允許擁有者（ADR 0018 §決定 11）。

**(c) 不在 M2**
- 所有具體週期工作：首頁排行（E14，M4）、匯入歌單自動刷新（E4，M4）、電台直播狀態與收聽中的直播間資訊（E12，M3）。M2 只建排程器本體與清單。
- 播放位置存檔（播放核心）、下載（事件驅動，ADR 0020，M6）、快取淘汰與 log 輪替（寫入時觸發）、更新檢查與插件更新（只手動，M3／M9）。
- `workmanager` 式系統排程、桌面縮到托盤時繼續跑（否決）。
- 診斷包暫存清理的對象（診斷包，ADR 0025，M3）、更新檔清理的對象（ADR 0022，M9）、孤兒曲目清理的對象（ADR 0019，M4）。

**(d) ADR 已固定的名稱**
- `BackgroundScheduler`；「啟動維護清單」；lint `fmp_periodic_timer_owner`。
- 狀態名沿用 ADR 0016（`Online`）。
- 設定值集合如 (a)。
- 舊行為錨點：`main.dart:347-365`（電台輪詢只在看不見時暫停，#95）。

**現況**：沒有排程器、沒有啟動維護清單；`lib/` 沒有 `Timer.periodic`／`Stream.periodic`；`AppLifecycleState` 只在 `app/lib/ui/toast/toast_host.dart` 用到。

---

### ADR 0025 — 只有「log 保留 7 天」屬 M2

**(a) M2 要做的**
- §決定 3「保留」：大小照 ADR 0011（2MB × 3）；最後修改超過 7 天的檔案由啟動維護清單（ADR 0017）刪除；先到哪個限制就先刪；不做設定項。

**(b) M2 的驗證**
- 單元測試：超過 7 天的檔被刪、未滿 7 天的保留，大小與天數同時作用（ADR 0025 §如何確認）。

**(c) 不在 M2**（`milestones.md:66`，M3）
- Debug 頁、開發者模式、診斷包、插件開發工具、重設資料、資料檢查（含其加入 Debug 頁的里程碑實測，§8，M3）。
- 診斷包暫存 zip 的清理項目（清單在 M2，項目隨診斷包在 M3）。

**(d) 已固定的名稱／格式**：log 目錄 `logs/`（資料目錄下）；檔案 `logs/fmp.jsonl`、`fmp.1.jsonl`、`fmp.2.jsonl`（JSON Lines，已在 M1 實作，`app/AGENTS.md:245-247`）；7 天；「不做設定項」。
**現況**：`app/lib/core/logging/log_file.dart` 輪替 2MB × 3；沒有保留天數的刪除。

---

### ADR 0024 — 播放頁 B、播放列三段、快捷鍵全表、焦點三區

**(a) M2 要做的**
- 播放頁方案 B（§決定 4）：
  - ≥ 840：左右各半；左為封面（上限 420dp）、曲名、歌手、進度、五個播放控制；右欄分頁「歌詞｜佇列｜詳細」，依裝置記住上次的分頁；「詳細」與右側面板共用同一個內容 widget。
  - extraLarge（≥ 1600）：三欄（約 1：1.15：0.9），封面與控制｜歌詞｜分頁「佇列｜詳細」。
  - 手機與 medium：封面與歌詞切換，佇列以底部面板開啟。
  - 共通：Esc 關閉；背景為模糊封面＋遮罩。
- 毛玻璃（§決定 1）：播放頁在模糊封面背景上，以半透明表面色（約 60–72%）＋一般模糊做右欄、佇列、控制區，不做折射；系統「減少透明度」或高對比時改為不透明。
- 播放列（§決定 5，依內容區寬度、曲名至少約 160dp）：≥ 840：隨機、上一首、播放、下一首、循環、輸出裝置、音量滑桿；600–839：上一首、播放、下一首、音量圖示（點開滑桿）、「⋯」（隨機、循環、輸出裝置）；< 600：播放、下一首。點空白處開播放頁，點擊區與按鈕分開（U3、U4）。
- App 內快捷鍵全表（§決定 8，固定、不可自訂、只在 FMP 為前景且焦點不在輸入框時有效）：

  | 按鍵 | 動作 | M1 已有 |
  |---|---|---|
  | 空白鍵 | 播放暫停 | 是 |
  | Ctrl+←／→ | 上一首／下一首 | 是 |
  | Shift+←／→ | 倒轉／快轉 5 秒 | 是 |
  | Ctrl+↑／↓ | 音量 | 否 |
  | Ctrl+S | 隨機 | 否 |
  | Ctrl+R | 循環 | 否 |
  | Ctrl+F | 搜尋 | 是 |
  | Ctrl+L／Ctrl+Q | 播放頁右欄切到歌詞／佇列 | 否 |
  | Esc | 關閉播放頁與對話框 | 否 |
  | F6 | 在導覽／內容／播放列三區之間移動焦點 | 是 |
  | Ctrl+, | 設定 | 是 |

- 焦點三區（§決定 8）：`FocusTraversalGroup` 分三區、Tab 只在區內移動（M1 已做，`app/AGENTS.md:526-528`）；M2 要把播放頁納入焦點與 Esc。
- 提示文字附按鍵；只有圖示的按鈕有 tooltip 與語意標籤。
- 斷點與右側「正在播放」面板（§決定 3）：expanded 以上常駐、可收起、可拖寬（U7）；播放頁依 `WindowClass` 切手機版／B 兩欄／B 三欄。
- 數字格式：`NumberFormat.compact`、slang 複數（§決定 6，若播放頁出現播放量等數字）。

**(b) M2 的驗證**（ADR 0024 §如何確認）
- widget 測試：播放頁在淺色與深色主題下通過 `meetsGuideline(labeledTapTargetGuideline)` 與 `textContrastGuideline`，播放頁以最淺與最深的測試封面各測一次。
- widget 測試：快捷鍵與焦點（空白鍵、Esc、F6，輸入框內空白鍵只輸入空格）；播放列三段寬度的控制項集合，曲名寬度不小於 160dp。
- golden（`alchemist`，色塊字型）：播放頁 B 在 1000、1400、1800 寬，播放列三段寬度；只守版面結構，數量保持少。
- i18n：三語言 key 集合相同（M1 已有閘門 `test/i18n/translations_test.dart`）。
- lint `fmp_design_tokens`（M1 已有）涵蓋新 UI。
- 第一個里程碑實測（空白鍵、F6、字形）已在 M1 完成。
- M1 的播放列測試 `test/ui/player/player_bar_test.dart` 的 `controls per width` 目前只斷言 M1 有的控制項（`app/AGENTS.md:516-519`）。

**(c) 不在 M2**
- 設定頁「鍵盤快捷鍵」列出 App 內與全域兩組、錄製全域快捷鍵與 App 內衝突時提示（M8，`milestones.md:110,113`）。
- 歌詞分頁的內容（歌詞，M7）；逐字、桌面歌詞。
- `docs/user-guide.md` 與關於頁（M9）；其他版面（搜尋頁 chip 列的修正等已在 M1）。
- 全域快捷鍵（M8）。

**(d) ADR 已固定的名稱**
- `AppTokens`、`AppLayout`、`WindowClass`（M1 已有）；播放頁「方案 B」；右欄分頁名「歌詞｜佇列｜詳細」；快捷鍵表如上；`FocusTraversalGroup` 三區。
- 規格數值：封面上限 420dp；曲名至少約 160dp；半透明約 60–72%；三欄比例約 1：1.15：0.9；快轉倒轉 5 秒。
- 示意頁網址（僅擁有者可見）：ADR 0024 檔頭與 `phase2-plan.md:280`。

**現況**：`app/lib/ui/shell/shell_shortcuts.dart` 已有 6 組鍵；`app/lib/ui/player/player_bar.dart`（294 行）；沒有播放頁、沒有右側「正在播放」面板（外殼只有搜尋與設定兩個導覽項）；`app/lib/ui/layout/window_class.dart`。

---

### ADR 0009 — 平台層（與 M2 相關：系統媒體控制、平台宣告）

**(a) M2 要做的**
- 系統媒體控制為平台層的一個能力，`<能力>.dart` 介面加 `<能力>_<平台>.dart` 實作；每個平台一份不可變的 `PlatformCapabilities`，只含已有實作的欄位（`app/AGENTS.md:167-177`、`.trellis/spec/app/platform/index.md`「加一個能力」五步）。
- 套件（§決定 6）：系統媒體控制用 `audio_service`（Android／iOS／macOS）＋ Windows SMTC ＋ Linux `audio_service_mpris`；`connectivity_plus`、`file_picker`、`path_provider` 五平台共用；桌面套件需要修補時用 git 依賴鎖 commit 並註明上游 issue。
- 平台層以外禁止平台判斷與平台套件 import（§決定 3）。
- 宣告也包含音訊後端與可播格式（§決定 2，M1 已有 `PlaybackSupport`）；ADR 0016 要求平台層另宣告「快取上限預設」與「記憶體 `ImageCache` 大小」（桌面／行動不同）。
- 新的 MethodChannel 一律 Pigeon（§決定 5）。

**(b) M2 的驗證**
- lint `fmp_platform_checks`、`fmp_layer_imports`（M1 已有）；`platform_test.dart` 逐平台核對宣告與實作；新欄位每個平台一個斷言（`.trellis/spec/app/platform/index.md` Quality Check）。
- 「宣告為沒有的能力，UI 不出現入口」是每個平台 child task 的驗收（ADR 0009 §如何確認）；M2 適用於輸出裝置等入口（見未定之處 5）。

**(c) 不在 M2**
- Linux、macOS、iOS 的實作檔（§決定 4）；托盤／全域快捷鍵／開機自啟（M8）；登入 WebView（M3）；應用內更新（M9）；桌面歌詞與懸浮歌詞（M7）；`PermissionGateway`（ADR 0020 §決定 9，M6）。

**(d) 固定的名稱**：`app/lib/platform/`、`PlatformCapabilities`、`AppPlatform`（組裝點 `lib/platform/platform.dart`）、套件 `smtc_windows`、`audio_service`、`audio_service_mpris`、`connectivity_plus`。系統媒體控制的目錄名與介面名 ADR 未定（見未定之處 6）。

---

### ADR 0010 — drift：M2 可能新增的表

**(a) M2 要做的**
- 新表走 `app/AGENTS.md:191-218` 與 `.trellis/spec/app/data/index.md` 的流程：bump `schemaVersion`、存新快照（`drift_schemas/app_database/`）、寫 migration 與升級測試、產生檔提交（§決定 3）。
- 時間存 UTC epoch 毫秒；音源 id 用字串；只存事實；串流 URL 不進資料庫；曲目以 `TrackKey` 字串為唯一鍵；設定在設定表、每組一張單列表（§決定 2、ADR 0011 §決定 7）。
- ADR 0010 §決定 1：只有資料層（repository）能存取資料庫；上層拿 repository 自己的值型別（`app/AGENTS.md:195-197`）。
- ADR 0010 §決定 3：migration 不得改寫使用者設定過的值，失敗整個回滾。
- `cache.db` 是 ADR 0010 §背景以外另一個資料庫，ADR 0010 §決定 2 的「表名」清單把它列為 ADR 0016 的獨立索引（M2）。

**(b) M2 的驗證**：schema 快照與升級測試在 CI（`test/drift/app_database/schema_test.dart`）；「migration 不改使用者設定過的值」測試；`fmp_layer_imports`。

**(c) 不在 M2**（表名由後續 ADR 定義）：`playlists`、`playlist_remote`、`playlist_entries`、`tracks`、`track_origins`、`match_results`（ADR 0019，M4）；`downloads`（ADR 0020，M6）；`lyrics_matches`（ADR 0021，M7）；舊資料匯入流程（M5）。

**(d) 已固定的名稱**：`cache.db`；`PRAGMA foreign_keys = ON`（M1 已做）。**M2 要新增的表（播放歷史、佇列持久化、排程器「上次成功時間」、播放設定組、快取設定）沒有任何 ADR 定表名或欄位**（見未定之處 1、2、3、9）。

**現況**：`app/lib/data/database/tables.dart` 只有 `appearance_settings`、`installed_plugins`、`plugin_storage`（schema v1）；repositories 為 `appearance_settings_repository`、`plugin_repository`、`plugin_storage_repository`。

---

### ADR 0011 — 設定分組（M2 引入的組）

**(a) M2 要做的**
- ADR 0011 §決定 7：設定依功能分組（播放、外觀、音樂庫與同步、下載、歌詞、網路、桌面、開發者），每組一張單列表、每個設定一個有型別的欄位，每組一個 Riverpod Notifier 只寫改動的欄位；欄位為空＝使用者沒設定過、讀取時套用程式預設。
- ADR 0026 §決定 2：該組欄位清單在引入它的里程碑定案。M1 只引入「外觀」組（`appearance_settings`）。**M2 引入「播放」組**（跳過試聽片段、記住播放位置、臨時播放倒退秒數等，具體欄位未定，見未定之處 3）；快取上限與排程器間隔屬哪一組 ADR 未寫（見未定之處 3、9）。
- 設定頁 expanded 以上用 list-detail（ADR 0024 §決定 6）。
- 舊值匯入：ADR 0016 §3 舊版兩個快取設定不匯入；ADR 0017 §6 舊的刷新間隔原樣匯入（M5）。

**(b) 驗證**：設定測試——寫入使用者值後改變程式預設，斷言讀到的仍是使用者值；未設定的欄位讀到新預設（M1 對外觀組已有，`test/settings/appearance_settings_test.dart`）。

**(c) 不在 M2**：其他組（音樂庫與同步、下載、歌詞、網路、桌面、開發者）；開發者模式與 log 層級調整（ADR 0025，M3）。
**(d) 固定的名稱**：組名如上；`.trellis/spec/app/settings/index.md` 的加欄位流程。
**舊版設定參考**（`docs/audit/data.md` §7，非 ADR 決定）：`rememberPlaybackPosition`（預設 true）、`restartRewindSeconds`（0）、`tempPlayRewindSeconds`（10）、`autoScrollToCurrentTrack`（false）、`playHistoryLimit`（10000）、`audioQualityLevelIndex`、`audioFormatPriority`、`preferredAudioDeviceId／Name`、`maxCacheSizeMB`、`rankingRefreshIntervalMinutes`（60）、`radioRefreshIntervalMinutes`（5）。

---

### ADR 0013、0023 — M2 行為

**ADR 0013（錯誤模型）**
- (a) 呈現表（§決定 5）中屬 M2 的行：無法取得「曲目上標示原因；播放時跳過並提示」；找不到「曲目標示『已失效』；播放時跳過並提示」；網路／限流在播放層由 ADR 0018 的 `RecoveryPolicy` 接手。同類別＋同音源短時間內只提示一次（ADR 0023 的 5 秒）。背景工作不跳 toast，只在對應畫面顯示狀態（排程器、離線）。
- (b) 驗證：播放層以 fixture 或假插件斷言各類別對應的恢復動作（ADR 0018 §如何確認）。
- (c) 不在 M2：音源各自的錯誤對應表（M3 加入 YouTube／網易時）；B 站 geetest（待辦）。
- (d) 名稱：`AppError` 十個子類（M1 已有）；`NetworkError`、`RateLimited`、`Unavailable(只有試聽)`。

**ADR 0023（Toast）**
- (a) 「跳過並提示」走 `Toaster`；M1 follow-up 要求控制器發出「跳過」事件才能提示（`implement.md:224`）；離線期間背景 `NetworkError` 不跳 toast（ADR 0016 §決定 7）；離線全域提示與播放頁的底部位移（外殼發佈 `toastBottomInsetProvider`，播放頁是全螢幕頁：「全螢幕頁：貼底部安全區」，ADR 0023 §決定 2）。
- (b) 驗證：widget 測試的全螢幕路由與對話框開啟時提示可見（M1 已有 `integration_test/toast_layering_test.dart`；M2 新增的播放頁路由需納入）。
- (c) 不在 M2：`ErrorReport`、詳細頁、「回報」按鈕、`bug_report.yml`（M3，`milestones.md:66`、`implement.md:276` 的 PR 12 說明）。
- (d) 名稱：`Toaster`、`ToastHost`、時長成功／資訊 4 秒、錯誤／警告 6 秒、去重 5 秒。

---

## 2. M1 帶來的 M2 待辦

| # | 待辦 | 來源 |
|---|---|---|
| 1 | CDN 403 開不起來目前對到 `Unsupported`，提示是「視為 bug」的通用訊息；M2 做恢復與提示時改對應 | M1 `implement.md:223`（12b 留下的後續） |
| 2 | 播放中「跳過並提示」：控制器沒有發出跳過事件，目前跳過不提示；M2 | `implement.md:224`；`app/AGENTS.md:438-439`；`recovery_policy.dart` 檔頭 |
| 3 | Android 返回鍵在任何分頁都直接離開 App（與舊版相同）；M2 做播放頁時一併看 | `implement.md:226` |
| 4 | 前瞻開不起來時兩個後端的行為沒有契約案例（Android 會被當成目前這首中斷；Windows 可能卡在 Playing）；前瞻解析比目前這首播完還慢時會多解析一次；M2 補契約案例 | `implement.md:227` |
| 5 | 被取代的 `resolveStream` 只丟結果、不取消網路工作（`SourcePlugin` 沒有取消參數）；ADR 0018 §決定 6 的「經宿主 `http.request` 取消」要等插件 API | `implement.md:228`；`app/AGENTS.md:441-442` |
| 6 | `.trellis/spec/app/playback/index.md` 的「實機驗證」段與 `verify-on-device` skill 重複；改成指向 skill（PR 12 動到播放時順手） | `implement.md:229` |
| 7 | 封面 `Image.network`：轉址的下一跳不經 `allowedHosts`、下載沒有大小上限與逾時；M6 的媒體 client 接手（與 ADR 0016 的 M2 圖片快取有衝突，見未定之處 7） | `implement.md:225`；`app/AGENTS.md:532-534` |
| 8 | ADR 0018 的兩條 `fmp_layer_imports` 規則（結束原因型別、窄介面）等 M2 有路由器與 `PlaybackSession` 時再加 | `app/AGENTS.md:410-411` |
| 9 | M1 的 `recovery` 缺的項目：連線偵測、試聽片段設定、緩衝飢餓、輸出裝置失敗、「正常播放 10 秒後歸零」（M1 換歌才歸零） | `app/AGENTS.md:437-438`；`recovery_policy.dart` 檔頭 |
| 10 | M1 的 `QueueModel` 與播放列只做 M1 有的功能：佇列只在記憶體、播放列只放 M1 有的控制項；其他模式、隨機、上限在 M2 | `queue_model.dart` 類別註解；`app/AGENTS.md:400-401,516` |
| 11 | 插件每重新載入一次，`Redactor._mediaCdns` 多一份相同規則（輸出不受影響）；M3 插件頁一併去重。**非 M2** | `implement.md:231`（列此以免誤收） |
| 12 | 啟動 log 的 `App started` 帶 `dataDirectory`（含系統使用者名稱）；M3 做診斷包時處理。**非 M2** | `implement.md:222` |
| 13 | 真實 Android 的 dev 與 prod 並存沒實測；Android 播放只以 AudioFlinger 寫入、音訊焦點與位置前進判斷，模擬器沒有出聲；flutter_js 成本只有 debug 模式的數字 | `research/m1-acceptance.md` § 留下的限制 |
| 14 | Android 的 `AndroidManifest.xml` `INTERNET` 已在 PR 13 處理（`app/AGENTS.md:103`），但新增 `audio_service` 會需要前景服務等宣告（ADR 未寫，見未定之處 6） | `implement.md:216`；`app/AGENTS.md:103` |
| 15 | 播放列「點空白處開播放頁」尚無播放頁；M1 的 UI 開始播放只經 `playTracks`（整份清單與起點交給 `playQueue`）；沒有播放的開發入口 | `app/AGENTS.md:443-446` |

---

## 3. 新增的依賴套件

目前 `app/pubspec.yaml` 的依賴沒有下列任何一個。最新版與日期取自 pub.dev API（2026-10-01 查）。**本檔不加依賴。**

| 套件 | 出處 | 用途 | 最新版 | 發佈日 | 備註 |
|---|---|---|---|---|---|
| `audio_service` | ADR 0018 §決定 8、ADR 0009 §決定 6 | Android 系統媒體控制 | 0.18.19 | 2026-06-29 | Flutter ≥ 3.27；持續維護；依賴 `audio_session`、`flutter_cache_manager`（與 `cached_network_image` 同一個依賴）；舊版 App 用 `^0.18.15`（`docs/audit/playback.md` §3.8） |
| `smtc_windows` | ADR 0018 §決定 8、ADR 0009 §決定 1、6 | Windows 系統媒體控制 | 1.1.0 | 2025-08-18 | 上一版 1.0.0 是 2024-10-17；距今約 13 個月沒有新版；依賴 `flutter_rust_bridge`、`ffi`（建置需求未查）；舊版 App 用 `^1.1.0`；SMTC 不支援 seek（舊版 `now_playing_publisher.dart:283-284`） |
| `connectivity_plus` | ADR 0016 §決定 6、ADR 0009 §決定 6 | 系統回報有沒有網路介面 | 7.3.1 | 2026-07-23 | 持續維護；`NoInterface` 判定來源 |
| `cached_network_image` | ADR 0016 §決定 4 | 圖片磁碟快取，自訂 cache manager | 4.0.4 | 2026-09-30 | 需 Flutter ≥ 3.44、Dart ^3.12（`app/` 是 Dart ^3.13.4）；4.0.2–4.0.4 在 2026-09-23 至 09-30 連發三版；依賴 `flutter_cache_manager`、`material_ui` |
| `flutter_cache_manager` | `cached_network_image` 的傳遞依賴；ADR 0016 §決定 4 的「自訂 cache manager」要實作它的介面 | 同上 | 3.4.5 | 2026-09-19 | ADR 未獨立列為依賴 |
| `audio_service_mpris` | ADR 0018 §決定 8 | Linux | 0.2.1 | 2026-03-15 | **非 M2**（Linux 延後）；同時有 1.0.0-beta.1／beta.2（2026-03） |
| `audio_session` | 無 ADR 點名（`just_audio`、`audio_service` 的傳遞依賴） | Android 音訊中斷與拔耳機 | 0.2.4 | 2026-06-29 | 舊版對中斷的處理在 `docs/audit/playback.md` §3.7；ADR 0018 沒規定 |

已有且與 M2 相關：`just_audio` ^0.10.6（最新 0.10.6，2026-06-29）、`media_kit` ^1.2.6（最新 1.2.6，2025-12-13；`media_kit_libs_windows_audio` 停在 2023-09 的 libmpv，ADR 0018 §後果）、`drift`、`sqlite3`、`path_provider`、`intl`、`clock`、`fake_async`、`alchemist`。

沒有列為依賴、但 ADR 提到的：`share_plus`（ADR 0025，M3）、`file_picker`（ADR 0009 五平台共用，M2 沒有用到它的 UI）、`opencc`（ADR 0019，M4）。

沒有套件被標為停止維護（`isDiscontinued` 皆無）；`smtc_windows` 是更新間隔最長的一個。

---

## 4. M2 範圍總表

| `milestones.md` M2 範圍 | ADR 章節 | 備註 |
|---|---|---|
| 完整 `QueueModel` | ADR 0018 §決定 4、5、10 | 模式、隨機、上限、持久化；Mix 與 live 模式的插件能力在 M3 |
| `RecoveryPolicy` | ADR 0018 §決定 7；ADR 0013 §決定 5；ADR 0016 §決定 6（暫停計數靠網路狀態）；ADR 0023（提示） | 依賴網路狀態 |
| 播放頁方案 B | ADR 0024 §決定 1、3、4 | 歌詞與詳細分頁內容分屬 M7、M3 |
| 播放列三段 | ADR 0024 §決定 5 | 輸出裝置、音量、隨機、循環控制項在 M2 加入 |
| App 內快捷鍵全表 | ADR 0024 §決定 8 | 設定頁列出兩組在 M8 |
| 焦點三區 | ADR 0024 §決定 8 | M1 已有，納入播放頁 |
| 系統媒體控制 | ADR 0018 §決定 1、8；ADR 0009 §決定 1、2、6 | 只做 Android、Windows |
| 速度、音量、輸出裝置（E19） | ADR 0018 §決定 3（`AudioBackend`）、§決定 7（輸出裝置失敗）、§決定 10（音量持久化、速度不持久化）；ADR 0024 §決定 5、8（播放列、Ctrl+↑／↓） | 只有 `questions.md` E19 與 `playback.md` §3.14 定義功能，ADR 沒有專章（見未定之處 4、5） |
| 播放歷史（E15） | ADR 0018 §決定 4（單曲循環每圈一筆，D6）；`questions.md` E15「保留」；`playback.md` §3.9 | 沒有 ADR 定資料表與頁面（見未定之處 1） |
| 統一快取庫 | ADR 0016 §決定 1–5 | |
| 離線狀態 | ADR 0016 §決定 6、7 | |
| 背景排程器 | ADR 0017 §決定 1–6 | 沒有具體工作可登記（見未定之處 9） |
| 啟動維護清單 | ADR 0017 §決定 1；ADR 0025 §決定 3、10；ADR 0019、0022 | M2 只有 log 保留一項（見未定之處 10） |
| log 保留 7 天 | ADR 0025 §決定 3 | |
| 驗收：ADR 0016、0017、0018 的測試 | 各 ADR §如何確認 | 見未定之處 15 |

---

## 5. 未定之處

每條列來源；這些會變成擁有者問題。分類：A 資料與設定、B 範圍邊界、C ADR 之間或與程式碼衝突、D 缺規格。

### A. 資料與設定

1. **播放歷史（E15）沒有資料模型也沒有頁面規格。**
   - 沒有任何 ADR 定表名、欄位、保留筆數（`grep` 全 ADR：只有 ADR 0018 §決定 4 的「單曲循環每圈記一筆歷史（D6）」與 §如何確認提到歷史；ADR 0010 §後果表列表沒有歷史表）。
   - 舊行為：`PlayHistory` 以 `PlayHistory.fromTrack(track)` 存曲目快照，依 `playHistoryLimit`（預設 10000）每寫一筆裁最舊（`docs/audit/playback.md` §3.9；`docs/audit/data.md` §7）。「保留筆數」設定項去留、是否需要快照欄位（`tracks` 表在 M4）未決。
   - 何時記：舊行為是「開流成功」與 gapless 跟隨，不是聽了幾秒；重試、啟動恢復、臨時播放結束恢復佇列不算（`playback.md` §3.9）。ADR 0018 只固定單曲循環每圈一筆，其他規則未明寫是否沿用。
   - 歷史頁的入口與版面：`questions.md:253` 只勾「保留」，M1 外殼只有「搜尋」「設定」兩個導覽項（`app_shell.dart`）；ADR 0024 沒有歷史頁。舊版頁面 `play_history_page.dart:633`（`docs/audit/playback.md:117`）。
   - 來源：`milestones.md:52`、`questions.md:253`、ADR 0018 §決定 4、ADR 0010 §決定 2。
2. **佇列持久化的儲存與 `tracks` 表的先後。**
   - ADR 0018 §決定 10 只列持久化的內容（曲目鍵、目前位置、播放位置、隨機位置順序、循環模式、模式、Mix 身分、音量），沒有表名或欄位；ADR 0019 §決定 1 的 `tracks`（曲目元資料）屬 M4，且說孤兒曲目是「沒有被歌單項目、佇列、下載紀錄參照」的曲目，暗示佇列會參照 `tracks`。
   - M1 沒有曲目表，播放列以 `queueTracksProvider`（記憶體）查顯示資料（`app/AGENTS.md:443-446`）。M2 持久化佇列後，重啟時曲名、封面、時長從哪裡來未定（只存曲目鍵無法顯示；ADR 0010 §決定 2「只存事實」）。
   - 同一問題適用於播放歷史（未定之處 1）。
   - 來源：ADR 0018 §決定 10、ADR 0019 §決定 1、`app/AGENTS.md:443-446`。
3. **「播放」設定組的欄位清單（ADR 0026 §決定 2 說在引入該組的里程碑定案）。**
   - ADR 已點名的欄位：「跳過試聽片段」（ADR 0018 §決定 7）、「記住播放位置」「臨時播放回佇列倒退秒數」（§決定 10，沿用）、「快取上限」（ADR 0016 §決定 3，所屬組未寫；舊版放在快取設定，`data.md` §7）。
   - 舊版有、ADR 未提是否保留：`autoScrollToCurrentTrack`、`restartRewindSeconds`、`playHistoryLimit`、`audioQualityLevelIndex`、`audioFormatPriority`、`preferredAudioDeviceId／Name`（音質與格式偏好屬播放還是網路／音源，ADR 0016 §決定 5 的快取鍵含「音質偏好」，ADR 0014 的 `resolveStream` 輸入沒有列音質偏好）、`sourceSettings` 各音源的設定（ADR 0001 舊版機制，ADR 0011 §決定 7 另一張表，M3）。
   - 預設值也沒定：快取預設「由平台層宣告」，但 `PlatformCapabilities` 目前沒有這個欄位。
   - 來源：ADR 0011 §決定 7、ADR 0026 §決定 2、ADR 0016 §決定 3。
4. **E19 的功能範圍與狀態不一致。**
   - `milestones.md:52` 把「速度、音量、輸出裝置（E19）」列入 M2；`questions.md:257` E19 那一列的勾選是第四欄「不確定」，不是「保留」；`phase2-plan.md:203` 把「E19 均衡器、響度」記成待辦（新功能），沒有為速度、音量、輸出裝置另寫決定。
   - 舊行為（`playback.md` §3.14）：速度 0.5–2.0（`app_constants.dart:43-51`）、播放頁可選（`player_page.dart:747-766`）、不持久化（`setSpeed` 只打後端，`audio_provider.dart:1174-1182`）；音量 0–1 存在 `PlayQueue.lastVolume`、靜音記住靜音前的值（只在記憶體）。
   - ADR 0018 §決定 10 確認：音量持久化（隨佇列）、速度不持久化。
   - ADR 0024 §決定 5 的播放列有音量與輸出裝置，**沒有速度控制**；§決定 8 的快捷鍵有音量（Ctrl+↑／↓），沒有速度。速度控制要放哪裡、選項集合是否沿用 0.5–2.0、音量步進大小（Ctrl+↑／↓ 一次多少）、靜音、速度對 `AudioBackend`／兩個引擎的行為（最大值 clamp）都沒有 ADR。
   - 來源：`milestones.md:52`、`questions.md:257`、`phase2-plan.md:203`、`playback.md` §3.14、ADR 0018 §決定 10、ADR 0024 §決定 5、8。
5. **輸出裝置只有 Windows，但播放列規格沒有平台條件。**
   - 舊版：輸出裝置選擇只有 Windows（`playback.md` §3.7、§3.14；偏好存 `preferredAudioDeviceId／Name`，啟動後裝置清單第一次就緒時套用一次，`audio_provider.dart:1252-1302`）。
   - ADR 0018 §決定 7 只說「桌面輸出裝置失敗只暫停並提示」；ADR 0024 §決定 5 的播放列 ≥ 840 與 600–839 都列輸出裝置，沒說 Android 是否顯示。ADR 0009 §如何確認要求「宣告為沒有的能力，UI 不出現入口」，但 `PlatformCapabilities`（`platform_capabilities.dart`）沒有輸出裝置欄位，`AudioBackend` 介面沒有裝置成員。
   - 裝置偏好存在哪（播放組設定？）、裝置消失時的行為（回到系統預設？）ADR 未寫。
   - 來源：ADR 0018 §決定 7、ADR 0024 §決定 5、ADR 0009 §如何確認、`playback.md` §3.7。

### B. 範圍邊界

6. **系統媒體控制的細節。**
   - 平台層目錄與介面名：ADR 0009 §決定 1 的能力清單寫「系統媒體控制」，沒有目錄名；ADR 0018 §決定 1 說「轉接器由平台層經 provider 注入」；`NowPlayingPublisher` 放哪個模組（播放模組或平台層）也未寫。
   - Android 宣告：`audio_service` 需要前景服務、通知相關宣告；ADR 0020 §決定 9 把 `POST_NOTIFICATIONS`（下載通知，第一次下載時請求）放到 M6 的 `PermissionGateway`，ADR 0020 §背景說舊版「沒有宣告 `POST_NOTIFICATIONS`」。M2 的媒體通知在 Android 13+ 是否需要請求通知權限、`AndroidManifest.xml` 要加什麼，ADR 沒有決定。
   - 舊版行為（`playback.md` §3.8）：`androidStopForegroundOnPause: true`、快轉倒轉 10 秒（App 內快捷鍵是 5 秒，ADR 0024）、SMTC 不支援 seek、封面經 `ThumbnailUrlUtils.getOsMediaArtwork` 轉成乾淨網址；M2 的媒體通知封面網址如何取、是否經媒體 client（M6）ADR 未定。
   - 音訊中斷：舊版有 duck 減半音量、pause 類中斷暫停並在結束時恢復、拔耳機暫停（`playback.md` §3.7），Windows 沒有任何焦點處理；ADR 0018 只固定「Android 換歌時不釋放音訊焦點」，沒有寫中斷與拔耳機的行為。
   - `smtc_windows` 最後發版 2025-08-18、依賴 `flutter_rust_bridge`，建置需求（Rust 工具鏈）未查。
   - 來源：ADR 0009 §決定 1、6；ADR 0018 §決定 1、8；ADR 0020 §決定 9。
7. **圖片快取（ADR 0016，M2）與媒體 client（M6）的衝突。**
   - ADR 0016 §決定 4：圖片「經 ADR 0012 媒體 client」，`milestones.md:53` 把 ADR 0016 放在 M2。
   - `app/AGENTS.md:321-322`：「媒體 client 延到 M6」；`app/AGENTS.md:532-534`：「磁碟快取與經媒體 client 讀圖（每跳檢查）在 M6（ADR 0016 §決定 4）」；`implement.md:225`：封面轉址與下載上限「M6 的媒體 client 接手」。
   - 所以「統一快取庫」在 M2 能做到哪一步（只做快取庫與索引、圖片仍 `Image.network`？還是 M2 就建媒體 client？）需要擁有者決定。
   - 另外 ADR 0016 §決定 4 的 fallback（`cached_network_image` 的 cache manager 接不起來就保留它自己的索引並由統一淘汰器依檔案大小一起淘汰）要實作時才知道走哪條，ADR 沒有指定先試哪個；`cached_network_image` 4.0.4 自己依賴 `flutter_cache_manager`。
8. **離線功能裡 M2 做不到的部分。**
   - ADR 0016 §決定 7：已下載曲目照常播放、未下載淡化（下載在 M6）、歌詞與排行顯示快取（M7、M4）、音樂庫／歌單／下載管理（M4、M6）、插件安裝與更新、登入（M3）。M2 只有搜尋、設定、播放列／播放頁可實作離線狀態。
   - ADR 0016 §如何確認的「widget 測試：各頁在離線時顯示離線狀態」在 M2 只能涵蓋存在的頁面；「離線時未下載的曲目播放時自動跳過並提示一次，整個佇列不能播就停止」在 M2 沒有「已下載」的概念。
   - 來源：ADR 0016 §決定 7、`milestones.md:53`。
9. **背景排程器在 M2 沒有可登記的工作。**
   - ADR 0017 §決定 1 的四個工作：排行（M4，E14）、匯入歌單刷新（M4，E4）、電台狀態與收聽中直播間資訊（M3，E12）。M2 只能用假工作測排程器本體。
   - 排程器的設定（§決定 6 的三組間隔）屬哪個設定組、哪個里程碑加欄位：ADR 0026 §決定 2 說欄位在引入該組的里程碑定案，這三個設定的功能分別在 M3／M4。
   - 「上次成功時間存資料庫」要新增一張表（表名未定），沒有 ADR 定欄位；M2 是否現在建表或等第一個真工作出現未定。
   - 來源：ADR 0017 §決定 1、2、6；`milestones.md:54`。
10. **啟動維護清單在 M2 的內容。**
    - 登記項目有四個來源：ADR 0025 的 log 保留（M2）、診斷包暫存清理（診斷包在 M3）、ADR 0022 的更新檔清理（M9）、ADR 0019 的孤兒曲目（M4）。M2 實際只有 log 保留一項；其他是否現在先放空的登記點、還是各里程碑加進去，ADR 0017 只說「清單在 M2 實作」。
    - 「第一個畫面後依序跑一次」的「第一個畫面」是 `runApp` 之後還是第一幀；失敗處理（跳過還是重試）ADR 未寫。
    - 來源：ADR 0017 §決定 1、ADR 0025 §決定 3、10、ADR 0019 §決定 1、ADR 0022。
11. **`cache.db` 的模組位置與 lint 擁有者。**
    - ADR 0010 §決定 1：只有資料層（repository）能存取資料庫；M1 的 `fmp_layer_imports` 把 `drift`／`sqlite3` 的擁有者限制在 `lib/data/`（`app/AGENTS.md:195`）。ADR 0016 §決定 2：快取模組擁有 `cache.db`、`fmp_layer_imports`「快取目錄只經快取模組取得」。快取模組放在 `lib/data/` 底下還是另一個目錄（需改 lint 擁有者表）ADR 未寫。
    - `cache.db` 是否也要 `drift_dev schema dump` 快照與 migration 測試（ADR 0010 §決定 3 對「資料庫」的規則）未寫。
    - 來源：ADR 0010 §決定 1、3；ADR 0016 §決定 2、§如何確認。
12. **移除插件時刪快取項目、排程工作的前提。**
    - ADR 0016 §決定 2、ADR 0017 §決定 5 都依賴「移除插件」事件；`app/lib/plugins/install/` 目前只有安裝（grep 無移除路徑），插件頁在 M3（ADR 0014 §決定 8 的 `plugin_storage` cascade 已有）。M2 只能在快取庫與排程器層面測「移除插件」的入口，UI 與事件來源在 M3。
    - 來源：ADR 0016 §決定 2、ADR 0017 §決定 5、`milestones.md:65`。
13. **佇列的使用者操作入口。**
    - ADR 0018 §決定 4、5 規定了「加入」「下一首播放」「歌單全部加入佇列」「拖曳」「所有加入方式檢查 10,000 首上限」，但 M2 沒有歌單（M4）；M2 的入口只能是搜尋結果與佇列面板。「加入佇列」「下一首播放」「移除」「清空」「跳到某首」在哪裡出現（搜尋結果的動作選單？播放頁佇列分頁？）ADR 0024 §決定 4 只說右欄分頁有「佇列」，沒有佇列的動作清單。
    - 超過 10,000 首的提示用哪個 i18n 與 `Toaster` 類別未寫。
    - 「隨機位置語意要在佇列頁說清楚」（ADR 0018 §後果）：「佇列頁」是獨立頁還是播放頁的佇列分頁，未寫。
    - 來源：ADR 0018 §決定 4、5、§後果；ADR 0024 §決定 4。
14. **臨時播放（D1）與佇列替換的 UI 觸發。**
    - 舊版 UI「點歌」幾乎都走 `playTemporary`（`playback.md` §3.10、§1.2，`docs/audit/playback.md:117`）。M1 的搜尋頁點一首則是 `playQueue`（整份搜尋結果當佇列從該首開始，`app/AGENTS.md:443-446`）。ADR 0018 §決定 4 定義了 `temporary` 模式但沒有說哪個使用者動作進入它、哪個動作取代佇列。
    - `detached` 模式在全部 ADR 中只出現在 ADR 0018 §決定 4 的一個詞（`grep detached` 只命中 ADR 0018 與無關的 ADR 0022），沒有定義。
    - 來源：ADR 0018 §決定 4、`playback.md` §3.10、`app/AGENTS.md:443-446`。
15. **哪些屬 M3 的功能其測試或模式要不要在 M2 做。**
    - ADR 0018 §如何確認含「開直播取消進行中的音樂請求」（直播 E12 在 M3）、`QueueModel` 的「Mix 修剪」（Mix 的插件能力在 M3，但修剪是 `QueueModel` 純邏輯）；ADR 0016 §如何確認含「插件契約斷言 `expiresAt` 與 fixture 網址內的期限參數一致」（官方插件目前只有 B 站）。
    - `milestones.md:57` 只寫「ADR 0016、0017、0018 的測試」，沒有區分。`QueueModel` 的 `mix`／`live` 模式是否在 M2 建出來（只有型別、沒有插件能力）未定。
    - 來源：`milestones.md:50,57,64`、ADR 0018 §決定 4、9、§如何確認、ADR 0016 §如何確認。

### C. ADR 之間或與程式碼的衝突

16. **離線時未下載曲目：ADR 0016 與 ADR 0018 的優先順序。**
    - ADR 0016 §決定 7：離線時未下載的曲目「播放時自動跳過並提示一次，整個佇列不能播就停止」。ADR 0018 §決定 7：`NetworkError`、`RateLimited` 等「從目前位置重試 1／3／9 秒共 3 次；不在 `Online` 時暫停計數；仍失敗就跳過並提示」。
    - 狀態為 `NoInterface`／`Unreachable` 時對一首尚未開始播的曲目，是立即跳過（ADR 0016）還是暫停計數等網路回來（ADR 0018）沒有明寫；與連續跳過達佇列長度或 10 首停止的規則如何疊加也未寫。
17. **App 內快捷鍵「焦點不在輸入框時有效」與 M1 的實作不同。**
    - ADR 0024 §決定 8：快捷鍵「只在 FMP 為前景且焦點不在輸入框時有效」。M1 的實作讓 Ctrl+F、Ctrl+, 與 F6 在輸入框裡也有效，只有同時是文字編輯鍵的空白、Ctrl／Shift＋方向鍵讓給輸入框（`shell_shortcuts.dart` 檔頭、`app/AGENTS.md:520-525`）。M2 新增的 Ctrl+S／R／L／Q／↑／↓、Esc 在輸入框內要不要生效（Ctrl+S、Ctrl+A 類在文字欄有編輯意義；Esc 關閉對話框）ADR 沒有逐鍵規定。
    - Ctrl+L／Ctrl+Q 在播放頁沒開時的作用未寫（ADR 0024 表格寫「播放頁右欄切到歌詞／佇列」）。
18. **ADR 0025 的 `AudioController` 與 ADR 0018 的 `PlaybackController`。** ADR 0025 §決定 5 寫「播放控制仍只經 `AudioController`」，ADR 0018 §決定 1 的新名稱是 `PlaybackController`（M1 已實作）。M3 的 Debug 頁會讀播放狀態；M2 要不要為它預留的資料（重試次數與下次重試時間、輸出裝置、串流格式／位元率／容器／來源類型、前後各 5 首，ADR 0025 §決定 5）未寫，`PlaybackState.Retrying` 目前帶什麼欄位見 `playback_state.dart`。
19. **網址有效期的兩個數字。** ADR 0016 §決定 5：記憶體網址快取有效到 `expiresAt − 5 分鐘`；M1 的前瞻與恢復使用 `ResolvedStream.expiryMargin = 30 秒`（`stream_resolver.dart`，ADR 0018 §決定 6「前瞻交接前檢查網址過期」沒給秒數）。兩個值的用途（快取是否可重用 vs. 已取得的候選是否該重新解析）不同，ADR 沒有說明 M2 是否要統一。
20. **`StreamResolver` 的快取鍵含「音質偏好」，但沒有這個偏好。** ADR 0016 §決定 5 鍵為「曲目鍵＋分 P＋音質偏好」；M1 的 `StreamRequest` 只有 `sourceId`、`cid`、`formats`（`stream_resolver.dart`）。音質偏好（舊版 `audioQualityLevelIndex`、`audioFormatPriority`）在 ADR 中沒有定義，與未定之處 3 相關。

### D. 其他缺規格

21. **舊資料匯入的歸屬措辭。** ADR 0026 §決定 2：「每個新增資料表的里程碑，同時補上那張表的舊資料匯入（M5 起）」，字面意思是 M5 之後新增的表在該里程碑補匯入；M5 之前新增的表由 M5 的 `legacy_import` 一次處理（`milestones.md:85` 寫匯入「歌單、曲目、歷史、設定、帳號」，ADR 0010 §決定 4）。M2 新增的表（歷史、佇列、排程器、播放設定、快取）的匯入對照（舊 `PlayHistory`、`PlayQueue`、`Settings`）到 M5 才寫，但 M2 定的欄位格式會限制它（持久化格式規則，`app/AGENTS.md:213-216`）。是否在 M2 就為舊資料欄位對照預留（例如歷史的曲目快照）需要決定。
22. **播放頁右欄「歌詞」與「詳細」分頁在 M2 的內容。** 歌詞屬 M7、曲目詳細（插件 `trackDetail` 能力）在 ADR 0014 §決定 4 列為能力、`milestones.md` 沒有標里程碑；右側「正在播放」面板與播放頁共用的「詳細」widget 的 M2 內容未定；M2 的「佇列」分頁是否獨佔右欄（歌詞分頁顯示空狀態？）未定。
    - 「依裝置記住上次的分頁」的儲存位置（外觀組？播放組？）未寫。
    - 右側面板的展開與寬度（舊版 `railExpanded`、`detailPanelExpanded`、`detailPanelWidth`，`data.md` §7）在 `appearance_settings` 還沒有欄位；`milestones.md` M2 範圍沒有把右側面板列入，但 ADR 0024 §決定 3 的表在 expanded 以上要求常駐。
    - 來源：ADR 0024 §決定 3、4；ADR 0014 §決定 4；`data.md` §7。
23. **播放頁的毛玻璃與封面色。** ADR 0024 §決定 1 規定半透明約 60–72％、減少透明度或高對比時改不透明；沒有規定如何偵測（`MediaQuery.disableAnimations`／`highContrast` 等，要查文檔）、封面色是否取主色（dynamic color 被否決），背景只用模糊封面＋遮罩。
24. **Android 返回鍵行為**（M1 follow-up 3）：返回鍵在播放頁、佇列面板、一般分頁各做什麼，ADR 0024 只規定 Esc 關閉播放頁，沒寫返回鍵。
25. **播放進度與位置存檔的觸發時機與「進背景時存」。** ADR 0018 §決定 10：位置每 10 秒與暫停、seek、進背景時存；「進背景」對應 ADR 0017 的 `hidden`／`paused`；桌面縮到托盤（M8）時的行為未寫；`fmp_periodic_timer_owner` 的允許目錄名（播放模組、排程器模組的實際路徑）ADR 0017 未寫路徑，M1 的 `lib/playback/` 是播放模組，排程器放哪未定（ADR 0017 稱 service 層，`app/` 目前沒有 `services/` 目錄；頂層是 `app/core/data/domain/i18n/platform/playback/plugins/settings/ui`）。

---

## 6. 建議的相依順序

只列工作之間「什麼要先有才能做什麼」，不是 PR 清單。

1. **決定未定之處 A、B 的擁有者問題**（尤其 1–5、7、13、14）：它們決定要不要建表、哪些功能在 M2。
2. **網路狀態**（`connectivity_plus` 經平台層、網路層擁有 `NoInterface`／`Unreachable`／`Online`）：被 `RecoveryPolicy`（暫停計數）、排程器（只在 `Online` 跑）、離線 UI、`Toaster` 靜音規則依賴。先於它們三者。
3. **生命週期狀態**（`AppLifecycleState` 的 provider，`resumed`／`inactive` vs. `hidden`／`paused`）：排程器與位置存檔的「進背景」都用它。
4. **資料層新表與設定組**（依 1、2、3 的決定）：播放設定組（含快取上限若歸於此組）、佇列持久化、播放歷史（需曲目顯示資料的來源）、排程器「上次成功時間」。每張表一次 schema bump、快照、升級測試（`app/AGENTS.md:191-218`）。先於佇列持久化、歷史、排程器、快取設定。
5. **`PlaybackSession`、`PlaybackEventRouter` 從控制器抽出**，加兩條 `fmp_layer_imports` 規則（`app/AGENTS.md:410-411`）：先於 `QueueModel` 與 `RecoveryPolicy` 的擴充（它們依賴事件路由的形狀），也先於新增後端成員。
6. **`AudioBackend` 介面加音量、速度、輸出裝置（Windows）**，並更新契約測試與假後端：先於播放列的對應控制項、快捷鍵 Ctrl+↑／↓、E19 UI、`PlatformCapabilities` 的輸出裝置欄位。
7. **完整 `QueueModel`**（隨機位置語意、`temporary`、上限、持久化、循環）→ **完整 `RecoveryPolicy`**（試聽設定、緩衝飢餓、10 秒歸零、離線暫停計數、跳過事件）→ 控制器發出跳過事件（M1 follow-up 2）→ 播放時的 `Toaster` 提示。前瞻失敗的契約案例（M1 follow-up 4）與 CDN 403 對應（M1 follow-up 1）在此一起處理。
8. **串流網址的記憶體快取**（`StreamResolver`）：依賴 `expiresAt`（M1 已有）與「音質偏好」的決定；先於「預取後播放只解析一次」的測試。
9. **快取庫與 `cache.db`**（模組位置與 lint 擁有者要先決定，未定之處 11）→ 圖片接到快取庫（依賴媒體 client 的決定，未定之處 7）→ 設定頁的快取上限、各類用量、「清除快取」→ 離線空狀態元件與全域離線提示。
10. **排程器**（工作宣告、單一計時器、生命週期與網路狀態輸入、退避、代際檢查）→ `fmp_periodic_timer_owner` lint（含雙向變異測試）。**啟動維護清單**（先放 log 保留 7 天一項）可與排程器並行，但要放在 `runApp` 之後。
11. **系統媒體控制**：平台層能力與宣告 → `NowPlayingPublisher` → Android（`audio_service`、Manifest、權限決定）與 Windows（`smtc_windows`）轉接器。依賴 `PlaybackController` 的完整狀態（5、7）。
12. **播放頁 B 與播放列三段**：依賴 7（狀態與佇列）、6（音量、輸出裝置）、9（封面載入）。順序：播放列完整控制項 → 播放頁路由與手機版 → B 兩欄 → extraLarge 三欄 → 右側「正在播放」面板（若納入 M2）→ 毛玻璃。Toast 底部位移在播放頁路由要驗證。
13. **App 內快捷鍵補齊與 Esc、焦點納入播放頁**：依賴 6、7（音量、隨機、循環）與 12（播放頁、右欄分頁、Esc）。
14. **播放歷史**（資料、記錄時機、頁面）：依賴 4（表）與 7（記錄時機在控制器）；頁面依賴導覽結構的決定。
15. **驗收**：兩平台端到端各一次（含 `verify-on-device`，ADR 0027）；ADR 0016、0017、0018 的測試；更新 `milestones.md` 狀態與勾選（ADR 0026 §如何確認）；`.trellis/spec/app/playback/index.md` 與 `app/AGENTS.md` 同步（新增 lint 規則、閘門說明）。
