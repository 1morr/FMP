# 測試（`app/test/`）

`app/` 的每個測試都適用。哪種改動跑哪些指令見 `app/AGENTS.md` § 驗證；零聯網與身分
的規則本身也寫在那裡，這裡只寫怎麼寫測試。

## 分層（ADR 0015 §決定 1）

測試守契約與使用者看得到的行為，不守實作細節；行為變更同一個 PR 補測試，用能證明它
的最低層。

| 層 | 用在 | 目前的例子 |
|---|---|---|
| 單元 | 純邏輯、平台層實作（注入路徑與 callback，在暫存目錄上跑） | `test/platform/app_data_directory_test.dart` |
| widget | 畫面；依賴以建構子或 provider override 注入 | `test/app/fmp_app_test.dart` |
| 建置設定 | 原生身分：能執行就執行（`cmake -P`），不能就解析設定檔並附變異案例 | `test/identity/` |
| 插件契約、整合、golden | M1 PR 9、PR 13 與設計系統元件加入時再寫 | — |

- 碰資料庫的測試用 `test/support/memory_database.dart`，寫法見
  `.trellis/spec/app/data/index.md` § 測試。
- 正式程式碼不留測試掛鉤（`*ForTesting`、`@visibleForTesting` 的後門）；要替換的東西
  經建構子或 provider 注入。
- 不設覆蓋率門檻。

## 零聯網

`test/flutter_test_config.dart` 讓建立真實 `HttpClient` 直接拋 `StateError`；
`dart_test.yaml` 讓 `live` tag 預設跳過。

- 需要 HTTP 的程式碼注入假的 client 或 adapter，不去碰網路。
- 真的要打真實 API 的測試：標 `tags: 'live'`，並在測試裡自己放行：

  ```dart
  final class _AllowNetwork extends HttpOverrides {}

  test('...', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      // 這個 zone 內建立的 HttpClient 是真的
    }, _AllowNetwork());
  }, tags: 'live');
  ```

  執行：`flutter test --run-skipped --tags live`。
- `flutter_test_config.dart` 先初始化測試 binding 再設 `HttpOverrides.global`：binding
  初始化時會換上 flutter_test 自己的假 client（回 400、不報錯），順序反過來這道防線
  就失效。

## 讀原始碼或設定檔的測試

優先寫行為測試。非讀原始碼不可時（例如 Gradle 設定在 CI 上跑太慢），同一個測試檔要有
兩個變異案例：造一個違規證明解析抓得到，改一次無關的格式或命名證明結果不變。例子：
`test/identity/android_identity_test.dart` 的 `parser mutations`。

## Quality Check

- `dart format --output=none --set-exit-if-changed .`、`flutter analyze` 乾淨。
- 新的讀原始碼測試有兩個變異案例。
- 沒有新的測試直接連網；`live` 測試在自己的 zone 放行。
