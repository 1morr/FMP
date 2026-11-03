# iOS 平台

## Goal

讓新版 App 在擁有者的 iPhone 上可以日常使用：dev 版能在 iPhone 與 iPad 上啟動、裝插件、搜尋、播放、背景與鎖屏播放、用鎖定畫面與控制中心控制、登入，來電之後自動續播。之後的功能從一開始就在 iOS 上做（擁有者 2026-10-24 定的順序：U → macOS → iOS → M6）。

## Background

- 現況：`lib/platform/platform.dart` 對 iOS 回 `PlatformCapabilities.none`，畫面只顯示「此平台尚未支援」（ADR 0009 §決定 4）。CI 的 iOS job 只建置，沒有模擬器測試。
- 研究（`research/`）：
  - `platform-inventory.md`：每個能力的現況、macOS 的檔案能不能共用、`app/ios/` 的現況。
  - `packages-ios.md`：套件在 iOS 的行為與模擬器實測（格式、標頭、ATS、keychain、路徑）。
  - `plugin-runtime-ios.md`：QuickJS 編進 iOS 的做法，背景時 JS 會被凍結。
  - `signing-distribution-ios.md`：免費與付費帳號的差別、這台 Mac 的簽章狀況、未簽章 IPA。
- 決定：ADR 0037。另外沿用：
  - ADR 0009：平台層與能力宣告；
  - ADR 0018：just_audio 與 audio_service；
  - ADR 0027：實機驗證；
  - ADR 0035 §決定 13：iPhone 安全區域與右滑返回；
  - ADR 0036：macOS 的做法（QuickJS、Podfile、本機簽章、媒體控制）。
- 擁有者 2026-11-04 已定：
  - 簽章先用免費 Apple ID，用這台 Mac 上已有的 Apple Development 憑證，從 Mac 安裝，7 天重裝一次；付費帳號留到 M9。
  - 本機簽名資訊不進 repo。
  - 支援 iPhone 與 iPad；iPad 在模擬器上驗。
  - 功能全部做完、模擬器驗過，再約擁有者在 iPhone 上一次驗。
  - Live Activity 歌詞移到 M7。
  - 技術細節照研究建議定案；會影響擁有者的取捨（例如設計稿等級的 UI 變動）要標出來。
- 環境：開發機是擁有者的 Mac（Apple Silicon、macOS 27、Xcode 27.1、Flutter 3.47.5）。模擬器有 iOS 27。驗證只用 dev（`com.personal.fmp.dev`）。

## Requirements

### R1 啟動與資料

- R1.1 dev、prod 都能在 iOS 模擬器啟動；dev 能在擁有者的 iPhone 上啟動。資料在 App 容器的 `Library/Application Support`，兩個 flavor 分開（ADR 0037 §決定 12）。
- R1.2 重設資料、從備份還原之後，App 收掉 Now Playing 再關閉，對話框請使用者自己再開；再開時資料是新的（§決定 10）。
- R1.3 舊資料：prod 沒有可找的位置；dev 的 `--fmp-legacy-dir` 照其他平台的規則運作（沒有舊憑證）。

### R2 插件

- R2.1 插件在 iOS 載入並執行，引擎和 Android、macOS 相同（§決定 3）。
- R2.2 背景播放中，插件能解析下一首的網址，不必回到前景。

### R3 播放

- R3.1 播 B 站 DASH 音訊、YouTube AAC、網易 MP3／FLAC、測試插件的 WAV（ADR 0018 §8 的里程碑實測）（§決定 7）。
- R3.2 B 站直播走 HLS。
- R3.3 回到主畫面或鎖屏後繼續播放與換曲（§決定 4）。
- R3.4 音訊中斷（§決定 8）：
  - 來電、鬧鐘、Siri 讓播放暫停，結束後系統說可以續播就自動續播；
  - 別的 App 開始播放時 FMP 暫停，不自己續播；
  - 拔耳機或藍牙斷線時暫停。

### R4 系統媒體控制

- R4.1 鎖定畫面與控制中心的 Now Playing 顯示曲名、作者、封面、進度（§決定 9）。
- R4.2 從鎖定畫面、控制中心、耳機按鍵能播放、暫停、上一首、下一首、拖進度。
- R4.3 重設資料或還原後，Now Playing 不殘留舊的曲目。

### R5 帳號

- R5.1 憑證存在 keychain：重開 App、同一個帳號重裝之後仍在；鎖屏時背景換曲也讀得到（§決定 6）。
- R5.2 App 內網頁登入可用；QR 登入與貼上 cookie 照常（§決定 11）。

### R6 外觀與操作

- R6.1 iPhone：頁面不進動態島與 home indicator，內頁能右滑返回，橫向可用（ADR 0035 §決定 13）。
- R6.2 iPad：直向、橫向、分割畫面時版面跟著寬度換，都能操作（§決定 14）。
- R6.3 iPad 的分享表從按下的按鈕彈出。
- R6.4 鍵盤不蓋住正在輸入的欄位。
- R6.5 字型清單：系統預設、蘋方-繁、蘋方-簡、Hiragino Sans；繁中不混入日文字形（ADR 0035 §決定 5）。
- R6.6 App 圖示是 FMP 的圖示；深色模式啟動時不閃白。
- R6.7 iPad 外接鍵盤的快捷鍵用 ⌘（ADR 0035 §決定 7）。
- R6.8 深淺色主題下，狀態列的文字看得清楚。

### R7 建置、簽章、CI、發版

- R7.1 iOS 建置不再改動追蹤中的檔案（提交 Podfile 與相關變動，§決定 5）。
- R7.2 Team ID 等本機簽名資訊不進 repo；模擬器與 CI 不簽，實機在這台 Mac 上簽（§決定 1）。
- R7.3 CI 的 iOS job 查 QuickJS 的符號，並在模擬器跑 `install_search_play_test.dart`（§決定 15）。
- R7.4 `app-release.yml` 產出未簽章的 `fmp-v{版本}-ios.ipa`，verify 檢查它（發版仍只能手動觸發，M9 才開，§決定 2）。

### R8 文件與驗證工具

- R8.1 `verify-on-device` skill 加 `references/ios.md`：模擬器的建置、安裝、啟動、操作（`orca emulator`）、讀 log、收尾；實機的簽章安裝與擁有者在場的步驟。
- R8.2 `app/AGENTS.md`、`.trellis/spec/app/platform/index.md` 的平台相關段落補上 iOS。

## Acceptance Criteria

- [ ] `implement.md` 的 PR 都已合併，CI 綠。
- [ ] ADR 0037 擁有者核可，狀態改為已採納；ADR 0021、0022、0026 有指向它的修訂。
- [ ] iOS 模擬器（iPhone）上的 dev 版，模式是重播加最少量的真實連線，回報列出請求：
  - [ ] 測試插件：搜尋、播放、佇列、背景換曲（回到主畫面）。
  - [ ] B 站 DASH、B 站直播 HLS、YouTube、網易各播一首或一間。
  - [ ] 網頁登入頁打得開，做到輸入帳密那一步。
  - [ ] 動態島、home indicator、右滑返回、鍵盤、橫向、深淺色。
  - [ ] 字型清單與繁中字形。
  - [ ] 重設資料後 App 關閉，再開是新的資料。
- [ ] iOS 模擬器（iPad）：直橫向、分割畫面、分享表的位置、外接鍵盤的 ⌘ 快捷鍵。
- [ ] 擁有者的 iPhone 上的 dev 版（release 模式），擁有者在場：
  - [ ] 鎖屏後背景播放至少一首換曲，換曲用到需要登入的插件。
  - [ ] 鎖定畫面與控制中心的 Now Playing：曲名、作者、封面、進度；播放、暫停、上下首、拖進度。
  - [ ] 來電（或 FaceTime 音訊）中斷，掛斷後自動續播。
  - [ ] 登入（網頁或 QR，由擁有者操作），重開 App、同一個帳號重裝後仍登入。
  - [ ] 拔耳機或斷開藍牙時暫停（擁有者有耳機時）。
- [ ] `milestones.md` 的 iOS 列：
  - 「AVPlayer 對 B 站 DASH 與直播 HLS」打勾；
  - 「Live Activity 本機逐行更新」移到 M7 的驗收；
  - iOS 列標成完成並寫結果。
- [ ] 擁有者以 dev 版在 iPhone 上試用後認可。

## Out of Scope

- Live Activity 與動態島歌詞（M7，ADR 0037 §決定 17）。
- 付費 Developer Program、TestFlight、ad hoc（M9）；以 SideStore／AltStore 實際安裝發出去的 IPA。
- 下載位置與「檔案」App 的可見性（M6，ADR 0020）。
- App 內更新（iOS 是 `none`，ADR 0022）。
- 插件開發工具（`pluginDevTools`）在 iOS 的支援；iPad 專屬的版面設計；CarPlay、Widget、Siri 與捷徑。
- macOS 的登入 WebView（等 CI 的 Xcode，ADR 0036 §決定 9）、Linux（`10-01-linux-platform`）。
