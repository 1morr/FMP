# macOS 平台的驗收紀錄（2026-10-28）

平台：macOS 27（Apple Silicon），開發機也就是擁有者的 Mac。只用 dev（`com.personal.fmp.dev`）。
驗的是合併後的 main（`4849f74f`）；各 PR 的實機驗證寫在各自的 PR 描述裡。

## PR

| PR | 內容 |
|---|---|
| #352 | 規劃：ADR 0036、任務文件、研究 |
| #353 | `fmp_quickjs`：Android 那份 QuickJS 橋接編進 macOS App；Mac 本機能跑完整 `flutter test` |
| #354 | 原生專案：不開沙盒、`LSMultipleInstancesProhibited`、ATS 媒體例外、Dock 叫回視窗、提交 Podfile |
| #355 | 平台層的 macOS 組裝（資料目錄、憑證、播放、字型、⌘、重啟…）；修正登入 keychain 的 `readAll` 回 `-50` |
| #356 | 紅綠燈標題列（高度跟系統標題區）、App 圖示 |
| #357 | 登入 WebView：CI 的 Xcode 26.6 建不過，關掉，保留 stub（ADR 0036 §決定 9 的結果） |
| #358 + fmp-plugins #28 | B 站直播在 macOS 走 h5 的 HLS |
| #359 | CI 的 macOS 整合測試、發版的 macOS zip |
| #360 | Now Playing 與媒體鍵（`audio_service`） |
| #361 | tooltip 的快捷鍵改由實際的按鍵組字（Mac 是 ⌘F、⌥⌘U） |
| #362 | `verify-on-device` 的 `references/macos.md` |

## 結果

模式：重播用測試插件；真實連線是匿名的，每個音源只做一次搜尋、播一首。

| 項目 | 結果 |
|---|---|
| 啟動、資料目錄 | 通過：`~/Library/Application Support/com.personal.fmp.dev`；fallback 字型 `PingFang TC` |
| 插件（QuickJS） | 通過：測試插件、B 站、YouTube、網易都載入並執行；Mac 主機的 `flutter test test/plugins/` 1080 過 |
| 測試插件播放 | 通過：`Track audible` 594ms |
| B 站隨選（DASH，mp4/aac） | 通過：`Track audible` 13.5 秒。同一時間封面下載也逾時，那時網路慢 |
| B 站直播（HLS） | 通過：第一次開流 20 秒後 `-1008`，直播恢復重新解析，第二次 5 秒內播放 |
| YouTube（mp4/aac） | 通過：2.6 秒 |
| 網易（mp3） | 通過：1.6 秒；進度 0:05／3:04 正常，just_audio#1599 沒有出現。前兩首是 VIP 曲（`fee 1`），是內容限制 |
| 憑證（login keychain） | 通過：`integration_test/secure_storage_test.dart -d macos` 實機寫、讀、覆寫、刪除、`deleteAll` |
| 單一實例、Dock 叫回 | 通過：`open`、`open -n` 都回到同一個行程；最小化後再開，視窗回來 |
| 重設資料後自己重啟 | 通過：新行程 1 秒內寫出 `App started`；有 Now Playing 時也一樣 |
| 標題列 | 通過：紅綠燈中心與列的中心差 0.25pt；真的滑鼠事件可以拖曳、雙擊縮放（系統設定「填滿」，再雙擊不還原，Finder 也一樣）；全螢幕進出 |
| 快捷鍵、字型 | 通過：⌘F、⌥⌘U；tooltip「下一首（⌘→）」；字型清單有蘋方-繁、蘋方-簡、Hiragino Sans |
| Windows 不受影響 | 通過：main 在 Windows 電腦（經 SSH）建置，標題列照舊（36dp、三顆鈕） |
| Now Playing 畫面、媒體鍵 | **待擁有者看**：macOS 27 不讓第三方行程讀 Now Playing；按全域媒體鍵可能叫醒 Music |
| 登入（QR）、重開後憑證仍在 | **待擁有者操作**：要擁有者掃碼 |
| 擁有者以 dev 版試用 | **待擁有者** |

## 之後要做或要注意

- 登入 WebView：等 CI 的預設 Xcode ≥ 27（GitHub 目前只有預覽映像）或上游修好，拿回 #357 的做法，分支還在。在那之前，macOS 的 YouTube 登入只能貼上 cookie。
- 發版的 macOS zip：
  - Release 的簽章帶 `get-task-allow`，是 Xcode 的「Sign to Run Locally」注入的。沒有公證所以不擋使用，正式發版前要決定要不要在 Release 設 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`。
  - `build-macos` job 要到第一次發版才會真的在 runner 上跑。
- 直播第一次開流的 `-1008`：只見過一次。之後的里程碑冒煙測試再播幾間，看是不是常態。
- 設定「格式偏好」在 macOS 也顯示「Opus 優先」，但 macOS 不播 WebM/Opus，選它不會有作用，等同 AAC。是否在沒有 Opus 的平台藏起來，留給 UI 的後續。
- iOS 平台任務沿用 `fmp_quickjs`（加 `ios` 的 podspec）、login keychain 的做法要重新看（iOS 一定是沙盒，有 data protection keychain）。
