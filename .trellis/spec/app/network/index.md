# 網路（`app/lib/core/network/`）

發 HTTP 請求、改攔截器、接插件的請求、寫網路相關測試時適用。規則（`Dio` 只在這裡建、
攔截器順序、重試只在這裡、網域與轉址、網路紀錄欄位）與閘門見 `app/AGENTS.md` § 網路；
為什麼這樣做，見 ADR 0012 §決定 1–2、ADR 0013 §決定 2、4。這裡只寫怎麼做。

## 目錄

```
lib/core/network/
  source_http_client.dart  # SourceHttpClientFactory、SourceHttpClient、SourceRequest、SourceResponse、RequestCancelled
  interceptors.dart        # part：五個攔截器、每次送出的狀態 _Attempt、只收自己 host 的 cookie jar
  media_http_client.dart   # MediaHttpClientFactory、MediaHttpClient、MediaDownload
  http_rules.dart          # 兩種 client 共用：網域、轉址、限流語意、傳輸錯誤的對應
  network_log.dart         # networkLogTag、NetworkClient、NetworkRecordIds、writeNetworkRecord
  auth.dart                # AuthRequirement、decideAuth、CredentialSource、NoCredentials
  allowed_hosts.dart       # AllowedHosts：manifest 網域比對（請求與 cookie 的 Domain 共用）
  request_throttle.dart    # RequestThrottle：併發上限＋最小間隔
  media_headers.dart       # mediaRequestHeaders：媒體請求只留的 header
  network_status.dart      # NetworkStatus、狀態機、networkStatusProvider、RequestOutcomeSink
```

## 發一個請求

```dart
// 組裝點（PR 9 起）：一個 factory，log 與認證來源給一次。
final factory = SourceHttpClientFactory(log: log);
final client = factory.create(
  pluginId: manifest.id,
  allowedHosts: manifest.allowedHosts,
  retryPolicy: manifest.retryPolicy ?? const RetryPolicy(),
  rateLimitPolicy: manifest.rateLimitPolicy,
);

final response = await client.send(
  SourceRequest(
    url,
    headers: {'Referer': referer},
    auth: AuthRequirement.userPreference,
  ),
  abortTrigger: cancelled.future,
);
```

- `send` 丟的只有 `AppError` 與 `RequestCancelled`。網域不符、轉址出網域、`Location`
  解析不了或超過 5 次是 `Unsupported`；未登入的 `required` 是 `AuthRequired`；傳輸錯誤是 `NetworkError`；
  429 與帶 `Retry-After` 的 503 是 `RateLimited`（都已經照策略重試過）。
- 其他狀態碼照樣回 `SourceResponse`，插件在自己的邊界依錯誤對應表轉成 `AppError`
  （`.trellis/spec/app/errors/index.md` § 音源的錯誤對應表）。
- `body` 是位元組；JSON 由插件自己 `utf8.decode`。
- 方法照 RFC 9110 大寫（`GET`），重試只看它判斷冪等；`get` 會被當成不冪等。
- 網址寫在 `lib/core/endpoints.dart`（`fmp_url_literal`），插件的網址在插件裡。

## 一次 `send` 的流程

1. 檢查網域（`AllowedHosts.allows`）。
2. 送出：`_Attempt` 帶新的紀錄 id 放進 `extra`，經五個攔截器到 adapter。
3. 失敗時依 `shouldRetry`／`delayFor` 決定要不要等了再送，回到 2（新的紀錄 id、
   `retry` 加一）。
4. 301／302／303／307／308 帶 `Location`：檢查網域，照 RFC 9110 §15.4 改方法，跨 host
   就拿掉 `Cookie`、`Authorization` 並改成 `AuthRequirement.never`（之後各跳沿用，
   轉回原本的 host 也不再帶），回到 1。

## 改攔截器

- 攔截器都在 `interceptors.dart`（`source_http_client.dart` 的 `part`），順序在
  `SourceHttpClientFactory.create` 的 `interceptors.addAll`。
- 攔截器之間共用的狀態放 `_Attempt`，不另開 `extra` 的鍵。
- reject 一律 `handler.reject(error, true)`；在 onRequest 或 onResponse 裡要讓請求失敗
  時，把 `AppError` 放進 `DioException.error`（`_rejection`），`send` 會把它拆出來丟。
- 會等的攔截器（例如限流）先把要釋放的東西記進 `_Attempt` 再等：等的時候被取消，dio
  直接走 onError，要在那裡釋放。
- 改了順序，`interceptors run in the ADR 0012 order` 應該會紅；新的前後關係如果看得出
  行為差異，在那個測試加一條斷言。

## 測試

```dart
final harness = Harness(
  (options) => switch (options.uri.path) {
    '/a' => redirect('/b'),
    _ => reply(200, body: '{}'),
  },
  credentials: FakeCredentials(headers: {'Cookie': 'SESSDATA=FAKE_SESSDATA_123'}),
  retryPolicy: const RetryPolicy(maxRetries: 0),
);
await harness.get('https://example.test/a', auth: AuthRequirement.userPreference);
expect(harness.adapter.requests.last.headers['cookie'], ...);
expect(harness.records.single.fields['status'], 200);
```

- `test/core/network/harness.dart`：client 加上 `test/support/fake_http_adapter.dart`
  的假 adapter（不聯網，記下送到最底層的 `RequestOptions`）、假時鐘（`waits` 記下每次
  等待，等待立刻完成並把時鐘往前撥）、固定種子的 `Random`、`LogLevel.debug` 的 log。
- adapter 要模擬傳輸錯誤就在 handler 裡 `throw DioException.connectionTimeout(...)` 之類；
  要模擬掛著的請求就回一個自己控制的 `Completer` 的 future。
- 等非同步進度用 `test/support/pump_until.dart` 的 `pumpUntil`／`settle`
  （`fmp_test_waits`）。
- 網域在測試裡用 `example.test`、`cdn.example`（RFC 2606 保留網域），不用真實網站。
- 驗遮蔽時兩個出口都看：`harness.log.history` 與 `LogFile`（見
  `.trellis/spec/app/logging/index.md` § 測試）。

## 網路狀態

```dart
// 組裝點：client 的工廠接上網路狀態（plugin_registry.dart 的寫法）。
SourceHttpClientFactory(
  log: ref.watch(logProvider),
  reportOutcome: ref.watch(networkStatusProvider.notifier).report,
);

// 畫面：請求失敗而狀態不是 online 時換成離線空狀態。
final network = ref.watch(networkStatusProvider);
if (failed && network != NetworkStatus.online) {
  return OfflineMessage(status: network, action: retryButton);
}
```

- API client 在「每次送出」之後回報一次：拿到回應 `RequestOutcome.responded`，傳輸錯誤
  `RequestOutcome.networkError`，沒送出與取消不回報（`SourceHttpClient._reportFailure`）。
  媒體 client 在每一跳結束時回報一次（`MediaHttpClient._hop` 的 `finish`）：收內容時中斷
  或逾時也是 `networkError`。
- 轉換規則全在 `NetworkStatusMachine`（純 Dart，讀 `clock`）；Notifier 只接平台層與
  log（tag `network-status`，每次改變一筆 `Network status changed`，欄位 `from`、`to`、
  `cause`）。改規則先改 `network_status_test.dart` 的轉換表那一列。
- 測試：狀態機直接建；要時間就包 `fakeAsync`，結尾斷言 `async.pendingTimers` 是空的。
  client 的回報看 `Harness.outcomes`／`MediaHarness.outcomes`。畫面的測試用 `ShellHarness.setNetwork`。

## 媒體 client

```dart
// 組裝點：PluginRegistry 在插件加入清單時建，畫面與播放層從這裡拿。
final media = ref.read(pluginRegistryProvider.notifier).mediaClient(pluginId);

final download = await media!.download(
  url,
  destination: File(p.join(directory, fileName)),
  maxBytes: 10 * 1024 * 1024,
  headers: {'Referer': referer},
  abortTrigger: cancelled.future,
);
// download.headers 是回應標頭（Cache-Control、ETag、Content-Type）。
```

- `download` 丟的只有 `AppError` 與 `RequestCancelled`，錯誤對應見 `app/AGENTS.md`
  § 網路的「媒體 client」。內容只在成功時出現在 `destination`；失敗時 `.part` 已刪掉。
- 沒有重試。要重試的呼叫端（M6 的下載）自己決定，封面靠下一次顯示時再抓。
- 封面不直接呼叫 `download`：經 `artworkCacheManagerProvider(pluginId)`
  （`lib/plugins/plugin_artwork.dart`）的 cache manager，下載的暫存檔、索引與淘汰都在快取庫
  （`.trellis/spec/app/data/index.md` § 快取庫）。新的呼叫端每次下載給不同的 `destination`。
- 一跳的流程在 `_hop`：送出 → 轉址就取消那一跳、回傳 `Location` → 錯誤狀態碼與
  `Content-Length` 過大就丟 → `_save` 邊收邊數寫 `.part` → 改名。不讀的回應一定要
  `cancelToken.cancel()`，否則連線一直開著。
- 測試用 `harness.dart` 的 `MediaHarness`；要控制內容怎麼來（一塊一塊、中斷、不來）用
  `streamed(StreamController)`，在 controller 的 `onCancel` 看連線有沒有放掉（取消是非同步
  的，用 `pumpUntil` 等）。暫存目錄在 `setUp` 建，失敗的案例斷言目錄是空的。
- 逾時用 `fakeAsync`：只在還沒收到資料、沒碰到檔案的情況下用（`.part` 收到第一塊才建立）。
  真的檔案 I/O 在 fakeAsync 裡不會完成。

## 媒體 header

媒體 client 的每一跳、播放後端拿到的串流 headers 都先過 `mediaRequestHeaders`，再交給
dio 或 just_audio／media_kit。要多放一個 header 時改 `mediaHeaderNames`，並在
`media_headers_test.dart` 加一個會留與一個不會留的案例。

## Quality Check

- `test/core/network/` 全綠；新行為在對應群組有案例。
- `lib/core/network/` 沒有 import 上層（`fmp_layer_imports`）、沒有網址字面值。
- 改了網路紀錄的欄位（`network_log.dart`）：`app/AGENTS.md` § 網路與兩個 client 測試的
  `network log` 群組一起改。
