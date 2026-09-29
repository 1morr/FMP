# 網路（`app/lib/core/network/`）

發 HTTP 請求、改攔截器、接插件的請求、寫網路相關測試時適用。規則（`Dio` 只在這裡建、
攔截器順序、重試只在這裡、網域與轉址、網路紀錄欄位）與閘門見 `app/AGENTS.md` § 網路；
為什麼這樣做，見 ADR 0012 §決定 1–2、ADR 0013 §決定 2、4。這裡只寫怎麼做。

## 目錄

```
lib/core/network/
  source_http_client.dart  # SourceHttpClientFactory、SourceHttpClient、SourceRequest、SourceResponse、RequestCancelled
  interceptors.dart        # part：五個攔截器、每次送出的狀態 _Attempt、只收自己 host 的 cookie jar
  auth.dart                # AuthRequirement、decideAuth、CredentialSource、NoCredentials
  allowed_hosts.dart       # AllowedHosts：manifest 網域比對（請求與 cookie 的 Domain 共用）
  request_throttle.dart    # RequestThrottle：併發上限＋最小間隔
  media_headers.dart       # mediaRequestHeaders：媒體請求只留的 header
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

## 媒體 header

媒體 client 延到 M6。播放後端（PR 10）拿到插件給的串流 headers 時先過
`mediaRequestHeaders`，再交給 just_audio／media_kit。要多放一個 header 時改
`mediaHeaderNames`，並在 `media_headers_test.dart` 加一個會留與一個不會留的案例。

## Quality Check

- `test/core/network/` 全綠；新行為在對應群組有案例。
- `lib/core/network/` 沒有 import 上層（`fmp_layer_imports`）、沒有網址字面值。
- 改了網路紀錄的欄位：`app/AGENTS.md` § 網路與 `network log` 群組一起改。
