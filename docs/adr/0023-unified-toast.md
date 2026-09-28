# 0023 — 統一 Toast：單一入口、Material 單條且新的取代舊的、包住 Navigator 的宿主、遮蔽後的詳細頁與回報

- 狀態：已採納
- 日期：2026-09-28
- 影響範圍：`app/` 的 toast 模組（`Toaster`、`ToastHost`）、錯誤詳細頁與 `ErrorReport`、外殼版面的底部位移、子視窗與懸浮窗的錯誤轉送、`fmp_lints`

## 背景

舊專案（`.trellis/tasks/archive/2026-09/09-28-design-toast/research/current-state.md`，已以程式碼核對）：

- SnackBar 只在 `toast_service.dart:109` 建立，但入口有三條並存：`failure(context, e)`、`error(context, 文字)`、背景 stream。
  靜態呼叫共 161 處、散在 45 個檔。
- 送出前先清掉目前的提示（`:240-241`），所以新的蓋掉舊的；成功 1.5 秒、錯誤 3 秒。
- 背景 stream 只有 `app_shell.dart:44` 在聽；`app.dart` 沒設 `scaffoldMessengerKey`。全螢幕播放頁掛在根 Navigator 上，是否看得到提示未實測（G9）。
- 開發者模式對提示沒有任何影響，沒有「詳細」。
- 非預期例外會以 `e.toString()` 上畫面（`audio_provider.dart:1988`）；static-rule 只掃 `lib/ui`，所以漏掉。

已定的邊界：
- ADR 0011：錯誤歷史、遮蔽函式；
- ADR 0013：呈現表、同類提示短時間只一次、背景工作不跳提示、開發者模式附「詳細」；
- parent prd 第 3 項：單一入口；詳細可看錯誤類型、音源、請求摘要、stack trace 並複製。

## 考慮過的選項

- **三條入口並存（舊版）**：否決，G9 的來源。
- **桌面右下角疊卡（Fluent 2）**：否決（擁有者 2026-09-28 選擇 Material 單條）。要做兩套元件並自做無障礙，連續操作時卡片會一直堆疊。
- **依序排隊（Material 預設）**：否決。連續操作時回饋會延遲好幾秒。
- **`fluttertoast`**：否決，沒有 Windows 實作。
- **`toastification`**：否決，沒有動作參數、沒有 live region。
- **把報告內容放進 GitHub 網址**：否決。網址會被瀏覽器記錄，也有長度上限。
- **一般使用者完全看不到回報**：否決（擁有者選擇預期外的錯誤可回報）。
- **子視窗各自顯示提示**：否決。多個 engine 各自一份提示狀態，去重會失效。

## 決定

1. **單一入口 `Toaster`**（provider 注入，不需 `BuildContext`）：
   - `success`、`info`、`warning` 收 i18n 字串；
   - `error(AppError, {operation})` 只收 `AppError`，由 ADR 0013 的對應表轉成訊息；
   - 各自最多一個動作。
   
   背景工作不呼叫它，只更新對應畫面的狀態。錯誤不論是否顯示提示，都經 log 門面寫入錯誤歷史（ADR 0011）。
2. **外觀**：Material `SnackBar`，`floating`，四種語意色加圖示。
   - 位置：
     - 手機：迷你播放列與底部導覽列之上；
     - 桌面：播放列之上置中，最寬 560px；
     - 全螢幕頁：貼底部安全區。
     
     外殼版面發佈「底部被佔用的高度」，由宿主算邊距。
   - 一次一則，新的立刻取代目前的。
   - 時長：成功與資訊 4 秒，錯誤與警告 6 秒。帶動作的也照此自動消失；系統開啟無障礙導覽時才停留到手動關閉。
   - 去重：同類別＋同音源（非錯誤為同一訊息）5 秒內只顯示一次，即 ADR 0013 的「短時間」。
3. **層級（G9）**：
   - `ToastHost` 放在 `MaterialApp.builder`，以一個 `ScaffoldMessenger` 與透明 `Scaffold` 包住 Navigator，所以全螢幕頁、對話框、底部面板之上都看得到。
   - 桌面歌詞子視窗與 Android 懸浮窗不顯示提示，錯誤以型別化訊息（ADR 0021）轉給主視窗的 `Toaster`。
   - App 在背景時不顯示、不發系統通知，錯誤仍進錯誤歷史。
4. **詳細頁與回報**：
   - 誰看得到：開發者模式下每則錯誤提示附「詳細」；一般使用者只有 `Unsupported`、`UnexpectedError` 附「回報」，開同一頁。
   - `ErrorReport` 在錯誤發生時組裝一次並經 ADR 0011 的遮蔽函式，顯示、複製、回報都用這一份。內容：
     - 錯誤類型與原因、音源（插件 id 與版本）、使用者動作；
     - 請求摘要（方法、已遮蔽網址、狀態碼、耗時）、stack trace；
     - App 版本與 flavor、系統與版本、ISO 8601 時間。
   - 詳細頁文字可選取，按鈕：
     - 「複製」：Markdown 格式；
     - 「在 GitHub 回報」：先複製，再開新增 issue 頁（bug 範本），內容不放進網址。第一次使用提醒 repo 公開、送出前檢查。
   - Debug 頁的錯誤歷史用同一個詳細頁（ADR 0025）。
5. **無障礙**：
   - 使用 `SnackBar` 內建的 live region：朗讀但不搶焦點。
   - 單獨朗讀用 `SemanticsService.sendAnnouncement(View.of(context), …)`，不用已棄用的 `announce`（與多視窗不相容）。

採用的慣例：
- Material 3 Snackbar 規範：一次一則、單一動作、4–10 秒、避開底部導覽、live region；
- Finamp、Immich、LocalSend 以一個 service 包 SnackBar；
- Spotube 讓提示層浮在對話框之上；
- Finamp 以錯誤類型為鍵去重；
- NewPipe `ErrorActivity` 的詳細頁、「複製」與「回報到 GitHub」。

## 後果

- 好的：
  - 一個入口、一種外觀；
  - 在所有畫面都看得到提示；
  - 例外原文不會上畫面；
  - 開發者能看詳細並複製；
  - 一般使用者能回報 bug，內容先遮蔽。
- 壞的：
  - 新的會取代舊的，連續出現時較早的一則可能來不及讀，要靠錯誤歷史補看；
  - 一般使用者在回報頁會看到技術內容；
  - 外殼要負責發佈底部位移。
- 之後要注意：repo 目前沒有 issue 範本，落地時新增 `.github/ISSUE_TEMPLATE/bug_report.yml`；系統層通知不在本 ADR 範圍。

## 如何確認

- lint `fmp_toast_entry`（加入 ADR 0015 的 `fmp_lints`）：`SnackBar(`、`ScaffoldMessenger.of`、`showSnackBar`、`clearSnackBars` 只准在 toast 模組，依 ADR 0015 寫雙向變異測試。
  它取代舊 `error_presentation_static_rule_test.dart` 中「UI 不得自組錯誤文字」的部分。`error(AppError)` 的型別擋掉以字串傳例外原文。
- 單元測試：
  - 去重視窗、取代、時長；
  - 開發者模式與一般使用者的按鈕；
  - `ErrorReport` 經遮蔽（假 cookie、token、簽名網址不出現在 Markdown）；
  - GitHub 網址不含報告內容。
- widget 測試：全螢幕路由與對話框開啟時送出提示，提示可見；底部位移依外殼發佈的高度。
- 第一個里程碑實測：提示在全螢幕頁與對話框之上可見（目前依原始碼推得）；Windows Narrator 下提示不凍結無障礙樹（上游 #190357 類問題）。
