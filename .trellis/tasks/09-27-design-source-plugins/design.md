# 設計：音源插件化（腳本插件）

採用的慣例：MusicFree、LX Music 的 JS 腳本插件（使用者可安裝的來源）；Spotube 的 manifest 宣告能力與 API 版本、
iOS 以側載發佈；Flutter federated plugin 的「一套介面、多種實作」；Spotube 的匹配結果快取與使用者改選。
參考其他專案只看設計，不複製程式碼（MusicFree 為 AGPL-3.0）。

## 1. 形狀

```mermaid
flowchart TB
  UI[UI 與 service<br/>只認 SourcePlugin 介面與能力宣告] --> REG[插件註冊表]
  REG --> SP1[ScriptSource：bilibili.js]
  REG --> SP2[ScriptSource：netease.js]
  REG --> SP3[ScriptSource：youtube.js<br/>或暫時的 Dart 實作]
  REG --> SP4[ScriptSource：其他來源的腳本]
  IDX[插件庫 index.json<br/>官方 1morr/fmp-plugins 或自訂] -.安裝／更新.-> REG
  subgraph 宿主（App）
    RT[JS 執行環境 flutter_js<br/>QuickJS / JavaScriptCore]
    HOST[宿主 API v1<br/>http、crypto、storage、log、login]
    NET[網路層 ADR 0012／0013]
  end
  SP1 & SP2 & SP3 & SP4 --> RT --> HOST --> NET
```

- **一套介面 `SourcePlugin`**：App 其他部分只認它與能力宣告，分不出來源是哪個、是不是腳本。
- **所有來源都是 JS 腳本，App 不內建任何來源**：可播放音源（B 站、網易、YouTube）、僅元資料來源（Spotify、QQ 匯入）、
  歌詞源（網易、QQ、lrclib）都放在獨立的官方插件庫，由使用者在 App 內安裝（§5）。官方插件與使用者自己的插件走同一條安裝路徑。
- **YouTube 例外的退路**：可行性驗證失敗時，YouTube 暫時以 Dart 實作同一個 `SourcePlugin` 介面；找到解法後換回腳本。
- **腳本引擎**：`flutter_js`（Android／Windows／Linux 用 QuickJS，iOS／macOS 用 JavaScriptCore）。腳本以 ES2020 JS 撰寫；作者可用 TypeScript 再打包。

## 2. manifest（每個腳本一份）

| 欄位 | 說明 |
|---|---|
| `id`、`name`、`version`、`author`、`homepage` | 識別與顯示；`id` 是音源 id（ADR 0001 的字串 id 沿用） |
| `apiVersion` | 宿主 API 版本；不相容時拒絕載入並顯示原因 |
| `capabilities` | 見 §3 |
| `domains` | 允許連線的網域清單；宿主 HTTP 只放行這些 |
| `login` | 支援的登入方式與所需資料（WebView 登入網址與要讀的 cookie 名、QR 流程、貼上 cookie 需要的欄位與說明） |
| `retryPolicy`、`rateLimit` | 重試次數、可重試的錯誤、併發上限、最小請求間隔（ADR 0013） |
| `redaction` | 追加的遮蔽名單：cookie／header／參數名、CDN 網域（ADR 0011） |
| `defaults` | 例如「以登入身分瀏覽與播放」的預設值（ADR 0012） |
| `icon` | 顯示用圖示 |

## 3. 能力

| 能力 | 意思 |
|---|---|
| `search` | 搜尋曲目（可再宣告支援的搜尋類型與排序） |
| `resolveStream` | 由曲目取得可播放的串流（含 headers、到期時間、音質、格式、是否試聽） |
| `trackDetail` | 曲目詳情 |
| `multiPart` | 一個項目含多個分 P（B 站 cid，ADR 0005） |
| `importPlaylist` | 以網址匯入歌單（宣告可處理的網址樣式） |
| `libraryRead` | 讀取使用者的收藏夾與私人歌單（需登入） |
| `libraryWrite` | 建立歌單、加入／移除曲目（需登入） |
| `charts` | 排行／探索 |
| `live` | 直播／電台（開播狀態、直播串流） |
| `mix` | 推薦或無限播放佇列 |
| `lyrics` | 搜尋歌詞候選、取得歌詞（逐字／逐行時間軸、翻譯） |
| `login` | 由 manifest 的 `login` 欄位宣告方式 |

- 可播放音源：有 `resolveStream`。僅元資料來源：有 `search` 或 `importPlaylist` 但沒有 `resolveStream`。歌詞源：只有 `lyrics`。不另立型別。
- 下載不是插件能力：凡是 `resolveStream` 回傳可下載格式的，下載由宿主處理（第 11 項）。
- UI 依能力顯示入口；同一個能力由多個來源提供時（例如搜尋、排行），UI 列出所有提供者，不寫死任何一個。

## 4. 宿主 API v1（腳本能用的全部）

| API | 說明 |
|---|---|
| `http.request` | 經網路層發出（ADR 0012／0013）：帶 `authRequirement`、只能連 manifest 的網域、統一重試與限流、網路紀錄與遮蔽；回傳狀態、headers、body |
| `crypto` | MD5、SHA、HMAC、AES（CBC／ECB）、RSA、Base64 等，涵蓋網易 weapi／eapi 與 B 站 WBI 所需 |
| `storage` | 每個插件自己的鍵值儲存（非機密，例如 WBI 金鑰快取、匿名 `buvid`） |
| `credentials` | 只能讀自己音源的憑證欄位（例如 B 站寫入需要的 `bili_jct`）；不能讀其他音源 |
| `log` | 經 log 門面（ADR 0011），tag 為插件 id |
| `errors` | 腳本丟出 `{ category, code, message, retryAfter }`，宿主轉成 `AppError`（ADR 0013）；分類對應表寫在腳本裡 |

沒有檔案系統、沒有任意 socket、沒有其他插件的資料。資料交換一律是 JSON DTO（曲目、歌單、串流結果、歌詞候選…），
以 `apiVersion` 版本化；宿主提供 TypeScript 型別定義檔。

## 5. 插件庫、安裝與信任

採用的慣例：MusicFree 的「訂閱」插件來源、LX Music 的自訂源匯入（App 本體不附音源）。

- **官方插件庫是另一個 repo**（`1morr/fmp-plugins`）：每個插件一個目錄（腳本＋manifest＋錄下的測試 fixture）；
  它自己的 CI 跑每個插件的契約測試，並產生 `index.json`（id、名稱、版本、`apiVersion`、能力、網域、下載網址、SHA-256）。
  主 repo 只放播放器本體，測試用假插件與錄下的回應。
- **插件頁**：預設讀官方 index；可加入其他 index 網址；也可從檔案或單一網址安裝。
- **安裝前顯示** manifest：名稱、作者、來自哪個插件庫、能力、**會連的網域**，並警告「此腳本會以你的登入身分存取這些網站」。
  由 index 安裝時以 SHA-256 驗證檔案。
- **更新**：不在背景定時檢查；打開插件頁或手動「檢查更新」時比對 index，可一鍵全部更新。音源壞掉時更新插件即可，不必發 App 新版。
- **首次啟動**：沒有任何來源時顯示引導，列出官方插件，勾選後一鍵安裝。
- **舊版升級**：legacy import 不依賴插件；匯入時偵測舊資料用到的音源（B 站、YouTube、網易），提示一鍵安裝對應的官方插件；
  未安裝前這些曲目標示「音源未安裝」。
- **停用與移除**：移除時一併清除該插件的 storage 與憑證；已存在的曲目保留並標示「音源未安裝」。
- Debug 頁提供「音源健康檢查」：對每個已安裝插件跑一組基本呼叫（第 4、8 項）。
- 法律面：App 本體不含呼叫非官方 API 的程式碼，降低主 repo 的暴露面，但不消除風險（B 站社群 API 文件庫已於 2026-01 因存證信函關閉，`research/login-methods.md` §0）。

## 6. 匹配流程（宿主統一）

- **一份共用評分核心**：標題、歌手（正規化後的相似度）、時長（容差內加分）、歌詞時另加同步歌詞加分。歌單匯入與歌詞都用它，不再各有一套。
- **跨來源比較**：對所有啟用的目標來源同時搜尋，取分數最高者，不在第一個命中時就停；分數相同依使用者排序的來源優先序。
- **目標來源集合**：由使用者設定（啟用的可播放來源與順序）；自動匹配與手動重搜用同一個集合。
- **使用者可改選**：匹配結果持久化；使用者改選後標為手動，之後不再自動重算。
- **匹配失敗**：保留該項目並標示「未匹配」，可手動搜尋；不靜默丟棄。

## 7. 對其他 ADR 的影響

- ADR 0008「搬運葉節點邏輯」：音源邏輯改為**以舊 Dart 程式碼為規格、用 JS 重寫**；非音源的葉節點（`TrackKey` 格式等）仍照搬。ADR 0008 加註。
- 第 8 項：契約測試要能對腳本插件以錄下的 HTTP 回應重播執行；插件作者也能在本機跑。

## 8. 第一個里程碑與可行性驗證

- 第一個里程碑的 tracer bullet 用一個腳本音源（哪一個在里程碑規劃時定）完成搜尋與播放，同時建立 JS 執行環境、宿主 API 的最小集合、腳本契約測試的雛形。
  插件庫 repo 與插件頁可在後續里程碑建立；第一個里程碑以「從檔案安裝」載入腳本即可。
- **YouTube 可行性驗證（有時限）**：YouTube.js（MIT，官方只寫支援 Node.js、Deno、瀏覽器）在 `flutter_js` 裡能否搜尋並解出可播放串流；它需要宿主提供 `fetch` 與 eval。時限內失敗則 YouTube 暫以 Dart 實作。
- `flutter_js` 在 Android 與 Windows 上的非同步（Promise）、記憶體與啟動成本實測。
