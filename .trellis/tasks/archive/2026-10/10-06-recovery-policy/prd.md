# `RecoveryPolicy` 完成與播放提示（M2 PR 12）

> 父任務：`.trellis/tasks/10-01-m2-full-playback`。技術設計在父任務 `design.md` §5.3（離線時的播放）、§7.5（`RecoveryPolicy` 完成，含 2026-10-06 新增「開流失敗但沒有狀態碼」一列）、§7.9（`events` 與提示）、§10 末段（`previewOnly` 只在測試插件）、§3.3（`skip_preview_clips`，表已在 PR 10 建好）；M1 follow-up 1、2、9。執行清單在父任務 `implement.md`「12.」。本檔只列做什麼與驗收。

## 目標

播放失敗時照錯誤類型做對的事：該重試的重試、網址失效的先重新解析、離線時停下等網路並在恢復後自動續播、救不回來的跳過並告訴使用者原因；試聽片段依設定跳過或照播並標示。

## 做什麼

1. **`decideRecovery`**（照 design §7.5 的表逐列實作）：
   - 新輸入：網路狀態（PR 2 的 `NetworkStatus`）、「跳過試聽片段」、這一首已重解析過的次數；
   - 新結論：`WaitForNetwork`、`PlayAsPreview`、`ReResolve`；
   - `NetworkError`、`RateLimited`、中斷、提前結束：`online` 時 1／3／9 秒重試、仍失敗跳過；不是 `online` 時 `WaitForNetwork`；
   - 不可重試的錯誤立即跳過並提示；
   - 開不起來、解碼失敗：換候選一次，再失敗跳過；
   - HTTP 403／404／410（PR 11 的 `SourceFailed.httpStatus`）：作廢網址快取、重解析一次，仍被拒換候選一次，再不行跳過（404、410 → `NotFound`，403 → `Unavailable`，原因為空）；
   - **開流失敗但沒有狀態碼**（Android 一律如此）：同樣先作廢、重解析一次，仍失敗換候選一次，再不行跳過（`Unsupported`）；
   - 緩衝飢餓 15 秒（一次性 `Timer`，進 `Buffering` 開、離開取消）：第一次重解析，同一首第二次跳過；
   - 一首正常播放 10 秒重試計數歸零，以位置前進累計，不開計時器；
   - 跳過的去處：`queue` 往下一首；`temporary` 回到佇列（PR 10 已有這條路徑，接上即可）；
   - 連續跳過達佇列長度或 10 首就停在 `Failed` 並提示一次。
2. **離線**（design §5.3）：狀態不是 `online` 而目前這首失敗 → 停在這首等網路：狀態 `Retrying(delay: null)`，播放列顯示「等待網路連線」；不計入重試次數、不算跳過；回到 `online` 時立刻從原位置重試；等網路期間不跳任何提示。
3. **型別**：`Retrying.delay` 可空；`Unavailable.reason` 可空；ADR 0013 加一行更正（design §11 若有列，照列的文字）。
4. **`StreamResult.previewOnly`**（插件 API v1 的可選輸出，`hostApiVersion` 不變）：DTO、`fmp-plugin.d.ts`、`sourceDtoShapes` 等該同步的地方；測試插件加一個回傳 `previewOnly: true` 的關鍵字。
5. **試聽**：「跳過試聽片段」開（預設）→ 跳過並提示；關 → `PlayAsPreview`，播放並在播放列標「試聽」。設定頁「播放」組加一列（Notifier 加 setter；表欄位已存在）。
6. **`events`**：加 `TrackSkipped(error)`、`PlaybackStopped(error)`、`PreviewPlaying`；外殼的 listener（PR 10 已有，處理 `QueueFull`）轉成 `Toaster`；M1 的「停在 `Failed` 時提示一次」併進同一個 listener。提示文字依錯誤類型給具體原因（ADR 0013 的呈現表、ADR 0023），不再是 `Unsupported` 的通用文字。去重交給 `Toaster` 的 5 秒同類同音源。
7. **播放列標示**：「重試中」「等待網路連線」「試聽」。版面照 ADR 0024 與現有播放列（compact、medium、expanded 三段都要能看到狀態或至少不溢出）。
8. **測試插件**：要能在不連外網的情況下，實機重播驗證「試聽」與「等待網路」。`fail` 關鍵字已有（搜尋失敗）；若現有能力不足以觸發播放中的 `NetworkError`／`WaitForNetwork`，補一個關鍵字或說明實機要怎麼造（例如解析時丟 `NetworkError`，再讓網路狀態變成非 `online`）。不得連外網。
9. 文件：`app/AGENTS.md` § 播放（恢復表、離線、事件）、§ 設定、§ 介面；playback／errors／ui／settings spec；每條寫閘門，沒有閘門的寫明。

## 不做

- 本機檔在離線時可播（M6）；`mix`、`live`（M3）。
- 輸出裝置失敗的 `OutputDeviceFailed`（PR 13）。
- 播放頁的「試聽」標示（PR 18a，播放頁 B 還沒有）。

## 驗收

- [ ] 測試（ADR 0018 §如何確認的 `RecoveryPolicy` 部分）：
  - 每類錯誤的處理（表的每一列至少一例）；
  - 離線暫停計數、恢復後立刻重試；離線期間沒有提示；
  - 正常播放 10 秒歸零（以位置前進，沒有計時器）；
  - 緩衝飢餓 15 秒兩次；
  - 連續跳過停止並提示一次；
  - `temporary` 中跳過回到佇列；
  - 403 先重解析；沒有狀態碼的開流失敗也先重解析；404／410 對 `NotFound`；
  - 試聽兩種設定；
  - `app_shell_test.dart` 的提示案例（各事件一例）；設定頁一列；播放列三種標示。
- [ ] 驗證清單全綠（父任務 implement.md「每個 PR 的固定流程」第 5 步）。
- [ ] 實機（主對話做；重播，測試插件）：兩平台 `fail` 類失敗的具體提示；播放中讓網路變成非 `online` → 顯示「等待網路連線」→ 恢復後自動續播；試聽關鍵字在設定開與關各一次。
