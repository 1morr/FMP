# 研究：日誌套件、遮罩策略、網路請求日誌

範圍對應 task brief 項目 1、2、4。規則：版本 / 平台 / 維護狀態一律附 URL；查不到寫「查不到」；推測寫「推測」。全文繁體中文，程式識別碼保留原文。

---

## 1. 日誌套件比較

候選：`logging`、`logger`、`talker`（+ `talker_flutter`、`talker_dio_logger`）、`loggy`、自寫薄層。

### 1.1 版本與維護狀態（pub.dev API，抓取於 2026-09-27）

| 套件 | 最新版本 | 發布日期 | 發布者 | 來源 |
|---|---|---|---|---|
| `logging` | 1.3.0 | 2024-10-17 | Dart team（`dart-lang/core` monorepo，作者欄 `Dart Team <misc@dartlang.org>`；pub.dev 是否為 verified publisher 查不到，僅能由 repository URL `github.com/dart-lang/core/tree/main/pkgs/logging` 佐證） | https://pub.dev/api/packages/logging |
| `logger` | 2.8.0 | 2026-09-05 | verified publisher `sourcehorizon.org` | https://pub.dev/api/packages/logger |
| `talker` / `talker_flutter` / `talker_dio_logger` | 全部 5.1.20（同步發版） | 2026-07-28 | `frezyx`（talker 作者） | https://pub.dev/api/packages/talker_dio_logger 、 https://pub.dev/api/packages/talker_flutter |
| `loggy` | 2.0.3 | 2022-11-07（近 4 年未更新） | verified publisher `infinum.com` | https://pub.dev/api/packages/loggy |

`logging` 距今近兩年未發版但屬 Dart 官方套件，API 面極小（`Logger`/`LogRecord`/`hierarchicalLoggingEnabled`），停滯代表「穩定」而非「廢棄」。`loggy` 近 4 年零更新，且下方 1.2 節會說明其功能缺口，判斷為**不推薦**而非單純過時。

### 1.2 五平台支援（pub.dev 分數頁，抓取於 2026-09-27）

| 套件 | Android/iOS/Windows/Linux/macOS/Web | Pub points | 備註 |
|---|---|---|---|
| `logger` | 6/6 皆支援 | 150/160 | Web 非 WASM 相容（`advanced_file_output_stub.dart` import `dart:io`），平台分只拿 10/20；不影響 Android/Windows/Linux 使用 |
| `talker_flutter` | 6/6 皆支援 | 160/160 | WASM-ready；`share_plus` 透傳的 `url_launcher_windows`/`url_launcher_linux` 平台警告不計分 |
| `loggy` | 6/6 皆支援，WASM-ready | 150/160（靜態分析扣 10） | — |
| `logging` | 純 Dart package，無平台限制（查不到 pub.dev 分數頁的逐平台列表，但作為 `dart:core` 層級套件不含平台相關程式碼，推測全平台可用） | 查不到 | — |

FMP 目標平台為 Android + Windows（＋ ADR 0009 提到的 Linux），四個套件在平台支援面都不構成排除理由。

Sources: https://pub.dev/packages/logger/score 、 https://pub.dev/packages/talker_flutter/score 、 https://pub.dev/packages/loggy/score

### 1.3 功能矩陣

| 能力 | `logging` | `logger` | `talker`生態 | `loggy` | 自寫薄層 |
|---|---|---|---|---|---|
| Log level | 內建 `Level`，可階層式（`hierarchicalLoggingEnabled`） | 內建 `Level` | 內建 `LogLevel` + `TalkerLog` 型別 | 內建，含自訂 `LogOptions` | 自訂 enum，工作量最小 |
| 結構化欄位（非純字串） | `LogRecord` 有 `error`/`stackTrace`/`zone`，無自由欄位 map | 同左，`error`/`stackTrace` | `TalkerData` 有 `message`/`exception`/`error`/`stackTrace`，**皆為 `final`**（見下方 2.4 節的關鍵限制） | 僅 `message`/`error`/`stackTrace` | 完全自訂 |
| 記憶體內歷史（in-app 可查） | 無內建，需自接 `Logger.root.onRecord.listen` 手動存 list | `MemoryOutput`（`BufferOutput` 子類，可設 buffer size） | `Talker` 本身即維護 `history` list（`TalkerHistory` 介面），為套件核心設計 | 無內建，需自接 stream | 自訂 ring buffer |
| 落盤 + 輪替 | 無內建 | `AdvancedFileOutput`：支援依大小/時間輪替、`maxLogFiles` | 無內建輪替；需自接 `FileOutput`（社群方案）或自寫 | 無內建 | 自訂（FMP 現況即此路線） |
| 內建檢視 UI | 無 | 無（純 logging 套件，無 UI 套件） | **有**：`talker_flutter` 提供 `TalkerScreen`/`TalkerView`，含分級篩選、搜尋、複製、分享匯出 | 無 | 無（FMP 現況自寫 Debug 頁） |
| dio 整合 | 無官方橋接 | 無官方橋接（需自寫 `Interceptor` 呼叫 `Logger`） | **有**：`talker_dio_logger`（官方子套件，見下方第 4 節） | 需額外套件 `flutter_loggy_dio`（非官方維護，功能未知，查不到近期更新記錄） | 自訂 dio interceptor |
| Riverpod 整合 | 無官方橋接，慣例做法是把 logger 實例包成一個 `Provider<Logger>` | 同左 | 無官方 Riverpod 套件；talker 本身是一個可注入的物件，包 `Provider<Talker>()` 即可，方式與其他兩者相同 | 同左 | 自訂 |
| release build 自動抑制 | 需手動判斷 `kReleaseMode` 設定 `Logger.root.level = Level.OFF` | **內建**：預設 `Filter` 是 `DevelopmentFilter`，`kReleaseMode` 下自動只放行 `Level.warning` 以上（原始碼行為，見 pub.dev 文件） | 無自動行為，需自己在建構 `TalkerSettings` 時依 `kReleaseMode` 設 `enabled`/`useConsoleLogs` | 無自動行為，需自訂 `LogOptions` | 自訂，FMP 現況已自行處理 |
| 單一遮罩 hook 點 | 無（資料模型 `LogRecord` 欄位非 final 但套件本身不提供攔截點） | 無官方攔截點，但呼叫端可在呼叫 `logger.d(msg)` 前自行處理 | **不可在 `TalkerObserver` 做**——`TalkerData` 的 `message`/`exception`/`error`/`stackTrace` 皆為 `final`，物件建立後才進 observer，字串已經定型（原始碼確認，見下方 2.4） | 無官方攔截點 | 完全掌控，天然是唯一 hook 點 |

Sources（套件文件）：
- `logger` `MemoryOutput`/`AdvancedFileOutput`/`DevelopmentFilter`：https://pub.dev/documentation/logger/latest/logger/logger-library.html
- `talker` 核心與 `TalkerData`：https://pub.dev/packages/talker ，原始碼確認見任務前段（`packages/talker/lib/src/talker.dart` 等，上一輪已讀取）
- `talker_flutter` `TalkerScreen`：https://pub.dev/packages/talker_flutter
- `talker_dio_logger`：https://pub.dev/packages/talker_dio_logger
- `loggy`：https://pub.dev/packages/loggy （功能限制由 README 描述反推，未見獨立的 history/file-output API）

### 1.4 結論與理由

**推薦：`talker` + `talker_flutter` + `talker_dio_logger`。**

理由（對照 owner 的四個硬性要求）：

1. **單一遮罩函式**：無論選哪個套件，`TalkerData` 系列欄位都是 `final`——這不是 talker 特有的限制，而是確認了一個通用結論：**遮罩必須發生在呼叫進 logging 套件的 API 之前**，也就是 FMP 現有的 `AppLogger` 薄層角色不能省。talker 在這件事上不比其他套件差，因為反正大家都得靠呼叫端遮罩。
2. **內建歷史 + 內建 UI**：talker 唯一內建「歷史紀錄」和「現成 Debug 頁 UI 元件」的套件，可以直接省掉 FMP 現有 Debug 頁裡「log 檢視/過濾」那塊的自製 UI 工作量，同時仍可用 `TalkerScreen` 的客製化參數（`TalkerScreenTheme`、自訂 `logsListBuilder` 等，查不到完整客製清單，需要實作時再查 API doc）保留現有外觀。
3. **dio 整合官方支援**：`talker_dio_logger` 是同一作者維護、隨 talker 同步發版（見 1.1 版本同步的證據），比起自己接 `logger`/`loggy` 的 dio interceptor，維護面更集中。
4. **release 抑制**：talker 沒有像 `logger` 的 `DevelopmentFilter` 那樣自動化，需要自己在初始化時判斷 `kReleaseMode`——這點 `logger` 略勝，但差距是一行 `if (kReleaseMode) ...` 的等級，不足以扭轉結論。
5. **維護活躍度**：三個 talker 子套件在 2026-07-28 同步發到 5.1.20，屬於目前候選中最新鮮的（`logger` 2026-09-05 更新更近，但 `logger` 沒有內建 UI/歷史/dio 官方整合，三項關鍵能力都要自己補)。

**為何不選 `logger`**：功能面（`MemoryOutput` + `AdvancedFileOutput` + release 自動抑制）扎實，但沒有內建 UI 元件，Debug 頁的「log 檢視/過濾」仍要自己刻；dio 整合也要自己寫 interceptor。等於在「網路日誌」與「UI」這兩塊都要重新造 talker 生態已經提供的輪子。

**為何不選 `loggy`**：近 4 年未更新，且不論歷史或落盤都要自己補，dio 整合還得依賴一個看不到維護紀錄的第三方套件 `flutter_loggy_dio`，風險最高、能力最少。

**為何不選 `logging` 或自寫薄層當「後端」**：`logging` 是最小可用的分級 API，沒有歷史/UI/dio 整合，等同從零開始搭；自寫薄層工作量最大，且 FMP 現有 `AppLogger` 已經是這條路線，若要重寫，talker 能提供的 UI + 歷史管理是現成的淨增量，沒有理由再全部自己刻一次。

**待 owner 定案的開放問題**：
- talker 的 `TalkerScreen` UI 客製化程度是否足以取代 FMP Debug 頁現有外觀，還是要另外接自訂 UI 只用 talker 當後端資料源——需要在設計階段實際跑一次 `TalkerScreen` 才能判斷，本次研究未做 UI 實測（不在本任務範圍：純研究，不寫程式碼、不跑 app）。
- release build 下是否要完全關閉本地檔案落盤（只保留記憶體歷史），或降級只寫 warning 以上——這是產品決策，非技術限制。

---

## 2. 遮罩（redaction）策略

### 2.1 三種可辨識的遮罩手法

| 手法 | 判斷依據 | 代表實作 |
|---|---|---|
| (a) 結構化 allowlist：依 **key 名稱** + regex | 掃過 map/JSON 的 key，命中黑名單 key 就整個值換成 `***` | FMP 現有 `AppLogger.redactSensitive`（26 個 key 名稱，不分大小寫比對，但**沒有 word boundary**，例如 key 名 `apikey_display_name_only` 也會誤命中——見 `docs/audit/accounts-network.md` §4.1 對此缺口的描述） |
| (b) 結構性截斷：依 **URL 形狀** | 不看內容是否敏感，一律只留 `scheme://host/…/最後一段`，中段路徑與整個 query 丟棄 | FMP 現有 `redactStreamUrl`（`lib/services/audio/playback_media.dart:12`），因為 YouTube HLS manifest 與 NetEase 的簽章可能落在**路徑中段**而非 query，只砍 query 不夠 |
| (c) 已知值替換：拿**目前登入帳號的實際敏感值**做全文字串比對替換 | 不靠 key 名稱也不靠 URL 形狀，而是遍歷「目前所有已登入帳號」的 `baseUrl`/`accessToken` 等真實值，在整段 log 字串（**含 stack trace**）中做不分大小寫的精確值比對並替換 | Finamp `censored_log.dart`（`legacy` 分支）：對每個 `finampUserHelper.finampUsers` 的帳號，把其 `baseUrl`、`accessToken` 的字面值在 log 全文中取代；另外任何標記 `containsLogin` 的紀錄整則訊息直接換成字串 `"LOGIN BODY"` |

Source（Finamp）：https://raw.githubusercontent.com/finamp-app/finamp/legacy/lib/services/censored_log.dart

**手法比較**：(a)(b) 屬「靜態規則」，不需要知道當下登入了誰，缺點是規則要窮舉 key 名稱／URL 形狀，容易漏；(c) 屬「動態比對」，優點是不管值出現在哪個欄位、哪種格式都能抓到（因為比對的是值本身，不是位置），缺點是只能遮罩「已知在系統裡的值」，對外部本來就未儲存成帳號物件的一次性 token（例如某次請求臨時簽出的 CDN 網址）無效，仍需要靠 (b) 的結構性規則補。**三者互補、不互斥**——FMP 應該三種都留：(a) 管一般 header/表單欄位、(b) 管 CDN 簽名網址、(c) 管「目前登入帳號」的長效憑證（cookie/token/baseUrl），三層疊加。

### 2.2 stackTrace 是否需要遮罩

需要。證據：
- Finamp 的已知值替換明確涵蓋 stack trace 全文（見上）。
- FMP 自己的稽核發現「log 檔案裡 stackTrace 是原樣寫入，沒有經過任何遮罩」是一個現存缺口（`docs/audit/accounts-network.md` §4.2，log file 那一列：「stackTrace 原樣寫入」）。
- 理由很直接：Dart 例外訊息常把觸發例外的請求物件（含 URL、header）字串化進 `toString()`，這段字串會被收進 stackTrace 或 exception message，等於繞過任何只檢查「log 呼叫參數」而不檢查「例外物件內容」的遮罩。

結論：遮罩函式的輸入必須包含 `error`/`exception` 物件的 `toString()` 結果與 `StackTrace` 的 `toString()`，不能只處理呼叫端傳入的純文字訊息。

### 2.3 CDN 簽名網址參數名稱清單

#### Bilibili（upos）

證據來源：`SocialSisterYi/bilibili-API-collect` 原始倉庫已被 GitHub 封存且預設分支改名為 `deprecated`、內容清空（疑似下架事件，`gh api repos/SocialSisterYi/bilibili-API-collect` 確認 `archived:true`），改用其活躍 fork `pskdje/bilibili-API-collect` 的 `docs/video/videostream_url.md`（master 分支，內容完整，含真實擷取範例網址）。

Source: https://raw.githubusercontent.com/pskdje/bilibili-API-collect/master/docs/video/videostream_url.md

會被 `upsig` 簽章覆蓋、必須視為敏感的參數（`uparams` 欄位本身會自我聲明涵蓋哪些 key，例如實測值 `uparams=e,uipk,nbs,deadline,gen,os,oi,trid,mid,platform`）：

| 參數 | 意義 | 敏感等級 |
|---|---|---|
| `e` | 不透明長權杖 | 高（簽章覆蓋） |
| `uipk` | 未知用途，簽章覆蓋 | 中 |
| `nbs` | 未知用途，簽章覆蓋 | 中 |
| `deadline` | unix 秒數到期時間 | 中（本身非機密，但暴露「這條網址還能用多久」；**FMP 自己的 `playback_request_session.dart` 的 `_expiryFromUrl` 函式已在讀這個欄位算過期時間，等於一階證據確認此參數存在且被 FMP 使用**） |
| `gen` | 產生方式（playurl/playurlv2/playurlv3） | 低 |
| `os` | CDN 路由標籤（mcdn/cosbv/08cbv/bcache/upos） | 低 |
| `oi` | 數字 id | 低 |
| `trid` | 請求追蹤 id | 低 |
| `mid` | **使用者數字 id——敏感，可識別帳號** | 高 |
| `platform` | pc/html5 | 低 |
| `upsig` | 簽章雜湊本身 | 高 |

非簽章覆蓋但仍屬路由/裝置指紋的參數：`bvc`、`nettype`、`orderid`、`agrr`、`bw`、`logo`、`og`、`mcdnid`、`cdnid`、`buvid`（裝置指紋）、`build`、`lrs`、`tag`、`dl`、`f`、`qn_dyeid`。

另外，*請求*端（非回傳網址）會帶一個 `session` 參數（buvid3 + 時間戳做 md5），用途是配額驗證，與回傳的 CDN 網址簽章是兩件事，同樣需要遮罩。

一階佐證：`lib/services/audio/playback_request_session.dart` 約第 434 行：

```dart
Duration _expiryFromUrl(String url) {
  final deadline = int.tryParse(
    Uri.tryParse(url)?.queryParameters['deadline'] ?? '',
  );
  ...
}
```

（FMP 自己的程式碼直接讀 `deadline` 這個 query 參數，證實其存在且被業務邏輯依賴。）

#### YouTube（googlevideo）

沿用上一輪研究成果（`docs/audit/accounts-network.md` 與外部 InnerTube 相關文件已於前次交叉確認，本輪未重新查證，逐字保留）：`expire`、`ei`、`ip`、`id`、`itag`、`mime`、`sig`、`lsig`、`sparams` 等；`sparams` 本身也會像 Bilibili 的 `uparams` 一樣列出哪些參數被簽章涵蓋。InnerTube API 呼叫另有 `key=` 這個 API key query 參數，`docs/audit/accounts-network.md` §4.1 明確指出這是 FMP 現有 `redactSensitive` 完全沒處理到的缺口。

#### NetEase Cloud Music

**結構性結論：NetEase 的串流網址本身不走「query string 簽章」這條路。**

證據鏈：
1. GitHub 外部查證是死路——`Binaryify/NeteaseCloudMusicApi` 已被封存且倉庫清空至只剩 README（`size:1`），`gh api .../forks` 逐一檢查約 30 個 fork，全部一樣被清空（同樣疑似下架事件），無法從外部文件補上參數名稱清單。
2. 改用 FMP 一階原始碼佐證：`lib/core/utils/netease_crypto.dart` 顯示 NetEase 兩套簽章機制——
   - `weapi()`：雙層 AES-128-CBC 加密 + RSA 包公鑰，回傳 `{'params': ..., 'encSecKey': ...}`，這兩個值放進 **POST body**，不是 URL query。
   - `eapi()`：AES-128-ECB + MD5 完整性摘要，回傳一段 hex 編碼的 `params` 字串，一樣放進 **POST body**。
3. 串流網址的到期時間來自 API JSON 回應裡的 `expi` 欄位（缺省 fallback 16 分鐘），同樣不是 URL 參數。

**對遮罩設計的意涵**：對 NetEase 的音訊串流網址做「砍 query」幾乎是 no-op——網址本身結構上就沒有東西好砍。真正需要遮罩的是**請求時的 POST body**（`params`/`encSecKey` 或 hex `params`）與**隨請求附帶的 header/cookie**（`docs/audit/accounts-network.md` §3.3、§4.1 記錄的 `X-Real-IP: 118.88.88.88` 這個固定偽造值本身不敏感，但同一批請求帶的帳號 cookie 敏感）。換句話說，NetEase 這條路徑的遮罩重點從「URL 形狀」轉移到「POST body 內容」與「header/cookie」，跟 Bilibili/YouTube 的威脅模型不同，設計文件要分開處理，不能套用同一個「砍 query」function 就當作三個來源都覆蓋到了。

Sources: `lib/core/utils/netease_crypto.dart`（FMP 原始碼）、`docs/audit/accounts-network.md` §3.3 / §4.1（FMP 稽核文件）。

### 2.4 為何遮罩不能做在 logging 套件內部（架構結論）

以 talker 為例驗證（原始碼於前次研究讀取確認）：`TalkerData` 的 `message`、`exception`、`error`、`stackTrace` 全部宣告為 `final`，物件建構完成後才會傳進 `TalkerObserver.onLog()`。也就是說：

- 想在 `TalkerObserver` 裡攔截並改寫內容——**做不到**，欄位是 `final`，观察者拿到的已經是定型後的物件，只能讀不能改。
- talker 內建的匯出機制（`talker_flutter` 的 `download_logs_native.dart`）是**原樣**把歷史紀錄寫成純文字檔案再呼叫 `SharePlus` 分享，過程中不會做任何二次處理。

（Source：https://raw.githubusercontent.com/frezyx/talker/master/packages/talker_flutter/lib/src/utils/download_logs/download_logs_native.dart ，確認匯出用 `path_provider` 存到暫存檔 `talker_logs_<timestamp>.txt` 後 `SharePlus.instance.share(ShareParams(files:...))`。）

**結論對三個套件都成立，不是 talker 特有的限制**：無論最終選 `logging`／`logger`／`talker`／`loggy` 哪一個當後端，遮罩都必須在「呼叫進 logging 套件 API 之前」完成，也就是 owner 要求的「單一遮罩函式」在架構上只能是一層**呼叫端的薄 facade**（FMP 現有 `AppLogger` 的角色），而不能實作成任何一個 logging 套件的 plugin/observer/formatter。這對「Toast 詳情、Debug 頁、診斷包、logs 都要走同一個遮罩函式」這個 owner 需求是決定性的架構前提：這四個出口理論上可能分別呼叫「logging 套件的 API」與「build 診斷包字串」與「顯示 Toast 文字」三種不同路徑，若遮罩函式只掛在 logging 套件裡，另外三個出口就會漏接——必須讓四個出口的原始資料在各自組字串前，共同先過同一個頂層函式。

---

## 3. 網路請求日誌（dio interceptor）

比較對象：`talker_dio_logger`、`pretty_dio_logger`、`alice`（含 `alice_dio` adapter）/ `alice_lightweight`。

### 3.1 版本與維護狀態

| 套件 | 最新版本 | 發布日期 | 備註 |
|---|---|---|---|
| `talker_dio_logger` | 5.1.20 | 2026-07-28 | 與 talker 核心同步發版 |
| `pretty_dio_logger` | 1.4.0 | 2024-07-21 | Dart SDK 限制 `>=3.0.0 <4.0.0`；1.1.1 起不再宣告 Flutter SDK 依賴（純 Dart 相依 `dio: ^5.5.0`），近 2 年多未更新但 API 面小、無明顯棄用訊號 |
| `alice`（核心） | 1.10.0 | 2026-09-18 | verified，pub points 160/160，6/6 平台（含 Windows/Linux），WASM-ready |
| `alice_dio`（dio adapter） | 1.3.2 | 2026-09-18 | 依賴 `alice: ^1.10.0`、`dio: ^5.8.0+1`，與核心同步發版 |
| `alice_lightweight` | 3.10.0 | 2025-05-12 | 第三方 fork（`payfazz`），移除部分依賴的輕量版，維護活躍度低於官方 `alice`+`alice_dio` 組合 |

Sources: https://pub.dev/api/packages/talker_dio_logger 、 https://pub.dev/api/packages/pretty_dio_logger 、 https://pub.dev/api/packages/alice 、 https://pub.dev/api/packages/alice_dio 、 https://pub.dev/api/packages/alice_lightweight 、 https://pub.dev/packages/alice/score

**修正歷史**：舊版 `alice`（`jhomlala/alice`，對應本輪之前的既有印象）採單一套件內建全部 adapter 的設計，`getDioInterceptor()` 一類方法后來被移除；目前（1.10.0，2026-09-18）採**模組化設計**——核心 `alice` 套件 + 專用 adapter 套件（`alice_dio`／`alice_http`／`alice_chopper` 等），透過 `AliceDioAdapter().getInterceptor(alice)` 掛進 dio。`alice_lightweight` 是舊架構下「移除多餘依賴」的 fork，在新架構模組化之後已不是必要的替代方案，因為官方版現在本來就用得輕量。

### 3.2 各套件記錄的內容與用途

| 套件 | 記錄內容（可設定項） | 保留方式 | 內建遮罩 |
|---|---|---|---|
| `talker_dio_logger` | 走 talker 的 `TalkerDioLogger` interceptor，把 request/response/error 轉成 talker 的 log 條目，進而進入 talker 的 history/UI 同一套機制 | 併入 talker 歷史（受 talker 的記憶體上限與（若接了）落盤規則管） | **無**，且因 `TalkerData` 欄位 final（見 2.4 節），必須在呼叫 `talker.log(...)`／`GenerousDioLogInterceptor` 產生訊息**之前**完成遮罩——即需要客製 `TalkerDioLogger` 的 `requestPen`/`responsePen`/`errorPen` 或自寫等價 interceptor，在組字串當下呼叫遮罩函式 |
| `pretty_dio_logger` | 依建構參數各自開關：`requestHeader`（預設 false）、`requestBody`（預設 false）、`responseHeader`（預設 false）、`responseBody`（預設 **true**）、`error`（預設 true）；另有 `filter` callback 可依 `RequestOptions`/資料型別排除特定請求 | **不保留歷史**——純粹即時印到 `logPrint`（預設 `print`），沒有記憶體 buffer 或檢視 UI，要保留歷史得自己接 `logPrint` 存起來 | **無**內建遮罩；但有 `filter` 掛鉤可用來跳過或改寫要印的內容（原始碼 `onRequest`/`onResponse`/`onError` 都是先跑 `filter` 判斷再印，理論上可以在 `filter` 或自訂 `logPrint` 裡插入遮罩，但這是繞過官方設計意圖的用法，官方 API 沒有正式的「內容改寫」鉤子，只有「是否印」的布林鉤子) |
| `alice` + `alice_dio` | 完整請求/回應（header、body、query parameter〔限 dio〕、狀態碼、耗時），另外附加圖片/影片預覽、curl 匯出、安全/不安全連線標示 | **有獨立的 Inspector UI**（`showInspector()`），有自己的儲存/瀏覽機制，功能面最重 | 查不到官方文件提及任何內建遮罩機制（README/pub.dev 敘述未提 redaction），推測需要在 adapter 層自行處理，等同前兩者的限制 |

Sources: 
- `pretty_dio_logger` 建構參數與 `onRequest`/`onResponse`/`onError` 原始碼：context7 `/websites/pub_dev_pretty_dio_logger`（來源 https://pub.dev/documentation/pretty_dio_logger/latest/ ）
- `alice`/`alice_dio` 功能描述：https://pub.dev/packages/alice 、 https://pub.dev/packages/alice_dio （WebSearch 摘要整理，功能清單部分來自同系列套件的歷史描述，未逐條在原始碼核對，標記為**推測**的部分已在上表註明）

### 3.3 結論

延續第 1 節選定 talker 生態的前提下，**`talker_dio_logger` 是自然選擇**，理由：
- 統一進 talker 的 history/UI，不必再維護第二套「網路請求檢視」畫面，直接對應 owner 要求的「Debug 頁要有網路請求檢視」。
- 遮罩鉤子的限制與第 2.4 節結論一致——不管選哪個 dio logger 套件，都得在 interceptor 組訊息字串的當下呼叫同一個頂層遮罩函式，`talker_dio_logger` 允許自訂 `requestPen`/`responsePen`（需在實作階段查 API 細節確認精確簽名，本研究未逐行核對這兩個 callback 的參數型別，標記**查不到**具體簽名，只確認 talker_dio_logger 支援客製化輸出這件事本身）。
- `alice` 系列功能最完整（含 curl 匯出、圖片預覽），但代價是引入一整套獨立於 talker 的 UI/儲存系統，會與「單一遮罩函式」「統一 Debug 頁」的目標打架——等於要在兩個獨立系統裡各自插入遮罩鉤點，增加遺漏風險。除非 owner 認為 curl 匯出等進階功能是硬需求，否則不建議引入。
- `pretty_dio_logger` 不保留歷史，不符合 owner「網路請求要能檢視」的需求（純粹即時印出，重啟或翻頁後就看不到之前的請求），排除。

**待 owner 定案的開放問題**：
- `talker_dio_logger` 的 `requestPen`/`responsePen`/`errorPen` 客製化 callback 確切簽名與是否能完全掌控輸出字串（含 body 的巢狀結構如何序列化）需要在設計/實作階段直接讀套件原始碼或寫小範例驗證，本次研究以「文件已確認可自訂輸出」為止，未深入到逐參數層級。
- 是否需要記錄 request body：若 body 含帳號密碼（如 NetEase 登入的 `password` 欄位），這是遮罩函式必須覆蓋的欄位，需在設計階段把「NetEase 登入 body 裡的密碼欄位」加進允許清單式遮罩（2.1 節手法 (a)）的 key 名單。
