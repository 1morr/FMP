# 舊專案現況：Toast 與錯誤呈現

- 查證日：2026-09-28
- 查證方式：實讀 `lib/` 原始碼（`檔案:行號` 皆為本分支 `docs/audit` 的當前行號，非 audit 文件抄錄），
  grep 統計呼叫點，並與 `docs/audit/devtools.md` §2–§4、`docs/audit/errors.md` §4–§5、`docs/audit/ui.md` §5–§7 交叉核對。
  沒有執行 App、沒有跑測試；程式碼推不出來的執行期行為標 **推測**。
- 只描述事實，不含設計建議。

## 1. 三種 toast／錯誤呈現寫法

全 app 沒有第三方 toast 套件（`pubspec.yaml` 與 `lib/` grep `fluttertoast|bot_toast|oktoast|overlay_support` 無結果）。
底層一律 `ScaffoldMessenger`，`SnackBar` 的**建構點只有一個**：`lib/core/services/toast_service.dart:109`。
但在這之上有三條並存的入口路徑：

| # | 寫法 | 代表位置 | 呼叫點數（grep，不含定義檔與註解） |
|---|---|---|---|
| A | `ToastService.failure(context, e, tag:)` — 內部先 `AppLogger.error` 記原文，畫面顯示 `userMessageFor(e)` | `toast_service.dart:188-198`；例：`lib/ui/pages/search/search_page.dart:731`、`lib/ui/pages/settings/bilibili_login_page.dart:188` | 13 |
| B | `ToastService.error(context, t.xxx(error: userMessageFor(e)))` — log 由呼叫端自己另行 `AppLogger.error` | 例：`lib/ui/pages/settings/log_viewer_page.dart:140-146` | `ToastService.error(` 42 總數中含此類 |
| C | 背景服務走實例 stream：`_toastService.showError(...)` → broadcast stream → 只有 `AppShell` `ref.listen` | `lib/services/audio/audio_provider.dart:641,1604,1993,2685`；`lib/ui/app_shell.dart:44-49` | `showError` 12、`showInfo` 6、`showWarning` 5、`showSuccess` 2 |

靜態方法呼叫點總數（grep `lib/`）：`success` 60、`error` 42、`show` 26、`warning` 14、`failure` 13、`showWithAction` 6。
使用 `ToastService` 的檔案 45 個。`.trellis/spec/ui/widgets.md`（Reuse 表「Toast」列）明文接受 A 與 B 兩種：
「`ToastService.failure(...)`，或 a plain toast whose template is fed `userMessageFor(e)`」——所以 B 不是違規。
`toast_service.dart:182-185` 自己的註解卻宣稱 `failure` 是「UI 顯示例外的唯一入口」，與實際不符。

**外觀／位置／時長**（由 `buildSnackBar` 統一決定，`toast_service.dart:93-135`）：

- `behavior: SnackBarBehavior.floating`（`:110`）——不是貼底 `fixed`。
- 依類型上色：info=primary、success=`Colors.green`、warning=`Colors.orange`、error=`colorScheme.error`；
  content 是 `Row(icon + Expanded(Text))`，字與圖示寫死白色（`:112-131`）。
- 時長：error／warning／帶 action 用 `ToastDurations.long`（3000ms），其餘 `ToastDurations.short`（1500ms）
  （`:126-131`；常數 `lib/core/constants/ui_constants.dart:162-170`）。
- `persist: action != null && MediaQuery.accessibleNavigationOf(context)`（`:134`）——只有讀屏模式才讓帶按鈕的 toast 不自動消失。
- 動作按鈕：`showWithAction` 帶單一 `SnackBarAction`（`:219-235`），6 個呼叫點全在
  `lib/ui/pages/library/playlist_detail_page.dart:981,988,1065,1081,1102,1111`。
- **不排隊、直接覆蓋**：`:238-243` `showSnackBarNow` 每次都先 `messenger.clearSnackBars()` 再
  `removeCurrentSnackBar()` 才 `showSnackBar`；因此連續錯誤只看到最後一則。
  `:249-257` 的 `showSnackBarWithMessenger`（給「pop 對話框前先擷取 messenger」用）語意相同。
- 無 `showCloseIcon`、無 `width`／`margin` 客製（皆為框架預設）。

## 2. 成功／資訊類提示

- 語意上沒有專屬元件，就是 `ToastType.info/success` 的同一顆 SnackBar。
- 例：「已加入佇列／下一首」`lib/ui/handlers/track_action_coordinator.dart:30,35`；
  清空／刪除播放歷史 `lib/ui/pages/history/play_history_page.dart:919,957,992`；
  電台刪除 `lib/ui/pages/home/home_page.dart:632`。
- 「已複製」類：`lib/ui/pages/settings/log_viewer_page.dart:294`（`t.logViewer.copied`）、`:404`（`copiedToClipboard`）。
- 成功／警告語意色不是 `ColorScheme` 給的，是 `ToastService.successColor` / `warningColor`
  （`toast_service.dart:42-43`，`Colors.green` / `Colors.orange`），spec 明說要重用這兩個常數。

## 3. 背景錯誤的監聽點與看不到的路由

- **音樂播放錯誤**：`AudioController` 經 `_toastService`（`audio_provider.dart:75,185`）推 stream；
  全 app 唯一監聽 `toastStreamProvider` 的地方是 `lib/ui/app_shell.dart:44`（`ref.listen`），
  在 `:20-29` 轉成 SnackBar。`AppShell` 由 `ShellRoute` 包住（`lib/ui/router.dart:129-131`）。
- **電台錯誤**：不走 stream，改由頁面級 `ref.listen<RadioState>(radioControllerProvider, ...)`，
  且各寫一份：`lib/ui/pages/home/home_page.dart:126`、`lib/ui/pages/radio/radio_page.dart:32`。
  使用者停在音樂庫／搜尋／設定等頁時，電台錯誤不跳 toast（那兩頁的 listen 不存在）。
- **蓋在 shell 之上的全螢幕路由**：`/player`、`/radio-player` 掛 `parentNavigatorKey: rootNavigatorKey`
  （`lib/ui/router.dart:292-306`），是 `ShellRoute` 之外的根層 route。
  repo 自己的 static rule 註解斷言「Riverpod 3 會暫停被不透明路由蓋住的 consumer 的 `ref.watch` 訂閱」
  （`test/providers/static_rules/riverpod3_static_rule_test.dart:29-35`），且 `FMPApp.build` 之所以把
  副作用 provider 錨在 `MaterialApp` 之上就是為了不被暫停。
  因此 **推測**：使用者在全螢幕播放頁時，AppShell 的 `ref.listen` 可能被暫停，或即使不暫停，
  SnackBar 也畫在被蓋住的 shell Scaffold 上——兩種情形都看不到。audit G9 原文即為此事，
  標「（推測）」，本次同樣**未實測**。
- **對話框**：`MaterialApp.router`（`lib/app.dart:133`）**沒有設 `scaffoldMessengerKey`**，
  由框架自動建立的根 ScaffoldMessenger 承接。`ScaffoldMessenger` 的 SnackBar 畫在註冊的 Scaffold 內，
  對話框（`showDialog`）是 `Overlay` 上的 route；repo 另備 `showSnackBarWithMessenger`
  （`toast_service.dart:249-257`），正是為了在 pop 對話框前先擷取 messenger 避免 context 失效。
- **Windows 桌面歌詞子視窗**：走 `desktop_multi_window` 獨立 engine（`lib/ui/windows/lyrics_window.dart:28-30`
  `lyricsWindowMain` 是 `@pragma('vm:entry-point')`），自己一個 `MaterialApp`（`:159`）與 `Scaffold`（`:681`），
  不共用主視窗的 ScaffoldMessenger；該檔 grep 不到 `ToastService`／`SnackBar`／`ScaffoldMessenger` 使用。
- **Android 背景**：播放由 `audio_service` 的 `AudioService`（`android/app/src/main/AndroidManifest.xml:63-72`）
  以 foreground media notification 呈現；`AndroidManifest.xml` 沒有 `SYSTEM_ALERT_WINDOW`，
  沒有懸浮窗。背景播放時 Flutter UI 不在前景，in-app toast 無處可顯示——這一段**推測**，未實測。

## 4. 錯誤詳細與 log 檢視（開發者模式現況）

- **開發者模式對 toast 沒有任何影響**：`developerOptionsProvider` 只在
  `lib/ui/pages/settings/widgets/settings_about.dart:7,94` 被讀（版本列連點 7 次解鎖），
  `toast_service.dart` 與 `app_shell.dart` grep 不到 `developerOptionsProvider`。**目前沒有**「錯誤 toast 旁附『詳細』按鈕」這種東西。
- **log 檢視**在 `lib/ui/pages/settings/log_viewer_page.dart`：開頁複製 `AppLogger.logs` 最近 500 筆、
  訂閱 stream 追加、畫面上限 1000 筆；級別篩選（Debug+/Info+/Warning+/只看 Error）＋文字搜尋；
  單筆詳情對話框顯示 error + stack（`:345-415`）；可複製全部、長按單筆複製、匯出落盤檔。
- 開發者模式本身**不持久化**（`lib/providers/settings/developer_options_provider.dart:6-34`，註釋明說不落 `Settings`），
  且 release 版也能解鎖（audit §1.1 已核）。
- `docs/adr/0011` 目標是「錯誤歷史＝統一錯誤型別經 log 門面以 warning/error 寫入，Debug 頁篩選即錯誤歷史」——
  這是**目標**，舊專案的等價物就是上面的 log viewer；它目前沒有限制等級（warning/error）的「錯誤歷史」檢視。

## 5. `user_message.dart` / `failureMessage()` 的角色

- `lib/core/errors/user_message.dart` 是「例外 → 一句翻譯」的映射層：
  `userMessageFor(error)`（`:72-87`）只認 `SourceApiException`、`DioException`、`SocketException`／`HttpException`／
  `TlsException`、`TimeoutException`、`FormatException`、`PathAccessException`；**其他型別一律回 `t.error.unknownError`**。
- `sourceErrorReason`（`:29`）／`_reasonFor`（`:35`）以窮舉 `switch` 把 `SourceErrorKind` 映射到 i18n 句；
  `rateLimited` 回 `message`、`unknown` 回 `message` 或 `unknownError`——即 adapter 的 `message` 會直接上畫面。
- `failureMessage(error, stackTrace, what, {tag})`（`:97-105`）＝ 寫一筆 `AppLogger.error` 後回傳 `userMessageFor(error)`，
  給「provider 的 `state.error` 要直接畫成文字」用（搜尋、詳情、匯入）。
- **文件與程式碼不一致**：`:64-67` 註解宣稱「回傳值裡不會有 Dart 例外的原文」，
  但 adapter 把非預期例外包成 `message: e.toString()`（例 `lib/data/sources/bilibili_source.dart` 多處），
  而 `unknown` kind 直接顯示 message。audit `errors.md` §4.3 #2 已列。
- `AudioController` 限流分支直接把 `e.message` 餵 `showWarning`（`lib/services/audio/audio_provider.dart:1988`），
  繞過 `userMessageFor`。

## 6. 舊專案相關的 static rule 與測試

- 唯一與此相關的靜態規則：`test/ui/static_rules/error_presentation_static_rule_test.dart`，三條：
  1. `lib/ui` 內 async error 分支不得畫 `SizedBox.shrink()`（要 `ErrorDisplay(compact: true)`）。
  2. 掃**整個 `lib/`**：`t.x(...error: ...)` 模板內不得塞 `e.toString()` 或 `$e` 插值。
  3. `lib/ui` 內 `ToastService.*`／`ErrorDisplay.*` 的引數不得出現 `e.toString()` / `state.error.toString()` 等原文。
- **沒有**「禁止直接 `SnackBar(`」的規則，也沒有「禁止繞過 ToastService」的規則；
  現況之所以沒人繞過，是因為全 app 只有一處 `SnackBar(` 建構（`toast_service.dart:109`），
  不是因為有閘門（audit §2.1「繞過的地方：0 處」是事實描述，非規則）。
- 第 1、3 條的檔案集合由 `_uiDartFiles()`（`error_presentation_static_rule_test.dart:176`）決定，只掃 `lib/ui`；
  第 2 條例外，掃整個 `lib/`（`:35-57`）。
  所以 `lib/services/audio/audio_provider.dart:1988` 的 `e.message` 漏網（audit 清單 #6 已列）。
- Trellis spec `.trellis/spec/ui/widgets.md` 的 Gates 段列出上述 rule；Reuse 表列 Toast 入口並要求重用 `successColor`／`warningColor`。

## 7. 與本任務相關的 audit 出處

- `docs/audit/devtools.md` §2.1（呈現入口一覽、呼叫次數）、§2.3（三種寫法、原文外洩、背景兩種送達、全螢幕推測、
  互相覆蓋）、§2.4（ErrorDisplay／NetworkStatusBanner／StartupFailureApp）、§3.4（log viewer）、§4（流向圖）、§5（不一致清單 #5–#11）。
- `docs/audit/errors.md` §4.1（各功能失敗時看到什麼）、§4.2（catch 統計 511 個）、§4.3 #1（翻譯好的錯誤被壓成「發生錯誤」）、#2（原文上畫面）。
- `docs/audit/ui.md` §5.1–5.2（語意現況：`Semantics(` 12 處、無 `semanticLabel`；播放頁大播放鍵無名稱）、
  §6.3（跨平台一致性）、§7（問題總表）、§8（建議放進決策清單的項目）。
- `docs/audit/questions.md` G9（`:305`）即本項目的 audit 條目：三種寫法＋背景只有 AppShell 在聽＋全螢幕看不到（推測）。
