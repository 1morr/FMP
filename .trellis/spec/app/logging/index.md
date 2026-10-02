# Log 與遮蔽（`app/lib/core/logging/`、`app/lib/core/redaction/`）

寫 log、加遮蔽名單、改 log 檔時適用。規則（門面唯一、遮蔽函式唯一、log 檔格式）與
閘門見 `app/AGENTS.md` § Log 與遮蔽；為什麼這樣做，見 ADR 0011、ADR 0025 §決定 3。
這裡只寫怎麼做。

## 目錄

```
lib/core/logging/
  log.dart              # 門面 Log：遮蔽 → talker（歷史 1,000 筆、console、分派到檔案）
  log_record.dart       # LogLevel、LogRecord（JSON Lines 一行）、parseLogLines
  log_file.dart         # LogFile：排隊寫入、2MB × 3 輪替、7 天保留、失敗計數
  uncaught_errors.dart  # routeUncaughtErrors：FlutterError／PlatformDispatcher → 門面
lib/core/redaction/
  redaction_lists.dart  # 內建名單：header、鍵名、媒體 CDN（MediaCdn）
  redactor.dart         # Redactor：redact、redactObject、redactValue、addRules、registerSecret
```

## 寫一筆 log

```dart
log.warning(
  'Search failed',
  tag: 'search',                         // 模組或音源 id
  error: error,                          // 原物件即可，門面會轉成遮蔽過的字串
  stackTrace: stackTrace,
  fields: {'status': 412, 'ms': 830},    // 遞迴遮蔽；非 JSON 值取遮蔽過的 toString()
);
```

- 訊息寫英文，比照 log 字串的慣例；會變的值放 `fields`，不要拼進訊息，Debug 頁（M3）
  才能依欄位篩選。
- 不要自己先遮再傳：門面一定會遮，重複遮沒有壞處但也沒有用。
- 網址、header、body 片段照原樣放進 `fields` 或 error，交給遮蔽函式；不要為了 log 另寫
  截斷或去 query 的函式（舊專案的 `redactStreamUrl` 就是這種第二條路）。
- `Log` 實例由 `main()` 建立。之後要在其他模組用，經 provider 或建構子注入，不另建實例。

## 加一個遮蔽名單項目

- 所有音源共用、或官方音源已知的：加在 `redaction_lists.dart` 的對應清單。
  - header 名稱（值整段遮）→ `builtInHeaderNames`；
  - 鍵名（`鍵=值`、`"鍵": "值"`、欄位的鍵）→ `builtInKeyNames`。比對不分大小寫，
    而且是「以名稱結尾」：加 `token` 就涵蓋 `access_token`，不必逐一列；
  - 媒體 CDN → `builtInMediaCdns`，`host` 涵蓋子網域，`signedQueryParameters` 列要去掉
    的參數，路徑本身帶簽章時設 `signedPath: true`。同一個網址符合多條規則（內建與插件
    追加的）時全部合併：參數取聯集，任一條 `signedPath` 為真就換路徑。
- 只有某個插件知道的：插件載入時呼叫 `Redactor.addRules(...)`（M1 的 B 站插件在 PR 9）。
  名單只增不減。
- 內建名單變嚴格，插件庫（`1morr/fmp-plugins`）既有的 fixture 可能過不了契約測試的
  「再遮一次不變」掃描：同一個 PR 裡用新名單跑一次各插件的契約測試，紅了就重錄，或照
  遮蔽函式的輸出改那幾個值（例如拿掉 `buvid=***`），在插件庫另開 PR。
- 帳號的實際憑證值：登入或載入帳號時 `registerSecret`，登出時 `unregisterSecret`
  （帳號層在 M3）。少於 4 個字元的值會被拒絕。
- 每加一項，在 `test/core/redaction/redactor_test.dart` 加一個「會遮」的案例；名稱
  短或常見（例如 `e`、`n`）時，另加一個不該遮的相鄰案例，確認不會把一般文字吃掉。
- 測試只用明顯的假值（`FAKE_SESSDATA_123`），不得寫入真實憑證。

## 改遮蔽的樣式（`redactor.dart`）

- 會重複的部分只寫單一字元類別（`[^"&;\s]+`）或有上限的次數（`{0,32}`）。
  `(?:a|b)+` 這種「分組＋重複」在 irregexp 每一輪佔一格回溯堆疊，1MB 的值就
  Stack Overflow，整筆 log 會被門面丟掉（`redactor_test.dart` 的 `very long input`）。
- 解不開、解析失敗時要往多遮的方向走，不能原樣放行（例如編碼過的網址只解 ASCII
  跳脫，不用會拋錯的 `Uri.decodeComponent`）。
- 每個新寫法在 `redactor_test.dart` 加「會遮」與相鄰「不該遮」的案例。

## log 檔

- 欄位：`time`（UTC ISO 8601）、`level`（`debug`／`info`／`warning`／`error`）、`tag`、
  `message`，有值才寫的 `error`、`stackTrace`、`fields`。這是持久化格式，改了就是改
  資料格式：`log_record_test.dart` 的 `stored format` 會紅，要一起想舊檔怎麼讀。
- 讀檔一律用 `parseLogLines`：壞行略過、不中止。
- 寫入走 `LogFile.write`（不等待）；要讀檔或匯出前先 `await flush()`。
- 會刪、改名 log 檔的操作（保留期限 `deleteExpired`，之後 Debug 頁的「清除 log」）寫成
  `LogFile` 的方法、排進它的寫入佇列，不從外面直接動 `logs/`：輪替也在那條佇列上改名，
  不排隊就會交錯。錯誤經回傳的 future 交給呼叫端，佇列本身不能帶著錯誤往下傳（否則之後
  的寫入全被跳過）；`log_file_test.dart` 的 `retention` 群組是例子。

## 測試

- 門面的測試在 `Directory.systemTemp` 下建 `LogFile`，斷言時先 `flush()` 再讀檔。
- 驗遮蔽時同時看記憶體歷史（`log.history`）與 log 檔，兩個出口都要沒有原值。
- 要改 `FlutterError.onError` 或 `PlatformDispatcher.onError` 的測試，在斷言之前就還原；
  用 `PlatformDispatcher.instance`，flutter_test 的 `TestPlatformDispatcher.onError`
  setter 不會寫入。

## Quality Check

- `lib/core/` 沒有 import `platform/`、`data/`、`settings/` 等上層（`fmp_layer_imports`）；
  路徑由 `main()` 傳入。
- 新的遮蔽名單項目有測試；新的 log 出口有「假憑證不出現」的測試。
