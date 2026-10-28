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
  輸入法在中文模式時也可能整串吃掉：框架收不到任何按鍵事件，輸入框只留一個空白的組字（M4 PR 2 實機，
  一度被誤判成 App 的回歸）。打字前先對 FMP Dev 視窗跑 `scripts/ime_off.ps1`（只關這個視窗的輸入法，
  印出 `open=0` 才算關掉）。
- **組合鍵（Ctrl+A、Ctrl+F 之類）不要用 `SendKeys` 或掃描碼填 0 的 `keybd_event`**：兩者送出的按鍵
  掃描碼都是 0，Flutter 的 Windows 嵌入層把每個鍵都當成同一個實體鍵（`physicalKey` 是
  `0x1600000000`），按下 A 前先替 Ctrl 補一個放開，框架收到的是 Ctrl↓ Ctrl↑ A↓ A↑，任何 Ctrl 快捷鍵都
  對不上，看起來像 App 的快捷鍵壞了（M4 PR 5 實機，Ctrl+A 全選一度被誤判成焦點問題）。單鍵（Esc、Enter、
  打字）不受影響。組合鍵改用帶真實掃描碼的 `keybd_event`，例如 Ctrl+A：
  `keybd_event(0xA2, 0x1D, 0, 0)`、`keybd_event(0x41, 0x1E, 0, 0)`、`keybd_event(0x41, 0x1E, 2, 0)`、
  `keybd_event(0xA2, 0x1D, 2, 0)`（`VK_LCONTROL`／`'A'`；其他鍵的掃描碼用 `MapVirtualKey(vk, 0)` 取）。
- **不要跨行程最小化再還原來搶前景**（`ShowWindow` 的 `SW_MINIMIZE`／`SW_RESTORE`）：App 的 lifecycle
  會停在 `inactive` 回不到 `resumed`，Flutter 把焦點暫放在根範圍，外殼的快捷鍵（Esc、Ctrl+F、F6）全部
  沒反應，看起來像快捷鍵壞了。用 `msaa_tree.ps1 -Click` 拉前景（`AttachThreadInput`＋`SetWindowPos`），
  非得最小化時改送 `WM_SYSCOMMAND` 的 `SC_MINIMIZE`／`SC_RESTORE`。
- **整合測試會蓋掉 dev 產物**：`flutter test integration_test/... -d windows` 建到同一個
  `build\windows\x64\dev\runner\Debug\fmp.exe`，跑完後那裡是測試版，還可能留下一個沒有視窗、沒有 log
  的 `fmp.exe`（占住單一實例，之後啟動會直接結束）。跑完整合測試先結束它，再
  `flutter build windows --flavor dev --debug`。
- **一次只給一個整合測試檔**：`flutter test integration_test/a.dart integration_test/b.dart -d windows`
  第一個檔案照常，第二個建置完就報 `Error waiting for a debug connection: The log reader stopped
  unexpectedly` 與 `Unable to start the app on the device`。不是單一實例擋住（那時沒有別的 `fmp.exe`），
  是 flutter_tools 的桌面 log reader 只能用一次；每個檔案分開下指令。
- **Narrator**：`Start-Process narrator.exe` 會帶出「快速入門」視窗搶前景（之後的 `-Click` 回 exit 3），
  `taskkill /F /IM NarratorQuickStart.exe` 關掉它；Narrator 本身 `taskkill` 會被拒，用 Win+Ctrl+Enter 關。

## SMTC（系統媒體控制，M2 PR 16b 起）

**一律帶 `-AppFilter`／`-Aumid`**：不帶的話會列出、甚至操作擁有者其他 App 的媒體工作階段（含曲名）。

讀狀態（唯讀）：

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $S/smtc_probe.ps1 -AppFilter com.personal.fmp.dev
```

從 WinRT 讀媒體工作階段的 `TITLE`、`ARTIST`、`THUMBNAIL`（`present`／`none`，Windows 自己下載封面的結果）、
`POSITION`／`END`、`STATUS`、各按鈕的 `Is…Enabled`，以及 `IsShuffleActive`、`AutoRepeatMode`（`None`／`List`／`Track`），App 不必在前景。`-AppFilter` 是 AppUserModelID 的子字串比對：
只寫 `fmp` 會連舊版與 prod（`com.personal.fmp`）一起列出，但不會列出別的 App。必須是 `powershell.exe`（5.1）；
`pwsh` 沒有 WinRT 投影。

送指令（只送給 FMP）：

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $S/smtc_command.ps1 -Command toggle   # play|pause|toggle|next|previous|stop|shuffle-on|shuffle-off|repeat-none|repeat-list|repeat-track
```

- **不要用全域鍵盤媒體鍵驗 FMP**（`SendKeys`、`keybd_event` 的 `VK_MEDIA_*`）：Windows 自己決定送給哪個工作階段，
  別的 App 也在播時會送到它那裡。`smtc_command.ps1` 經 `GlobalSystemMediaTransportControlsSession` 的
  `TryPlayAsync`／`TrySkipNextAsync`／`TryStopAsync` 等，只對 AppUserModelID **完全等於** `-Aumid`（預設
  `com.personal.fmp.dev`）的工作階段送，別的 App、舊版與 prod 都碰不到；找不到就 exit 1、不送。
  `ACCEPTED=False`（exit 3）是那顆按鈕沒啟用。
- `shuffle-*`、`repeat-*`（`TryChangeShuffleActiveAsync`、`TryChangeAutoRepeatModeAsync`）是浮層隨機、循環鈕的要求，App 決定要不要照做：Mix 與直播中不理（log `System media command ignored`），Mix 中 `repeat-list` 變成單曲（`Track`）。送完用 probe 看 `IsShuffleActive`、`AutoRepeatMode` 是不是 App 實際的狀態。
- 送完以 log（tag `media-controls` 與 `Playback state`）或再跑一次 probe 確認反應。

預期（2026-10-07 實機）：

- 沒有曲目、或啟動恢復後還沒按播放：SMTC 停用，`SESSIONS=0` 與 `NO_SESSION`，不代表出錯。
- 播放中 `POSITION` 約每 5 秒更新一次（沒有 seek）；暫停時 App 不再推位置。
- `THUMBNAIL=present`（交的是 `https` 網址；`file:///` 讀不到）。
- `IsStopEnabled=True`，`-Command stop` 之後 `STATUS=Paused`、位置保留（停止＝暫停）。
- `IsShuffleEnabled`／`IsRepeatEnabled` 是 True：套件註冊了這兩種請求的監聽，App 不處理，不是錯。

## 從 Mac 遠端（SSH）

開發機是 Mac、Windows 是另一台電腦時用（Mac 上的 Win11 ARM64 VM 跑不了 FMP：插件與資料庫的原生庫只有 x64）。
2026-10-28 U 的 Windows 驗收就是這樣做的。

### 設定（擁有者在 Windows 上做一次）

系統管理員 PowerShell：裝 OpenSSH 伺服器並設成自動啟動（`Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`、
`Start-Service sshd`、`Set-Service sshd -StartupType Automatic`），預設 shell 改成 PowerShell（`HKLM:\SOFTWARE\OpenSSH`
的 `DefaultShell`），公鑰寫進 `%ProgramData%\ssh\administrators_authorized_keys`（管理員帳號讀這份，ACL 只留
Administrators 與 SYSTEM）與 `%USERPROFILE%\.ssh\authorized_keys`，`sshd_config` 設 `PasswordAuthentication no`。
Mac 這邊用一把專用金鑰，在 `~/.ssh/config` 加一個 Host（腳本預設叫 `winpc`；位址只寫在這裡，不進 repo）。

### 為什麼要經桌面工作階段

SSH 的工作階段（session 0）沒有桌面：開 GUI、截圖、點擊、WinRT 的 SMTC 都碰不到使用者的桌面。`scripts/remote/`：

- `insession.ps1`：在 Windows 上，以排程工作（Interactive、目前使用者）在 console 工作階段跑一支腳本，等它結束、印回輸出，
  再刪掉排程工作。擁有者要登入著、螢幕沒鎖。
- `wrun.sh <本機 .ps1> [秒] [參數...]`：從 Mac 上傳腳本與一個帶參數的呼叫檔，經 `insession.ps1` 執行。
  `FMP_WIN_HOST`、`FMP_WIN_TOOLS` 改主機與 Windows 上的目錄。第一次用之前把 `insession.ps1` 複製到那個目錄。
- `win_ui.ps1 -Op …`：對 `FMP Dev` 視窗量矩形與 DPI、拉前景、移動與點擊（含右鍵、雙擊）、拖曳、滾輪、組合鍵（真實掃描碼）、
  `WM_SYSCOMMAND`（最大化、最小化、還原、關閉）、`PrintWindow` 截圖、讀游標形狀（`-Op cursor -Keys '<x>,<y> …'`，
  用來確認縮放邊）。座標是相對視窗左上角的物理像素。

這節上面的 `msaa_tree.ps1`、`window_shot.ps1`、`smtc_probe.ps1`、`smtc_command.ps1`、`ime_off.ps1` 都經 `wrun.sh` 跑。

### 陷阱

- **建置在桌面工作階段裡做**：從 SSH 直接 `flutter build windows` 會在 `flutter_inappwebview_windows` 的 nuget 下載與
  `smtc_windows` 的 Rust 編譯失敗；經 `insession.ps1` 就成功（第一次約 9 分鐘，之後約 2.5 分鐘）。PowerShell 裡把建置包成
  `cmd /c "flutter build … > log 2>&1"`：`$ErrorActionPreference = 'Stop'` 會把 CMake 寫在 stderr 的警告當成錯誤中斷。
- **中文要 UTF-8 帶 BOM**：PowerShell 5.1 讀沒有 BOM 的 `.ps1` 用系統碼頁（繁中 cp950），字串常量（`-Click '設定'`）會變亂碼、
  註解還可能讓語法壞掉。`wrun.sh` 會補 BOM（已有就不補，兩個 BOM 會讓 `param(` 失效）。印回的輸出要先設
  `[Console]::OutputEncoding = UTF8`（`insession.ps1` 已設）。
- **PowerShell 變數不分大小寫**：參數 `$H`（高度）和視窗代碼 `$h` 是同一個變數，後者蓋掉前者，`SetWindowPos` 拿到的「高度」
  是代碼值（看起來像視窗高度怎樣都設不動）。`win_ui.ps1` 的視窗代碼叫 `$hwnd`。
- **`FindWindow($null, …)`**：PowerShell 把 `$null` 傳給 `string` 參數會變成空字串，找不到視窗；用 `[NullString]::Value`。
- **Mac 端是 zsh**：`set -- $變數` 不拆字，迴圈裡拿空白分隔的座標要用 `bash -c`。參數含空白時自己加單引號（`-Filter "'menu item'"`）。
- **縮放邊在視窗內側**：`TitleBarStyle.hidden` 下，左、右、下的縮放區是視窗矩形內緣幾個像素（`-Op cursor` 讀到
  `size-we`／`size-ns`），頂邊是標題列的拖曳區、不能縮放。縮放後視窗寬度變了，下一次的座標要重量。
- **滑鼠停在帶 tooltip 的元件上之後，MSAA 的樹會停住**（`docs/troubleshooting.md` 的 `Failed to update ui::AXTree`）：
  點擊後把游標移到標題列的空白處；樹停住就改用截圖，或重開 App。
- **量啟動閃爍用 release**：debug 建置第一個畫格送上螢幕慢，外觀設定也還沒讀到，會先白約 0.7 秒、再「跟隨系統」的顏色約 0.5 秒；
  release 只有系統約 200ms 的淡入。量法：輪詢視窗可見後，每 30ms 用 `CopyFromScreen` 取視窗中央一小塊的平均亮度（只算數字、不存圖）。
- **測試音會從擁有者的喇叭出來**：要播放就用最短的測試曲，驗完用 `smtc_command.ps1 -Command pause` 停（只送給 FMP Dev）。
- 收尾：`WM_CLOSE` 關掉 `FMP Dev`、`Get-ScheduledTask -TaskName 'fmp-verify-*'` 確認沒有殘留。建置目錄與工具目錄留不留問擁有者。
