# macOS 桌面版

macOS 平台任務（ADR 0036）之後的實機驗證。開發機就是 Mac，直接在本機跑。只用 dev（`com.personal.fmp.dev`，
選單列與 Dock 顯示 `FMP Dev`）。

## 建置與啟動

在 `app/`：

```bash
flutter build macos --flavor dev --debug
open build/macos/Build/Products/Debug-dev/fmp.app --args --fmp-dev-plugin=<app 的絕對路徑>/test/fixtures/plugins/test_plugin/test_plugin.js
```

- **單一實例**（`Info.plist` 的 `LSMultipleInstancesProhibited`）：已經有 FMP Dev 在跑時，`open` 只會把它帶到前景，
  參數也不會送到它。先 `pgrep -fl "Debug-dev/fmp.app/Contents/MacOS/fmp"` 看是哪個 worktree 的；只關自己開的
  （`kill <pid>`），別的 worktree 或子代理的整合測試也會開同一個 dev App，而且共用同一個資料目錄。
- 直接執行 `.app/Contents/MacOS/fmp` 不經 LaunchServices，擋不住第二個實例，也就會有兩個行程寫同一個資料庫：只在要讀
  stdout（原生 `NSLog`）時這樣跑，而且先確認沒有別的實例。
- 資料與 log 在 `~/Library/Application Support/com.personal.fmp.dev/`（不開沙盒，ADR 0036 §決定 2）：
  `logs/fmp.jsonl`、`fmp.db`。格式見 `runtime-state.md`。
- 整合測試：`flutter test integration_test/<檔>.dart -d macos --flavor dev`，一次一個檔。它會蓋掉
  `build/macos/Build/Products/Debug-dev/fmp.app`，之後要手動操作就重建一次。
  `integration_test/secure_storage_test.dart` 驗真的 keychain（只在本機跑，CI 不跑）。
- `flutter run -d macos --flavor dev` 可以熱重載，要讓它跨對話留著就放進 Orca terminal（SKILL.md § 1）。

## 讀畫面、操作

Flutter 的語意樹不經 macOS 的無障礙 API 暴露，`orca computer get-app-state --app com.personal.fmp.dev` 只看得到視窗與
紅綠燈。以截圖讀畫面，以座標操作：

- 截圖在結果的 `screenshot.path`。`scale` 是截圖像素與視窗點的比：動作座標＝截圖像素 ÷ `scale`
  （Retina 的 800 點寬視窗是 1600 像素寬、`scale` 2；全螢幕大小的視窗會縮成 `scale` 0.5）。
- 視窗大小會影響版面（寬時設定頁是左右兩欄）。座標每換一次畫面就重讀一次截圖。
- `orca computer click` 對 Flutter 的內容有效；**對系統的標題區（拖曳、雙擊）無效**，要用真的滑鼠事件：
  `scripts/macos/mouse.swift`（編一次，全域座標＝`System Events` 讀的視窗位置＋視窗內座標）。真的事件會移動使用者的
  游標，送之前先把 FMP 帶到最前面（下面的 `frontmost`），否則會點到擋在前面的別的 App。
- **按鍵**：`orca computer hotkey`／`press-key` 送不到 Flutter。用 System Events：

  ```bash
  osascript -e 'tell application "System Events" to set frontmost of (first process whose bundle identifier is "com.personal.fmp.dev") to true' \
            -e 'delay 0.3' -e 'tell application "System Events" to keystroke "f" using command down'
  ```

  `key code 49` 是空白鍵（播放／暫停），`key code 53` 是 Esc。
- **打字**：擁有者的輸入法可能是中文，`keystroke "https://…"` 會被轉成中文字。改用剪貼簿貼上，先存再還原使用者的剪貼簿：
  `pbpaste > <暫存目錄>/clip.bak; printf '%s' '<文字>' | pbcopy;`（⌘V）`; pbcopy < <暫存目錄>/clip.bak`。輸入框若已經有
  組字中的文字，先送 Esc 再 ⌘A、Delete。
- 視窗位置與大小：`osascript -e 'tell application "System Events" to get {position, size} of window 1 of (first process whose bundle identifier is "com.personal.fmp.dev")'`；
  全螢幕用 `set value of attribute "AXFullScreen" of window 1 … to true/false`。設定位置與大小會被拒（-10003），要換大小就請擁有者拖。
- 量位置（例如紅綠燈是否在標題列正中間）：截圖用 Pillow 讀像素（`python3 -m pip install --user pillow`）。

## 讀不到的東西

- **Now Playing**：macOS 27 不讓第三方行程讀（MediaRemote 回空、pid 0），System Events 也讀不到控制中心。控制中心與選單列的
  畫面、媒體鍵，請擁有者看。不要送全域媒體鍵：FMP 不是目前的 Now Playing App 時，它會叫醒擁有者的 Music。
- 系統的 log（`log show`）裡 mediaremoted 的內容是私密的，讀不到 App 名稱。

## 收尾

關掉自己開的 FMP Dev（`kill <pid>`，確認路徑是自己的 worktree）。真實連線的驗證完之後暫停播放：聲音從擁有者的 Mac
放出來。dev 的資料留著不清，除非是驗證本身改的（例如重設資料）。截圖只存暫存目錄，回報只寫文字觀察與 `<資料目錄>`。
