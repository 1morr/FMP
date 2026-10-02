# 啟動維護清單與 log 保留 7 天（M2 PR 6）

> 父任務：`.trellis/tasks/10-01-m2-full-playback`。技術設計在父任務 `design.md` §6（擁有者決定 2：背景排程器延到 M3，M2 只做啟動維護清單）；本檔只列做什麼與驗收。

## 目標

App 每次啟動、第一個畫面畫完之後，依序跑一次維護工作；第一項是刪掉超過 7 天的 log 檔（ADR 0025 §決定 3、ADR 0017 §決定 1）。

## 做什麼

1. `lib/app/startup_maintenance.dart`：
   - `StartupMaintenanceTask { String id; Future<void> Function() run; }` 的有序清單，由 App 的組裝層收集；
   - 第一幀畫完之後跑一次（`FmpApp` 的 `initState` 以 `SchedulerBinding.addPostFrameCallback` 排），每個行程只跑一次；
   - 每項各自 try：失敗以 `log.report` 寫進錯誤歷史，接著跑下一項；不重試、不跳提示（ADR 0013 §決定 5）；
   - 每項跑完寫一筆 log（tag 自訂，例如 `maintenance`），帶項目 id 與結果；方便實機驗證。
2. 第一項 log 保留（`lib/core/logging/` 提供函式）：
   - `logs/` 底下最後修改超過 7 天的 `fmp*.jsonl` 刪掉；
   - 目前在寫的 `fmp.jsonl` 不刪；
   - 與既有的大小輪替並存，兩個限制先到先刪；
   - 不做設定項；時間經 `clock` 取（可測）。
3. 孤兒曲目那一項在 PR 14 登記；M2 不放空的登記點，診斷包（M3）、更新檔（M9）也不放。
4. 文件：`app/AGENTS.md` 加啟動維護清單的契約（何時跑、失敗處理、新項目怎麼登記），每條寫閘門；需要時更新 `.trellis/spec/app/logging/`。

## 不做

- 背景排程器、週期性工作（M3）。
- log 保留天數的設定項。

## 驗收

- [ ] 測試：
  - 依序、只跑一次、在第一幀之後（widget 測試以 `pump` 確認 `runApp` 當下還沒跑）；
  - 一項丟錯時下一項照跑，錯誤進錯誤歷史，沒有 toast；
  - log 保留：超過 7 天的檔被刪、未滿 7 天的保留、目前的 `fmp.jsonl` 不刪；大小輪替與天數同時作用（ADR 0025 §如何確認；以 `File.setLastModified` 造時間）；非 `fmp*.jsonl` 的檔不動。
- [ ] 驗證清單全綠（父任務 implement.md「每個 PR 的固定流程」第 5 步）。
- [ ] 實機（主對話做；重播即可）：Windows 在 dev 資料目錄放一個修改時間改到 8 天前的舊 log 檔，啟動後被刪、log 有維護紀錄；Android 以 `run-as` 做同樣的事。
