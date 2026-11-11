# 02b: 完整閘門獨佔共用裝置

**What to build:** 讓 `dart run tool/check.dart` 完整版用到的共用資源同一時間只給一個 worktree 用：`winpc` 的 `C:\fmp-wt`、iOS 模擬器、Android 模擬器，以及 macOS 上同一個 `com.personal.fmp.dev`。現在 `app/tool/winpc/sync.sh` 每次都先刪掉 `C:\fmp-wt\app` 再解開，路徑不分 worktree；兩張票同時跑完整版時，後同步的會刪掉前一張正在建置的程式碼，模擬器上的 App 也會互相覆蓋安裝，綠燈可能測到另一張票的程式碼。票 06、07 在 `winpc` 碰到的 Dart frontend_server 崩潰（MSB8066）可能就是這樣來的。協調者 2026-11-11 插票：同一條紅燈出現第二次，加上票 07 的 Heads up 指出互蓋。

讀：plan §2、§4；票 02、06、07 的 `## Comments`；spec〈共同規則〉

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 先寫出失效條件：能重現「兩個 worktree 同時跑會互相覆蓋」的 repro 或測試，修之前會紅。
- [ ] 完整版在碰共用裝置之前取得一把跨 worktree 的鎖（放在所有 worktree 都看得到的位置，例如 `git rev-parse --git-common-dir` 底下），涵蓋 `winpc` 的同步、建置、`integration_test`，iOS、Android 模擬器與 macOS 的 `integration_test`。拿不到就等，並印出持有者（worktree、pid、開始時間）。持有的行程異常結束後，鎖能被回收，不會永久卡住。
- [ ] 鎖有測試：取得、等待、持有者死掉後回收；在測試檔內做雙向變異驗證（拿掉鎖會紅，改無關格式不紅）。
- [ ] 查清 `winpc` 的 frontend_server 崩潰：在沒有其他閘門同時跑的情況下，main 上連續跑 Windows 建置 5 次並記錄結果。仍會崩潰就用 `mattpocock-skills:diagnosing-bugs` 找根因，寫明是產品、閘門還是環境的問題；只拉長逾時或加重試、說不出原因的不收。
- [ ] 查清「adb 被別處重啟」的來源：閘門或腳本裡有沒有 `adb kill-server`、`start-server` 或其他會重啟 adb 的呼叫；結論寫進 plan §2。
- [ ] plan §2、§4 寫明鎖的位置、行為與怎麼手動解除。
- [ ] 貼一次完整版綠燈的輸出。

## Comments
