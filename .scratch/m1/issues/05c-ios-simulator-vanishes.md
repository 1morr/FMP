# 05c: 完整閘門跑 iOS 時模擬器不見

Status: ready-for-agent
Blocked by: None
讀: `docs/development.md`〈開發環境與閘門〉〈平台〉的 iOS 模擬器；`app/tool/src/full_gate.dart`、`app/tool/src/device_lock.dart`；票 04、05 的 Comments（完整閘門那段）；spec〈共同規則〉

2026-11-15 協調者插票（擁有者同意）：同一條紅燈出現第二次。票 04、05 跑 `dart run tool/check.dart` 完整版時，iOS 的兩個 `integration_test` 都以 `No running ios simulator/emulator found` 失敗；開回 iPhone 模擬器重跑就綠，兩個 session 都說不是自己關的（05 只關過自己開的 iPad 模擬器）。閘門只挑已經開著的模擬器，不會自己開。修復票的驗收包含回頭補勾被它卡住的票：04、05 都已用重跑通過合併，不用補。

## What to build

先分清是產品、閘門還是環境的問題，找出 iOS 模擬器是被誰、在哪一步關掉的，修根因。

- 先寫出失效條件：能重現「完整版跑到 iOS 時模擬器不在」的 repro（例如照票 04、05 的順序：開著 iPhone 模擬器、另外開關一台 iPad 模擬器、跑完整版或其中幾步），修之前會紅。懷疑對象至少查：完整版自己的步驟（建置、`--no-uninstall`、裝置鎖前後）、關掉另一台模擬器時連帶關掉（Simulator.app 結束、`simctl shutdown`）、Orca 的模擬器面板。
- 修根因。根因在共用環境、修不到時，閘門在 iOS 步驟前確認有開著的 iPhone 模擬器，沒有就開一台並印出原因，不能靜默跳過；只拉長逾時、說不出原因的重試不收。
- 查到的平台行為補成事實；`docs/development.md`〈開發環境與閘門〉的前置條件照實改。

## 驗收

- [ ] 有 repro，修之前紅、修之後綠；根因寫在 Comments（或寫明為什麼查不到）。
- [ ] 完整版連續跑兩輪（中間照 repro 的方式開關另一台模擬器），iOS 步驟都綠。
- [ ] `docs/development.md` 的前置條件與實際行為一致。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
