# 研究：HTTP 錄製重播與零網路測試

> 對應 `.trellis/tasks/09-27-design-testing` 研究第 2、3 點：dio 生態系的
> HTTP fixture 錄製／重播工具、錄製時如何自動遮蔽憑證、fixture 檔案
> 格式設計、JS 腳本插件如何透過宿主 HTTP 層重播 fixture；以及如何讓
> `flutter test` 不帶參數時保證連不到網路、smoke test 如何標記與執行、
> 是否該排程跑、失敗時如何通知。
> 查證方式：pub.dev／GitHub 官方頁面、Dart 官方文件（WebFetch／
> WebSearch）、flutter_js 官方 repo。查不到的一律寫「查不到」，推論
> 一律標「推測」。查證時間 2026-09-27。

---

## 第 2 點：HTTP 錄製與重播

### 現有 dio 生態系工具盤點

| 工具 | 對接方式 | 錄製到磁碟 | 維護狀態 | 來源 |
|---|---|---|---|---|
| `http_mock_adapter` | `HttpClientAdapter` 或 `DioInterceptor`（Mockito 為底） | 不支援，要手寫每個回應 | 最後活躍約 2023-11，`dio` 版本鎖 `^5.3.2` | <https://pub.dev/packages/http_mock_adapter> |
| `dio_mock_interceptor` | Interceptor，回傳寫死的回應 | 不支援 | 未深入查證版本歷史 | <https://pub.dev/packages/dio_mock_interceptor> |
| `vcr` | 自訂 `HttpClientAdapter`（`VcrAdapter`），設在 `dio.httpClientAdapter` | **支援**，第一次找不到錄製檔就照常送出請求並存檔，之後重播 | 原作者 repo 更新時間**查不到**（WebSearch 未取得最後 commit 日期） | <https://github.com/louis-kevin/vcr>、<https://pub.dev/documentation/vcr/latest/> |
| `vcr2` | 同上，宣稱是 `vcr` 的 null-safety 維護 fork，「可搭配 http 套件使用」 | 支援 | 比 `vcr` 新，但確切最後更新時間**查不到** | <https://pub.dev/documentation/vcr2/latest/> |
| `dartvcr`（EasyVCR 的 Dart port） | `package:http` 的 `BaseClient`，**不是** dio 的 `HttpClientAdapter** | 支援，且原生附「錄製過期」「Mode.auto／record／replay／bypass」「內建 censor（如 `Censors().censorQueryElementsByKeys(['api_key'])`）」 | 有維護（EasyPost 官方 port），但因為底層是 `package:http` 而非 dio，要接進 FMP 的 dio 生態必須額外寫一層 `HttpClientAdapter` 橋接，或改用 `dio_compatibility_layer`（讓 `package:http` 的 `Client` 包成 dio adapter，方向與 FMP 需要的相反，仍需自己驗證是否雙向可行） | <https://pub.dev/packages/dartvcr> |

### 建議做法：不直接採用任何現成套件，自寫一個薄的 `HttpClientAdapter` 包裝層

理由：

1. `vcr`／`vcr2` 維護狀態的最後更新時間查不到，且它們的錄製格式、
   匹配邏輯（怎麼判斷「這是同一個請求」，是否含 body／query
   自訂比對規則）沒有在查證中看到足夠細節，無法確認能否滿足 FMP
   需要的「錄製時自動遮蔽」與「fixture 帶結構化 metadata（來源、
   擷取時間）」需求。
2. `dartvcr` 雖然功能最完整（含內建 censor、過期機制），但底層 HTTP
   client 型別與 FMP 的 dio 架構（ADR 0012 講的「每來源一個 dio
   client」）不同源，橋接層本身變成一個新的、沒人驗證過的依賴。
3. 官方與社群共識的作法（來源：WebSearch 摘要多篇 Dio 測試指南）是
   「Dio 5 的慣例做法是自寫一個包住真正 adapter 的
   `HttpClientAdapter`：record 模式下正常放行請求、把回應存成 JSON；
   replay 模式下直接從存好的檔案組出
   `ResponseBody.fromString(...)`」——這與 FMP 既有的
   `test/support/` 慣例（自己寫測試基礎設施）一致，且**adapter
   層級正好位在所有 interceptor 之下**：dio 的請求方向是
   `interceptors → adapter`，回應方向是 `adapter → interceptors`，
   所以 adapter 錄到的請求是「所有 request interceptor（含 ADR 0012
   注入的 `Authorization`／cookie）都已套用之後」的最終原始請求，
   錄到的回應是「response interceptor（含 ADR 0013 的錯誤對應、
   ADR 0011 的 log）都還沒碰過」的原始回應——**這代表 adapter 層級
   錄到的資料一定含有真實憑證，遮蔽必須在寫入磁碟之前、由錄製層
   自己動手，不能依賴任何 interceptor 幫忙擋掉**（見下方遮蔽小節）。

### fixture 檔案格式設計（本研究自行設計，非抄自既有工具）

沿用 ADR 0014 決定 6「每插件一目錄（腳本、manifest、錄下的測試
fixture）」的既有方向，建議目錄與檔案結構：

```
<音源目錄>/test/fixtures/
  search_keyword_basic.json
  resolve_stream_track_123.json
  error_401_credential_invalid.json
```

單一 fixture 檔案內容（JSON，逐一鍵值為建議欄位，非任何工具強制格式）：

```jsonc
{
  "meta": {
    "recordedAt": "2026-09-27T00:00:00Z",   // 擷取時間，UTC
    "sourceId": "bilibili",                  // 對應音源，供人工排錯
    "capturedBy": "manual",                  // manual｜ci-live-smoke，追蹤是誰錄的
    "redacted": true                          // 是否已跑過遮蔽，錄製流程強制為 true 才可寫檔
  },
  "request": {
    "method": "GET",
    "url": "https://api.bilibili.com/x/web-interface/search?keyword=xxx",
    "headers": { "cookie": "[REDACTED]" }
  },
  "response": {
    "statusCode": 200,
    "headers": { "set-cookie": "[REDACTED]" },
    "body": "{...}"
  }
}
```

- 一個檔案對應「一次請求／回應」，而非整個測試案例的多次請求打包在
  一起——理由是重播時每個請求各自比對／各自替換更直覺，也讓
  diff／code review 時容易看出單一 fixture 的變化。
  一個測試案例若牽涉多次請求（例如先搜尋、再取得播放地址），對應
  多個 fixture 檔，由測試程式按呼叫順序或按 URL 比對來取用——比對
  規則本身（要精確比對 query string 還是只比對 path）留給
  `implement.md` 依實際音源 API 決定，本研究不預先下死規定。
- `meta.redacted` 這個欄位本身**不能**單獨當作信任依據（它只是
  記錄「錄製流程有沒有跑過」），真正的把關要靠遮蔽函式在寫檔前
  強制執行、加上一條測試斷言：對每個現有 fixture 檔案掃描已知的
  憑證特徵（`Set-Cookie`、`Authorization`、簽名 URL 的 `sign=`／
  `expires=` 等 query 參數樣式）不得出現非 `[REDACTED]` 的值——這條
  測試本身即是「fixture 內容不含真憑證」的閘門，建議放在
  `test/support/` 底下、跑在一般 `flutter test`（不需要網路）。

### 錄製時自動遮蔽——沒有任何查到的工具原生支援「跟 FMP 一致的遮蔽規則」

- `dartvcr` 原生有 censor 機制（`Censors().censorQueryElementsByKeys(...)`），
  但它是通用工具，遮蔽規則要自己設定要遮哪些 key／header，且如前述
  它底層是 `package:http` 而非 dio，FMP 若要用它就要接受這層橋接
  成本。
- `vcr`／`vcr2` 的文件**查不到**有內建遮蔽機制的描述。
- ADR 0011（雖然本研究未直接讀取該 ADR 全文，但 ADR 0012／0013／0014
  的「如何確認」段落都提到「遮蔽」是同一份規格）代表 FMP 已經有、
  或即將有一個「production 用的遮蔽函式」（用來清 log／診斷包）。
  **建議：錄製 fixture 時直接呼叫同一個 production 遮蔽函式**，而不是
  另外維護一套「只給測試用」的遮蔽規則——這樣遮蔽規則只有一份來源，
  且錄製流程「不小心洩漏正式環境沒設定要遮的東西」的風險與正式
  log 洩漏風險綁在一起，一次測試（同一份契約測試／redaction test）
  就能同時涵蓋兩種使用情境。這是本研究對 ADR 0011「遮蔽」與
  ADR 0014「契約測試涵蓋 0011」兩項要求的具體串接建議，需要
  `implement.md` 階段落實成「遮蔽函式簽章要能同時處理『dio
  RequestOptions／Response 物件』與『log 字串』兩種輸入」。

### JS 腳本插件如何透過宿主 HTTP 層重播 fixture

依 ADR 0014 決定 5，腳本能用的宿主 API 只有 `http.request`（經
ADR 0012／0013 網路層），這正是唯一的 HTTP 出入口，也是天然的
重播掛勾點。技術путь：

- `flutter_js`（`abner/flutter_js`）的橋接機制是
  `evaluate()`／`onMessage(channel, handler)`／`sendMessage(channel,
  payload)`：Dart 端註冊一個 channel（例如 `http.request`），JS
  腳本呼叫宿主提供的 `http.request(...)` 包裝函式時，實際上是把
  參數用 `sendMessage` 送回 Dart，Dart 端在 `onMessage` 回呼裡真正
  執行 HTTP 呼叫、再把結果回傳給 JS。
  （來源：`flutter_js` 官方 repo README，
  <https://github.com/abner/flutter_js>——README 有 `onMessage`／
  `sendMessage` 的範例，具體參數型別建議在 `implement.md` 落地前
  直接讀原始碼核對，此處只確認機制存在與大致用法。）
- **這代表「host API 的 `http.request` 實作」是唯一需要替換的地方**：
  正式執行時，這個 Dart handler 呼叫真正的 dio client（含 ADR 0012
  的 `AuthRequirement` 注入、ADR 0013 的錯誤對應）；契約測試執行時，
  同一個 handler 改成呼叫上一節設計的「重播 adapter」，回傳
  fixture 內容——**JS 腳本本身完全不知道自己在測試環境，呼叫方式
  一模一樣**，這正是題目要求的「用同一個宿主 API，測試替身換掉
  production 後端」。
- 具體做法：`SourceHttpClient`（或等效的宿主 HTTP 抽象）改成建構子
  注入一個 `HttpClientAdapter`，production 組裝走真正的 dio
  `IOHttpClientAdapter`，契約測試組裝走「重播 adapter」（讀
  `test/fixtures/*.json`，依 URL／method 比對回傳對應的 fixture
  回應，找不到就丟出明確錯誤而非靜默通過，避免測試因為 fixture
  遺漏而誤判成功）。

---

## 第 3 點：零網路測試與 smoke test

### 預設 `flutter test` 保證連不到網路——雙重機制

**機制一：`dart_test.yaml` 的 tag 預設跳過**

Dart test 官方支援在設定檔用 `tags:` 區塊，對某個 tag 設定
`skip: true`（或帶理由的字串），這個設定**對所有呼叫方式生效**，
包含裸 `flutter test`（不帶任何參數）——要跑被跳過的測試，必須用
`-P`／`--tags`／設定檔的 `presets` 明確覆蓋。這是 Dart test 官方
機制的一部分（`package:test` 的 `dart_test.yaml` 設定檔），FMP
可以：

```yaml
# dart_test.yaml
tags:
  live:
    skip: "會打真實 API，只能手動或排程執行，見 docs/development.md"
```

被標 `@Tags(['live'])` 的測試檔，一般 `flutter test`（含 CI 的
`flutter test --exclude-tags live`，這條指令其實在有了 `dart_test.yaml`
的 `skip` 設定後已經是多餘但無害的雙保險）都會顯示「跳過」而非
「執行」。要真正執行，需要 `flutter test --tags live` 之類的明確
呼叫並額外提供 preset 或環境變數解除 skip（Dart test 的 `skip`
選項可以接受一個字串，永遠跳過除非在設定檔用
`presets: { live: { tags: { live: { skip: false } } } }` 這類結構
明確解除——**具體語法組合建議落地時對照當時的 `package:test` 版本
文件重新核對，本研究只確認「tag + 設定檔 skip + presets 解除」這個
機制存在**，未逐字驗證最新語法）。

**機制二：`HttpOverrides.global` 攔截所有真實 socket 建立**

- 在 `test/flutter_test_config.dart` 的 `testExecutable` 內，於所有
  測試執行前安裝一個自訂 `HttpOverrides`：

  ```dart
  Future<void> testExecutable(FutureOr<void> Function() testMain) async {
    HttpOverrides.global = _ThrowingHttpOverrides();
    await testMain();
  }

  class _ThrowingHttpOverrides extends HttpOverrides {
    @override
    HttpClient createHttpClient(SecurityContext? context) {
      throw StateError(
        '測試中偵測到真實 HttpClient 建立——一般測試不得連網路，'
        '若這是刻意的 live/smoke 測試，請在該測試內用 '
        'HttpOverrides.runZoned 明確允許。',
      );
    }
  }
  ```

- 涵蓋範圍：`dart:io` 的 `HttpClient` 本身、`package:http` 的
  `IOClient`（底層用 `HttpClient`）、dio 預設的
  `IOHttpClientAdapter`（同樣底層用 `HttpClient`）都會在建立時
  立刻丟例外，測試會直接失敗並顯示清楚訊息，而不是安靜地嘗試連線
  然後在 CI 環境因為連不到而逾時或間歇性失敗。
- **涵蓋不到的例外**：直接用 `dart:io` 的 `Socket.connect`（略過
  `HttpClient` 抽象）不受此攔截；某些平台專屬的 HTTP 引擎
  （`cupertino_http` 用 `NSURLSession`、`cronet_http` 用 Android
  Cronet）繞過 `dart:io HttpClient`，`HttpOverrides` 對它們無效——
  FMP 若日後改用這些引擎作為 dio adapter，需要額外設計攔截機制
  （例如強制在測試環境注入假 adapter，而不倚賴 `HttpOverrides`）。
  就 FMP 目前 dio-based 架構而言，這兩個機制合起來已能攔住幾乎所有
  意外連網。
- 需要刻意允許連網的 smoke test，可用
  `HttpOverrides.runZoned(testMain, createHttpClient: (context) =>
  HttpClient())` 在該測試的 zone 內暫時換回真正的 `HttpClient`，
  離開該 zone 後恢復全域攔截——保證「允許連網」是**逐一測試顯式
  聲明**，不是整份測試檔案的預設狀態。

兩個機制疊加的理由：tag skip 解決「這個測試會不會被執行」，
`HttpOverrides` 解決「萬一有人忘記標 tag、或某個測試意外新增了會
連網的程式碼路徑」的最後防線——這是縱深防禦（defense in depth），
不是其中一個就夠。

### smoke test 的標記與執行方式

- 用 `@Tags(['live'])` 標記在測試檔頂端（`package:test` 官方標籤
  機制），與上方 `dart_test.yaml` 的 `live: skip:` 設定對應。
- 執行方式建議兩種入口都留：
  1. **手動**：`flutter test --tags live`（開發者本機在需要驗證
     「音源 API 是否仍然可用」時手動跑，例如插件作者要驗證自己的
     `1morr/fmp-plugins` 插件契約測試對應到真實 API 還有沒有壞）。
  2. **App 內 Debug 頁健康檢查**：依擁有者方向「真實 API 呼叫只能經
     由 Debug 頁健康檢查或明確呼叫的 smoke test」，這代表 App 本身
     要有一個開發者可以手動觸發的頁面，對每個已安裝音源跑一次
     「呼叫一個最輕量的 API、回報成功/失敗」，這是產品功能而非
     測試框架的一部分，屬於 `implement.md` 的 UI 設計範疇，本研究
     只確認它與「smoke test」共用同一份「真實呼叫」程式碼路徑是
     合理設計（同一組 API 呼叫，一份給人在 App 內手動點、一份給
     CI 排程跑）。

### 是否該在 CI 排程執行 smoke test——不建議排程，只建議手動觸發

**證據**（沿用之前研究、本次未重新查證，僅整理結論與既有 URL）：

- Bilibili：沒有官方聲明會封鎖雲端／CI 網段，但多個社群專案（`
  yt-dlp` 相關 issue、至少一個公開 GitHub Actions 專案的 README）
  顯示從自動化環境呼叫會遇到 HTTP 412「風控」回應，該專案的因應
  方式是準備 `BILI_COOKIE` secret 並加上 cooldown（延遲）機制，
  顯示這不是憑空的疑慮而是有人實際踩過的問題。
- YouTube：自 2024 年中起有廣泛紀錄的雲端／機房 IP 封鎖
  （「Sign in to confirm you're not a bot」、後續演變成 403 加
  proof-of-origin token），屬於公開、多方確認的現象；但**沒有直接
  證據**顯示這具體會擋到 GitHub Actions 的 runner IP 段（GitHub
  Actions 的出口 IP 屬於 Azure 的資料中心範圍，一篇部落格文章推測
  Azure IP 可能有「不同的信譽分數」，這點明確標記為**推測**，非
  確認事實）。

**建議**：**不要**把 smoke test 排進 GitHub Actions 排程
（`schedule:` cron）。理由：

1. 排程一旦命中風控／封鎖，會產生持續失敗的雜訊——擁有者的目標是
   「保護真實憑證帳號與 IP 信譽」，而不是「盡快發現音源掛掉」（音源
   掛掉更適合由使用者實際使用時回報、或插件作者手動驗證來發現，
   ADR 0014 決定 7 本來就是「使用者手動檢查更新」的哲學，排程 smoke
   test 與這個哲學不一致）。
2 若排程從共享的 GitHub-hosted runner IP 段持續打真實 API，一旦
   帳號或 IP 被標記為異常，受影響的不只是 FMP 這個 repo，同一個
   IP 段是所有使用 GitHub Actions 的專案共用的，可能连累其他不相干
   的自動化。
3. 若擁有者仍然想要某種形式的「定期健康檢查」，比較安全的作法是
   **自架的、非 CI 網段的排程**（例如擁有者自己機器上的 cron，或
   Debug 頁本身在使用者打開 App 時順手跑一次而非固定排程），而不是
   公開 CI 服務的共享網段——這點屬於需要擁有者確認方向的決策，列入
   最終報告的待決策清單。

若擁有者仍決定要排程（不論排在哪裡），失敗通知機制的技術做法
（來源：WebSearch 對 2026 年現況的綜合整理，非單一權威來源，此段
标记为社群慣例整理而非官方規範）：

- GitHub 對排程失敗**沒有內建的「開 issue」機制**，預設只會寄信給
  最後修改該 workflow 檔案的人（等於失敗紀錄躺在一個人的信箱裡）。
- 三種常見做法：
  1. **Marketplace action**：如
     `JasonEtco/create-an-issue`（用 issue 範本檔案 + `if: failure()`
     步驟）或「Failed Build Issue」action，設定簡單但引入第三方
     action 的信任面。
  2. **獨立 watcher workflow**：用 `workflow_run` 事件監看其他
     workflow 的完成狀態，好處是不用改每個既有 workflow
     （`urcomputeringpal/workflow-failure-issues` 是一個現成的
     reusable workflow 範例）。
  3. **直接用 `gh` CLI，不引入任何第三方 action**（多篇 2026 年的
     專案採用，視為目前較常見的做法）：在失敗的 job 後面加一個
     `if: failure() && github.event_name == 'schedule'` 的步驟，
     先 `gh issue list` 搜尋是否已有同標題的開放 issue，有就
     `gh issue comment` 累加、沒有才 `gh issue create`——避免同一個
     問題连續多天各開一個新 issue。
- **建議**：若日後真的要接失敗通知，直接用 `gh` CLI 的自建 step
  （做法 3），不引入額外 action 依賴，且與 FMP 既有「issue tracker
  用 `gh` 操作」的 agent 慣例（`docs/agents/issue-tracker.md`）
  一致。**但前提是擁有者先決定「要不要排程執行 smoke test」——本研究
  的建議是不要，這段技術做法只在擁有者選擇排程時才用得上**。

---

## 待補查項（誠實列出）

- `vcr`／`vcr2` 兩個套件的實際最後維護時間、與目前 dio 主版本
  （`cfug/dio`，目前 5.x 系列）的相容性**查不到**——WebSearch
  摘要沒有給出明確的 commit／發布日期，若日後决定改採用其中之一
  而非本研究建議的「自寫薄 adapter」，落地前必須直接開
  pub.dev 版本頁與 GitHub commit 紀錄核對。
- `flutter_js` 的 `onMessage`／`sendMessage` 確切函式簽章（參數
  型別、是否為 async、channel 命名限制）本研究只確認機制存在於
  README，未逐行核對原始碼；`implement.md` 階段需要直接讀
  `abner/flutter_js` 的原始碼確認。
- Dart `package:test` 目前版本（配合 FMP 使用的 Dart 3.13.x）
  `dart_test.yaml` 的 `presets`／`skip` 解除語法，本研究引用的是
  機制概念而非逐字核對當前語法版本，落地前建議寫一個最小可執行的
  範例（一個永遠失敗的 `live` 測試＋一次 `flutter test` 確認跳過、
  一次 `flutter test --tags live` 確認執行）驗證行為，而不是照抄
  本文件的 YAML 片段。
- GitHub Actions 排程失敗通知的三種做法，本研究只做了現況整理
  （WebSearch 綜合摘要），未實際驗證任何一種在 FMP repo 上的行為；
  且此段本身建立在「擁有者決定要排程」這個尚未拍板的前提上，暫時
  不建議投入實作時間查證更深。
