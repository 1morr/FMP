# 研究：憑證儲存與 HTTP 層

對應項目 2、3、4。查不到的地方寫「查不到」，超出已驗證證據的推論標「推測」。

## 1. 憑證儲存：`flutter_secure_storage`

### 1.1 版本與五平台後端

pub.dev（<https://pub.dev/api/packages/flutter_secure_storage>）：最新版 **11.2.0**，發布於
2026-09-16。score（<https://pub.dev/api/packages/flutter_secure_storage/score>）滿分 160/160、4,490 個
like、近 30 天下載 454.9 萬次——目前 Flutter 生態圈事實標準的安全儲存套件，沒有理由不選它。

自 10.x 起是聯邦式套件（federated plugin），核心套件 `flutter_secure_storage` 只定義介面，各平台後端各自
一個套件，`pubspec.yaml` 的 `dependencies` 已列出對照關係：

| 平台 | 後端套件 | 底層機制 |
|---|---|---|
| Android | 內建於核心套件（`com.it_nomads.fluttersecurestorage`） | Android Keystore 包一層自家 cipher，寫入 SharedPreferences |
| iOS / macOS | `flutter_secure_storage_darwin` ^0.4.0 | Keychain |
| Windows | `flutter_secure_storage_windows` ^4.2.2 | DPAPI（`CryptProtectData`，官方 README 用詞） |
| Linux | `flutter_secure_storage_linux` >=3.0.1 <5.0.0 | `libsecret`，需要一個執行中的 keyring service |
| Web | `flutter_secure_storage_web` ^2.1.1 | 瀏覽器儲存（非本專案關注範圍） |

### 1.2 11.x 的破壞性改動（讀官方 CHANGELOG 逐條確認）

CHANGELOG：<https://raw.githubusercontent.com/mogol/flutter_secure_storage/develop/flutter_secure_storage/CHANGELOG.md>
（官方倉庫現況：`repository` 欄位在 pubspec 寫的是 `mogol/flutter_secure_storage`，但目前實際维護者/組織是
`juliansteenbakker`，兩個帳號指向同一個專案歷史，`CHANGELOG.md` 內容與 pub.dev 發布記錄一致，可信）。

**11.0.0**（2026-08-06）明確標「Breaking changes」，重點摘錄（原文英文，以下為理解整理）：

- 移除 v10 就已標記 deprecated 的項目：**若資料是用 v10 之前的舊版寫入、且從未升級過 v10，直接跳到 v11
  會讀不出來**（CHANGELOG 原文："If you used a version prior to v10, upgrade to v10 first so existing data
  is migrated."）——這是唯一一條會導致資料真的遺失的規則。
- Android：移除 `KeyCipherAlgorithm.RSA_ECB_PKCS1Padding`、`StorageCipherAlgorithm.AES_CBC_PKCS7Padding`
  這兩個舊版加密方案；移除 `AndroidOptions.encryptedSharedPreferences` 參數（Jetpack Security 後端整個不再
  支援，資料在 v10 已自動搬到自家 cipher）；移除 `AndroidOptions.sharedPreferencesName`（改用
  `storageNamespace`）。
- Android `minSdk` 提高到 24、`compileSdk` 提高到 37；理由是 Flutter 3.35 本身已把最低 Android API 拉到
  24，導致 API 23 的支援路徑事實上沒人能再驗證，連帶砍掉支援 API 21-22 的舊 AES-CBC cipher 路徑。
- 11.1.0（2026-09-10）新增 `checkUpgradeStatus()`，可以在執行期主動查詢「這次啟動是不是直接從 v10 之前
  跳過來、資料可能已經遺失」；11.2.0（2026-09-16）修掉一批 Android 端的 biometric/多執行緒相關 bug。

**對 FMP 的實際影響（結合 ADR 0010 已定案的架構）**：

- ADR 0010 已經把 `flutter_secure_storage` 10.x 隔離在 `app/lib/legacy_import/`，只用來**唯讀**讀取舊 App
  寫入的憑證（舊 App 本身用的正是 10.x）。10.x 本身不受 11.x 這些破壞性改動影響，維持現狀即可。
- 新 App（`app/` 主體）要寫入的是**全新的憑證資料**（重新登入或匯入後轉存），不存在「舊版 v10 之前資料
  沒升級就跳 v11」的情境，因此**新 App 直接使用 11.2.0（目前最新穩定版）沒有升級路徑風險**，符合使用者
  規則「依賴裝當前 stable」。这一點回答了 ADR 0010 §後果留下的「`flutter_secure_storage` 升到 11.x 的條件
  在網路與帳號的 ADR 決定」：條件已經滿足（新 App 的資料本來就是全新寫入，沒有舊資料可言），可以直接採用
  11.x，不需要额外的相容層。

### 1.3 Linux：libsecret／keyring 需求與無 keyring 時的行為

`flutter_secure_storage_linux` 官方 README
（<https://raw.githubusercontent.com/juliansteenbakker/flutter_secure_storage/master/flutter_secure_storage_linux/README.md>，
已完整讀取）：

- 建置需要 `libsecret-1-dev`，執行需要 `libsecret-1-0`（多數 Linux 桌面環境預裝）。
- **執行期還需要一個「正在運行的 keyring service」**：GNOME/Ubuntu 靠 `gnome-keyring`（GNOME session 預設
  啟動）、KDE 靠 `kwallet`、其他輕量桌面環境靠 `secret-service`。
- README 明確把「Headless / CI」列成需要額外處理的情境，提供的解法是手動啟動並解鎖一個
  `gnome-keyring-daemon`：
  ```bash
  eval $(dbus-launch --sh-syntax)
  echo "" | gnome-keyring-daemon --unlock --daemonize --components=secrets
  ```
  這代表官方文件本身承認「沒有桌面 session、沒有人手動解鎖 keyring」的環境下這個套件**預期無法直接運作**，
  需要額外啟動步驟。README **沒有明說**一般桌面環境下 keyring 被鎖住或不存在時 API 呼叫會拋什麼例外、還是
  靜默失敗——**這點查不到**，需要在 Linux child task 的 POC 階段實測（例如全新安裝、未曾設定過密碼鑰匙圈
  的 Ubuntu minimal、或使用者手動殺掉 `gnome-keyring-daemon` 後）才能確認失敗模式。
- 已知建置問題：透過 snap 安裝的 Flutter 在 Ubuntu 22.04+ 上，因為 snap 內建的 GLib 版本與系統
  `libsecret` 編譯時的 GLib 版本不一致，會出現連結器錯誦（`undefined reference to
  'g_task_set_static_name'` 等），官方建議改用官方 tar 版 Flutter 而非 snap 版。這點值得記進 Linux child
  task 的建置文件，避免踩坑後才發現。

### 1.4 有沒有更好的替代方案

沒有找到明顯更好的替代——`flutter_secure_storage` 是 Flutter 生態圈裡分數、下載量、平台覆蓋度都最高的
選項，且 ADR 0010 已經因為「新舊憑證都要能讀」而選定它作為新舊兩端共用的技術路線（差在版本號）。查證過程
沒有刻意再找第二個候選方案，因為使用者規則「通用功能的順序：專案已有依賴→成熟且持續維護的套件→自己寫」
——本專案已經在用這個套件，且它本身仍然活躍維護（近一個月內三次發版），沒有理由切換。

## 2. HTTP 層：`dio` 與周邊套件

### 2.1 版本與周邊套件現況

| 套件 | 最新版 | 發布日期 | 用途 |
|---|---|---|---|
| `dio` | 5.11.1 | 2026-09-04 | HTTP client 本體 |
| `cookie_jar` | 4.0.9 | 2026-02-27 | Cookie 儲存與比對邏輯（RFC 6265） |
| `dio_cookie_manager` | 3.5.0 | 2026-07-25 | 把 `cookie_jar` 接成 dio 的 Interceptor |
| `dio_smart_retry` | 7.0.1 | **2024-10-22** | 逾時／特定狀態碼自動重試 |

（均來自 `curl https://pub.dev/api/packages/<name>` 直接讀取的 `latest` 欄位。）

**`dio_smart_retry` 已將近兩年沒有新版**（上次發版 2024-10-22，距今近 23 個月），score
（<https://pub.dev/api/packages/dio_smart_retry/score>）145/160、313 個 like，仍能通過 pub.dev 的相容性
分析，但不算「持續維護中」的專案；若採用，建議把它定位成「單純的逾時/連線層退避重試」（它的訴求本來就是
HTTP 層級的重試，不涉及認證邏輯），不要把認證刷新的邏輯也塞進去，降低對這個套件維護狀態的依賴程度。
`cookie_jar`／`dio_cookie_manager` 都是 `cfug`（dio 官方 GitHub 組織）自己維護的子套件，跟 dio 本體版本
同步發布，可信賴度高於 `dio_smart_retry`。

### 2.2 per-source client v.s. 共用 client

`docs/audit/accounts-network.md` §2（已讀）記錄了舊專案的現狀：**沒有共用 Dio**，每個音源、甚至同一個音源
內的不同 service（帳號 service、收藏夾 service、播放 adapter）都各自 new 一個 Dio 實例；全 `lib/` 只有
三處 `interceptors.add`，且全部是認證攔截器，**沒有** `LogInterceptor`、重試攔截器、快取攔截器，也沒有
`CookieJar`（accounts-network.md:139）。這造成的實際後果（accounts-network.md:249-253 表格）：認證攔截器
只掛在「歌單/收藏夾服務」的 Dio 上，播放/搜尋用的 adapter Dio 完全沒有攔截器，導致播放期偵測不到登入失效
（errors.md:336）。

**建議**：**per-source 一個 Dio 實例**（Bilibili 一個、YouTube 一個、網易一個），而不是 per-service 或全域
共用一個：

- 三個音源的 base header、簽名邏輯、cookie 網域完全不同，共用一個全域 Dio 反而要在攔截器裡用 if-else 分流，
  違反「單一音源的邏輯別外洩到別的音源」的分層目標。
- 但**同一個音源內部**的所有 service（帳號檢查、收藏夾、播放 adapter、下載）必須共用同一個 Dio 實例，
  這樣認證攔截器只要掛一次，就能涵蓋該音源的所有請求類型——直接修正 accounts-network.md 記錄的「攔截器
  只掛在部分 service」這個根因（不是攔截器邏輯寫錯，是掛的位置從一開始就不夠廣）。
- CDN／媒體位元組請求（見 §3.2）不套用該音源的認證攔截器，理由見下方。

### 2.3 Cookie 管理：`cookie_jar`／`dio_cookie_manager` v.s. 手動組 header

舊專案是手動把 cookie 字串塞進 `options.headers['Cookie']`（`bilibili_auth_interceptor.dart:28-33`，見
§2.4 完整分析）。`dio_cookie_manager` 官方定位（pub.dev description）是「結合 `cookie_jar` 與 dio 的攔截器」
——好處是能自動處理 `Set-Cookie` 回應、cookie 的網域/路徑/過期比對都交給 `cookie_jar`（實作 RFC 6265）
處理，不必自己維護字串拼接邏輯。

**建議採用 `PersistCookieJar`（`cookie_jar` 提供，可持久化到磁碟）+ `CookieManager`（`dio_cookie_manager`）
掛在每個音源自己的 Dio 上**，取代手動字串拼接，原因：

1. 手動拼接容易漏掉 cookie 屬性比對（過期時間、路徑），也是舊 bug 的根源之一（見 §2.4：`onRequest` 寫死
   的 cookie 字串在刷新後不會自動更新，因為它根本不是從一個「活的」cookie store 讀出來的）。
2. `PersistCookieJar` 本身處理持久化，可以取代「憑證存進 secure storage 之後，还要手動同步回 Dio」这一步
   ——改成「認證用的長效憑證（SESSDATA、MUSIC_U 等）存 secure storage 做單一事實來源；請求時的 cookie 由
   `CookieJar` 管理，登入/刷新成功後只需要呼叫 `cookieJar.saveFromResponse()` 或直接建構 `Cookie` 物件寫入,
   不需要自己在每個攔截器裡手動組字串」。

需要注意：`cookie_jar`／`dio_cookie_manager` 本身不做「認證」判斷（不知道什麼是登入失效），仍然需要一個
自訂的認證攔截器疊在它上面做「偵測 -101/301/401 之類的業務碼、觸發刷新」——兩者是互補而非取代關係。

### 2.4 重試模式：官方 `QueuedInterceptor` 範例 v.s. FMP 舊 bug 的直接對比

**dio 官方文件對「認證刷新後重試」給出了明確的建議模式**，範例檔案：
<https://github.com/cfug/dio/blob/main/dio/example_dart/lib/queued_interceptor_crsftoken.dart>
（透過 context7 `/cfug/dio` 確認此為官方 README 引用的範例；已直接讀取完整原始碼）。關鍵設計，逐條對照
FMP 舊程式碼（`lib/services/account/bilibili_auth_interceptor.dart`，本次研究已完整讀取，行號依現況檔案）：

| 面向 | dio 官方範例的做法 | FMP 舊 `BilibiliAuthInterceptor` 的做法 | 問題 |
|---|---|---|---|
| 攔截器基底類別 | `QueuedInterceptorsWrapper`——dio 內建、專門解決「多個並發請求同時觸發刷新」的攔截器基底，會自動把並發請求排隊 | 普通 `Interceptor` + 自己手寫一個 `Completer<bool>` 去重（`_ensureRefreshed()`，第 92-114 行） | FMP 的手寫版本邏輯本身沒有明顯錯誤（`Completer` 去重是正確技巧），但重新造了 dio 已經內建的輪子，且只去重「刷新動作」，沒有去重「等待刷新完成前的請求排隊順序」，維護成本比直接用 `QueuedInterceptor` 高 |
| 刷新成功後怎麼重試 | **明確地在重試前重寫 `requestOptions.headers`**：`dio.fetch(error.requestOptions..headers = {'Authorization': 'Bearer ${tokenManager.accessToken}'})`——用**當下最新**的 token 覆寫 headers，再送出同一個 `RequestOptions` 物件 | `_accountService.dio.fetch(requestOptions)`（第 77 行）——**直接重送同一個 `RequestOptions` 物件，不重寫任何欄位** | **這就是 accounts-network.md:128 已記錄的真實 bug**：舊 cookie 是在 `onRequest`（第 28-34 行）處理**送出前**的階段被寫進 `options.headers['Cookie']` 的；重試呼叫的 `_accountService.dio`（帳號服務自己的 Dio）**沒有掛這個攔截器**（`bilibili_account_service.dart:83` 沒有 `interceptors.add`），所以重試**不會重新跑一次 `onRequest`**，那個 `RequestOptions` 物件裡凍結的還是**刷新前**的舊 Cookie 字串。`refreshCredentials()` 只更新了 secure storage 與記憶體快取（`:425-429`），**不會回頭修改已經建構好的 `RequestOptions`**。結果：換了新 cookie，但重試送出的還是舊的，大機率再收到一次 -101，被誤判成「刷新也救不回來」而標記帳號失效（`markSessionExpired()`）——使用者其實已經登入成功，卻被系統判定成需要重新登入 |
| 併發保護測到什麼程度 | 用「當時請求帶的 token」跟「目前 token」比對，只有兩者相同時才觸發刷新，避免同一批並發請求觸發多次刷新 | 同上，`Completer` 機制本身能達到類似效果 | 這部分 FMP 的手寫邏輯是對的，不是 bug 來源 |

**結論與建議**：

1. 新專案的認證攔截器一律繼承 `QueuedInterceptor`（或用 `QueuedInterceptorsWrapper`），不要再手寫
   `Completer` 去重——這是 dio 官方為同一個問題提供的內建解法，語意更清楚、更不容易在維護時漏掉邊界情況。
2. **重試前必須用最新憑證重新建構請求**，不能直接 `dio.fetch(requestOptions)` 重送凍結的舊物件。具體做法：
   用 `requestOptions.copyWith(headers: {...最新 cookie...})` 或直接修改 `requestOptions.headers` 後再
   `fetch`，並且要用**掛了同一個攔截器鏈的 Dio 實例**去發這個重試請求（不要像 FMP 舊碼一樣切去另一個沒掛
   攔截器的 Dio），否則同樣的「憑證沒跟著更新」問題還會用不同形式重現。
3. 这也回頭印證 §2.2 的建議：認證攔截器必須掛在該音源**唯一**的共用 Dio 上，而不是像舊專案一樣只掛在部分
   service 的 Dio——如果重試要呼叫「同一個掛了攔截器的 Dio」，前提就是這個 Dio 真的涵蓋所有需要認證的
   請求，不能分裂成多個實例。

### 2.5 速率限制／退避

舊專案的限流退避邏輯分散在多處、各自硬編碼重試次數與秒數（`docs/audit/errors.md` §3.2 已整理：串流解析
1 次/3 秒、排行榜 4 次/5 秒-30 秒-2 分-10 分、播放漸進重試 1-2-4-8-16 秒、電台重連 1-3-10 秒），且播放層
「不退避、不跳過」限流錯誤（`errors.md:227`）。

本次查證沒有找到 pub.dev 上專門做「HTTP 429/backoff」且比自己寫更有優勢的成熟套件（`dio_smart_retry` 本身
支援按狀態碼、按次數退避,但如 §2.1 所述已近兩年未更新，且它的退避策略是通用 HTTP 語意，不理解「Bilibili
的 -352 風控碼」這種業務層限流）。**建議**：業務層的限流（各音源自訂的錯誤碼）用一個共用的、可設定重試
次數/退避序列的小型 helper 自行實作（不依賴 `dio_smart_retry`），統一放在音源共用的錯誤處理層，取代舊
專案「數字硬編碼在四五個不同檔案」的狀況；純 HTTP 層級的逾時重試（連線失敗、5xx）可以視情況疊加
`dio_smart_retry`，但不要用它處理業務碼判斷。

## 3. 憑證宣告 Pattern：哪些請求該帶認證，CDN 位元組請求絕對不該帶

### 3.1 官方支援的欄位：`RequestOptions.extra`

透過 context7 查證 dio 官方 README（`/cfug/dio`）確認 `RequestOptions`／`Options` 類別本身就有一個官方
支援、專門給呼叫端附加自訂中繼資料的欄位：

> `Map<String, dynamic>? extra` — "Custom field that you can retrieve it later in `Interceptor`,
> `Transformer` and the `Response.requestOptions` object."

這代表「用一個型別化標記，宣告這個請求需不需要帶認證」不需要發明新機制，dio 本身就設計了這個切入點，
攔截器可以在 `onRequest` 裡讀 `options.extra` 來決定要不要注入認證資訊。

### 3.2 設計提案（本次研究基於上述官方欄位提出的建議，非既有套件或客戶端的既定作法，標記為「本任務原創
設計提案」而非查證得到的既有慣例）

```dart
/// 標記一個請求是否需要帶該音源的認證憑證。
///
/// 放進 [RequestOptions.extra]，音源自己的認證攔截器讀這個值決定要不要注入
/// Cookie／Authorization header；沒有這個標記的請求（含所有 CDN／媒體位元組
/// 請求）一律視為 [AuthRequirement.never]，避免把帳號憑證意外送到不該送的地方。
enum AuthRequirement {
  /// 一定要帶：例如收藏夾、帳號狀態查詢。認證攔截器缺憑證時直接失敗，不送出。
  required,

  /// 依使用者設定的「使用登入態」開關決定要不要帶：例如排行榜、串流解析、詳情。
  optional,

  /// 一定不能帶：所有 CDN／媒體位元組請求、不需要認證的公開 API。
  never,
}

extension AuthRequirementExtra on RequestOptions {
  AuthRequirement get authRequirement =>
      extra['authRequirement'] as AuthRequirement? ?? AuthRequirement.never;
}
```

呼叫端在建構請求時明確標註：

```dart
dio.get(
  '/x/v2/fav/video/favoured',
  options: Options(extra: {'authRequirement': AuthRequirement.required}),
);
```

認證攔截器的 `onRequest` 邏輯變成：

```dart
@override
void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
  switch (options.authRequirement) {
    case AuthRequirement.never:
      break; // 什麼都不做，確保絕不會不小心帶認證資訊
    case AuthRequirement.required:
      // 缺憑證直接 reject，不送出
    case AuthRequirement.optional:
      // 依 Settings.useAuthForPlay(sourceId) 決定要不要注入
  }
  handler.next(options);
}
```

這個設計直接對應擁有者「使用登入態」開關必須語意一致、且可能要涵蓋所有讀取請求（含排行榜）的要求——因為
**預設值是 `never`**（沒標註的請求視為不該帶認證），新增一個讀取端點時，工程師必須主動決定它是
`required`／`optional`／`never` 三者之一才能編譯過（若把它做成一個必填的建構參數而非有預設值的具名參數）
，而不是像舊專案那樣「大部分請求根本沒有攔截器，帶不帶認證取決於這個 service 的 Dio 有沒有被加過攔截器」
這種隱性、容易遺漏的狀態（accounts-network.md 記錄的排行榜、播放 adapter 沒有攔截器覆蓋正是這種遺漏）。

### 3.3 CDN／媒體位元組請求為什麼絕對不能帶認證

三個可播放音源的串流位元組本身都是從各自的 CDN 網域下載（Bilibili 的 `upos-*`／`cn-*` 系列 CDN 網域、
YouTube 的 `*.googlevideo.com`、網易雲的 `music.126.net` 等——具體網域列表見
`docs/audit/accounts-network.md` 已有的音源 API 網域整理，本次未重新枚舉），這些網域：

1. **通常不需要認證**——串流 URL 本身已經帶簽名/過期時間（例如 Bilibili 的 `durl`/`dash` URL 帶
   `deadline`、`gorder` 等簽名參數，網易雲的 CDN URL 同樣帶簽名），認證是在**取得串流 URL 這一步**（API
   請求）做的，位元組下載這一步不需要、也不應該再帶帳號 cookie。
2. **帶了反而是風險**：CDN 網域與 API 網域即使是同一間公司,也不代表用同一套 cookie 網域規則；把帳號
   cookie（SESSDATA 等長效憑證）打到 CDN 請求上，等於擴大這組憑證的曝光面（多一個會看到它的伺服器），
   且沒有任何已知功能需要這麼做。
3. `AuthRequirement.never` 作為預設值，加上「音源的認證攔截器只掛在該音源的 API Dio 上、下載/播放的位元
   組請求用**另一個完全沒掛認證攔截器的 Dio 實例**（甚至可以是同一個 dio 套件的裸實例，不套用任何音源
   專屬設定）」——雙重保險：就算某個 CDN 請求不小心被標成需要認證，只要它是透過「位元組下載專用 Dio」
   發出去的，攔截器根本不存在，物理上不可能被注入 cookie。

**建議**：位元組下載（串流播放的 range request、下載到本機檔案）統一走一個獨立的、跨音源共用的「媒體
下載 Dio」，不繼承任何音源的認證攔截器；音源的 API Dio（帶認證攔截器）只負責「換取串流 URL」這一類
metadata 請求，兩者職責與 Dio 實例層級都明確分開，不依賴「記得幫這個請求標 `never`」这種容易遺漏的人工
規則作為唯一防線。

## 4. 需要 owner 決定的事項

1. **`AuthRequirement` 是本次研究提出的設計提案，不是抄某個現成套件或客戶端的既定做法**（dio 官方只提供
   `extra` 這個底層欄位，沒有定義任何「認證需求分級」的慣例）——需要 owner 確認這個三態設計（
   `required`/`optional`/`never`）是否貼合「使用登入態」開關語意上要涵蓋哪些請求的實際需求,或者需要更細的
   分級（例如是否要區分「登入態必須新鮮」與「登入態可以是快取的舊憑證」）。
2. **`flutter_secure_storage` Linux 在無 keyring 環境下的實際失敗模式查不到**（§1.3），需要在 Linux child
   task 的 POC 階段實測（例如全新未設定密碼鑰匙圈的系統、或 keyring 被鎖住時）才能決定要不要為此加一層
   「secure storage 不可用」的降級處理（例如提示使用者需要啟用系統鑰匙圈,或退回明確標示為較不安全的
   儲存方式）。
3. **業務層限流退避沒有找到合適的成熟套件**（§2.5），確認是否接受「自行實作一個共用退避 helper、取代
   舊專案分散在四五個檔案的硬編碼重試邏輯」這個方向，還是有其他既有內部工具可以複用。
