# B 站插件的實作紀錄（M1 PR 9c）

- 日期：2026-09-30
- 環境：Flutter 3.47.5（Dart 3.13.4）、Windows 11；插件在 `<fmp-plugins>\bilibili\`
  （`1morr/fmp-plugins`，分支 `feat/bilibili`）。
- 規格：舊專案 `lib/data/sources/bilibili_source.dart`、`bilibili_exception.dart`、
  `source_http_policy.dart`、`base_source.dart` 的 `AudioStreamConfig`。

## 1. 舊專案 → JS 的對照

| 舊專案 | 插件（`bilibili.js`） | 差異 |
|---|---|---|
| `search`：`/x/web-interface/search/type`，`search_type=video`、`page_size=20`、`order` | `search`：同一支、同參數，`order=totalrank`（`SearchQuery` 沒有排序） | 沒有 `bvid` 的結果（課堂）略過，舊版會留下 `sourceId` 空字串的曲目 |
| `_cleanHtmlTags`、`_parseDuration`、`_fixImageUrl` | `cleanHtml`、`colonDurationMs`、`artwork` | 讀不懂的時長是 `null`（舊版 0）；封面只收 `hdslb.com` 的 https |
| `hasMore: page * pageSize < numResults` | 同 | — |
| `_generateBuvid3/4`、`_buildBrowserCookie`：每次建構時亂數 | `anonymousCookie`：第一次亂數、存 `storage` 的 `anonymousIdentity`，之後沿用 | 跨重啟同一個匿名身分（prd「匿名 buvid 存在插件自己的 storage」） |
| `SourceHttpPolicy.apiHeaders(bilibili)`、`bilibiliSearchApiHeaders` | `API_HEADERS`、`SEARCH_HEADERS`（Referer、Origin、Accept、UA Chrome 122、搜尋另加 Accept-Language） | Cookie 由 `get` 每次附上 |
| `mediaHeaders(bilibili)`：Referer（無結尾斜線）＋ UA Chrome 120 | `MEDIA_HEADERS` | 不帶 Cookie（ADR 0012） |
| `_getCid`：`/x/web-interface/wbi/view`，**不簽名** | `cidOf`：同一支，**WBI 簽名**（`wbiSign`，md5 用 `fmp.crypto.md5`） | 見 §2 |
| — | `wbiKeys`：`/x/web-interface/nav` 的 `wbi_img`，存 `storage` 的 `wbiKeys`，北京時間換日重取 | 新增 |
| `streamPriority`：audioOnly → muxed → hls | DASH → durl | Bilibili 沒有 hls |
| `_tryGetDashStream`：`fnval=16&qn=0&fourk=1`，依頻寬排序後依音質等級挑**一個** | `dashCandidates`：同參數，**全部**依頻寬由高到低，每軌主網址在前、備用在後 | 挑選交給宿主（`StreamResult` 是排好序的候選清單）；以 `formats` 過濾 |
| `_tryGetDurlStream`：`fnval=0&qn=120`，第一段，container `flv`、codec `null` | `durlCandidates`：同參數，第一段；container 看 `data.format`（`flv`／`mp4`），codec 寫 `aac` | 要能以 `formats` 比對，混流的音訊是 aac |
| `getAlternativeAudioStream`（`failedUrl` 換備用網址） | 備用網址直接列為後面的候選 | 不需要另一個能力 |
| `_expiryFromUrl`：`deadline`，沒有就 2 小時 | `expiresAt`：`deadline`，或 Akamai 的 `hdnts=exp=`；都沒有是 `null` | 不猜 2 小時（DTO：不知道就是 `null`） |
| `_checkResponse`、`BilibiliApiException.kind`、`_handleDioError` | `checkCode`、`businessError`、`statusError`；表見 `bilibili/README.md` § 錯誤對應 | 見 §2 |
| `_shouldAbortStreamFallback`：只有 `unavailable`、`vipRequired` 換下一種流 | `fallsBack`：`NotFound`、`Unavailable` 換下一種 | 舊版的 unavailable（-404、62002）在新版是 `NotFound` |

## 2. 決定

- **WBI 只簽 `wbi/view`**：prd 要 WBI 簽名；舊專案實測（2026-09-15）B 站不驗 `wbi/view` 的簽名，但這支
  是 wbi 端點，簽了才不怕哪天開始驗。搜尋與 `playurl` 留在舊專案實測可用的非 wbi 端點，不改端點
  （改了就沒有舊規格可對）。代價：`resolveStream` 在沒有當天 key 的時候多一個 nav 請求。
- **簽名演算法**以公開文件的範例驗過（img_key `7cd0…077c`、sub_key `4932…ac45` → mixin
  `ea1db124af3c7062474693fa704f4ff8`；`foo=114&bar=514&zab=1919810`、`wts=1702204169` → `w_rid`
  `8f6f2b5b3d485fe1886cec6a0be8c5d4`），在 scratchpad 以 node 離線跑，沒有連網。
- **錯誤對應**照舊專案的分類換到 `AppError`：風控碼與 HTTP 412 → `RateLimited`（舊版 rateLimited）；
  -404、62002 → `NotFound`（舊版 unavailable，但 `Unavailable` 必須有原因，這兩個是「沒有這個稿件」）；
  -10403 → `Unavailable(region)`；-101、-403 → `AuthRequired`（舊版 loginRequired、permissionDenied）；
  -503 → `NetworkError`；其他 → `UnexpectedError`。另加 62004、62012 → `NotFound`，87007、87008 →
  `Unavailable(membership)`，舊專案沒有這幾個碼。nav 沒有 `wbi_img` 時，業務碼不是 0 或 -101（例如
  風控的 -352）照上表對應，其餘才是 `ParseError`（check 階段補上）。
- **`auth: 'userPreference'`**：搜尋、串流解析照 ADR 0012 §決定 2。M1 是 `NoCredentials`，實際不帶。
- **`rateLimit`：併發 2、間隔 300ms**。舊專案 API 沒有限流；舊專案量到匿名一分鐘十餘次就 -352，
  ADR 0013 §決定 4 要每個音源宣告併發與間隔。數字是保守的起點，沒有量測依據。
- **`allowedHosts`**：`api.bilibili.com`（API）、`hdslb.com`（封面）、`bilivideo.com`、
  `upos-hz-mirrorakam.akamaized.net`（這次錄到的兩個 CDN）、`bilivideo.cn`（PCDN
  `*.mcdn.bilivideo.cn`，`app/` 內建的媒體 CDN 遮蔽名單有它，這次沒錄到）。Akamai 只列那一個 host，不列整個
  `akamaized.net`。不在清單的串流網址丟掉並寫 warning（宿主遇到清單外的網址會拒收整個回傳值）。
- **遮蔽追加**（manifest `redaction`）：
  - `keyNames`：`buvid`、`buvid3`、`buvid4`、`buvid_fp`、`_uuid`、`b_nut`、`bili_ticket`（匿名身分與
    B 站的 cookie）、`w_rid`、`wts`（簽名；`wts` 每次不同，遮了重播才對得上）、`hdnts`（Akamai 的
    簽名 token）、`ip_region`、`v_voucher`（風控回應裡的驗證憑據）；
  - `headerNames`：`X-Bili-Metadata-Ip-Region`、`X-Bili-Metadata-Legal-Region`、
    `X-Bili-Gaia-Vvoucher`。
  - `buvid`、`hdnts`、`ip_region`、`X-Bili-Metadata-Ip-Region` 是第一次錄製後逐檔檢查才發現的，見 §4；
    `v_voucher` 與另兩個 header 是 check 階段依回應的 `access-control-expose-headers` 預先補的，
    fixture 裡沒有出現，加了不影響重播。
- **檢查案例**：`search` 用「钢琴」，`minItems: 10`，`nonEmpty` 含 `artwork`；`resolveStream` 用舊專案
  live 測試用的 `BV1xx411c79H`、格式 `mp4`／`aac`，`nonEmpty` 含 `bitrate`（durl 沒有 bitrate，所以
  這條也證明走的是 DASH）。不放 `expiresAt`：fixture 的簽名參數已遮，重播時是 `null`。
- **錄製前的乾跑**：在 scratchpad 以手寫 fixture 跑契約測試：成功路徑、搜尋 -352 → `RateLimited`、
  DASH 為 `null` 時改走 durl（durl 案例因沒有 `bitrate` 而紅，符合預期）。都沒有連網。

## 3. 真實連線（模式：真實）

照 ADR 0027 §決定 2，只經 `record_test.dart` 的錄製入口，兩次，每次 4 個請求、沒有重試，全部 200：

| # | 案例 | 方法 | host | path |
|---|---|---|---|---|
| 1 | search | GET | api.bilibili.com | /x/web-interface/search/type |
| 2 | resolveStream | GET | api.bilibili.com | /x/web-interface/nav |
| 3 | resolveStream | GET | api.bilibili.com | /x/web-interface/wbi/view |
| 4 | resolveStream | GET | api.bilibili.com | /x/player/playurl |

- 第一次（11:16 UTC+8）：錄製與重播都綠，但逐檔檢查發現遮蔽缺口（§4），fixture 作廢、刪除。
- 第二次（11:18 UTC+8）：補了遮蔽名單後重錄，也就是任務允許的那一次重試。錄製與重播都綠。
- 合計 8 個真實請求。沒有 curl、瀏覽器或其他連 B 站的腳本；串流網址本身沒有被請求。
- 沒有遇到風控：搜尋拿到 20 筆（3 筆是課堂、被略過）、`numResults` 1000；playurl 回兩條 DASH 音訊
  （30216、30232，約 66 kbps，`mp4a.40.2`）。

## 4. 遮蔽檢查

第一次錄製的 fixture 有三個缺口（契約執行器的兩道掃描都沒擋，因為當時的名單上沒有這些名稱）：

1. playurl 回應裡每個串流網址都帶 `buvid=<我們送出的 buvid3>`：manifest 的 `buvid3` 以「鍵名結尾」
   比對，蓋不到 `buvid`。
2. Akamai 鏡像的網址帶 `hdnts=exp=…~hmac=…`：內建的 `akamaized.net` 規則（`_bilibiliSigned`）沒有
   `hdnts`。
3. nav 回應的 `data.ip_region` 與回應 header `x-bili-metadata-ip-region` 是錄製者的地區碼。

處理：在 manifest 加上 §2 的四項，先確認新名單會讓第一次的 fixture 在契約測試裡紅（「再遮一次會變」
與「名單上的值不是 `***`」兩種都報），再刪掉它們重錄。沒有手改任何 fixture，所以都沒有
`meta.edited`，之後可以直接重錄。

第二次的 fixture 逐檔看過並 grep：

- 請求的 `cookie` 都是 `***`；URL 的 `wts`、`w_rid` 是 `***`；
- 串流網址沒有 `e`、`deadline`、`upsig`、`uparams`、`trid`、`mid`、`oi`（內建規則拿掉），`buvid`、
  `hdnts` 是 `***`；
- `ip_region` 與 `x-bili-metadata-ip-region` 是 `***`；
- 沒有 SESSDATA、bili_jct、DedeUserID、`infoc` 結尾的 buvid 原值，也沒有 IPv4 位址；
- 留下的 id：UP 主的 `mid`、影片資訊（公開資料）、搜尋的 `seid`、串流網址的 `qn_dyeid`（看起來是
  每次請求的追蹤碼，不是憑證）、各種 trace id header。沒有錄製者的個人資訊。

## 5. PR 8 的後續：不合法的 `Set-Cookie`

兩次錄製的 8 個回應都**沒有** `Set-Cookie`（請求已帶匿名 cookie，B 站不再發）。所以這次觀察不到
「伺服器回不合法的 `Set-Cookie` 時請求變成 `UnexpectedError`」；也沒有任何請求以 `UnexpectedError`
失敗。結論：B 站 M1 用到的四支 API 不會觸發這條路徑，這個問題留著，等遇到會發 cookie 的端點
（例如登入）再看。

## 6. FMP 端發現的問題（沒有修，另開 PR）

1. **內建的 B 站 CDN 遮蔽名單少了 `hdnts`、`buvid`**（`lib/core/redaction/redaction_lists.dart`
   的 `_bilibiliSigned`）。插件的 manifest 已經補上（`keyNames`），而插件載入後名單加在全 App
   共用的 `Redactor` 上，所以現在沒有外洩；但沒載入插件時（例如 Debug 頁看舊 log）不會遮。建議把
   兩者加進 `_bilibiliSigned`，並在 `redactor_test.dart` 加一個 Akamai 鏡像網址的案例。
2. **`Redactor._redactMediaUrl` 只用第一個符合的 `MediaCdn`**（`firstOrNull`）。內建規則先加，所以插件
   的 `mediaCdns` 對 `akamaized.net`、`bilivideo.com` 之類已有內建規則的 host 追加簽名參數時不會生效，
   只能像這次改用 `keyNames`。建議合併所有符合的項目的 `signedQueryParameters`（`signedPath` 取或），
   並補「插件追加的參數在內建 host 上也會遮」的測試。
3. **登入之後插件的 `Cookie` 會被蓋掉**（M3 才會發生，現在沒有 repro）：`_AuthInterceptor` 以
   `options.headers.addAll(headers)` 注入憑證，會整個取代插件送的 `Cookie`（匿名 `buvid3`）。舊專案的
   `_withAuth` 是把兩者合併。做登入時要決定合併還是由插件自己處理。

契約執行器與宿主 API 接 B 站時不需要修正。

## 7. 交接（給 M1 交接段）

- 插件庫：`https://github.com/1morr/fmp-plugins`，本機 `<fmp-plugins>`；B 站插件在
  `bilibili/`（分支 `feat/bilibili`，commit 由主 session 建立）。
- 重播：在 FMP 的 `app/` 內
  `FMP_PLUGIN_DIR=<fmp-plugins>\bilibili flutter test test/plugins/contract/contract_test.dart`
  （4 個測試全綠）。
- dev App 安裝（Windows）：在 `app/` 內
  `flutter run -d windows --dart-entrypoint-args=--fmp-dev-plugin=<fmp-plugins>\bilibili\bilibili.js`，
  或設環境變數 `FMP_DEV_PLUGIN` 指向同一個檔案；身分頁會列出 `bilibili`。這一步（驗收的實機項目）
  還沒做。
