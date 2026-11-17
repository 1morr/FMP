# 10: 佇列與進度跨重啟保存

Status: ready-for-agent
Blocked by: 08、09
讀: brief §6、§9；architecture〈測試策略〉；`app/test/drift/app_database/`；M0 票 07、12 的 Comments；spec〈共同規則〉

## What to build

佇列（含原順序、播放順序、隨機與循環）與正在播的那首和進度跨重啟保存；重啟後停在原本那首、不自動播放；臨時播放不保留，回到佇列原本那首。設定不提供開關。

- 這是第一次建表：照 ARCHITECTURE〈測試策略〉升 schema，同時建資料完整性測試的骨架（M0 票 12 原判不做，回顧改成第一次建表時建）。曲目 id 存進資料庫後，改插件的 id 格式要做資料 migration（brief §5.3）。
- 開資料庫失敗時怎麼呈現（M0 票 07 留下的）：照錯誤分類與 Toast，App 照常能搜尋播放，只是不保存；做法記成一條決定。

## 驗收

- [ ] schema 升級照流程（快照、`generated/`、`stepByStep`），閘門的 schema 檢查與升級測試通過；資料完整性測試的骨架就位，至少有一條。
- [ ] 保存與還原有測試：佇列、兩種順序、播放模式、正在播的那首與進度；臨時播放不保留；還原後不自動播放。
- [ ] 開資料庫失敗有測試，畫面有提示、App 照常能播放。
- [ ] 四平台實跑：排佇列、播到一半、關掉重開，讀回停在原本那首與位置。
- [ ] 完整閘門的 integration_test（例如 `app_test.dart` 跑 `app.main()`）不寫到擁有者 dev 版的資料庫與 log，照票 08b 實跑驅動的資料隔離做法（`FMP_SCRATCH_DATA`）；有測試守著（2026-11-18 協調者加，票 08b 的發現）。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
