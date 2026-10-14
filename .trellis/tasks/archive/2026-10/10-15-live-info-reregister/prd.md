# 收聽中停用再啟用插件後重新登記 live-info（#255）

## 目標

收聽直播時把該插件停用再啟用，`live-info` 要恢復，標題、主播、人數繼續更新；
不必停止直播再重新收聽。

## 現況（讀碼確認）

- 停用時 `PluginRegistry.setEnabled` 先呼叫排程器的 `unregisterPlugin`，移除了
  `live-info`，再發出新的插件清單。
- `PlaybackController` 的 `_liveInfoRegistered` 仍是 true，之後的
  `_registerLiveInfo` 直接返回；插件清單改變時控制器只放掉前瞻，不管 `live-info`。

## 要求

1. 插件清單改變時，控制器同步 `live-info`：
   - 已登記、但所屬插件不在清單上 → 當成已移除（清掉登記旗標）；
   - 沒登記、仍在收聽（`LivePhase.listening`）且插件在清單上 → 重新登記。
2. 直播已結束、查詢失敗、停下時（`_haltLive` 移除了工作）不因插件清單改變而重新登記。
   `LiveStop` 停下時階段仍是收聽中，所以另看播放狀態不是 `Idle`、`Failed`（審查發現）。
   控制器釋放途中送達的清單通知也不登記（審查發現）。
3. 停用時正在播的直播照播（M3a 驗收的擁有者決定），只是停用期間不更新。

## 驗收

- 控制器測試：收聽中移除插件（含排程器移除工作）→ 沒有 `live-info`；放回插件 →
  重新登記一次；換到同插件另一個直播間也有登記。
- 控制器測試：直播已結束後插件清單改變，不重新登記。
- 拿掉修正時上面的測試變紅；無關改動維持綠。
- Android 模擬器（重播，`fmp-test`）：收聽 `live-ok`，停用再啟用 `fmp-test`，
  一分鐘內 log 有 `live-info` 的執行。

## 不做

- 不改排程器與 `PluginRegistry` 的順序。

## 結果

- 審查（opus）補了上面第 2 條的兩個守衛與測試，刪了一個重複測試；兩個守衛都做過變異。
- Android 模擬器（dev debug，重播 `fmp-test`，沒有真實請求）：收聽 `live-ok`，
  UTC 18:59:04 停用再啟用 `fmp-test`；`scheduler_runs` 的 `live-info` 之後在
  19:00:21、19:01:21 成功，每分鐘照常更新。
- 本機 `flutter test` 有兩個 trackDetail 測試紅，是 `core.autocrlf=true` 把
  `test_plugin.js` checkout 成 CRLF，測試的字串替換對不上；改回 LF 後全過，與本修正無關。
