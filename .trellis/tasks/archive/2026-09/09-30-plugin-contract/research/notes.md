# 契約執行器與 fixture 的設計查證（M1 PR 9b）

- 日期：2026-09-30
- 環境：Flutter 3.47.5（Dart 3.13.4）、Windows 11。
- 來源：dio 5.11.1、dio_cookie_manager 3.5.0、drift 2.35.0 的 pub cache 原始碼；成熟工具的官方文件
  （下列網址，2026-09-30 以 raw GitHub 取得）。

## 1. 執行器放在哪：`app/test/plugins/contract/`，不是 `app/packages/plugin_contract/`

prd 寫的是 workspace 裡的獨立套件。實作時改成 `app/` 自己的測試目錄，理由是具體的：

1. **要在 `flutter test` 裡跑 QuickJS，而那個準備是測試目錄層級的**：`test/flutter_test_config.dart`
   預先載入 flutter_js 的原生庫（`test/support/quickjs.dart`）並裝零聯網的 `HttpOverrides`。
   獨立套件要在自己的 `test/` 各抄一份；而且 `quickjs.dart` 從工作目錄的
   `.dart_tool/package_config.json` 找 flutter_js，workspace 成員的工作目錄沒有那個檔（只在
   workspace 根 `app/`），要另外改。
2. **依賴方向會成環**：執行器要 `package:fmp` 的載入器、網路層（`createAdapter` 注入點）、
   `Redactor`、`AppDatabase`。套件依賴 `fmp`；`app/` 的 CI 又要對 `test/fixtures/plugins/` 跑它
   （ADR 0015 §決定 6），`fmp` 就得 dev 依賴這個套件：`fmp` → `plugin_contract` → `fmp`。不成環
   的做法是 CI 另在套件目錄跑一次 `flutter test`，等於為了目錄位置多一個步驟。
3. **分層 lint**：dio 只准在 `lib/core/network/`、drift 只准在 `lib/data/`（`fmp_layer_imports`，
   以 package 根算路徑）。套件的 `lib/` 放錄製與重播的 adapter、記憶體資料庫就會違規或要加例外；
   放在測試目錄沒有這個問題（`test/support/fake_http_adapter.dart` 已是先例）。
4. **插件庫的 CI 用法一樣簡單**：checkout FMP 的固定 ref，在 `app/` 內
   `FMP_PLUGIN_DIR=<插件目錄> flutter test test/plugins/contract/contract_test.dart`。
   套件方案也是 checkout 整個 FMP 再進某個目錄跑，沒有比較省。

也沒有放進 `lib/`：錄製與重播的 adapter、checks 的模型現在只有測試在用。ADR 0015 §決定 7 的 App
內插件開發工具（M3）要在 App 裡切換真實、錄製、重播時，再把 `fixture.dart`、
`fixture_adapters.dart` 移進 `lib/core/network/`（dio 的擁有者），格式不變。

ADR 0015 §決定 6 寫「一個通用套件」：實際是 `app/` 測試目錄裡的一組檔案。要不要在 ADR 加一行
更正，由主 session 決定。

## 2. fixture 格式：WireMock stub mapping

WireMock（`https://raw.githubusercontent.com/wiremock/wiremock.org/main/src/content/docs/docs/stubbing.mdx`）
一個 stub 是 `{"request": {"method", "url"}, "response": {"status", "headers", "body" | "jsonBody" | "base64Body"}}`，
`jsonBody` 讓 JSON 回應不必跳脫、可以直接手改。採用它的欄位名稱，外層加 ADR 0015 §決定 5 的 `meta`：

```json
{
  "meta": { "recordedAt": "2026-09-30T00:00:00.000Z" },
  "request": {
    "method": "GET",
    "url": "https://api.fmp.test/search?page=1&keyword=tone&access_key=***",
    "headers": { "referer": "https://www.fmp.test/" }
  },
  "response": {
    "status": 200,
    "headers": {
      "content-type": ["application/json"],
      "set-cookie": ["demo_session=***; Path=/"]
    },
    "jsonBody": { "demo_session": "***", "list": [], "more": false }
  }
}
```

- 沒採用的 WireMock 欄位：`urlPath`、`queryParameters` 等比對器（比對規則固定，見 §3）、
  `base64Body`（見 §4）、`bodyFileName`（一個請求一個檔就夠）。
- response headers 是「名稱（小寫）→ 字串陣列」，和宿主給插件的 `HttpResponse.headers` 相同；
  request 的 `headers`、`body` 只供閱讀，不比對。
- 一個請求一個檔（ADR 0015 §決定 5），放 `fixtures/<能力>/`，依檔名排序是請求順序，錄製寫
  `001.json`、`002.json`…。一個目錄相當於 VCR 的一卷 cassette。
- `meta.recordedAt`：錄製時間；`meta.edited`：手寫或手改的理由（prd「錯誤案例可手改 fixture，
  並在 meta 標記」）。錄製遇到有 `edited` 的案例整個略過，不蓋掉手寫的錯誤案例。

## 3. 重播的比對：Polly.js 與 VCR

- Polly.js（`https://raw.githubusercontent.com/Netflix/pollyjs/master/docs/configuration.md`
  § matchRequestsBy）預設比 method、headers、body、order、url（query 是「Sorted query
  string」）。VCR（`https://raw.githubusercontent.com/vcr/vcr/master/features/request_matching/README.md`）
  預設只比 method 與 URI，`:query` 比對不分順序；同樣的請求依序拿不同的回應。
- 採用：**method＋網址（query 不分順序）＋順序**（ADR 0015 §決定 5 也這樣寫）。headers、body
  不比：headers 帶 cookie、UA 這類會變的值，照 Polly 的預設比 headers 只會讓錄好的 fixture 很快
  過時。
- 順序是嚴格的：第 n 個請求只對第 n 個 fixture。比 Polly 的 order（同一個識別碼的第幾次）更嚴，
  理由是插件的請求本來就是依序發的，順序變了通常就是插件的邏輯變了。
- 用完與沒用到：VCR 的 `allow_unused_http_interactions: false`
  （`features/cassettes/allow_unused_http_interactions.feature`）在 cassette 結束時若有沒用到的
  互動就報錯。採用：沒被請求用到的 fixture 算違反；請求多於 fixture 也算。
- 遮蔽過的欄位：VCR 的 `filter_sensitive_data` 寫佔位字串，重播時換回原值
  （`features/configuration/filter_sensitive_data.feature`）。這裡換不回（遮蔽不可逆，也不該留
  原值），改成**比對前以同一個遮蔽函式遮過實際的網址**，被遮的欄位兩邊都是 `***`；另外 fixture
  裡值是 `***` 的 query 參數與路徑段不比值，給手寫時標出「這個會變」（時間戳、簽名）。
- 對不上時 adapter 丟一個不是 `IOException` 的錯誤：網路層轉成 `UnexpectedError`、不重試
  （`interceptors.dart` 的 `_map`），執行器另外從 adapter 讀出哪一個請求對不上。

## 4. 錄製

- 接在同一個注入點：`RecordingAdapter` 包住真正的 adapter（live 用 dio 的
  `IOHttpClientAdapter`，測試用假的），回應原樣交給插件，遮蔽過的一份寫檔。
- 遮蔽（ADR 0011 §決定 3，一律經 `Redactor`）：網址與文字 body 用 `redact`；header 與
  `jsonBody` 用 `redactValue`（鍵在名單上的值整個換成 `***`，JSON 仍然合法。對整段 JSON 文字用
  `redact` 時，`"token": 123` 會變成 `"token": ***`，不是合法 JSON）。
- `set-cookie`：`redactValue` 會把整個值換成 `***`，重播時 `dio_cookie_manager` 以
  `Cookie.fromSetCookieValue('***')` 解析會拋 `HttpException`、請求失敗（`cookie_mgr.dart` 的
  `_fromSetCookieValue`，`ignoreInvalidCookies` 預設 false）。所以只換 cookie 的值：
  `名稱=***; 屬性`，名稱與屬性也經 `redact`。
- 不留 `content-length`、`content-encoding`、`transfer-encoding`：body 已經解壓、遮蔽後重新編碼，
  長度與編碼都不對了（VCR 的 `update_content_length_header`、`decompress` 處理同一件事）。
- 不是 UTF-8 的 body 不錄、報出來：fixture 沒有 `base64Body`，因為二進位內容無法經文字遮蔽函式；
  M1 的案例（搜尋、解串流網址）都是 JSON。
- 只錄得了免登入的案例（prd 擁有者決定 8）：錄製的認證來源是 `NoCredentials`，
  `auth: 'required'` 的請求以 `AuthRequired` 失敗，不需要另外的欄位標示。
- 重試照真的時間等（重播時立刻重送）：live 錄製遇到 429 不能連打。
- live 入口在呼叫端 zone 以 `HttpOverrides.runWithHttpOverrides` 放行。插件的請求是背景 isolate
  送訊息、主 isolate 的 `ReceivePort` 監聽器發出的；監聽器在 `PluginRuntime.start` 時註冊，跑在
  註冊當下的 zone，所以整個錄製包在放行的 zone 裡就行。`record_test.dart` 的 `sends real
  requests from the zone it runs in` 以只計數、不連網的 `HttpOverrides` 證明這點。

## 5. checks.json

- 一個物件，鍵是能力名稱：「每插件每能力最多一條」由格式保證。只收 `SourcePlugin` 已有方法的
  能力（M1：`search`、`resolveStream`），其他鍵是不認得的欄位（封閉物件，比照 manifest 與 DTO）。
- `input` 就是該能力的 DTO（`SearchQuery`、`StreamRequest`），以 `sourceDtoShapes` 解碼。
- `expect` 兩種：成功（`minItems`、`nonEmpty`：清單每一筆的這些欄位都要有值，欄位名稱同 d.ts）；
  失敗（`error`：`AppError` 類別名，`reason`：只有 `Unavailable`）。沒有 JSONPath 之類的通用斷言
  語言：prd 要的只有「至少 N 筆、欄位非空、錯誤類別」。
- 不強制每個宣告的能力都有案例（ADR 寫的是「最多一條」）。

## 6. 執行器檢查什麼、怎麼查

| 檢查 | 做法 |
|---|---|
| 能力與匯出一致 | `ScriptPluginLoader.load` 本來就拒絕（`Unsupported`），執行器先載入一次並報出原因 |
| DTO 驗證 | 經 `ScriptSourcePlugin` 呼叫，驗證失敗是 `ParseError`，期望成功時就不符 |
| 案例的期望 | §5 |
| 錯誤類別 | `AppError.typeName` 與 `Unavailable.reason`；原因以 `log.report` 取遮蔽過的字串（`AppError` 的 cause 是函式庫私有） |
| 媒體請求不帶憑證 | M1 沒有媒體 client：看 `resolveStream` 回傳的每個候選的 headers，名單上的 header 名稱或值會被遮蔽的都算 |
| 只連 manifest 網域 | 網路層本來就不送出（`Unsupported`，原因含 `not allowed`）；執行器報出這種錯誤、檢查每個 fixture 的網址、adapter 再看一次每個送到底層的請求 |
| log 經遮蔽 | 每個案例的 log 歷史：再遮一次不變、名單上的欄位值是 `***` |
| fixture 沒有憑證 | 同上兩道，對每個 fixture 檔 |

看不到的（已知限制，寫在 `app/AGENTS.md`）：插件自己接住並吞掉網域錯誤；插件拋的 `ParseError`
與 DTO 驗證的 `ParseError` 分不出來。前者要網路層對被拒的請求也寫網路紀錄才看得到，屬於網路層的
行為變更，這個 PR 不做。

每個案例各自一份記憶體資料庫、log、遮蔽函式與 HTTP client（VCR、Polly 每個測試一卷的做法），
案例之間不共用 storage 與 cookie；資料庫在案例結束時就關（drift 在 debug 下會對同時開著的多個
`AppDatabase` 警告，`db_base.dart` 的 `_handleInstantiated`）。

## 7. CI

選「已包含在 `flutter test` 內」：`contract_test.dart` 在裸 `flutter test` 裡跑
`test/fixtures/plugins/` 的兩個測試插件；`ci.yml` 只補註解。`record_test.dart` 的 live 測試被
`dart_test.yaml` 跳過（本機 `flutter test test/plugins/contract` 顯示 `~1`）。

## 8. 對 `app/` 以外的目錄實際跑一次

把兩個測試插件複製到 session scratchpad 的 `fmp-plugins/`（`http-test/`、`tone/`），在 `app/` 內：

```
$ FMP_PLUGIN_DIR='<暫存目錄>\fmp-plugins' \
    flutter test test/plugins/contract/contract_test.dart
00:00 +0: finds plugin directories
00:00 +1: fmp-test-http (http-test) install file, checks.json and fixtures
00:00 +2: fmp-test-http (http-test) search
00:00 +3: fmp-test-http (http-test) resolveStream
00:00 +4: fmp-test (tone) install file, checks.json and fixtures
00:00 +5: fmp-test (tone) search
00:00 +6: fmp-test (tone) resolveStream
00:00 +7: All tests passed!
```

指向單一插件目錄（`fmp-plugins/http-test`）也可以（4 個測試）。改壞一份副本的 fixture 路徑時的
輸出：

```
fmp-test-http (broken) search [E]
  Expected: empty
    Actual: [ 'search: expected success, got UnexpectedError: …',
              'search: request #1 (GET https://api.fmp.test/search?access_key=***&keyword=tone&page=1) does not match fixtures/search/001.json (GET https://api.fmp.test/find?access_key=***&keyword=tone&page=1)',
              'search: fixtures/search/001.json was not requested' ]
```
