# 05c: 完整閘門跑 iOS 時模擬器不見

Status: done
Blocked by: None
讀: `docs/development.md`〈開發環境與閘門〉〈平台〉的 iOS 模擬器；`app/tool/src/full_gate.dart`、`app/tool/src/device_lock.dart`；票 04、05 的 Comments（完整閘門那段）；spec〈共同規則〉

2026-11-15 協調者插票（擁有者同意）：同一條紅燈出現第二次。票 04、05 跑 `dart run tool/check.dart` 完整版時，iOS 的兩個 `integration_test` 都以 `No running ios simulator/emulator found` 失敗；開回 iPhone 模擬器重跑就綠，兩個 session 都說不是自己關的（05 只關過自己開的 iPad 模擬器）。閘門只挑已經開著的模擬器，不會自己開。修復票的驗收包含回頭補勾被它卡住的票：04、05 都已用重跑通過合併，不用補。

## What to build

先分清是產品、閘門還是環境的問題，找出 iOS 模擬器是被誰、在哪一步關掉的，修根因。

- 先寫出失效條件：能重現「完整版跑到 iOS 時模擬器不在」的 repro（例如照票 04、05 的順序：開著 iPhone 模擬器、另外開關一台 iPad 模擬器、跑完整版或其中幾步），修之前會紅。懷疑對象至少查：完整版自己的步驟（建置、`--no-uninstall`、裝置鎖前後）、關掉另一台模擬器時連帶關掉（Simulator.app 結束、`simctl shutdown`）、Orca 的模擬器面板。
- 修根因。根因在共用環境、修不到時，閘門在 iOS 步驟前確認有開著的 iPhone 模擬器，沒有就開一台並印出原因，不能靜默跳過；只拉長逾時、說不出原因的重試不收。
- 查到的平台行為補成事實；`docs/development.md`〈開發環境與閘門〉的前置條件照實改。

## 驗收

- [x] 有 repro，修之前紅、修之後綠；根因寫在 Comments（或寫明為什麼查不到）。
- [x] 完整版連續跑兩輪（中間照 repro 的方式開關另一台模擬器），iOS 步驟都綠。
- [x] `docs/development.md` 的前置條件與實際行為一致。
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments

根因：Orca（1.4.258）的模擬器面板。同一個 worktree 的面板從一台 iOS 模擬器換到另一台時，Orca 先停掉前一台的串流行程、再 `xcrun simctl shutdown` 前一台（`app.asar` 的 `stopActiveForSwitch` 對 iOS 帶 `shutdownDevice`；別的 worktree 也接著它時不關，Android 不關）。是共用環境的行為，修不到，所以照票面的退路改閘門。
證據：iPhone 18 Pro 自己的 log（`xcrun simctl spawn <udid> log show`）記到 11-15 四次關機，都是 `System shutdown initiated by kernel - launchd got a SIGTERM`（12:57:49、13:13:39、17:37:47、17:40:39）。票 05 那次（17:37:47）：17:37:46.976 一個 Orca 行程（17:35:58 起的串流 helper）和 CoreSimulatorService 斷線，17:37:47.14 起一個 simctl，17:37:47.225 iPhone 收到 SIGTERM，和 `stopActiveForSwitch` 的順序相同。12:57:49 也是 Orca 行程先斷線、接著關機；票 04 閘門那次（13:13:39）是 Orca 行程 13:13:33 結束、6 秒後關機，像同一個原因，但查不到那時面板換過裝置。
其他懷疑對象：閘門自己的步驟（建置、`--no-uninstall`、裝置鎖前後）排除：閘門與 repo 裡沒有任何 `simctl shutdown`、`orca emulator shutdown`，下面的 repro 不經閘門也重現；Simulator.app 結束排除：它整天沒在跑（Orca 面板用 serve-sim 串流，不開 Simulator.app）；關另一台時連帶關掉排除：持鎖直接 `simctl bootstatus <iPad> -b`、`simctl shutdown <iPad>`，iPhone 一直開著。
repro（scratch 腳本，持鎖跑閘門自己的 `lock shared devices` 與 `integration_test ios` 兩步）：`orca emulator attach <iPhone>` → `orca emulator attach <iPad>`（`simctl list devices booted` 只剩 iPad）→ `xcrun simctl shutdown <iPad>`（一台都沒有）→ 修改前的 `full_gate.dart` 報 `FAIL … No running ios simulator/emulator found`（紅，和票 04、05 同一句）；修改後印 `No booted iPhone simulator … booting iPhone 18 Pro (…)`，開機後 `app_test.dart` 通過（綠）。單元測試 `full_gate_test.dart`〈iOS simulator〉的三條改之前紅兩條。
修法：iOS 改從 `xcrun simctl list devices --json` 挑開著的 iPhone（事實 T5），沒有就印出原因、以 `simctl bootstatus <udid> -b` 開最近用過的那台 iPhone，每個 iOS 檔前都查一次；一台可用的 iPhone 都沒有時判失敗。閘門只知道「沒有開著的 iPhone」，不知道是誰關的，訊息裡的 Orca 是舉例。
兩輪完整閘門（`7a4f250c`）：第 1 輪全綠（iPhone 開著）。中間持鎖照 repro 做一次（attach iPhone → attach iPad → 關 iPad，`simctl list devices booted` 變空）。第 2 輪印出 `No booted iPhone simulator … booting iPhone 18 Pro (…)`，iOS 兩個檔都綠；`build windows` 與 Windows 的兩個 integration_test 紅在 `exit codegen=78`、缺 `database.g.dart`，是 docs/development.md〈其他已知怪癖〉的 `winpc` Dart 偶發當掉，同一個 commit 第 1 輪是綠的。
code-review 未處理：`test/tool/support/concurrent_gate.dart` 另寫一份 simctl JSON，和 `full_gate_test.dart` 的 `_simctlJson` 同形（原本的 `flutter devices` fixture 也各寫一份）
code-review 未處理：Android 找不到模擬器的訊息仍是 `No running android simulator/emulator`，docs/development.md〈adb server 自己當掉〉照原句引用
Session 紀錄：2026-11-15 從模擬器自己的 log 查出 Orca 面板換裝置會關掉前一台 iOS 模擬器，做 repro，閘門改成沒有開著的 iPhone 就開一台並印出原因
決定：根因在 Orca，修不到，照票面的退路改閘門：iOS 步驟前確認有開著的 iPhone，沒有就開一台並印出原因（Agent 定）
決定：閘門的 iOS 只用 iPhone 模擬器，iPad 開著也不用；改從 `simctl list devices --json` 挑（Agent 定）
決定：沒有開著的 iPhone 時開 `lastUsedAt` 最新的那台可用 iPhone，不寫死裝置名稱（Agent 定）
決定：Orca 面板的行為是驗證工具的怪癖，照 brief〈事實索引〉寫在 development.md〈其他已知怪癖〉；閘門依賴的 simctl 行為寫成事實 T5（Agent 定）
決定：事實照「當時的下一號」用 T5；沒合進 main 的 `bk` 分支也有一條 T5，若它之後要合併，照第 7 步改號（Agent 定）
決定：上一版文件寫的「不要用 `orca emulator kill`」實測後改寫：它只停串流、清登記，不關機（Agent 定）
變更：無
