# 02b: 完整閘門獨佔共用裝置

**What to build:** 讓 `dart run tool/check.dart` 完整版用到的共用資源同一時間只給一個 worktree 用：`winpc` 的 `C:\fmp-wt`、iOS 模擬器、Android 模擬器，以及 macOS 上同一個 `com.personal.fmp.dev`。現在 `app/tool/winpc/sync.sh` 每次都先刪掉 `C:\fmp-wt\app` 再解開，路徑不分 worktree；兩張票同時跑完整版時，後同步的會刪掉前一張正在建置的程式碼，模擬器上的 App 也會互相覆蓋安裝，綠燈可能測到另一張票的程式碼。票 06、07 在 `winpc` 碰到的 Dart frontend_server 崩潰（MSB8066）可能就是這樣來的。協調者 2026-11-11 插票：同一條紅燈出現第二次，加上票 07 的 Heads up 指出互蓋。

讀：plan §2、§4；票 02、06、07 的 `## Comments`；spec〈共同規則〉

**Blocked by:** None (can start immediately)

**Status:** done

- [x] 先寫出失效條件：能重現「兩個 worktree 同時跑會互相覆蓋」的 repro 或測試，修之前會紅。
- [x] 完整版在碰共用裝置之前取得一把跨 worktree 的鎖（放在所有 worktree 都看得到的位置，例如 `git rev-parse --git-common-dir` 底下），涵蓋 `winpc` 的同步、建置、`integration_test`，iOS、Android 模擬器與 macOS 的 `integration_test`。拿不到就等，並印出持有者（worktree、pid、開始時間）。持有的行程異常結束後，鎖能被回收，不會永久卡住。
- [x] 鎖有測試：取得、等待、持有者死掉後回收；在測試檔內做雙向變異驗證（拿掉鎖會紅，改無關格式不紅）。
- [x] 查清 `winpc` 的 frontend_server 崩潰：在沒有其他閘門同時跑的情況下，main 上連續跑 Windows 建置 5 次並記錄結果。仍會崩潰就用 `mattpocock-skills:diagnosing-bugs` 找根因，寫明是產品、閘門還是環境的問題；只拉長逾時或加重試、說不出原因的不收。
- [x] 查清「adb 被別處重啟」的來源：閘門或腳本裡有沒有 `adb kill-server`、`start-server` 或其他會重啟 adb 的呼叫；結論寫進 plan §2。
- [x] plan §2、§4 寫明鎖的位置、行為與怎麼手動解除。
- [x] 貼一次完整版綠燈的輸出。

## Comments

### 決定與取捨

- **鎖的做法**：`app/tool/src/device_lock.dart` 的 `DeviceLock`，用 Dart 的 `RandomAccessFile.lock()`（macOS 上是 fcntl 鎖，事實 K16）鎖 `<git common dir>/fmp-device.lock`。持有的行程一死，OS 就放掉鎖，不用 pid 存活檢查，也沒有 pid 重用的問題。fcntl 鎖屬於整個行程：同一個行程裡另外打開這個檔再關掉，鎖就會被放掉。所以持有者資訊（worktree、pid、開始時間）寫在另一個檔 `fmp-device.lock.holder`，鎖檔除了持鎖的 handle 之外誰都不碰。拿不到鎖時先印持有者再等，沒有逾時（票寫「拿不到就等」）。`acquire` 只把 EAGAIN（errno 35，Linux 的 11、13）當成「別人持有」，其他錯誤先關掉 handle 再拋出。
- **鎖的範圍**：`platformSteps` 在 Mac 上的三個建置（只寫這個 worktree 的 `build/`）之後才上鎖，`build windows` 到最後一個 integration_test 都在鎖裡，最後 `unlock shared devices`。鎖裡的步驟都包一層：沒持有鎖就判失敗、不執行，所以拿鎖出錯時也不會在沒鎖的情況下碰裝置。`check.dart` 用 `DeviceLock.forRepo(app)` 決定鎖的位置。
- **測試**（`test/tool/device_lock_test.dart`、`full_gate_test.dart`）：
  - repro：兩個子行程模擬兩個 worktree，同時跑真的 `platformSteps`，用假的 `Shell` 把 `C:\fmp-wt` 與模擬器換成共用目錄裡的檔。修之前寫好、跑出紅燈（兩邊都報 `winpc/sim/emu was overwritten`），修之後轉綠，而且輸出裡有 `Waiting for the shared-device lock`，證明兩邊真的撞在一起過。
  - 鎖本身：沒人持有時馬上拿到；別人持有時印出持有者並等待，放掉後拿到；持有者被 `kill -9` 後拿得到；放掉後下一個 worktree 拿得到；`forRepo` 從主 worktree 與 linked worktree 找到同一個鎖檔，位置在 git common dir 底下。
  - 閘門：每個碰 `winpc`、模擬器與 Mac 上 App 的指令都在持鎖時跑，跑完放掉鎖。
- **雙向變異（在測試檔內）**：
  - 會紅：拿掉 `lock shared devices` 步驟；每個 worktree 用各自的鎖檔（等於拿掉鎖），repro 就互蓋；在錄下來的執行紀錄裡，把任何一個共用裝置指令標成沒持鎖。
  - 不紅：改 integration_test 檔名、多一個本機步驟、調換 Mac 建置的順序；只有 Mac 建置與 `flutter devices` 在鎖外。
  - 另外手動改過正式碼：拿掉 `acquire` 的阻塞等待，等待測試與 repro 變紅；拿掉鎖步驟與包裝，閘門的鎖測試與 repro 變紅；只改區域變數名稱，全部仍綠。
- **實機確認**：完整版持有鎖時，從另一個行程去拿 `<repo>/.git/fmp-device.lock`，印出 `Waiting for the shared-device lock <repo>/.git/fmp-device.lock, held by worktree <repo 的 t02b worktree>, pid 84446, since 2026-11-11T21:05:14.077122` 並等待；停掉它不影響閘門。
- **手動實跑**：第一輪只寫了「動手前先看 `.holder`」，第二輪（見下面〈補強：手動實跑也經過鎖〉）改成一律經過鎖。

### `winpc` 的 frontend_server 崩潰（diagnosing-bugs）

結論：**環境問題**（`winpc` 的硬體或韌體不穩），不是產品，也不是閘門。細節與重現方式寫在 plan §2〈其他已知怪癖〉。

- 沒有其他閘門同時跑（協調者確認）時，main `b2fadc04` 連續乾淨同步並建置 5 次，每次都和閘門一樣先刪 `C:\fmp-wt\app`：

  ```text
  run 1 secs=148 exit pubget=0 exit slang=0 exit codegen=0 exit build=0
  run 2 secs=83  exit pubget=0 exit slang=0 exit codegen=0 exit build=0
  run 3 secs=83  exit pubget=0 exit slang=0 exit codegen=0 exit build=0
  run 4 secs=40  exit pubget=0 exit slang=0 exit codegen=1 exit build=1            # build_runner 預編譯：Compilation did not produce any result
  run 5 secs=67  exit pubget=0 exit slang=0 exit codegen=-1073740791 exit build=1  # ===== CRASH =====
  ```

  兩次 `exit build=1` 都是 codegen 失敗、缺 `database.g.dart` 之後連帶的 MSB8066。
- 回饋迴圈：在 SSH 工作階段（不經排程工作、沒有桌面）對同一份輸入連跑 60 次 `dart compile kernel`（編 pub cache 裡的 build_runner 2.17.1，不含 App 的程式碼），每次約 5 秒。結果 2 次當掉（`ExceptionCode=-1073741819`，其中 1 次留下空的輸出檔），成功的 58 次輸出 SHA-256 全部相同。
- 三次當掉（迴圈兩次、閘門一次）的位址扣掉 `isolate_instructions` 基址後都不同：`0x46455d`、`0x6a425`、`0x2b47b2`，呼叫堆疊也不同。事件記錄裡的 `0xc0000409` 都落在 `dartaotruntime.exe+0x332aa1`，那是 VM 印出 `===== CRASH =====` 後自己 abort 的地方，真正的錯是前面的存取違規。
- 假設與驗證：
  1. 閘門互蓋：已排除。單一行程、沒有其他閘門時也會當。
  2. 排程工作或桌面工作階段：已排除。SSH 工作階段一樣會當。
  3. 我們的程式碼：已排除。編的是 build_runner，不碰 App 的程式碼。
  4. Dart SDK 3.13.4 在 Windows 上有確定性的 bug：很不像。輸入相同，當掉的位置卻每次不同。
  5. 硬體或韌體不穩：符合。同一台機器 14 天內有 73 次程式當掉，除了 Dart，還有 Windows 自己的服務（`sppsvc`、Windows Update、Defender 的 `MsMpEng`）、MSVC 的 `CL.exe`，以及以非法指令 `0xc000001d` 當掉的使用者程式；另有 6 次 Kernel-Power 41 與先前的藍屏。
- 還沒定位到是哪個元件：記憶體、處理器電壓設定、BIOS（KWCN54WW，microcode `0x12E`）或 Hyper-V／VBS。要擁有者在場處理：Windows 記憶體診斷要重開機，協調者這次不准重開 `winpc`。Intel 的 Vmin 不穩問題官方只認桌上型處理器，`winpc` 的 i9-13900HX 是行動版，不能直接套用。
- 閘門不改：照票，只加重試或拉長逾時、說不出原因的做法不收。紅燈照實報，重跑能過就是這個問題。這次的完整版也碰到一次（見下面〈驗證輸出〉）。
- 票 06、07 的猜測：互蓋可能造成過部分紅燈（例如票 07 那個不存在的「缺成員」錯），但當掉本身和互蓋無關。

### 「adb 被別處重啟」

- 查過：`app/`、`.githooks/`、`.claude/skills/` 與已安裝的 skill 都沒有 `adb kill-server`、`start-server`。`verify-legacy-on-device` 收尾時的 `adb emu kill` 關的是模擬器，不是 adb server。閘門只跑 `flutter devices` 與 `flutter test`。機器上只有一個 adb（platform-tools 37.0.1）。
- 原因是 adb server 自己當掉：`~/Library/Logs/DiagnosticReports/adb-*.ips` 有 25 份（11-08 至 11-11），父行程都是 launchd，堆疊都在 Rust 的 mDNS 模組裡（`adbmdns_bridge` → `simple_dns` 的 `Name::try_from`）panic 後 abort。adb server log 從 11-10 18:53 起有 53 次啟動。下一個 adb 指令會再把它叫起來，所以看起來像被別人重啟。這次開工時 server 也已經不在了。寫進 brief 事實 K15 與 plan §2。
- 根治的方法是讓 adb server 以 `ADB_MDNS=0` 啟動（官方文件與 Issue Tracker 573133666）。但這要先停掉現有的 server，會打斷正在用模擬器的 session，而協調者這次不准 kill adb，所以沒有實測，留給擁有者決定。

### code-review 處理

- 已修：
  - plan 的迴圈次數寫錯（原本寫成 2 次當掉加 1 次空檔，其實空檔是其中一次當掉）。
  - 手動解除改成停整個行程群組，並先確認 `winpc` 上沒有排程工作在跑（只 kill 閘門時，`flutter test`、`run_task.sh` 與 `winpc` 的排程工作會繼續用裝置）。已實測 Dart 開的子行程和它在同一個群組。
  - 手動實跑改成先用 `ps -p` 確認持有者還在不在。
  - 補檢查器本身的雙向變異、拿掉鎖的 repro 變異與 `forRepo` 的測試。
  - `acquire` 只把 EAGAIN 當成被佔用。
  - `_sharedDeviceSteps` 併回 `platformSteps`（重複的 `flutter` helper 跟著消失）；`_FakeShell.log` 改名為 `ranWithLock`。
- 不修：
  - 持有者剛拿到鎖、還沒寫好 `.holder` 的那一瞬間，等待的一方可能印出上一任的資訊或 `unknown`，只影響提示文字。
  - repro 的 `Waiting` 斷言靠兩個子行程同時開跑（兩邊都印出 `ready` 之後才一起送 `go`，持鎖段約 1.5 秒），理論上機器極忙時可能沒撞到。
  - 持有者 JSON 的鍵在讀和寫各出現一次。
  - K15 的出處用 `~/Library/...`，是 macOS 的通用路徑，plan §2 也這樣寫。
  - frontend_server 崩潰只定到「環境」，元件要擁有者在場查，見上一節。

### 驗證輸出

`cd app && dart run tool/check.dart`（完整版，commit `8418e14b`，2026-11-11）：

```text
Holding the shared-device lock <repo>/.git/fmp-device.lock
ok   i18n (slang)
ok   codegen (build_runner)
ok   format
ok   analyze
ok   test                     # 00:10 +143: All tests passed!
ok   schema snapshot (drift)
ok   doc gate
ok   build macos
ok   build ios
ok   build android
ok   lock shared devices
ok   build windows            # exit pubget=0、exit slang=0、exit codegen=0、exit build=0
ok   integration_test macos: integration_test/app_test.dart     # +2: All tests passed!
ok   integration_test ios: integration_test/app_test.dart       # +2: All tests passed!
ok   integration_test android: integration_test/app_test.dart   # +2: All tests passed!
ok   integration_test windows: integration_test/app_test.dart   # +2: All tests passed!、exit test=0
ok   unlock shared devices
gate_exit=0
```

這個 session 一共跑了 5 次完整版，綠燈是 `e42082b9` 的第 2 次與 `8418e14b` 的第 5 次。另外 3 次的紅燈都是這張票查清楚的環境問題，沒有一次和程式有關：

- 第 1 次：`FAIL build windows` 與 `FAIL integration_test windows`。build_runner 在 `winpc` 當掉（`exit codegen=-1073740791`、`===== CRASH =====`），Windows 的 integration_test 因為缺 `database.g.dart` 跟著失敗。
- 第 3 次：`FAIL integration_test windows`，只報 `MSB8066`。
- 第 4 次：`FAIL build windows`（只報 `MSB8066`）與 `FAIL integration_test android`（`No running android simulator/emulator`）。Mac 上的 adb server 在 21:21:50 又重啟（事實 K15），`flutter devices` 剛好在 server 不在時執行。

每次都有 `lock shared devices`／`unlock shared devices`，鎖照預期取得與放掉。

### 補強：手動實跑也經過鎖（協調者 2026-11-11 追加）

協調者轉來的 Heads up 經查證屬實：手動跑 `sync.sh` 或手動裝 App 不經過鎖，A 票跑閘門時 B 票手動實跑，照樣會蓋掉 A 的程式碼。協調者接下來要同時跑兩張票，所以在這張票補齊。commit `a0ee3f89`、`d4c566b4`。

- **包裝指令** `app/tool/device_lock.dart`：照 util-linux `flock(1)`「包住一個指令」的慣例。
  - `dart run tool/device_lock.dart [--repo <目錄>] -- <指令>`：拿同一把鎖、寫同一份持有者資訊，執行指令後放鎖，退出碼照傳（被訊號結束時是 128 + n）。SIGINT、SIGTERM、SIGHUP 會轉給指令。死掉時同樣由 OS 放鎖。
  - `--held`：只回答「這個 worktree 是否持有這把鎖」。
- **腳本自己守**：`tool/winpc/lock_guard.sh` 由 `sync.sh`、`run_task.sh` 一開頭 source。沒持鎖就經包裝指令重新執行自己，等於自己拿鎖。重新執行時用腳本的絕對路徑，所以 `bash sync.sh` 這種只給檔名的叫法也行。測試會檢查 `tool/winpc/` 的每支 `*.sh` 都在碰 `ssh`／`scp` 之前 source 它。
- **可重入的判斷**：先做成「持有者是祖先行程」（沿 `ps -o ppid=` 往上找），審查後改成「`.holder` 的 worktree 是自己這個，而且鎖確實被佔著」。理由：
  - 鎖本來就是跨 worktree 的，同一個 worktree 就是同一張票。
  - 互動實跑要跨好幾輪讀畫面、操作，可以先在背景用 `dart run tool/device_lock.dart -- sleep <秒>` 持鎖，之後這個 worktree 下的指令都不必等。祖先判斷做不到這件事：另開的 shell 不是背景持有者的子行程，`sync.sh` 會一直等它。
  - 沒有採用協調者舉例的環境變數：殘留或手動設的變數會繞過鎖，`.holder` 加上鎖的實際狀態比較可靠。
  - 代價：如果有人在持有者還活著時刪掉 `.holder`，它自己開的腳本會一直等它。plan §4 已寫明不要刪。
- **plan §2**：手動實跑一律經過鎖，分兩種用法，一口氣做完的（整串包進一個 `bash -c`）與互動的（背景持鎖）。各平台的「實跑」改成持鎖的寫法：macOS 開 dev App、iOS／Android 安裝並啟動、`winpc` 的同步、建置、截圖、取回截圖，以及清掉 `C:\fmp-wt`，步驟之間都用 `&&` 串接。手動解除寫在 §4，持有者可能是閘門，也可能是包裝指令。AGENTS.md 與 spec 沒動。
- **測試**（`test/tool/device_lock_cli_test.dart`，在暫存的 git repo 裡跑，PATH 前面放一支假的 `adb`，不碰開發機上真的鎖與 adb server）：
  - 包裝指令：持鎖時執行、放鎖、退出碼照傳；別的 worktree 持有時印出持有者並等待；巢狀不等自己；這個 worktree 在背景持鎖時直接執行；`--held` 的三種情況；拿到鎖後以 `ADB_MDNS=0` 跑 `adb start-server`，指令也帶 `ADB_MDNS=0`。
  - 守門：沒持鎖時先拿鎖，別的 worktree 持有就等；只給檔名也能重新執行；持鎖的行程（閘門）呼叫時直接跑。
  - 靜態規則的雙向變異（在測試檔內）：拿掉 source、註解掉、移到第一個 `ssh`／`scp` 之後都會紅；加註解或空行、改變數名、在守門前多一個無關指令、縮排都不紅。
  - 這輪的測試是先寫實作才補的，所以改正式碼做變異，每一項都讓對應的測試變紅，還原後全綠：
    - 不檢查 worktree；
    - 永遠不可重入；
    - 守門改回直接用 `$0`；
    - 包裝指令不拿鎖；
    - 守門不重新執行；
    - 包裝指令不叫 adb；
    - 閘門不叫 adb。
- **真實環境驗證**：
  - 單獨跑 `tool/winpc/sync.sh`，印出 `Holding the shared-device lock <repo>/.git/fmp-device.lock` 後同步，退出碼 0。
  - 背景 `dart run tool/device_lock.dart -- sleep 40` 持鎖時跑 `sync.sh`，沒有另外拿鎖，2 秒完成；`kill` 背景持有者後鎖與 `.holder` 都放掉了。
  - 完整版裡只出現一次 `Holding`：閘門呼叫 `sync.sh`、`run_task.sh` 時沒有卡住等自己。

### 擁有者的決定（2026-11-11，協調者轉達）

1. **`winpc` 硬體檢查**：先不查，遇到 Dart 崩潰就重跑，不重開 `winpc`。plan §2 維持「重跑那一步」。
2. **adb 用 `ADB_MDNS=0`**：在這張票實測。21:41 用包裝指令持鎖，`adb kill-server` 回 `cannot connect to daemon`（server 在那之前又自己當掉了），接著 `ADB_MDNS=0 adb start-server`。`adb server-status` 顯示 `mdns_backend: MDNS_DISABLED`、`mdns_enabled: false`，模擬器 1 秒內回到 `device`。到 22:09 為止 server 沒再重啟（adb log 的啟動次數停在 58，中間跑了 4 次完整版），在那之前是 11-10 18:53 起 57 次。結果寫進 brief 事實 K15（協調者說的 K16 是 Dart 檔案鎖那條）與 plan §2。
   - 之後由誰、怎麼以 `ADB_MDNS=0` 啟動：包裝指令拿到鎖後、完整閘門找 Android 模擬器之前，各跑一次 `adb start-server`，兩者開的指令也都帶 `ADB_MDNS=0`（`sharedDeviceEnvironment`）。
   - 判斷與理由：server 不在時就以 `ADB_MDNS=0` 啟動；在跑時 `start-server` 什麼都不做，不會打斷別的 session，所以不必先偵測，也不主動 kill 開著 mDNS 的 server，它當掉後由閘門或包裝指令叫起來的就關掉了。只靠環境變數不夠：`orca emulator …` 交給 Orca App 跑 adb，帶的是 Orca 的環境（審查時指出）。
   - 要全面關掉，得把 `ADB_MDNS=0` 放進擁有者的登入環境（含 Orca 的）。那是機器設定，這張票沒做。

### 補強的 code-review

- 已修：
  - `$0` 只有檔名時重新執行會失敗；
  - SIGHUP 沒轉給指令；
  - 被訊號結束時的退出碼；
  - `heldByThisWorktree` 與 `acquire` 重複的非阻塞上鎖，抽成 `_tryLock`；
  - `lock_repo` 改名 `lock_dir`；
  - 測試輔助檔的註解；
  - plan 裡 Windows 的清理與取回截圖原本在鎖外；
  - 互動實跑原本沒有辦法做；
  - iOS 讀文字的指令沒寫完整；
  - Android 那串用 `;` 會吃掉失敗；
  - 「包裝指令帶 `ADB_MDNS=0` 就夠」說得太滿（Orca 的 adb）；
  - progress 那一列的待決敘述已過時。
- 不修：
  - 在終端機按 Ctrl-C 時，指令本來就會收到 SIGINT，包裝指令再轉一次，等於收到兩次，無害。
  - pid 被重用造成誤判的機率可以忽略（現在只看 worktree，這點已經不適用）。
  - `lock_guard.sh` 的註解維持英文，和同目錄的腳本一致。

### 補強後的驗證輸出

`cd app && dart run tool/check.dart`（完整版，commit `d4c566b4`，2026-11-11）：

```text
Holding the shared-device lock <repo>/.git/fmp-device.lock
ok   i18n (slang)
ok   codegen (build_runner)
ok   format
ok   analyze
ok   test                     # 00:17 +158: All tests passed!
ok   schema snapshot (drift)
ok   doc gate
ok   build macos
ok   build ios
ok   build android
ok   lock shared devices
ok   build windows            # exit pubget=0、exit slang=0、exit codegen=0、exit build=0
ok   integration_test macos: integration_test/app_test.dart     # +2: All tests passed!
ok   integration_test ios: integration_test/app_test.dart       # +2: All tests passed!
ok   integration_test android: integration_test/app_test.dart   # +2: All tests passed!
ok   integration_test windows: integration_test/app_test.dart   # +2: All tests passed!、exit test=0
ok   unlock shared devices
gate_exit=0
```

補強期間的另外兩次完整版都只紅在 Windows，都是 `winpc` 上已知的 Dart 當掉，照擁有者的決定重跑：

- `a0ee3f89`：`FAIL build windows`，build_runner `===== CRASH =====` 後 `Compilation did not produce any result`；
- `d4c566b4` 第一次：`FAIL integration_test windows`，只報 `MSB8066`。

Android 在 `ADB_MDNS=0` 之後每次都過。
