# FMP 新版開發

> 新版（`app/`）怎麼建置、在各平台實跑驗證、閘門怎麼跑。架構在根目錄的 `ARCHITECTURE.md`。舊版的開發文件是 `docs/legacy/development.md`。

## 平台

每個平台一節：用的框架與套件、怎麼建置、怎麼實跑驗證。以下指令都在 `app/` 裡跑，`<暫存目錄>` 放截圖（截圖不進 repo）。框架與套件由加入它們的票補。

完整閘門（〈開發環境與閘門〉）在每個平台跑 `integration_test/` 的每個 `*_test.dart`，一次一個檔；四平台共用的測試依賴是 `integration_test`（SDK）。各節的「閘門」是 `tool/check.dart` 實際下的指令，手動重跑單一平台時照抄。

`winpc` 的 `C:\fmp-wt`、iOS 與 Android 模擬器、Mac 上的 `com.personal.fmp.dev` 是所有 worktree 共用的：`sync.sh` 每次都刪掉 `C:\fmp-wt\app` 再解開，模擬器與 Mac 上同一個 applicationId 只有一份。所以碰它們之前一律先拿共用裝置鎖（〈開發環境與閘門〉的共用裝置鎖）：完整閘門自己拿；手動實跑經包裝指令 `dart run tool/device_lock.dart -- <指令>`（在 `app/` 裡跑）。鎖以 worktree 為單位：同一個 worktree 已持有時，包裝指令與 `tool/winpc/` 的腳本直接執行，不會等自己。兩種用法：

- 一口氣做完：把碰裝置的步驟（安裝、啟動、讀畫面、截圖、關 App、讀 log）包在同一個 `dart run tool/device_lock.dart -- bash -c '…'` 裡，整段持有鎖。分成好幾次包時，中間鎖會放掉，別的 worktree 的閘門可能插進來重裝。截圖與輸出存到 `<暫存目錄>`，放鎖之後再看。
- 互動（要跨好幾輪讀畫面、操作）：先在背景持鎖，`dart run tool/device_lock.dart -- sleep 1200 &`，記下它的 pid；之後這個 worktree 裡的指令照常一條條下（不必再包）；做完 `kill <pid>` 放鎖。持鎖期間別的 worktree 都在等，用完就放，`sleep` 的秒數抓實際需要。同一個 worktree 自己跑完整閘門前也要先放掉，閘門不認背景的持有者，會等它。

建置（`flutter build …`）只寫這個 worktree 的 `build/`，不必拿鎖。各平台的「實跑」是一口氣做完的寫法。

### macOS

框架與套件：Flutter macOS 桌面，平台套件：path_provider（log 目錄、資料庫位置）、just_audio（AVPlayer）。

log：`~/Library/Containers/com.personal.fmp.dev/Data/Library/Application Support/com.personal.fmp.dev/logs/fmp.log`。

資料庫：`logs/` 的上一層（App 支援目錄）的 `fmp.sqlite`。

閘門：`flutter build macos --debug`；`flutter test integration_test/<檔> -d macos`（會在本機開一個 App 視窗）。

實跑：`flutter build macos --debug`，再 `dart run tool/device_lock.dart -- bash -c 'open "build/macos/Build/Products/Debug/FMP Dev.app" && sleep 10 && orca computer get-app-state --app com.personal.fmp.dev > <暫存目錄>/macos.txt && osascript -e "quit app \"FMP Dev\""'`，讀回畫面（`macos.txt` 裡的截圖路徑要打開來看）。

### iOS 模擬器

框架與套件：Flutter iOS，平台套件：path_provider（log 目錄、資料庫位置）、just_audio（AVPlayer）。

log：`xcrun simctl get_app_container booted com.personal.fmp.dev data` 底下的 `Library/Application Support/logs/fmp.log`。

資料庫：`logs/` 的上一層（App 支援目錄）的 `fmp.sqlite`。

閘門：`flutter build ios --simulator --debug`；`flutter test integration_test/<檔> -d <模擬器 id> --no-uninstall`。模擬器要先開好；`check.dart` 從 `flutter devices --machine` 挑第一台 `emulator: true` 的 iOS 裝置，不會挑連著的實體 iPhone，找不到就讓這一步失敗。

實跑：`flutter build ios --simulator --debug`，再 `dart run tool/device_lock.dart -- bash -c 'xcrun simctl install booted build/ios/iphonesimulator/Runner.app && xcrun simctl launch booted com.personal.fmp.dev && sleep 10 && xcrun simctl io booted screenshot <暫存目錄>/ios.png && orca emulator ax > <暫存目錄>/ios-ax.txt'`。`orca emulator ax` 讀的是 Orca 面板接上的裝置，先在鎖外 `orca emulator attach <裝置>`（只設定面板，不碰裝置）。雙螢幕的 iPhone Duo 截圖要加 `--display=1`，否則報 `Invalid argument`。

### Android 模擬器

框架與套件：Flutter Android，平台套件：path_provider（log 目錄、資料庫位置）、just_audio（ExoPlayer）。

log：`adb shell run-as com.personal.fmp.dev cat files/logs/fmp.log`。

資料庫：`files/fmp.sqlite`，取出：`adb exec-out run-as com.personal.fmp.dev cat files/fmp.sqlite > <暫存目錄>/fmp.sqlite`。

閘門：`flutter build apk --debug`；`flutter test integration_test/<檔> -d <模擬器 id> --no-uninstall`。模擬器要先開好（`flutter emulators --launch Medium_Phone_API_37.0`），挑法同 iOS。`--no-uninstall` 讓測試跑完不刪 App 與資料。

實跑：`flutter build apk --debug`，再 `dart run tool/device_lock.dart -- bash -c 'orca emulator install build/app/outputs/flutter-apk/app-debug.apk --reinstall && orca emulator launch com.personal.fmp.dev && sleep 20 && orca emulator ax > <暫存目錄>/android-ax.txt && adb exec-out screencap -p > <暫存目錄>/android.png'`。debug 版第一次啟動要十幾秒，太早讀只會看到啟動畫面。

### Windows（`winpc`）

框架與套件：Flutter Windows 桌面，平台套件：path_provider（log 目錄、資料庫位置）、media_kit（libmpv；建置時從 GitHub 下載，事實 K26）。

log：`ssh winpc 'Get-Content "$env:APPDATA\com.personal.fmp\FMP Dev\logs\fmp.log" -Tail 20'`。

資料庫：`logs/` 的上一層（App 支援目錄）的 `fmp.sqlite`。path_provider 連帶把 `jni` 列進 Windows 的 FFI 插件。

閘門：`check.dart` 依序跑 `tool/winpc/sync.sh`、`run_task.sh fmpbuild C:/fmp-wt/build.ps1 -Mode debug`，每個 integration_test 檔再跑一次 `run_task.sh fmptest C:/fmp-wt/test.ps1 -File integration_test/<檔>`（`test.ps1` 跑 `flutter test <檔> -d windows`，要先跑過 `build.ps1` 的 `pub get`、slang 與 build_runner）。每次執行前先刪遠端的 `build.log`／`test.log`，跑完經 SSH 讀回並存到 `app/build/winpc/`（`build.log`、`test-<檔名>.log`）。log 裡每個 `exit <階段>=<退出碼>` 都是 0 且有 `=== done` 才算通過；排程工作中途死掉時沒有 `=== done`。integration_test 會在擁有者的桌面開 App 視窗，和截圖一樣會搶前景。

經 SSH 操作，不 push（2026-11-11 實測，`winpc` 是 Flutter 3.47.5）。腳本在 `app/tool/winpc/`，在 Mac 上跑。`sync.sh`、`run_task.sh` 沒持鎖時會自己經包裝指令拿鎖（〈開發環境與閘門〉），但只在那一支腳本的期間；一次實跑的同步、建置、截圖、取回截圖要連續做完，整串包在一個 `dart run tool/device_lock.dart -- bash -c 'tool/winpc/sync.sh && tool/winpc/run_task.sh fmpbuild … && tool/winpc/run_task.sh fmpshot … && scp winpc:C:/fmp-wt/shot.png <暫存目錄>/'` 裡（或用上面的互動持鎖），裡面的腳本認得這個 worktree 已持鎖，不會再等：

1. 同步：`tool/winpc/sync.sh` 把 `app/`（含未追蹤、不含 gitignore 的檔）與三支 `.ps1` 打包，`scp` 到 `winpc` 的 `C:\fmp-wt` 解開。舊的 `C:\fmp-wt\app` 先刪，每次都是乾淨建置。
2. 建置：`tool/winpc/run_task.sh fmpbuild C:/fmp-wt/build.ps1 -Mode debug`（或 `release`）。`run_task.sh` 用 `schtasks /IT` 建一次性排程工作，在桌面工作階段跑，等它結束再刪掉；`build.ps1` 跑 `flutter pub get`、`dart run slang`、`dart run build_runner build`、`flutter build windows`。讀 log：`ssh winpc 'Get-Content C:\fmp-wt\build.log -Tail 40' | iconv -c -f cp950 -t utf-8`。debug 約 77 秒、release 約 31 秒。
3. 啟動與截圖：`tool/winpc/run_task.sh fmpshot C:/fmp-wt/shot.ps1 -Exe C:/fmp-wt/app/build/windows/x64/runner/Debug/fmp.exe -Out C:/fmp-wt/shot.png`，再 `scp winpc:C:/fmp-wt/shot.png <暫存目錄>/`。`shot.ps1` 啟動 App、等 8 秒、把視窗拉到最上層再截視窗矩形、關掉 App；`-Type <文字>` 在截圖前按 Tab 聚焦第一個欄位、打字、按 Enter，`-Click x,y` 再點客戶區的邏輯座標（依視窗 DPI 換算），兩者動作前都重新拉一次前景；`-Click "x,y;x,y;…"` 依序點好幾下，每下等 `-ClickWait` 秒後另存一張 `shot-<n>.png`（n 從 1 起，和 `shot.png` 同目錄，例如用「點一首、暫停、空點一下、繼續」看暫停與繼續）；`C:\fmp-wt\shot.log` 有 `foreground_is_fmp=True` 才代表截到的是 App。App 的 stdout、stderr 存到 `C:\fmp-wt\app-stdout.txt`、`app-stderr.txt`（Dart VM 中止時訊息印在這裡），關視窗後 `shot.log` 記 `exited_after_close`；看有沒有在關閉時崩潰，再對照事件記錄（`Get-WinEvent -FilterHashtable @{LogName="Application"; Id=1000}`，事實 W11）。完整閘門跑完後，`Debug\fmp.exe` 已被 `flutter test -d windows` 用 integration_test 的入口重建，實跑前先重跑一次步驟 2（2026-11-11：直接啟動閘門留下的 exe，畫面正常卻沒有建立資料庫檔）。
4. 清理：排程工作由 `run_task.sh` 刪掉；`ssh winpc 'Get-Process fmp -EA SilentlyContinue'` 確認 App 已關；整個工作樹用 `dart run tool/device_lock.dart -- ssh winpc 'Remove-Item -Recurse -Force C:\fmp-wt'` 清掉（持鎖做，別的 worktree 的閘門可能正在用它）。

注意：

- 建置與截圖都要擁有者已登入 `winpc` 的桌面。截圖會短暫搶走前景視窗，擁有者正在用 `winpc` 時先說一聲。
- 截圖可能夾到擁有者桌面的其他內容（輸入法候選窗、視窗邊緣外的桌面），只留在 `<暫存目錄>`。
- 經 SSH 組 `schtasks /TR` 時反斜線會被吃掉，腳本路徑與參數一律寫正斜線。`schtasks /Query` 的狀態字串是在地化的（zh-TW 是「執行中」）。
- 腳本維持純 ASCII，避開 PowerShell 5.1 以 cp950 讀無 BOM 檔案的問題。原生指令用 `cmd /c "… 2>&1"` 包起來，不設 `$ErrorActionPreference='Stop'`。
- `Start-Process` 失敗不會讓腳本中止，只會拿到 null；`shot.ps1` 用 `-ErrorAction Stop` 把錯誤寫進 log。
- `run_task.sh` 輪詢狀態時 SSH 失敗會重試，連續 12 次才放棄並回傳非零。不能把查詢失敗當成工作結束：刪掉還在跑的排程工作會連同腳本一起終止（2026-11-11，`winpc` 藍屏時遇到）。

### 其他已知怪癖

上一版文件，用到時重驗：

- **Windows 自動化輸入**：`SendKeys` 與掃描碼為 0 的 `keybd_event` 會讓 Ctrl 組合鍵失效；中文輸入法會吃掉英數字；跨行程最小化與還原會讓 lifecycle 卡在 `inactive`。
- **模擬器的輸入法**（2026-11-12）：iOS 模擬器的鍵盤是注音、Android 模擬器的是速成，`orca emulator type lofi` 在 iOS 會變成注音符號直接送出（搜尋的 keyword 是 `ㄠ ㄟ ㄑ ㄛ`），在 Android 會停在組字區、不送出。打英文前先按鍵盤的地球鍵切到英文，打完切回；送出前看 log 的 keyword 對不對，打錯也算一次匿名搜尋。
- **integration_test**：一次只能給一個檔；Android 不加 `--no-uninstall` 時可能刪掉模擬器上同 applicationId 的 App 連同資料。完整閘門照這兩條做（見上面各平台的「閘門」）。
- **adb server 自己當掉**：完整閘門的 `integration_test android` 報「No running android simulator/emulator」、`flutter devices` 看不到 Android 模擬器時，多半是 Mac 上的 adb server 不在。起初以為是別的 session 重啟了 adb；查過，`app/`、`.githooks/`、`.claude/skills/` 都沒有 `adb kill-server`、`start-server`（`verify-legacy-on-device` 收尾的 `adb emu kill` 關的是模擬器，不是 server），閘門也只跑 `flutter devices` 與 `flutter test`。原因是 platform-tools 37.0.1 的 adb server 被區網的 mDNS 封包弄當（事實 K15），下一個 adb 指令再把它叫起來。擁有者 2026-11-11 決定 adb server 以 `ADB_MDNS=0` 啟動（關掉 mDNS，模擬器不靠它）。實測：持鎖後 `adb kill-server`、`ADB_MDNS=0 adb start-server`，`adb server-status` 顯示 `mdns_enabled: false`、`mdns_backend: MDNS_DISABLED`，模擬器 1 秒內回到 `device`。之後由誰啟動：包裝指令拿到鎖後、完整閘門找 Android 模擬器之前，各跑一次 `adb start-server`，閘門與包裝指令開的每個指令也都帶 `ADB_MDNS=0`（`app/tool/src/device_lock.dart` 的 `sharedDeviceEnvironment`）。server 不在時就以 `ADB_MDNS=0` 叫起來；在跑時 `start-server` 什麼都不做，不會打斷別的 session。不主動 kill 已經在跑的 server：萬一在跑的是開著 mDNS 的，它當掉後下一次由閘門或包裝指令叫起來的就關掉了。之所以主動叫而不只靠環境變數：`orca emulator …` 是交給 Orca App 去跑 adb，帶的是 Orca 的環境，不是包裝指令的；Orca、Android Studio、其他專案在 server 不在時叫起來的仍會開 mDNS。要全面關掉得把 `ADB_MDNS=0` 放進登入環境（含 Orca 的），那是擁有者機器的設定，還沒做。遇到「No running android simulator/emulator」時跑一次 `ADB_MDNS=0 adb devices`、等模擬器回到 `device` 再重跑那一步。
- **`winpc` 的 Dart 偶發當掉（環境問題）**：`flutter build windows`、Windows 的 `integration_test` 或 `build.ps1` 的 build_runner 偶發失敗。症狀有三種，根源相同：只報 `error MSB8066`（`flutter_assemble.rule` 結束代碼 1，加 `-v` 才看得到 `===== CRASH =====`）；`exit codegen=78`、`exit codegen=-1073740791` 或 `exit codegen=1` 加上 `Compilation did not produce any result`，之後 `flutter build` 因為缺 `database.g.dart` 跟著失敗；或不存在的「缺成員」編譯錯。都是 Dart 的 `dartaotruntime.exe`（frontend_server）或 `gen_snapshot.exe` 存取違規（`0xc0000005`），VM 印出 `===== CRASH =====` 後自己 abort（事件記錄是 `0xc0000409`，位移固定在 `0x332aa1`）。查證：沒有其他閘門同時跑時，main（`b2fadc04`）連續乾淨建置 5 次，第 4、5 次失敗；在 SSH 工作階段（不經排程工作）對同一份輸入連跑 60 次 `dart compile kernel`（編 pub cache 裡的 build_runner，不含 App 的程式碼），2 次當掉（其中 1 次留下空的輸出檔），成功的 58 次輸出逐位元組相同。三次當掉的位址扣掉 snapshot 基址後都不同（`0x46455d`、`0x6a425`、`0x2b47b2`），呼叫堆疊也不同。同一台機器 14 天內還有 Windows 自己的服務（`sppsvc`、Windows Update、Defender）、MSVC 的 `CL.exe` 與其他使用者程式以存取違規、非法指令（`0xc000001d`）當掉，6 次 Kernel-Power 41（非預期重開），11-10、11-11 有藍屏（兩次 `0x00020001` HYPERVISOR_ERROR、一次 `0x1E`，minidump 在 `C:\WINDOWS\Minidump\`）。結論：是 `winpc` 的硬體或韌體不穩（i9-13900HX、BIOS KWCN54WW、microcode `0x12E`），不是產品也不是閘門；worktree 互蓋可能造成過部分紅燈（缺成員錯），但不是當掉的原因。還沒定位到是哪個元件：記憶體、處理器電壓（降壓或超頻工具）、BIOS 或 Hyper-V／VBS，要擁有者在場檢查（Windows 記憶體診斷要重開機）。Intel 的 13、14 代 Vmin 不穩問題官方只認桌上型處理器，行動版說沒有受影響，13900HX 是行動版，不能直接套用。在那之前，閘門照實報紅，遇到時重跑；重跑能過就不是程式問題。說不出原因的重試不收，閘門也沒有自動重試。重現：在 `winpc` 對任一份已經 `pub get` 的 `app/` 連跑 `dart compile kernel --packages=.dart_tool\package_config.json -o <檔> <build_runner>\bin\build_runner.dart` 60 次，約 5 分鐘，失敗率約 3%（2026-11-11）。
- **Android 模擬器**：音訊比實際快約 1.7 倍，不能拿來量時長；GPU 是 SwiftShader（CPU 軟體模擬，`dumpsys SurfaceFlinger` 的 GLES 一行）而且只有 1 核，連實心畫面捲動的 raster 中位數都約 24 ms，不能拿來量幀時間（舊版基準 `docs/legacy/audit/perf-baseline.md` 的 Android 數字是在 `winpc` 的模擬器以主機 GPU 量的）；Flutter 在上面走 Impeller OpenGLES；`adb shell input text` 打不了中文；畫面持續更新時 `uiautomator dump` 會失敗；Claude Code 的沙箱擋 `adb` 連 5037。
- **macOS**：macOS 27 不讓第三方經 MediaRemote 讀 Now Playing。媒體控制改用輔助使用 API 讀選單列的「正在播放」面板（標題、按鈕、進度條，也能按按鈕與 seek），再對照 `mediaremoted` 的系統 log（brief 事實 M9）；腳本是 `scripts/experiments/macos-now-playing/` 的 `np-panel.sh`、`mediakey.sh`（模擬媒體鍵），要「輔助使用」權限；它們會送 Escape、按面板、送媒體鍵，影響最前面或最近出過聲的 App，所以自己拿共用裝置鎖（同 `tool/winpc/` 的腳本）。App 沒出過聲時不是 Now Playing App，這時送媒體鍵會叫起「音樂」App（事實 M10），先播再測。zsh 的 `log` 是內建指令，讀系統 log 要寫 `/usr/bin/log`。Flutter 的語意樹不經 macOS AX 暴露，要用截圖加座標。
- **iOS 模擬器**：沒有可截圖的鎖定畫面與控制中心，Now Playing 只能讀系統 log；不要用 `orca emulator kill`。
- **無害的建置雜訊**：`media_kit_libs_windows_audio` 的 CMake `CMP0175` 警告、`flutter_inappwebview_windows` 在 cp950 下的 C4819、`resolve_symlinks.ps1` 的 `Get-Item` 錯誤。

## 開發環境與閘門

- `dart run tool/check.dart --quick`（在 `app/` 裡跑）：產生 i18n、codegen（build_runner）、format、analyze、單元測試、schema 快照檢查（`ARCHITECTURE.md`〈測試策略〉）、文件閘門（`python3 scripts/check_docs.py` 與它的測試，在 repo 根目錄跑，要 Python 3；規則寫在腳本開頭）；commit 改到 `app/` 時由 `.githooks/pre-commit` 執行。
- `dart run tool/check.dart`（完整版）：quick 之後依序做 macOS、iOS 模擬器、Android 模擬器、Windows（SSH 同步工作樹到 `winpc`、以排程工作執行，不靠 push）的建置，再在四平台跑 `integration_test`（指令見〈平台〉各平台的「閘門」），最後檢查插件打包產物是否最新（`plugin bundles (esbuild)`：在 `app/plugins/` 跑 `npm ci` 與 `npm run build -- --outdir <暫存目錄>`，含型別檢查，再和提交的各插件 `dist/` 逐位元組比對）。前面的步驟失敗也照跑完，最後列出每一步的結果；步驟名稱帶平台，失敗時印成 `FAIL build ios`、`FAIL integration_test windows: integration_test/<檔>`，退出碼非零。前置條件：在 Mac 上跑（iOS 建置要 Xcode），iOS 模擬器與 Android 模擬器先開好，`winpc` 的桌面有人登入。每張票合併前跑完整版。
- **共用裝置鎖**：完整版在 Mac 上的三個建置之後、`build windows` 之前跑 `lock shared devices`，四平台的 `integration_test` 跑完後跑 `unlock shared devices`；中間的步驟（`winpc` 的同步、建置與 integration_test，模擬器與 macOS 的 integration_test）持有鎖時才跑，沒拿到就判失敗。同一時間只有一個 worktree 的完整版在碰共用裝置。
  - 位置：`git rev-parse --path-format=absolute --git-common-dir` 底下（所有 worktree 共用的 `.git`）的 `fmp-device.lock`，持有者資訊在同目錄的 `fmp-device.lock.holder`（JSON：`worktree`、`pid`、`started`）。實作在 `app/tool/src/device_lock.dart`。
  - 包裝指令：`dart run tool/device_lock.dart [--repo <目錄>] -- <指令> [參數…]`（在 `app/` 裡跑，照 util-linux `flock(1)` 包住一個指令的慣例）拿目前目錄所在 repo 的鎖、執行指令、指令結束就放鎖，退出碼是指令的退出碼（被訊號結束時是 128 + 訊號編號）；收到 SIGINT、SIGTERM、SIGHUP 時轉給指令。訊息印到 stderr。`--held` 只回答這個 worktree 是否持有這把鎖（是 0，否則 1）。
  - 腳本自己守：`tool/winpc/` 的每支 `*.sh` 一開頭 source `lock_guard.sh`，沒持鎖就經包裝指令重新執行自己（先拿鎖、必要時等）。`test/tool/device_lock_cli_test.dart` 檢查每支都在碰 `ssh`／`scp` 之前 source 它，新加的腳本也一樣。
  - 可重入：鎖以 worktree 為單位。`.holder` 記的 `worktree` 是自己這個 worktree、而且鎖確實被佔著時，包裝指令與 `tool/winpc/` 的腳本直接執行（完整閘門呼叫的 `sync.sh`、包裝指令裡再包一次、互動時背景持鎖之後下的指令）。持有者死掉後 `.holder` 會留著，但鎖已放掉，不算。完整閘門自己拿鎖時不看這條，背景持鎖要先放掉。
  - adb：包裝指令拿到鎖後、完整閘門找 Android 模擬器之前跑 `adb start-server`，開的指令都帶 `ADB_MDNS=0`（〈平台〉〈adb server 自己當掉〉）。
  - 行為：鎖是 OS 的檔案鎖（事實 K16）。別人持有時印出 `Waiting for the shared-device lock …, held by worktree <路徑>, pid <pid>, since <開始時間>` 然後等，沒有逾時。持有的閘門結束、當掉或被 `kill -9` 時，OS 自動放掉鎖，鎖本身不必清理（還在跑的子行程與 `winpc` 排程工作見下一條）。
  - 手動解除：只在持有者卡住時需要。看 `fmp-device.lock.holder` 的 `pid`，`ps -o pid,pgid,command -p <pid>` 確認是 `dart run tool/check.dart` 或 `tool/device_lock.dart`，先 `ps -o pid,command -g <pgid>` 看群組裡只有這個閘門與它開的行程（從沒有 job control 的 shell 啟動時，群組可能包含那個 shell），再用 `kill -- -<pgid>` 停掉整個群組（只停閘門本身時，它開的 `flutter test`、`run_task.sh` 會繼續用裝置），鎖隨之放掉。再確認 `winpc` 上沒有還在跑的排程工作（`ssh winpc 'schtasks /Query /TN fmpbuild'`、`fmptest`），有的話等它結束：排程工作不會跟著 Mac 上的行程結束，下一個閘門同步時會刪掉它正在用的 `C:\fmp-wt\app`。閘門在終端機按 Ctrl-C 時同理。不要刪 `fmp-device.lock`：持有者還活著時刪掉，下一個閘門會鎖到新建的同名檔，兩邊同時碰裝置。也不要刪 `fmp-device.lock.holder`：持有者還活著時刪掉，它自己開的 `sync.sh` 等腳本認不出鎖在自己這邊，會一直等它。持有者死掉後 `.holder` 可能留著，內容是上一個持有者，不影響拿鎖。
- 插件：原始碼在 `app/plugins/<id>/src/`。改了之後在 `app/plugins/` 跑 `npm ci`（第一次）與 `npm run build`（`tsc --noEmit` 加 esbuild），把 `dist/plugin.js` 一起提交；新插件目錄另外要列進 `pubspec.yaml` 的 `assets`（`test/plugins/plugin_assets_test.dart` 守著）。宿主 API 的型別在 `app/plugins/host.d.ts`，和 Dart 端（`lib/plugins/src/`）一起改。npm 11 預設不跑 esbuild 的 postinstall，不影響建置（平台二進位由 optional dependency 裝好）。
- GitHub Actions：新版平常不跑。`app-v*` tag 觸發 `app-release.yml`，跑完整閘門後發佈。舊版的 `ci.yml` 照舊，M0 要確認它不受 `app/` 影響。
- 環境：Flutter 3.47.5（Mac 與 `winpc`）、Xcode 27.1、iOS 27.1 模擬器、Android 模擬器 `Medium_Phone_API_37.0`、Node（開發插件與完整閘門用；2026-11-12 本機 26.12.0、npm 11.20.0，esbuild 0.28 要 Node ≥ 18）、rustup（Rust ≥ 1.95，fjs 在 Android 與 Windows 從原始碼編；`winpc` 的 default host 要是 msvc）。
