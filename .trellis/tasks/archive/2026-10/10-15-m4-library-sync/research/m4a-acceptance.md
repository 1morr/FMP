# M4a 驗收：兩平台端到端

來源：`implement.md`「## M4a 驗收」→「### 兩平台端到端」的九個步驟。日期 2026-10-21，FMP `main` 23b9c83b、fmp-plugins `main`（bilibili 1.10.0、netease 1.7.0、youtube 1.6.0），dev flavor、debug build。

- **Android**：模擬器 `Medium_Phone`（SDK 37），App 語系英文。
- **Windows**：Windows 11，App 語系繁體中文。
- **擁有者在場**：第 1 步清資料後在兩個平台重新登入三個平台；第 6 步的寫入事先取得同意。
- **擁有者決定（驗收中）**：沒有平台差異的步驟只做 Android。第 6 步（寫入走同一套 Dart 程式碼）與第 8 步的四個重播狀態因此只在 Android 做；排程（生命週期是平台各自的）兩個平台都做。

## 結果

| 步驟 | Android | Windows | 模式 |
|---|---|---|---|
| 1 清資料、首次啟動引導、裝插件 | 通過 | 通過 | 真實（官方插件庫）＋開發入口 |
| 2 導覽、本機歌單、多選、重排、移除、加入佇列、首頁、歷史 | 通過 | 通過 | 重播（`fmp-test`） |
| 3 三平台公開歌單匯入與手動刷新 | 通過（多 P 改在第 6 步） | 通過 | 真實、匿名 |
| 4 Mix 建立與播放 | 通過 | 通過 | 真實、匿名 |
| 5 帳號頁匯入「FMP 測試」、關開關後刷新 | 通過 | 通過 | 真實、登入 |
| 6 「FMP 測試」加入與移除（三平台各一次） | 通過 | 不做（擁有者決定） | 真實、寫入 |
| 7 B 站「從帳號匯入電台」→ 首頁電台區塊 | 通過 | 通過 | 真實、登入 |
| 8 `pl-partial`、`pl-gone`、`pl-auth`、`pl-unavailable`；排程 | 通過 | 排程通過；四個狀態不做（擁有者決定） | 重播 |
| 9 離線 | 通過 | 不做（見下） | — |

## 各步驟的觀察

1. 清資料：Android 解除安裝 `com.personal.fmp.dev` 重裝；Windows 刪建置產物旁的 `userdata-dev`（資料庫、log、WebView）、`%LOCALAPPDATA%\com.personal\fmp-dev\fmp_cache`，`%APPDATA%\com.personal\fmp-dev` 的 secure storage 先改名備份、驗收後刪掉。啟動後首頁出現「安裝插件才能開始搜尋」與三個預設勾選的官方插件 → 安裝、權限確認 → 首頁變成空狀態。`--fmp-dev-plugin` 裝上 `fmp-test`，搜尋頁出現四個音源。
2. 五個導覽項各點一次，畫面標題對得上。建本機歌單 → 搜尋 `song` 多選三首（Android 長按、Windows 曲目選單的「選取」）加入 → 詳情拖曳把手把第三首移到最前、移除一首（剩 2 首）→「全部加入佇列」「隨機加入佇列」各有提示 → 首頁「我的歌單」有這張 → 音樂庫「歷史」開得起來。
3. YouTube `PLjxrf2q8roU23XGwz3Km7sQZFTdB996iG`（181 首）、B 站官方收藏夾 `fid=4026748432`（10 首）、網易 `19723756`（100 首）各匯入一次、手動刷新一次，「上次刷新」時間都更新。這張 B 站收藏夾沒有多 P 影片，多 P 改在第 6 步以「FMP 測試」驗。
4. `mix:dQw4w9WgXcQ` 建立「Mix - Rick Astley …」→「Mix 播放」：Android 媒體工作階段 `PLAYING`、Windows 播放鈕變「暫停」，之後手動暫停。先試的 `mix:TfoJ55nx1S4`（Flutter 清單裡的一部）回「找不到，可能已被移除」：`next` 請求 200、插件判定這部影片沒有 Mix（`NotFound: no Mix playlist for this video`）。
5. 帳號頁三個平台的「歌單」各列出帳號的歌單 → 只勾「FMP 測試」匯入，三張的 `writable` 都是 1 → 三個平台的「以登入身分瀏覽與播放」都關掉 → 逐張刷新。兩個平台、三個插件都是同樣的兩個請求：第一個不帶憑證、第二個帶憑證重送，刷新完成（B 站 `fav/resource/list`、網易 `v6/playlist/detail`、YouTube `browse`）。
6. Android，每個平台搜尋一次、挑一首「加入遠端歌單」到「FMP 測試」→ 60 秒後的自動刷新把它帶進本地副本 →「從遠端歌單移除」→ 本地副本回到原本的首數：
   - B 站：搜尋 `OST full album`，挑一部有「Show parts」的 5 P 影片。加入（`wbi/view`、`fav/resource/deal`）→ 刷新以 `x/player/pagelist` 展開，本地從 2 首變 7 首，詳情頁以影片標題分組、底下 P1…P5（**B 站多 P 展開的真實驗證**）。從 P1 的選單移除（`fav/resource/batch-del`）→ 刷新 `removed: 4`（P1 已先在本地移除），回到 2 首。
   - 網易：搜尋 `Lemon` 第一首。加入與移除各兩個 `linux/forward`，刷新後 3 首、移除後 2 首。
   - YouTube：搜尋 `Never Gonna Give You Up` 第一首。加入與移除各一個 `browse` 加一個 `browse/edit_playlist`；60 秒後的刷新讀得到剛加的那首（寫後讀延遲在 60 秒內），移除後回到 2 首。
7. B 站帳號卡片的選單「從帳號匯入電台」：`MedalWall` 加 `get_status_info_by_uids`，log `Imported live rooms from the account {added: 90, existing: 0}`（兩個平台相同）；首頁出現「電台」區塊。
8. 重播（Android）：
   - `pl-partial`：3 首都在，狀態列「Last refreshed: partial · …」。
   - `pl-unavailable`：第 2 首標「Unavailable · FMP」。
   - `pl-gone`：從一開始就不存在，匯入對話框回「Couldn't import: Not found. It may have been removed.」；詳情頁的「來源失效」狀態列在實機到不了，只有測試守著。
   - `pl-auth`：以假憑證 `fmp_test_session=fake-session-0000` 登入 `fmp-test` → 匯入 3 首 → 只登出 `fmp-test` → 刷新：狀態列「Sign in to refresh this playlist」加「Sign in」按鈕，另有錯誤提示。
   - 排程（兩個平台）：匯入 `pl-grow` → 關 App → 把它的 `last_refreshed_at` 改成 25 小時前、`scheduler_runs` 的 `playlist-refresh` 改成 31 分鐘前 → 重啟：log `Playlist refresh finished`，只有 `pl-grow` 的時間更新，其他沒到期的與 `authRequired` 的 `pl-auth` 不動。改 `scheduler_runs` 是必要的：工作間隔 30 分鐘、上次成功時間持久化，只改歌單的時間不會觸發。
   - 生命週期：Android 按 Home 6 分 20 秒、Windows 最小化 6 分 20 秒，期間沒有新的排程工作（電台狀態的間隔是 5 分鐘）；回到前景後到期的電台狀態工作立刻開始。Windows 最小化當下正在跑的那輪電台狀態查詢會跑完（約 35 秒）：看不見只擋「開始」，不中止進行中的工作（`_mayStartScheduled`，照設計）。
9. 離線（Android，`svc wifi disable`、`svc data disable`）：首頁、音樂庫、181 首的詳情照常，頂端「No network connection」；手動刷新提示「Offline, couldn't refresh the playlist」。之後恢復網路。Windows 不做：要關掉主機的網路介面，會連帶切斷這台機器與這個工作階段；離線判斷之後的處理是共用的 Dart 程式碼，平台差異只在 `connectivity_plus` 的偵測。

## 真實請求

兩個平台各自的 log（`fmp.jsonl`）統計，不含封面等媒體請求。

| 插件 | 請求 | Android | Windows |
|---|---|---|---|
| 插件庫 | `index.json`、各插件 `.js` 與 `checks.json` | 8 | 8 |
| B 站 | 登入（QR 產生、輪詢、`cookie/info`、`nav`） | 9 | 8 |
| B 站 | 帳號歌單 `fav/folder/created/list`（帶憑證） | 4 | 2 |
| B 站 | `fav/resource/list`（不帶／帶憑證） | 5／4 | 3／2 |
| B 站 | 寫入 `fav/resource/deal`、`fav/resource/batch-del`、`wbi/view` | 1、1、2 | — |
| B 站 | 搜尋 `search/type`、分 P `player/pagelist` | 1、2 | — |
| B 站 | 排行 `ranking/v2`（首頁排行工作） | 3 | 2 |
| B 站 | 匯入電台 `MedalWall`、`get_status_info_by_uids` | 1、2 | 1、2 |
| B 站 | 電台狀態（`room_init`、`get_info`、`get_anchor_in_room`） | 約 1,780 | 約 1,900 |
| 網易 | 登入（`qrcode/unikey`、`client/login` 輪詢、`account/get`） | 15 | 7 |
| 網易 | `v6/playlist/detail`（不帶／帶憑證）、`v3/song/detail` | 8／4、5 | 5／2、4 |
| 網易 | 寫入與帳號歌單 `linux/forward` | 6 | 1 |
| 網易 | 搜尋 `cloudsearch/pc` | 1 | — |
| YouTube | 登入（`sw.js_data`、`config`、`account_menu`） | 3 | 3 |
| YouTube | `browse`（不帶／帶憑證）、`browse/edit_playlist` | 10／8、2 | 7／3、— |
| YouTube | Mix 與播放（`next`、`player`）、搜尋 | 3、2、1 | 5、2、— |

## 留下的後續

- **電台狀態的請求量**：每個電台每輪 3 個請求（`room_init` 換長號、`get_info`、主播名），預設每 5 分鐘一輪。從帳號匯入後電台數到幾十個，一輪就是兩三百個請求、持續一分多鐘；這次兩個平台各累積約 1,800 個。長號在加入時已存，`room_init` 可以省；B 站有批次的 `get_status_info_by_uids`（匯入時已在用）。屬於 M3 電台的既有行為，M4a 的匯入讓它變明顯。
- Mix 詳情頁的「種子曲目」顯示原始影片 id（`dQw4w9WgXcQ`），不是曲名。
- `mix:<videoId>` 給沒有 Mix 的影片時，訊息是通用的「找不到，可能已被移除」。
- 多 P 影片從遠端移除：確認框寫「移除 1 首」，B 站實際移除整支影片，刷新後其餘分 P 一起消失。
- Windows 的 FMP Dev 在驗收途中（約 02:50，Android 背景測試期間）結束：沒有應用程式錯誤事件，log 停在一般的封面請求；正常關閉也不寫 log，分不出是被關掉還是結束。重開後繼續，沒有再發生。
- 沿用：`pl-gone` 的「來源失效」狀態列與 Windows 的離線只有測試守著。
