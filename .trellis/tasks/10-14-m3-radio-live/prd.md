# 電台與直播播放（M3b PR 18b）

父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`（implement.md §18、design §3.1、§3.3、§8、§9.1、§9.2、§9.4、§4.9）。依據 ADR 0031 §決定 1、2、6、7，ADR 0018 §決定 6、7、9（含更正），ADR 0017。

PR 18 的第三塊（18a 宿主 `live` #247、18a-plugins B 站 `live` fmp-plugins#10 之後）。介面在 18c：這個 PR 只做資料、服務、排程工作、播放核心與系統媒體控制，**沒有新的頁面或設定列**。

## 要做的

1. **schema v12**（`.trellis/spec/app/data/index.md` § 改 schema 全流程）
   - `radio_stations`：欄位依 design §3.1 的表。
     - 唯一鍵是（`plugin_id`、`room_id`）；
     - 不建外鍵到 `installed_plugins`。
   - `network_settings` 加 `radio_status_interval_minutes` int?：
     - 空的時候是預設 5 分；
     - `0` 表示關閉；
     - 其他值限 1、3、5、10。
     - 讀寫都經現有的網路設定 Notifier，比照該組其他欄位。這個 PR 不加設定列。
2. **`lib/radio/`**
   - **`radio_repository`**（`lib/data/repositories/`）：
     - 依 `sort_order` 列出並 `watch`；
     - 新增；刪除；
     - 排序：拖曳後整批重寫 `sort_order`；
     - 更新狀態欄位：`live_status`、`live_title`、`status_checked_at`。
     - **只加有人呼叫的方法。**
   - **`radio_service.dart`**：
     - **以網址新增**（ADR 0031 §決定 2）：
       1. 依序問每個已啟用、宣告 `live` 的插件 `liveRoomFromUrl`，第一個回 `roomId` 的插件勝出。
       2. 對它呼叫 `liveStatus`，取得標題、主播、封面與狀態。
       3. 寫入時用 `liveStatus` 回傳的 `roomId`，它可能和網址裡的不同：B 站短號 `1` 會回長號 `5440`。重複判斷也用這個 id。
       - 結果回傳三種之一，讓 18c 顯示對應的提示：「無法辨識這個網址」「已在電台清單」「已加入」。
     - **加為電台**：直接以 `LiveRoom` 寫入，重複時同樣回「已在電台清單」。
     - **狀態**：每列除了資料庫存的狀態，記憶體還帶「查詢失敗」（D10）。顯示時共有四種狀態：開播中、未開播、查詢失敗、還沒查過。「查詢失敗」不寫進資料庫，也不當成未開播。
3. **狀態工作**（design §9.2）
   - 每個「已啟用、宣告 `live`、清單裡有電台」的插件登記一個 `radio-status:<pluginId>`，間隔取設定（`0`＝關閉）。
   - 工作依序對該插件的每個電台呼叫 `liveStatus`，成功就更新狀態欄位。
     - 單一電台失敗：只把那一列標「查詢失敗」，其他繼續。
     - 全部失敗才丟錯，讓排程器退避。
     - 用 `JobContext.isCurrent` 丟掉過期的結果。
   - 以下變化時重新登記或移除：插件清單（啟用、停用、安裝、移除）、該插件的電台增減、間隔設定。
     - 插件停用與移除時，排程器已經會移除工作（PR 17）；重新啟用時要再登記回來。
   - 提供手動刷新：對每個工作 `runNow`。回傳值讓 18c 分得出「離線」與「完成」。
   - 啟動時先顯示資料庫存的狀態，排程器到期才跑（ADR 0017 §決定 3）。
4. **直播播放**（design §9.4、§4.9）
   - `QueueMode.live`。`PlaybackController.playLive(LiveTarget)`：
     - `LiveTarget` 至少要有 `pluginId`、`roomId`、`title`、`hostName`、`artwork`。
     - 記下佇列快照，與臨時播放相同：佇列目前位置、播放位置、是否在播。
     - 經 `PlaybackSession` 開 `resolveLive` 的流，不排前瞻。
     - 已經在直播時再 `playLive` 換台：快照保留第一次進入時的那份。
   - **停止**（直播的停止，或在佇列點選任一首）：回到快照的佇列，規則照臨時播放回佇列。
   - **暫停就是停止串流**；再按播放時重新 `resolveLive`。
   - **提前結束**（後端 `completed` 或中斷）：
     - 先問 `liveStatus`：
       - 是 `live`：以 1、3、9 秒重連，共 3 次，都失敗就停在「直播已結束」；
       - 不是 `live`：直接停在「直播已結束」；
       - 拋錯：顯示「查詢失敗」並停下（D10）。
     - 這些狀態要能從播放狀態讀出來，給 18c 顯示。
   - **開直播時**：進行中的音樂解析結果以代際丟掉，不播出，也不再因它發解析（ADR 0018 §決定 6 的更正）。
   - **不持久化**：`player_state` 不寫 `live`；直播中關 App，重開時回到快照的佇列，比照臨時播放。
   - **收聽中的 `live-info` 工作**：`playLive` 時登記，固定 1 分鐘，`pluginId` 帶上；停止直播時移除。它呼叫 `liveStatus`，更新目前直播的標題與人數；失敗不中斷播放。
   - **播放狀態**：要能讓 18c 畫出直播版。至少要有：模式、直播的標題、主播、封面、人數、已收聽時間（位置）、「直播已結束」與「查詢失敗」兩種狀態。
5. **系統媒體控制**（`lib/platform/media_controls/`）：
   - `NowPlaying` 帶直播標題與封面，沒有時長、不能 seek；
   - 上一首、下一首停用；
   - Android 與 Windows（SMTC）都要對應。
6. **文件**
   - `app/AGENTS.md`：新增 § 電台；播放核心、資料層、平台層各補一條，只寫查不到的契約與它的閘門。
   - 父 implement.md §18 對應的項目打勾。

## 驗收（測試）

- **控制器**（design §9.4 的閘門）：
  - 進入時記快照，停止後回佇列；
  - 暫停等於停止，再播放時重新取流；
  - 提前結束時先問狀態；`offline` 不重連；`liveStatus` 拋錯時顯示查詢失敗；
  - 重連間隔 1、3、9 秒，共 3 次；
  - 解析中開直播：解析完成後，後端只收到直播流，`resolveStream` 的呼叫次數不變；
  - 換台時快照不變；
  - 直播狀態不寫進 `player_state`。
- **`RecoveryPolicy`**：直播的分支。
- **電台服務**：
  - 以網址新增的三種結果、用長號判斷重複、加為電台；
  - 停用插件的 `liveRoomFromUrl` 不會被問到。
- **狀態工作**：
  - 單一電台失敗只標那一列，全部失敗才丟錯；
  - 過期的結果被丟掉；
  - 插件停用、重新啟用、電台增減、間隔改成 `0` 時，工作都跟著變。
- **`live-info`**：`playLive` 時登記，停止後移除，間隔 1 分鐘。
- **系統媒體控制**：直播時沒有時長，不能 seek，上一首、下一首停用。用現有的媒體控制測試寫法。
- **migration**：空資料升級、資料完整性、不改使用者設定過的值。
- **lint**：`forbiddenLayerImports` 的 `radio/` 規則在 `lib/radio/` 出現後仍然成立，哨兵維持 14 條規則都有報。
- 每個新閘門都做雙向變異驗證並回報。
- 驗證清單：
  - `dart format --output=none --set-exit-if-changed lib test tool integration_test packages`
  - `build_runner` 後沒有實質變動
  - `dart analyze --fatal-infos`、`flutter analyze`
  - `flutter test`
  - `packages/fmp_lints` 的 `dart test`、`dart run tool/lint_sentinel.dart`
  - 改到播放後端時，照 `app/AGENTS.md` § 驗證，在兩平台跑 `integration_test/audio_backend_contract_test.dart`（主對話做）

## 實機

- 沒有新的介面可操作，所以實機留到 18c 一起做：Android 與 Windows、重播加 B 站匿名真實連線，排程器在最小化、背景、飛航模式下的行為也在那時驗。
- 這個 PR 改到 `lib/platform/media_controls/`。如果也改到播放後端，主對話在合併前兩平台各跑一次整合測試。

## 不做

- 導覽、電台頁、搜尋頁的直播間模式、播放頁與播放列的直播版、設定列（18c）。
- 粉絲勳章匯入、首頁的電台區塊（M4，ADR 0031）。
