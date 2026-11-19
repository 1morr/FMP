# 17: 曲目資訊

Status: done
Blocked by: 16
讀: ADR 0039；`docs/design/DESIGN.md` §5.2（詳情面板）；`docs/design/shell.html`（`.detail`）；`GLOSSARY.md`〈曲目資訊〉；`docs/design/player.html`（曲目資訊）；事實 F1、F21；spec〈共同規則〉

## What to build

播放頁可以看曲目資訊：專輯、發佈日期、播放數、點讚數、評論數、簡介，插件給不了的欄位不顯示（ADR 0039）。`trackInfo` 插件能力由 bilibili 實作，介面寫回 ADR 0039；結果只放記憶體（ARCHITECTURE〈快取〉）。

桌面右側的實心詳情面板（票 05 做了面板框與收起）照 `DESIGN.md` §5.2 填內容：標頭「正在播放」與收起，封面、曲名、音源 chip、下一首、簡介（簡介取自 `trackInfo`）。存取等級徽章（M2）、加入歌單（M3）、資訊／歌詞分段（M4）不出現（spec〈共同規則〉）。2026-11-15 擁有者定併進這張（票 05 發現沒有票負責）。

## 驗收

- [x] `trackInfo`：契約測試有 fixture，`live` 冒煙測試加一條，ADR 0039 補了介面。
- [x] 缺欄位不顯示，有 widget 測試。
- [x] 曲目資訊的截圖和 `player.html` 對得上。（手機 sheet、窄視窗與桌面的對話框，深淺色）
- [x] 桌面詳情面板的截圖和 `shell.html` 對得上（深淺色、有曲目與沒有曲目、收起）。（加中寬度浮出的面板）
- [x] 四平台實跑：打開一首的曲目資訊，讀回畫面；macOS、Windows 讀回詳情面板。（照 spec〈共同規則〉縮成 macOS＋iOS；Windows 跳過）
- [x] 桌面 ⌘I（Windows 用 Ctrl+I）打開曲目資訊（`DESIGN.md` §10）；有 widget 測試（2026-11-19 擁有者同意，文件審查發現）。
- [x] 無障礙照 `DESIGN.md` §10：這張新增的可聚焦元件有 2px 強調色焦點外框（offset 2）、手機點擊區補到 44（〈稿內不一致與實作注意〉第 2 點）、系統開「減少動態效果」時照 §3.4 改淡入淡出、不彈跳；各一條 widget 測試（2026-11-19 擁有者同意，文件審查發現）。
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。（`--skip-windows`，其餘全綠）

## Comments
決定：⌘I 與這張頁面的無障礙加進這張票（使用者同意）
Session 紀錄：2026-11-20 曲目資訊：`trackInfo` 插件能力（bilibili 打 wbi/view）、曲目資訊 sheet 與對話框（音源膠囊、⋮、兩欄頂列的資訊鈕、⌘I／Ctrl+I）、桌面詳情面板的內容、共用按鈕可聚焦；macOS＋iOS 實跑與三種寬度深淺色比對 player.html、shell.html；完整閘門 --skip-windows 綠
決定：ADR 0039 的 `trackInfo` 照草稿寫入：欄位全選填、名字照 YouTube Data API、bilibili 打 wbi/view 不簽 WBI、B 站沒有專輯（使用者同意）
決定：詳情面板沒有目前曲目時只有標頭與一句「目前沒有播放的曲目」（使用者同意）
決定：測試接縫四層：插件契約與 fixture、宿主 `Plugin.trackInfo`、曲目資訊 widget、詳情面板 widget（協調者代答）（Agent 定）
詳情面板查曲目資訊的取捨：查過的每首留在記憶體（`trackInfoProvider` 不 autoDispose、以 TrackRef 為鍵）到 App 關掉，換來同一首不重查；被播放頁或對話框蓋住也算看不到
決定：詳情面板只在看得到時查曲目資訊，換歌停 1 秒還是同一首才查，同一首這次開 App 期間只查一次（協調者要求）（Agent 定）
決定：共用按鈕 `FmpButton` 可聚焦（強調色外框、Enter 按）留在這張（協調者代答）（Agent 定）
決定：按鈕有焦點時 Space 只播放／暫停、不按下按鈕（`ShellButton` 與 `FmpButton`；對話框與選單裡照框架預設）：查到票 16 起 Space 會同時按下有焦點的按鈕（Agent 定）
決定：手機是底部 sheet，平板與桌面是置中對話框（平板 540、桌面 480），內容照稿的 `plInfoSheet`；存取等級、音質兩列 M2 才有（Agent 定）
決定：欄位順序是音源、專輯、發佈日期、時長、分 P、播放數、點讚、評論、簡介（稿的順序，B 站多的三項插在評論前）；時長、分 P 數、網址取自曲目，不另查（Agent 定）
決定：載入中與失敗（稿沒畫）在欄位下面寫一句灰字，失敗帶「重試」（重新查一次）；手機的重試點擊區補到 44（`FmpButton.touchTarget`）（Agent 定）
決定：「在<音源>打開」「複製連結」照稿放在底部，曲目沒網址時不出現，動作沿用 `trackActionRunner`（Agent 定）
決定：播放頁的 ⋮ 一直在：曲目資訊在上，連結兩項隔一條線在下（Agent 定）
決定：音源膠囊可點、加上稿的 ›；手機的點擊區往膠囊上方補到 44，兩欄的觸控版從上面的間距扣掉，左右滑版由上面的畫面吸收（390 寬的手機封面受寬度限制，位置不變）（Agent 定）
決定：⌘I 掛在 `PlaybackShortcuts`（App 任何頁面），經路由的 navigator 打開；沒有目前曲目、或對話框與選單開著時不攔（Agent 定）
決定：詳情面板封面下一行是播放數、評論數、專輯（有才有）；下一首是佇列接下來 3 首（同播放頁的佇列），點了從那首播；簡介沒給時寫稿的「這個音源沒有提供簡介。」（Agent 定）
決定：中寬度浮出的詳情面板打開時拿焦點，Esc 才關得掉（原本靠 autofocus，焦點已在別處時不生效）（Agent 定）
決定：數字寫完整的千分位（3,120，照稿），日期是當地時間的 yyyy-MM-dd（Agent 定）
決定：實跑情境兩支：`track_info_states_run`（不聯網，照稿截圖）、`track_info_run`（聯網，搜一次、播一首、詳情面板、⌘I、音源膠囊，這首只查一次曲目資訊）（Agent 定）
共用按鈕已可聚焦，19b 只需補其餘元件與已做完頁面的檢查
Windows 跳過：沒有建置、integration_test 與實跑。補驗看：(1) 完整閘門 Windows 步驟；(2) Ctrl+I 從首頁與播放頁打開曲目資訊、Esc 關掉；(3) 詳情面板讓出視窗鈕那一列後的內容排版，窄視窗浮出的面板從視窗鈕下方開始、Esc 關掉；(4) 播放頁兩欄頂列的資訊鈕與 ⋮ 在視窗鈕左邊；(5) `track_info_states_run.dart` 與 `track_info_run.dart` 實跑（`resize` 只有 macOS，Windows 用 `shot.ps1 -Size`）
code-review 未處理（都是判斷題）：`ShellButton` 與 `FmpButton` 的焦點包裝幾乎相同，可抽共用元件（19b 補其餘元件時一起看）；`plugin_host.dart` 的「曲目屬於別的插件」檢查有三份；`manifest?.name ?? pluginId` 有三處；`touch` 布林一路往下傳；`PlaybackShortcuts` 多收 navigator key 只為 ⌘I
變更：Added｜曲目資訊｜播放頁點音源膠囊、⋮ 的「曲目資訊」或桌面頂列的資訊鈕，看這首的音源、時長、發佈日期、播放數、點讚數、評論數與簡介（音源給不了的不顯示），可以到音源網站打開或複製連結
變更：Added｜曲目資訊｜桌面在任何頁面按 ⌘I（Windows 用 Ctrl+I）打開正在播放那首的曲目資訊
變更：Added｜外殼｜桌面右側的詳情面板顯示正在播放的封面、曲名、音源、播放數與評論數、接下來 3 首與簡介；沒有播放時寫「目前沒有播放的曲目」
變更：Added｜外殼｜文字按鈕可以用鍵盤選到（強調色外框）、按 Enter 按下
變更：Fixed｜外殼｜窄視窗叫出的詳情面板按 Esc 就會關掉
變更：Fixed｜播放控制｜鍵盤選到按鈕時按 Space 只播放／暫停，不會同時按下那顆按鈕
