# 15: B 站分 P

Status: ready-for-agent
Blocked by: 09、14
讀: brief §5.1、§5.3、§6；`GLOSSARY.md`〈分 P〉；ADR 0039；`docs/design/search.html`（B 站多 P 展開）、`docs/design/DESIGN.md` §4.1；事實 F1、F21；spec〈共同規則〉

## What to build

多 P 影片在搜尋結果帶分 P 數的標示，可以展開列出每個分 P。`listParts` 插件能力（bilibili 實作，介面寫回 ADR 0039）列出一支影片的分 P，每個分 P 是一首曲目（id 照 brief §5.3）。點父列時整組當成一首臨時播放，播完整組才回佇列；點單一分 P 只臨時播放那一個。選單可以把單一分 P 或整組加入佇列；整組進佇列時是一首還是拆成每個分 P，由這張票定，記成一條決定。

M1 主要流程的 integration_test 寫在這張：搜尋、加入佇列、臨時播放一組分 P、整組播完回到佇列原本那首，四平台都跑（串流指向假 CDN）。

## 驗收

- [ ] `listParts`：契約測試有 fixture，`live` 冒煙測試加一條，ADR 0039 補了介面。
- [ ] 整組臨時播放有單元測試：播完整組才回佇列；組內上一首、下一首在組內移動；回佇列時照常倒退。
- [ ] 展開分 P 的截圖和 `search.html` 對得上。
- [ ] M1 主要流程的 integration_test 四平台通過。
- [ ] 四平台實跑：展開一支多 P 影片、臨時播放整組，讀回畫面。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
