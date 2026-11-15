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
Session 紀錄：2026-11-15 讀完稿與規格、問完兩題、加 go_router 18.1.4（pubspec），還沒寫外殼；額度用完中斷，下一個 session 照下面的計畫接著做
決定：Windows 先用原生標題列，自繪另開 M1 票 05b；截圖比對時記為 05b 會補的已知差異（使用者定）
決定：圖示照稿，把 kit.js 的路徑搬進 `app/` 的 FmpIcons，用 path_parsing 1.1.0 畫，用到哪個搬哪個（Agent 定）
決定：桌面詳情面板只做框、標頭「正在播放」與收起，內容歸票 17；截圖比對時記為票 17 會補的已知差異（使用者定）
決定：音樂庫空狀態只留圖示與「還沒有歌單」，不放新建、匯入的說明與按鈕（M3 才有）（Agent 定）
接手計畫（還沒做）：
- go_router `ShellRoute`：/home /library /queue /settings /search，NoTransitionPage，initialLocation /home；分頁用 go，進搜尋用 push（返回＝pop 回原分頁）；外殼的 PopScope 讓非首頁分頁按返回回首頁，首頁才離開。
- 搜尋框共用 Riverpod 持有的 TextEditingController：手機在 dock（搜尋圓鈕展開成欄位，導覽收成左邊圓鈕、顯示進搜尋前的分頁；聚焦時欄位撐滿、圓鈕藏起），中寬度在搜尋頁頂端，寬級在側欄搜尋欄（聚焦即進 /search）。佔位搜尋與播放面板搬進 `ui/search/`，integration_test 改成先點「搜尋」再輸入。
- 尺寸照 fmp.css：dock 高 160、導覽膠囊 W-100×62、圓鈕 62；細欄外框 72（平板 80）、項目高 50（58）；側欄外框 248、項目高 32、搜尋欄 30；詳情面板 320、標頭 52，中寬度由頂列 sidebarR 鈕叫出浮動面板（平板 360），寬級收起後同一顆鈕叫回；設定頁預設收起。
- macOS：MainFlutterWindow 透明標題列＋fullSizeContentView、minSize 720×560，側欄／細欄頂端讓出紅綠燈的高度（由 `platform/` 提供是否要讓）；Windows：win32_window.cpp 處理 WM_GETMINMAXINFO（依 DPI 換算，含邊框）。
- ARCHITECTURE〈主要依賴〉要補 go_router 18.1.4 與 path_parsing 1.1.0 兩列（寫入前照協調者指示先問）。
