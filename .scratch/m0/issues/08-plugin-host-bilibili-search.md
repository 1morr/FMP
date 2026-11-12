# 08: 插件宿主跑通 bilibili 搜尋

**What to build:** 在佔位搜尋頁輸入關鍵字，宿主載入隨 App 打包的 bilibili 插件，呼叫它的搜尋能力，四個平台都列出 B 站的搜尋結果（標題、作者、時長）。這張票建起插件宿主的最小完整路徑：JS 引擎（票 03 的結論）、manifest（插件能力、網域）、宿主網路 API（只放行 manifest 宣告的網域）、插件錯誤代碼轉成錯誤分類；bilibili 插件用 TypeScript 寫、esbuild 打包，產物提交，閘門檢查產物是否最新。

讀：ADR 0038；brief §5.3、§13、§18.1（事實 F1、F2、F4）、票 03 寫進 brief 的結論；plan §1.1–§1.4、§3、〈待決〉P3；`GLOSSARY.md`〈宿主與插件〉；spec〈共同規則〉

**Blocked by:** 02、03、06

**Status:** done

- [x] 插件宿主的介面用 `mattpocock-skills:codebase-design` 設計，只涵蓋搜尋與之後的解析串流；完整的插件能力清單在 M1 拆票時定（plan〈待決〉P3），這張票不先定，但 manifest 的插件能力宣告要能直接加新的能力；介面與取捨記到票的 Comments，影響架構的另寫 ADR（照〈擁有者確認〉）。
- [x] manifest 宣告插件能力與網域；插件連未宣告的網域會被宿主拒絕，有測試。插件沒有檔案系統與 socket。
- [x] 建立 fjs 引擎時只開白名單內的內建模組，不含 `fs`、`net`、`child_process`、`fetch` 等：fjs 自帶的 fetch 會繞過宿主的網域白名單（brief 事實 K11）。由測試強制，並在測試檔內做雙向變異驗證：多開一個非白名單模組會紅，改無關的設定不紅。（擁有者 2026-11-11 在票 03 確認加入）
- [x] 宿主網路 API 經 dio，請求與錯誤都經過票 06 的 log 與遮蔽；B 站的風控碼與 HTTP 412、429 由插件回報成固定代碼，宿主轉成「限流」（事實 F2）。
- [x] bilibili 插件的原始碼在 `app/plugins/bilibili/`（TypeScript），esbuild 打包的產物提交；`check.dart` 完整版檢查產物與原始碼一致，造一次不一致證明會紅。開發需要的 Node 版本寫進 plan §4。
- [x] Dart 端沒有 bilibili 專屬的分支（依賴規則測試通過）。
- [x] 單元測試用假的宿主網路回應測搜尋結果的轉換與錯誤代碼，零聯網。
- [x] 四平台實跑：佔位搜尋頁搜一次，讀回畫面看到結果（匿名、每平台只搜一次）。
- [x] `dart run tool/check.dart` 完整版綠燈。

## Comments

### 插件宿主的介面（codebase-design）

- 公開介面只有 `lib/plugins/plugins.dart`：`PluginHost(bundles:, log:, httpAdapter:, callTimeout:)`、`host.plugins`（manifest 合格的插件）、`Plugin.search(query) → List<Track>`、`host.close()`；失敗一律丟 `AppError`。插件能力是 `Plugin` 上的方法，宣告了才呼叫得到，沒宣告丟 `Unsupported`；之後的解析串流照同一個形狀加一個方法。`loadBundledPlugins(rootBundle)` 從資產找 `plugins/<id>/manifest.json`，Dart 端沒有任何插件名稱；`pluginHostProvider` 給 UI 用。
- seam：網路用 dio 自己的 `HttpClientAdapter`（真的與 `FakeHttp` 兩個 adapter），不另立網路介面；JS 引擎不設 seam，測試直接在 Mac 上跑真的 fjs（`test/support/fjs.dart`，brief 事實 K19）。所以宿主的測試從公開介面進去，插件的 JS 與宿主的 Dart 一起被測到。
- 內部：`manifest.dart`（manifest 與插件能力 enum）、`host_network.dart`（網域白名單、轉址、log）、`plugin_error.dart`（固定代碼 → 錯誤分類）、`js_engine.dart`（白名單內建模組、宿主 API prelude、呼叫插件的包裝模組）、`plugin_host.dart`（引擎生命週期、bridge 分派）。
- manifest 格式參考 Spotube `plugin.json`（能力與權限分開，ADR 0038）與 Chrome 擴充的 `host_permissions`（`*.` 涵蓋子網域）：`id`、`name`、`version`、`capabilities`、`domains`。認不得的能力字串略過，舊宿主讀得了新插件的 manifest；新增能力 = `PluginCapability` 加一個值。
- 插件端的契約：esbuild 打包成 ES module，匯出插件能力同名的函式（`search({query}) → {tracks: [{id, title, author, durationMs?}]}`）；宿主給全域 `host.http.request({url, headers}) → {status, body}` 與 `PluginError(code)`，型別在 `app/plugins/host.d.ts`。`durationMs` 照 Spotube 的命名。
- 沒寫 ADR：這些都是 ADR 0038 決定的實作（插件只連 manifest 宣告的網域、錯誤以固定代碼回報），插件能力清單照 plan〈待決〉P3 留到 M1。

### 票內的取捨

- 宿主網路只收 https 的 443 埠；轉址不讓 dio 自己跟，由宿主逐跳檢查網域（最多 5 跳），否則一個 302 就繞過白名單。任何狀態碼照實交回插件，由插件判斷（B 站的 412、429 與風控碼由插件回報 `rate_limited`，事實 F2）；只有連不上、逾時算 `network`。目前只有 GET，請求 body、回應 header 等要用時再加（宿主 API 到 v2.0.0 才凍結）。
- 錯誤代碼對照：宿主擋下未宣告網域是 `domain_not_allowed`，對使用者等於這個插件做不到，歸 `Unsupported`；插件丟了沒有代碼的例外、或回傳形狀不對，多半是音源的回應變了，歸 `ParseFailure`。呼叫逾時（預設 60 秒，比宿主網路單次請求的上限 15 + 30 秒長，慢網路會先以 `network` 回到插件）代表插件卡住：關掉引擎、下次重建，也歸 `ParseFailure`。兩份錯誤代碼（`host.d.ts` 與 `PluginErrorCode`）由 `test/plugins/plugin_error_codes_test.dart` 對齊。
- fjs 把 JS 例外交給 Dart 時只剩訊息字串（事實 K19），所以用一個包裝模組 `fmp_invoke` 在 JS 端接住，把 `{ok}` 或 `{error: {code, message}}` 當回傳值交出。
- 內建模組白名單只有 `timers`。測試三層：`pluginBuiltins` 的值（從 freezed 的 `toString()` 讀開了哪些，fjs 新增的模組也算得到）、`lib/` 裡建立引擎的 AST 規則（只能 `JsEngine.create(builtins: pluginBuiltins)`，不能直接建 runtime）、真的引擎裡 `fetch`／`require`／`process` 是 undefined、`import('fs'|'net'|'child_process'|…)` 失敗。另外依賴規則加了「只有 `plugins/` 能 import fjs 與 dio」：別處不能自己建引擎，也不能繞過網域白名單自己連網。
- App 裡要先 `LibFjs.init()`：單元測試由 `loadFjsForTests()` 初始化，所以沒抓到；macOS 實跑看到「搜尋失敗」、新寫的 integration_test 在 macOS 紅（`flutter_rust_bridge has not been initialized`），修在 `js_engine.dart` 的 `_ensureFjs()`，同一個 integration_test 轉綠。用到 fjs 標了 `@internal` 的 `LibFjs.instance`（只為了問 `initialized`），已加註原因。
- 佔位頁的搜尋對每個宣告了 search 的插件各搜一次，一個失敗不影響其他；錯誤分類以外的例外寫 error log、畫面只說搜尋失敗。
- 打包產物檢查（`plugin bundles (esbuild)`，完整版最後一步）：`npm ci` 後 `npm run build -- --outdir <暫存>`（含 `tsc --noEmit`）重建，和提交的 `dist/` 逐位元組比對。`build.mjs` 設 `absWorkingDir`，產物裡的路徑註解不隨執行目錄變。
- 連網權限：Android 主 manifest 加 `INTERNET`、macOS 兩份 entitlements 加 `network.client`（事實 K20）。`winpc` 的 `shot.ps1` 加 `-Type`：Tab 聚焦、以 Unicode `SendInput` 打字（避開中文輸入法）、Enter。
- B 站搜尋照舊版的做法（`/x/web-interface/search/type`、瀏覽器 UA、search.bilibili.com 的 Referer／Origin、本地亂數指紋 cookie），寫成事實 F20。

### 驗證

- 白名單的雙向變異：除了測試檔內的變異，實際把 `pluginBuiltins` 改成多開 `fetch`，值那層（`Actual: Set:['fetch']`）與真引擎那層（`typeof fetch` 變成 `function`）都紅，改回轉綠。`host.d.ts` 多加一個代碼，`plugin_error_codes_test.dart` 紅，改回轉綠。443 埠的檢查拿掉時，「其他埠」那條測試紅。
- 打包產物檢查實跑（真的 `npm ci` 加 esbuild）：在提交的 `dist/plugin.js` 後面加一行 → 紅並列出 `plugins/bilibili/dist/plugin.js`；原始碼只改空白 → 綠（esbuild 輸出相同）；改原始碼裡的網址、不重建 → 紅；還原 → 綠。
- 四平台實跑（匿名，每個平台只搜一次，持共用裝置鎖；截圖留在暫存目錄）：
  - macOS：搜 `lemon`，列出 B 站結果（標題、作者、時長）。第一次實跑看到「搜尋失敗」，就是上面 `LibFjs.init()` 的 bug，修好重建後才是這個結果（修之前那次沒有發出請求）。
  - iOS 模擬器：模擬器的鍵盤是注音輸入法，`orca emulator type lemon` 被打成注音符號送出；照「只搜一次」沒有重搜，畫面列出那組注音的 B 站結果（標題、作者、時長），log 有對應的 GET。
  - Android 模擬器：鍵盤是速成輸入法，`lemon` 停在組字區沒上屏（那次按搜尋時查詢是空的，沒發出請求）；按 Enter 上屏成「被一例」後送出，列出 B 站結果。
  - Windows（`winpc`）：`shot.ps1 -Type lemon`，`foreground_is_fmp=True`，畫面列出 B 站結果，log 有 `GET …keyword=lemon -> 200 in 519ms`。

- 完整閘門（`dart run tool/check.dart`，commit c7c688e9）第一次就全綠，含四平台的插件搜尋 integration_test 與打包產物檢查：

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

### code-review（795d8c9e 起）

已處理：網域白名單加「只放行 443 埠」（附測試）；呼叫逾時從 30 秒改 60 秒，比宿主網路單次請求的上限長，逾時改歸 `ParseFailure`；dio 和 fjs 一樣只准 `plugins/` import；`host.d.ts` 與 `PluginErrorCode` 的代碼由測試對齊；`PluginCapability` 拿掉和值名稱一樣的 `wireName`；`SourceResults` 改名 `PluginResults`（裝的是插件的結果，不是音源）；`build.mjs` 的註解改成閘門實際下的指令。

未處理：

- 寫不出會紅的測試，照「修 bug 前先有失效條件」沒改，留給之後碰到時再修：
  - 逾時的競態：A 呼叫逾時、關掉引擎後，同一個引擎上的 B 會以 cancelled 失敗並再呼叫一次 `_closeEngine()`，理論上可能關掉 C 剛重建的新引擎。要在毫秒級的時序縫裡插進 C 才會發生，造不出穩定的 repro。做法：`_closeEngine` 只在要關的 future 還是目前的引擎時才清掉。
  - 建引擎時丟出 `JsError` 以外的例外（例如原生庫載入失敗），失敗的 future 會留在 `_engine`，之後每次呼叫都丟同一個例外；`_fjsReady` 也會快取失敗的初始化。測試裡造不出這種失敗。
- 宿主網路放在 `plugins/src/` 而不是 plan §1.2 的 `core/`：網域白名單是插件的 manifest 決定的，目前只有插件連網；plan §1.4 寫的依音源限流與重試這張票沒做（plan §7 的風險，要做時再定在哪一層），plan §1.4 已改成寫明還沒做。
- 「有 `manifest.json` 的目錄就是插件」在 `build.mjs`、`plugin_bundle_gate.dart`、`bundled_plugins.dart` 各寫一次：跨 JS、閘門與 App 三個執行環境，共用不了。
- 插件 id 用裸 `String`（`Track.source`、`PluginManifest.id`）：M0 先這樣。
- `Track.author` 不在 `GLOSSARY.md`：它是欄位名，不是新的領域概念；要不要進名詞表等擁有者決定（改名詞表要擁有者確認）。
