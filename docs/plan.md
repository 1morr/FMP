# FMP 新版實作計劃

> 狀態：第一版定稿（2026-11-06）。`/to-tickets docs/plan.md` 以〈里程碑任務〉為輸入，拆票後以票為準。決定的來源是 `docs/design-brief.md`，兩者衝突時以 brief 為準。

## 0. 工程慣例

- 一張票一個分支，在本機 `git merge --no-ff` 合回 main 再 push，不開 PR（`AGENTS.md`）。
- 每張票在四個平台做完並驗收，合併前跑 `dart run tool/check.dart`（完整版）。
- 新字串在同一張票補齊 zh-TW、zh-CN、en 三種語言。
- 依賴的版本開工時查 pub.dev 決定，寫進〈主要依賴〉，不憑記憶寫。
- 命名用 `GLOSSARY.md` 的詞。

## 1. 架構總覽

### 1.1 執行形態

單一 Flutter App。插件在 fjs 的 JS 引擎（QuickJS-NG，brief 事實 K11）裡執行：每個插件一個引擎，JS 跑在 fjs 全行程共用的 2 條原生執行緒，Dart 端在主 isolate 以 async 呼叫，不另開 isolate。每個引擎設記憶體上限；每次呼叫都有逾時，逾時就 `close()` 這個引擎再重建、重新載入插件（2 個插件同時卡住會讓其他插件停擺到逾時為止）。宿主 API 都經 fjs 的單一 bridge 進 Dart，在一處分派與檢查；建立引擎時只開白名單內的內建模組。音訊在原生播放器裡（ExoPlayer、AVPlayer、libmpv）。

### 1.2 目錄結構

新版放在 `app/`，根目錄舊版不動；建好後補進 `AGENTS.md`〈目錄〉。

```text
app/
  lib/
    app/        組裝、路由、主題、i18n
    domain/     曲目、歌單、存取等級等模型（純 Dart）
    core/       log、遮蔽、錯誤分類、網路
    plugins/    JS 引擎、宿主 API、插件管理
    playback/   佇列、臨時播放、音訊後端介面與兩個實作（實作在 `playback/backends/`）
    library/    本地歌單、匯入歌單、刷新、遠端寫入
    accounts/   帳號、登入、會員狀態
    lyrics/     歌詞匹配與顯示用的資料
    data/       drift 資料庫
    platform/   平台能力
    ui/<頁面>/  畫面與 view model
  plugins/      官方插件原始碼：bilibili、youtube、netease、lrclib
  test/
  integration_test/
  tool/check.dart
```

### 1.3 依賴規則

- `ui` 只能依賴功能模組與 `domain`，不能直接碰 `data`、`plugins` 的內部，也不能碰平台套件。
- 只有 `data/` 能 import drift，只有 `platform/` 能 import 平台套件，例外是 `playback/backends/`（音訊後端的兩個實作）可 import `just_audio`、`media_kit`；平台層以外不得用 `Platform.isXxx`（依平台選音訊後端也在平台層做）。
- 音源專屬的邏輯只能在 `app/plugins/` 裡；Dart 端不得出現音源識別碼的字面值分支（ADR 0038）。
- 由一支掃 import 與識別碼的 Dart 測試強制，並在測試檔內做雙向變異驗證；不自寫 analyzer lint 套件（flutter/flutter#187999）。M0 票 01 接上。
- 模組的實際介面在 M0 用 codebase-design skill 細化。

### 1.4 主要依賴

版本寫的是加入時 `pubspec.lock` 解出的版本；還沒加的由加入的那張票寫。

| 用途 | 依賴 | 理由 |
| --- | --- | --- |
| 狀態管理 | flutter_riverpod 3.5.0（手寫 provider） | 舊版與上一輪都用；自動重試全域關閉（brief 事實 K5） |
| 路由 | go_router | flutter.dev 官方維護，舊版用過；外殼用 `ShellRoute` |
| 資料庫與設定 | drift 2.35.4（帶進 sqlite3 3.9.1）；drift_dev 2.35.3、build_runner 2.17.1（dev） | schema 快照與升級測試（§3）；設定也存這裡，不用 shared_preferences。sqlite3 3.x 用 build hook 自帶 SQLite，不用 `sqlite3_flutter_libs`（brief 事實 K14）；沒用 `drift_flutter`，檔案位置由 `platform/` 給 |
| HTTP | dio | 插件請求都經宿主網路層，統一限流、重試、遮蔽 |
| 音訊 | just_audio（Android、iOS、macOS）、media_kit（Windows） | brief §6、事實 K1 |
| 媒體控制 | audio_service（Android、iOS、macOS）、audio_session、smtc_windows | macOS 由 M0 票 05 實測（brief 事實 M10、K17）；Windows 不在 audio_service 的平台內（事實 R4） |
| 登入 WebView | flutter_inappwebview 6.1.5 | 唯一涵蓋四平台的穩定版（事實 R1） |
| 憑證 | flutter_secure_storage 11.2.0 | brief §8 |
| 圖片 | cached_network_image | |
| i18n | slang 4.19.2、slang_flutter 4.19.0；flutter_localizations（SDK） | 舊版用過 |
| log | logger 2.8.0 | `AdvancedFileOutput` 依大小輪替、限制保留份數；只在 `core/log/` 用（brief 事實 K12） |
| App 目錄 | path_provider 2.1.6 | flutter.dev 官方；log 目錄與資料庫檔案由 `platform/` 經它取得（brief 事實 K13） |
| JS 引擎 | fjs 3.3.2 | 四平台同一個 QuickJS-NG，能中斷、能設記憶體上限、支援 async（M0 票 03，brief 事實 K11） |
| 插件建置 | TypeScript 加 esbuild（需 Node） | ADR 0038 |
| lint（dev） | flutter_lints 6.0.0 | `flutter create` 的預設；`app/analysis_options.yaml` 另開幾條 |
| 依賴規則測試（dev） | analyzer 14.7.0 | 以 AST 判斷 import 與分支，不靠字串比對；只在測試裡用，不做 lint 套件（§1.3） |
| 換掉平台實作（dev） | path_provider_platform_interface 2.1.3、plugin_platform_interface 2.1.8 | path_provider 官方的測試做法：換一個假的 `PathProviderPlatform` |
| 平台上的測試（dev） | integration_test（SDK） | Flutter 官方的 `flutter test integration_test/…`；完整閘門在四平台跑（§2、§4） |

## 2. 平台

每個平台一節：用的框架與套件、怎麼建置、怎麼實跑驗證。以下指令都在 `app/` 裡跑，`<暫存目錄>` 放截圖（截圖不進 repo）。框架與套件由加入它們的票補。

完整閘門（§4）在每個平台跑 `integration_test/` 的每個 `*_test.dart`，一次一個檔；四平台共用的測試依賴是 `integration_test`（SDK）。各節的「閘門」是 `tool/check.dart` 實際下的指令，手動重跑單一平台時照抄。

`winpc` 的 `C:\fmp-wt`、iOS 與 Android 模擬器、Mac 上的 `com.personal.fmp.dev` 是所有 worktree 共用的：`sync.sh` 每次都刪掉 `C:\fmp-wt\app` 再解開，模擬器與 Mac 上同一個 applicationId 只有一份。所以碰它們之前一律先拿共用裝置鎖（§4〈共用裝置鎖〉）：完整閘門自己拿；手動實跑經包裝指令 `dart run tool/device_lock.dart -- <指令>`（在 `app/` 裡跑）。鎖以 worktree 為單位：同一個 worktree 已持有時，包裝指令與 `tool/winpc/` 的腳本直接執行，不會等自己。兩種用法：

- 一口氣做完：把碰裝置的步驟（安裝、啟動、讀畫面、截圖、關 App、讀 log）包在同一個 `dart run tool/device_lock.dart -- bash -c '…'` 裡，整段持有鎖。分成好幾次包時，中間鎖會放掉，別的 worktree 的閘門可能插進來重裝。截圖與輸出存到 `<暫存目錄>`，放鎖之後再看。
- 互動（要跨好幾輪讀畫面、操作）：先在背景持鎖，`dart run tool/device_lock.dart -- sleep 1200 &`，記下它的 pid；之後這個 worktree 裡的指令照常一條條下（不必再包）；做完 `kill <pid>` 放鎖。持鎖期間別的 worktree 都在等，用完就放，`sleep` 的秒數抓實際需要。同一個 worktree 自己跑完整閘門前也要先放掉，閘門不認背景的持有者，會等它。

建置（`flutter build …`）只寫這個 worktree 的 `build/`，不必拿鎖。各平台的「實跑」是一口氣做完的寫法。

### macOS

框架與套件：Flutter macOS 桌面，平台套件：path_provider（log 目錄、資料庫位置）。

log：`~/Library/Containers/com.personal.fmp.dev/Data/Library/Application Support/com.personal.fmp.dev/logs/fmp.log`。

資料庫：`logs/` 的上一層（App 支援目錄）的 `fmp.sqlite`。

閘門：`flutter build macos --debug`；`flutter test integration_test/<檔> -d macos`（會在本機開一個 App 視窗）。

實跑：`flutter build macos --debug`，再 `dart run tool/device_lock.dart -- bash -c 'open "build/macos/Build/Products/Debug/FMP Dev.app" && sleep 10 && orca computer get-app-state --app com.personal.fmp.dev > <暫存目錄>/macos.txt && osascript -e "quit app \"FMP Dev\""'`，讀回畫面（`macos.txt` 裡的截圖路徑要打開來看）。

### iOS 模擬器

框架與套件：Flutter iOS，平台套件：path_provider（log 目錄、資料庫位置）。

log：`xcrun simctl get_app_container booted com.personal.fmp.dev data` 底下的 `Library/Application Support/logs/fmp.log`。

資料庫：`logs/` 的上一層（App 支援目錄）的 `fmp.sqlite`。

閘門：`flutter build ios --simulator --debug`；`flutter test integration_test/<檔> -d <模擬器 id> --no-uninstall`。模擬器要先開好；`check.dart` 從 `flutter devices --machine` 挑第一台 `emulator: true` 的 iOS 裝置，不會挑連著的實體 iPhone，找不到就讓這一步失敗。

實跑：`flutter build ios --simulator --debug`，再 `dart run tool/device_lock.dart -- bash -c 'xcrun simctl install booted build/ios/iphonesimulator/Runner.app && xcrun simctl launch booted com.personal.fmp.dev && sleep 10 && xcrun simctl io booted screenshot <暫存目錄>/ios.png && orca emulator ax > <暫存目錄>/ios-ax.txt'`。`orca emulator ax` 讀的是 Orca 面板接上的裝置，先在鎖外 `orca emulator attach <裝置>`（只設定面板，不碰裝置）。雙螢幕的 iPhone Duo 截圖要加 `--display=1`，否則報 `Invalid argument`。

### Android 模擬器

框架與套件：Flutter Android，平台套件：path_provider（log 目錄、資料庫位置）。

log：`adb shell run-as com.personal.fmp.dev cat files/logs/fmp.log`。

資料庫：`files/fmp.sqlite`，取出：`adb exec-out run-as com.personal.fmp.dev cat files/fmp.sqlite > <暫存目錄>/fmp.sqlite`。

閘門：`flutter build apk --debug`；`flutter test integration_test/<檔> -d <模擬器 id> --no-uninstall`。模擬器要先開好（`flutter emulators --launch Medium_Phone_API_37.0`），挑法同 iOS。`--no-uninstall` 讓測試跑完不刪 App 與資料。

實跑：`flutter build apk --debug`，再 `dart run tool/device_lock.dart -- bash -c 'orca emulator install build/app/outputs/flutter-apk/app-debug.apk --reinstall && orca emulator launch com.personal.fmp.dev && sleep 20 && orca emulator ax > <暫存目錄>/android-ax.txt && adb exec-out screencap -p > <暫存目錄>/android.png'`。debug 版第一次啟動要十幾秒，太早讀只會看到啟動畫面。

### Windows（`winpc`）

框架與套件：Flutter Windows 桌面，平台套件：path_provider（log 目錄、資料庫位置）。

log：`ssh winpc 'Get-Content "$env:APPDATA\com.personal.fmp\FMP Dev\logs\fmp.log" -Tail 20'`。

資料庫：`logs/` 的上一層（App 支援目錄）的 `fmp.sqlite`。path_provider 連帶把 `jni` 列進 Windows 的 FFI 插件。

閘門：`check.dart` 依序跑 `tool/winpc/sync.sh`、`run_task.sh fmpbuild C:/fmp-wt/build.ps1 -Mode debug`，每個 integration_test 檔再跑一次 `run_task.sh fmptest C:/fmp-wt/test.ps1 -File integration_test/<檔>`（`test.ps1` 跑 `flutter test <檔> -d windows`，要先跑過 `build.ps1` 的 `pub get`、slang 與 build_runner）。每次執行前先刪遠端的 `build.log`／`test.log`，跑完經 SSH 讀回並存到 `app/build/winpc/`（`build.log`、`test-<檔名>.log`）。log 裡每個 `exit <階段>=<退出碼>` 都是 0 且有 `=== done` 才算通過；排程工作中途死掉時沒有 `=== done`。integration_test 會在擁有者的桌面開 App 視窗，和截圖一樣會搶前景。

經 SSH 操作，不 push（2026-11-11 票 01 實測，`winpc` 是 Flutter 3.47.5）。腳本在 `app/tool/winpc/`，在 Mac 上跑。`sync.sh`、`run_task.sh` 沒持鎖時會自己經包裝指令拿鎖（§4），但只在那一支腳本的期間；一次實跑的同步、建置、截圖、取回截圖要連續做完，整串包在一個 `dart run tool/device_lock.dart -- bash -c 'tool/winpc/sync.sh && tool/winpc/run_task.sh fmpbuild … && tool/winpc/run_task.sh fmpshot … && scp winpc:C:/fmp-wt/shot.png <暫存目錄>/'` 裡（或用上面的互動持鎖），裡面的腳本認得這個 worktree 已持鎖，不會再等：

1. 同步：`tool/winpc/sync.sh` 把 `app/`（含未追蹤、不含 gitignore 的檔）與三支 `.ps1` 打包，`scp` 到 `winpc` 的 `C:\fmp-wt` 解開。舊的 `C:\fmp-wt\app` 先刪，每次都是乾淨建置。
2. 建置：`tool/winpc/run_task.sh fmpbuild C:/fmp-wt/build.ps1 -Mode debug`（或 `release`）。`run_task.sh` 用 `schtasks /IT` 建一次性排程工作，在桌面工作階段跑，等它結束再刪掉；`build.ps1` 跑 `flutter pub get`、`dart run slang`、`dart run build_runner build`、`flutter build windows`。讀 log：`ssh winpc 'Get-Content C:\fmp-wt\build.log -Tail 40' | iconv -c -f cp950 -t utf-8`。debug 約 77 秒、release 約 31 秒。
3. 啟動與截圖：`tool/winpc/run_task.sh fmpshot C:/fmp-wt/shot.ps1 -Exe C:/fmp-wt/app/build/windows/x64/runner/Debug/fmp.exe -Out C:/fmp-wt/shot.png`，再 `scp winpc:C:/fmp-wt/shot.png <暫存目錄>/`。`shot.ps1` 啟動 App、等 8 秒、把視窗拉到最上層再截視窗矩形、關掉 App；`C:\fmp-wt\shot.log` 有 `foreground_is_fmp=True` 才代表截到的是 App。完整閘門跑完後，`Debug\fmp.exe` 已被 `flutter test -d windows` 用 integration_test 的入口重建，實跑前先重跑一次步驟 2（2026-11-11 票 07：直接啟動閘門留下的 exe，畫面正常卻沒有建立資料庫檔）。
4. 清理：排程工作由 `run_task.sh` 刪掉；`ssh winpc 'Get-Process fmp -EA SilentlyContinue'` 確認 App 已關；整個工作樹用 `dart run tool/device_lock.dart -- ssh winpc 'Remove-Item -Recurse -Force C:\fmp-wt'` 清掉（持鎖做，別的 worktree 的閘門可能正在用它）。

注意：

- 建置與截圖都要擁有者已登入 `winpc` 的桌面。截圖會短暫搶走前景視窗，擁有者正在用 `winpc` 時先說一聲。
- 截圖可能夾到擁有者桌面的其他內容（輸入法候選窗、視窗邊緣外的桌面），只留在 `<暫存目錄>`。
- 經 SSH 組 `schtasks /TR` 時反斜線會被吃掉，腳本路徑與參數一律寫正斜線。`schtasks /Query` 的狀態字串是在地化的（zh-TW 是「執行中」）。
- 腳本維持純 ASCII，避開 PowerShell 5.1 以 cp950 讀無 BOM 檔案的問題。原生指令用 `cmd /c "… 2>&1"` 包起來，不設 `$ErrorActionPreference='Stop'`。
- `Start-Process` 失敗不會讓腳本中止，只會拿到 null；`shot.ps1` 用 `-ErrorAction Stop` 把錯誤寫進 log。
- `run_task.sh` 輪詢狀態時 SSH 失敗會重試，連續 12 次才放棄並回傳非零。不能把查詢失敗當成工作結束：刪掉還在跑的排程工作會連同腳本一起終止（2026-11-11 票 02，`winpc` 藍屏時遇到）。

### 其他已知怪癖

上一版文件，用到時重驗：

- **Windows 自動化輸入**：`SendKeys` 與掃描碼為 0 的 `keybd_event` 會讓 Ctrl 組合鍵失效；中文輸入法會吃掉英數字；跨行程最小化與還原會讓 lifecycle 卡在 `inactive`。
- **integration_test**：一次只能給一個檔；Android 不加 `--no-uninstall` 時可能刪掉模擬器上同 applicationId 的 App 連同資料。完整閘門照這兩條做（見上面各平台的「閘門」）。
- **adb server 自己當掉**：完整閘門的 `integration_test android` 報「No running android simulator/emulator」、`flutter devices` 看不到 Android 模擬器時，多半是 Mac 上的 adb server 不在。票 02、06、07 以為是別的 session 重啟了 adb；票 02b 查過，`app/`、`.githooks/`、`.claude/skills/` 都沒有 `adb kill-server`、`start-server`（`verify-legacy-on-device` 收尾的 `adb emu kill` 關的是模擬器，不是 server），閘門也只跑 `flutter devices` 與 `flutter test`。原因是 platform-tools 37.0.1 的 adb server 被區網的 mDNS 封包弄當（事實 K15），下一個 adb 指令再把它叫起來。擁有者 2026-11-11 決定 adb server 以 `ADB_MDNS=0` 啟動（關掉 mDNS，模擬器不靠它）。票 02b 實測：持鎖後 `adb kill-server`、`ADB_MDNS=0 adb start-server`，`adb server-status` 顯示 `mdns_enabled: false`、`mdns_backend: MDNS_DISABLED`，模擬器 1 秒內回到 `device`。之後由誰啟動：包裝指令拿到鎖後、完整閘門找 Android 模擬器之前，各跑一次 `adb start-server`，閘門與包裝指令開的每個指令也都帶 `ADB_MDNS=0`（`app/tool/src/device_lock.dart` 的 `sharedDeviceEnvironment`）。server 不在時就以 `ADB_MDNS=0` 叫起來；在跑時 `start-server` 什麼都不做，不會打斷別的 session。不主動 kill 已經在跑的 server：萬一在跑的是開著 mDNS 的，它當掉後下一次由閘門或包裝指令叫起來的就關掉了。之所以主動叫而不只靠環境變數：`orca emulator …` 是交給 Orca App 去跑 adb，帶的是 Orca 的環境，不是包裝指令的；Orca、Android Studio、其他專案在 server 不在時叫起來的仍會開 mDNS。要全面關掉得把 `ADB_MDNS=0` 放進登入環境（含 Orca 的），那是擁有者機器的設定，還沒做。遇到「No running android simulator/emulator」時跑一次 `ADB_MDNS=0 adb devices`、等模擬器回到 `device` 再重跑那一步。
- **`winpc` 的 Dart 偶發當掉（環境問題）**：`flutter build windows`、Windows 的 `integration_test` 或 `build.ps1` 的 build_runner 偶發失敗。症狀有三種，根源相同：只報 `error MSB8066`（`flutter_assemble.rule` 結束代碼 1，加 `-v` 才看得到 `===== CRASH =====`）；`exit codegen=78`、`exit codegen=-1073740791` 或 `exit codegen=1` 加上 `Compilation did not produce any result`，之後 `flutter build` 因為缺 `database.g.dart` 跟著失敗；或不存在的「缺成員」編譯錯（票 07）。都是 Dart 的 `dartaotruntime.exe`（frontend_server）或 `gen_snapshot.exe` 存取違規（`0xc0000005`），VM 印出 `===== CRASH =====` 後自己 abort（事件記錄是 `0xc0000409`，位移固定在 `0x332aa1`）。票 02b 查證：沒有其他閘門同時跑時，main（`b2fadc04`）連續乾淨建置 5 次，第 4、5 次失敗；在 SSH 工作階段（不經排程工作）對同一份輸入連跑 60 次 `dart compile kernel`（編 pub cache 裡的 build_runner，不含 App 的程式碼），2 次當掉（其中 1 次留下空的輸出檔），成功的 58 次輸出逐位元組相同。三次當掉的位址扣掉 snapshot 基址後都不同（`0x46455d`、`0x6a425`、`0x2b47b2`），呼叫堆疊也不同。同一台機器 14 天內還有 Windows 自己的服務（`sppsvc`、Windows Update、Defender）、MSVC 的 `CL.exe` 與其他使用者程式以存取違規、非法指令（`0xc000001d`）當掉，6 次 Kernel-Power 41（非預期重開），11-10、11-11 有藍屏（兩次 `0x00020001` HYPERVISOR_ERROR、一次 `0x1E`，minidump 在 `C:\WINDOWS\Minidump\`）。結論：是 `winpc` 的硬體或韌體不穩（i9-13900HX、BIOS KWCN54WW、microcode `0x12E`），不是產品也不是閘門；worktree 互蓋可能造成過部分紅燈（票 07 的缺成員錯），但不是當掉的原因。還沒定位到是哪個元件：記憶體、處理器電壓（降壓或超頻工具）、BIOS 或 Hyper-V／VBS，要擁有者在場檢查（Windows 記憶體診斷要重開機）。Intel 的 13、14 代 Vmin 不穩問題官方只認桌上型處理器，行動版說沒有受影響，13900HX 是行動版，不能直接套用。在那之前，閘門照實報紅，遇到時重跑；重跑能過就不是程式問題。照票 02b，說不出原因的重試不收，閘門也沒有自動重試。重現：在 `winpc` 對任一份已經 `pub get` 的 `app/` 連跑 `dart compile kernel --packages=.dart_tool\package_config.json -o <檔> <build_runner>\bin\build_runner.dart` 60 次，約 5 分鐘，失敗率約 3%（2026-11-11）。
- **Android 模擬器**：音訊比實際快約 1.7 倍，不能拿來量時長；`adb shell input text` 打不了中文；畫面持續更新時 `uiautomator dump` 會失敗；Claude Code 的沙箱擋 `adb` 連 5037。
- **macOS**：macOS 27 不讓第三方經 MediaRemote 讀 Now Playing。媒體控制改用輔助使用 API 讀選單列的「正在播放」面板（標題、按鈕、進度條，也能按按鈕與 seek），再對照 `mediaremoted` 的系統 log（brief 事實 M9）；腳本是 `scripts/experiments/macos-now-playing/` 的 `np-panel.sh`、`mediakey.swift`（模擬媒體鍵），要「輔助使用」權限。App 沒出過聲時不是 Now Playing App，這時送媒體鍵會叫起「音樂」App（事實 M10），先播再測。zsh 的 `log` 是內建指令，讀系統 log 要寫 `/usr/bin/log`。Flutter 的語意樹不經 macOS AX 暴露，要用截圖加座標。
- **iOS 模擬器**：沒有可截圖的鎖定畫面與控制中心，Now Playing 只能讀系統 log；不要用 `orca emulator kill`。
- **無害的建置雜訊**：`media_kit_libs_windows_audio` 的 CMake `CMP0175` 警告、`flutter_inappwebview_windows` 在 cp950 下的 C4819、`resolve_symlinks.ps1` 的 `Get-Item` 錯誤。

## 3. 測試策略

- 預設零聯網：`live` tag 預設跳過；`HttpOverrides` 讓任何真實連線直接報錯（`app/test/support/no_network.dart`）。`test/` 由 `flutter_test_config.dart` 裝；`integration_test/` 不吃那個設定，每個檔在 `main()` 裡呼叫 `installNoNetworkGuard()`，`test/architecture/integration_test_guard_test.dart` 守著。
- `domain`、`playback`、`library` 用單元測試，音訊後端用 fake。
- 每個插件套同一套契約測試，用 fixture 重播；錄製工具寫檔前經過遮蔽函式。
- 每個里程碑的主要流程有一條 `integration_test`，四個平台都跑。
- drift 的 schema（M0 票 07）：每個版本的快照在 `app/drift_schemas/app_database/`，升級測試在 `app/test/drift/app_database/`。改 schema 時：改表、`schemaVersion` 加一、在 `app/` 跑 `dart run drift_dev make-migrations`（產生新快照、`generated/` 的各版本資料庫、`lib/data/database.steps.dart`），在 `AppDatabase.migration` 用 `stepByStep` 寫這一步；`migration_test.dart` 自動涵蓋每一對版本，改到既有欄位時照檔頭加資料完整性測試。閘門的 `schema snapshot (drift)` 比對目前的 schema 與最新快照，`migration_test.dart` 比對 `schemaVersion` 與最新快照的版本，忘了任一步都會紅。`*.g.dart` 不進 git，閘門的 `codegen (build_runner)` 先產生。
- 聯網冒煙測試：每個音源每種插件能力最多一條，手動執行，不擋合併；用真實帳號時照 `AGENTS.md` 的最少操作規則。

## 4. 開發環境與閘門

- `dart run tool/check.dart --quick`（在 `app/` 裡跑）：產生 i18n、codegen（build_runner）、format、analyze、單元測試、schema 快照檢查（§3）、文件閘門（還沒驗收的里程碑要有驗收票）；commit 改到 `app/` 時由 `.githooks/pre-commit` 執行。
- `dart run tool/check.dart`（完整版）：quick 之後依序做 macOS、iOS 模擬器、Android 模擬器、Windows（SSH 同步工作樹到 `winpc`、以排程工作執行，不靠 push）的建置，再在四平台跑 `integration_test`（指令見 §2 各平台的「閘門」），最後檢查插件打包產物是否最新（票 08 接上）。前面的步驟失敗也照跑完，最後列出每一步的結果；步驟名稱帶平台，失敗時印成 `FAIL build ios`、`FAIL integration_test windows: integration_test/<檔>`，退出碼非零。前置條件：在 Mac 上跑（iOS 建置要 Xcode），iOS 模擬器與 Android 模擬器先開好，`winpc` 的桌面有人登入。每張票合併前跑完整版。
- **共用裝置鎖**（M0 票 02b）：完整版在 Mac 上的三個建置之後、`build windows` 之前跑 `lock shared devices`，四平台的 `integration_test` 跑完後跑 `unlock shared devices`；中間的步驟（`winpc` 的同步、建置與 integration_test，模擬器與 macOS 的 integration_test）持有鎖時才跑，沒拿到就判失敗。同一時間只有一個 worktree 的完整版在碰共用裝置。
  - 位置：`git rev-parse --path-format=absolute --git-common-dir` 底下（所有 worktree 共用的 `.git`）的 `fmp-device.lock`，持有者資訊在同目錄的 `fmp-device.lock.holder`（JSON：`worktree`、`pid`、`started`）。實作在 `app/tool/src/device_lock.dart`。
  - 包裝指令：`dart run tool/device_lock.dart [--repo <目錄>] -- <指令> [參數…]`（在 `app/` 裡跑，照 util-linux `flock(1)` 包住一個指令的慣例）拿目前目錄所在 repo 的鎖、執行指令、指令結束就放鎖，退出碼是指令的退出碼（被訊號結束時是 128 + 訊號編號）；收到 SIGINT、SIGTERM、SIGHUP 時轉給指令。訊息印到 stderr。`--held` 只回答這個 worktree 是否持有這把鎖（是 0，否則 1）。
  - 腳本自己守：`tool/winpc/` 的每支 `*.sh` 一開頭 source `lock_guard.sh`，沒持鎖就經包裝指令重新執行自己（先拿鎖、必要時等）。`test/tool/device_lock_cli_test.dart` 檢查每支都在碰 `ssh`／`scp` 之前 source 它，新加的腳本也一樣。
  - 可重入：鎖以 worktree 為單位。`.holder` 記的 `worktree` 是自己這個 worktree、而且鎖確實被佔著時，包裝指令與 `tool/winpc/` 的腳本直接執行（完整閘門呼叫的 `sync.sh`、包裝指令裡再包一次、互動時背景持鎖之後下的指令）。持有者死掉後 `.holder` 會留著，但鎖已放掉，不算。完整閘門自己拿鎖時不看這條，背景持鎖要先放掉。
  - adb：包裝指令拿到鎖後、完整閘門找 Android 模擬器之前跑 `adb start-server`，開的指令都帶 `ADB_MDNS=0`（§2〈adb server 自己當掉〉）。
  - 行為：鎖是 OS 的檔案鎖（事實 K16）。別人持有時印出 `Waiting for the shared-device lock …, held by worktree <路徑>, pid <pid>, since <開始時間>` 然後等，沒有逾時。持有的閘門結束、當掉或被 `kill -9` 時，OS 自動放掉鎖，鎖本身不必清理（還在跑的子行程與 `winpc` 排程工作見下一條）。
  - 手動解除：只在持有者卡住時需要。看 `fmp-device.lock.holder` 的 `pid`，`ps -o pid,pgid,command -p <pid>` 確認是 `dart run tool/check.dart` 或 `tool/device_lock.dart`，先 `ps -o pid,command -g <pgid>` 看群組裡只有這個閘門與它開的行程（從沒有 job control 的 shell 啟動時，群組可能包含那個 shell），再用 `kill -- -<pgid>` 停掉整個群組（只停閘門本身時，它開的 `flutter test`、`run_task.sh` 會繼續用裝置），鎖隨之放掉。再確認 `winpc` 上沒有還在跑的排程工作（`ssh winpc 'schtasks /Query /TN fmpbuild'`、`fmptest`），有的話等它結束：排程工作不會跟著 Mac 上的行程結束，下一個閘門同步時會刪掉它正在用的 `C:\fmp-wt\app`。閘門在終端機按 Ctrl-C 時同理。不要刪 `fmp-device.lock`：持有者還活著時刪掉，下一個閘門會鎖到新建的同名檔，兩邊同時碰裝置。也不要刪 `fmp-device.lock.holder`：持有者還活著時刪掉，它自己開的 `sync.sh` 等腳本認不出鎖在自己這邊，會一直等它。持有者死掉後 `.holder` 可能留著，內容是上一個持有者，不影響拿鎖。
- GitHub Actions：新版平常不跑。`app-v*` tag 觸發 `app-release.yml`，跑完整閘門後發佈。舊版的 `ci.yml` 照舊，M0 要確認它不受 `app/` 影響。
- 環境：Flutter 3.47.5（Mac 與 `winpc`）、Xcode 27.1、iOS 27.1 模擬器、Android 模擬器 `Medium_Phone_API_37.0`、Node（開發插件用）、rustup（Rust ≥ 1.95，fjs 在 Android 與 Windows 從原始碼編；`winpc` 的 default host 要是 msvc）。

## 5. 里程碑任務

### 5.1 M0 骨架與 tracer bullet

已開工：[`.scratch/m0/spec.md`](../.scratch/m0/spec.md)。

### 5.2 D 設計稿

和 M0 並行，只產出文件。目標：brief §11 的第一版頁面全部有定稿。

- 先定設計系統（色彩、字級、間距、寬度分級、玻璃與實心兩種材質）。
- App 外殼與其餘頁面都做手機、中寬度與桌面三種寬度、深淺色。
- 有爭議的地方給 A／B 方案。

驗收：擁有者逐頁確認；M1 開工前完成。

### 5.3 M1 三音源與播放核心

目標：三個音源都能搜尋、播放，播放核心完整。

- youtube、netease 插件的搜尋與串流解析。youtube 插件的線索：tag `archive/youtubejs-probe-20261106`（把 YouTube.js 打包成插件的實驗，先查證再沿用）。
- 佇列、臨時播放、播放模式、持久化、串流過期重解析、預載、失敗處理。
- 背景播放與系統媒體控制。
- 照設計稿實作：App 外殼、首頁、搜尋頁、迷你播放器、播放頁、佇列頁；設定頁的外殼、外觀（主題、強調色、語言）與臨時播放倒退秒數；錯誤 Toast（含沒有網路、連續 3 首失敗）。
- 插件的「排行榜」能力（首頁的近期熱門，brief §5.1 第 12 項）。

驗收：四個平台上，三個音源各搜尋並播放一首；臨時播放、隨機與循環的組合照 brief §6 運作；背景播放與媒體控制可用。

### 5.4 M2 帳號與存取等級

目標：三個音源都能登入，會員狀態與存取等級正確呈現。

- 三音源的 QR 與 WebView 登入（YouTube 用 WebView 加貼 cookie）、憑證存放、登出。
- 會員狀態、存取等級徽章、音質選擇、試聽處理（brief §5.4）。
- 照設計稿實作：帳號頁（從設定進入）、設定的音質與「播放時使用登入狀態」、播放頁的音源膠囊與試聽、需驗證的流程。

驗收：四個平台上，三個音源都登入成功；VIP、試聽歌曲的標示與播放行為照 brief §5.4。

### 5.5 M3 音樂庫與遠端歌單

目標：本地歌單、匯入歌單、遠端寫入都可用，並能搬入舊版資料。

- 本地歌單、匯入歌單與刷新、複製成本地歌單。
- 遠端寫入與寫入前確認。
- 照設計稿實作：音樂庫、歌單詳情、加入歌單對話框、搜尋的「歌單中」、播放頁頂列的加入歌單、首頁的最近更新的匯入歌單；設定的刷新間隔與「資料 → 匯入舊版備份」。
- 匯入舊版 JSON 備份。

驗收：用擁有者指定的測試歌單做遠端加入、移除各一次；匯入一份真實的舊版備份，筆數對得上。

### 5.6 M4 歌詞

目標：播放頁顯示歌詞。

- netease、lrclib 插件的歌詞能力。
- 自動匹配、手動搜尋、偏移調整、翻譯並排。
- 照設計稿實作：播放頁的歌詞畫面、歌詞搜尋、設定的歌詞群組、桌面詳情面板的歌詞分段。

驗收：四個平台上，三個音源的曲目都能顯示同步歌詞。

### 5.7 M5 第一版發佈

目標：發佈 `app-v2.0.0` prerelease，交給擁有者試用。

- 照設計稿實作：插件頁（含插件更新，brief §5.1）、設定頁其餘群組（儲存空間、匯出診斷、關於）；三語補齊。
- 效能量測（brief §15）。
- `app-release.yml` 與四個平台的安裝檔（brief §16）。
- 重新開啟 `.github/dependabot.yml` 的 GitHub Actions 版本更新（2026-11-06 因舊版凍結而關閉）。

驗收：四個平台的安裝檔都裝得起來並能播放；效能達標；擁有者試用後同意發佈。

### 5.8 之後的里程碑

照 brief §5.2，第一版發佈後再排序，開工時才寫細節。

## 6. 待決

定了方向、細節未定的事。每條寫明卡在哪、怎麼定；定案後移到對應的章節，這裡刪掉。

- **P1 取代舊版的方式**：同 brief §17。卡在新版功能還沒齊全，到「取代舊版」的里程碑由擁有者決定。
- **P3 插件能力清單**：設計稿用到的能力（搜尋排序、排行榜、評論、點讚、複製連結、在瀏覽器開啟、遠端歌單分建立與收藏等）還沒列成清單，見 `docs/design/audit-2026-11-11.md` §3 第 6 項。宿主 API 在 v2.0.0 凍結，所以清單在 M1 拆票時定，寫進 M1 spec；M0 票 08 只做搜尋與解析串流。定案後寫進 brief §5.3 與 ADR。
- **P5 玻璃三級對 brief 事實 K10**：設計稿的三級定義和 K10 不同，brief §17 的退路做不出折射級。由 M0 票 05b 的實驗定，再一起改 brief 與 `docs/design/DESIGN.md`。

## 7. 風險與回寫點

- YouTube 的 client 會變（事實 F8）：解析串流準備候選序列；壞了就更新插件。
- B 站風控（事實 F2）：網路層依音源限流；登入後要確實帶憑證。
- `flutter_inappwebview` 的穩定版停在 2024-10（事實 R1、K8）：登入票先實測四個平台。
- Windows 的 libmpv 是舊快照（事實 W3）：遇到 Windows 獨有的播放失敗先懷疑它。
- iOS 的中斷與 Now Playing（事實 I2、I5）：模擬器驗不到的部分記在票的 Comments。
- audio_service 更新慢（事實 I5、K17：#1139 的 iOS 修正 2026-07 合併，至今沒發佈）：macOS 端壞了就改用自己的 platform channel 接 `MPNowPlayingInfoCenter`、`MPRemoteCommandCenter`（M0 票 05 已實測可行，原型在 `scripts/experiments/macos-now-playing/probe_channel/`）。
- 實作時發現與 brief 不符：停下來問擁有者，改 brief 並在 progress.md〈偏差與決定〉記一行。
