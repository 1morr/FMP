# 0018 — 播放核心：單一控制器（含直播）、Dart 端佇列、兩個後端、依錯誤類別恢復或跳過

- 狀態：已採納
- 日期：2026-09-28
- 影響範圍：`app/` 的播放模組（控制器、佇列、請求、後端、路由、恢復、系統媒體控制）、`resolveStream` 與 `live` 的 DTO、平台能力宣告、播放相關設定

## 背景

舊專案（`.trellis/tasks/archive/2026-09/09-27-design-playback-core/research/current-state.md`、`docs/audit/playback.md`，已以程式碼核對）：

- `AudioController`（2,953 行）已拆出 13 個協作者；路由純函數、請求代際、前瞻計畫、`NowPlayingPublisher` 的形狀可用。
- 狀態至少 5 份並存，`PlayerState.error` 一欄承載三種內容。
- 只有 queue 模式遇到無法取得會跳過，Mix 完全不跳（D3）；限流只設錯誤不重試（D5）；重試次數成功後不歸零；被取代的請求不取消網路工作。
- 電台直接操作後端、繞過控制器，開電台只暫停音樂、不取消進行中的解析（D8）；`restore()` 路徑也不停電台。
- 隨機模式下「下一首播放」插到隨機位置（D7）。

本 ADR 延續舊 ADR 0003「兩個後端」的形狀，適用於 `app/`；舊 ADR 0003 仍描述根目錄舊專案。

## 考慮過的選項

- **全平台 `media_kit`**：否決。Android 的通知、音訊焦點、拔耳機、gapless 都要自接，APK 每個 ABI 約 +3MB；
  均衡器只能靠 mpv 濾鏡且有失效回報；Windows／macOS／iOS 的 libs 停在 2023-09，蘋果平台還不接 Now Playing。
- **佇列真相放原生播放清單、Dart 只投影**（Spotube、Harmonoid、Finamp）：否決。臨時播放、Mix、位置式隨機與持久化都需要 Dart 端真相。
- **保留電台繞過控制器的例外**：否決，它是 D8 競態的來源。
- **隨機模式下「下一首播放」插到隨機位置**：否決（擁有者 2026-09-28 選擇插在目前這首之後）。
- **只在 queue 模式跳過、錯誤以字串存在狀態裡**：否決（D3、ADR 0013）。
- **Namida 的 7 秒倒數再跳過**：否決，改依 ADR 0013 的呈現表「跳過並提示」。

## 決定

1. **元件**：`PlaybackController` 是 UI、系統媒體控制與直播的唯一播放入口；協作者（`QueueModel`、`PlaybackSession`、`StreamResolver`、
   `PlaybackEventRouter` 純函數、`RecoveryPolicy` 純函數、`NowPlayingPublisher`）只回報、不寫狀態。系統媒體控制轉接器由平台層經 provider 注入。
2. **狀態**：一份 sealed 播放狀態（`Idle`、`Loading`、`Playing`、`Paused`、`Buffering`、`Retrying`、`Failed(AppError)`）；位置等高頻資料走獨立 stream；
   `QueueState` 與播放狀態沒有共同欄位。
3. **後端**：`AudioBackend` 介面，兩個實作——`JustAudioBackend`（Android、iOS、macOS）與 `MediaKitBackend`（Windows、Linux）；
   不能收斂的差異寫在介面 dartdoc，可收斂的規則（結束原因分類、直播邊緣 seek、前瞻計畫）是共用純函數並有契約測試。
   平台層宣告使用哪個實作與**可播格式**（ADR 0009）。後端只持有「目前＋一個前瞻」。Android 換歌時不釋放音訊焦點。
4. **佇列與模式**：佇列真相在 Dart 端 `QueueModel`。模式為 `queue`、`temporary`（臨時播放，D1，保留最早快照並回到佇列）、`mix`（插件 `mix` 能力，
   已播超過 100 首刪最舊的已播項目）、`live`、`detached`。歌單「全部」只加入佇列（D2）。所有加入方式檢查 10,000 首上限。
   單曲循環每圈記一筆歷史（D6），網址有效時 seek 回 0 不重解析。
5. **隨機**（D7）：隨機順序是位置的順序；拖曳只移動歌曲、不改位置順序，拖進本輪已播的位置本輪不再播；
   「下一首播放」插在目前這首之後，連續加入依加入順序排；其餘未播位置不變；隨機順序持久化。
6. **串流解析**：本機下載檔 → 記憶體網址快取（ADR 0016）→ 插件 `resolveStream`。輸入含分 P 與**平台可播格式**，輸出為依優先序排好的候選串流
   （網址、標頭、格式、`expiresAt`）；開流失敗換候選一次。恢復播放、長暫停後 seek、前瞻交接前檢查網址過期。被取代的請求經宿主 `http.request` 取消網路工作。
7. **錯誤恢復**（依 ADR 0013 類別，由 `RecoveryPolicy` 決定）：
   - `NetworkError`、`RateLimited`、傳輸中斷、提前結束：從目前位置重試 1／3／9 秒共 3 次；不在 `Online` 時暫停計數（ADR 0016）；仍失敗就跳過並提示。
   - `Unavailable`、`NotFound`、需登入與驗證類、`Unsupported`：立即跳過並提示。
   - `Unavailable(只有試聽)`：新設定「跳過試聽片段」（預設開）決定跳過或標「試聽」後播放（D4）。
   - 開不起來或解碼失敗換候選一次；緩衝飢餓 15 秒重解析一次、同首第二次跳過；桌面輸出裝置失敗只暫停並提示。
   - 跳過在 `queue`、`mix` 走下一首（D3），在 `temporary` 回到佇列；連續跳過達佇列長度或 10 首就停止並提示一次。
   - 一首歌正常播放 10 秒後重試計數歸零。
8. **系統媒體控制**：`NowPlayingPublisher` 唯一出口，按鈕依播放能力推導；轉接器 Android／iOS／macOS 用 `audio_service`、Linux 用 `audio_service_mpris`、
   Windows 用 `smtc_windows`；只在值改變時推送並序列化。
9. **直播**：`PlaybackController.playLive` 經插件 `live` 能力取流，走同一個 `PlaybackSession`，開直播必然取消進行中的音樂請求（D8）；
   進入時記佇列快照、停止時回到原佇列。提前結束時先問插件是否仍在直播，是才以 1／3／10 秒重連 3 次。
   直播狀態查詢失敗顯示「查詢失敗」，不當成「未開播」（D10）；直播狀態輪詢與收聽中刷新由 ADR 0017 的排程器負責。
10. **持久化與設定**：佇列（曲目鍵、目前位置、播放位置、隨機位置順序、循環模式、模式、Mix 身分、音量）持久化，位置每 10 秒及暫停、seek、進背景時存。
    「記住播放位置」「臨時播放回佇列倒退秒數」沿用；播放速度不持久化（E19）。
11. **計時器**：播放模組的位置檢查（每秒）與位置存檔（每 10 秒）只在播放中開，是 `fmp_periodic_timer_owner`（ADR 0017）允許的播放模組。

採用的慣例：Namida 的「一個介面、Android ExoPlayer／桌面 mpv」與 `insertAfterLatest`；Harmonoid 的媒體控制推送去重與序列化；
Finamp 以 `audio_service` 接系統媒體控制；ADR 0013 的錯誤類別與呈現表。

## 後果

- 好的：電台與音樂不會再互相覆蓋；Mix 與佇列的壞曲處理一致；錯誤不再以字串外洩到畫面；快速切歌不再堆積網路請求；
  新平台只要選一個既有後端並宣告可播格式。
- 壞的：仍要維護兩個後端；蘋果平台的 AVPlayer 格式較窄，插件要依可播格式挑串流；隨機位置語意要在佇列頁說清楚。
- 之後要注意：均衡器、響度、睡眠定時器、邊聽邊存在功能凍結待辦；Windows 的 libmpv 庫停在 2023-09；
  iOS／macOS 的格式支援（B 站 DASH 音訊、直播 HLS）在有機器時實測。

## 如何確認

- 單元測試：
  - `QueueModel`：隨機位置語意、拖曳、連續下一首播放、臨時播放快照、Mix 修剪、上限。
  - `RecoveryPolicy`：每類錯誤的處理、離線暫停計數、歸零、連續跳過停止。
  - 開直播取消進行中的音樂請求；預取後播放只解析一次；單曲循環每圈一筆歷史且不重解析。
- 後端契約測試：同一份純規則斷言跑兩個實作與假後端。
- lint `fmp_layer_imports`（ADR 0015）的依賴表：
  - `just_audio`、`media_kit` 只在後端實作目錄；
  - 結束原因型別只給後端與路由器 import；
  - 串流存取的窄介面只給 `PlaybackSession` import。

  這一組取代舊 `playback_event_routing`、`audio_seam`、`audio_backend_shared_rules` static-rule。
- 第一個里程碑實測：兩個後端的前瞻交接；Android 換歌時不釋放音訊焦點。
