# 0027 — 實機驗證：預設重播、只在改到音源互動時打真實 API、Android 與 Windows 每個 PR 都驗

- 狀態：已採納
- 日期：2026-09-28
- 影響範圍：`app/` 的 verify-on-device skill 與 `app/AGENTS.md` 的驗證段、各平台任務的操作說明、里程碑驗收

## 背景

舊專案（`.trellis/tasks/archive/2026-09/09-28-phase3-docs-cleanup/research/current-state.md` §g）：

- verify-on-device skill 只涵蓋 Android 模擬器（必要）與 Windows（只在 Windows 專屬改動時）。
- 它跑的是真實 App 對真實音源。筆記裡記過三個音源同時用不了（B 站 `playurl` 回 412、YouTube 要求登入）（`references/runtime-state.md:35-36`）。
- ADR 0015 的零聯網只管 `flutter test`（`dart_test.yaml` 的 `live` 跳過、`HttpOverrides`），不管實機驗證。

新架構已經有可以用的工具：
- 每插件可切換真實、錄製、重播（ADR 0015 §5、§7）；
- `app/` 有合成資料、播放本機音檔的測試插件（ADR 0015 §6）；
- Debug 頁的音源健康檢查以真實連線手動執行（ADR 0025）。

平台的排程已由 ADR 0026 定下：Android、Windows 全面驗證；Linux 在 M1 之後開平台任務；macOS、iOS 等 Mac 到貨。

parent prd 階段三要求：規劃新平台加入時實機驗證如何擴充，以及如何減少打真實 API。擁有者 2026-09-28 照建議選定。

## 考慮過的選項

- **預設打真實 API（舊版）**：否決。
  - 常被限流擋住，驗證結果時好時壞；
  - 頻繁操作可能讓擁有者的帳號被風控；
  - 上游一改版，無關的 UI PR 也跟著驗不過。
- **Windows 只在 Windows 專屬改動時驗（舊規則）**：否決。Windows 在新架構是兩個主力平台之一；舊版的 Windows 無障礙樹凍結就是這樣漏掉的。
- **Linux 每個 PR 都驗**：否決，每個 PR 都要開虛擬機，時間成本高。
- **現在就改寫 skill**：否決。`app/` 還不存在；舊專案的緊急修正仍要用現在的 skill。

## 決定

1. **預設模式是重播**：實機驗證一律跑 dev flavor，每個插件切成「重播」，或使用 `app/` 的測試插件。UI、播放、下載、歌詞、設定的改動都在這個模式下驗。
2. **改用真實連線的條件**：
   - 只在改動本身是插件、網路層、登入，或正在錄製 fixture 時；
   - 只做最少的操作（例如搜尋一次、播放一首），不做批次或迴圈；
   - 回報寫明「模式：真實」與做了哪些請求。
   - 上游改版由 Debug 頁的健康檢查與手動冒煙測試發現（ADR 0015 §4），不靠每個 PR 的實機驗證。
3. **平台分工**：

   | 平台 | 時機 | 何時加入 skill |
   |---|---|---|
   | Android 模擬器 | 每個改到使用者看得到的 PR | M1 |
   | Windows | 每個改到使用者看得到的 PR | M1 |
   | Linux 虛擬機（VMware，Ubuntu 桌面，X11 與 Wayland） | 每個里程碑一次冒煙測試 | Linux 平台任務 |
   | macOS | 每個里程碑一次冒煙測試 | macOS 平台任務（Mac 到貨後） |
   | iOS 模擬器 | 每個里程碑一次冒煙測試 | iOS 平台任務（Mac 到貨後） |

   - 每個平台的操作說明沿用現在 skill 的閉環：啟動 → 執行 → 觀察 → 操作 → 收尾。放在 skill 的 `references/<平台>.md`。
4. **時程**：
   - M1 時為 `app/` 改寫 skill；
   - 根目錄舊專案的 skill 維持原樣，給緊急修正用，切換 PR 時移除。

採用的慣例：
- 契約測試與實機驗證共用錄製的 fixture（ADR 0015 §4 的「檢查案例一份四用」）；
- 現在這份 skill 的閉環與「做不到就具名回報 blocker」。

## 後果

- 好的：
  - 實機驗證的結果可以重現，不受上游和限流影響；
  - 擁有者的帳號很少被打到；
  - Windows 的問題在 PR 階段就會被發現。
- 壞的：
  - 重播看不到上游的最新行為，要靠健康檢查與冒煙測試；
  - 每個 PR 要驗兩個平台，時間比舊規則長；
  - fixture 要定期重錄。
- 之後要注意：
  - 若測試插件的合成資料不足以涵蓋某類 UI，先補測試插件，不要改成打真實 API；
  - Linux、macOS、iOS 的操作說明由各自的平台任務負責；
  - 更正（2026-09-29）：根目錄舊專案的 verify-on-device skill 已改名 `verify-legacy-on-device`（M1 PR 1），只更新 skill 內指向自身的路徑；`verify-on-device` 這個名字留給本 ADR 決定 4 要建立的 `app/` 版 skill。

## 如何確認

- `app/AGENTS.md` 的驗證段寫明「預設重播、真實連線的條件、Android 與 Windows 每個 PR」。這是 review 點：實機驗證無法寫成測試。
- 實機驗證的回報格式包含「平台」與「模式：重播／真實」。PR review 指南缺這兩項就退回。
- 里程碑驗收表（`milestones.md`）的每個里程碑，在 Linux 平台任務完成後都含「Linux 冒煙測試」一格。
