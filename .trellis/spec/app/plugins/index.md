# 插件（`app/lib/plugins/`）

寫一個插件、改宿主 API、加 DTO 欄位或能力、寫插件相關測試時適用。規則（安裝檔格式、能力與匯出
一致、網域、全域只有 `fmp`、錯誤轉換、逾時、開發入口）與閘門見 `app/AGENTS.md` § 插件；為什麼
這樣做，見 ADR 0014。這裡只寫怎麼做。

## 目錄

```
lib/plugins/
  source_plugin.dart          # SourcePlugin：App 其他部分只認它
  source_dto.dart             # DTO v1 與 sourceDtoShapes（欄位表）
  json_shape.dart             # JsonShape、JsonFields：封閉物件的解碼
  script_source_plugin.dart   # ScriptSourcePlugin、ScriptPluginLoader（載入、匯出檢查）
  plugin_registry.dart        # pluginRegistryProvider：已載入的插件與各自的媒體 client
  manifest/
    plugin_manifest.dart      # PluginManifest、PluginCapability、hostApiVersion、manifestShapes
    plugin_file.dart          # PluginFile：從安裝檔標頭取出 manifest
  runtime/                    # 只有這裡 import flutter_js（實際只有 plugin_worker.dart）
    plugin_runtime.dart       # PluginRuntime（主 isolate）：spawn、訊息、宿主呼叫、看門狗、錯誤轉換
    plugin_worker.dart        # 背景 isolate：QuickJS、prelude、Promise 工作、crypto
    worker_protocol.dart      # 兩邊之間的訊息
    js_prelude.dart           # 建出 fmp 的 JS
    plugin_host.dart          # PluginHost（主 isolate）：網路、storage、憑證、log、hostApiShapes
    script_errors.dart        # 結構化錯誤 → AppError
  install/
    plugin_installer.dart     # PluginInstaller：解析 → 載入 → 寫入 → 註冊；installPrepared、remove
    dev_plugin_entry.dart     # dev 的開發入口
  repository/                 # 插件庫（ADR 0030）
    plugin_index.dart         # PluginIndex、PluginIndexEntry、PluginRejected／PluginRejection
    plugin_downloader.dart    # PluginDownloader：讀 index、下載並驗證（SHA、manifest 比對、checks）
    plugin_updates.dart       # updateStatus（semver）、addedAccess（新增的能力與網域）
  accounts/                   # 憑證與帳號（見 § 帳號）
    login_credentials.dart    # LoginCredentials：{cookies, extra?}
    credential_store.dart     # CredentialStore：secure storage 的憑證、狀態、遮蔽登記
    account_service.dart      # AccountService：登出、移除插件的帳號面
  types/fmp-plugin.d.ts       # 給插件作者的 TypeScript 型別

test/plugins/contract/        # 契約執行器（只在測試裡，理由見 PR 9b 的 research/notes.md）
  contract_runner.dart        # PluginDirectory、runContract／runCheck／recordContract
  checks.dart                 # checks.json、checkShapes、期望的比對
  fixture.dart                # fixture 格式、fixtureShapes、遮蔽、重播的網址比對
  fixture_adapters.dart       # ReplayAdapter、RecordingAdapter（dio 最底層的 adapter）
  credential_scan.dart        # fixture、log、串流 headers 的憑證檢查
  contract_test.dart          # 重播的入口（FMP_PLUGIN_DIR）
  record_test.dart            # 錄製（live 測試是真實連線的入口）
```

## 寫一個插件

```js
/* ==FMP Plugin==
{
  "id": "example",
  "name": "Example",
  "version": "1.0.0",
  "author": "you",
  "apiVersion": 1,
  "capabilities": ["search", "resolveStream"],
  "allowedHosts": ["api.example.com", "cdn.example.com"]
}
==/FMP Plugin== */

export async function search({ keyword, page }) {
  const response = await fmp.http.request({
    url: `https://api.example.com/search?q=${encodeURIComponent(keyword)}&p=${page}`,
  });
  if (response.status === 429) throw { fmpError: 'RateLimited' };
  if (response.status !== 200) throw { fmpError: 'ParseError', message: `HTTP ${response.status}` };
  const json = JSON.parse(response.body);
  return {
    items: json.list.map((item) => ({ sourceId: item.id, title: item.name, durationMs: item.ms })),
    hasMore: json.more,
  };
}

export async function resolveStream({ sourceId, cid, formats, quality }) {
  // 依 formats 挑平台能播的（順序已依使用者的格式偏好排過）、依 quality 挑碼率；
  // 找不到就拋 NotFound 或 Unavailable，不回空清單。
  return { candidates: [{ url: 'https://cdn.example.com/a.m4a', container: 'mp4', codec: 'aac' }] };
}
```

- 型別與每個欄位的限制看 `lib/plugins/types/fmp-plugin.d.ts`；物件多一個欄位就整個被拒收。
- 能力名稱＝匯出函式名稱。其他匯出（常數、helper）不影響。
- 狀態碼與業務錯誤碼在插件裡轉成結構化錯誤（`.trellis/spec/app/errors/index.md` § 音源的錯誤
  對應表）；`fmp.http.request` 自己丟的錯誤（網域不符、限流重試後仍失敗、傳輸錯誤）直接讓它往上拋。
- `quality`（`high`／`medium`／`low`）是使用者的音質偏好：選中的那一個放第一個候選，其他的排在後面
  當備援（B 站：依頻寬排，`medium` 取中間；備援先往下降，沒有更低的才往上）；沒給時自己決定。`formats` 的先後就是使用者的格式偏好，
  同一首有多種格式時照它排候選。
- 候選只有試聽片段（非會員之類）時回 `{ candidates: [...], previewOnly: true }`：宿主依使用者的
  「跳過試聽片段」跳過或照播並標「試聽」。連試聽都沒有就拋
  `{ fmpError: 'Unavailable', reason: 'previewOnly' }`。
- 要跨重啟的值（匿名 cookie 等）存 `fmp.storage`；`fmp.credentials.get()` 回 `{cookies, extra?}`（`FmpLoginCredentials`），沒登入、暫時讀不到或已失效時是 `null`；憑證的值是秘密，不要寫進 log 或 storage。
- 沒有 `setTimeout`、`fetch`、`require`，也不能 `import` 其他 module：一個檔案就是全部。
- 用 `fmp-test` 當範本：`app/test/fixtures/plugins/test_plugin/test_plugin.js`；會發請求的範本是
  `app/test/fixtures/plugins/http_test_plugin/`。

## 寫檢查案例與 fixture

插件目錄是契約檢查的單位（格式在 `fmp-plugin.d.ts` 的 `FmpChecks`、`FmpFixture`）：

```
<插件目錄>/
  <名稱>.js                     # 安裝檔，只能有一個
  checks.json                   # 每能力最多一條
  fixtures/<能力>/001.json …    # 該案例依序的請求與回應
```

```json
{
  "search": {
    "input": { "keyword": "tone", "page": 1 },
    "expect": { "minItems": 2, "nonEmpty": ["sourceId", "title"] }
  },
  "resolveStream": {
    "input": {
      "sourceId": "a1",
      "purpose": "playback",
      "formats": [{ "container": "mp4", "codec": "aac" }]
    },
    "expect": { "error": "Unavailable", "reason": "copyright" }
  }
}
```

- 網址自己帶期限的音源，在成功的 `resolveStream` 案例加 `"expiresAtPattern"`（一個擷取群組，擷取
  unix 秒；B 站是 `[?&](?:deadline=|hdnts=exp=)(\d+)`，JSON 裡反斜線要寫兩次）。執行器核對每個
  網址對得上的候選，`expiresAt` 要等於那個時間，而且至少要有一個候選對得上。期限參數被遮蔽名單
  拿掉的話這條會紅：先確認遮蔽名單（`redaction_lists.dart`）沒有遮它。
- 成功的案例盡量用錄的：`FMP_PLUGIN_DIR=<絕對路徑> flutter test --run-skipped --tags live
  test/plugins/contract/record_test.dart`（`app/` 內；真實連線，照 ADR 0027 §決定 2 回報）。
  那個能力原本的 fixture 整組重寫，但只在結果符合 `expect` 時寫（不符就不動原本的檔案並回報）；
  需要登入的案例錄不了（M1 沒有憑證，會以 `AuthRequired` 失敗）。
- 只重錄一個能力（錄製會跑 checks.json 的每一條）：把插件目錄複製到暫存處，在副本的
  checks.json 與 `fixtures/` 拿掉其他能力再錄，錄完只把那個能力的 `fixtures/<能力>/` 複製回來，
  再對原目錄重播一次。
- 錯誤案例（風控、下架）多半錄不到：手寫或把錄到的改掉，在 `meta.edited` 寫理由，錄製就不會蓋掉
  那個案例。手寫的 fixture 也要是遮過的樣子（值寫 `***`），掃描不會放過。
- 會變的 query 參數（時間戳、簽名）在 fixture 裡寫 `***` 就不比值；鍵名名單上的參數錄的時候
  已經是 `***`，媒體 CDN 規則上的簽名參數則整個拿掉。
- 跑：`FMP_PLUGIN_DIR=<絕對路徑> flutter test test/plugins/contract/contract_test.dart`；沒設
  `FMP_PLUGIN_DIR` 就是跑 `app/` 內的測試插件（裸 `flutter test` 已包含）。失敗訊息列出每一條
  違反，例如 `search: request #1 (GET …) does not match fixtures/search/001.json (GET …)`。

## 插件庫與生命週期

規則與閘門見 `app/AGENTS.md` § 插件的「插件庫與生命週期」。

- 流程（UI 在插件頁）：`readIndex` → `updateStatus` 決定要不要更新 → `prepare`（下載、驗 SHA、比對 manifest）→ 以
  `Prepared.plugin`（`PreparedPlugin`） 的 `file.manifest`、`addedCapabilities`、`addedHosts` 做確認對話框 → `installPrepared(confirmed:)`。
  從檔案或網址安裝仍走 `installBytes`／`installSource`（沒有來源 index、沒有 checks）；網址的檔案以
  `PluginDownloader.downloadFile` 下載並讀出 manifest，確認後再 `installSource`。
- 預期內的拒絕（SHA 不符、manifest 與 index 不一致、需要更新 FMP）是回傳值：`prepare` 回 `PrepareResult`
  （`Prepared`／`PrepareRejected`），`readIndex` 回 `IndexReadResult`（`IndexRead`／`IndexRejected`）；其他失敗丟 `AppError`。
  呼叫端用 `switch` 接，兩種都要處理。
- 測試：`PluginDownloader(fetch:, log:)` 的 `fetch` 注入一個查表的假函式，不碰網路；移除用 `CacheHarness`
  （`test/data/cache/cache_harness.dart`）開一個真的快取庫。寫法看 `plugin_installer_test.dart` 的
  `plugin repository` 群組。
- 停用的插件不在 `pluginRegistryProvider` 的 Map 裡，要區分「停用」與「未安裝」用
  `PluginRegistry.isDisabled`（Map 每次改變都會發出新值，讀它的 provider 會跟著重建）。
- 移除時之後的 PR 要加的步驟（憑證、帳號、排程器）加在 `PluginInstaller.remove` 刪 `installed_plugins` 列之前，並在
  `removing` 群組加對應的斷言。

## 帳號

規則與閘門見 `app/AGENTS.md` § 帳號。

- 要憑證的程式碼拿 `credentialStoreProvider`（`CredentialStore`）：`state(id)` 是 `none`／`active`／`invalidated`／
  `unreadable`，`activeCredentials(id)` 只在 `active` 回值；`save(account, credentials)` 先寫 secure storage 再寫
  帳號列；`delete(id)` 只刪憑證與遮蔽登記，帳號列由 `AccountService.logout` 刪。
- `PluginHarness` 自帶 `credentials`（接在記憶體資料庫與 `secureStorage`，一個 `InMemorySecureStorage`）；測試用
  `harness.credentials.save(...)` 造出已登入的狀態。`InMemorySecureStorage.readError`／`writeError` 模擬 keystore 失敗。
  需要 `ProviderContainer` 的測試要 override `credentialStoreProvider`（`harness.credentials`），App 層的測試
  override `secureStorageProvider`。
- 憑證值用 `FAKE_…` 開頭的假值，遮蔽才好斷言。

## 在 App 裡試插件

- 測試：`PluginHarness().load(source)`（`test/plugins/plugin_harness.dart`），HTTP 走假 adapter。
- dev 實機：Windows `flutter run --dart-entrypoint-args=--fmp-dev-plugin=<路徑>`，或設環境變數
  `FMP_DEV_PLUGIN`；Android 見 `verify-on-device` skill 的 `references/android.md`。有 `search`
  能力的插件出現在搜尋頁的音源 chip。

## 加一個宿主 API

1. `js_prelude.dart`：在 `fmp` 上加函式，經 `callAsync`（會等 I/O）或 `callSync`（純計算、log）送
   一個 op 名稱與物件參數。
2. 決定它在哪個 isolate 執行：
   - 碰外界（網路、檔案、資料庫、憑證）或需要安全檢查的：`callAsync`，在主 isolate 的
     `plugin_host.dart` 的 `callAsync` `switch` 加 op（背景 isolate 以 `HostRequest` 轉過來）。插件 id
     只能用 `PluginHost.pluginId`，不收腳本傳來的 id。
   - 純計算：`callSync`，在 `plugin_worker.dart` 的 `_sync` 加 op，不送訊息。背景 isolate 只能做不需要
     信任的事：它跑的是插件的程式。
   參數用 `JsonFields` 讀；參數不對拋 `ArgumentError`／`FormatException`（腳本收到 `TypeError`），
   其他失敗拋 `AppError`（腳本收到帶 `fmpError` 的 Error）。
3. `fmp-plugin.d.ts`：加到對應的 `Fmp*` interface；新的 JSON 物件同時加 interface 與
   `hostApiShapes` 的一列。`type_definitions_test.dart` 會比對。
4. 測試：`test/plugins/runtime/plugin_runtime_test.dart` 的 `host API` 群組。碰到儲存或網路的 API
   要有「另一個插件看不到」的案例。

要不要加 `hostApiVersion`：

- **只加東西**（新函式、DTO 或參數的新**選填**欄位）：不加版本。舊插件照跑；新插件用了新東西，在
  舊 App 上會得到 `TypeError` 或被拒收。要讓新插件在舊 App 上明確失敗，改用下一條。
- **不相容**（改名、刪除、選填改必填、改語意、DTO 欄位改型別）：`hostApiVersion` 加一。版本不同的
  manifest 一律 `Unsupported`（`PluginManifest.parse` 開頭），同時把 `apiVersion: 1` 的插件升級。
  這是對外介面的破壞性變更，先告知擁有者（插件庫要同步發版）。

## 加一個 DTO 欄位或能力

- DTO：`source_dto.dart` 的類別、`fromJson`／`toJson` 與 `sourceDtoShapes` 一起改，`fmp-plugin.d.ts`
  同步。欄位名稱是插件的介面，列舉值寫死字串（`wireName`），不用 `.name`。
- 能力：`PluginCapability` 已有 ADR 0014 的 12 個；新能力的方法加在 `SourcePlugin`（引入它的里程碑
  才加，不寫空殼），`ScriptSourcePlugin` 以 `_invoke` 呼叫同名匯出，再加 `fmp-plugin.d.ts` 的
  `FmpPluginExports`。

## 測試

- `flutter test` 直接跑 QuickJS（`test/support/quickjs.dart`）。只在 Windows、Linux；macOS 會失敗。
- `PluginHarness().runtime(script)` 測 runtime 與宿主 API：腳本只寫 module（沒有標頭），任意名稱的
  匯出都能 `invoke`。`.load(source)` 測整條載入（manifest、匯出檢查、DTO 驗證）；`pluginSource()`
  組標頭。storage 有外鍵，兩者預設先在 `installed_plugins` 放一列。
- 看門狗用小的 `callTimeout`、`livenessGrace`（例如 500ms／300ms），太小會讓背景 isolate 還在建
  QuickJS 時就被判逾時。等非同步結果用 `pumpUntil`／`settle`；要等實際時間（計時器）就 await 一個由
  計時器完成的 `Completer`，`pumpUntil` 不會等時間。
- 同步卡住的測試（`while(true){}`）每個會留下一條忙著的執行緒到測試檔的行程結束，只寫必要的幾個。
- 背景 isolate 當掉的情況用 `runtime(entryPoint: ...)` 換掉進入點（照 `worker_protocol.dart` 的協定
  回訊息再拋錯），不在正式程式碼留開關。
- 走 Riverpod 的測試（安裝、清單）用 `ProviderContainer(retry: (_, _) => null, ...)`：App 關了重試，
  不關的話失敗的 provider 會一直重試到測試逾時。
- 契約執行器本身（`test/plugins/contract/`）：改它的檢查時，在 `contract_runner_test.dart` 以
  `copyPlugin`／`edit`（`plugin_copy.dart`）在測試插件的副本上造一個會紅的變異，並留一個改無關處
  不紅的案例。`edit` 找不到要換的字串會讓測試失敗（Windows checkout 可能是 CRLF，只換單行）。

## Quality Check

- `test/plugins/` 全綠（含契約執行器）；新的宿主 API 有隔離案例；`type_definitions_test.dart` 綠。
- `lib/plugins/` 以外沒有 import `flutter_js`；沒有網址字面值（`fmp_url_literal`）。
- 改了 `fmp` 形狀或 DTO：`fmp-plugin.d.ts` 一起改，`app/AGENTS.md` § 插件若規則變了也改。
- 加了 DTO 欄位：`test/plugins/contract/checks.dart` 的 `trackFields`／`candidateFields` 一起加
  （`checks_test.dart` 比對）；`SourcePlugin` 加了能力的方法：`checkShapes['FmpChecks']`、
  `PluginCheck.run` 與 d.ts 的 `FmpChecks` 一起加。
