# 設計：統一 Toast（階段二第 3 項）

## 目標

為 `app/` 定下單一的提示入口、各裝置的外觀與位置、排隊與去重、開發者模式的「詳細」、在所有畫面上都看得到的層級，以及無障礙。產出 ADR 0023。技術設計見 `design.md`，執行步驟見 `implement.md`。

依據：parent `prd.md` 階段二第 3 項；`docs/audit/questions.md` G9；ADR 0011（錯誤歷史＝統一錯誤經 log 門面寫入、Debug 頁篩選；所有展示請求內容處經同一遮蔽函式）、
ADR 0013（錯誤呈現表；同類別＋同音源短時間只提示一次；背景工作不跳 toast、只在對應畫面顯示狀態；開發者模式附「詳細」）、ADR 0021（歌詞子視窗與 Android 懸浮窗是獨立 engine）。

## 現況（`research/current-state.md`，關鍵項已以程式碼核對）

- SnackBar 只在 `lib/core/services/toast_service.dart:109` 建立，外觀統一：`floating`、四色、錯誤／警告／帶動作 3 秒、其他 1.5 秒、沒有關閉鈕。
- **入口有三條並存**：`ToastService.failure(context, e)`、`ToastService.error(context, 翻譯(userMessageFor(e)))`、背景 stream（`showError`／`showInfo`／`showWarning`／`showSuccess`）；
  靜態呼叫共 161 處、散在 45 個檔（`success` 60、`error` 42、`show` 26、`warning` 14、`failure` 13、`showWithAction` 6）。
- **不排隊、直接覆蓋**：送出前先 `clearSnackBars()`＋`removeCurrentSnackBar()`（`toast_service.dart:240-241`）。
- 背景 stream 只有 `app_shell.dart:44` 在聽；電台錯誤另由首頁與電台頁各自監聽，停在其他頁看不到。`app.dart` 沒設 `scaffoldMessengerKey`；
  全螢幕播放頁與電台播放頁掛在根 Navigator 上（`router.dart:292-306`），是否看得到提示未實測（G9 的推測）。歌詞子視窗有自己的 `MaterialApp`，完全收不到。
- **開發者模式對提示沒有任何影響**，沒有「詳細」按鈕；最接近的是 log 檢視頁（500 筆、級別篩選、單筆 stack、匯出）。
- `user_message.dart` 宣稱不含例外原文，但非預期例外會以 `e.toString()` 上畫面；`audio_provider.dart:1988` 直接把 `e.message` 餵給提示。
  static-rule `error_presentation_static_rule_test.dart` 有兩條只掃 `lib/ui`，所以漏掉；沒有禁止直接建 `SnackBar(` 的規則。

## 研究結論（`research/prior-art.md`、`research/packages-and-platform.md`）

- **Material 3**：一次只顯示一條、最多一個動作、無動作 4–10 秒、底部並避開 FAB 與導覽列、大螢幕維持 40–60 字行長、polite live region 且不搶焦點。M3 的 snackbar 頁沒有「錯誤」用法，嚴重或持續的錯誤改用對話框或就地狀態。
- **Fluent 2**：in-app toast 用於「有用但不關鍵」的訊息，無動作 7 秒、最多疊 4 條；關鍵訊息用 Dialog、欄位錯誤或 Message bar。Windows 系統層通知是另一回事（出現在 App 視窗外）。
- **Apple HIG**：沒有 toast；錯誤用 Alert 或就地狀態。
- **Flutter App**：Finamp、Immich、LocalSend、AppFlowy 用 Material SnackBar 包一層 service；Spotube 用 `shadcn_flutter` 的 toast，並在對話框內另包一層讓提示浮在對話框之上；
  Namida、Harmonoid 自製或原生。沒有一個用 `bot_toast`、`another_flushbar`。Finamp 以錯誤類型鍵（不含網址）去重。
- **錯誤詳細的慣例**：NewPipe 的提示動作「Report」開詳情頁（動作、請求、服務、版本、系統、時間、可選取的 stack），提供「複製」與「回報到 GitHub」，送出前先顯示隱私說明。
  共同模式：提示本身不能複製，詳細另開頁面或對話框。
- **Flutter 行為**：`MaterialApp` 內建的根 `ScaffoldMessenger` 包住 Navigator，但 SnackBar 由 Scaffold 自己畫，後推的全螢幕頁或對話框可能蓋住它（依原始碼推測，待實測）；
  `showSnackBar` 本身會排隊；3.38 起帶動作的 SnackBar 不自動消失；內建 `Semantics(liveRegion: true)`。
  `SemanticsService.announce` 已棄用（與多視窗不相容），改用 `sendAnnouncement(view, …)`。
- **套件**：`fluttertoast` 沒有 Windows 實作；`toastification` 六平台、維護中，但沒有動作參數、沒有 live region。
- **Windows 無障礙樹**：上游有 #190357（推送的頁面內 Slider 永久凍結無障礙樹，open）等；是否波及 overlay 類提示查不到，需實測。

## 已確定的方向

- 單一入口；開發者模式下錯誤提示附「詳細」，可看錯誤類型、音源、請求摘要、stack trace 並複製；所有錯誤同時進入錯誤歷史（ADR 0011）；「詳細」與複製內容經同一遮蔽函式。
- 呈現規則照 ADR 0013 的表：背景工作不跳提示；同類別＋同音源短時間只提示一次；訊息一律 i18n，不顯示例外原文。

## 已決定

1. **Material 單條橫條、新的取代舊的（2026-09-28，按建議）**：手機在迷你播放列上方；桌面在播放列上方置中、最寬約 560px；一次一則，新的立刻取代。
   錯誤不因被取代而遺失（錯誤歷史）；同類別＋同音源短時間只提示一次（ADR 0013）。否決：桌面右下角疊卡（兩套元件、自做無障礙）、依序排隊（連續操作回饋延遲）。

## 待決定

1. 「詳細」提供哪些動作，以及一般使用者遇到非預期錯誤時能否回報。

## 不在範圍

- 系統層通知（App 視窗外）；Debug 頁本身的版面（第 4 項）。

## 驗收條件

- [ ] ADR 0023 記錄：單一入口與 API、外觀與位置、排隊與去重、層級（全螢幕頁、對話框、子視窗）、開發者模式詳細、無障礙、閘門。
- [ ] G9 對到決定。
- [ ] `phase2-plan.md` §3 第 3 項標 ✅ 與 ADR 編號。
