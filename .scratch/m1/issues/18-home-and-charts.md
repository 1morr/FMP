# 18: 首頁與 B 站排行榜

Status: ready-for-agent
Blocked by: 05、07、09
讀: brief §5.1；ADR 0039；architecture〈快取〉；`docs/design/DESIGN.md` §6.7；`docs/design/home.html`；spec〈共同規則〉

## What to build

首頁照稿：繼續聽（正在播放與接下來）、近期熱門（手機 chip 切換音源、展開到 10 名；桌面每個音源一欄，現在只有 B 站），含第一次打開、載入骨架、單一音源失敗（只重試該音源）、沒有網路時顯示快取的榜並寫「這是 n 小時前的榜」、桌面 hover。「最近更新的匯入歌單」在 M3，不出現。點榜上的曲目臨時播放（brief §6）。

`charts` 插件能力（一張榜、前 N 名、不需登入）由 bilibili 實作，介面寫回 ADR 0039。榜照 ARCHITECTURE〈快取〉存 drift：首頁先顯示快取，超過 1 小時在背景重抓，下拉刷新強制重抓。

## 驗收

- [ ] `charts`：契約測試有 fixture，`live` 冒煙測試加一條，ADR 0039 補了介面。
- [ ] 榜的快取有測試（假的時鐘）：先顯示快取、超過 1 小時重抓、強制重抓、離線時顯示抓取多久了；schema 升級照流程。
- [ ] 首頁各狀態在三種寬度、深淺色的截圖和 `home.html` 對得上。
- [ ] 四平台實跑：打開首頁看到 B 站近期熱門、點一首播放，讀回畫面。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
