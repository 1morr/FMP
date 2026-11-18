# 17: 曲目資訊

Status: ready-for-agent
Blocked by: 16
讀: ADR 0039；`docs/design/DESIGN.md` §5.2（詳情面板）；`docs/design/shell.html`（`.detail`）；`GLOSSARY.md`〈曲目資訊〉；`docs/design/player.html`（曲目資訊）；事實 F1、F21；spec〈共同規則〉

## What to build

播放頁可以看曲目資訊：專輯、發佈日期、播放數、點讚數、評論數、簡介，插件給不了的欄位不顯示（ADR 0039）。`trackInfo` 插件能力由 bilibili 實作，介面寫回 ADR 0039；結果只放記憶體（ARCHITECTURE〈快取〉）。

桌面右側的實心詳情面板（票 05 做了面板框與收起）照 `DESIGN.md` §5.2 填內容：標頭「正在播放」與收起，封面、曲名、音源 chip、下一首、簡介（簡介取自 `trackInfo`）。存取等級徽章（M2）、加入歌單（M3）、資訊／歌詞分段（M4）不出現（spec〈共同規則〉）。2026-11-15 擁有者定併進這張（票 05 發現沒有票負責）。

## 驗收

- [ ] `trackInfo`：契約測試有 fixture，`live` 冒煙測試加一條，ADR 0039 補了介面。
- [ ] 缺欄位不顯示，有 widget 測試。
- [ ] 曲目資訊的截圖和 `player.html` 對得上。
- [ ] 桌面詳情面板的截圖和 `shell.html` 對得上（深淺色、有曲目與沒有曲目、收起）。
- [ ] 四平台實跑：打開一首的曲目資訊，讀回畫面；macOS、Windows 讀回詳情面板。
- [ ] 桌面 ⌘I（Windows 用 Ctrl+I）打開曲目資訊（`DESIGN.md` §10）；有 widget 測試（2026-11-19 擁有者同意，文件審查發現）。
- [ ] 無障礙照 `DESIGN.md` §10：這張新增的可聚焦元件有 2px 強調色焦點外框（offset 2）、手機點擊區補到 44（〈稿內不一致與實作注意〉第 2 點）、系統開「減少動態效果」時照 §3.4 改淡入淡出、不彈跳；各一條 widget 測試（2026-11-19 擁有者同意，文件審查發現）。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
決定：⌘I 與這張頁面的無障礙加進這張票（使用者同意）
