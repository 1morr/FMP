# M4 PR 4 首頁的我的歌單與電台區塊

> M4 的 PR 4（`../10-15-m4-library-sync/implement.md` § 4）。設計在 `../10-15-m4-library-sync/design.md` §10.2；決定在 ADR 0033 §決定 6。照 PR 2 定下的首頁區塊樣式（`home_page.dart` 的「最近播放」區塊）。

## 做什麼

- 首頁區塊依序：（排行在 PR 21）我的歌單、電台、最近播放。
- **我的歌單**：依 `sort_order` 前 20 張歌單卡（同音樂庫的卡片：封面、名稱、首數與標記），點一下開歌單詳情（在首頁的巢狀導覽裡，`openPlaylist`）；「查看全部」切到音樂庫目的地。
- **電台**：依 `sort_order` 前 20 個電台（封面、標題、狀態標記：`RadioEntry` 的四種狀態——開播中／未開播／查詢失敗／還沒查過），點一下 `playLive`；「查看全部」切到電台目的地。
- 沒有內容的區塊不顯示；全部都沒有時顯示既有的說明。
- 字串三語言；guideline。
- 文件：`app/AGENTS.md` § 介面（首頁）。

## 驗收

- 測試：區塊的有無（沒有內容不顯示）、20 個上限、依 `sort_order`、點歌單開詳情、點電台 `playLive`、「查看全部」切到對的目的地、電台四種狀態標記；guideline（淺色、深色，400／1000 寬）。
- `dart format`、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過。
- 實機（主對話做）：重播（Android）：`fmp-test` 的直播間加兩個電台 → 首頁電台區塊點一個播放 → 查看全部。
