# 14: 搜尋頁照稿與搜尋排序

Status: ready-for-agent
Blocked by: 05、07、09
讀: brief §5.1、§6；ADR 0039；`docs/design/DESIGN.md` §6.1、§6.3、§9；`docs/design/search.html`；architecture〈測試策略〉；spec〈共同規則〉

## What to build

搜尋頁照稿：搜尋紀錄、輸入中、全部音源的結果（現在只有 B 站）、載入骨架、單一音源出錯（只重試該音源）、找不到、曲目的 ⋮ 選單（下一首播放、加入佇列；有曲目網址才有複製連結、在瀏覽器開啟）、多選、桌面表格與右鍵。點一首臨時播放（09），選單與多選加入佇列（07）。沒有網路時顯示網路錯誤。

`search` 插件能力加排序（ADR 0039：排序鍵由宿主定，綜合、最多播放、最新發布，manifest 宣告支援哪幾種），bilibili 實作；介面寫回 ADR 0039。B 站多 P 的展開在 15。佔位搜尋刪掉，M0 的 integration_test 跟著改。

## 驗收

- [ ] 搜尋頁各狀態在三種寬度、深淺色的截圖和 `search.html` 對得上（多 P 展開除外）。
- [ ] 排序：契約測試有每種排序的 fixture，`live` 冒煙測試加一條；manifest 宣告支援的排序，畫面只列宣告的。
- [ ] 搜尋紀錄保存與清除有測試。
- [ ] 依賴規則照過；佔位搜尋已刪除，M0 的 integration_test 改到新搜尋頁、四平台通過。
- [ ] 四平台實跑：搜尋、換排序、點一首臨時播放、選單加入佇列，讀回畫面。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
