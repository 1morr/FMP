# M2 PR 16a：系統媒體控制（Android）與返回鍵

M2 `design.md` §8.1–§8.3、§9.1；決定 7；ADR 0018 §決定 1、§決定 8；ADR 0009 §決定 2、§決定 4。依賴 PR 4（封面快取）與 PR 10（控制器的佇列操作）。Windows 的 SMTC 在 PR 16b。

## 目標

在 Android 上：
- 播放時，通知與鎖定畫面顯示曲名、上傳者、封面、進度條，並有上一首／播放暫停／下一首；
- 耳機、藍牙、車機的媒體鍵可以操控 App；
- 返回鍵不再直接結束 App：不在第一個分頁時回到「搜尋」，在第一個分頁時把 App 退到背景，音樂照常播。

## 要做的

### 平台層 `lib/platform/media_controls/`（design §8.1）

- **`media_controls.dart`**：介面 `SystemMediaControls`。
  - `publish(NowPlaying)`；
  - `commands` stream：播放、暫停、上一首、下一首、seek、停止；
  - `dispose`。
  - `NowPlaying` 是不可變的值物件：曲名、上傳者、時長、封面本機檔、是否在播、位置、速度、按鈕。
- **`media_controls_android.dart`**：以 `audio_service` 實作，設定照 design §8.3：
  - 版本：design 寫 0.18.19。加依賴時到 pub.dev 核對當前 stable，並以 pub-cache 原始碼確認 design 引用的行為仍成立：`file://` 的 `artUri` 直接交給平台，`getFlutterEngine` 用 `createDefault()`；
  - `androidStopForegroundOnPause: true`；
  - 通知按鈕：上一首、播放／暫停、下一首；
  - `systemActions` 含 seek，Android 13 起的通知才有進度條；
  - 不放快轉、倒轉；
  - 不傳 `cacheManager`。
- **能力宣告**：`PlatformCapabilities.mediaControls`，型別帶 `supportsSeek`（Android 為真）。
  - 照 ADR 0009 §決定 4，連同實作一起加欄位。Windows、其他平台在這個 PR 宣告為沒有，16b 再給 Windows。
- **初始化**：`main()` 在開好資料庫之後、`runApp` 之前初始化，以 provider 注入。
  - 初始化失敗時記 log，宣告改為沒有，App 照常啟動。
- `audio_service` 只准在 `lib/platform/`（lint 擁有者表裡已經有）；要改擁有者表時照 lint spec 寫雙向案例。

### `NowPlayingPublisher`（`lib/playback/now_playing_publisher.dart`，design §8.2）

- **輸入**：控制器的狀態、佇列、進度、播放能力；**輸出**：`NowPlaying`。
- **推送規則**：
  - 值改變才推，推送依序排隊、不重疊；
  - 位置只在狀態改變與 seek 時推（系統依速度自己外推）；
  - 「Windows 每 5 秒節流」留給 16b，這個 PR 不做。
- **按鈕依能力推導**：
  - 有下一首（或循環全部）才有「下一首」；
  - `Retrying`、`Loading` 時播放鍵是「暫停」；
  - `Idle` 而佇列有歌時可以播放。
- **啟動恢復後還沒按播放（`Idle`）時不顯示通知**：對 `audio_service` 推 `processingState: idle`，不搶前景。與「啟動時不解析、不出聲」一致。
- **封面**：經 `artworkCacheManagerProvider`（design §4.3）拿本機檔，交 `file://`。拿不到就不帶封面，不影響其他欄位。
- **系統指令一律經控制器**，控制器是唯一入口：
  - 播放 → `play`，暫停 → `pause`；
  - 上一首、下一首 → `previous`、`next`；
  - seek → `seek`；
  - **停止 → 當作暫停**（擁有者決定：位置與佇列都保留，之後按播放從原處繼續）。

### Android 原生（design §8.3、§9.1）

- **`AndroidManifest.xml`**：
  - 權限：`WAKE_LOCK`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`；
  - `com.ryanheise.audioservice.AudioService` 服務：`foregroundServiceType="mediaPlayback"`、`exported`、`MediaBrowserService` intent filter；
  - `MediaButtonReceiver`；
  - **不加 `POST_NOTIFICATIONS`**。
- **`MainActivity`** 改繼承 `AudioServiceActivity`，並覆寫兩處：
  - **`provideFlutterEngine`**：快取裡沒有引擎時，自己建一個，以 `executeDartEntrypoint(DartEntrypoint.createDefault(), getDartEntrypointArgs())` 啟動，放進 `FlutterEngineCache`，鍵用 `AudioServicePlugin.getFlutterEngineId()`。這是為了保住 `--fmp-dev-plugin`，也就是 `dart_entrypoint_args` 這個開發入口。
  - **`popSystemNavigator`**：`moveTaskToBack(true)` 並回傳 `true`。
  - 兩處都在註解寫明理由。

### 外殼的返回鍵（design §9.1）

- `PopScope(canPop: 目前是第一個分頁)`：不在第一個分頁時，`onPopInvokedWithResult` 換回第一個分頁；在第一個分頁時放行。
- Dart 端不判斷平台；Windows 沒有返回鍵，不受影響。

### 文件

- `app/AGENTS.md` § App 身分或 § 平台層：寫明 `MainActivity` 兩個覆寫的理由、它們沒有自動閘門、要實機驗。另寫 publisher 的推送規則與閘門。
- 需要時更新 `.trellis/spec/app/{platform,playback}/` 與 `verify-on-device` 的 Android 參考。例如 `audio_service` 之後若改變帶參數啟動的方式，就要更新參考。

## 驗收

- **`NowPlayingPublisher` 的測試**（假平台實作）：
  - 值不變不推；
  - 推送依序、不重疊；
  - 位置只在狀態改變與 seek 時推；
  - 按鈕推導的各種情況；
  - `Idle` 恢復狀態是 idle；
  - 封面拿不到時其他欄位照推。
- **系統指令經控制器**：六種指令各有測試，停止 = 暫停。
- **`test/identity/android_manifest_test.dart`**：以 XML 解析斷言三個權限、服務的屬性與 intent filter、receiver，以及沒有 `POST_NOTIFICATIONS`。要做雙向驗證：缺一項會紅；改屬性順序或縮排不紅。
- **`platform_test.dart`**：Android 宣告 `mediaControls` 且 `supportsSeek: true`；其他平台沒有；初始化失敗時宣告為沒有。
- **外殼返回的三種情況**：widget 測試以 `handlePopRoute` 模擬。
  - 在第二、第三個分頁按返回：回到第一個分頁；
  - 在第一個分頁按返回：放行。
- **本機**：`dart format`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全綠，`packages/fmp_lints` 與 `lint_sentinel` 照常。
- **整合測試**：
  - `install_search_play_test.dart` 在 Windows 跑；
  - `audio_backend_contract_test.dart` 在 Android 模擬器跑，確認在 `AudioServiceActivity` 下照常執行。
- **APK**：`flutter build apk --flavor dev --debug` 成功。新增的原生庫以 `zipalign -c -P 16` 檢查 16KB 對齊（design §8.3）。
- **實機**（Android 模擬器，重播／測試插件）：
  1. 以 `--fmp-dev-plugin` 啟動，確認測試插件仍裝得上（`provideFlutterEngine` 覆寫有效）；
  2. 播放中下拉通知：曲名、封面、上一首／播放／下一首都在，進度條可以拖；
  3. 鎖定畫面的控制；
  4. `dumpsys media_session` 有 FMP 的工作階段；
  5. 返回鍵：在「歷史」按返回會回到「搜尋」；再按一次，App 退到背景、音樂繼續；從最近使用的應用程式回來，狀態不變；
  6. 以 `adb shell input keyevent` 送 `MEDIA_PLAY_PAUSE`、`MEDIA_NEXT`、`MEDIA_STOP`：停止等於暫停，之後播放從原處繼續；
  7. 重開 App、恢復後還沒按播放時，沒有媒體通知。
- **Windows**：沒有功能改動，只跑整合測試，並確認建置不受影響。

## 範圍外

- Windows SMTC（PR 16b）。
- 播放頁開著時的返回（PR 18a 之後再驗一次）。
- 快轉、倒轉按鈕；`POST_NOTIFICATIONS`（M6）。
