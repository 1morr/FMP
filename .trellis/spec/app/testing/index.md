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
| 插件契約 | 插件目錄的 `checks.json` 以 fixture 重播（寫法見 `.trellis/spec/app/plugins/index.md` § 寫檢查案例與 fixture） | `test/plugins/contract/contract_test.dart` |
| 整合 | 只挑 ADR 0015 列的情境與只能在真引擎上看的事，寫法見下方「整合測試」 | `integration_test/install_search_play_test.dart` |
| golden | 設計系統共用元件（寫法見 `.trellis/spec/app/ui/index.md`） | `test/ui/player/player_bar_golden_test.dart` |

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

## 整合測試（`integration_test/`）

在建出來的 App 裡跑（`flutter test integration_test/<檔> -d <裝置>`），預設是 dev flavor，
測試插件等 dev 的 asset 讀得到（`rootBundle`）。

- 開頭 `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`。`test/flutter_test_config.dart`
  只套用在 `test/` 底下：要零聯網就在 `main()` 自己設
  `HttpOverrides.global = NoNetworkHttpOverrides()`（從那個檔案 import），QuickJS 不用預先載入
  （App 內附原生庫）。
- 要從 App 根開始的，照 `main()` 注入：`appProviderScope` 包 `FmpApp`，override 資料庫、資料目錄、
  log、遮蔽函式、平台宣告。資料庫用 `openAppDatabase` 開在 `Directory.systemTemp` 底下的暫存資料
  目錄（和 App 一樣是檔案），要驗「重新啟動」就拆掉 App（`pumpWidget(SizedBox.shrink())`）、關庫、
  再開一次。
- 播放後端用 `test/playback/fake_audio_backend.dart`（override `audioBackendProvider`，
  `ref.onDispose` 裡 dispose）：CI 的 runner 沒有音訊裝置，Linux 也還沒有後端。真後端只在
  `audio_backend_contract_test.dart`，實機手動跑。
- 等待用實際時間：插件在背景 isolate、資料庫在 drift 的 isolate。逐格 `tester.pump(50ms)` 直到
  條件成立、設上限（例子：`install_search_play_test.dart` 的 `_waitFor`）；畫面有轉圈時
  `pumpAndSettle` 不會結束。只維持一下子的狀態（例如一首 1 秒的播放）不要輪詢當下的值，
  慢的 runner 會整段錯過：先訂閱 stream 記下每次變動，再等紀錄裡出現。
- 輸入文字照 widget 測試寫（`enterText`、`testTextInput.receiveAction`）：整合測試的 binding 沒有
  註冊假的文字輸入，但這兩個不需要註冊。
- 找畫面上的字用插件回的資料（例如測試插件的曲名），不用介面字串：介面語言跟著機器的系統語言。
- 一次 `flutter test` 只跑一個檔案（桌面裝置的限制，見 `app/AGENTS.md` § 驗證）。新檔案要進 CI，
  在 `.github/workflows/ci.yml` 的 Linux 與 Windows 整合測試 job 各加一步。

## 讀原始碼或設定檔的測試

優先寫行為測試。非讀原始碼不可時（例如 Gradle 設定在 CI 上跑太慢），同一個測試檔要有
兩個變異案例：造一個違規證明解析抓得到，改一次無關的格式或命名證明結果不變。例子：
`test/identity/android_identity_test.dart` 的 `parser mutations`。

## Quality Check

- `dart format --output=none --set-exit-if-changed .`、`flutter analyze` 乾淨。
- 新的讀原始碼測試有兩個變異案例。
- 沒有新的測試直接連網；`live` 測試在自己的 zone 放行。
