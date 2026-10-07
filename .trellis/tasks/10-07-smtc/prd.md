# M2 PR 16b：系統媒體控制（Windows SMTC）

依據：M2 `design.md` §8.1、§8.2、§8.4；ADR 0018 §決定 1、§決定 8；ADR 0009 §決定 2、§決定 7（平台套件只在實作檔 import）。依賴 PR 16a（Android 與 `NowPlayingPublisher`）。

## 目標

Windows 上，系統的媒體鍵與音量浮層的媒體卡片（SMTC）可以：
- 看到曲名、上傳者、封面；
- 播放／暫停、上一首、下一首；
- 停止＝暫停，照 16a 擁有者的決定。

## 要做的

### 平台層（`lib/platform/media_controls/media_controls_windows.dart`）

- **套件**：`smtc_windows` 1.1.0，pub.dev 上的當前 stable。
  - 只准在這個實作檔 import，`platformPackages` 加上它。lint `fmp_layer_imports` 擋其他位置，附雙向測試，照 `audio_service` 那一列的寫法。
  - `pubspec.yaml` 釘版本並註明原因：它要從原始碼編 Rust，見 design §8.4。
- **實作 `SystemMediaControls`**：
  - `publish(NowPlaying)` 轉成 SMTC 的 metadata（曲名、上傳者、封面）、timeline（位置、時長）、播放狀態與按鈕的啟用。
  - SMTC 的按鍵轉成 `MediaCommand`：播放、暫停、上一首、下一首、停止（`MediaStop`，控制器照 16a 當暫停）。
  - 沒有 seek。
  - `dispose` 關掉 SMTC。
- **轉換寫成純函數**，例如 `smtcMetadataOf`、`smtcTimelineOf`、`smtcStatusOf`、`smtcButtonsOf`，可以在 `flutter test` 裡單元測試，不建 SMTC 實例。
- **`MediaPhase.idle`**（啟動恢復後還沒播）：SMTC 停用或狀態設成 closed／stopped，媒體卡片不顯示，照 16a「還沒按播放不顯示通知」。
- **封面**：
  - 先交快取檔的 `file:///` 網址（`Uri.file(artworkFile.path)`）。交出前一律以 `Uri.tryParse` 檢查，不合法就不帶封面：`smtc_windows` 對不合法的網址會 panic（design §8.4）。
  - 實機若 `file:///` 不顯示封面，主對話再決定改交原本的 `https` 網址。這個 PR 先實作 `file:///` 這條。
- **能力宣告**：Windows 宣告 `PlatformCapabilities.mediaControls = MediaControlsSupport(supportsSeek: false, …)`。
  - 組裝點 `platform.dart` 的 Windows 分支給 factory。
  - 初始化失敗照 Android：記 log、宣告改為沒有，App 照常啟動。
- **位置的推送頻率**：`MediaControlsSupport` 加一個欄位，例如 `positionRefresh`（`Duration?`）。
  - Android 是 `null`：系統依速度自己外推，照舊只在狀態改變與 seek 時推。
  - Windows 是 5 秒：SMTC 的 timeline 不會自己前進。
  - `NowPlayingPublisher` 播放中依這個值，從進度 stream 節流推位置（design §8.2「Windows 的 timeline 播放中最多每 5 秒推一次，從進度 stream 節流，不是計時器」）。
  - 欄位名稱可以自己取，但只加這一個。

### 文件

- `app/AGENTS.md`：
  - § 驗證：Windows 建置要有 `rustup`（`smtc_windows` 每次建置都從原始碼編 Rust），CI 的 Windows runner 內建。
  - § 平台層「系統媒體控制」：Windows 的實作、`supportsSeek: false`、位置節流、封面的 `file:///` 與 `Uri.tryParse`、idle 不顯示，每條附閘門。
  - 驗證表「系統媒體控制」那一列加上 Windows 的實機項目。
- `.trellis/spec/app/platform/index.md`、`.trellis/spec/app/playback/index.md`：需要時更新。
- `verify-on-device` 的 `references/windows.md`：已有 `smtc_probe.ps1` 的段落，對照實際行為更新。

## 驗收

- **轉換函數**的單元測試：
  - 曲名、上傳者、時長、位置；
  - 有封面、沒封面、路徑轉出不合法網址時不帶封面；
  - 各 `MediaPhase` 與 `playing` 的狀態；
  - 按鈕依 `NowPlaying.controls` 啟用；
  - 按鍵到 `MediaCommand` 的對應（含停止）。
- **`platform_test.dart`**：
  - Windows 宣告有 `mediaControls`、`supportsSeek` 為假、`positionRefresh` 為 5 秒；
  - Android 的 `positionRefresh` 為空；
  - Windows 初始化失敗時宣告為沒有；
  - 未驗證平台仍全部為沒有。
- **`now_playing_publisher_test.dart`**：
  - 有 `positionRefresh` 時，播放中位置最多每 5 秒推一次，用 fakeAsync 推進度 stream；
  - 暫停時不推；
  - 沒有 `positionRefresh` 時照舊，既有案例不變。
- **lint**：`fmp_layer_imports` 擋 `lib/platform/media_controls/` 以外 import `smtc_windows`，加報與不報的測試；`tool/lint_sentinel.dart` 照舊全報。
- **本機**：
  - `dart format`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全綠；
  - `packages/fmp_lints` 的 `dart test`、`dart run tool/lint_sentinel.dart`；
  - `flutter build windows --flavor dev` 與 `--flavor prod` 成功（會編 Rust）；
  - Windows 跑 `install_search_play_test.dart`；
  - `flutter build apk --flavor dev --debug` 仍成功。
- **CI**：Windows 建置與整合測試綠。缺 Rust 時才在 `ci.yml` 加步驟。
- **實機**（Windows，主對話做）：
  - 模式是重播。封面要用真實 B 站時，另外做一次最少操作：搜尋一次、播一首。
  - 播放中按鍵盤媒體鍵：播放／暫停、下一首；
  - 音量浮層的媒體卡片有曲名、封面；
  - 暫停與恢復時卡片同步；
  - 啟動恢復後還沒播時沒有卡片；
  - 記錄 `file:///` 封面是否可用，結論寫進 `app/AGENTS.md`。

## 範圍外

- SMTC 的 seek（套件不支援）。
- Linux（MPRIS）、macOS：各自的平台任務。
