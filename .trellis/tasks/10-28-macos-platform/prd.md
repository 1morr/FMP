# macOS 平台

## Goal

讓新版 App 在 Mac 上可以日常使用：dev 版與 prod 版都能在 Apple Silicon 的 Mac 上啟動、裝插件、搜尋、播放、登入、用系統媒體控制，外觀和 Windows 一致（自繪標題列，保留紅綠燈）。之後的功能從一開始就在 macOS 上做（擁有者 2026-10-24 定的順序：U → macOS → iOS → M6）。

## Background

- 現況：`lib/platform/platform.dart` 只有 Android、Windows 的實作，macOS 宣告 `PlatformCapabilities.none`，畫面只顯示「此平台尚未支援」（ADR 0009 §決定 4）。
- 研究（`research/`）：
  - `platform-inventory.md`：每個能力的現況與 macOS 要做的事。
  - `packages-macos.md`：套件在 macOS 的行為，含 ad-hoc 簽章加沙盒的實測。
  - `plugin-runtime-macos.md`：插件引擎在 macOS 的狀況。`flutter_js` 在 macOS 沒有 QuickJS，插件一載入就失敗。
- 決定：ADR 0036。另外沿用：
  - ADR 0009：平台層與能力宣告；
  - ADR 0018：just_audio 與 audio_service；
  - ADR 0022：未公證的 zip；
  - ADR 0027：實機驗證；
  - ADR 0035：Mac 標題列與快捷鍵。
- 擁有者 2026-10-28 說「繼續，不用問我」：照研究的建議定案，結果回報給擁有者。
- 環境：開發機就是擁有者的 Mac（Apple Silicon、macOS 27、Xcode 27.1、Flutter 3.47.5）。實機驗證在這台機器上做，只用 dev（`com.personal.fmp.dev`）。

## Requirements

### R1 啟動與資料

- R1.1 dev、prod 都能啟動，資料在 `~/Library/Application Support/<bundle id>`，兩者分開（ADR 0036 §決定 2）。
- R1.2 不開 App Sandbox；網路、檔案對話框、分享、開網址都能用。
- R1.3 單一實例：再開一次會回到已在執行的那一個；沒有視窗時點 Dock 圖示會把視窗叫回來（§決定 4）。
- R1.4 重設資料、從備份還原之後 App 自己重新啟動（§決定 5）。
- R1.5 舊資料：prod 沒有可找的位置；dev 的 `--fmp-legacy-dir` 能匯入從別的平台複製來的資料夾（沒有舊憑證）。

### R2 插件

- R2.1 插件在 macOS 載入並執行，引擎和 Android 相同（ADR 0036 §決定 1）。
- R2.2 Mac 上的 `flutter test` 能跑插件執行環境與契約測試。

### R3 播放與媒體控制

- R3.1 just_audio 播放 B 站 DASH 音訊、YouTube AAC、網易 MP3／FLAC、測試插件的 WAV（ADR 0018 §8 的里程碑實測）。
- R3.2 B 站直播在 macOS 走 HLS（插件依平台宣告的格式選）；Windows、Android 照舊。
- R3.3 Now Playing（控制中心、選單列）顯示曲名、作者、封面、進度；媒體鍵與控制中心的播放、暫停、上下首、拖進度都有效。

### R4 帳號

- R4.1 憑證存在 login keychain，重開 App 之後仍在（§決定 3）。
- R4.2 App 內網頁登入可用；若 CI 的 macOS runner 建不過 `flutter_inappwebview_macos`，改為宣告沒有，帳號頁只剩 QR 與貼上 cookie（§決定 9）。

### R5 外觀與操作

- R5.1 自繪標題列：36dp、主題色，紅綠燈在左且垂直置中，「FMP」置中；拖曳、雙擊縮放；全螢幕時不預留紅綠燈的空間（ADR 0035 §決定 6、ADR 0036 §決定 6）。
- R5.2 快捷鍵用 ⌘，開佇列 ⌥⌘U；提示文字用 ⌘ ⌥ ⇧ 符號（ADR 0035 §決定 7）。
- R5.3 字型清單：系統預設、蘋方-繁、蘋方-簡、Hiragino Sans；繁中 fallback 蘋方（ADR 0035 §決定 5）。

### R6 建置、CI、發版

- R6.1 macOS 建置不再改動追蹤中的檔案（提交 Podfile 與相關變動，§決定 10）。
- R6.2 CI 的 macOS job 跑 `install_search_play_test.dart -d macos`。
- R6.3 `app-release.yml` 產出 `fmp-v{版本}-macos.zip`，verify 檢查它（發版仍只能手動觸發，M9 才開）。

### R7 文件與驗證工具

- R7.1 `verify-on-device` skill 加 `references/macos.md`：建置、啟動、操作（`orca computer`）、讀 log、收尾。
- R7.2 `app/AGENTS.md`、`.trellis/spec/app/platform/index.md` 的平台相關段落補上 macOS。

## Acceptance Criteria

- [ ] `implement.md` 的 PR 都已合併，CI 綠。
- [ ] 擁有者的 Mac 上 dev 版，模式是重播加最少量的真實連線，回報列出請求：
  - [ ] 測試插件：搜尋、播放、佇列、Now Playing、媒體鍵。
  - [ ] B 站 DASH、B 站直播 HLS、YouTube、網易各播一首或一間。
  - [ ] 登入：網頁登入或 QR，由擁有者操作；重開 App 之後憑證仍在。
  - [ ] 標題列、紅綠燈、全螢幕、單一實例、Dock 叫回視窗、重設後自己重啟。
  - [ ] 快捷鍵與字型。
- [ ] Mac 上 `flutter test` 跑插件測試通過（`test/plugins/`）。
- [ ] ADR 0036 已寫入；ADR 0014、0009 有指向它的修訂。
- [ ] `milestones.md` 的 macOS 列與兩項 §8 處理好：
  - 「AVPlayer 對 B 站 DASH 與直播 HLS」打勾；
  - 「桌面歌詞」移到 M7；
  - 「更新不帶 quarantine」移到 M9。
- [ ] 擁有者以 dev 版在 Mac 上試用後認可。

## Out of Scope

- 桌面歌詞（M7）、托盤、全域快捷鍵、關閉後留在背景（M8）、應用內更新與 quarantine（M9）、付費簽章與公證（ADR 0022）。
- iOS（下一個平台任務，沿用 `fmp_quickjs`）、Linux（`10-01-linux-platform`）。
- `app/ios/` 的 CocoaPods 檔：iOS 平台任務照 §決定 10 的做法處理，這個任務不動。
