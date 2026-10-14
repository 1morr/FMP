# 背景排程器（M3b PR 17）

父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`（implement.md §17、design §8、§2.2、§3.1、§7.3、§7.4）。依據 ADR 0017。

這個 PR 沒有使用者看得到的改動：第一個工作（電台狀態）在 PR 18 登記。

## 要做的

1. **schema v11：`scheduler_runs`**（`job_id` text 主鍵、`last_success_at` int，UTC epoch 毫秒）
   - 照 `.trellis/spec/app/data/index.md` § 改 schema 走完：快照、`stepByStep`、三種 migration 測試。
   - 在 `lib/data/repositories/` 加 repository：讀全部或單一 job 的上次成功時間、寫入（upsert）、刪除。
2. **`lib/scheduler/background_scheduler.dart`**（design §8.1 的全部規則）
   - 以 Riverpod Notifier 建立，由 `appLifecycleProvider`（`lib/app/app_lifecycle.dart`）與 `networkStatusProvider`（`lib/core/network/network_status.dart`）驅動。
   - 工作：`SchedulerJob {String id; String? pluginId; Duration? interval; Future<void> Function(JobContext) run;}`，提供 `register`／`unregister`／`unregisterPlugin(pluginId)`。
     - `interval` 為空表示關閉：不會自動跑，只能 `runNow`。
     - 以已存在的 id 再 `register` 會取代舊的，代際加一，進行中那次的結果視為過期。
   - **只用一個計時器**：一次性 `Timer` 指向最早到期的工作（包含退避中的工作）。到期、狀態改變、登記變動時都重算。排程器本身不用 `Timer.periodic`。
   - **何時跑**：生命週期是 `resumed` 或 `inactive`，而且網路狀態是 `online`。
     - 其他狀態（`hidden`、`paused`、`detached`、`noInterface`、`unreachable`）：取消計時器；進行中的工作跑完，結果照常記錄；不開新的。
     - 變可見或回到 `online` 時，已到期的工作各跑一次。
     - App 啟動視同變可見。沒有上次成功時間的工作視為已到期。
   - **並行**：全域同時最多 2 個，同一 `pluginId` 依序。超出的排隊，等有空位再跑。
   - **失敗與退避**：工作丟錯時，依 1、2、4… 分鐘退避，上限為該工作的間隔。
     - 錯誤是 `AppError` 且帶 `retryAfter` 時，以 `retryAfter` 為準。
     - 成功後退避歸零，下次到期是成功時間加間隔。
     - 錯誤經 `log.report`（tag `scheduler`，`AppError.wrap` 帶 plugin id）進錯誤歷史，另記一行 info（審查時由 warning 改正，照 `app/AGENTS.md` § Log）。不跳提示（ADR 0013 §決定 5）。
   - **上次成功時間**：成功時寫進 `scheduler_runs`；登記時讀出來算下一次到期，所以重啟後照算。過期的那次成功不寫。
   - **手動刷新** `runNow(id)`：
     - 不看間隔。回傳值讓呼叫端分得出四種情況：「跑完」「離線（沒有發）」「沒有這個工作」「已經在跑（不開第二個）」。
     - 一樣受「全域 2 個、同插件依序」的限制。
     - 成功後同樣寫上次成功時間、退避歸零。
     - 看不見但在線時也可以手動跑。
   - **取消**：`unregister`、`unregisterPlugin` 或取代時立即移除，代際加一。進行中那次的結果，由工作自己以 `JobContext.isCurrent` 判斷後丟掉，排程器也不替它寫上次成功時間。
   - 時間一律以 `clock` 讀；測試用 `fakeAsync`。
   - 在 `lib/app/fmp_app.dart` 讓 provider 常駐，比照 `pluginDevelopmentProvider` 的做法。原因是 Riverpod 3 沒人聽的 provider 會被暫停。
3. **插件停用與移除時移除它的工作**
   - `PluginRegistry.setEnabled(…, enabled: false)` 呼叫 `unregisterPlugin`。
   - `PluginInstaller.remove` 在刪 `installed_plugins` 列之前加一步 `unregisterPlugin`（design §7.4 的順序）。這一步也要可重複，並更新那段 doc 註解。
   - 開發資料夾的載入與卸載不處理：它換的是同 id 的插件，工作由登記者自己決定。
4. **lint**
   - 新規則 `fmp_periodic_timer_owner`：`Timer.periodic`、`Stream.periodic` 只准出現在 `lib/scheduler/`、`lib/playback/`。
     - 雙向變異：
       - `lib/radio/` 的 `Timer.periodic` 會報，`lib/scheduler/` 的不報；
       - 自訂的 `Timer.periodicLike` 與 `Timer.run` 都不報；
       - `Stream.periodic` 一樣兩向都要測。
     - 在 `tool/lint_sentinel.dart` 加違規行。
   - `forbiddenLayerImports`：
     - `core/`、`domain/`、`data/` 不 import `scheduler/`、`radio/`；
     - `scheduler/` 不 import `ui/`、`radio/`、`plugins/`；
     - `radio/` 不 import `ui/`（PR 18 才有 `radio/`，規則先加，變異案例照寫）。
   - 照 `.trellis/spec/app/lints/index.md` 寫案例，同步 `app/AGENTS.md` § Lint 的表。
5. **文件**
   - `app/AGENTS.md` 新增 § 排程器：寫規則與閘門，以及怎麼登記工作。只寫從程式碼查不到的東西。
   - 父 implement.md §17 打勾；design §7.3 的閘門補上「排程器的工作被移除」。

## 驗收（測試）

- design §8.2 的七項，各一組單元測試（假時鐘、假生命週期、假網路狀態）：
  1. 看不見與離線時不跑；
  2. 恢復後已到期的工作各跑一次，沒到期的不跑；
  3. 任何時刻待執行的計時器最多一個（`fakeAsync` 的 `pendingTimers`）；
  4. 手動刷新不看間隔，離線時回傳「離線」且沒有呼叫工作；
  5. 移除或停用後不再跑，進行中那次的 `isCurrent` 變成假，也不寫上次成功時間；
  6. 退避序列 1、2、4… 與上限、`retryAfter` 優先、成功後歸零；
  7. 上次成功時間重啟後生效：新的 Notifier 讀同一個資料庫。
- 另加兩項：同一插件依序；全域最多 2 個。
- `plugin_registry_test`：停用後該插件的工作被移除。`plugin_installer_test`：移除後工作不在，中途失敗重跑可完成。
- migration：空資料升級、資料完整性、不改使用者設定過的值。
- lint：上面列的雙向變異；哨兵 13 條變成 14 條都要有報。
- 每個新閘門都做雙向變異驗證並回報。
- 驗證清單：
  - `dart format --output=none --set-exit-if-changed lib test tool integration_test packages`
  - `build_runner` 後沒有實質變動
  - `dart analyze --fatal-infos`、`flutter analyze`
  - `flutter test`
  - `packages/fmp_lints` 的 `dart test`
  - `dart run tool/lint_sentinel.dart`

## 實機

- 沒有使用者看得到的改動，也沒動平台層與播放後端：不做實機。PR 18 的實測涵蓋（父 implement §17）。

## 不做

- 電台狀態工作、電台間隔設定（PR 18）；排行與匯入歌單的工作與間隔（M4，design §8.4）。
- 把 `queue_store.dart` 的 `Timer.periodic` 搬進排程器（播放核心允許，ADR 0018 §決定 11）。
