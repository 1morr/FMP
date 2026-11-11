# 09: 插件契約測試與 fixture 錄製

**What to build:** 每個插件都套同一套契約測試，用錄好的 fixture 重播音源的回應，不連網就能證明插件的每個插件能力照宿主 API 的約定回傳。附錄製工具：手動執行時打真實音源，寫檔前經過遮蔽函式。這張票讓 bilibili 的搜尋能力納入契約測試，並加一條手動執行的 `live` 冒煙測試。

讀：plan §3；ADR 0038〈如何確認〉；brief §5.3、§14；`AGENTS.md`〈公開 repo〉；票 08 的 Comments；spec〈共同規則〉

**Blocked by:** 08

**Status:** done

- [x] 契約測試依插件宣告的插件能力自動套用：插件宣告了搜尋，就跑搜尋的契約；新增插件不用改契約測試本身。
- [x] fixture 重播時零聯網；fixture 對不上請求時測試直接失敗並說明哪個請求沒有 fixture。
- [x] 錄製工具寫檔前經過票 06 的遮蔽函式；檢查提交的 fixture 不含 cookie、token、簽名網址的值，造一份含敏感值的 fixture 證明會紅。
- [x] bilibili 搜尋的 fixture 已錄製並提交，契約測試通過。
- [x] `live` 冒煙測試：bilibili 搜尋一條，預設跳過；手動執行一次並貼輸出。錄製與冒煙測試的指令寫進 `AGENTS.md` 或 plan §3。
- [x] `dart run tool/check.dart` 完整版綠燈。

## Comments

### 做法

- 工具都在 `app/test/support/plugin_fixtures.dart`，三個入口共用：
  - 契約測試 `test/plugins/plugin_contract_test.dart`（每次跑）。
  - 錄製 `test/plugins/record_plugin_fixture_test.dart`（`live` tag）。
  - 冒煙測試 `test/plugins/plugin_live_test.dart`（`live` tag）。
  - 自己的測試在 `test/support/plugin_fixtures_test.dart`。指令寫在 plan §3，`AGENTS.md`〈目錄〉加了一句指過去。
- fixture 放在插件目錄裡：`app/plugins/<id>/fixtures/<插件能力>/<案例>.json`。這樣「新增音源等於新增一個插件目錄」（ADR 0038），連同它的案例。plan §1.2 已補上這一層。fixture 不列進 `pubspec.yaml` 的 `assets`，不會打包進 App。
- 格式照 VCR 的 cassette，也就是一串請求與回應，再加上呼叫插件能力的參數 `input` 和錄製日期。「錄製模式」的做法參考 nock back 與 Polly.js：用環境變數 `FMP_RECORD=<id>/<插件能力>/<案例>` 指定要錄哪個案例，一次只錄一個（事實 F2 的匿名風控）。新案例先建一個只有 `{"input": …}` 的檔。
- 錄製沒有寫成 `tool/` 底下的 Dart 腳本。原因是 fjs 依賴 Flutter，`dart run` 跑不動，而且原生庫要靠 `loadFjsForTests()` 才載得進來；所以錄製工具用 `flutter test` 跑。
- 契約自動套用：從 manifest 讀出插件宣告的能力，各插件能力的契約寫在 `checkContract` 的 switch 裡。新增 `PluginCapability` 的值時這個 switch 不完整，會編譯不過。
- 以下情況契約測試都會紅：
  - 宣告了插件能力卻沒有案例。
  - `fixtures/` 底下有沒宣告的插件能力目錄（防打錯字）。
  - 錄了卻沒用到的請求（VCR 的 `allow_unused_http_interactions: false`）。
- 重播比對：用「方法加遮蔽後的網址」比對（`redact()` 對遮過的文字結果不變），每筆只用一次。對不上的請求列成 `no fixture for GET <網址>`，插件因此丟的錯不重複列出。
- 遮蔽：`RecordingHttp` 收到回應時，網址、header、內文都先經 `redact()`，原始值不留在記憶體的 fixture 裡。回應 header 只留宿主會讀的 `content-type`、`location`：`set-cookie` 和 CDN 的追蹤 header 宿主用不到，又可能帶 IP。請求 header 不錄，所以插件本地產生的 buvid 指紋不會進檔案。
- 敏感值檢查（`unredactedValues`）：fixture 的每個字串都要是遮蔽函式的不動點，整份文字也要是。整份文字那層抓 JSON 鍵就是敏感名稱的情況（例如 `"set-cookie": "…"`）和非字串值；字串那層抓回應內文裡跳脫過的 JSON。錄製前後各查一次：錄製工具寫檔前查，契約測試對每份提交的 fixture 也查。
- search 的契約比 `host.d.ts` 嚴一點：錄下的案例要有結果。空陣列在宿主 API 是合法的，但錄一個沒結果的案例證明不了轉換。之後要測「查無結果」時，再讓案例自己宣告預期。
- `realHttpClient()`（`test/support/no_network.dart`）在 zone 裡建一個真的 `HttpClient`，不動全域的防線。插件的請求經 fjs 的 bridge 回到 Dart，不一定跑在測試的 zone 裡，所以 client 要在建立時就決定好。
- 沒有改 App 的程式（`lib/`、插件），只動了測試和 fixture，所以沒有在四平台手動實跑；完整閘門照樣跑了四平台。

### 驗證

- 雙向變異（每次改完都還原，再跑一次轉綠）：
  - 拿掉 `unmatched` 的回報：「names the request that has no fixture」紅。
  - 關掉字串那層檢查：body 裡的 token、簽名網址兩條紅。
  - 關掉整份文字那層：cookie header、input 裡的 token 兩條紅。
  - 錄製時不遮內文：RecordingHttp 那條紅。
  - 格式化（壓成一行）以及含 `design`、`assign`、`tokens_left` 的內容：保持綠。
- 在真的 fixture 上做端到端變異：
  - 塞進 `"set-cookie": "SESSDATA=…"`：`has no secrets` 紅，回報行號。
  - 把錄下的網址改成 `keyword=lemonade`：契約紅，列出 `no fixture for GET …keyword=lemon` 與 `unused fixture request …keyword=lemonade`。
- 錄製（2026-11-12，匿名、一次）：

```
$ FMP_RECORD=bilibili/search/lemon flutter test --run-skipped --tags live test/plugins/record_plugin_fixture_test.dart
00:00 +0: record the plugin fixture named by FMP_RECORD
recorded 1 request(s) into plugins/bilibili/fixtures/search/lemon.json:
  GET https://api.bilibili.com/x/web-interface/search/type?search_type=video&page=1&keyword=lemon -> 200
00:00 +1: All tests passed!
```

  - 提交前人工看過內容：沒有 IP，沒有被遮掉的值。內文是公開的搜尋結果，20 筆影片，有標題、UP 主名稱與 mid、封面網址。
- `live` 冒煙測試（手動，匿名、一次）：

```
$ flutter test --run-skipped --tags live test/plugins/plugin_live_test.dart
00:00 +0: bilibili search against the real source
bilibili search {query: lemon}:
  GET https://api.bilibili.com/x/web-interface/search/type?search_type=video&page=1&keyword=lemon -> 200
00:00 +1: All tests passed!
```

  - 不加 `--run-skipped` 時，兩支 `live` 測試都跳過（`flutter test test/plugins/`：`+73 ~2`）。

- 完整閘門（`dart run tool/check.dart`，commit b2c0dd6a），退出碼 0：

```
ok   i18n (slang)
ok   codegen (build_runner)
ok   format
ok   analyze
ok   test
ok   schema snapshot (drift)
ok   doc gate
ok   build macos
ok   build ios
ok   build android
ok   lock shared devices
ok   build windows
ok   integration_test macos: integration_test/app_test.dart
ok   integration_test macos: integration_test/plugin_search_test.dart
ok   integration_test ios: integration_test/app_test.dart
ok   integration_test ios: integration_test/plugin_search_test.dart
ok   integration_test android: integration_test/app_test.dart
ok   integration_test android: integration_test/plugin_search_test.dart
ok   integration_test windows: integration_test/app_test.dart
ok   integration_test windows: integration_test/plugin_search_test.dart
ok   unlock shared devices
ok   plugin bundles (esbuild)
```

### code-review（33e48763 起）

已處理：
- 對不上的請求原本回報兩次（一次是請求本身，一次是插件因此丟的錯），現在只列一次。
- live 和錄製重複建立真實網路的程式，抽成 `liveRecording()` 與 `RecordingHttp.summary`。
- `FMP_RECORD` 格式錯、插件或插件能力不存在時，給明確的訊息。
- 檢查器的測試不再寫死行號。
- 重播比對的限制寫進 `FixtureReplay` 的註解。

未處理：
- **要擁有者確認**：fixture 的回應內文原樣留著 20 位 B 站 UP 主的名稱、mid 與頭像網址。這些是匿名搜尋拿到的公開資料，不是擁有者的個資，遮蔽函式本來就不處理。但 `AGENTS.md`〈公開 repo〉寫的是「不含個人資訊：使用者名稱……」，沒限定是誰的名稱。如果擁有者不接受，錄製時要把回應裁成插件會讀的欄位，重錄。
- 重播不比對請求 header 與 body。插件改了 Referer、UA 或 cookie，契約測試抓不到，這部分由 `bilibili_plugin_test.dart` 的單元測試守。網址裡每次都變、又不遮的參數（WBI 的 `wts`、`w_rid`）會讓重播永遠對不上；票 10 以後用到 WBI 的插件能力時要決定怎麼比對（例如比對時忽略這兩個參數）。
- `realHttpClient()` 沒有東西限制只能在 `live` tag 的檔案裡用。目前只有 `liveRecording()` 呼叫它；要守的話，在依賴規則那類測試加一條。
- 「有 `manifest.json` 的目錄就是插件」又多了一份（`pluginDirectories`）。`plugin_assets_test.dart` 沒改用它：那個測試要在 `dist/` 缺檔時回報缺什麼，`pluginDirectories` 遇到缺檔會直接讀檔失敗。
- 「暫存目錄加 `Log.open`」的 setUp 在測試檔裡各寫一次。沿用既有的寫法，沒抽出來。
- plan §3 寫進了格式（VCR cassette）、只留哪些回應 header 這類做法。這些是這張票的實作，不是新的決定；擁有者看過後覺得要改，照常改。
