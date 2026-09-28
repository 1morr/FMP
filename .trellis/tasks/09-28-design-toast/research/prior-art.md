# Prior art：統一提示 / Toast / 錯誤呈現

- **查證日**：2026-09-28
- **查證方式**：
  - 設計規範：直接讀官方規範頁，逐字引用，網址附於各條。M3 Snackbar、Fluent 2 Toast / Message bar、Apple HIG Alerts 由本 agent 於 2026-09-28 親自以 `tavily-extract`（`extract_depth: advanced`，因 `m3.material.io` 與 `fluent2.microsoft.design` 為 JS 渲染，`WebFetch` 只取得到標題）與 `WebFetch`（`developer.apple.com`）重新抓取核對；其餘條目由子代理抓取後附 URL。
  - Flutter 開源 App：以 `--depth 1` clone 或 `gh api` + `raw.githubusercontent.com` 讀原始碼，`grep` 定位。所有 repo 的 commit SHA 已用 `gh api repos/<owner>/<repo>/commits/<sha>` 驗證存在（見下表）；行號以該 SHA 為準。
  - 所有引用行號本 agent 已逐一開原始檔核對（少數與子代理原報告不同處已修正，見「與子代理報告的差異」）。
  - **本檔不含任何 FMP 內部程式碼引用**；FMP 現狀見同目錄 `current-state.md`。
- **限制**：未執行任何 App，未打任何音樂平台 API。開源 App 的行為描述一律為「讀原始碼得到的靜態事實」，不是實機觀察；凡屬推論一律標「推測」。

## SHA 對照表（2026-09-28 驗證）

| App | repo | default branch | 本檔使用 commit |
|---|---|---|---|
| Spotube | `krtirtho/spotube` | `master` | `69a310c78f5ceaf4eab7dfee98f187d38211c9ba` |
| Namida | `namidaco/namida` | `main` | `acb1e1622600440cc793f389f497e6771c732c5e` |
| LocalSend | `localsend/localsend` | `main` | `6f6cd3ee496903e2206c51ffa3a13a5d10bc340b` |
| AppFlowy | `AppFlowy-IO/AppFlowy` | `main` | `5cf3a365dec0d59f64bad1ee4bb1050471a39b93` |
| Immich (mobile) | `immich-app/immich` | `main` | `970c496e55bdf261e7c1247bb282d3a7204e40f2` |
| Finamp | `jmshrv/finamp` | **`redesign`** | `0aae9d5ed530ffdf3d62ab12dab4f475a67687dc` |
| Harmonoid | `alexmercerind/harmonoid` | `master` | `2b021f7b0b5dbcbe027aec010580977a2939a28d` |
| NewPipe | `TeamNewPipe/NewPipe` | `dev` | `7e5df38aad4b2c035332b3f71aee3064d4fdaae4` |

註：`jmshrv/finamp` 與 `UnicornsOnLSD/finamp` 是同一個 repo（redirect），default branch 是 `redesign`（改寫中的分支），不是 `main`。NewPipe 是 Android/Kotlin 專案，列在此處是因為它是「錯誤詳情頁」的參考樣本。

---

## 1. Material 3 Snackbar

### 定義與定位
https://m3.material.io/components/snackbar/overview

- "Snackbars show short updates about app processes at the bottom of the screen"
- "Snackbars shouldn't interrupt the user's experience" / "Usually appear at the bottom of the UI" / "Can disappear on their own or remain on screen until the user takes action"

### 何時用（vs dialog）
https://m3.material.io/components/snackbar/guidelines

- "Snackbars inform users of a process that an app has performed or will perform. They appear temporarily, towards the bottom of the screen."
- "When to use snackbars: Snackbars communicate messages that are minimally interruptive and don't require user action."
- 官方對照（同頁）：Snackbar = "Low priority" / "Optional: Snackbars disappear automatically"；Dialog = "High priority" / "Required: Dialogs block app usage until the user takes a dialog action…"
- "Dialogs are also designed to show important messages. Choose the right component based on the importance of the message. This component messaging strategy can help avoid overusing snackbars."

### 動作按鈕數量
- "A snackbar can contain a single action. 'Dismiss' or 'cancel' actions are optional."
- "Snackbars can display a single text button. Snackbars shouldn't be the only way to access a core use case, to make an app usable."
- Caution："A dismiss action is unnecessary, as snackbar disappears on their own by default"
- Caution："Avoid adding icons to snackbars. If your message needs an icon, consider using a different component such as a dialog."

### 時長
- "Snackbars without actions can auto-dismiss after 4–10 seconds, depending on platform. Avoid using auto-dismissing snackbars on web unless there's also inline feedback."
- "Snackbars with actions should remain on the screen until the user takes an action on the snackbar, or dismisses it."
- https://m3.material.io/components/snackbar/accessibility ："Snackbars with actions shouldn't auto-dismiss."；"common acceptable durations are 4–10 seconds"

### 一次只顯示一條
- "Only one snackbar may be displayed at a time."
- "Consecutive snackbars must appear one at a time."
- "However, a snackbar with updated information can immediately replace an outdated snackbar."
- Don't："Don't stack snackbars on top of one another"

### 位置
- "Snackbars should be placed at the bottom of a UI, in front of the main content. In some cases, snackbars can be nudged upwards to avoid overlapping with other UI elements near the bottom, such as FABs or docked toolbars."
- "Snackbars should appear above FABs."
- "Avoid placing a snackbar in front of frequently used touch targets or navigation."
- "Snackbars can span the entire width of the screen only when a UI does not use persistent navigation components like app bars or navigation bars."

### 大螢幕
- "On medium and expanded breakpoints, like tablet and desktop, snackbars should scale horizontally to accommodate longer text strings, keeping in mind that the ideal line length for text is typically between 40-60 characters."
- "Whenever possible, snackbars on medium and large displays should aim for a single line of text with an optional button."
- "In wider layouts, snackbars can be left-aligned or center-aligned if they are consistently placed on the same spot at the bottom of the screen."
- Compact breakpoint："snackbars should expand vertically from 48dp to 64dp… maintaining a fixed distance from the leading, trailing, and bottom edges"

### 錯誤
**M3 snackbar 頁面本身沒有「error」用法條目**。相鄰規範說的是：
- M3 Dialogs（https://m3.material.io/components/dialogs/guidelines ）："General errors such as network issues preventing saving or submitting should appear in a basic dialog when the confirming action fails."；"Errors about the dialog fields should always appear inline where they occur."
- M1（舊版）Errors pattern（https://m1.material.io/patterns/errors.html ）："The snackbar contains app feedback about a peripheral error. **Snackbars are transient. Don't use them for critical, persistent, or bulk errors.**"

### 無障礙
https://m3.material.io/components/snackbar/accessibility

- "When a snackbar appears, announce the message but don't move focus."
- "On Android and web, use a live region with a polite (queued) announcement instead of an assertive announcement."

---

## 2. Microsoft Fluent 2 / Windows

### Fluent 2 Toast（in-app 訊息）
https://fluent2.microsoft.design/components/web/react/core/toast/usage

- "A toast communicates the status of an action someone is trying to take or that something happened elsewhere in the app. **Toasts are temporary surfaces. Use them for information that's useful and relevant, but not critical.**"
- "**For critical messages, try a modal Dialog, Field error, or Message bar instead.**"
- "If there is no action to take, toast will time out after seven seconds."
- "Use conditional dismissal for toasts that should persist until a condition is met"（例：progress toast 完成才消失）
- "**Don't use toasts for necessary actions.** If you need the encourage people to take an action before moving forward, try a more forceful surface like a message bar or a dialog."
- "Include the Close button to allow people to expressly dismiss toasts **only if they can find that information again elsewhere, like in a notification center.**"
- "Toasts should always appear in a consistent location within your app… This is usually the **top-right or bottom-right**."
- "Don't show more than four toasts in a toaster and keep 16 pixels of space between them."
- "All feedback states except info have an 'assertive' aria-live… don't overload people with too many assertive toasts."
- 鍵盤：people who navigate via mouse 可以 hover 暫停計時；"toasts that don't include actions won't receive keyboard focus for people who navigate primarily by keyboard."

### Fluent 2 Message bar（= Fluent 1 的 InfoBar）
https://fluent2.microsoft.design/components/web/react/core/messagebar/usage

- "A message bar communicates important information about the state of the entire product or the surface where it appears, such as a page, drawer, dialog, or card."
- "If the message is intended to prevent a destructive action, try a dialog instead. **If the message is time-sensitive, but relates to an activity or status from a different location, try a toast notification instead.**"

### Windows InfoBar（WinUI 3）
https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar

- "The InfoBar control is for displaying app-wide status messages to users that are highly visible yet non-intrusive."
- "**Use an InfoBar control when a user should be informed of, acknowledge, or take action on a changed application state. By default the notification will remain in the content area until closed by the user but will not necessarily break user flow.**"
- "An InfoBar will take up space in your layout and behave like any other child elements. It will not cover up other content or float on top of it."
- "**Do not use an InfoBar control to confirm or respond directly to a user action that doesn't change the state of the app, for time-sensitive alerts, or for non-essential messages.**"
- "For scenarios where a notification is a transient teaching moment, a TeachingTip is a better option."

### Windows Toast = OS 層（Windows App SDK / WinRT），不是 in-app widget
https://learn.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/toast-notifications-overview

- "**App notifications are UI popups that appear outside of your app's window**, delivering timely information or actions to the user."
- API 名稱：新的 `AppNotificationManager`（`Microsoft.Windows.AppNotifications`）；舊 UWP 為 `ToastNotificationManager`（`Windows.UI.Notifications`）。https://learn.microsoft.com/en-us/windows/apps/develop/notifications/
- 進 Notification Center：`ToastNotification.ExpirationTime` = "the time after which a toast notification should not be displayed"；`ExpiresOnReboot` = "Indicates whether the toast notification will remain in the Notification Center after a reboot." https://learn.microsoft.com/en-us/uwp/api/windows.ui.notifications.toastnotification
- 特定情境才會一直留在畫面上："In the reminder scenario, the notification will stay on screen until the user dismisses it or takes action."；"Incoming call notifications… stay on the user's screen till dismissed." https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-content

> 註：Windows 11 系統設定已改稱「Action Center」字樣（或沿用「Notification Center」），上列 API 文件仍用後者。官方文件目前無一致命名，兩者指同一處。

---

## 3. Apple HIG

### HIG 沒有 toast 這個概念
- 以匿名視窗讀 https://developer.apple.com/design/human-interface-guidelines 下的 Components 全部子分類（Content / Layout and organization / Menus and actions / Navigation and search / Presentation / Selection and input / Status / System experiences），**未出現「toast」字樣**（查證日 2026-09-28）。
- HIG 對應的角色分給 Alerts（modal 中斷）、Notifications（OS 層）、Progress indicators 與 inline status。

### Alerts（modal 中斷）
https://developer.apple.com/design/human-interface-guidelines/alerts

- "An alert gives people critical information they need right away."
- "**Use alerts sparingly. Alerts give people important information, but they interrupt the current task to do so.** Encourage people to pay attention to your alerts by making certain that each one offers only essential information and useful actions."
- "**Avoid using an alert merely to provide information.** People don't appreciate an interruption from an alert that's informative, but not actionable. If you need to provide only information, prefer finding an alternative way to communicate it within the relevant context."
- "Avoid displaying alerts for common, undoable actions, even when they're destructive."
- "Avoid showing an alert when your app starts. …consider alternative ways to let people know… you could show cached or placeholder data and a **nonintrusive label** that describes the problem."

### Notifications（OS 層）
https://developer.apple.com/design/human-interface-guidelines/notifications

- "A notification gives people timely, high-value information they can understand at a glance."
- "**Use an alert – not a notification – to display an error message.** People are familiar with both alerts and notifications, so you don't want to cause confusion by using the wrong component."
- "**Handle notifications gracefully when your app is in the foreground.** Your app's notifications don't appear when your app is in the front, but your app still receives the information. In this scenario, present the information in a way that's discoverable but not distracting or invasive, such as incrementing a badge or subtly inserting new data into the current view."

### Feedback（inline status）
https://developer.apple.com/design/human-interface-guidelines/feedback

- "The most effective feedback tends to match the significance of the information to the way it's delivered."
- "**Consider integrating status feedback into your interface.** When status feedback is available near the items it describes, people get important information without having to take action or leave their current context."
- "**Use alerts to deliver critical – and ideally actionable – information.** By design, alerts disrupt the current context, so you need to match the importance of the information to the level of interruption."
- "It's generally best to reserve this type of confirmation for activities that are sufficiently important – because people typically expect their action or task to succeed, **they only need to know when it doesn't**."

### Progress indicators（唯一的「transient」東西）
https://developer.apple.com/design/human-interface-guidelines/progress-indicators

- "All progress indicators are transient, appearing only while an operation is ongoing and disappearing after it completes."
- "When possible, use a determinate progress indicator."

### 三系統一致／不一致（事實陳述）
- iOS/macOS **沒有** in-app transient toast 元件；最接近的「打斷一下」語意交給 OS Notification banner（需使用者同意），app 層被導向 inline status / badge。
- Fluent 2 的「Message bar」對應 Material 的 banner/InfoBar，Windows 端實作是 WinUI `InfoBar`；Fluent 2 的「Toast」是 in-app 訊息，與 Windows OS toast notification **同名但不同物**。Apple 對應物是 OS Notification。
- 三系統一致：**錯誤（critical 資訊）都不建議走 transient toast/snackbar** —— Material 建議 dialog 或 inline，Fluent 2 建議 Dialog / Field error / Message bar，Apple 建議 Alert 或 inline。

---

## 4. Flutter 開源 App 怎麼做統一提示

以下 7 個都讀了原始碼。欄位固定：元件、單一入口 API、桌面/手機位置分流、佇列/去重、錯誤詳情或回報、與 Navigator/全螢幕的關係。

### 4.1 Spotube（`krtirtho/spotube` @ `69a310c`）
- **元件**：第三方元件庫 `shadcn_flutter 0.0.47` 內建的 toast。不用 Material SnackBar，**沒有自建 service 層**。
- **單一入口**：shadcn 的 `showToast(context:, location:, builder:)`，回傳 `ToastOverlay`（可 `.close()`）。Spotube 唯一抽出的 helper 是 `showToastForAction`：
  https://github.com/krtirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/components/track_presentation/presentation_actions.dart#L16-L49
  （`builder:` 內自繪 `SurfaceCard` + 關閉 IconButton，L29-L48）
- **位置**：**呼叫端每次自己指定** `ToastLocation`。多數 `topRight`（同檔 L40）；全域連線狀態用 `bottomCenter`：
  https://github.com/krtirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/modules/root/use_global_subscriptions.dart#L83-L85
  desktop / mobile **沒有分流**，同一套 location。
- **佇列/取代**：由元件庫決定 —— `showToast`（`packages/shadcn_flutter/lib/src/components/overlay/toast.dart#L265`）把 entry `addEntry`（同檔 L296）給最近的 `ToastLayer`；`ToastLayer.maxStackedEntries` 預設 **3**（同檔 L559），超過時舊的被摺疊。是**堆疊**語意，不是取代。`showToast` 內有 `assert(layer != null, 'No ToastLayer found in context')`（同檔 L284）——**必須有 `ToastLayer` 祖先**。
- **錯誤詳情/report**：**無**。（`lib/pages/settings/logs.dart` 只是顯示 log 的頁面，不是從錯誤訊息連過去。）
- **與 Navigator/全螢幕的關係**：根層的 `ToastLayer` 由 `ShadcnApp.router` 提供；**dialog 是獨立 route/overlay，因此 Spotube 在 dialog 內額外包一層 `ToastLayer`**：
  https://github.com/krtirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/modules/playlist/playlist_create_dialog.dart#L293
  （`builder: (context) => const ToastLayer(child: PlaylistCreateDialog())`）——「訊息層要跟著覆蓋它的 overlay 走」的具體範例。

### 4.2 Namida（`namidaco/namida` @ `acb1e162`）
- **元件**：**自製套件** `nampack`（namida 自家的 pub 套件，`lib/snackbar/` 下 5 個檔），是 pub `snackbar` 套件的 fork，類別改名 `NamSnackBar`（`snackbar_controller.dart`、`snackbars_manager.dart`、`snackbar_scope.dart`、`snackbar_widget.dart`、`snackbar_enum.dart`）。非 Material SnackBar、非 `fluttertoast`。
- **單一入口**：全域函式 `snackyy({...})`，回傳 `SnackbarController`：
  https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/controller/navigator_controller.snackbar.dart#L11-L30
  （`part of 'navigator_controller.dart'`，宣告在 L37）
- **位置**：參數 `bool top = true`（同檔 L16）——預設頂部；`top: false` 給底部，例如「再按一次退出」：
  https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/controller/navigator_controller.dart#L705-L717
  `NamSnackBar` 內部以 `SafeArea` 處理 top/bottom。
- **桌面/手機分流**：**有**。同檔 L89-L96 依 `view.physicalSize` 決定寬度；`WindowController.instance?.windowTitleBarHeightIfActive` 在桌面額外加上 **title bar 高度作為 top margin**，避免被自繪視窗標題列蓋住。桌面上概念位置仍是頂部，只是往下推。
- **佇列/合併/取代**：三者都有，樣本中最完整。`_snackbarsStackManager`（同檔 L5）+ `addDurationForGenericSnackbars`（L55）會**替較舊的 snackbar 延長顯示時間**以免被新的蓋掉；`SnackbarMerge` 與 `_mergedSnackbars` map（L7、L31-L36）把同 key 的訊息**合併成同一條並累加次數**（`addCount`）；`isError ??= title == lang.error`（L38）。另有教學式 `dismissHint`（滑動關閉提示，最多顯示 3 次，L9、L47-L50）。
- **錯誤詳情/report**：**無** stack trace 檢視；`SnackbarButton`（L25、L120-L172）是通用 action 按鈕，可放「重試」，但沒有內建 report 機制。
- **與 Navigator/全螢幕的關係**：訊息由 `nampack` 的 manager 插入。Namida 在 `lib/main.dart` 的 `MaterialApp.builder` 裡自己包了一層 `Overlay(initialEntries: [OverlayEntry(...)])`（L685-L730），訊息層在其之上。

### 4.3 LocalSend（`localsend/localsend` @ `6f6cd3e`）
- **元件**：純 Material `SnackBar` + `ScaffoldMessenger.of(context)`。**沒有**任何 toast 套件。
- **單一入口**：`extension SnackbarExt on BuildContext { void showSnackBar(String text) }`，整檔 13 行：
  https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/lib/util/ui/snackbar.dart#L3-L13
- **位置**：沿用預設 `ScaffoldMessenger`（由 `MaterialApp` 建立、**在 Navigator 之上**），所以切換路由時訊息不消失。desktop / mobile **無分流**。
- **佇列/取代**：**取代** —— 先 `scaffold.removeCurrentSnackBar()` 再 `showSnackBar`（同檔 L6-L7）。同時最多 1 條。
- **錯誤詳情/report**：**無**（內容只有一個 `Text`）。全 repo 只有少數檔呼叫它。另有通用 `CopyableText`（`app/lib/widget/copyable_text.dart#L18-L26`）是「點文字複製 → 用 snackbar 確認」的最輕量慣例。

### 4.4 AppFlowy（`AppFlowy-IO/AppFlowy` @ `5cf3a36`）
- **元件**：**兩套並存**。
  1. `fluttertoast` 的 `FToast`（包成 `FlowyMessageToast`）：https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/workspace/presentation/home/toast.dart#L10-L50
  2. Material `SnackBar`（`showSnackBarMessage`，同檔 L52-L78），以及 `flowy_infra_ui` 的 `showSnapBar`：https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/packages/flowy_infra_ui/lib/style_widget/snap_bar.dart#L6-L27 （`clearSnackBars()` L7、`duration: 8000ms` L14、桌機字級 14 / 其餘 12 在 L18-L21）
- **單一入口**：**沒有**單一 service class，是三個自由函式：`showMessageToast`、`showSnackBarMessage`、`showSnapBar`。`FToast` 由 `getIt<FToast>()` 取得，需先 `initToastWithContext(context)`。
- **桌面/手機分流**：**字級分流**（`UniversalPlatform.isDesktop ? 14 : 12`，`toast.dart#L74`；`snap_bar.dart` 用 `Platform.isLinux/Windows/MacOS`）。位置不變（toast 預設 `ToastGravity.BOTTOM`）。
- **佇列/取代**：`showSnapBar` 先 `clearSnackBars()`（`snap_bar.dart#L7`）＝**清空取代**；`showSnackBarMessage` 不清，交給 Flutter 預設**排隊**。`FToast` 自己維護 overlay entry 佇列。兩者的預設時長：SnapBar 8000ms（`snap_bar.dart#L14`）、SnackBar 4s（`toast.dart#L56`）。
- **錯誤詳情/report**：**有，而且是一整頁**。`FlowyErrorPage.error/message/exception`：
  https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/shared/error_page/error_page.dart#L17-L60
  - 可點擊複製的 message，hover tooltip："Click to copy message"（同檔 L112-L119），複製後另彈一條 "Message copied to clipboard"（同檔 L100-L108）
  - 修復提示 `howToFix`（L127）
  - `GitHubRedirectButton`（同檔 L210-L272）：`_gitHubNewBugUri`（L224-L230）組 `https://github.com/AppFlowy-IO/AppFlowy/issues/new?…&template=bug_report.yaml&title=[Bug]+…&context=…`，`_contextString`（L232-L245）把 message 與 stack trace 用 code fence 塞進 `context` 參數
  - `StackTracePreview`（L147 起）帶自己的 copy 按鈕

### 4.5 Immich mobile（`immich-app/immich` @ `970c496`, `mobile/`）
- **元件**：純 Material SnackBar，**但自建 manager**：
  https://github.com/immich-app/immich/blob/970c496e55bdf261e7c1247bb282d3a7204e40f2/mobile/packages/ui/lib/src/snackbar.dart
  全域 `final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>()`（L7）、`class SnackbarManager`（L17）、`const snackbar = SnackbarManager()`（L99 附近）。
- **單一入口**：**兩層**。低階 `snackbar.info/success/error(message, duration:, action:)`；app 層 `ToastService`：
  https://github.com/immich-app/immich/blob/970c496e55bdf261e7c1247bb282d3a7204e40f2/mobile/lib/services/toast.service.dart#L12-L22
  （`success` / `error`，參數 `ToastOption(timeout, onUndo)`；`onUndo` 轉成 `SnackbarAction`）
- **外觀/位置**：`behavior: SnackBarBehavior.floating`（`snackbar.dart` L56）、`persist: false`（L61）、icon + 色彩語意（info/success/error）。desktop/mobile **無分流**（Immich mobile 本來只跑手機）。
- **佇列/取代**：**取代** —— `messenger.hideCurrentSnackBar()` 再 `showSnackBar`（L33-L34）。
- **錯誤詳情/report**：訊息層**沒有**。`mobile/lib/utils/error_handler.dart#L11-L36` 的 `handleError` 先用 `Trace.from(stack).foldFrames(... terse: true)` 洗掉 framework frames 再 `dPrint`，顯示只給 `snackbar.error(message)`。**詳情走獨立頁**：`mobile/lib/pages/common/app_log.page.dart#L97` → `AppLogDetailRoute`，`app_log_detail.page.dart` 分區塊（MESSAGE / DETAILS / FROM / STACK TRACE）各帶 copy IconButton；整批 log 可用 `ImmichLogger.shareLogs` 匯成檔案分享（`mobile/lib/services/immich_logger.service.dart#L18-L52`）。
- **與 Navigator/全螢幕的關係**：`mobile/lib/main.dart` 的 `MaterialApp.router(scaffoldMessengerKey: scaffoldMessengerKey)` → **messenger 在 router/Navigator 之上**，跨路由存活。未捕捉例外只進 logger，不彈訊息。

### 4.6 Finamp（`jmshrv/finamp` @ `0aae9d5`, branch `redesign`）
- **元件**：Material SnackBar + 樣本中最完整的自建 service：`class GlobalSnackbar`（353 行）
  https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/components/global_snackbar.dart
  掛在 `MaterialApp.scaffoldMessengerKey` + `navigatorKey`。全 repo 呼叫點極多；舊的 `errorSnackbar(...)` 已標 `@Deprecated` 指向 `GlobalSnackbar.error`。
- **單一入口**：靜態方法 `show` / `showPrebuilt`（L107-L113）/ `message`（L120 附近）/ `error` / `popup`（L264 附近）/ `dismissAllSnackbars`（L95-L104）。
- **外觀/位置**：`SnackBarBehavior.floating` 被**刻意註解掉**（`lib/main.dart` 附近，理由是與 FAB 位置衝突），因此用預設 `fixed`，貼在 ScaffoldMessenger 底部。desktop / mobile **無分流**。
- **佇列/取代**：**排隊**（用 Flutter 內建佇列，未呼叫 clear）。兩層保險：啟動完成前的呼叫進內部 `_queue`，用 `Timer.periodic` 等 MaterialApp ready；`dismissAllSnackbars()` 一次清空。
- **去重（樣本中最特別）**：`static final Set<String> _activeErrorKeys`（L60）只對**網路類**錯誤去重，key 為 `"network:${event.statusCode}:${underlying.runtimeType}"`（L201-L203，**不帶 URL/body**）；訊息關閉後才移除 key，允許之後再出現（L254）。另有常見網路錯誤靜音：`Failed host lookup` / `HTTP connection timed out` / `TimeoutException` 直接不顯示（L159-L177）。
- **錯誤詳情/report**：**兩條**。
  1. 錯誤 snackbar 帶 "more" action（label 取 `MaterialLocalizations.moreButtonTooltip`，L231）→ 彈 `AlertDialog` 顯示完整 `errorText`。
  2. **長按或右鍵點任何 snackbar**（L138、L143）→ `showSnackbarOptionsMenu` bottom sheet（L291-L296），內含 `DismissAllSnackbarsMenuEntry` 與 `ViewLogsMenuEntry`；後者導到 `LogsScreen`，其 `CopyLogsButton` 複製後再以 `GlobalSnackbar.message(..., isConfirmation: true)`（1.5 秒）確認。另有 `popup()` 用 AlertDialog 顯示雙行訊息。
- **與 Navigator/全螢幕的關係**：messenger 在 MaterialApp 層＝**Navigator 之上**；需要 context 時刻意用 navigator 的 context（原始碼註解說明 scaffold context 缺全域狀態）。

### 4.7 Harmonoid（`alexmercerind/harmonoid` @ `2b021f7`）
- **元件**：**不用 Flutter 層元件**。走 MethodChannel 呼叫原生：
  https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/utils/platform_utils.dart#L53-L57
  `Future<void> showToast(String text)`，第一行 `if (!Platform.isAndroid) return;` → **桌面上是 no-op**。
- 原生端：https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/android/app/src/main/kotlin/com/alexmercerind/harmonoid/UtilsMethodCallHandler.kt#L23-L27
  `Toast.makeText(activity, text, Toast.LENGTH_SHORT).show()`
- **呼叫點**：全 repo 只有 2 處，都在
  https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/features/media_library/playlists/utils/rendering.dart#L77-L79 （「已加入播放清單」）。
- **位置/佇列/取代**：全交給 Android 原生 Toast（系統佇列、底部）。**錯誤詳情/report：無**。
- **維護狀態**：最後 push 2026-09-02，且原始碼中大量功能已標為不再維護 —— 「專案停滯」屬**推測**（本檔只確認日期與檔案內容）。

---

## 5. NewPipe 的 `ErrorActivity`

NewPipe 是 Android/Kotlin 專案，列在此處是因為它的「錯誤詳情頁」是樣本中最完整的一個。

### 分層準則（原始碼註解本身就是準則）
https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/error/ErrorUtil.kt#L20-L30

- 非致命且拿得到 root view → **snackbar**；在背景 service 或拿不到 root view → **notification**；致命 → **ErrorActivity**（最後手段）。

### Snackbar 的 action 就是「開詳情頁」
同檔 L157-L168：

```kotlin
Snackbar.make(rootView, errorInfo.getMessage(context), Snackbar.LENGTH_LONG)
    .setActionTextColor(Color.YELLOW)
    .setAction(context.getString(R.string.error_snackbar_action).uppercase()) { … }
```

- 字串：`error_snackbar_action` = "Report"、`error_snackbar_message` = "Sorry, something went wrong."
  https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/res/values/strings.xml#L270-L271
- 拿不到 root view 時改發 notification，並**額外補一個 Toast**（同檔 L143-L147）。

### 內嵌錯誤面板（不跳頁）
https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/error/ErrorPanelHelper.kt#L66-L96

`showError(errorInfo)` 預設只顯示 message，依條件解鎖：`recaptchaUrl` → 解 captcha 按鈕；`isReportable` → "Report" 按鈕（呼叫 `ErrorUtil.openActivity`）；`isRetryable` → retry；`openInBrowserUrl` → 用瀏覽器開。版面 `res/layout/error_panel.xml`。

### `ErrorActivity` 的內容
https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/error/ErrorActivity.kt
（版面 `app/src/main/res/layout/activity_error.xml`）

- 標題「Sorry…」+ 彩蛋 guru meditation
- 「What happened:」→ `errorMessageView`（人類可讀訊息，帶超連結）
- 「Info:」→ `errorInfosView`（user action / request / content language / content country / app language / service / 時間戳 ISO8601 / package / 版本 / OS；`buildInfo` L166-L181）
- 「Details:」→ `errorView`：等寬字型 + `textIsSelectable="true"` 的 stack trace，多個 trace 之間用 `-----` 分隔
- 「Your comment (in English):」→ `errorCommentBox` 使用者留言框（寫進 `buildJson` 的 `user_comment`，L198）
- **三顆按鈕**（L90-L100）：
  - **Email** → `openPrivacyPolicyDialog(this, "EMAIL")`（L90-L92）；確認後 `Intent.EXTRA_EMAIL = arrayOf(ERROR_EMAIL_ADDRESS)`，常數 `ERROR_EMAIL_ADDRESS = "crashreport@newpipe.schabi.org"`（L277）
  - **Copy formatted report** → `ShareUtils.copyToClipboard(this, buildMarkdown())`（L94-L96）；字串 `copy_for_github` = "Copy formatted report"（`strings.xml#L267`）
  - **Report on GitHub** → `openPrivacyPolicyDialog(this, "GITHUB")`（L98-L100）；確認後只**開啟** `ERROR_GITHUB_ISSUE_URL = "https://github.com/TeamNewPipe/NewPipe/issues"`（L280），**不代填** issue 內容
- 上方 overflow 另有 **share** 圖示分享 **JSON**（`R.id.menu_item_share_error`，L123-L130，`buildJson()`）
- 兩顆送出按鈕都**先彈隱私政策 AlertDialog**（`openPrivacyPolicyDialog` L136 起）
- 兩種輸出格式：`buildJson()`（L183-L206，欄位 `user_action/request/content_language/content_country/app_language/service/package/version/os/time/exceptions[]/user_comment`）；`buildMarkdown()`（L208-L261，先使用者留言，再 `## Exception` 清單，多個 trace 時用 GitHub 的 `<details><summary>` 收合）
- 崩潰自動上報：ACRA 的 `AcraReportSender.java#L36-L41` 不真的送 server，而是把 ACRA 的 STACK_TRACE 轉成 `ErrorInfo` 再開 `ErrorActivity`，讓使用者自己決定要不要送 —— **同一頁 UI 吃所有來源**。

---

## 6. 「複製錯誤資訊」的其他產品慣例

本輪逐一看到的樣本：

| App | 可複製的內容 | 容器 | 備註 |
|---|---|---|---|
| NewPipe | Markdown / JSON | 獨立 `ErrorActivity` | 「Copy formatted report」為 GitHub issue 而寫；另有 Email / 開 GitHub issues 頁 |
| AppFlowy | error message、stack trace（分開兩個 copy） | 獨立 `FlowyErrorPage` | 另附 GitHub issue URL prefill（`template=bug_report.yaml`，把 message 與 trace 塞進 `context` 參數） |
| Immich mobile | log 各欄位（MESSAGE / DETAILS / FROM / STACK TRACE） | 獨立 log detail 頁 | 另有整批 `shareLogs` 匯出檔案 |
| Finamp | logs | 獨立 `LogsScreen` | 從 snackbar 長按/右鍵的 bottom sheet 進入；訊息層本身只給一個「more」dialog |
| LocalSend | 任意文字（通用元件 `CopyableText`） | 就地元件 | 複製後以 snackbar 確認 |
| Spotube / Namida / Harmonoid | 無 | — | 樣本中沒有錯誤詳情或回報機制 |

**共同模式（推測）**：訊息本身不可複製，details 一定有一個獨立容器（頁面／dialog／bottom sheet）才提供 copy 或 report。此條是從上表歸納，非任何文件的明文規定。

---

## 7. 查不到 / 無 / 與子代理報告的差異

### 查不到
- **M3 規範沒有「snackbar 用於錯誤」的明文條目**；只能引相鄰的 M3 Dialogs 與 M1（已歸檔）Errors pattern。
- **Apple HIG 完全沒有 toast 元件或 toast 一詞**（已把 Components 全部子分類頁讀過）。
- **沒有任何一個樣本 app 使用 `bot_toast` / `another_flushbar` / `overlay_support` / `Get.snackbar`**。實際分布是：Material SnackBar 自建 service（Finamp、Immich、LocalSend、AppFlowy）、第三方元件庫內建 toast（Spotube → `shadcn_flutter`）、自製套件（Namida → `nampack`）、原生 Toast（Harmonoid）。
- Harmonoid 的 Flutter 層沒有訊息層可言，桌面無 toast（`showToast` 是 no-op）。Spotube / LocalSend / Namida / Harmonoid 沒有錯誤詳情或回報機制。
- Windows 官方文件對「Action Center / Notification Center」命名不一致，未找到一份統一名稱的現行文件。

### 我核對後修正子代理報告之處
- AppFlowy 的 `GitHubRedirectButton` **不是獨立檔案**，class 就在 `error_page.dart` L210-L272；URL 建構在 L224-L230、`_contextString` 在 L232-L245（子代理原報告寫 L45-L68，錯）。
- shadcn_flutter 的 toast 檔路徑是 `packages/shadcn_flutter/lib/src/components/overlay/toast.dart`（子代理只寫 `toast.dart`）；`showToast` L265、`assert(layer != null, …)` L284、`addEntry` L296、`ToastLayer` L450、`maxStackedEntries` 預設 3 在 L559。核對的版本是 `master`（pub 最新 0.0.54），Spotube 實際鎖的是 0.0.47 —— 預設值 3 是否在 0.0.47 即如此，**未查**。
- NewPipe 的 `ErrorUtil.kt` / `ErrorActivity.kt` 路徑是 `app/src/main/java/org/schabi/newpipe/error/`（子代理原報告未給完整路徑，我按 `util/` 取檔得到 404）。
- AppFlowy 的 `snap_bar.dart` 在 `frontend/appflowy_flutter/packages/flowy_infra_ui/lib/style_widget/` 底下（子代理寫 `packages/flowy_infra_ui/...`，少了 `frontend/appflowy_flutter/` 這段）。
- Finamp 的 `SnackBarBehavior.floating` 在 `lib/main.dart` L1024-L1025 與 L1041-L1042 被註解掉，緊鄰的 TODO 原文是 "get rid of floating action buttons and re-enable the floating behavior and insetPadding" —— 理由確認。
- NewPipe 的 GitHub 按鈕**不代填** issue，只開 `.../NewPipe/issues`（L280）；代填 issue 的是 AppFlowy。
- Harmonoid 的「專案已停滯」是**推測**，本檔只把它寫成日期與內容事實。

### 本檔已親自重新抓取核對的引文
M3 Snackbar guidelines 與 accessibility、Fluent 2 Toast usage、Apple HIG Alerts（皆 2026-09-28）；LocalSend `snackbar.dart`、Immich `snackbar.dart` + `toast.service.dart`、Finamp `global_snackbar.dart` + `main.dart`、AppFlowy `error_page.dart` + `toast.dart` + `snap_bar.dart`、Harmonoid `platform_utils.dart` + `UtilsMethodCallHandler.kt` + `rendering.dart`、NewPipe `ErrorUtil.kt` + `ErrorActivity.kt` + `strings.xml`、Spotube `presentation_actions.dart` + `use_global_subscriptions.dart` + `playlist_create_dialog.dart`、shadcn_flutter `toast.dart`。其餘（M3 overview/dialogs、Fluent 2 message bar、WinUI InfoBar、Windows toast API、Apple HIG Notifications/Feedback/Progress indicators、Namida 各檔行號）為子代理抓取後附 URL，行號未逐條重開檔核對。
