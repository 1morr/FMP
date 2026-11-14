# 17: 曲目資訊

Status: ready-for-agent
Blocked by: 16
讀: ADR 0039；`GLOSSARY.md`〈曲目資訊〉；`docs/design/player.html`（曲目資訊）；事實 F1、F21；spec〈共同規則〉

## What to build

播放頁可以看曲目資訊：專輯、發佈日期、播放數、點讚數、評論數、簡介，插件給不了的欄位不顯示（ADR 0039）。`trackInfo` 插件能力由 bilibili 實作，介面寫回 ADR 0039；結果只放記憶體（ARCHITECTURE〈快取〉）。

## 驗收

- [ ] `trackInfo`：契約測試有 fixture，`live` 冒煙測試加一條，ADR 0039 補了介面。
- [ ] 缺欄位不顯示，有 widget 測試。
- [ ] 曲目資訊的截圖和 `player.html` 對得上。
- [ ] 四平台實跑：打開一首的曲目資訊，讀回畫面。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
