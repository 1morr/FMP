# U 里程碑 Android 驗收（2026-10-27）

`prd.md` 的 R1–R7 在 Android 模擬器上走一遍的記錄。Windows 的部分在最後（2026-10-28 在擁有者的 Windows 電腦上驗）。

## 環境

| 項目 | 內容 |
|---|---|
| 平台 | Android 模擬器，AVD `Medium_Phone_API_37.0`（1080x2400，手機直向；橫向 914dp） |
| 建置 | `origin/main` `947779f2`（U 的 PR 0–17 已合併），`flutter build apk --flavor dev --debug`，dev flavor `com.personal.fmp.dev` |
| 模式 | 重播（測試插件 `fmp-test`，不連網）為主；最後一節是最少量的真實連線 |
| 語系 | 系統預設（英文）；匯入進度另切到繁體中文確認字串 |
| 聲音 | 模擬器的音訊不當作證據；播放以畫面與語意樹判斷 |
| 截圖 | 檔名在 `<暫存目錄>/acceptance/`，不進 repo；截圖內沒有個人資料（帳號是測試插件的假帳號） |

資料：開驗前 dev 資料庫已有三張匯入歌單（`pl-basic`、`pl-auth`、`pl-long`）、兩個電台、搜尋歷史與播放歷史，都是測試插件的資料。驗證中新建又刪掉的歌單（`AccLocal`、`pl-long-slow`、`pl-long-nototal`）已清掉。

## 結果摘要

- 通過：大部分項目，見下表。
- 沒通過：無「功能壞掉」的項目。
- 觀察（版面或與 PRD 字面不符，需要擁有者看過再決定）：8 項，見「已知問題與觀察」。
- 沒驗到：封面選擇器的封面格、首頁「建立歌單」佔位、歷史多選／日期／搜尋、佇列的 Mix 標題，原因見表。

## 逐項結果

「通過」＝畫面與語意樹符合 PRD 該條。引用的節點是 `ax_flatten.py` 的 `txt=`。

### R1 外殼、導覽、主題

| 需求 | 結果 | 觀察 | 證據 |
|---|---|---|---|
| R1.1 導覽六項 | 通過 | 手機底部 `Home / Search / Library / Queue / Radio / Settings`，節點 `Queue\nTab 4 of 6`；橫向側欄同一組；佇列是整頁 | s01、s11、l01 |
| R1.2 側欄 72↔256dp、記住狀態 | 通過 | 橫向收合 72dp，按 `Expand side bar` 展開出 `FMP` 與 `Collapse side bar`；強制停止再啟動後仍是展開 | l01、l03、l04 |
| R1.2 補充 | 觀察 | 橫向手機的高度放不下六項，只看得到 4–5 項，要在側欄內捲動才按得到 Radio、Settings（捲動後可用） | l01、l02 |
| R1.3 置中 AppBar | 通過 | `Home`、`Queue`、`Library`、`Radio`、`Settings` 的標題節點 `center=(540,136)`（手機寬 1080 的正中） | s01、s11、s16 |
| R1.4 播放列橫跨、頂端細線 | 通過 | 播放列在側欄與右側面板下方橫跨整個寬度；播放列頂端有細線，播放中 `SeekBar txt='0:00, Playback position'`，細線隨進度填色（s06）。hover 變粗在 Windows 驗 | s06、l01 |
| R1.5 主題 preset 與元件主題 | 通過 | 9 色節點：`Default purple / Indigo / Ocean blue / Teal / Forest green / Sun yellow / Amber orange / Ruby red / Rose pink`；選 Ruby red 後整個 App 換色（導覽指示、開關、按鈕） | s25、s26 |
| R1.6 外觀：主題模式、主題色、自訂色、字型、語言 | 通過 | `System / Light / Dark`；`Custom` 開出 `Custom theme color` 對話框（HEX、Hue、Saturation、Brightness），輸入 `00BCD4` 套用後 App 變青色，`Custom` 圓點打勾；字型選 `Serif` 後全 App 換襯線字 | s25、s26、s27、s27b |
| R1.6 Android 字型清單 | 觀察 | 清單只有 `Default font / Sans-serif / Serif / Monospace` 四個通用字族，沒有具名的中文字型；PRD 寫「清單內容改成繁中為主」 | s25 |
| R1.6 重啟後主題與字型 | 沒驗 | 只重啟驗了側欄展開；主題色與字型的持久化由資料庫與 widget 測試守，沒有在裝置上重啟確認 | — |
| R1.7 Windows 標題列 | 待 Windows | 見最後一節 | — |
| R1.8 右側面板 | 通過 | 橫向有曲目時出現 `Now playing`，內容有標題、`Uploader`、`Duration`、`Source`、`Next up`，頂部有 `Add to playlist` 與 `Collapse the now playing panel`；清空佇列後面板與播放列一起消失，側欄延伸到底 | l01、l12、l14 |
| R1.8 點封面或標題開原網頁 | 沒驗 | 測試插件只有 `tone-440` 帶 `webUrl`，點了會開外部瀏覽器，沒有走 | — |
| R1.9 不做液態玻璃 | 通過 | 播放頁、對話框、底部面板都是不透明 Material | s54、s55 |
| R1.10 舊資料匯入四項 | 測試驗證 | 沒有舊版 Isar 資料庫副本，裝置上驗不了。`test/legacy_import/legacy_settings_converter_test.dart`：群組 `theme color and font (primaryColor, fontFamily)`、`railExpanded is written for both sources`、群組 `search history`；`legacy_settings_migration_test.dart`。本機（Mac）跑這兩個檔通過；`legacy_converter_import_test.dart` 有 2 項因本機沒有 `libisar.dylib` 失敗（Mac 環境已知問題，`implement.md` PR 1），不是這次的回歸，交給 CI | — |

### R3 播放頁

| 需求 | 結果 | 觀察 | 證據 |
|---|---|---|---|
| R3.2 控制區 | 通過 | 80dp 實心播放鍵（`Play (Space)` 在 `center=(540,2169)`）、曲名置中粗體、沒有毛玻璃底板 | s54 |
| R3.3 頂列 | 通過 | 手機：`Close the player (Esc)`、`Add to playlist`、`Track info`、`More`；寬版加音量、輸出裝置在播放列（`Mute`、`Volume`） | s54、l07、l01 |
| R3.3 資訊鈕 | 通過 | 手機開底部面板：封面、標題、`Uploader`、`Duration`、`Source`；返回鍵只關面板、播放頁還在 | s55 |
| R3.4 封面圓角與陰影 | 通過 | 封面大圓角、下方有陰影 | s54、l07 |
| R3.4 上滑轉場 | 通過 | 開啟時半途截圖：播放頁從底部升起、後面的搜尋頁還看得到 | s57 |
| R3.4 關閉 | 通過 | 左上收合鈕關閉（畫面已回到搜尋頁）。佇列清空時自動關閉沒有驗。PRD 與對照文件 P-19 只要求轉場方向，沒有「下滑手勢關閉」；實測在內容區下滑沒有關閉，與舊版一致 | s54 |
| R3.5 窄版沒有封面／歌詞切換 | 通過 | 手機直向沒有切換鈕 | s54 |
| R3.5 橫向矮版 | 通過 | 914dp 橫向：左封面、右曲名、進度、五個控制，單欄沒有歌詞欄 | l07 |
| R3.1 寬版 5:7 與歌詞欄 | 不適用 | M7 之前一律單欄 | — |
| R3.3 橫向資訊面板 | 觀察 | 橫向開底部面板時封面佔去大半高度，標題、`Uploader` 等在畫面外，要在面板內捲動 | l08 |

### R4 佇列

| 需求 | 結果 | 觀察 | 證據 |
|---|---|---|---|
| R4.1 頂部 | 通過 | 節點 `Jump to bottom`、`Shuffle`、`Clear the queue`，橫幅 `Playing track 2\n5 songs in queue`；單數 `1 song in queue` | s11、s13 |
| R4.1 打亂 | 通過 | 目前播放是第 2 首，按 `Shuffle` 後橫幅變 `Playing track 1`，第一列是 `Test tone 440 Hz (room)`（原來的目前曲目）；只剩 1 首時 `Shuffle` 停用（節點沒有 `click=True`） | s11、s12、s13 |
| R4.1 清空要確認 | 通過 | `Clear the queue?`，確認鈕 `Clear` 是紅色 | s14 |
| R4.1 空佇列引導 | 通過 | `The queue is empty`、`Songs you play from Search or the Library line up here.`、`Go to Search` | s15、l14 |
| R4.1 Mix 標題／停用打亂／續取轉圈 | 沒驗 | 測試插件的 Mix 要從曲目選單開，這次沒走；由 widget 測試守 | — |
| R4.2 每列 × 、把手、選單 | 通過 | 節點 `Remove "Playlist tone 220 Hz" from the queue`；按 × 後 5→4 首 | s11 |
| R4.2 手機直向列寬 | 觀察 | 曲名只剩約 12 個字（`Test tone 44…`），時長、×、⋮、把手佔去右側 | s11 |
| R4.3 正在播放遮罩 | 通過 | 目前那列封面疊動態遮罩，曲名主色粗體；搜尋、首頁排行同樣 | s11、s06、s01 |

### R5 歷史

| 需求 | 結果 | 觀察 | 證據 |
|---|---|---|---|
| R5.1 統計卡 | 通過 | `Today\n3 plays\n0m`、`This week`、`All time\n11 plays`（測試曲 2 秒，總時長 `0m`） | s17 |
| R5.1 篩選與排序 | 通過 | 音源 chip `All / FMP Test Plugin`；排序選單 `Newest first / Oldest first / Most played`；選 `Oldest first` 後第一組變成最舊的日期 | s17、s20 |
| R5.1 日期、搜尋鈕 | 部分 | 節點 `Pick a date`、`Search history` 在頂列；沒有操作 | s17 |
| R5.2 日期分組 | 通過 | 時間軸圓點、`Today  3 songs`、可折疊（節點 `…, Collapse Today` ↔ `Expand`） | s17、s20 |
| R5.3 每列時長與音源圖示 | 通過 | 列尾有 `0:02` 與 `FT` 徽章，副標 `FMP · 17:29` | s17 |
| R5.4 刪除此曲所有紀錄 | 通過 | 列選單 `Remove from history`、`Delete all plays of this song` 都是紅字；確認對話框 `Delete every play of this song?`，`Delete` 紅色鈕（取消，沒有真的刪） | s18、s19 |
| R5.4 多選批次刪除 | 沒驗 | 選單有 `Select`，沒有再走 | s18 |
| R5.5 載入／重試／空狀態 | 沒驗 | 資料量小，載入太快；沒有造空歷史 | — |

### R6 搜尋與瀏覽

| 需求 | 結果 | 觀察 | 證據 |
|---|---|---|---|
| R6.1 正在播放標示 | 通過 | 搜尋結果中正在播放的 `Test tone 440 Hz (tone)` 疊遮罩、粗體主色；切到下一首後標示跟著走；首頁排行、歌單詳情同樣 | s06、s57、s01 |
| R6.2 全部音源、預設選它 | 通過 | `All sources` 排第一且打勾；真實連線的結果見最後一節 | s04、s05、r01 |
| R6.3 搜尋歷史 | 通過 | 空搜尋框顯示 `Search history`、`Clear`、`room`、`tone`，每列有 `Remove from search history` | s04 |
| R6.4 捲到底自動載入 | 通過 | 搜 `tone` 第一頁兩首，沒有按任何鈕就出現第三首與 `All loaded` | s05 |
| R6.5 播放數 | 通過 | `Views 1.23K`、`Views 4.6M`、`Views 12`；無值的列沒有（測試插件的排行 4、5 名；網易雲音樂的搜尋結果） | s05、s01、r02 |
| R6.6 首頁：卡片、選單、直播優先 | 通過 | 歌單卡與電台卡都有 `More options`；電台列 `Test live room\nLive` 排在 `Test offline room\nOffline` 前 | s03 |
| R6.6 卡片高度 | 通過 | 電台卡與最近播放卡高度一致 | s03 |
| R6.6 「建立歌單」佔位 | 沒驗 | 資料庫已有歌單，沒有造「沒有歌單」的狀態；音樂庫頂列有 `New playlist` | s16 |
| R6.6 捲動箭頭 | 待 Windows | 桌面 hover 才有 | — |
| R6.7 電台：清單／網格 | 通過 | 手機直向清單；橫向 914dp **收起右側面板**後是網格（圓形封面、`Live` 徽章） | s21、l10 |
| R6.7 橫向面板開著時的電台 | 觀察 | 面板開著時內容寬度約 480dp，電台頁退成清單；要看到網格得先收起面板 | l09、l10 |
| R6.7 排序模式 | 通過 | 按 `Sort` 進入：`Done` 鈕與說明 `Drag the handles to reorder. Outside sort mode, live stations are listed first.`；手動序（離線在前）與平常序（直播在前）不同 | s22 |
| R6.7 新增對話框說明 | 通過 | `Paste a live room URL; an enabled source will recognise it.` | s23 |
| R6.8 多選補項 | 通過 | 選取列：`Cancel selection (Esc)`、`Select all (Ctrl+A)`（全選後變 `Deselect all`）、`Play next`、`Add to queue`、`More actions`；溢位選單 `Add to playlist…`、`Add to remote playlist…` | s08、s09 |
| R6.9 探索下拉重新整理 | 通過 | 下拉出現轉圈，時間戳從 `5:28 PM` 變 `5:46 PM` | s52 |
| R6.10 錯誤狀態 | 通過 | 探索的 `Broken` 榜單：紅色驚嘆號圖示、`Couldn't update the chart`、`Use Refresh at the top to try again.`；首頁同榜單是緊湊橫條（`Update failed`） | s53、s02 |
| R6.10 轉圈下說明文字 | 通過 | 匯入對話框 `Looking up the link…` | 對話框文字，見匯入一節 |
| R6.11 時長固定欄 | 通過 | 曲目列尾 `0:02`、`2:41`、`55:31` 靠右同一欄 | s05、r01 |
| R6.11 直播間列 | 通過 | 未開播：封面灰階、`Offline` 徽章、列內沒有播放鈕、分區標籤 `Chat`；開播：`Live`、`Test area`、`42 watching` | s07 |

### R7 音樂庫、匯入、設定

| 需求 | 結果 | 觀察 | 證據 |
|---|---|---|---|
| R7.5 格狀卡片、來源圖示、連結圖示 | 通過 | 手機兩欄、橫向三欄；卡片左上 `FT` 徽章、右上拖曳把手、副標 `🔗 3 songs`（連結圖示）；頂列匯入鈕是連結圖示 `Import a playlist` | s16、l11 |
| R7.5 來源圖示 | 觀察 | 測試插件與 Bilibili 的來源「圖示」都是兩個字母的縮寫徽章（`FT`、`BI`），不是品牌圖示 | s16、r01 |
| R7.5 載入轉圈／錯誤重試 | 沒驗 | 資料在本機，載入太快 | — |
| R7.6 歌單詳情 | 通過 | 頂圖模糊背景，`1200 songs · 40 min`、`Under 1 min`，徽章 `Imported · FMP Test Plugin`、`Owner: FMP` | s29 |
| R7.7 從歌曲封面選 | 部分 | 編輯對話框有 `Pick from song covers`，開出 `Choose a cover`；測試曲目都沒有封面，只出現 `None of the songs in this playlist has a cover`。封面格要用有封面的歌（真實插件）驗 | s34、s35 |
| R7.8 加入歌單資訊卡、手機底部面板 | 通過 | `Add to playlist` 底部面板：資訊卡（`3 songs`）、`New playlist`、勾選 `AccLocal\n0 songs`、`Add` | s10、s32 |
| R7.9 紅色確認鈕、選單刪除上色 | 通過 | 刪歌單 `Delete the playlist?` 的 `Delete` 是紅色；歌單卡選單的 `Delete`、歷史的兩項紅字 | s33、s36、s19、s14 |
| R7.10 網址匯入對話框來源圖示 | 通過 | 貼上網址後輸入框尾端出現 `FT` 徽章，節點 `ImageView txt='FMP Test Plugin'`，並出現兩個選項 | s38 |
| R7.10 帳號歌單全選、底部主要鈕 | 通過 | 有可匯入的歌單時底部 `Select all`、`Import selected (0)`（節點，沒有截圖）；全部已匯入時三列的勾選框停用 | s46、s47 |
| R7.11 分組列摘要 | 觀察 | 設定首頁只有 `Appearance\nTheme: System`、`Playback\nQuality: Medium` 有摘要；`Accounts`、`Library`、`Network`、`Plugins`、`Backup and restore`、`About`、`Debug` 沒有 | s24 |
| R7.11 音質說明 | 通過 | `High: Highest bitrate, best quality` 等三行與備援說明 | s28 |

### R7.1–R7.4 匯入進度與取消（`pl-long-slow`、1200 首）

| 步驟 | 結果 | 觀察 | 證據 |
|---|---|---|---|
| 網址匯入（英文） | 通過 | 對話框內：`Imported 100 of 1200`（s40）、`Imported 300 of 1200`（s41），有刻度的進度條、目前曲名 `Long track 300`、`Cancel`；背後歌單格同步增加（`300 songs`） | s40、s41 |
| 網址匯入（繁中） | 通過 | `已匯入 150／1200 首`、`Long track 150`、`取消` | z02 |
| 取消＝丟掉新匯入 | 通過 | 按取消後提示 `Import cancelled`／`已取消匯入`，音樂庫沒有 `Long playlist (slow)`；等 8 秒後仍沒有 | s42、z03 |
| 沒給總數（`pl-long-nototal`） | 通過 | `Songs read: 450`、不定長進度條、目前曲名 | s44 |
| 完整匯入 | 通過 | 讀完 `1200 songs · 40 min`，歌單可開 | s50 |
| 帳號匯入全頁 | 通過 | 標題 `Import playlists`、總進度 `Playlist 0 of 1`、列內 `Imported 1000 of 1200` 與進度條、`Cancel`；完成後 `Playlists imported: 1`、`Imported 1200 of 1200`、`Done` | s48、s49 |
| 帳號頁 | 說明 | 測試插件的帳號 `FMP Test User` 本來就在登入狀態（假憑證，這次沒有登入、登出） | s45、s46 |
| R7.3 歌單刷新轉圈、R7.4 外部匯入曲名 | 沒驗 | 刷新用 `pl-grow` 的情境；外部匯入要有外部歌單來源；由 widget 測試守 | — |

### 真實連線（R6.2 多音源，最少量）

從「設定 › 插件 › 可安裝」安裝官方索引裡的 Bilibili、網易雲音樂、YouTube（索引共 5 個：另有 QQ 音樂、Spotify，沒裝）。為了只看三組，搜尋時暫時停用測試插件，驗完已重新啟用。搜一次 `piano`，選「全部音源」。

| 項目 | 結果 | 觀察 | 證據 |
|---|---|---|---|
| 安裝確認 | 通過 | `Install Bilibili?`：版本、能力、連到的網站、警語 | s62 |
| chip 順序 | 通過 | `All sources / Bilibili / 網易雲音樂 / YouTube` | r01 |
| 三組依 chip 順序 | 通過 | 往下捲，群組標題依序是 `Bilibili`、`網易雲音樂`、`YouTube` | r01、r02 |
| 群組標題的來源圖示與名稱 | 觀察 | 有名稱；圖示是 `BI` 縮寫徽章 | r01 |
| 播放數 | 通過 | Bilibili `▶ 1.86K`、`166K`…；YouTube `Views 333K` 等；網易雲音樂的結果沒有播放數（該插件不提供） | r01、r02 |
| 自動載入 | 通過 | 每個插件只送出一次搜尋，沒有額外載入下一頁（見下） | — |
| 播放一首 | 沒做 | 選配，為少打網路沒做 | — |

## 真實請求清單

來源是 App 的 `logs/fmp.jsonl`（tag `network`），路徑與查詢已遮蔽。沒有登入、沒有帳號頁、沒有迴圈。

| # | 請求 | 次數 | 什麼觸發 |
|---|---|---|---|
| 1 | `GET raw.githubusercontent.com/1morr/fmp-plugins/main/index.json` | 1 | 開「可安裝」分頁 |
| 2 | `GET …/bilibili/bilibili.js`、`…/bilibili/checks.json` | 各 1 | 安裝 Bilibili |
| 3 | `GET …/netease/netease.js`、`…/netease/checks.json` | 各 1 | 安裝網易雲音樂 |
| 4 | `GET …/youtube/youtube.js`、`…/youtube/checks.json` | 各 1 | 安裝 YouTube |
| 5 | Bilibili `GET api.bilibili.com/x/web-interface/search/type`（`keyword=piano`、第 1 頁） | 1 | 搜尋 |
| 6 | 網易雲音樂 `POST music.163.com/api/cloudsearch/pc` | 1 | 搜尋 |
| 7 | YouTube `POST www.youtube.com/youtubei/v1/search` | 1 | 搜尋 |
| 8 | 圖片快取：封面縮圖 `GET`（`*.hdslb.com`、`p1/p2.music.126.net`、`i.ytimg.com`） | 約 68 | 搜尋結果與首頁排行的封面 |
| 9 | **安裝後自動刷新首頁排行**：Bilibili `GET /x/web-interface/nav`、`/x/web-interface/ranking/v2`；網易雲音樂 `POST /api/v6/playlist/detail`、`/api/v3/song/detail`；YouTube `GET www.youtube.com/sw.js_data`、`POST /youtubei/v1/config`、`/youtubei/v1/browse` | 各 1 | 插件裝好後 App 自己刷新排行，不是我按的 |

第 9 項是計畫外的：安裝官方插件會立刻對三個站各打 2–3 個請求。ADR 0027 §決定 2 的「各音源搜尋一次」只算 5–7；之後驗收若要嚴格控制，要知道安裝本身就會觸發排行刷新。

## Windows 實機（2026-10-28）

| 項目 | 內容 |
|---|---|
| 平台 | 擁有者的 Windows 11 x64 電腦，螢幕 3840×2160、縮放 150%（DPI 144） |
| 建置 | `origin/main` `381b2bc6`，以及修正分支（#345），`flutter build windows --flavor dev --debug`，資料在建置目錄旁的 `userdata-dev`（全新，與擁有者的資料分開） |
| 模式 | 重播（測試插件 `fmp-test`），沒有對音源網站發請求；建置時下載依賴（pub、nuget、cargo） |
| 操作 | 從 Mac 經 SSH，以排程工作在擁有者登入中的桌面工作階段執行腳本：MSAA 讀樹與點擊、合成滑鼠與鍵盤、`PrintWindow` 截圖；截圖不進 repo |

結果（「沒驗」的原因寫在該條）：

- PR 2：清單有 6 個 Windows 字型，逐一切換都套用到整個 App；標楷體、新細明體、Meiryo 字形明顯不同，選項名稱也以各自的字型顯示。淺色主題與主題色（青綠）套用。沒驗：自訂色（Android 已驗）。
- PR 5：側欄展開、收合；搜尋頁多選時 Ctrl+F 退出多選、焦點回到搜尋框且字被選取。沒驗：hover 效果與動畫的觀感、重啟後記住展開。
- PR 6：細線滑鼠移入變粗、出現把手與時間泡泡（`0:00 / 0:02`）；播放列在展開與收合的側欄下方都橫跨整個寬度；有曲目時面板出現；加入歌單對話框；840 邊界（827dp 沒有面板、860dp 有）。沒驗：拖曳中移出播放列；Tab 到細線（細線只在可拖曳時拿得到焦點，2 秒的測試曲播完就不行）；「下一首」（佇列只有一首）。
- PR 12：「我的歌單」一排 8 張卡，滑鼠移入時右端漸層與右箭頭；按右箭頭捲到底，左箭頭出現、右箭頭收起；移出後箭頭消失；右鍵開歌單卡選單（空歌單的「全部加入佇列」停用、「刪除」紅字）。沒驗：滑鼠拖曳捲動、漸層下的卡片點擊與滾輪、電台卡與電台網格（沒有電台資料）。
- PR 13：音樂庫格狀在 1400dp、側欄展開、面板收起時 6 欄（側欄收合多 184dp，約 7 欄）；卡片 hover；用滑鼠拖封面角的把手，把第 1 張排到第 3 張。沒驗：頂圖在寬視窗的版面。
- PR 15：
  - 系統標題列隱藏，自繪列 36dp（按鈕 54px，150%）淺色與深色；標題文字是「FMP」（刻意不翻譯）。
  - 左、右、下三邊與右下角拖曳可縮放，頂邊不行（游標在頂邊是一般箭頭，拖曳只會移動視窗），與預期一致。
  - 標題列空白處拖曳移動視窗、雙擊切換最大化；最小化、最大化、還原鈕，最大化時名稱變「還原」；Win+↑、Win+↓；Win+← 貼邊後仍是「最大化」；拖到螢幕頂端最大化（Aero Snap）。最大化時按鈕沒有被切到。
  - 標題列 tooltip（「最大化」）。Debug 頁、對話框開著時標題列都在。**播放頁開著時標題列被蓋成一條灰帶**：背景模糊沒有裁切、溢到頁面上方，已在 #345 修正，重建後確認標題列正常。
  - 同一個 flavor 再開一次：沒有第二個行程，最小化的舊視窗還原並在前景。
  - 播放頁開著時把視窗縮過 840 與 600（569dp 是窄版播放頁）再拉回，F6 後 Esc 仍關掉播放頁。
  - 搜尋框內 Ctrl+Q 換到佇列，Ctrl+L 沒反應。
  - Alt+F4 與 `WM_CLOSE` 都正常結束行程；結束後 SMTC 沒有 `com.personal.fmp.dev` 的工作階段。
  - 整段在 150% 縮放下進行，標題列與縮放邊的命中區正確。
  - 沒驗：啟動時有沒有先閃一下（截圖抓不到）；dev 與 prod 同時開（prod 的 AppUserModelID 與單一實例和舊版共用，為了不碰到擁有者的舊版沒有跑）；Win 10 的 1px 白線（這台是 Win 11）；對話框開著時拖曳標題列。
- 根 route 焦點：播放頁開著時跨過 600 來回，Esc 仍作用在播放頁；搜尋框跨 600 時文字保留。沒驗：Debug 頁開著時跨 600。

### 第二輪補驗（同日）

- PR 5：重啟後側欄仍是展開。
- PR 6：單曲循環播放中，F6 進播放列的第一個焦點就是細線：變粗、把手、時間泡泡（`0:01 / 0:02`）、外框。按住細線往上拖出播放列，細線維持展開、把手跟著游標的水平位置。←／→ 一次 5 秒，測試曲 2 秒看不出來，沒驗。
- PR 12：卡片列用滑鼠按住拖曳會捲動、不會誤開歌單；漸層下的卡片點得到（開出 Shelf 8）；捲到中間時兩個箭頭都在。以網址加了 4 個測試直播間：電台頁網格（收起面板、收合側欄後），開播的排在未開播前面；卡片 hover 底色；電台頁與首頁的電台卡右鍵開出紅字「刪除」。
- PR 13：歌單頂圖在 1280dp 與最大化（2560dp）都是模糊背景鋪滿、封面與標題在左。
- PR 15：對話框開著時拖曳標題列，視窗移動、對話框還在。
- 根 route 焦點：Debug 頁開著時縮到 569dp（Debug 變單欄）再拉回，Debug 頁仍在最上層、回到雙欄。
- 只剩擁有者要看的：啟動時有沒有閃、側欄動畫的觀感、dev 與 prod 同時開。

### Windows 驗證的環境事項

- 從 SSH 直接建置會失敗（nuget 下載與 Rust 編譯），在擁有者的桌面工作階段裡建置才成功；第一次 9 分鐘，之後約 2.5 分鐘。
- 滑鼠停在帶 tooltip 的元件上之後，MSAA 讀到的樹會停在舊狀態（`docs/troubleshooting.md` 的 `Failed to update ui::AXTree`，上游 `flutter/flutter#182444`），之後改以截圖判斷。
- 腳本裡的中文要存成 UTF-8 帶 BOM，PowerShell 5.1 才不會用 cp950 讀成亂碼。

R2（Apple 平台慣例）照 PRD 以 widget 測試驗，不在這份。

## 已知問題與觀察

### 偶發失敗的測試（來自 `implement.md`）

- **未解決**：`plugin_onboarding_test.dart` 的 flutter_tester segmentation fault（PR 15 合併 main 後的一輪）。原本的 log 沒留下，重現不出來；已排除結束時的行程、QuickJS 的 stack 檢查、`Shutdown` 之後的呼叫。已知但沒證明是原因：`QuickJsRuntime2.close` 先 `jsFreeContext` 才釋放 Dart 端持有的 JS 值（flutter_js 0.8.7），以及負載下測試結束時插件還在載入、載入完的 runtime 沒人 dispose。
- **未解決**：`test/ui/tracks/part_display_test.dart`「the player bar shows the composed title」卡住到逾時（PR 5 的一輪完整跑，log 沒留下）。目前的程式碼與當時的程式碼都在 40 份副本加負載下重現不出來。
- 已解決（留作紀錄）：`image_cache_manager_test.dart` 兩個插件同時下載同一網址；`plugin_onboarding_test.dart` 負載下的斷言太早。

### 這次驗收發現

以下都不是功能壞掉，是版面、字面不符或沒驗到。需要擁有者決定要不要開修正。

1. **914dp 橫向、側欄展開加右側面板，內容區只剩約 290dp。** 側欄 256dp、面板 366dp。搜尋結果曲名縮成 `Test t…`、播放數被擠掉（只剩 `▶`），首頁排行曲名 `Hot tone…`。收合側欄或面板就恢復。證據：l03、l05、l06。
   - **已修正**（擁有者核可）：內容區至少留 360dp，放不下時側欄畫成收合，按展開會一併收起面板（ADR 0035 §決定 2 的修訂，`implement.md` §驗收後修正）。
2. **面板開著時電台頁是清單，不是網格。** 內容寬度不到展開斷點。PRD R6.7「expanded 以上用網格」若指視窗寬，914dp 應是網格；現在是依內容寬度。證據：l09 對 l10。
3. **橫向手機的側欄放不下六項。** 播放列佔 120dp 後，側欄只有約 340dp 高，Radio、Settings 要捲動才按得到。證據：l01、l02。
4. **橫向曲目資訊面板的內容在畫面外。** 封面太大，標題與欄位要捲。證據：l08。
5. **手機直向佇列的曲名被截成約 12 字。** 時長、×、⋮、把手四個東西並排。證據：s11。
6. **設定首頁只有兩列有摘要**（外觀、播放）。R7.11 寫「分組列加摘要」，其餘七列沒有。若是刻意，PRD 要補一句。證據：s24。
7. **Android 字型清單是四個通用字族**，沒有具名的中文字型，與 R1.6「繁中為主」的字面不同。Android 的系統中文字型沒有穩定名稱可列，這點要擁有者確認。證據：s25。
8. **「Amber orange」色票看起來是深黃褐色**（接近橄欖），與名稱不符。證據：s25。
9. **來源圖示是縮寫徽章**（`FT`、`BI`），官方插件也是。R7.5 寫「卡片有來源圖示」，要確認縮寫是否算數。證據：s16、r01。
   - **已修正**（擁有者核可）：fmp-plugins #27 讓五個官方插件的 manifest 都內嵌 `icon`（bilibili 1.11.1、netease 1.8.1、youtube 1.7.1、qqmusic 1.0.1、spotify 1.0.1）。Android 更新插件後，匯入對話框的 B 站網址顯示品牌圖示，不再是 `BI`。測試插件沒有圖示，仍是 `FT`。

### 沒驗到的項目

- 首頁「建立歌單」佔位規則、歷史的多選／日期／搜尋、佇列的 Mix 標題與續取轉圈、歌單刷新轉圈（R7.3）、外部匯入曲名（R7.4）、點封面或標題開原網頁（R1.8）、封面選擇器的封面格：測試資料造不出，已列在表中。
- 外觀的主題色與字型沒有在重啟後確認（側欄展開有）。

### 驗證過程的環境事項

- 模擬器的 adb 伺服器隨每次工具呼叫結束而死，一次呼叫內要先 `adb kill-server` 再啟動 `adb nodaemon server`，之後同一次呼叫內的指令才穩定。需要在匯入進度的幾秒內截圖時，把指令包成一條 `adb shell '…; sleep; screencap …'` 在裝置上連續執行。
- 驗完還原：手機直向（`user_rotation 0`），語系回到系統預設，主題回預設紫與預設字型；測試插件已重新啟用。dev App 留在裝置上，另外裝了 Bilibili、網易雲音樂、YouTube 三個官方插件。
