# Windows 桌面版

## 建置與啟動

在 `app/`：

```bash
flutter build windows --flavor dev --debug
```

產物：`build\windows\x64\dev\runner\Debug\fmp.exe`（舊版、prod、dev 的執行檔都叫 `fmp.exe`，
只有 dev 的視窗標題是 `FMP Dev`）。直接執行，參數照 `runtime-state.md` 的開發入口：

```powershell
Start-Process build\windows\x64\dev\runner\Debug\fmp.exe -ArgumentList '--fmp-dev-plugin=<app 的絕對路徑>\test\fixtures\plugins\test_plugin\test_plugin.js'
```

- **dev 是單一實例**（mutex `Local\FMP_MainInstance-dev`）：別的 worktree 開著的 FMP Dev 也算。
  第二個實例只會把第一個帶到前景就結束，看起來像「新版沒起來」。先 `tasklist | findstr fmp.exe`，
  確認是 FMP Dev 才關。
- 資料與 log 在執行檔旁的 `userdata-dev\`：`userdata-dev\logs\fmp.jsonl`。`flutter clean` 會一起清掉。
  格式與清法見 `runtime-state.md`。
- `flutter run -d windows` 時熱重載 `r` 可以；熱重啟 `R` 會讓行程結束，改用 `q` 離開再重開。

## 讀畫面文字、點按鈕（MSAA）

Flutter 的 Windows 視窗只經 MSAA 暴露語意，UI Automation 與 `orca computer get-app-state` 看不到
裡面（只有 `pane FLUTTERVIEW`）。用 `scripts/msaa_tree.ps1`（要 `powershell.exe`）：

```bash
S=.claude/skills/verify-on-device/scripts
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $S/msaa_tree.ps1 [-Filter text]
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $S/msaa_tree.ps1 -Click '<名稱>' [-Role 'push button'] [-Index 0]
```

- 第一行 `nodes=<n>`。先在同一個畫面記一次當基準（例如搜尋頁、有結果、播放列在）；之後同一個
  畫面只剩個位數，或送出提示後節點數掉到個位數、不再變動，代表無障礙橋卡住
  （`docs/troubleshooting.md` 的 `Failed to update ui::AXTree`）。
- 輸出的矩形是螢幕上的物理像素。`-Click` 是**真的滑鼠點擊**，先用 `-Filter` 確認名稱；它會把游標
  停回視窗左上角（游標下有 tooltip 會讓樹卡住）。
- 要確認資料目錄，看 `userdata-dev\` 是否存在，或 log 的 `App started` 的 `dataDirectory`。
- 腳本只找行程 `fmp` 而且視窗標題是 `FMP Dev` 的（`-Proc`、`-Title` 改），不會點到舊版或 prod；
  exit 1 是沒有視窗，2 是 `-Click` 沒對到，3 是視窗拉不到前景。

## 截圖

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $S/window_shot.ps1 \
  -Exe <fmp.exe 路徑> [-ArgLine '--fmp-dev-plugin=<插件.js>'] -Out <png> [-Wait 8] [-KeepRunning]
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $S/window_shot.ps1 -Attach -Out <png>
```

- 以 `PrintWindow` 只截 App 視窗，不含桌面與其他視窗；視窗被蓋住也截得到，最小化的不行（exit 1）。
- 預設截完就結束它啟動的行程，要接著操作加 `-KeepRunning`；`-Attach` 對已開的 `FMP Dev` 視窗
  截圖、不結束它。
- 舊專案觀察過 `PrintWindow` 回傳一張不再更新的畫面：兩張截圖逐位元相同時，先別斷定操作沒生效，
  用 MSAA 或 log 對照。
- 輸出放 session 暫存目錄。確認畫面上沒有個人資訊（使用者名稱、帳號）才貼進 PR 或回報。
- 不要改用整螢幕截圖（`CopyFromScreen`）：會截到蓋在上面的其他視窗。

## 操作的陷阱

- 合成輸入（`orca computer click`）要先把視窗拉到前景；`SetForegroundWindow` 單獨呼叫常被前景鎖
  靜默擋掉。`msaa_tree.ps1 -Click` 已經處理。
- 腳本要量座標或截圖時先設 `SetProcessDpiAwarenessContext(-4)`（`window_shot.ps1` 已設），否則
  DPI 縮放下座標與截圖對不上。
- 對主視窗送 `WM_CLOSE` 才是「使用者按 X」；`Stop-Process` 是強殺，測不到關閉流程。

- **中文輸入法**：這台機器預設是中文輸入法時，`SendKeys` 打的英數字會先進組字，第一個 Enter 只是送出
  組字、第二個才觸發搜尋；空白鍵會拿去選字（「a」＋空白鍵變「日」）。送出搜尋就連按兩次 Enter；要驗
  「輸入框內空白鍵只輸入空格」看 log 裡沒有 `Playback state` 即可，或在 Android 用 `adb shell input text`。
- **整合測試會蓋掉 dev 產物**：`flutter test integration_test/... -d windows` 建到同一個
  `build\windows\x64\dev\runner\Debug\fmp.exe`，跑完後那裡是測試版，還可能留下一個沒有視窗、沒有 log
  的 `fmp.exe`（占住單一實例，之後啟動會直接結束）。跑完整合測試先結束它，再
  `flutter build windows --flavor dev --debug`。
- **Narrator**：`Start-Process narrator.exe` 會帶出「快速入門」視窗搶前景（之後的 `-Click` 回 exit 3），
  `taskkill /F /IM NarratorQuickStart.exe` 關掉它；Narrator 本身 `taskkill` 會被拒，用 Win+Ctrl+Enter 關。

## SMTC（M2 起才有東西可讀）

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $S/smtc_probe.ps1 -AppFilter com.personal.fmp.dev
```

從 WinRT 讀每個媒體工作階段的 `IsNextEnabled`／`IsPreviousEnabled` 等，App 不必在前景。`-AppFilter`
是 AppUserModelID 的子字串比對：只寫 `fmp` 會連舊版與 prod（`com.personal.fmp`）一起列出。必須是
`powershell.exe`（5.1）；`pwsh` 沒有 WinRT 投影。M1 的 App 還沒有註冊媒體工作階段，目前的輸出是
`SESSIONS=0` 與 `NO_SESSION`，不代表出錯。
