# 05: App 外殼與導覽

Status: ready-for-agent
Blocked by: 03、04
讀: brief §11；`docs/design/DESIGN.md` §5、§9、§10；`docs/design/shell.html`；architecture〈目錄結構〉〈主要依賴〉；spec〈共同規則〉

## What to build

App 有照稿的外殼與路由：手機是導覽膠囊（首頁、音樂庫、佇列、設定）加獨立的搜尋圓鈕，捲動時不收合，進搜尋時導覽收成左邊圓鈕、搜尋圓鈕展開成欄位；中寬度是左側玻璃細欄；桌面是左側浮動玻璃側欄（搜尋欄、導覽、設定）、右側實心詳情面板（可收起）、底部播放膠囊的位置。路由用 go_router 的 `ShellRoute`，App 打開在首頁。

- 各頁先是空頁；佔位搜尋搬進搜尋路由，照常能搜尋播放，M0 的 integration_test 跟著改。
- 音樂庫在 M3 才有：導覽照稿保留四項，音樂庫先顯示空狀態（擁有者 2026-11-11 定的四項導覽），不畫「之後提供」。歌單清單、帳號這類 M1 沒有的入口不出現（spec〈共同規則〉）。
- 桌面視窗最小 720×560。

## 驗收

- [ ] 三種寬度、深淺色的外殼截圖和 `shell.html` 對得上（手機、中寬度直向與橫向、窄視窗、桌面完整與收起詳情面板）。
- [ ] 路由與導覽有 widget 測試：四項導覽與搜尋都到得了，返回行為正確。
- [ ] go_router 的版本寫進 ARCHITECTURE〈主要依賴〉。
- [ ] M0 的 integration_test 在新外殼下四平台通過。
- [ ] 四平台實跑讀回畫面。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
