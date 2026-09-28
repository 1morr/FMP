# Flutter 框架、套件與平台：瞬時訊息（Toast / SnackBar）

- 查證日：2026-09-28
- 查證方式：Flutter 官方 API 文件（`api.flutter.dev`，WebFetch 原文）、Flutter 官方部落格與 breaking-changes（context7 `/flutter/website` 與 `/websites/api_flutter_dev`）、
  **本機 Flutter SDK 原始碼**（欄位 `6655482ec06e547f90abf8ae7590466f4415978d`，`3.47.1` stable；下方 permalink 用此 SHA）、
  `pub.dev/api/packages/<name>` 直接核對版本與發布日、`gh api`／`gh search issues` 查上游 issue。
  本機 toolchain：Flutter 3.47.1 stable / Dart 3.13.1；pub.dev 現行 stable 為 **3.47.5**（2026-09-18，`releases_windows.json`）。
- 標 `推測` 的是未經官方文件或程式碼直接支持的推論；查不到寫 `查不到`。

## 1. Flutter 框架（3.47 世代）

### 1.1 `ScaffoldMessenger` 與根 messenger

- `MaterialApp` 內建一個根 `ScaffoldMessenger`：`ScaffoldMessenger` 在 `_materialBuilder` 中**包住整個 child（含 Navigator）**
  ——`flutter/flutter@6655482ec0 packages/flutter/lib/src/material/app.dart#L1047`。官方 breaking-change 文件原文：
  「By default, a root `ScaffoldMessenger` is included in the `MaterialApp`」、
  「The `ScaffoldMessenger` now handles `SnackBar`s in order to persist across routes and always be displayed on the current `Scaffold`.」
  （https://docs.flutter.dev/release/breaking-changes/scaffold-messenger）
- **SnackBar 由 `Scaffold` 自己畫，不是由 messenger 畫**：`ScaffoldMessengerState._updateScaffolds()` 對每個已註冊的
  Scaffold 呼叫 `scaffold._updateSnackBar()`（`.../material/scaffold.dart#L231-L236`），`ScaffoldState` 把 messenger 的第一個
  SnackBar 存進 `_messengerSnackBar`（`#L2320-L2329`）並在 Scaffold 的版面裡建構它（`#L3090-L3099`）。
  → **推測**（框架未明文寫，但由原始碼結構直接推出）：SnackBar 被畫在該 Scaffold 的子樹內；
  任何在此之後 push 到同一 Navigator 上的 route（對話框、`showModalBottomSheet`、全螢幕播放頁）在 Overlay 中排在更上層，
  因此**會蓋住 SnackBar**。
- **多個 Scaffold**：class 文件原文「the ScaffoldMessenger will only present the notification to the **root Scaffold of the subtree of Scaffolds**」
  （https://api.flutter.dev/flutter/material/ScaffoldMessenger-class.html）；原始碼 `_isRoot()`
  （`.../material/scaffold.dart#L241-L244`）「Nested Scaffolds are handled by the ScaffoldMessenger by only presenting a
  MaterialBanner or SnackBar in the root Scaffold of the nested set.」。
  但 `showSnackBar` 自己的 dartdoc 又寫「Shows a `SnackBar` across **all registered** `Scaffold`s」並說「the snack bar is shown
  simultaneously on all of them」（https://api.flutter.dev/flutter/material/ScaffoldMessengerState/showSnackBar.html）
  ——同一份文件裡這兩句互相矛盾，`_isRoot()` 才是實際行為。
- **排隊**：`showSnackBar` 原文「the given snack bar will be added to a queue and displayed after the earlier snack bars have closed.」；
  原始碼 `_snackBars` 是 `Queue`，已顯示時走 `_snackBars.addLast(controller)`（`#L198-L199`、`#L348-L350`）。
  移除：`hideCurrentSnackBar`（帶動畫）／`removeCurrentSnackBar`（無動畫）。
- `showSnackBar` **不能在 build 期間呼叫**：dartdoc 原文「The showSnackBar() method cannot be called during build.」，
  建議 `initState`／`didChangeDependencies` 或 `SchedulerBinding.addPostFrameCallback`。
- **沒有 `ScaffoldMessenger` 祖先會 assert**：`debugCheckHasScaffoldMessenger`；
  `ScaffoldMessenger.showSnackBar was called, but there are currently no descendant Scaffolds to present to.`（`scaffold.dart#L317-L322`）。

### 1.2 `MaterialApp.scaffoldMessengerKey`

- dartdoc 原文「A key to use when building the `ScaffoldMessenger`.」若提供，「can be directly manipulated without first obtaining it
  from a `BuildContext`」（https://api.flutter.dev/flutter/material/MaterialApp/scaffoldMessengerKey.html）。
- 這是「服務層不拿 context、也能推 SnackBar」的官方做法（拿 `GlobalKey.currentState` 直接呼叫 `showSnackBar`）。
- 舊專案的 `lib/app.dart:133` **沒有**設 `scaffoldMessengerKey`，所以只有框架自動的根 messenger，且只能透過 `ScaffoldMessenger.of(context)` 取得。

### 1.3 `SnackBar` 屬性（3.47）

| 屬性 | 文件／原始碼原文 | 備註 |
|---|---|---|
| `behavior` | `fixed`＝「Fixes the SnackBar at the bottom of the Scaffold」「will be shown above a `BottomNavigationBar` or a `NavigationBar`」「will cause other non-fixed widgets … to be pushed above」（FAB 為例）；`floating`＝「shown above other widgets in the Scaffold」 | **兩者都沒有被標 deprecated**（https://api.flutter.dev/flutter/material/SnackBarBehavior.html） |
| `action` | 型別是**單一個** `SnackBarAction?`；dartdoc 沒有寫數量上限 | M3 規範另有「只有一個 action」的設計限制（見 `prior-art.md`） |
| `duration` | 「The amount of time the snack bar should be displayed.」 | 預設為私有常數 |
| `persist` | 「Whether the snack bar will stay or auto-dismiss after timeout.」啟用時「remains visible even after the timeout」直到使用者點 action 或 close icon；「If not provided, but the snackbar action is not null, the snackbar will persist as well.」（https://api.flutter.dev/flutter/material/SnackBar/persist.html） | 預設＝`action != null` 就 persist |
| `showCloseIcon` | 「Whether to include a "close" icon widget.」 | 舊專案未使用（`toast_service.dart` 無此參數） |
| 無障礙 | 「A `SnackBar` with an action will not time out when TalkBack or VoiceOver are enabled.」（由 `AccessibilityFeatures.accessibleNavigation` 控制） | 舊專案 `toast_service.dart:134` 用同一旗標決定 `persist` |
| 內建語意 | `snack_bar.dart` 內建 `Semantics(... liveRegion: true ...)`（`@6a19cca`：https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/material/snack_bar.dart#L828） | SnackBar 本身就是 live region |

### 1.4 3.38–3.47 的相關變更

- **SnackBar 帶 action 不再自動消失**：Flutter 3.38（2026-05）「For more predictable behavior, a SnackBar that includes an action will no
  longer auto-dismiss」（PR https://github.com/flutter/flutter/pull/173084，標題「SnackBar with action no longer auto-dismiss」，已 merged）。
  這正是 `persist` 的預設語意；舊專案 `toast_service.dart:129-134` 的註解已記載，並在非讀屏模式把它覆寫回「會消失」。
- **`OverlayPortal.targetsRootOverlay` 已 deprecated** → 改用 `OverlayPortal(overlayLocation: OverlayChildLocation.rootOverlay, ...)`；
  `Overlay.of`／`Overlay.maybeOf` 不再越過 `LookupBoundary`（https://docs.flutter.dev/release/breaking-changes/deprecate-overlay-portal-targets-root）。
- **3.38 起 `OverlayPortal.overlayChildLayoutBuilder` 可在樹上任何 Overlay 渲染子節點**（PR #174239），官方部落格舉例正是
  「show an app-wide notification or other UI that needs to escape the layout constraints of its parent widget」
  （https://flutter.dev/blog/whats-new-in-flutter-3-38）。
- **`Overlay` 的兩種取得方式**：`Overlay.of(context)` 取最近的（受 `LookupBoundary` 限制），要 Navigator 的那個要 root overlay。
  Navigator 的 Overlay 是最常見的一種（`Overlay` class 文件：「most common to use the overlay created by the `Navigator`」、
  「the navigator uses its overlay to manage the visual appearance of its routes」）。
- **Flutter 3.47 沒有 SnackBar／ScaffoldMessenger 的 breaking change**（3.47 的三條 breaking change 是 OpenGL ES render-to-texture、
  iOS/Android `header`/`headingLevel` 語意行為、移除 `describeEnum`；來源 https://docs.flutter.dev/release/breaking-changes）。
  3.47 的無障礙變更另有：`BlockSemantics` 現在也擋鍵盤焦點、Android 高對比／反色偵測（`MediaQueryData.highContrast`／`invertColors`）。
  （來源為搜尋結果彙整的官方頁面，未逐條在 API 文件核對；標 **推測** 的部分僅指這些摘要之間無衝突。）

## 2. 套件（資料來自 `pub.dev/api/packages/<name>`，2026-09-28 實查）

| 套件 | 最新版 / 發布日 | SDK / Flutter 約束 | 平台 | likes / 30d 下載 | 需 context | 佇列 | 去重 | action 鈕 | 無障礙 |
|---|---|---|---|---|---|---|---|---|---|
| `toastification` | 3.2.0 / 2026-04-19 | `>=3.0.0 <4.0.0` / `>=3.38.0` | android, ios, windows, linux, macos, web | 1294 / 205,228 | 否（`ToastificationWrapper`） | 是（`AnimatedList` + `maxToastLimit`＝10） | 查不到 | `show()` 無 action 參數；`showCustom` 可自帶 | 原始碼 0 處 `Semantics`／`liveRegion` |
| `bot_toast` | 4.1.3 / **2023-09-19** | `^2.12.0` / `>=2.0.0` | 同上六平台 | 1004 / 377,808 | 否（`BotToastInit`） | 部分（回傳 `cancel`） | 否 | 否 | 0 處 |
| `another_flushbar` | 2.2.4 / 2026-05-15 | `>=2.12.0 <4.0.0` / 未宣告 flutter | 同上六平台 | 1041 / 135,539 | **是**（`Flushbar(...).show(context)`） | 推測 | 查不到 | 是（`mainButton`） | 只有 `Semantics(container: true, explicitChildNodes: true)`，**無 `liveRegion`** |
| `fluttertoast` | 10.0.0 / 2026-07-31 | `>=3.12.0 <4.0.0` / `>=3.44.0` | **只有 android, ios, web**（plugin） | 4135 / 603,523 | 否 | 否（原生 toast） | 否 | 否 | 交給原生 Android Toast，無 Flutter semantics |
| `elegant_notification` | 2.5.1 / 2025-05-08 | `>=2.19.0 <4.0.0` / 未宣告 | 同上六平台 | 521 / 10,685 | **是**（`ElegantNotification(...).show(context)`） | 是（可堆疊） | 查不到 | 是（`action` Widget） | 0 處 |
| `overlay_support` | 2.1.0 / **2022-11-13** | `>=2.14.0 <3.0.0` | 同上六平台 | 701 / 101,836 | 否（`OverlaySupport.global` + `toast()`） | 推測 | 是（以 `key` 取代既有通知） | 否 | 0 處 |

維護狀態（GitHub repo、最後 push、最新 release）：

- **`toastification`** — `payam-zahedi/toastification`，817★，push 2026-04-19，release v3.2.0（2026-04-19）。維護中。
- **`bot_toast`** — `MMMzq/bot_toast`，847★，push 2024-05-29，GitHub 最新 release 仍是 4.0.0（2021-02-27）。**停滯約 2 年**，但下載量最高。
- **`another_flushbar`** — issue tracker 指向 `ideployed/another-flushbar`（建立於 2026-05-10、0★、無 release）；首頁改為 `flushkit.dev`。
  社群舊版是 `AndreHaueisen/flushbar`（push 2023-05-30）。2.x 新增自家遠端通知服務 `FlushbarRemote.init(apiKey:, context:)`，
  並多出 `http`／`shared_preferences`／`url_launcher` 依賴。**推測**是 publisher 易主，建議自行核對再決定是否採用。
- **`fluttertoast`** — `PonnamKarthik/FlutterToast`，1530★，push 2026-08-10，99 個 open issue，無 GitHub release。
- **`elegant_notification`** — `koukibadri/Elegant-Notification`，僅 52★，push 2026-02-07，release v2.5.1（2025-05-08），23 open issue。低度維護。
- **`overlay_support`** — `boyan01/overlay_support`，379★，push 2023-10-04，release v2.1.0（2022-11-13）。**停滯近 3 年**。

**值得注意的矛盾**：`overlay_support` 的 pubspec 是 `sdk: >=2.14.0 <3.0.0`（排除 Dart 3），但 pub 的 score tags 同時標了
`is:dart3-compatible`。**推測** tag 過時、實務上在 Dart 3 專案無法解析；要用前必須實測。
另 `another_flushbar` 2.2.4 的 pubspec **不再宣告 `flutter:` 區塊**（1.x 有 android/ios/web plugin 條目），但 pub 平台 tag 仍列六平台。

**對 FMP（Android + Windows）最要緊的一點**：`fluttertoast` 是 plugin，**沒有 Windows 實作**——在 Windows 上呼叫會是
`MissingPluginException`，且它不產生 Flutter 端 semantics。`toastification` 是六平台 Dart 套件、維護中、有佇列與上限，
但沒有內建 action 參數與 live region。

引用原始碼（pinned SHA）：
- `another_flushbar` 的 `Semantics`：`https://github.com/ideployed/another-flushbar/blob/001ce540dd37696a9ae14e5c25151cd66b23ff56/lib/flushbar_route.dart#L99`
- `toastification` `maxToastLimit`：`https://github.com/payam-zahedi/toastification/blob/4f1068f5265a0d189aee6881d125e8a35adec74f/lib/src/core/toastification_config.dart`
- `toastification` `show()` 參數表（無 `action`）：同 repo `.../lib/src/core/toastification.dart#L240`
- `overlay_support` 依 `key` 取代：`https://github.com/boyan01/overlay_support/blob/134575de99d34a4fcd366baba2fddd57435c0377/lib/src/notification/overlay_notification.dart`

（上述四條 GitHub 原始碼為子代理查證，未逐條重跑；版本與發布日已由本代理以 pub.dev API 獨立核對，全部相符。）

## 3. 無障礙

### 3.1 `SemanticsService.announce` 已 deprecated（3.35 起）

原文（https://api.flutter.dev/flutter/semantics/SemanticsService/announce.html）：

```
@Deprecated(
  'Use sendAnnouncement instead. '
  'This API is incompatible with multiple windows. '
  'This feature was deprecated after v3.35.0-0.1.pre.',
)
static Future<void> announce(String message, TextDirection textDirection,
    { Assertiveness assertiveness = Assertiveness.polite })
```

替代品 `sendAnnouncement`（https://api.flutter.dev/flutter/semantics/SemanticsService/sendAnnouncement.html）：

```dart
static Future<void> sendAnnouncement(
  FlutterView view, String message, TextDirection textDirection,
  { Assertiveness assertiveness = Assertiveness.polite })
```

- 文件：「One can use `View.of` to get the current `FlutterView`.」——**每個 view 各自送**，這是它與 `announce` 的差別
  （`announce` 的 deprecation 理由正是「incompatible with multiple windows」）。
- 「Not all platforms support announcements. Check to see if it is supported using `MediaQuery.supportsAnnounceOf` before calling this method.」
- `assertiveness`「Currently, this is only supported by the web engine and has no effect on other platforms.」
- Android 段：「Android has deprecated announcement events due to its disruptive behavior with TalkBack forcing it to clear its
  speech queue … Instead, use mechanisms like `Semantics` to implicitly trigger announcements.」
- class 層級文件：「When possible, prefer using mechanisms like `Semantics` to implicitly trigger announcements over using this event.」
  （https://api.flutter.dev/flutter/semantics/SemanticsService-class.html）

### 3.2 live region

`SemanticsProperties.liveRegion` 原文（https://api.flutter.dev/flutter/semantics/SemanticsProperties/liveRegion.html）：

> 「If non-null, whether the node should be considered a live region. A live region indicates that updates to semantics node are
> important. Platforms may use this information to make polite announcements to the user to inform them of updates to this node.
> An example of a live region is a `SnackBar` widget. **On Android and iOS, live region causes a polite announcement to be generated
> automatically, even if the widget does not have accessibility focus.**」

用法：`Semantics(liveRegion: true, child: ...)`（旗標 `SemanticsFlag.isLiveRegion`）。
**平台缺口**：live region 在 macOS 不作用（flutter/flutter#167318，open，2025-04-16）；
Android 在對話框關閉時會誤報（#166258，open）。（#167318 已由 `gh api` 核對存在。）

### 3.3 SnackBar 的內建無障礙

Flutter 的 `SnackBar` 自己就包了 `Semantics(... liveRegion: true ...)`
（`@6a19cca`：https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/material/snack_bar.dart#L828），
並用 `accessibleNavigation` 決定帶 action 時不自動消失。→ 自製 toast 若要等價無障礙，最省事的做法是照抄
`Semantics(liveRegion: true)`，而不是呼叫 announce 系列。

### 3.4 Windows 無障礙樹與 overlay 類元件的關係

- repo 自己記過：`docs/troubleshooting.md` §「Windows：`Failed to update ui::AXTree`」——`OverlayPortal` 的內容實體上掛在
  Overlay 底下、走訪順序卻嫁接回觸發它的元件，落在 Navigator 的 Overlay 時 Windows 的 AccessibilityBridge 收不下，
  整批 update 被丟掉且不會自我修復（**不是噪音**）。已知觸發：Material `Slider`／`RangeSlider` 的數值指示器、
  滑鼠 hover 的 `Tooltip`。FMP 的避法是 `ScopedSlider` 用 `Overlay.wrap` 給它一個本地 Overlay
  （`lib/ui/widgets/controls/scoped_slider.dart:6,43`），並以 `test/ui/static_rules/slider_overlay_static_rule_test.dart` 擋直接建 `Slider(`。
  上游 issue：**flutter/flutter#182444**（open，2026-02-15，標題「Windows ListView+Tooltip can trigger error: Failed to update
  ui::AXTree …」，labels 含 `platform-windows`、`a: accessibility`）。
- **`docs/troubleshooting.md` 有一句已過時**：它寫「Slider 那一種沒有最小重現…上游沒有提到 Slider」。
  上游現在有明確的 Slider 版本：**flutter/flutter#190357**（open，2026-07-31，updated 2026-09-25，標題「[Windows] A Slider inside a
  pushed route serializes an orphan semantics node, permanently freezing the accessibility tree」）。此行號出處：`docs/troubleshooting.md:40`。
- 其他相關上游：**#175041**（Windows AccessibilityBridge::CreateRemoveReparentedNodesUpdate crash，open）、
  **#187198**（`OverlayPortal` 在 macOS 上語意樹崩壞，open）、**#190144**（web：Slider 的 value-indicator `OverlayPortal` 產生
  無 payload 的全視窗語意節點，closed）。
- **SnackBar／ScaffoldMessenger 的 Windows 或 multi-window 專屬 bug：查不到**（對 `flutter/flutter` 搜 `windows snackbar`、
  `ScaffoldMessenger windows` 皆無對應命中）。唯一的 multi-window 訊號是 `announce` 的 deprecation 理由。
- **overlay 類 toast 套件是否被點名：查不到**任何 issue 直接指名 toast 套件。**推測**：這類套件（`toastification`、
  `overlay_support`、`bot_toast` 等）都把內容掛進 Overlay（多半是 Navigator 的 root Overlay），機制與 #182444／#190357 同一類，
  因此同屬高風險，但**無實測證據**；`ScopedSlider` 的 `Overlay.wrap` 是本 repo 已驗證的迴避手法。

## 4. 多視窗與背景

- **Windows 桌面歌詞子視窗**（`desktop_multi_window` 0.3.1，`pubspec.yaml:89`）跑在**獨立 Flutter engine**：
  `lib/ui/windows/lyrics_window.dart:28-30` 的 `@pragma('vm:entry-point') void lyricsWindowMain(...)`，
  自己一個 `MaterialApp`（`:159`）與 `Scaffold`（`:681`），不共用主視窗的 `ScaffoldMessenger`。
  該檔 grep 不到 `ToastService`／`SnackBar`／`ScaffoldMessenger`。子視窗要顯示提示需自備一套（管線、位置、語意都要重做）。
- 這正是 `SemanticsService.announce` deprecation 理由「incompatible with multiple windows」所指的情境：
  多 engine 下要改用 `sendAnnouncement(view, ...)`，並先以 `MediaQuery.supportsAnnounceOf` 檢查。
- **Android 背景**：播放由 `audio_service` 0.18.15 的 foreground `AudioService` 承擔
  （`android/app/src/main/AndroidManifest.xml:63-72`；通知 channel 在 `lib/main.dart:175-180`）。
  `AndroidManifest.xml` **沒有** `SYSTEM_ALERT_WINDOW`，App 沒有懸浮窗／overlay 權限。→ 背景播放時 Flutter UI 不在前景，
  in-app toast 無處可畫，只能靠 media notification 或事後在畫面顯示狀態。**推測**，未實測。
- **Windows 系統匣**：`tray_manager` 0.5.3（`pubspec.yaml:56`）只用 `setIcon`／`setToolTip`／`setContextMenu`／`popUpContextMenu`
  （`lib/services/platform/windows_desktop_service.dart:111,120,176,199,228`），**沒有** 送 OS 通知的呼叫。
  FMP 目前沒有任何 Windows OS 層通知路徑。
- Windows OS 層通知（`AppNotificationManager`、WinRT `ToastNotificationManager`）在 Flutter 需另外接 plugin，
  FMP 的 `pubspec.yaml` 沒有這類依賴；查不到 FMP 內既有用法。
