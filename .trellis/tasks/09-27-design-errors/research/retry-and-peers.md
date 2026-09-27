# 統一錯誤模型前置研究（二）：重試／退避與同類專案比較

本檔涵蓋研究項目 4–6：指數退避與 jitter、Dart 重試套件與 dio 攔截器重試模式、`Retry-After`
標頭、並發上限與 token bucket、不該重試的情況；同類開源客戶端（Spotube、Finamp、NewPipe）如何
分類「自動恢復／提示使用者／只記錄」；風控驗證（B 站 -352/-412、`v_voucher`、geetest）與地區
限制（YouTube「確認你不是機器人」、年齡／地區限制）的常見處理方式，含 NewPipe 與 yt-dlp 的分類。
查證方式與標記規則同研究一。

## 4. 重試與退避

### 4.1 指數退避與 jitter：AWS 官方部落格與可執行原始碼

來源：<https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/>（官方部落格，
四種公式以圖片呈現、頁面文字無法直接擷取數學式，已改用其連結的參考實作確認）；
<https://github.com/awslabs/aws-arch-backoff-simulator>
（`awslabs` 官方帳號下的模擬器倉庫，`src/backoff_simulator.py`，已直接讀取原始碼確認）。

確認的四種公式（逐字取自官方模擬器原始碼）：

```python
class Backoff:
    def __init__(self, base, cap):
        self.base = base
        self.cap = cap
    def expo(self, n):
        return min(self.cap, pow(2, n) * self.base)

class ExpoBackoff(Backoff):          # 無 jitter：純指數
    def backoff(self, n):
        return self.expo(n)

class ExpoBackoffEqualJitter(Backoff):   # Equal Jitter：一半固定 + 一半隨機
    def backoff(self, n):
        v = self.expo(n)
        return v / 2 + random.uniform(0, v / 2)

class ExpoBackoffFullJitter(Backoff):    # Full Jitter：整個區間隨機
    def backoff(self, n):
        v = self.expo(n)
        return random.uniform(0, v)

class ExpoBackoffDecorr(Backoff):        # Decorrelated Jitter：以上一次結果為基礎
    def __init__(self, base, cap):
        Backoff.__init__(self, base, cap)
        self.sleep = self.base
    def backoff(self, n):
        self.sleep = min(self.cap, random.uniform(self.base, self.sleep * 3))
        return self.sleep
```

AWS 部落格原文的結論（文字部分可讀取確認）：**Full Jitter** 與 **Decorrelated Jitter** 的模擬
結果最好（在高併發重試下完成總時間最短、對後端造成的請求尖峰最小），純指數退避（無 jitter）
在多個 client 同時重試時會造成「雷鳴群聚」（thundering herd），Equal Jitter 介於兩者之間。
**建議（推測，供 FMP 設計參考）**：新設計優先選 Full Jitter（實作最簡單、`random.uniform(0,
v)`）或 Decorrelated Jitter（需要保留上一次的 sleep 值當狀態）；純指數或無 jitter 不建議用於
多裝置／多分頁可能同時對同一音源退避的情境。

### 4.2 Dart 重試套件現況

**`retry`（google/dart-neats）**——來源：<https://pub.dev/packages/retry>（pub.dev API 確認最新版
`3.1.2`，發布於 `2023-05-16T14:26:11Z`）；原始碼
<https://github.com/google/dart-neats/blob/master/retry/lib/retry.dart>（直接讀取確認）。

```dart
final class RetryOptions {
  final Duration delayFactor;       // 預設 200ms
  final double randomizationFactor; // 預設 0.25（±25%）
  final Duration maxDelay;          // 預設 30s
  final int maxAttempts;            // 預設 8

  const RetryOptions({
    this.delayFactor = const Duration(milliseconds: 200),
    this.randomizationFactor = 0.25,
    this.maxDelay = const Duration(seconds: 30),
    this.maxAttempts = 8,
  });
}
```

延遲公式為 `pow(2, attempt) * delayFactor`，再乘上 `(1 ± randomizationFactor)` 的隨機係數；預設
排程約為 400ms、800ms、1600ms、3200ms、6400ms、12800ms、25600ms（各自再 ±25%），共 8 次嘗試、
7 次等待。**這個 jitter 風格是「在指數值附近 ±25% 隨機」，跟 AWS 四種公式都不完全相同**（不是
Equal Jitter 的「一半固定一半隨機」，也不是 Full Jitter 的「整個區間隨機」）——是第三種變體，
選用時不要跟 AWS 的兩個名稱混用。**現況：距今 3 年多沒有新版，屬於停滯但功能單純、程式碼量小
（單檔）的套件，停滯風險相對低**（推測：功能單純代表也不太需要維護）。

**`dio_smart_retry`**——來源：<https://pub.dev/packages/dio_smart_retry>（pub.dev API 確認最新版
`7.0.1`，發布於 `2024-10-22T03:40:02Z`）；原始碼
<https://github.com/rodion-m/dio_smart_retry>（`retry_interceptor.dart`、
`http_status_codes.dart` 已直接讀取確認）。

確認的預設可重試狀態碼集合（逐字取自 `default_retry_evaluator.dart`／`http_status_codes.dart`）：

```dart
const defaultRetryableStatuses = <int>{
  status408RequestTimeout, status429TooManyRequests,
  status500InternalServerError, status502BadGateway,
  status503ServiceUnavailable, status504GatewayTimeout,
  status440LoginTimeout, status499ClientClosedRequest, status460ClientClosedRequest,
  status598NetworkReadTimeoutError, status599NetworkConnectTimeoutError,
  status520WebServerReturnedUnknownError, status521WebServerIsDown,
  status522ConnectionTimedOut, status523OriginIsUnreachable,
  status524TimeoutOccurred, status525SSLHandshakeFailed, status527RailgunError,
};
```

值得注意這組集合混入了非標準／CDN 專屬碼（IIS 440、nginx 499、AWS ELB 460、Cloudflare
520–527），但不含 501、505–511、526。**確認：`dio_smart_retry` 完全不支援解析 HTTP
`Retry-After` 標頭**——已直接讀原始碼確認package 內沒有任何處理該標頭的程式碼，另用
`gh api "search/code?q=retry-after+repo:rodion-m/dio_smart_retry"` 搜尋整個倉庫也是零筆命中。
**對 FMP 的啟示**：若音源（尤其 B 站限流）會回 `Retry-After`，不能直接依賴
`dio_smart_retry`，需要自己在攔截器裡讀該標頭並覆寫等待時間，或整個重試邏輯自己寫（ADR 0012
本來就要求「限流與退避策略由音源宣告」，代表本來就不是套用一個套件的預設值就能滿足）。

### 4.3 `Retry-After` 標頭處理（推測性設計建議）

未找到 Dart 生態圈中「開箱即用、正確解析 `Retry-After`（可能是秒數或 HTTP-date 兩種格式）」的
現成攔截器套件（標**查不到現成套件**）。標頭本身的格式定義屬於 HTTP 規範
（RFC 9110 §10.2.3，非本次逐字查證重點，僅供 FMP 實作時對照）：值可以是整數秒數，也可以是
HTTP-date 字串。**建議（推測）**：FMP 若要支援它，需自行在音源的錯誤對應攔截器中讀取此標頭、
解析兩種格式、把結果轉成「retry-after 等待時間」欄位放進統一錯誤型別（見研究一第 3.5
節），而不是交給任何現成重試套件的預設行為。

### 4.4 並發上限與 token bucket

**`pool`（dart-lang/tools，Dart 團隊官方套件）**——來源：<https://pub.dev/packages/pool>（pub.dev
API 確認最新版 `1.5.3`，發布於 `2026-08-28T20:42:37Z`，非常新，代表持續在維護）。`pool` 提供
`Pool(maxAllocatedResources)` 語意，可以直接當作「每音源／每主機並發上限」的號誌
（semaphore）：`final resource = await pool.request(); ... resource.release();` 或
`pool.withResource(() => ...)`。**建議（推測）**：優先用這個現成、官方維護的套件實作「每 host
並發上限」，不需要自己寫號誌；token bucket（限制「單位時間內請求數」而非「同時並發數」）則
`pool` 本身不直接提供，若音源需要的是速率限制（而非並發上限），需要另外實作簡單的 token
bucket 或改用固定視窗計數器（本次未找到官方／pub.dev 上維護中、對應此需求的現成 Dart 套件，標
**查不到現成套件**，屬於自己寫的範圍，符合 CLAUDE.md「專案已有依賴 → 成熟套件 → 自己寫」的
優先序最後一級）。

### 4.5 什麼情況不該重試

- **HTTP 方法冪等性**——來源：<https://developer.mozilla.org/en-US/docs/Glossary/Idempotent>
  （MDN，官方詞彙表）。確認冪等方法：GET、HEAD、OPTIONS、TRACE、PUT、DELETE；**非冪等**：POST、
  PATCH、CONNECT。定義原文：「the intended effect on the server of making a single request is
  the same as the effect of making several identical requests」。MDN 特別註明這是「意圖」而非
  伺服器強制保證，且冪等不代表回應內容每次相同（例如 DELETE 重送可能第二次回 404）。
  **對 FMP 的啟示**：非冪等請求（例如「寫入遠端歌單」這類 `AuthRequirement.required` 的 POST
  請求，見 ADR 0012）預設不自動重試，除非該端點本身具備冪等保證（例如帶了去重用的
  idempotency key）；純讀取（串流解析、搜尋、詳情）是 GET，可以安全重試。
- **4xx 語意**（綜合 `dio_smart_retry` 預設集合與一般 HTTP 慣例，推測歸納，非單一權威來源）：
  `dio_smart_retry` 的預設可重試集合裡幾乎不含標準 4xx（只有 408 Request Timeout、429 Too Many
  Requests 兩個是 4xx，其餘都是 5xx 或 CDN 專屬碼）——即業界慣例是「4xx 代表請求本身有問題
  （認證、參數、權限），重送同一個請求不會有不同結果，除非狀態改變（例如 401 先刷新憑證再重
  送，或 429/408 等等一下再送）」。**對 FMP 的啟示**：統一錯誤型別裡的「需登入／憑證過期」與
  「找不到」（通常對應 401／403／404）預設不該進入通用重試迴圈，而是先分別導向「刷新憑證後重送
  一次」（ADR 0012 已定義的 `QueuedInterceptor` 流程）或「直接回報使用者」；只有「限流」
  （429、Retry-After）與部分網路層錯誤（連線逾時、5xx）才進入退避重試。
- **Riverpod 3 的 `Error`／`ProviderException` 不重試**——見研究一第 2.2 節，這是另一層（provider
  初始化層級）的「不重試」規則，跟 dio 攔截器層级的規則是互補而非重複。

## 5. 同類開源客戶端如何分類「自動恢復／提示使用者／只記錄」

### 5.1 NewPipe：三層升級式 UI 呈現 + 獨立分類欄位

來源：
<https://github.com/TeamNewPipe/NewPipe/blob/dev/app/src/main/java/org/schabi/newpipe/error/ErrorUtil.kt>
（直接讀取原始碼確認）。NewPipe 用同一個 `ErrorInfo`（研究一第 3.2 節）餵給三種呈現方式，依
情境選擇：

1. **`showSnackbar`**——非致命、當下有可見的 root view 時的預設做法（例如某個縮圖載入失敗）。
2. **`createNotification`**——背景 service 執行中，或沒有 root view 可用時；因為系統通知本身是
   靜默的，程式碼裡同時會補跳一個 `Toast`，確保使用者當下有機會看到。
3. **`ErrorActivity`／`openActivity`**——只在「前景 activity 開著、且錯誤嚴重到必須中斷」時
   才使用，是最後手段，會整頁顯示錯誤詳情並提供回報功能。

`isReportable` 欄位（見研究一）額外控制「要不要提供回報按鈕」——即使走同一層 UI 呈現，
「已知的、可預期的來源限制」（如地區限制、需要登入）通常 `isReportable = false`（不需要使用者
回報成 bug），而未分類的例外預設 `isReportable = true`。**歸納（推測）**：NewPipe 的「自動恢復」
並非由這個錯誤呈現系統處理，而是分散在各個呼叫點自行判斷（例如串流解析失敗時嘗試下一個可用
的串流來源）——`ErrorInfo`／`ErrorUtil` 本身只負責「呈現」與「是否可回報」，不負責「重試」，
重試邏輯在更上層（各別的 fragment／presenter）依需要各自實作。

### 5.2 Finamp：型別比對 + 訊息關鍵字過濾 + 去重

來源：
<https://raw.githubusercontent.com/finamp-app/finamp/redesign/lib/components/global_snackbar.dart>
（注意：Finamp 預設分支是 `redesign` 不是 `main`，已用 `gh api repos/finamp-app/finamp --jq
.default_branch` 確認後直接讀取原始碼）。單一靜態入口 `GlobalSnackbar.error(dynamic event)`，
依「執行期型別＋訊息內容」分流，**沒有** sealed 錯誤型別：

- **只記錄、完全不顯示 UI**（呼叫 `_logger.info(...)` 後直接 `return`）：訊息內容符合
  `"Failed host lookup"`、`"HTTP connection timed out"`、任何 `TimeoutException`、
  `"Could not fetch the response for GET"` 的網路類錯誤——這些被視為「暫時性、使用者不需要每次
  都看到」的雜訊。
- **顯示給使用者**：其餘所有情況——彈出通用的「發生錯誤」SnackBar，並附「更多」按鈕開啟
  `AlertDialog` 顯示完整錯誤文字；其中 HTTP `401` 會額外對應到專屬的在地化字串
  （`responseError401`），其餘狀態碼共用通用字串（`responseError`）。
- **去重**：用 `"network:$statusCode:$底層例外執行期型別"`（或非 Response 例外的
  `"network:$執行期型別"`）當 key，記在 `_activeErrorKeys` 集合裡；只要對應的 SnackBar 還沒
  關閉，同一個 key 的錯誤不會重複彈出，SnackBar 的 `closed` future resolve 後才從集合移除。
- **沒有內建重試動作**：SnackBar 本身不附「重試」按鈕，恢復與否交給使用者手動操作
  （例如下拉重整）。

**對 FMP 的啟示**：Finamp 這種「用字串比對訊息內容來分流」的做法，正是統一錯誤型別要解決的
問題本身——用 `sealed class` 取代字串比對，才能在編譯期保證涵蓋所有分類，也才能讓「網路類錯誤
只記錄不顯示」這種規則寫成對 `NetworkError` 型別的一個 `case`，而不是一串脆弱的字串前綴比對。
去重機制（用「分類＋來源」當 key 抑制短時間內重複提示）是值得直接借鏡的模式。

### 5.3 Spotube

本次僅有先前（compaction 前）從 GitHub issue 討論串取得的間接證據（例如錯誤訊息以 stack
trace 形式出現在使用者回報中），未能直接確認 Spotube 目前版本實際的錯誤呈現／Toast 機制原始碼
位置與邏輯。**標記：查不到**（Spotube 使用 Riverpod + Riverpod 的 `AsyncValue` 錯誤模式，但
「自動恢復／提示／只記錄」三分法在其程式碼庫的具體實作細節，本次未能在時間內定位到對應檔案並
直接讀取確認，不列入具引用力的結論，僅供owner知悉此為未覆蓋的比較對象）。

### 5.4 三分法歸納（綜合本節，供 FMP 設計參考，推測）

| 分類 | NewPipe 對應 | Finamp 對應 | FMP 建議方向（推測） |
|---|---|---|---|
| 自動恢復（不打擾使用者） | 呼叫點自行 fallback（換一個串流來源），不經統一呈現層 | 無明顯對應（無自動 fallback 機制） | 限流／暫時性網路錯誤且 `retryable=true`：由重試層處理，只在多次重試後仍失敗才升級成提示 |
| 提示使用者 | `showSnackbar`／`createNotification`／`ErrorActivity`（依情境三選一） | 通用 SnackBar + 詳情 Dialog，401 有專屬文案 | 需登入／風控驗證／地區限制／不支援：這些使用者能採取行動（重新登入、完成驗證、知道不支援）的分類應提示 |
| 只記錄 | `isReportable=false` 時不強調回報，但仍走同一套 UI 呈現（NewPipe 沒有「完全不顯示」這一級） | 特定網路錯誤訊息完全不顯示，只 log | 找不到（單一項目層級的 404，不影響整體操作）、解析失敗但有 fallback 可用時：只記錄，避免每次列表捲動都跳提示 |

## 6. 風控驗證與地區限制

### 6.1 Bilibili：`-352`／`-412`／`v_voucher`／geetest

**直接原始碼證據（PiliPlus，`bggRGjQaUbCoE/PiliPlus`）**：

- `lib/http/error_msg.dart`（grep 確認）：`const errorMsg = {-352: '风控校验失败，请检查登录
  状态'};`——**沒有** `-412` 的對應項（間接印證下方「`-412` 回應是 HTML 不是 JSON code」的說法，
  因為若是 JSON code 就會列在這張表裡）。
- `lib/http/validate.dart`（直接讀取完整原始碼確認）——實作了 `v_voucher` 的兩段式驗證流程：

  ```dart
  abstract final class ValidateHttp {
    static Future<LoadingState<Map?>> gaiaVgateRegister(String vVoucher) async {
      final res = await Request().post(Api.gaiaVgateRegister,
        queryParameters: {if (Accounts.main.isLogin) 'csrf': Accounts.main.csrf},
        data: {'v_voucher': vVoucher},
        options: Options(contentType: Headers.formUrlEncodedContentType));
      if (res.data['code'] == 0) return Success(res.data['data']);
      else return Error(res.data['message']);
    }

    static Future<LoadingState<Map?>> gaiaVgateValidate({
      required dynamic challenge, required dynamic seccode,
      required dynamic token, required dynamic validate,
    }) async {
      final res = await Request().post(Api.gaiaVgateValidate,
        queryParameters: {if (Accounts.main.isLogin) 'csrf': Accounts.main.csrf},
        data: {'challenge': challenge, 'seccode': seccode, 'token': token, 'validate': validate});
      if (res.data['code'] == 0) return Success(res.data['data']);
      else return Error(res.data['message']);
    }
  }
  ```

  即：先呼叫 `register` 帶 `v_voucher`拿到 `token`／`challenge`，交給使用者完成 geetest
  （`lib/pages/login/geetest/geetest_webview_dialog.dart`，本次僅確認檔案存在、未逐行讀取細節，
  標**部分查不到**：geetest WebView 對話框的具體互動細節未展開），拿到 `validate`／`seccode`
  後呼叫 `validate` 完成驗證。

**間接證據（社群文件，非直接讀取確認，標為 推測／間接來源）**：`SocialSisterYi
/bilibili-API-collect` 倉庫的 `docs/misc/sign/v_voucher.md`（本次僅透過 WebSearch 綜合結果得知
其存在與大致內容，**未直接開啟該檔案逐字確認**，故標記為間接來源）記載的完整流程：`-352`
回應會帶 `v_voucher`；呼叫 register 端點取得 `token`＋`challenge`；使用者完成 geetest 驗證得到
`validate`＋`seccode`；呼叫 validate 端點換得 `grisk_id`；用 `grisk_id` 組出 `gaia_vtoken`
（URL 參數）與 `x-bili-gaia-vtoken`（cookie）後重送原始請求。此流程與 PiliPlus 的實際程式碼
（上方直接確認）在「register → 使用者完成驗證 → validate」三段式上完全吻合，可視為有直接程式碼
佐證的間接資料。另外社群普遍記載：wbi 簽名的 playurl 請求會多帶 `dm_img_list`／`dm_img_str`／
`dm_cover_img_str`／`dm_img_inter`（模擬螢幕互動軌跡的參數）與 `gaia_source=pre-load`／
`isGaiaAvoided=true` 來降低觸發 `-352` 的機率（本節同樣標記為間接來源，未直接讀取該社群文件
原文確認逐字內容）。

`-412`（間接來源，WebSearch 綜合，**查不到直接讀取到的 PiliPlus 或官方文件原始碼佐證**）：通常
代表 IP／頻率觸發的封鎖，持續數分鐘到數小時；即使帶著有效 cookie 也可能被觸發；回應常是 HTML
錯誤頁而非 JSON，代表偵測邏輯必須先檢查 Content-Type／內容形狀，不能直接假設是 JSON 硬解析；
社群建議是不要對 `-352`／`-412`／`-799` 做激進的自動重試（`-799` 代表另一種頻率限制，本次同樣
僅間接得知,查不到逐字定義來源）。

**對 FMP 的啟示（推測）**：「風控驗證」這個分類的錯誤型別，欄位至少要能承載「驗證用的 URL／
token／challenge」（呼應 NewPipe `ReCaptchaException` 的 `url` 欄位，見研究一第 3.4
節），且必須明確跟「限流」（`-412`、`-799`，只需要等待與退避）分開——ADR 0012
已經要求「每個音源明確列出哪些回應代表憑證無效，網路錯誤、限流、風控碼不算」，這條原則同樣
適用在「風控驗證」不等於「憑證無效」也不等於「限流」，三者是統一錯誤型別裡三個不同的分支。

### 6.2 YouTube：「確認你不是機器人」、年齡／地區限制

**直接原始碼證據（yt-dlp，`yt-dlp/yt-dlp`，`yt_dlp/extractor/youtube/`）**：

- `_video.py`（約 4030–4080 行，直接讀取確認）：當一支影片沒有可用格式時，依 `reason`
  字串內容分流訊息，並用**同一個** `ExtractorError`（透過 `raise_no_formats`）搭配不同訊息文字
  呈現三種情境：
  - 訊息含 `"sign in"` → 附加登入提示（見下方 `_youtube_login_hint`）。
  - 播放器回應帶 `playerCaptchaViewModel` → 附加「YouTube is requiring a captcha challenge
    before playback」。
  - 訊息含 `"This content isn't available, try again later"` → 附加「已被限流最多一小時，建議
    用 `-t sleep` 加延遲」的說明與 wiki 連結。
  - 若 `subreason` 顯示是地區限制（`"The uploader has not made this video available in your
    country"`），則呼叫**獨立的** `raise_geo_restricted`，帶上允許的國家清單。
- `_base.py`：`_youtube_login_hint` 屬性組出「附上如何匯出 cookie 的 wiki 連結」的完整提示文字；
  `_check_login_required` 在音源要求登入但未認證時呼叫 `raise_login_required`。
- `common.py`（yt-dlp 通用基底類別，直接讀取確認）：

  ```python
  def raise_login_required(self, msg='...', metadata_available=False, method=NO_DEFAULT):
      if metadata_available and (self.get_param('ignore_no_formats_error')
                                  or self.get_param('wait_for_video')):
          self.report_warning(msg); return
      msg += format_field(self._login_hint(method), None, '. %s')
      raise ExtractorError(msg, expected=True)

  def raise_geo_restricted(self, msg='...', countries=None, metadata_available=False):
      if metadata_available and (...):
          self.report_warning(msg)
      else:
          raise GeoRestrictedError(msg, countries=countries)

  def raise_no_formats(self, msg, expected=False, video_id=None):
      if expected and (...):
          self.report_warning(msg, video_id)
      elif isinstance(msg, ExtractorError):
          raise msg
      else:
          raise ExtractorError(msg, expected=expected, video_id=video_id)
  ```

  三個關鍵設計點：
  1. **地區限制有自己專屬的例外子類別**（`GeoRestrictedError`，攜帶 `countries` 清單），而
     「需要登入」「機器人驗證」「無可用格式」全部共用通用的 `ExtractorError`，只靠訊息文字
     與 `expected: bool` 旗標區分。
  2. **`expected` 旗標**——標記「這是已知、會發生的情境」還是「未預期的 bug」，跟 NewPipe 的
     `isReportable`（相反語意：`isReportable=true` 代表未預期）是同一個概念的兩種表達方式。
  3. **`metadata_available` + `ignore_no_formats_error`／`wait_for_video`**——當已經有部分中繼
     資料可用時，這三種本來會整個中斷的錯誤（登入、地區限制、無格式）都可以「降級成警告」而不是
     拋出例外，讓呼叫端可以選擇「有多少資料先顯示多少」。**這是「自動恢復」的一種具體實作模式**：
     不是重試，而是「接受部分結果、把錯誤降級為警告」。

**NewPipeExtractor 對應（研究一第 3.4 節已列出階層，此處補分類意義）**：

- `SignInConfirmNotBotException extends ParsingException`——文件註解原文：「Content can't be
  extracted because the service requires logging in to confirm the user is not a bot. Can
  usually only be solvable by changing IP (e.g. in the case of YouTube).」——**明確指出這類錯誤
  在客戶端側幾乎無法自動恢復**（換 IP 不是客戶端能做的事），對應到 FMP 分類應歸類為
  「風控驗證」而非「需登入」，即使訊息文字看起來像登入提示。
  - **對 FMP 的重要啟示（推測）**：YouTube 的「Sign in to confirm you're not a bot」訊息，
    yt-dlp 把它跟真正的「登入才能看」歸在同一個籠統的 `ExtractorError`（只靠訊息文字分流
    UI 提示），但 NewPipeExtractor 把它獨立成一個介於「風控」與「需登入」之間的類別
    （繼承 `ParsingException` 而非 `ContentNotAvailableException`）。這代表這個情境**不完全
    等同**擁有者定義的「需登入／憑證過期」或「風控驗證」任一個既有分類，而是兩者的交集——
    FMP 設計統一錯誤型別時，這是一個需要擁有者決定「歸類到哪一類、還是兩者都不完全貼切」的
    具體案例（見最終回報的待決問題）。
- `GeographicRestrictionException`、`AgeRestrictedContentException`：均繼承
  `ContentNotAvailableException`，與 yt-dlp 把地區限制獨立出來（`GeoRestrictedError`）的做法
  一致；年齡限制 NewPipeExtractor 有獨立子類別，yt-dlp 這邊本次未特別確認是否也有獨立處理
  （**標記查不到**：本次只確認了地區限制與登入／機器人驗證的 yt-dlp 程式碼路徑，未特別搜尋
  yt-dlp 對年齡限制的專屬處理邏輯）。

## 參考連結彙整

- AWS：<https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/>、
  <https://github.com/awslabs/aws-arch-backoff-simulator>
- Dart 套件（pub.dev API + 原始碼）：<https://pub.dev/packages/retry>、
  <https://github.com/google/dart-neats/blob/master/retry/lib/retry.dart>、
  <https://pub.dev/packages/dio_smart_retry>、
  <https://github.com/rodion-m/dio_smart_retry>、<https://pub.dev/packages/pool>
- MDN：<https://developer.mozilla.org/en-US/docs/Glossary/Idempotent>
- NewPipe：
  <https://github.com/TeamNewPipe/NewPipe/blob/dev/app/src/main/java/org/schabi/newpipe/error/ErrorUtil.kt>
- NewPipeExtractor：
  <https://github.com/TeamNewPipe/NewPipeExtractor/tree/dev/extractor/src/main/java/org/schabi/newpipe/extractor/exceptions>
- Finamp：
  <https://github.com/finamp-app/finamp/blob/redesign/lib/components/global_snackbar.dart>
- PiliPlus：<https://github.com/bggRGjQaUbCoE/PiliPlus>（`lib/http/validate.dart`、
  `lib/http/error_msg.dart`）
- yt-dlp：
  <https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_video.py>、
  <https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_base.py>、
  <https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/common.py>
- 間接來源（未直接讀取確認，供追蹤）：`SocialSisterYi/bilibili-API-collect` 倉庫的
  `docs/misc/sign/v_voucher.md`
