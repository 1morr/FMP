# 控制器的佇列操作、臨時播放與入口（M2 PR 10）

> 父任務：`.trellis/tasks/10-01-m2-full-playback`。技術設計在父任務 `design.md` §7.2（臨時播放、回到佇列）、§7.3（入口表）、§7.6 末段（單曲循環）、§7.9（`events` stream，這個 PR 只有 `QueueFull`）、§3.3（`playback_settings`）、§9.8（設定頁）；本檔只列做什麼與驗收。PR 9 的 `QueueModel` 已合併（`app/lib/playback/queue_model.dart`），它留下的事在父任務 `implement.md`「PR 9 留下的」。

## 目標

使用者在搜尋頁點一首＝臨時播放，播完或按上一首／下一首回到原本的佇列；用選單把歌「下一首播放」「加入佇列」；隨機與循環可以切換。控制器接上 PR 9 的完整模型。

## 做什麼

1. **控制器 API**（`PlaybackController`）：`playTemporary`、`addToQueue`、`playNext`、`removeAt`、`move`、`jumpTo`、`clear`、`setLoopMode`（或輪轉）、`setShuffle`；上一首傳實際播放位置（3 秒規則）。原本的 `playQueue` 沒有 UI 呼叫端後刪掉或改成測試以外仍有人用的形狀（只留有人呼叫的）。
2. **臨時播放**：
   - 進入、回到佇列照 design §7.2：載入快照那首；「記住播放位置」開時從快照位置倒退「臨時播放回佇列倒退秒數」，關時從頭；原本在播才自動播；佇列原本是空的時停在 `Idle`。
   - 觸發：臨時曲目播完、按下一首、按上一首（被跳過的部分在 PR 12）。
   - 臨時播放中不做前瞻交接到快照那首（否則會從頭播）；照舊版「臨時播放不預取」。
3. **單曲循環**：把同一份解析結果設成前瞻，收到 `SourceAdvanced` 時佇列不動；網址快過期時照 §7.4 先重新解析（design §7.6 末段）。臨時播放中單曲循環循環的是臨時曲目、模式維持 `temporary`。
4. **PR 9 留下的四件事**（父任務 `implement.md`「PR 9 留下的」）：
   - 佇列編輯（拖曳、插入、移除、下一首播放、附加、隨機切換）後重新準備前瞻，不讓前瞻指到別首；
   - 臨時播放結束時的交接（上面第 2 點）；
   - 臨時播放中佇列為空時 `hasNext` 與 `next` 不一致：讓播放列的下一首按鈕和實際行為一致；
   - 空佇列進入臨時播放後再加歌，回到佇列不自動播：照 design「佇列原本是空的時停在 `Idle`」確認並寫測試定下。
5. **`events` stream**：控制器加 `events`，這個 PR 只有 `QueueFull`（加入會超過 10,000 首整批不加時發）。外殼以 `ref.listen` 轉成 `Toaster` 提示（在 listener 裡，不在 build 裡）。三語言文案。
6. **入口**（design §7.3，只做搜尋頁與播放列；佇列分頁在 PR 18b、歷史在 PR 15）：
   - 搜尋頁點一下＝臨時播放；
   - 選單（右鍵、長按、尾端「⋯」）：「播放」（＝臨時播放，舊版 TrackAction「播放」也是 `playTemporary`，`docs/audit/playback.md` §1.2 表）、「下一首播放」、「加入佇列」；
   - 播放列的隨機、循環按鈕（快捷鍵 Ctrl+S、Ctrl+R 在 PR 17，不在這裡）。若播放列目前的版面放不下，照 ADR 0024 與現有播放列的做法定，並在報告說明。
7. **刪 `queueTracksProvider`**；播放列改讀 `QueueEntry` 的 `TrackInfo` 顯示資料。
8. **`playback_settings` 表**（design §3.3）：PR 8 還沒做，這個 PR 先建**整張表**（§3.3 全部欄位，一次 migration；主資料庫 schema 升 v3），repository 的 `write`／`clear` 一次涵蓋全部欄位；Notifier 只加這個 PR 用到的兩個 setter：`remember_position`（預設開）、`temp_play_rewind_seconds`（預設 10，選項 0／3／5／10／15／30）。照 data spec 走完整流程（快照、`stepByStep`、migration 三種測試、`schema_test`），照 PR 5 的 `network_settings` 形狀。
9. **設定頁「播放」組**：新增一組，放這兩列（design §9.8：外觀、播放、網路三組）。三語言文案。
10. **改寫**：`search_page_test.dart` 的 `tapping a result plays the whole list from it` 與 `install_search_play_test.dart` 的期望改成臨時播放。
11. 文件：`app/AGENTS.md` § 播放（控制器的佇列操作、臨時播放、單曲循環、`events`）、§ 設定（播放組）、需要時 § 介面；playback／settings／ui spec。每條規則寫閘門，沒有閘門的寫明。

## 不做

- 佇列分頁與底部面板、拖曳 UI、清空確認框（PR 18b）；歷史頁（PR 15）。
- 快捷鍵（PR 17）。
- 其他 `events`（`TrackSkipped`、`PlaybackStopped`、`OutputDeviceFailed`、`PreviewPlaying`，PR 12／13）。
- 音質、格式偏好的 setter 與設定列（PR 8）；其他 `playback_settings` 欄位的 setter（各自的 PR）。
- 持久化佇列（PR 14）。

## 驗收

- [ ] 測試：
  - 臨時播放結束、按下一首、按上一首都回到佇列；倒退秒數與「記住播放位置」四種組合；原本暫停時只載入不播；佇列原本是空的時停在 `Idle`；
  - 臨時播放中不預取、不交接到快照那首；
  - 單曲循環不重解析（兩圈只有一次 `Resolving stream`）；快過期時重新解析；臨時播放中單曲循環仍回到快照；
  - 佇列編輯後前瞻重新準備（拖曳、下一首播放、附加、移除、隨機切換各至少一例，交接到的是新的下一首）；
  - 上一首 3 秒兩側（控制器傳入實際位置）；
  - 加入超過上限發 `QueueFull`，外殼出現提示；
  - 搜尋頁點一下＝臨時播放；三個選單項目各自的效果；
  - 播放列的隨機、循環按鈕；
  - `playback_settings`：settings 五種與 migration 三種（照 data spec）；設定頁「播放」組兩列。
- [ ] 驗證清單全綠（父任務 implement.md「每個 PR 的固定流程」第 5 步），含 `lint_sentinel`（若動到 lint）。
- [ ] 實機（重播模式，測試插件；Windows 與 Android 模擬器各一次）：
  - 搜尋→點 A（臨時播放）→ 選單把 B、C 加入佇列 → 播放列下一首；
  - 回到佇列時位置與倒退正確；
  - 單曲循環兩圈（log 只有一次解析）；
  - 設定頁「播放」組改倒退秒數後生效。
