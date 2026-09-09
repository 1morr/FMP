# UI 回歸的歷史基準（2026-09-06）

28 張截圖，Windows 15 張、Android 13 張，全部拍於 `679f7829`，**Phase 5 的
UI 改動之前**。它們是 repo 裡唯一一份「改動前長什麼樣」的視覺證據 —— 產生它們
的那份審查報告已經刪除，圖留下來是因為文字取代不了。

環境：Flutter 3.47.1 stable / Windows 11 主機；AVD `Medium_Phone`（411×914dp）
與 `Medium_Tablet`（1280×800dp、800×1280dp）。

| 檔名 | 內容 |
|---|---|
| `win-01-home-1400.png` | Windows 1400dp 首頁（桌面三欄，面板 380） |
| `win-02-1199.png` / `win-03-1201.png` | 斷點兩側對照（版面相同） |
| `win-04-1250-panel.png` | 1250dp 首頁 |
| `win-05-panel-maxdrag.png` | 面板拖到當時的 500dp 上限，標題大量截斷 |
| `win-06-panel-collapsed.png` | 面板收起成 36dp 長條 |
| `win-07-1700-3sources.png` | **1700dp + 面板收起 → 三個排行榜音源** |
| `win-08-1700-panelmax-drops-source.png` | **同視窗 + 面板 500dp → 網易雲音樂整欄消失** |
| `win-09-settings.png` | 設定頁 |
| `win-10-account.png` | 帳號管理（issue #36 的兩態證據） |
| `win-11-narrow-560.png` | 560dp 手機佈局（桌面視窗） |
| `win-12-narrow-340.png` | 340dp，未 overflow |
| `win-13-dark-home.png` | 深色主題首頁 |
| `win-14-player-wide-1280.png` | 1280dp 播放頁：固定雙欄，右欄「暫無歌詞」；同時拍到標題與副標題不同步（進度條在 0:40/3:39 卻寫「選擇一首歌曲開始播放」） |
| `win-15-desktop-lyrics-window.png` | 桌面歌詞子視窗：標題列 8 個控制擠在 28dp，內容永遠停在「等待歌詞...」 |
| `and-01-home.png` | Android 首頁 |
| `and-02-player.png` | Android 播放器（「Select a track to start playing」文案 bug） |
| `and-03-search-empty.png` | Android 搜尋（音源 chip 被切、搜尋歷史空狀態） |
| `and-04-tablet-1280-land.png` | 平板橫向 1280dp 首頁，**未播放 → 三個音源** |
| `and-05-tablet-1280-panel.png` | **同一個視窗，只是播了一首歌 → 面板展開、網易雲音樂整欄消失** |
| `and-06-tablet-drag-attempt.png` | 觸控把面板拖到上限，標題大量截斷 |
| `and-07-tablet-800-portrait.png` | 平板直向 800dp，畫面下方約 34% 空白 |
| `and-08-tablet-800-player.png` | 800dp 播放頁 —— 單欄手機版面放大，封面約 742dp |
| `and-09-tablet-library.png` | 音樂庫空狀態 |
| `and-10-tablet-queue.png` | 佇列空狀態 |
| `and-11-tablet-radio.png` | 電台空狀態（三者結構一致，走共用元件） |
| `and-12-tablet-1280-player-wide.png` | 1280dp 寬版播放頁：右欄佔約 60% 且只放歌詞 |
| `and-13-statusbar-contrast.png` | 四條狀態列並排放大，白字白底 1.05:1 對比深字 5.64:1 |

`win-07` / `win-08` 與 `and-04` / `and-05` 是成對的：同一個視窗、只差面板寬度，
一個音源就消失了。那是「視窗級距不能拿來決定內容欄數」這條規則的來源，規則本身
記在 `lib/ui/AGENTS.md` § Layout Conventions。
