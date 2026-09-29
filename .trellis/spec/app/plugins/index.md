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
  plugin_registry.dart        # pluginRegistryProvider：已載入的插件
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
    plugin_installer.dart     # PluginInstaller：解析 → 載入 → 寫入 → 註冊
    dev_plugin_entry.dart     # dev 的開發入口
  types/fmp-plugin.d.ts       # 給插件作者的 TypeScript 型別
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

export async function resolveStream({ sourceId, cid, formats }) {
  // 依 formats 挑平台能播的；找不到就拋 NotFound 或 Unavailable，不回空清單。
  return { candidates: [{ url: 'https://cdn.example.com/a.m4a', container: 'mp4', codec: 'aac' }] };
}
```

- 型別與每個欄位的限制看 `lib/plugins/types/fmp-plugin.d.ts`；物件多一個欄位就整個被拒收。
- 能力名稱＝匯出函式名稱。其他匯出（常數、helper）不影響。
- 狀態碼與業務錯誤碼在插件裡轉成結構化錯誤（`.trellis/spec/app/errors/index.md` § 音源的錯誤
  對應表）；`fmp.http.request` 自己丟的錯誤（網域不符、限流重試後仍失敗、傳輸錯誤）直接讓它往上拋。
- 要跨重啟的值（匿名 cookie 等）存 `fmp.storage`；`fmp.credentials.get()` 在 M1 一律是 `null`。
- 沒有 `setTimeout`、`fetch`、`require`，也不能 `import` 其他 module：一個檔案就是全部。
- 用 `fmp-test` 當範本：`app/test/fixtures/plugins/test_plugin/test_plugin.js`。

## 在 App 裡試插件

- 測試：`PluginHarness().load(source)`（`test/plugins/plugin_harness.dart`），HTTP 走假 adapter。
- dev 實機：Windows `flutter run --dart-entrypoint-args=--fmp-dev-plugin=<路徑>`，或設環境變數
  `FMP_DEV_PLUGIN`；Android 見 `app/AGENTS.md` § 插件的 `adb` 指令。身分頁列出載入的插件。

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
- 錯誤 fixture 的契約測試、`checks.json` 在 PR 9b。

## Quality Check

- `test/plugins/` 全綠；新的宿主 API 有隔離案例；`type_definitions_test.dart` 綠。
- `lib/plugins/` 以外沒有 import `flutter_js`；沒有網址字面值（`fmp_url_literal`）。
- 改了 `fmp` 形狀或 DTO：`fmp-plugin.d.ts` 一起改，`app/AGENTS.md` § 插件若規則變了也改。
