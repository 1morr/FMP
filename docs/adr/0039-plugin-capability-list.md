# 0039 — 第一版的插件能力清單

- 狀態：已採納
- 日期：2026-11-14
- 影響範圍：`app/lib/plugins/`（manifest、插件能力的列舉、契約測試）、`app/plugins/`、`app/lib/domain/`（曲目的欄位）、宿主 API

## 背景

ADR 0038 定了音源用 JS 插件實作、介面依插件宣告的插件能力出現入口，但沒列出有哪些插件能力。M0 只做了搜尋與解析串流。設計稿（`docs/design/`）另外用到分 P、排行榜、曲目資訊、登入、會員狀態、遠端歌單讀寫、歌詞，以及搜尋排序、複製連結、評論、點讚（`docs/design/audit-2026-11-11.md` §3 第 6 項）。宿主 API 在 `app-v2.0.0` 凍結，所以第一版要用的插件能力要在 M1 開工時一次列齊，youtube、netease 插件照同一份清單寫。

## 考慮過的選項

### 選項 A：設計稿用到的每件事都是一個插件能力

排序、複製連結、評論、點讚各自一項。缺點是清單變長，而且排序只是搜尋的一個參數、複製連結只要一個網址，硬拆成插件能力會讓 manifest 宣告一堆只有一個欄位的東西。

### 選項 B：插件能力只收「插件要多做一次請求」的事，其餘改成插件提供的資料

排序變成搜尋的參數，網址、存取等級是曲目的欄位，音源標識放 manifest。清單短，介面一樣能依資料有沒有給決定入口。

## 決定

選 B。第一版的插件能力（manifest 的 `capabilities` 字串）：

| 插件能力 | 做什麼 | 實作的里程碑 |
| --- | --- | --- |
| `search` | 搜尋曲目；可帶排序，排序鍵由宿主定（綜合、最多播放、最新發布），manifest 宣告支援哪幾種 | M0；排序 M1 |
| `resolveStream` | 解析串流；M2 加上列出可用音質與哪些需要會員 | M0；音質 M2 |
| `listParts` | 列出一支影片的分 P | M1 |
| `charts` | 排行榜：一張榜、前 N 名，不需登入 | M1（bilibili）、M1.5 |
| `trackInfo` | 曲目資訊：專輯、發佈日期、播放數、點讚數、評論數、簡介；給不了的欄位不顯示 | M1 |
| `login` | QR、WebView 登入與登出，manifest 宣告支援哪幾種方式 | M2 |
| `membership` | 帳號的會員狀態：等級、到期日 | M2 |
| `readRemotePlaylists` | 列出自己的遠端歌單、讀取遠端歌單的內容（匯入、刷新） | M3 |
| `writeRemotePlaylists` | 遠端寫入：建立遠端歌單、加入曲目、移除曲目 | M3 |
| `lyrics` | 搜尋並取得歌詞 | M4 |

不是插件能力、由插件提供的資料：

- 音源標識（簡稱、顏色、16×16 的符號）：manifest 的欄位，宿主只負責畫（`docs/design/DESIGN.md` §2.4、§4.1）。
- 曲目網址：曲目的選填欄位；有網址才出現「複製連結」與「在瀏覽器開啟」。
- 存取等級：曲目的欄位，M2 做（brief §5.4）。

第一版不做：評論列表、點讚動作（brief §5.1 沒有）。宿主略過不認得的插件能力字串，所以之後加新的插件能力不會弄壞舊版宿主。

每個插件能力的輸入、輸出與 manifest 欄位，由實作它的票定，寫回本檔的〈各插件能力的介面〉。

採用的慣例：插件能力與權限分開宣告、遠端歌單寫入的形狀參考 Spotube v6（`MetadataPlaylistAPI`）；方法全部可選、搜尋類型由插件宣告參考 MusicFree 的 `supportedSearchType`、`getTopLists`（`docs/research/plugin-architectures.md`）。

## 各插件能力的介面

實作的票在這裡補一小節：函式名、輸入、輸出、manifest 多了哪些欄位。

### 音源標識（manifest 的 `mark`，M1 票 06）

不是插件能力，是 manifest 的選填欄位；沒宣告時畫面不畫符號。宿主照宣告畫，Dart 端沒有音源分支。

```json
"mark": {
  "short": "B站",
  "color": "#FB7299",
  "paths": [
    {"pathData": "M5 1.8 6.6 3.9M11 1.8 9.4 3.9", "strokeColor": "#FB7299", "strokeWidth": 1.5},
    {"pathData": "M4.4 3.9h7.2a3 3 0 0 1 3 3v4a3 3 0 0 1-3 3H4.4a3 3 0 0 1-3-3v-4a3 3 0 0 1 3-3z", "fillColor": "#FB7299"}
  ]
}
```

- `short`：簡稱，用在手機搜尋結果與歌單卡副標；全名是 manifest 的 `name`，螢幕閱讀器也讀它。
- `color`：音源色，`#RRGGBB`。
- `paths`：16×16 畫布上由下往上畫的路徑，至少一條。欄位名照 Android VectorDrawable：`pathData` 是 SVG 路徑字串；`fillColor`、`strokeColor` 是 `#RRGGBB`，至少給一個；有 `strokeColor` 就要給正的 `strokeWidth`。線頭與轉角一律圓角。`<rect rx>`、`<circle>` 要改寫成等價的路徑。用 path_parsing 畫，不加 SVG 渲染（ARCHITECTURE〈主要依賴〉）。
- 格式不合時整個插件不載入，和 manifest 其他欄位一樣（2026-11-17 擁有者同意用路徑清單，不另放 SVG 檔）。

### `search` 的曲目封面（M1 票 06）

`PluginTrack` 多一個選填的 `coverUrl`：清單用的封面縮圖網址，http 或 https 的絕對網址，給了別的值整次搜尋算解析失敗。縮圖的尺寸由插件挑，夠 3x 螢幕上 40–52 點的封面用（bilibili 用圖床參數裁成 160 方形 webp，約 2 KB；原圖平均約 450 KB）；播放頁的大圖見下一節。宿主不經網路層直接載入（ARCHITECTURE〈快取〉）。契約測試的 search 案例可以加 `{"covers": true}`，要求每首都有封面。排序、分頁與播放數、網址由票 14 補（見下一節）。（2026-11-17 擁有者同意在票 06 補封面；交出縮圖而不是原圖由協調者定。）

### `search` 的大封面（M1 票 16）

`PluginTrack` 多一個選填的 `coverLargeUrl`：播放頁用的大封面網址，http 或 https 的絕對網址，給了別的值整次搜尋算解析失敗（同 `coverUrl`）。尺寸由插件挑，夠 3x 螢幕上 300–380 點的封面用。沒給時播放頁用 `coverUrl`。Dart 的 `Track` 多 `coverLargeUrl`；`listParts` 的分 P 和 `coverUrl` 一樣沿用父曲目的。宿主不經網路層直接載入，封面色（播放頁背景）也從這張取。佇列的資料庫存它（schema v4），升級前存的佇列沒有。

- bilibili（事實 F23）：同一張原圖加 `@720w_720h_1c.webp`，約 30–40 KB；圖床不會把比原圖小的放大，再大沒有幫助。
- 契約測試：search 案例的 `expect` 可以加 `largeCovers`（每首都有）。（2026-11-19 擁有者同意。）

### `resolveStream` 的 `segmentBase`（M1 票 06b）

回應多一個選填的 `segmentBase`：`{"initialization": "0-836", "indexRange": "837-9432"}`，兩個都是含頭尾的位元組範圍 `<first>-<last>`，命名照 MPEG-DASH 的 `SegmentBase`（`Initialization@range`、`@indexRange`）。串流是單檔 fragmented MP4、而且插件拿得到這兩個範圍時才給；bilibili 照 playurl 的 `SegmentBase`（或 `segment_base`）填，讀不到就不給。宿主收進 `AudioStream.segmentBase`；給了但格式不對，整次解析算解析失敗。Apple 平台的音訊後端用它把串流包成 HLS（ADR 0040），其他平台不看。契約測試的 resolveStream 案例可以加 `{"segmentBase": true}`，要求串流給這兩個範圍。（2026-11-18 擁有者同意 ADR 0040 時一併同意。）

### `search` 的排序、分頁與曲目欄位（M1 票 14）

請求多兩個選填欄位，回應多一個，`PluginTrack` 多兩個：

```ts
interface SearchRequest { query: string; sort?: SearchSort; page?: number }
interface SearchResponse { tracks: PluginTrack[]; isEnd?: boolean }
type SearchSort = 'relevance' | 'viewCount' | 'date';
// PluginTrack 多 playCount?: number、url?: string
```

- `sort`：綜合排序、最多播放、最新發布，名字照 YouTube Data API search.list 的 `order`。宿主只傳 manifest 宣告過的值，沒給就用插件自己的預設。
- `page`：從 1 起，沒給是 1。
- `isEnd`：照 MusicFree 插件搜尋的慣例，true 表示沒有下一頁。沒給當成 true，不分頁的插件不會被一直載入；給了不是 boolean，整次搜尋算解析失敗。
- manifest 選填 `searchSorts`：插件支援哪幾種排序，第一個是預設；沒宣告就不能排序。宿主略過不認得的字串（同 `capabilities`）、去掉重複；宣告了但不是字串陣列，整個插件不載入（同其他欄位）。

```json
"searchSorts": ["relevance", "viewCount", "date"]
```

- `playCount`：播放數，非負整數；`url`：曲目在音源網站上的頁面，http 或 https 的絕對網址（有網址才出現「複製連結」與「在瀏覽器開啟」，見上面〈不是插件能力〉）。給了不合格的值，整次搜尋算解析失敗（同 `coverUrl`）。
- bilibili（事實 F26）：`relevance`、`viewCount`、`date` 對到 `order=totalrank`、`click`、`pubdate`，沒給用 `totalrank`，一律帶 `order`；`page` 照傳；`isEnd` 看回應的 `data.numPages`（頁碼大於等於它）或這頁沒有結果，讀不到 `numPages` 時當成最後一頁；`playCount` 取每筆的 `play`（有限的非負數字才給）；`url` 是 `https://www.bilibili.com/video/<bvid>`。
- 契約測試：search 案例的 `input` 可以加 `sort`（要是 manifest 宣告過的名字）與 `page`（正整數）；`expect` 可以加 `playCounts`、`urls`（每首都有）、`playCountsDescending`（播放數由大到小，驗最多播放的排序）、`more`（`isEnd` 要是 false）。宣告了 `searchSorts` 的插件，聯網冒煙測試多打一次非預設排序的案例。（2026-11-19 擁有者同意。）

### `listParts` 與搜尋結果的分 P 數（M1 票 15）

新插件能力 `listParts`，`PluginTrack` 多一個選填的 `partCount`：

```ts
interface ListPartsRequest { trackId: string }
interface ListPartsResponse { parts: PluginPart[] }
interface PluginPart { id: string; title: string; durationMs?: number; url?: string }
// PluginTrack 多 partCount?: number
```

- `listParts`：列出 `trackId` 所屬影片的全部分 P，依順序；`trackId` 可以是任一分 P 的 id。每個分 P 是一首曲目（GLOSSARY），`id` 格式照 brief §5.3（`<bvid>` 是 P1，`<bvid>?p=<n>` 是第 n 個，n ≥ 2）。
- 宿主轉成曲目時，曲名、時長、網址用分 P 自己的，作者與封面（`coverUrl`、`coverLargeUrl`）沿用傳入的父曲目（同舊版 `VideoPage.toTrack`）；`playCount`、`partCount` 不沿用。`parts` 是空的、`id` 重複、`url` 不是 http 或 https 的絕對網址、型別不對，都算解析失敗（`ParseFailure`，寫 warning）。Dart 端是 `Plugin.listParts(Track parent)`，`parent` 不是這個插件的曲目是程式錯誤（同 `resolveStream`）。
- `partCount`：這首曲目所屬影片的分 P 數，正整數；不知道就不給。大於 1 且插件宣告了 `listParts` 時，畫面標分 P 數、可以展開；給了不合格的值（0、負數、非整數、非數字），整次搜尋算解析失敗（同 `playCount`）。Dart 的 `Track` 多 `partCount`（插件不知道時是 null）。
- bilibili（事實 F21、F27）：`listParts` 打 `x/player/pagelist?bvid=<bvid>`，每筆 `page` 是分 P 序號、`part` 是標題（空字串時用 `P<n>`）、`duration` 是秒（有限的非負數字才給）；網址是 `https://www.bilibili.com/video/<bvid>`，n ≥ 2 加 `?p=<n>`；依 `page` 排序。搜尋結果本身沒有分 P 數，所以 `search` 拿到這頁結果後，每頁最多多打一次批次請求 `x/v3/fav/resource/infos?resources=<aid>:2,...&platform=web`，用回應每筆的 `bvid` 對回 `page` 當 `partCount`。這個請求失敗（任何插件錯誤、HTTP 不是 200、`code` 不是 0、回應形狀不對）或被限流時，搜尋照常回來，只是這頁沒有 `partCount`。
- 契約測試：`checkContract` 的 `listParts` 案例，`input` 是 `{"trackId": "..."}`；契約是列出的分 P 不是空的、含傳入的那首、`id` 不重複、每個都有標題。search 案例的 `expect` 可以加 `partCounts`（每首都有 `partCount`）。聯網冒煙測試照「每個插件能力用第一個案例」涵蓋 `listParts`。（2026-11-19 擁有者同意。）

### `trackInfo`（M1 票 17）

新插件能力 `trackInfo`：

```ts
interface TrackInfoRequest { trackId: string }
interface TrackInfoResponse {
  album?: string;          // 專輯名稱
  publishedAtMs?: number;  // 發佈時間，unix 毫秒
  playCount?: number;      // 播放數
  likeCount?: number;      // 點讚數
  commentCount?: number;   // 評論數
  description?: string;    // 簡介
}
```

- 全部選填：插件給不了就不給，畫面不顯示那一列；宿主把空白的字串當成沒給、去掉頭尾空白。名字照 YouTube Data API `videos` 的 `snippet.publishedAt`、`snippet.description`、`statistics.likeCount`、`statistics.commentCount`；播放數沿用 `search` 的 `playCount`，時間沿用 `expiresAtMs` 的 unix 毫秒。
- 計數要是非負整數、`publishedAtMs` 要是有限的整數、文字要是字串；不合格整次算解析失敗（`ParseFailure`，寫 warning）。
- 時長、網址、分 P 數、作者、封面已經在曲目上，不在這裡重給。manifest 只在 `capabilities` 多一個 `trackInfo`，沒有別的欄位。
- Dart 端是 `Plugin.trackInfo(TrackRef ref)`，回 `TrackInfo`（`domain/`）；`ref` 不是這個插件的曲目是程式錯誤（同 `resolveStream`）。結果只在記憶體（ARCHITECTURE〈快取〉）。
- bilibili（事實 F1）：打 `x/web-interface/wbi/view?bvid=<bvid>`，不簽 WBI；分 P（`<bvid>?p=<n>`）用同一支、回整支影片的資訊。`pubdate`（秒）→ `publishedAtMs`、`stat.view` → `playCount`、`stat.like` → `likeCount`、`stat.reply` → `commentCount`、`desc` → `description`；B 站沒有專輯，不給。
- 契約測試：`trackInfo` 案例的 `input` 是 `{"trackId": "..."}`；形狀由宿主檢查，沒有期望時空的也合格。`expect` 可以加 `stats`（三個計數都有）、`published`、`description`。聯網冒煙測試照「每個插件能力用第一個案例」涵蓋。（2026-11-20 擁有者同意。）

### `charts`（M1 票 18）

新插件能力 `charts`，manifest 多一個 `chartTitle`：

```ts
interface ChartsRequest { limit: number }          // 前 N 名，宿主傳 10
interface ChartsResponse { tracks: PluginTrack[] } // 依名次，第一個是第 1 名
```

```json
"chartTitle": {"en": "Music chart", "zh-TW": "音樂區排行榜", "zh-CN": "音乐区排行榜"}
```

- 一個插件一張榜、不需登入（GLOSSARY〈排行榜〉）。曲目的形狀與驗證規則同 `search` 的 `PluginTrack`（封面、大封面、播放數、分 P 數、網址都選填，給了不合格的值整次算解析失敗）。給多了宿主只取前 `limit` 名；空的、id 重複算解析失敗（`ParseFailure`，寫 warning）。
- `chartTitle`：榜名，語言標籤（BCP 47）對文字，宣告 `charts` 時必填、要有 `en`；宿主照 App 的語言挑，沒有就用 `en`（照 Chrome 擴充的 `default_locale` 退回）。放 manifest 不放回應，因為載入中與失敗時也要顯示榜名（`docs/design/home.html`）。缺 `en`、不是物件或有空的榜名，整個插件不載入（同其他欄位）。
- Dart 端是 `Plugin.charts({int limit = 10})`，回依名次的 `List<Track>`；`PluginManifest.chartTitle(languageTag)` 給榜名。榜存 drift（ARCHITECTURE〈快取〉）。
- bilibili（事實 F28）：打 `x/web-interface/ranking/v2?rid=1003&type=all`（音樂區，舊版用的），不簽 WBI；回 100 筆，取前 `limit`。`owner.name` → 作者、`duration`（秒）→ 時長、`videos` → `partCount`、`stat.view` → `playCount`、`pic` 照 `search` 換成兩種封面、網址是 `https://www.bilibili.com/video/<bvid>`；0 的時長與分 P 數當成沒給。
- 契約測試：`charts` 案例的 `input` 是 `{"limit": 10}`；契約是不是空的、每首屬於這個插件、有 id 與標題（同 `search`）；`expect` 沿用 `search` 的 `covers`、`largeCovers`、`playCounts`、`urls`、`partCounts`。聯網冒煙測試照「每個插件能力用第一個案例」涵蓋。慣例參考 MusicFree 的 `getTopLists`，簡化成一張榜。（2026-11-20 擁有者同意。）

## 後果

- 好的：清單短，插件頁（設計稿的 `plugins.html`）照這份列出支援與不支援；複製連結、排序不用另外宣告。
- 壞的：設計稿的插件頁畫的是 8 項，做插件頁時改成 10 項。
- 之後要注意：加新的插件能力時，在 `PluginCapability` 加一個值、在契約測試的 `checkContract` 補契約，並更新本檔。

## 如何確認

- `test/plugins/plugin_contract_test.dart`：manifest 宣告的每個插件能力都要有 fixture 與契約，`checkContract` 的 switch 在新增插件能力時編譯不過。
- 依賴規則測試：Dart 端不得依音源識別碼分支，入口只看插件能力與資料。
