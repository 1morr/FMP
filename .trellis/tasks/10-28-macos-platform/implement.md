# macOS 平台：執行計畫

每個 PR 都要讓 repo 可運作，合併前 CI 綠。設計見 `design.md`，需求見 `prd.md`。

## 共同規則

- 每個 PR 都在 `app/` 跑 `app/AGENTS.md` § 驗證的第一列。完整的 `flutter test`：
  - PR 1 合併前，用 `tool/linux_test.sh`；
  - PR 1 之後，Mac 本機也行（插件測試能跑）。
- 有 UI 或平台行為的 PR，在這台 Mac 上實機驗 dev：
  - 用 `orca computer` 操作，讀回畫面才算數；
  - 回報寫明平台、模式（重播或真實）、做了哪些請求。
  - 改到平台各自實作的才另驗 Windows（ADR 0027）。
- 主工作區的 `app/ios/` CocoaPods 變動不動、不提交；只 stage 明確的路徑，不用 `git add -A`。
- 實作交給 sonnet 子代理時，附 `design.md` 對應的節與這裡的驗收；遇到計畫外的設計決定就停下回報。

## PR 0：文件

- ADR 0036；ADR 0014、0009 的修訂行；任務的 `prd.md`、`design.md`、`implement.md`、`research/`。
- 驗收：只改文件，CI 只跑文件與舊 App 的 job（照路徑分）。

## PR 1：`fmp_quickjs`（design §2）

- 新套件 `app/packages/fmp_quickjs/`：
  - 原始碼、`LICENSE`、`SOURCE.md`、`src/fmp_extras.c`；
  - podspec（macOS）、空的 Swift plugin class；
  - `test/symbols_test.dart`。
- `app/pubspec.yaml`：依賴它，加入 workspace。
- `test/support/quickjs.dart`：macOS 主機編譯並預先載入。可行的話也預先載入 `libisar`。
- 驗收：
  - Mac 本機 `flutter test test/plugins/` 全過；
  - `flutter build macos --flavor dev --debug` 成功，`nm -gU` 看得到 `jsNewRuntime` 等符號在 App 的 framework 裡；
  - Linux 機器的完整 `flutter test` 照舊全過（不受影響）；
  - `app/AGENTS.md` § 驗證改寫 macOS 能跑的範圍。

## PR 2：原生專案（design §3）

- entitlements（不開沙盒）、`Info.plist` 兩個鍵、`AppDelegate` 的 reopen、Podfile 的六個 configuration。
- 提交 `macos/Podfile`、`Podfile.lock`、xcconfig、pbxproj、workspace 的 CocoaPods 變動。只提交 `app/macos/`，`app/ios/` 不動。
- `apple_identity_test.dart` 補檢查與變異案例。
- 驗收：
  - 乾淨的副本建 dev debug 與 prod release，`git status` 沒有 `app/macos/` 的變動；
  - `apple_identity_test` 在 Mac 本機綠。
  - App 這時仍顯示「此平台尚未支援」，因為能力還沒宣告。

## PR 3：組裝點與核心能力（曳光彈，design §4–§6）

- `_macos(...)` 分支，含以下能力：
  - 資料目錄、app info、快取、網路介面、憑證（`MacOsOptions`）；
  - 檔案、分享、開網址、字型、修飾鍵、播放（just_audio，格式先不含 `hls`）；
  - 舊資料 locator、重啟、單一實例宣告。
- 這個 PR 先不接三項：
  - 系統媒體控制：`mediaControls: null`，PR 4 接上；
  - 自繪標題列：`customTitleBar: false`，系統標題列，PR 5 接上；
  - 登入 WebView：`loginWebView: false`，PR 6 接上。
- `platform_test.dart`：macOS 的組裝與宣告。
- 快捷鍵提示的符號（design §4 最後一點），若需要。
- `verify-on-device` 的 `references/macos.md` 初版：建置、啟動、`--fmp-dev-plugin`、log 位置、`orca computer` 操作、收尾。
- 實機驗收，dev、重播：
  - 啟動；資料目錄在 `~/Library/Application Support/com.personal.fmp.dev`；
  - 測試插件搜尋並播放一首；
  - 設一個值重開後仍在；憑證寫入再讀回（Debug 頁或測試插件的帳號）；
  - 重設資料後自己重啟；
  - 再開一次回到同一個實例；
  - ⌘ 快捷鍵；字型清單。

## PR 4：系統媒體控制（design §9）

- 抽出 `media_controls_audio_service.dart`；新增 `media_controls_macos.dart`；在 `_macos` 接上 `mediaControlsFactory`。
- 驗收：
  - Android 的媒體控制測試照舊綠；Android 模擬器上通知與媒體鍵照舊，因為改到 Android 檔；
  - Mac 實機：控制中心的 Now Playing 有曲名、作者、封面、進度；播放、暫停、上下首、拖進度都有效；F8 媒體鍵有效；
  - 重設資料重啟後 Now Playing 不殘留。

## PR 5：Mac 標題列（design §8）

- `WindowChrome` 加 `captionButtons`、`leadingInset`；Windows 實作回 `drawn` 與 0。
- `MacosWindowChrome`；`WindowTitleBar` 的 `systemLeading` 版型；`MainFlutterWindow` 讓紅綠燈垂直置中；有白閃的話一起修啟動閃爍。
- widget 測試：
  - `systemLeading` 沒有三顆鈕、「FMP」置中、開頭留白跟著 `leadingInset`；
  - `drawn` 的測試照舊。
- 驗收：
  - Mac 實機：紅綠燈置中（截圖量）、拖曳、雙擊縮放一次、全螢幕進出、深淺主題、播放頁頂端拖曳；
  - Windows 改到共用的 `WindowTitleBar`，經 SSH 驗一次標題列與三顆鈕（verify-on-device 的 Windows 遠端做法）。

## PR 6：登入 WebView（design §7）

- 刪掉 macOS stub；`InAppLoginWebView.macos()`；改 `webview_stub_test`；`loginWebView: true`。
- 驗收：
  - CI 的 macOS 建置過；建不過就照 design §7 最後一點收尾。
  - Mac 實機：開網頁登入頁，讀得到頁面；登入由擁有者操作，做到輸入帳密那一步就停，問擁有者時間。
  - 登出後 cookie 清掉。

## PR 7：直播 HLS（design §10）

- fmp-plugins：
  - 錄 h5 的 `playUrl` 回應（真實連線、一次）；
  - `resolveLive` 依 `formats` 選；
  - `checks.json` 加案例；升版。
  - 在 fmp-plugins 開 PR、合併。
- FMP：
  - macOS 的 `formats` 加 `hls/aac`；
  - 有需要時 `JustAudioBackend` 對 HLS 用 `HlsAudioSource`；
  - 測試插件的內附副本（若 repo 內有 bilibili 的 fixture 副本）照 `app/AGENTS.md` 的同步規則更新。
- 驗收：Mac 實機播一間開播中的 B 站直播（真實連線：一次 `room_init`、一次 `playUrl`、HLS 的分段）。

## PR 8：CI 與發版（design §11）

- `ci.yml` 的 macOS 整合測試；`app-release.yml` 的 macOS zip；`verify_release_assets` 與它的測試。
- 驗收：
  - CI 的 macOS job 綠，含整合測試；
  - actionlint 過；
  - 本機以 verify 檢查一次自己打的 zip。

## PR 9：驗收

- 按 `prd.md` 的 Acceptance Criteria 在 Mac 上走完整流程，至少一個真實連線（B 站 DASH、直播、YouTube、網易各一首或一間），紀錄寫在 `research/macos-acceptance.md`。
- 修正驗收找到的問題（各自的修正 PR）。
- `milestones.md`：macOS 列標成完成並寫結果；§8 的三項照 `prd.md` 處理；`.trellis/spec/app/platform/index.md` 與 `app/AGENTS.md` 收尾。
- 擁有者以 dev 版試用後認可，才算完成。

## 回退點

- 每個 PR 獨立可回退。
- PR 2 回退會讓本機建置再次改動追蹤中的檔案，不影響功能。
- PR 3 回退後 macOS 回到「此平台尚未支援」。
