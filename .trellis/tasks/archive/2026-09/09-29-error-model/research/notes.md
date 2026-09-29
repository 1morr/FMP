# 錯誤模型與重試策略：查證紀錄

查證日期：2026-09-29。RFC 以 `curl https://www.rfc-editor.org/rfc/rfc9110.txt` 取得全文逐段讀；
AWS 文章的公式在圖片裡，下載原圖確認。

## 1. RFC 9110（HTTP Semantics）

來源：https://www.rfc-editor.org/rfc/rfc9110.html

- **§9.1**：「The method token is case-sensitive」，標準方法慣例全大寫。
  → `isIdempotent` 逐字比對，`get` 不算 `GET`；比對不上時往「不重試」的方向錯。
- **§9.2.1**：GET、HEAD、OPTIONS、TRACE 是 safe。
- **§9.2.2**：「Of the request methods defined by this specification, PUT, DELETE, and safe
  request methods are idempotent.」；「A client SHOULD NOT automatically retry a request with
  a non-idempotent method unless it has some means to know that the request semantics are
  actually idempotent, regardless of the method」。
  → 冪等表：GET、HEAD、OPTIONS、TRACE、PUT、DELETE。PRD 沒列 TRACE，照 RFC 加入。
  POST、PATCH、CONNECT 不是。
  → 同一段允許「確知語意冪等」的 POST 重試。YouTube innertube 與網易的查詢 API 都是 POST，
  只看方法的話這些查詢永遠不重試。要不要讓音源標記「這個 POST 冪等」留給 PR 8 決定。
- **§10.2.3 Retry-After**：`Retry-After = HTTP-date / delay-seconds`、`delay-seconds = 1*DIGIT`
  （非負十進位整數秒）。範例 `Fri, 31 Dec 1999 23:59:59 GMT`、`120`。
- **§5.6.7 Date/Time Formats**：
  - 收方「MUST accept all three HTTP-date formats」：IMF-fixdate
    （`Sun, 06 Nov 1994 08:49:37 GMT`）、RFC 850（`Sunday, 06-Nov-94 08:49:37 GMT`）、
    asctime（`Sun Nov  6 08:49:37 1994`，一位數的日以空白補齊）。
  - 「HTTP-date is case sensitive」。
  - RFC 850 的兩位數年份：「MUST interpret a timestamp that appears to be more than 50 years
    in the future as representing the most recent year in the past that had the same last two
    digits」。

## 2. `dart:io` 的 `HttpDate.parse`

讀 Flutter 3.47.5 內附 Dart SDK 的 `lib/_http/http_date.dart`：

- 三種格式都解析，但比 ABNF 寬鬆：星期與月份不分大小寫、年份 1–4 位數都收。
- asctime 分支在讀完月份與空白後直接 `source.codeUnitAt(index)`，沒有檢查長度：
  `Tue Sep ` 這種截斷的值會拋 `RangeError`，不是 `HttpException`。
- RFC 850 的兩位數年份原樣回傳（`94` 年），沒有套 §5.6.7 的規則。

→ `parseRetryAfter` 先以照 ABNF 寫的樣式比對三種格式，通過的才交給 `HttpDate.parse`，
所以不用 catch；兩位數年份自己補世紀。

## 3. AWS〈Exponential Backoff And Jitter〉

來源：https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/
（Marc Brooker，2015-03-04）

- Capped exponential backoff：`sleep = min(cap, base * 2 ** attempt)`（文中圖 3）。
- Full Jitter：`sleep = random_between(0, min(cap, base * 2 ** attempt))`（圖 6）。
  文中比較後，Full Jitter 與 Decorrelated Jitter 工作量都遠低於無抖動；Full Jitter 呼叫次數較少。
- → `delayFor`：`attempt` 從 0 起算（原本那次失敗後的第一次重試），預設 base 500ms、cap 8s。
  `Random` 由呼叫端傳入。

## 4. 實作時的決定

- **原始 error 與 stackTrace 設成函式庫私有**：`report` 以 `part` 放在同一個函式庫裡才讀得到；
  UI 拿不到原文，這比「列出公開 getter」的測試更強，是型別層面的保證。`toString()` 不含原始 error。
- **型別名稱不用 `runtimeType`**：release 開混淆時會變，log 與 Debug 頁的篩選就對不上；
  改以 exhaustive `switch` 寫死。
- **欄位名 `pluginId` 而非 PRD 的 `sourceId`**：`TrackKey` 的 `sourceId` 是曲目在音源上的 id，
  資料層（`PluginStorage`）也以 `pluginId` 表示音源 id。
- **公開成員測試**用 `package:analyzer` 的 `parseString`（只 parse，不 resolve）：它已經在 workspace
  裡（`fmp_lints` 釘 13.3.0），加成 app 的 dev dependency 只改 lock 的一個標記。flutter test 沒有
  `dart:mirrors`；以正規表示式掃原始碼抓不到沒寫型別或跨行的宣告。
