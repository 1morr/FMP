# M3a 驗收紀錄（2026-10-13）

逐項對照本任務 `implement.md`「## M3a 驗收」的 8 個步驟。證據類型：**實測**＝實機、執行時；**測試**＝單元／widget 測試。
兩平台都用 dev flavor 的 debug 建置。帳號是擁有者的（YouTube 是測試帳號）：QR 由擁有者掃、密碼由擁有者輸入。
本檔只記帳號狀態欄位（`accounts.status`）、cookie 的名稱與數量，不記帳號名稱、頭像網址與任何憑證值。

截圖只留在 session 暫存目錄，沒有放進來：搜尋結果的封面與標題是第三方內容。

## Android 模擬器

- **裝置**：AVD `Medium_Phone`，直向 411dp；介面語言英文。
- **建置**：
  - 第 1、2、7、8 步（10-10）：`main` 在 #230 之後（`6284dde8`）。
  - 第 3–5 步（10-13）：`6284dde8` 加上 #232 的分支。
  - 第 5 步的標示與第 6 步的移除（10-13）：`main` 在 #232 之後（`87bad3d2`）加上 #234 的分支。
  - 換建置都用 `adb install -r`，資料與登入保留。
- **模式**：第 1–6 步**真實**（官方插件庫 `1morr/fmp-plugins` 的 `main`：Bilibili 1.2.0、網易雲音樂 1.2.0、YouTube 1.0.0）；第 7、8 步**重播**（測試插件 `fmp-test`），第 8 步另有飛航模式。
- 開始前解除安裝 dev 再重裝，清掉資料與 secure storage。

### 真實請求（整段的網路紀錄，tag `network`）

封面圖片只記張數；音訊串流由播放引擎直連 CDN，不在網路紀錄裡。

| 步驟 | 插件庫（`raw.githubusercontent.com`） | Bilibili | 網易雲音樂 | YouTube |
|---|---|---|---|---|
| 1. 引導安裝 | `index.json` 2、三個插件的 `.js` 與 `checks.json` 各 1 | — | — | — |
| 2. 搜尋、播放 | — | `search/type` 1、`nav` 1、`wbi/view` 1、`playurl` 1；封面 14 | `cloudsearch/pc` 2、`player/url/v1` 1；封面 13 | `sw.js_data` 1、`config` 1、`search` 1、`player` 2；封面 13 |
| 3. 登入 | 打開插件頁時 `index.json` 1 | `qrcode/generate` 2（第一個過期，擁有者手動換新）、`qrcode/poll` 89、`nav` 1；頭像 1 | `qrcode/unikey` 1、`qrcode/client/login` 20、`account/get` 1；頭像 1 | `account/account_menu` 1；頭像 1 |
| 3. 帶憑證的搜尋（關鍵字 `lemon`） | — | `search/type` 1（帶憑證） | `cloudsearch/pc` 3、`player/url/v1` 3（都帶憑證） | `search` 1（帶憑證）；關掉「以登入身分瀏覽與播放」後 `search` 1（不帶） |
| 4. 重啟 | — | `cookie/info` 1（啟動刷新） | — | — |
| 5. 停用、跳過、檢查更新 | `index.json` 4 | 跳過後接著播：`nav` 1、`wbi/view` 2、`playurl` 2（都帶憑證）；`search/type` 1；重啟（換建置）時 `cookie/info` 1 | `cloudsearch/pc` 1（停用前） | — |
| 6. 登出、移除 | — | — | — | — |

- 第 1–2 步之外的 `index.json`：打開插件頁就會讀一次（ADR 0030 §決定 9）。
- 第 5 步停用之後，log 沒有任何網易的請求。
- 兩次重啟時 YouTube 封面各 2 張：播放列與佇列裡的曲目封面。

### 逐步

| 步驟 | 結果 |
|---|---|
| 1. 清資料 → 引導裝三個官方插件 | 通過：Bilibili 1.2.0、網易雲音樂 1.2.0、YouTube 1.0.0 |
| 2. 三個音源各搜尋、播一首 | 通過：三首都出聲；YouTube 的前瞻交接 `Look-ahead handover` |
| 3. 登入 | B 站 QR、網易 QR、YouTube 網頁登入後 `accounts.status` 都是 `active`；三個音源各一次帶憑證的搜尋（網路紀錄 `credentials: true`）；YouTube 關掉「以登入身分瀏覽與播放」後 `source_settings` 是 `youtube|0`，搜尋不帶憑證。**網易的試聽片段沒有實測**：擁有者的帳號是黑膠 VIP，《Lemon》《Patient Zero》都拿到完整的 320 kbps（`Track audible`），沒有試聽片段；以 `playback_controller_test.dart` 的 `recovery: preview clips` 與 M2 驗收第 13 步（`fmp-test` 的 `preview`）為證 |
| 4. 重啟 | 三個帳號仍是 `active`；B 站啟動刷新跑一次（`cookie/info`），帳號頁最後刷新結果「不需要更新」（`last_refresh_result = unchanged`）；網易與 YouTube 沒有刷新，照設計 |
| 5. 停用網易 → 啟用；檢查更新 | `installed_plugins` 的 `netease|0`，搜尋頁的 chip 消失。佇列（測試音 → 網易《Lemon》 → B 站一首）：按下一首，`Stream resolution failed {pluginId: netease}` → `Playback recovery` → `Track skipped`，接著播 B 站那首。重新啟用 `netease|1`，「Check for updates」顯示「All plugins are up to date」。**標示**（#234）：佇列裡網易那首的副標是「Source disabled」，被移除的測試插件那首是「Source not installed」；跳過提示是「Skipped "Lemon": Source disabled」 |
| 6. 登出 YouTube；移除網易 | **登出**：確認框說明「FMP deletes its sign-in data for this source. The "Browse and play while signed in" setting stays.」；帳號列刪除，`youtube|0` 保留；WebView 的 `Cookies` 從 50 個（`.google.com` 13、`.google.com.tw` 10、`.youtube.com` 21、`accounts.google.com` 6）變成 0 個，`SID`、`__Secure-1PSID`、`__Secure-3PSID`、`LOGIN_INFO`、`SAPISID` 都不在。**移除**：確認框「The plugin, its data, its sign-in and its cache are deleted. Songs stay and show "Source not installed".」；之後帳號列、`installed_plugins` 列、快取 33 項（`cache_entries` 的 `netease|image`）、secure storage 的 `credentials.netease` 鍵都不在（`plugin_storage` 本來就是 0 筆）；歷史 4 筆、佇列 1 筆保留，歷史頁顯示「Lemon / Source not installed · 06:09」這類副標 |
| 7. 失效（重播） | `expired`：刷新後搜尋成功（`Credentials refreshed {pluginId: fmp-test}`）；`expired-hard`：帳號標失效，提示「The sign-in to FMP Test Plugin is no longer valid」附「Sign in」 |
| 8. 離線 | 飛航模式：插件頁「Available」分頁與 B 站 QR 登入都顯示「No network connection」加「Retry」（`QR login failed {pluginId: bilibili}`，沒有請求） |

- 第 3–6 步讀 cookie 與 secure storage 時只讀名稱與數量；複製出來的資料庫讀完就刪掉。

## Windows

- **裝置**：Windows 11，縮放 150%，視窗 1920×1080 px；介面語言繁體中文。
- **建置**：`main` 在 #232 之後（`87bad3d2`）加上 `fix/unavailable-source-label`（#234 合併前的同一份程式）。
- **模式**：第 1–6 步**真實**（官方插件庫的 `main`：Bilibili 1.2.1、網易雲音樂 1.2.0、YouTube 1.0.0）；第 7 步**重播**（`fmp-test`，以 `--fmp-dev-plugin` 安裝）；第 8 步沒有實機（見表）。
- 開始前：在新的 worktree 建置，執行檔旁沒有 `userdata-dev\`（資料庫、log、WebView2 資料都在裡面）；刪掉 dev 的 secure storage 檔（`%APPDATA%\com.personal\fmp-dev\flutter_secure_storage.dat`）。舊版的 `com.personal\fmp` 沒有碰。

### 真實請求

| 步驟 | 插件庫（`raw.githubusercontent.com`） | Bilibili | 網易雲音樂 | YouTube |
|---|---|---|---|---|
| 1. 引導安裝 | `index.json` 2、三個插件的 `.js` 與 `checks.json` 各 1 | — | — | — |
| 2. 搜尋、播放 | — | `search/type` 1、`nav` 1、`wbi/view` 1、`playurl` 1；封面 4（1 張 30 秒逾時） | `cloudsearch/pc` 1、`player/url/v1` 2；封面 4 | `sw.js_data` 1、`config` 1、`search` 1、`player` 3；封面 15 |
| 3. 登入 | — | `qrcode/generate` 2、`qrcode/poll` 91、`nav` 1 | `qrcode/unikey` 1、`qrcode/client/login` 10、`account/get` 1；頭像 1 | `account/account_menu` 1；頭像 1 |
| 3. 帶憑證的搜尋（關鍵字 `lemon`） | — | `search/type` 2（帶憑證） | `cloudsearch/pc` 1（帶憑證） | `search` 1（帶憑證）；關掉開關後 `search` 1（不帶）；封面 11 |
| 4. 重啟 | — | `cookie/info` 1（啟動刷新） | — | — |
| 5. 停用、跳過、檢查更新 | `index.json` 3 | 佇列準備：`search/type` 1；跳過後接著播：`wbi/view` 1、`playurl` 1（帶憑證）；封面 4 | 佇列準備：`cloudsearch/pc` 1（帶憑證） | — |
| 6. 登出、移除 | — | — | — | — |
| 7. 失效（重播） | — | 重啟時 `cookie/info` 1 | — | — |

- 第 5 步停用之後，log 沒有任何網易的請求。

### 逐步

| 步驟 | 結果 |
|---|---|
| 1. 清資料 → 引導裝三個官方插件 | 通過：引導列出 Bilibili 1.2.1、網易雲音樂 1.2.0、YouTube 1.0.0，預設全選；FMP 自己的確認框列出能力與會連的網域 |
| 2. 三個音源各搜尋、播一首 | 通過：三首都 `Track audible`。網易《Lemon》匿名時 `Unavailable: membership`（提示需要會員，照設計），改播翻唱版（320 kbps）。YouTube 交接：佇列兩首 YouTube，`Look-ahead prepared` → `Look-ahead handover {end: completed}` → `Track audible {sinceHandoverMs: 111}` |
| 3. 登入 | B 站 QR、網易 QR、YouTube 網頁登入後 `accounts.status` 都是 `active`；三個音源各一次帶憑證的搜尋；YouTube 關掉「以登入身分瀏覽與播放」後 `youtube|0`，搜尋不帶憑證。網易試聽片段：同一個黑膠 VIP 帳號，沒測 |
| 4. 重啟 | 三個帳號仍是 `active`；B 站啟動刷新一次，`last_refresh_result = unchanged` |
| 5. 停用網易 → 啟用；檢查更新 | `netease|0`，搜尋頁的 chip 消失。佇列（YouTube 兩首 → 網易《Lemon》 → B 站一首）裡網易那首的副標是「音源已停用」；在第二首按下一首：`Stream resolution failed {pluginId: netease}` → `Track skipped`，提示「已跳過「Lemon」：音源已停用」，接著播 B 站那首。重新啟用 `netease|1`；「檢查更新」顯示「插件都是最新版本」 |
| 6. 登出 YouTube；移除網易 | **登出**：確認框「FMP 裡這個音源的登入資料會刪除。「以登入身分瀏覽與播放」的設定會保留。」；帳號列刪除，`youtube|0` 保留；WebView2 的 `Cookies` 從 57 個（`.google.com` 17、`.google.com.tw` 10、`.youtube.com` 23、`accounts.google.com` 7；其中登入用的 13 個）變成 0 個。**移除**：確認框「插件與它的資料、登入、快取都會刪除。曲目會保留，顯示「音源未安裝」。」；帳號列、`installed_plugins` 列、快取 48 項都不在（`plugin_storage` 本來是 0 筆）；歷史 1 筆、佇列 1 筆保留，歷史頁顯示「音源未安裝 · 19:17」。secure storage 在 Windows 是加密的單一檔案，看不到鍵名，沒有逐鍵確認 |
| 7. 失效（重播） | `fmp-test` QR 登入 → `active`。`expired`：`Credentials refreshed`、`last_refresh_result = refreshed`，搜尋成功；`expired-hard`：`invalidated`（`failed`），搜尋頁「搜尋失敗」加「重試」，警告提示「FMP Test Plugin的登入已失效」附「登入」 |
| 8. 離線 | **沒有實機**：要停用網卡或加防火牆規則，會影響整台電腦（照 M2 驗收時擁有者的決定略過）。以 widget 測試為證：`plugins_page_test.dart` 的 `offline (…): the shared offline state…`、`accounts_section_test.dart` 的 `offline: the section works, a login is still sent and a…`；Android 第 8 步已實測 |

- 第 2 步 YouTube 播放中 buffering 了 32 次，播放引擎記了 3 次 `tcp: ffurl_read`，同時 B 站一張封面 30 秒逾時：擁有者確認當時電腦上 Docker 的下載佔滿了網路，不是 FMP 的問題。
- 操作時有一次點擊落在 FMP Dev 視窗外（舊的點擊腳本沒帶座標，點到螢幕 (0,0)，當時前景是 Orca）：沒有開出選單、前景沒變。之後的點擊都經過只在 FMP Dev 視窗內才點的腳本。

## 發現與處理

1. **停用或移除音源後，它已準備好的前瞻仍會播出**（Android 第 5 步，10-10）：已備好的串流網址與前瞻不經插件，停用後照播。修正 #232（已合併）：插件清單一改就放掉已消失插件的前瞻，單曲循環下一圈準備前也查插件。重驗見上表第 5 步。停用時正在播的那首照播完（擁有者決定）。
2. **佇列與歷史沒有標「音源已停用」「音源未安裝」，跳過提示是通用訊息**（Android 第 5 步，10-13）：ADR 0030 §決定 7 的「標示」原本只做到曲目詳情；跳過提示是 `Unsupported` 的「Something went wrong.」。擁有者選補程式：#234（已合併）。兩平台重驗見各自的第 5、6 步。
3. **Android 的暫停媒體鍵在已暫停時會開始播放**（M2 範圍，不擋 M3a）：#233。
4. **B 站錯誤對應表只有部分測試**（ADR 測試對照）：fmp-plugins#9（已合併，1.2.1）。
5. **磁碟音訊快取**（擁有者在驗收時提出）：現在音訊只在播放引擎的記憶體裡緩衝（ExoPlayer 往前約 50 秒；mpv 的記憶體快取），換歌、重開就丟，重播同一首要重新下載。擁有者想要 Spotify 那種邊聽邊存到磁碟的快取。ADR 0016 把「邊聽邊存」列為凍結期後的新功能，要新 ADR，不擋 M3a。
