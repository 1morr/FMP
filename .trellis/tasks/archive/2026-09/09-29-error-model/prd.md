# 錯誤模型與重試策略（M1 PR 7）

父任務：`../09-28-m1-skeleton-tracer`（implement「7.」）。

依據：
- ADR 0013 §決定 1–4：分類、共同欄位、轉換位置、傳遞、重試只有一層；
- ADR 0011 §決定 5：錯誤歷史經門面寫入；
- ADR 0023 §決定 1：`Toaster.error` 只收 `AppError`，在 PR 12 使用。

## 做什麼

1. **`lib/core/errors/app_error.dart`**：sealed `AppError`，十個子類。
   - 子類：
     - `NetworkError`、`RateLimited`、`AuthRequired`、`CredentialInvalid`、`VerificationRequired`；
     - `Unavailable`：附原因 enum，地區、版權、會員、年齡、只有試聽；
     - `NotFound`、`ParseError`、`Unsupported`、`UnexpectedError`。
   - 共同欄位：
     - 音源 id（可空，網路層以外的錯誤可能沒有）；
     - `retryable`；
     - `retryAfter`（`Duration?`）；
     - 使用者訊息：i18n key（型別化的 enum 或常數）與參數；
     - `expected`：預期內，或視為 bug；
     - 原始 error 與 stackTrace：只進 log；
     - 網路紀錄 id（可空，PR 8 填入）。
   - 子類的預設 `retryable`：`NetworkError`、`RateLimited` 為真，其他為假。音源可以在建構時覆寫。
   - **UI 不顯示原文**（ADR 0013 §如何確認）：使用者訊息只能從 i18n key 取得，`AppError` 沒有可以直接顯示的字串欄位。
     - `toString()` 只給 log 用，而且原始 error 經遮蔽函式處理後才輸出。
     - i18n key 在 PR 12 接上 slang；本 PR 定型別與清單，每個子類一個預設 key。
     - key 的清單要在 PR 12 能直接對應到 slang 的 key，命名照 ADR 0013 §決定 5 的類別表。
2. **錯誤歷史**：`lib/core/errors/report_error.dart`（名稱可調），一個函式把 `AppError` 經 log 門面寫入（ADR 0011 §決定 5）。
   - 層級：`expected` 為真時是 `warning`，否則是 `error`。
   - 結構化欄位：錯誤類型、音源 id、網路紀錄 id、`retryable`、`retryAfter`。
   - error 與 stackTrace 交給門面遮蔽。
3. **包裝未知例外**：`AppError.wrap(Object error, StackTrace stack, {String? sourceId})`。
   - 已經是 `AppError` 就原樣回傳；
   - 其他一律包成 `UnexpectedError`，`expected` 為假。
   - 音源邊界（PR 9）用它。
4. **重試策略**：`lib/core/errors/retry_policy.dart`，純函數，網路層在 PR 8 使用。
   - `isIdempotent(method)`：`GET`、`HEAD`、`OPTIONS`、`PUT`、`DELETE` 為真，`POST`、`PATCH` 為假（RFC 9110 §9.2.2）。
   - `shouldRetry(AppError, attempt, method, policy)`：同時滿足三個條件才重試：
     - 冪等；
     - 錯誤的 `retryable` 為真；
     - 還沒超過次數上限（預設 2，音源可宣告）。
   - `delayFor(attempt, error, random)`：
     - 有 `retryAfter` 時用它，上限依策略，預設 60 秒，超過上限就不重試；
     - 否則指數退避加全抖動：`random(0, min(cap, base × 2^attempt))`，預設 base 500ms、cap 8s（AWS〈Exponential Backoff And Jitter〉的 Full Jitter）。
   - `parseRetryAfter(String)`：支援秒數與 HTTP-date（RFC 9110 §10.2.3），無效值回 `null`。
   - 併發上限與最小請求間隔屬於網路層的排程，在 PR 8 做；本 PR 只定策略的資料型別（`RetryPolicy`、`RateLimitPolicy` 的欄位），不實作排程。
5. **測試**：
   - 每個子類的預設 `retryable` 與 `expected`；
   - `wrap` 對 `AppError` 與一般例外的行為；
   - `report` 的層級、結構化欄位，以及原始 error 中的假憑證經門面後被遮蔽（用 PR 6 的門面與假 sink）；
   - 重試：
     - 冪等表；
     - `shouldRetry` 的各組合；
     - Full Jitter 的上下界（固定 `Random` 種子）；
     - `Retry-After` 秒數、日期、無效值、超過上限；
   - 型別層面：沒有可以直接顯示的字串欄位。用一個測試列出 `AppError` 的公開 getter，斷言沒有 `message`、`displayText` 之類欄位（在測試檔內做雙向變異）。
6. **文件**：
   - `app/AGENTS.md` 錯誤段：
     - 音源邊界以上只看得到 `AppError`；
     - 被處理的錯誤一律經 `report` 寫入；
     - 重試只有網路層一層，Riverpod 重試已關；
     - 禁止空 catch（`fmp_no_empty_catch`）。
   - `.trellis/spec/app/errors/index.md`（繁中）：怎麼加一個錯誤類型或 i18n key，音源怎麼寫對應表（PR 9 用）。

## 驗收

- [ ] `app/`：
  - format 通過；
  - codegen 沒有變動；
  - `dart analyze --fatal-infos`、`flutter analyze` 零問題；
  - `flutter test` 全綠；
  - 哨兵通過。
- [ ] 不是使用者看得到的改動，不需要實機驗證。
