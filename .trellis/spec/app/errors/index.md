# 錯誤（`app/lib/core/errors/`）

丟錯誤、接錯誤、加錯誤類型或 i18n key、寫音源的錯誤對應表時適用。規則（音源邊界以上
只看得到 `AppError`、錯誤一律經 `report`、重試只有網路層、沒有可顯示的字串）與閘門
見 `app/AGENTS.md` § 錯誤；為什麼這樣分類，見 ADR 0013。這裡只寫怎麼做。

## 目錄

```
lib/core/errors/
  app_error.dart     # sealed AppError 與十個子類、ErrorMessageKey、UnavailableReason、wrap
  report_error.dart  # part：Log 的 report 擴充，唯一讀得到原始 error 的地方
  retry_policy.dart  # RetryPolicy、RateLimitPolicy、isIdempotent、shouldRetry、delayFor、parseRetryAfter
```

## 丟與接

```dart
// 音源內：以對應表轉好再丟，原始例外放 cause。
throw RateLimited(
  pluginId: pluginId,
  retryAfter: parseRetryAfter(header, now: receivedAt),
  cause: response,
  stackTrace: StackTrace.current,
);

// 音源邊界：其他例外一律包起來。
} on Object catch (error, stackTrace) {
  throw AppError.wrap(error, stackTrace, pluginId: pluginId);
}

// 使用者動作的呼叫端：寫錯誤歷史，再交給呈現層（Toaster 在 PR 12）。
} on AppError catch (error) {
  log.report('Search failed', error, tag: 'search');
}
```

- `report` 的 `message` 寫失敗的動作（英文），會變的值不拼進去；`tag` 是模組或音源 id。
  層級由 `expected` 決定，不自己選。
- 背景工作也 `report`，但不跳 toast，只更新對應畫面的狀態（ADR 0013 §決定 5）。
- 不要把 `AppError` 直接傳給 `log.error(error: ...)`：它的 `toString()` 沒有原始 error，
  那筆 log 就少了原因。
- Riverpod provider 讓 `AppError` 直接拋出，`AsyncValue.error` 承接；UI 以 exhaustive
  `switch` 分類呈現，不用 `default`／`_`，新增子類時編譯器才會指出要補的地方。

## 音源的錯誤對應表（PR 9 起）

每個音源在自己的目錄內寫一個函式，把回應轉成 `AppError`；網路層已把傳輸錯誤轉成
`NetworkError`，音源只處理有回應的情況。

- 依序判斷：HTTP 狀態碼 → 音源的業務錯誤碼 → 回應形狀不對（`ParseError`）。
- 「憑證無效」只看音源明列的回應（ADR 0012 §決定 5）；網路錯誤、限流、風控碼不算。
- 限流帶 `Retry-After` 時用 `parseRetryAfter` 填 `retryAfter`；`now` 用收到回應的時間。
- 預設 `retryable` 不合用時才覆寫（例如某個 5xx 業務碼其實可重試）。覆寫只決定「錯誤
  可不可以重試」，請求是否冪等由網路層另外判斷。
- `messageArgs` 只放數字、enum 之類的值；伺服器的訊息原文放 `cause`，只進 log。
- 每一列對應表配一個以錄下的錯誤回應 fixture 寫的契約測試，斷言轉出的子類
  （ADR 0013 §如何確認）。

## 加一個錯誤類型

1. `app_error.dart` 加一個 `final class ... extends AppError`，照現有子類寫建構子：
   `retryable` 的預設、`messageKey` 的預設，`super._(expected: ...)`。
2. `_typeName` 加一列。型別名稱是 log 檔的持久化值，不用 `runtimeType`（release 混淆
   後會變）。
3. 編譯器會指出每個 exhaustive `switch`（呈現層、`test/core/errors/app_error_test.dart`
   的 `_defaults`），逐一補上。
4. 它需要新的使用者訊息時，照下一節加 key。
5. 測試：`app_error_test.dart` 的 `_samples` 加一個樣本，把 `hasLength(10)` 改成新的數目。

先想清楚能不能用既有類別加一個 `UnavailableReason`：只是「取不到的原因」不同，就加
原因，不加類別。

## 加一個 i18n key 或原因

- `ErrorMessageKey` 一個值對應 ADR 0013 §決定 5 類別表的一列，名稱就是 slang 的 key
  （PR 12 起在 `errors.` 之下）；加值要同時加翻譯，改名等於改翻譯檔的 key。
- `UnavailableReason` 加值時，同時加曲目上標示原因的翻譯（PR 12 起）。`report` 以
  `reason.name` 寫進 log，改名就是改 log 的值。

## 加欄位

`app_error.dart` 函式庫（含 `report_error.dart`）的公開成員是審過的清單：
`test/core/errors/app_error_surface_test.dart` 的 `_reviewedSurface`，涵蓋類別、enum、
extension 的成員（含靜態）與頂層宣告。加欄位、方法或頂層函式時一起改它；型別是
`String`、`Object`、`dynamic` 或沒寫型別的，測試會擋，除非列進 `_allowedTextMembers`
並寫出為什麼不是給使用者看的文字。原始 error 這類只給 log 的東西用私有欄位，在
`report_error.dart` 讀。

## 重試（網路層，PR 8 起）

```dart
for (var attempt = 0; ; attempt++) {
  try {
    return await send();
  } on AppError catch (error) {
    if (!shouldRetry(error, attempt: attempt, method: method, policy: policy)) rethrow;
    final delay = delayFor(error, attempt: attempt, policy: policy, random: random);
    if (delay == null) rethrow;
    await wait(delay);
  }
}
```

- `attempt` 是已經重試過的次數，原本那次失敗後為 0。
- `random`、`now`、等待都從外面注入，測試才能固定；`lib/` 不留測試掛鉤。
- `RetryPolicy`、`RateLimitPolicy` 由音源在 manifest 宣告（ADR 0014 §決定 3），沒宣告就用
  `const RetryPolicy()`。
- 冪等只看 HTTP 方法（RFC 9110 §9.2.2），方法名稱分大小寫。

## Quality Check

- `test/core/errors/` 全綠；新的子類、欄位、原因都有對應的測試或清單更新。
- `lib/core/errors/` 沒有 import 上層（`fmp_layer_imports`）；`dart:io` 只用 `HttpDate`。
