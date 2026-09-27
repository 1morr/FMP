# 背景任務排程：平台與套件硬性事實

- 查證日期：2026-09-27
- 查證方式：context7（Riverpod、flutter_workmanager 官方文檔）+ pub.dev API（版本與發佈日期）+ 官方文檔（developer.android.com、api.flutter.dev、developer.apple.com）+ tavily-search 補充 + GitHub API（workmanager 維護活動）。
- 適用範圍：FMP 重寫的背景任務排程設計（排行榜背景刷新、匯入歌單自動刷新、電台輪詢、連線偵測、快取清理）。

---

## 1. Android 背景執行限制

### Dart `Timer` 在背景的行為

`Timer` 依附於 Dart isolate 的事件迴圈，**只要進程活著且 CPU 醒著就會繼續觸發**；Flutter 官方沒有「背景自動停止 Timer」的機制。官方對背景執行的指引是：要在 App 非前景時執行 Dart 程式碼，需另外建立 isolate（callback dispatcher 模式），或用 WorkManager 類的持久化排程（來源：[docs.flutter.dev — Background processes](https://docs.flutter.dev/packages-and-plugins/background-processes)）。

硬性限制來自 Android 系統，不是 Flutter：

- **無前景服務時**：App 退到背景後進程屬 cached 狀態，系統在記憶體壓力下可隨時終止它；進程一死，Timer 自然也沒了。此外 App Standby bucket 會按使用頻度限制 job/alarm/網路額度（如 working set 每小時最多 10 次鬧鐘、rare bucket 更嚴；來源：[developer.android.com — Power management resource limits](https://developer.android.com/topic/performance/power/power-details)）。
- **有前景服務時**（媒體播放用的 mediaPlayback foreground service）：進程被歸類為前景，不會被 App Standby 判為 idle。官方原文：「The system makes this determination when the user doesn't touch the app for a certain period of time and none of the following conditions applies: … The app has a process currently in the foreground, either as an activity or foreground service」。但官方同時警告「Don't start a foreground service just to prevent the system from determining that your app is idle」（來源：[developer.android.com — Optimize for Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)）。

### Doze 的影響（對 Timer 與網路同樣致命）

Doze 期間（裝置未充電、靜置、關螢幕），系統對**所有** App 套用以下限制，前景服務也不例外（該頁只說前景服務可避開 App Standby 的 idle 判定，未給予 Doze 豁免）：

- **Suspends network access.**
- **Ignores wake locks.**（→ CPU 睡眠，Dart isolate 不跑，Timer 實質不觸發）
- 標準 `AlarmManager` 鬧鐘延遲到 maintenance window；`JobScheduler` 不跑，「WorkManager uses `JobScheduler` internally, so `WorkManager` tasks don't run」。
- 系統定期進入短暫 maintenance window 放行積壓的 jobs/syncs/alarms 與網路；且「the system schedules maintenance windows less frequently」——放著越久，窗口越稀疏。
- `setAndAllowWhileIdle()` / `setExactAndAllowWhileIdle()` 每 App 每 9 分鐘最多觸發一次。

（以上皆引自 [developer.android.com — Optimize for Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)；AOSP 層級的 Doze / Lightweight Doze 差異見 [source.android.com — Platform power management with Doze](https://source.android.com/docs/core/power/platform_mgmt)。）

部分豁免（使用者手動加入電池最佳化白名單）也只放開網路與 partial wake lock，jobs/syncs/鬧鐘照樣延遲。可查 `isIgnoringBatteryOptimizations()`。

### 對本專案的含意

Android 上「App 在背景、Timer 繼續跑」只在**裝置醒著且進程沒被殺**時成立，完全不可靠。即使播放中的前景服務保住進程，Doze 照樣斷網、忽略 wake lock。所以背景刷新在 Android 只能兩條路：前景（含播放中）跑 Timer，或交給 WorkManager 以 15 分鐘粒度、容忍 Doze 延遲；「恢復後補跑」是必要設計，不是加分項。

---

## 2. workmanager 套件與 Android 官方建議

### 套件現況（查證於 2026-09-27）

- pub.dev：**0.10.10**，發佈於 **2026-09-07**（verified publisher fluttercommunity.dev）。[pub.dev/packages/workmanager](https://pub.dev/packages/workmanager)
- 平台：**Android、iOS、macOS、Web**；README 提到經由獨立的 `workmanager_linux` 提供實驗性 Linux 支援（未列在 pub.dev 平台 metadata）。**不支援 Windows**。
- 維護狀態：活躍。GitHub `fluttercommunity/flutter_workmanager` 最近 push 2026-09-07，0.10.9（2026-08-20）→ 0.10.10（2026-09-07）連續發版，open issues 僅 8 個（gh api 查證）。

### 硬性限制

- **Android 週期任務最小間隔 15 分鐘**：「For Android, periodic tasks have a minimum frequency of 15 minutes」；periodic task 的 `initialDelay` 只是 best-effort hint，不保證首次準時（來源：[flutter_workmanager docs — customization.mdx](https://github.com/fluttercommunity/flutter_workmanager/blob/main/docs/customization.mdx)，context7 查證）。
- **iOS 不支援固定間隔**：`registerPeriodicTask` 的 `frequency` 被忽略，「the system determines if and when a task runs based on battery, device state, and usage patterns. The minimum gap between runs is 15 minutes, but tasks are frequently deferred or skipped entirely」（同上文檔）。iOS 需 `UIBackgroundModes: fetch` + `BGTaskSchedulerPermittedIdentifiers`（[quickstart.mdx](https://github.com/fluttercommunity/flutter_workmanager/blob/main/docs/quickstart.mdx)）。
- **Doze 下不準時**：如第 1 節，Doze 期間 WorkManager（底層 JobScheduler）不執行，全部延遲到 maintenance window。

### Android 官方對週期性背景工作的建議

官方推薦的可延遲、需保證執行的背景工作一律走 WorkManager（Jetpack）：它處理 Doze、App Standby bucket、裝置重開機後的持久化，並按約束（網路、充電等）排程。週期工作 `PeriodicWorkRequest` 的最小 repeat interval 即 15 分鐘。來源：[developer.android.com — WorkManager](https://developer.android.com/topic/libraries/architecture/workmanager)、[developer.android.com — Optimize for Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)。

### 對本專案的含意

workmanager 是目前仍活躍維護的唯一主流選項，且只做 Android/iOS（macOS/Web 不算本專案場景）——**Windows 不在內**，桌面端要另走「進程活著就跑 Timer」的路線。粒度上接受「至少 15 分鐘、Doze 下更久、iOS 完全由系統決定」：排行榜刷新、歌單刷新這類場景合用；電台輪詢若需要分鐘級以下精度，背景只能放棄，改在前景/播放中做。

---

## 3. Windows / Linux / macOS 桌面

### 最小化時 Dart `Timer` 是否繼續跑

**會。** 依 `AppLifecycleState` 官方 dartdoc：

- `paused`「**This state is only entered on iOS and Android**」，且 paused 時引擎停止 `onBeginFrame`/`onDrawFrame`。
- 桌面平台視窗最小化或不可見時進入的是 `hidden`（詳見第 5 節），引擎不停止，Dart isolate 與 `Timer` 照常執行。

（來源：[api.flutter.dev — AppLifecycleState](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html)。桌面平台沒有 Android/iOS 那種「App 進背景即可能被系統暫停/殺掉」的模型，進程只要沒被使用者關掉就一直跑。）

### OS 層的節流（Windows）

- **Power Throttling（Win10+）與 Efficiency Mode（Win11, EcoQoS）**會對系統判定為背景的進程降 CPU 頻率/降 QoS 等級；有使用者回報 App 一最小化就被自動套 Efficiency Mode。效果是**變慢而非停止**：Timer 照樣觸發，但排程延遲與執行時間可能拉長，且新版 Windows（25H2）在桌機、插電狀態下也更積極（來源：[Tweaktown — Windows 11 is secretly throttling your apps](https://www.tweaktown.com/guides/11436/windows-11-is-secretly-throttling-your-apps-heres-how-to-catch-it/index.html)、[Microsoft Q&A — Automatically activates efficiency mode](https://learn.microsoft.com/en-us/answers/questions/4011547/automatically-activates-efficiency-mode)）。
- 這是 per-process 的系統策略，App 端無公開 API 保證豁免；媒體播放中的進程因持有 audio session，實務上較不會被判為純背景（推測，無官方來源）。

### Linux / macOS

本次未查到官方文檔級來源。一般桌面模型同 Windows：最小化不暫停進程，Timer 照跑；macOS 的 App Nap 會對隱藏 App 做 timer coalescing（推測，未逐字查證 Apple 文檔，本專案現階段非目標平台）。

### 對本專案的含意

Windows（及日後 Linux/macOS）上「最小化/縮托盤後繼續跑 Timer」是成立且可靠的，背景刷新可以直接用 Dart `Timer` + Riverpod 實作，不需要任何平台排程器。唯一要注意的是 Efficiency Mode 造成的延遲是**效能問題不是正確性問題**，設計上容忍抖動即可。

---

## 4. iOS 背景執行

### BGTaskScheduler 的性質

- 系統決定何時執行，**不保證準時、不保證執行**：「The system decides timing, not the app」；任務會依電量、網路、使用習慣被延遲、節流或跳過（來源：[Apple — Configuring background execution modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes)、[WWDC25 — Finish tasks in the background](https://developer.apple.com/videos/play/wwdc2025/227)：「background execution isn't guaranteed. Instead, it's opportunistic, often discretionary」）。
- `BGAppRefreshTask`（小刷新）與 `BGProcessingTaskRequest`（長一點、可要求接電源）兩類；實測回報差異極大：Background Fetch 一天可能只有 3–4 次，Processing 常在充電整夜時才被排入（[r/iOSProgramming 實測討論](https://www.reddit.com/r/iOSProgramming/comments/1dt7njq/how_often_do_you_get_background_processing_with)）。系統會學使用者開 App 的時段，排在使用者快開之前跑（[uynguyen.github.io](https://uynguyen.github.io/2020/09/26/Best-practice-iOS-background-processing-Background-App-Refresh-Task)）。

### Audio background mode

宣告 `UIBackgroundModes: audio` 且在播放音訊時，App 退到背景**不會被 suspend**，可持續執行：「Typically, an app is in a suspended state when it's in the background. However, there are a limited number of background execution modes … such as playing audio … the system launches or resumes the app, in the background, and affords it time to process any related events」（[Apple — Configuring background execution modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes)）。Apple Developer Forums 上也有實測：正當使用 audio background mode 的 App 在背景持續收到並處理事件，而同時未宣告的 App 已被 suspend（[developer.apple.com/forums — Background Tasks](https://developer.apple.com/forums/tags/backgroundtasks)）。在此狀態下 Dart isolate 存活、`Timer` 可持續觸發（推論自上述官方行為；無 Flutter 官方文件逐字保證）。注意 Apple 審核會查「宣告 audio 但沒有持續音訊功能」的濫用（同論壇串有 Guideline 2.5.4 拒審案例）。

### 對本專案的含意

iOS 上唯一可靠的背景窗口是**播放中**（audio background mode）：此時 Timer 可用，排行榜/電台/歌單刷新都能跑。非播放時只能交給 BGTaskScheduler（workmanager 的 iOS 端），接受「系統決定、可能一天幾次」的現實——所以「恢復前景/恢復播放時補跑」在 iOS 上是主要路徑而非備援。

---

## 5. Flutter `AppLifecycleState` 各平台觸發時機

狀態定義（[api.flutter.dev — AppLifecycleState](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html)、[docs.flutter.dev — add AppLifecycleState.hidden 遷移指南](https://docs.flutter.dev/release/breaking-changes/add-applifecyclestate-hidden)）：

| 狀態 | 含意 | 平台差異 |
|------|------|----------|
| `resumed` | 可見且可互動 | 全平台 |
| `inactive` | 可見但無焦點/過渡中（Android 對應 `Activity.onPause` 或 onResume 但無視窗焦點，如來電、分割畫面、PiP） | 全平台 |
| `hidden` | 所有 view 不可見 | Android/iOS：只是 `inactive`↔`paused` 之間的短暫過渡；**桌面（非 web）：最小化或所在桌面不可見時的穩定狀態** |
| `paused` | 不可見、不接收輸入，引擎停止 `onBeginFrame`/`onDrawFrame` | **只有 iOS 和 Android 會進入** |
| `detached` | 引擎在跑但沒有 view（如 Android 通知回覆場景） | 各平台零星出現 |

針對本專案關心的 Windows：

- **最小化 → `hidden`**（dartdoc 原文：「minimized or placed on a desktop that is no longer visible (on non-web desktop)」）。引擎不停止，Timer 繼續跑。
- **縮到托盤**（`window_manager` 的 `hide()` 隱藏視窗）：視窗不可見，同理落到 `hidden`（推測——與最小化走同一 visibility 路徑；`window_manager` 另有 `WindowListener` 的 `onWindowMinimize` / `onWindowHide` 事件可明確區分兩者，若設計需要分辨「最小化」與「縮托盤」應用這組事件而非 lifecycle）。
- `window_manager` 現況：**0.5.2**，發佈 2026-07-04，支援 Windows/Linux/macOS，verified publisher leanflutter.dev（[pub.dev/packages/window_manager](https://pub.dev/packages/window_manager)）；托盤搭配 `tray_manager` **0.7.0**（2026-09-19，0.6.x 兩版已被 retract）。

### 對本專案的含意

跨平台判「要不要跑背景刷新」的單一訊號：`resumed`/`inactive` 一定跑；Android/iOS 的 `paused` 不跑（等 resume 補跑）；桌面 `hidden` **繼續跑**。監聽 `AppLifecycleState` 就能涵蓋「離線/背景暫停、恢復補跑」的觸發，桌面目標下不需要額外的視窗事件；要區分最小化與托盤才需要 `window_manager`。

---

## 6. Riverpod 3 與排程/定時刷新

查證版本：riverpod **3.4.3**（2026-09-03，[pub.dev/api/packages/riverpod](https://pub.dev/api/packages/riverpod)）。官方文檔（[riverpod.dev](https://riverpod.dev)，經 context7 查證）沒有獨立的「polling / periodic refresh」食譜頁，但有三個直接對口的官方模式：

1. **Provider 內開 `Timer` + `ref.onDispose` 取消**（[docs/concepts2/refs](https://riverpod.dev/docs/concepts2/refs) 的官方範例）：

   ```dart
   class Tick extends Notifier<int> {
     @override
     int build() {
       final timer = Timer.periodic(Duration(seconds: 1), (_) => state++);
       ref.onDispose(timer.cancel);
       return 0;
     }
   }
   ```

   間隔本身也可以 `ref.watch(durationProvider)` 讓週期可設定、改變時自動重建 Timer（[migration/from_state_notifier](https://riverpod.dev/docs/migration/from_state_notifier) 的範例即如此）。

2. **`keepAlive` + `Timer` 的 `cacheFor` 模式**（[docs/concepts2/auto_dispose](https://riverpod.dev/docs/concepts2/auto_dispose) 的官方範例）：auto-dispose provider 在無人監聽後再保留指定時長，適合「離開頁面後短時間內回來不用重抓」的快取語意：

   ```dart
   extension CacheForExtension on Ref {
     void cacheFor(Duration duration) {
      final link = keepAlive();
       final timer = Timer(duration, link.close);
       onDispose(timer.cancel);
     }
   }
   ```

3. **`ref.invalidate` / `ref.invalidateSelf`**：強制丟棄狀態、下次讀取時重算，即「立即刷新」與「排程器到點後觸發重抓」的掛鉤點。

### 對本專案的含意

Riverpod 3 的排程做法就是把 `Timer` 放進 Notifier 的 `build()`、`onDispose` 取消，加上 lifecycle/連線狀態 provider 決定 Timer 的建立與銷毀——例如 watch 一個「是否可跑背景刷新」的 provider（前景/桌面 hidden/播放中/Online），false 時 Timer 根本不建，true 時建立；恢復時用 `invalidateSelf` 補跑一次。這正好疊在第 5 節的 lifecycle 訊號與已定案的 Online/NoInterface/Unreachable 網路狀態上，不需要第三方排程套件介入 Dart 層。

---

## 套件版本速覽（查證日 2026-09-27，pub.dev API）

| 套件 | 最新版 | 最後發佈 | 平台 | 維護狀態 |
|------|--------|----------|------|----------|
| `workmanager` | 0.10.10 | 2026-09-07 | Android/iOS/macOS/Web（Linux 實驗性、**無 Windows**） | 活躍：連續發版（0.10.9 於 2026-08-20），open issues 僅 8 |
| `connectivity_plus` | 7.3.1 | 2026-07-23 | Android/iOS/Linux/macOS/Web/Windows | 活躍（plus_plugins 系列，fluttercommunity.dev） |
| `window_manager` | 0.5.2 | 2026-07-04 | Windows/Linux/macOS | 活躍（leanflutter.dev） |
| `tray_manager` | 0.7.0 | 2026-09-19 | Windows/Linux/macOS | 活躍；注意 0.6.0/0.6.1 已 retract |
| `disable_battery_optimization` | 1.1.2 | 2025-08-28 | 僅 Android | 低活動（一年未更新），只作引導使用者關閉電池最佳化的選配 |
