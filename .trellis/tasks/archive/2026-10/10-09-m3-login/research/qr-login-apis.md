# Research: B 站與網易的 QR 登入（插件端，M3 PR 8）

- **Query**: 準備 fmp-plugins 端 `bilibili`、`netease` 的 `login`（QR）：端點、host、狀態碼對應、憑證來源、verify、失效碼、刷新、header、宿主缺口
- **Scope**: internal（舊版 `lib/`、`docs/audit/accounts-network.md`、`../fmp-plugins`、`app/` 宿主契約）；沒有發任何網路請求，沒有複製任何真實 cookie 或 token
- **Date**: 2026-10-09

路徑簡寫：`BAS` = `lib/services/account/bilibili_account_service.dart`，`NAS` = `lib/services/account/netease_account_service.dart`（都在 `C:\Users\Roxy\orca\FMP\`）；插件在 `C:\Users\Roxy\orca\fmp-plugins\`。

## 0. 兩個插件共通

| 項目 | 事實 |
|---|---|
| 宿主契約 | `design.md` §4.3：`loginQrStart() → {qrText, token}`；`loginQrPoll(token) → {status, credentials?}`；`loginVerify(credentials) → {userId, displayName, avatar?}`；`loginRefresh(credentials) → credentials \| null`。憑證 `{cookies, extra?}`。 |
| `Set-Cookie` 取得 | `HttpResponse.headers` 是 `Record<string, string[]>`、名稱小寫（`app/lib/plugins/types/fmp-plugin.d.ts:184-190`），多個 `Set-Cookie` 是陣列的多個元素。`login*` 執行期間 jar 不存它（design §4.3）。舊版解析規則：每筆取第一個 `;` 之前、第一個 `=` 切名稱與值、不 URL-decode（`lib/services/account/http_cookie_parser.dart`，整檔）。 |
| `loginVerify` 自己組 `Cookie` | 傳入的 `credentials.cookies` 組成 `Cookie` header，請求 `auth: 'never'`（design §4.3）。現有 `bilibili.js` 的 `get()`（`bilibili.js:193-201`）固定附匿名 `buvid*` cookie 並標 `userPreference`，不能直接拿來做 verify。 |
| 時序 | 舊版輪詢間隔：B 站 2 秒、上限 90 次（`BAS:161`）；網易 3 秒、上限 60 次（`NAS:140,146`）；連續 5 次網路錯誤就當過期（`BAS:162,224-232`、`NAS:141,213-216`）。新設計由宿主 UI 每 2 秒呼叫 `loginQrPoll`（design §4.3），逾時與連續錯誤的處理屬宿主端，design 沒寫。 |
| 遮蔽 | 宿主內建 `keyNames` 有 `SESSDATA`、`bili_jct`、`DedeUserID`、`DedeUserID__ckMd5`、`csrf`（涵蓋 `__csrf`）、`MUSIC_U`、`musicU`、`eparams`（`app/lib/core/redaction/redaction_lists.dart:22-35`）。**沒有** `refresh_token`、`qrcode_key`、`unikey`、`encSecKey`、`params`；插件 manifest 的 `redaction.keyNames`（`bilibili.js:24-37` 的形式）可追加。 |

## 1. Bilibili

### 1.1 端點

所有請求 header 用舊版 API 預設：`User-Agent` = Chrome/122 桌面 UA、`Referer: https://www.bilibili.com/`、`Origin: https://www.bilibili.com`、`Accept: application/json, text/plain, */*`（`lib/data/sources/source_http_policy.dart:44-53`，UA 值在 `lib/core/utils/http_client_factory.dart:12-14`；`BAS:83` 用 `createApiDio(bilibili)`）。`bilibili.js:48-61` 的 `API_HEADERS` 已是同一組。沒有 `X-Real-IP`。沒有加密、沒有 WBI 簽名。

| 步驟 | 方法與網址 | 參數 | 回應用到的欄位 | 來源 |
|---|---|---|---|---|
| `loginQrStart` | `GET https://passport.bilibili.com/x/passport-login/web/qrcode/generate` | 無 | `data.url`（→ `qrText`）、`data.qrcode_key`（→ `token`） | `BAS:133-143` |
| `loginQrPoll` | `GET https://passport.bilibili.com/x/passport-login/web/qrcode/poll` | query `qrcode_key=<token>` | `data.code`（狀態）、`data.refresh_token`（成功時）、回應的 `Set-Cookie` | `BAS:171-186` |
| `loginVerify` | `GET https://api.bilibili.com/x/web-interface/nav` | 無；`Cookie` 自己組 | 頂層 `code`；`data.mid`、`data.uname`、`data.face`（`data.vip.status` 舊版存 VIP，新設計不存） | `BAS:475-495` |

- 舊版只讀 `response.data['data']['code']`，沒有檢查頂層 `code`（`BAS:178-179`）。
- 舊版 `Cookie` 只有四個名稱：`SESSDATA`、`bili_jct`、`DedeUserID`、`DedeUserID__ckMd5`（`lib/services/account/bilibili_credentials.dart` 的 `toCookieString`）。
- 舊版 verify 只帶這個 cookie 字串（`BAS:476-479`），沒有匿名 `buvid*`。

### 1.2 輪詢狀態碼 → 四個狀態

| `data.code` | 意義（舊版註解） | 新 `status` | 來源 |
|---|---|---|---|
| 86101 | 未掃碼（舊版落在 `default`） | `waiting` | `BAS:214-218` |
| 86090 | 已掃碼待確認 | `scanned` | `BAS:208-213` |
| 86038 | 已過期 | `expired` | `BAS:202-207` |
| 0 | 成功 | `done`（附 `credentials`） | `BAS:182-200` |

舊版把所有不認得的碼當 `waiting`（`default`）。這是舊版行為，不是文件化的碼表。

### 1.3 憑證從哪來

- `cookies`：輪詢成功那一次回應的 `Set-Cookie`，取 `SESSDATA`、`bili_jct`、`DedeUserID`、`DedeUserID__ckMd5`（`BAS:184,188-194`）。必要的三個：`SESSDATA`、`bili_jct`、`DedeUserID` 不得為空（`BAS:99-103`）；`DedeUserID__ckMd5` 與 `refresh_token` 舊版允許空字串。
- `extra`：`{refresh_token: data.refresh_token}`（回應 body，不是 cookie；`BAS:185`）。這是唯一要進 `extra` 的值，PR 10 刷新要用（`BAS:390`）。
- 已知舊版缺口：`code == 0` 但 `Set-Cookie` 解析不出 cookie 時，舊版仍回報成功（`docs/audit/accounts-network.md:61`）。新插件要自己決定這種情況回什麼（design 沒規定）。

### 1.4 verify 欄位與失效碼

- `userId` ← `data.mid`（數字，舊版 `toString()`；`BAS:487`）；`displayName` ← `data.uname`（`BAS:485`）；`avatar` ← `data.face`（`BAS:486`）。`face` 是 hdslb.com 網址；`bilibili.js:322-330` 的 `artwork()` 會補 https、檢查網域、加 `@160w`、`@480w` 後綴，已有 `export`。
- 頂層 `code === 0` 為有效；`-101`（未登入）與 `-111`（csrf 驗證失敗）為憑證無效（`BAS:500-501`）；其他碼為「錯誤」而非無效（`BAS:502-503`）。
- 現有 `businessError`（`bilibili.js:95-117`）把 `-101` 對到 `AuthRequired`，`-111` 沒有對應（落在 `UnexpectedError`）。
- 舊版 auth 攔截器判定「憑證無效」也是 `-101` 或 `-111`，HTTP 200 + body `code`（`lib/services/account/bilibili_auth_interceptor.dart:116-123`）。PR 10 的判定表：`credentialsAttached` 為真且 `code ∈ {-101, -111}`。
- 注意：`wbiKeys()` 的註解寫「未登入 nav 回 -101 但照樣帶 `wbi_img`」（`bilibili.js:253`），所以匿名 nav 的 `-101` 不是憑證失效。

### 1.5 刷新（PR 10 用）

宣告 `refresh: 'onStartup'`。舊版 `refreshCredentials()`（`BAS:351-454`），5 步：

1. `GET passport.bilibili.com/x/passport-login/web/cookie/info`，帶憑證 `Cookie`。`data.refresh != true` → 不需要，回 `null`（`BAS:359-366`）。要用 `data.timestamp`（`BAS:367`）。`needsRefresh` 是同一個呼叫（`BAS:331-348`）。
2. `correspondPath` = RSA-OAEP（SHA-256）加密 `refresh_<timestamp>`，輸出小寫 hex（`lib/services/account/bilibili_crypto.dart:14-25`）。公鑰是寫死的 1024-bit SPKI（同檔 `:29-33`）。
3. `GET https://www.bilibili.com/correspond/1/<correspondPath>`，帶憑證 `Cookie`；從 HTML 用 `<div\s+id="1-name"\s*>(.*?)</div>` 取 `refresh_csrf`（`BAS:373-381,459-462`）。
4. `POST passport.bilibili.com/x/passport-login/web/cookie/refresh`，`application/x-www-form-urlencoded`，body：`csrf`（= `bili_jct`）、`refresh_csrf`、`source=main_web`、`refresh_token`（舊的）；header `Cookie` 是舊憑證（`BAS:384-396`）。回應頂層 `code != 0` → 失敗；新 cookie 從回應 `Set-Cookie`，新 `refresh_token` 從 `data.refresh_token`，任一缺 → 失敗（`BAS:398-413`）。新憑證沒給的 cookie 名稱沿用舊值（`BAS:416-424`）。
5. `POST .../x/passport-login/web/confirm/refresh`，form body：`csrf`（**新** `bili_jct`）、`refresh_token`（**舊**）；`Cookie` 用新憑證（`BAS:433-443`）。舊版不檢查它的回應。
- 舊版任一步失敗一律回 `false`（`BAS:450-453`）→ 新設計是拋 `CredentialInvalid`。
- `www.bilibili.com/correspond/…` 回 HTML，不是 JSON。

### 1.6 manifest 與 host

現況 `allowedHosts`：`api.bilibili.com`、`hdslb.com`、`bilivideo.com`、`bilivideo.cn`、`upos-hz-mirrorakam.akamaized.net`（`bilibili.js:10-16`）。比對規則是「完全相同或以 `.<網域>` 結尾」（`app/lib/core/network/allowed_hosts.dart:41`）。

- PR 8 要加：`passport.bilibili.com`（generate、poll）。
- PR 10 要加：`passport.bilibili.com`（同上，cookie/info、refresh、confirm）與 `www.bilibili.com`（correspond）。
- `api.bilibili.com` 已有（verify 用）。
- 另要加 `capabilities: ["login"]` 與 `login: {methods: ['qr'], …}`；加網域與能力會觸發更新時「能力或網域比目前多」的確認（design §7.4），版本要升（design §7.2）。

## 2. 網易雲音樂

### 2.1 端點

QR 兩個端點用 **weapi** 加密；verify 不加密。舊版的 header：

- QR 與 verify 共用 `_dio`：`User-Agent` = 網易桌面 UA（`Mozilla/5.0 (Windows NT 10.0; WOW64) … Chrome/91.0.4472.164 NeteaseMusicDesktop/3.0.18.203152`）、`Referer: https://music.163.com/`、`Origin: https://music.163.com`、`Accept: application/json, text/plain, */*`（`source_http_policy.dart:61-70`、`NAS:32-35`）；`Content-Type: application/x-www-form-urlencoded`（`NAS:49`）。
- QR 兩個請求另帶**固定的匿名 `Cookie`**（偽裝 Windows 客戶端）：`os=pc; osver=Microsoft-Windows-10-Professional-build-10586-64bit; appver=2.7.1.198277; channel=netease; __csrf=; MUSIC_U=`（`NAS:36-39,48`）。`netease_playlist_service.dart:250` 才有 `X-Real-IP`，QR 與 verify **沒有** `X-Real-IP`（`NAS` 全檔無此字串）。

| 步驟 | 方法與網址 | body | 回應用到的欄位 | 來源 |
|---|---|---|---|---|
| `loginQrStart` | `POST https://music.163.com/weapi/login/qrcode/unikey?csrf_token=` | weapi(`{"type":1}`) | 頂層 `code == 200`、`unikey`；QR 內容 `https://music.163.com/login?codekey=<unikey>` | `NAS:108-123` |
| `loginQrPoll` | `POST https://music.163.com/weapi/login/qrcode/client/login?csrf_token=` | weapi(`{"type":1,"key":<unikey>}`)，**每次重新加密** | 頂層 `code`；成功時 `Set-Cookie`（或 body `cookie` 字串） | `NAS:150-160,163-195` |
| `loginVerify` | `GET https://music.163.com/api/nuser/account/get`，失敗時 fallback `POST https://music.163.com/api/w/nuser/account/get` | 無 | 頂層 `code`、`profile.userId`（或 `account.id`）、`profile.nickname`、`profile.avatarUrl`（`profile.vipType` 舊版存 VIP） | `NAS:320-350` |

weapi 加密（`lib/core/utils/netease_crypto.dart:56-68,93-121`）：JSON → AES-128-CBC（key `NeteaseCrypto._presetKey`、IV `0102030405060708`、PKCS7、base64）→ 再以隨機 16 字元 base62 key 做同樣的 AES-128-CBC → `params`。`encSecKey` = 隨機 key 反轉後的 UTF-8 位元組當大整數，做 `^65537 mod n`（n 是寫死的 1024-bit 模數，無 padding），輸出 hex 左補零到 256 字元。Body 是 `params=…&encSecKey=…`（form）。常量逐字在 `netease_crypto.dart:23-45`。

verify 的 header：`Cookie`（見 2.4）、`Origin`、`Referer`、`User-Agent`（`NAS:592-599`）。

### 2.2 輪詢狀態碼 → 四個狀態

| 頂層 `code` | 意義 | 新 `status` | 來源 |
|---|---|---|---|
| 801 | 等待掃碼（舊版落在 `default`） | `waiting` | `NAS:205-207` |
| 802 | 已掃碼待確認 | `scanned` | `NAS:201-204` |
| 800 | 已過期 | `expired` | `NAS:197-200`；碼表註解 `NAS:128` |
| 803 | 成功 | `done` | `NAS:163-195` |

`code == 803` 之後舊版還做三件事：
1. cookie 優先取 `Set-Cookie`；沒有 `MUSIC_U` 時退到 body `cookie` 字串，用 `;` 切，略過 `path`、`domain`、`expires`、`max-age`、`httponly`、`secure`、`samesite`（`NAS:164-168,557-586`）。
2. `MUSIC_U` 為空或沒有 cookie → 當 `expired`（`NAS:169-182`）。
3. 立刻跑帳號檢查，失敗當 `expired`（`NAS:184-192`）；新設計這步是宿主的 `loginVerify`。

### 2.3 憑證從哪來

- `cookies`：`MUSIC_U`（必要）、`__csrf`（或 `__csrf_token`，可為空字串，`NAS:175-176`）。舊版只存這兩個（加 `userId`，`lib/services/account/netease_credentials.dart`）。
- `extra`：沒有。
- 沒有刷新：`MUSIC_U` 有效期長（註解約 1 年），`refreshCredentials` 恆回 `true`、`needsRefresh` 恆回 `false`（`NAS:21-23,299-305`）。

### 2.4 verify 欄位與失效碼

- `userId` ← `profile.userId ?? account.id`（`NAS:345-346`）；`displayName` ← `profile.nickname`；`avatar` ← `profile.avatarUrl`（`NAS:347-348`）。頭像網址是 `music.126.net`，`netease/src/plugin.js:105-110` 的 `artwork()`（本檔內部函式，未 export）會轉 https、檢查網域並加 `?param=NyN`。
- 有效：頂層 `code == 200` 且 `profile != null`（`NAS:339-350`）。`profile == null` → 無效（`NAS:340-343`）；`code != 200`（註解：301 = 未登入）→ 無效（`NAS:360-362`）。
- 舊版 verify 的 `Cookie`：`MUSIC_U`、`__csrf`（非空才有）、加 `os=pc`、`deviceId=fmp`（`netease_credentials.dart` 的 `toCookieString`，註解說讓 CDN 回桌面端可用網址）。
- 憑證無效（PR 10）：頂層 `code === 301`，且帶了憑證才算（舊版 `netease_auth_interceptor.dart:49-52` 以「已登入」代替 `credentialsAttached`）。外掛現有 `responseCodeError` 已把 301 對到 `AuthRequired`（`netease/src/errors.js:27`）；`streamUnavailableError` 的 `code 301` 與 `code 404 && fee 0` 也是 `AuthRequired`（`errors.js:46,51`），後者匿名請求也會出現（`netease/README.md` 的取流實測），不能單獨當憑證無效。

### 2.5 manifest 與 host

- `allowedHosts` 目前 `['music.163.com', 'music.126.net']`（`netease/build.mjs:14`），子網域比對（`interface3.music.163.com` 已在用，`plugin.js:8`）。**登入不需要新增網域**。
- `build.mjs:6-16` 的 manifest 物件要加 `login` 能力與 `login` 欄位（`methods: ['qr']`，不宣告 `refresh`）；版本現為 `1.0.1`。

## 3. fmp-plugins 現況（可重用與不能直接用的）

| 項目 | 現況 |
|---|---|
| netease `post()` | `netease/src/plugin.js:70-90`：固定 `idempotent: true`、`API_HEADERS`、JSON 解析、`code` 非 200/0 就拋；**沒有傳 `auth`**，預設 `never`（`fmp-plugin.d.ts:174`）。所以目前網易的搜尋與取流登入後也不帶憑證（`grep "auth:"` 全插件只有 `bilibili.js:198`）。QR 輪詢的 `code` 800–803 是狀態不是錯誤，且要讀回應的 `Set-Cookie`，而 `post()` 對 `code` 非 200/0 就拋（`plugin.js:86-88`）、也不回傳 headers，所以 QR 輪詢不能直接用它。 |
| netease 加密 | `netease/src/aes.js` 只有 AES-128-ECB（`aes128EcbEncrypt`，`:102`）、`utf8Bytes`（`:81`）、`hexUpper`（`:117`）；`encryptBlock` 沒 export。沒有 CBC、base64、RSA、隨機數。eapi 在 `plugin.js:93-98`。 |
| netease 常量 | `MAINLAND_IP_HEADERS = {'X-Real-IP': '118.88.88.88'}`（`plugin.js:67`）只用在取流（`:171`）；搜尋不送（`netease/README.md:51`）。 |
| host crypto | 只有 `md5(text)`、`sha256(text)`，輸入是字串的 UTF-8 位元組，輸出小寫 hex（`fmp-plugin.d.ts:204-208`）。 |
| bilibili `get()` | `bilibili.js:193-201`：附匿名 cookie、`auth: 'userPreference'`、`parseJson` 在非 200 就拋；`checkCode()`（`:137-146`）要求 `data` 是物件。poll 的 `data.code` 86101/86090/86038 在 `data` 內，頂層 `code` 是 0。 |
| bilibili 匿名 cookie 與憑證 | design §6.3：同名以憑證為準，插件的 `Cookie` header 其次；現有 `get()` 的匿名 `buvid*` 不會被登入蓋掉。 |
| 版本與 index | 改 `.js` 要升 manifest 版本並重產 `index.json`（design §7.2）；網易是打包產物，改 `src/` 後要跑 `node build.mjs`（`build.mjs:1-2`）。 |
| 測試 | bilibili 有 `test/helpers.test.js`；netease 有 `aes.test.js`、`errors.test.js` 等（`node --test`）。`fixtures/` 只有 `search`、`resolveStream`；目前沒有 `login` 的 fixture 與 `checks.json` 案例（`bilibili/checks.json` 只有 `search`、`resolveStream`）。 |

## 4. 宿主 API 缺口與設計沒寫的地方

以下只列事實，不提建議。

1. **網易 weapi 的原語在插件內都沒有**：AES-CBC、base64 編碼、1024-bit 無 padding RSA、安全隨機數。宿主只有 md5/sha256（`fmp-plugin.d.ts:204-208`）。我在 `app/lib/plugins` 沒找到 `btoa`/`atob`/`BigInt`/`TextEncoder`/`getRandomValues` 的任何提供或使用，所以 QuickJS（`flutter_js` 0.8.7，`app/pubspec.yaml:59`）是否可用 BigInt 與 base64 全域沒有被查證（QuickJS 本身有 BigInt，這點是我的記憶，未驗證）。`aes.js` 的檔頭註解已寫「QuickJS 沒有 TextEncoder」（`:80`）。
2. **B 站刷新（PR 10）需要 SHA-256 作用在任意位元組**：RSA-OAEP 的 label hash 與 MGF1 對二進位資料做 SHA-256，而 `fmp.crypto.sha256` 的輸入是字串、以 UTF-8 編碼，無法表示 0x80 以上的任意位元組。design §5.3 已寫「純 JS 實作」，此處只是確認宿主 API 確實不足以代勞。另需要把 SPKI 公鑰拆成模數與指數（`bilibili_crypto.dart:36-` 的 DER 解析，插件內沒有）。
3. **`loginVerify` 失敗時該拋什麼，design 沒指定**：§6.4 只寫「`loginVerify` 拋錯就不寫，顯示錯誤（ADR 0013 的呈現表）」。`loginVerify` 用 `auth: 'never'`，`credentialsAttached` 一定是 false（design §4.2），所以 §6.5 的「憑證無效」判定表（只在 `credentialsAttached` 為真時成立）對 verify 不適用。
4. **`done` 但沒有可用 cookie 時回什麼，design 沒指定**：舊版 B 站假成功（`docs/audit/accounts-network.md:61`），網易回 `expired`（`NAS:169-182`）。
5. **輪詢逾時與連續錯誤**：舊版在服務內（B 站 3 分鐘／網易 3 分鐘、連續 5 次錯誤），新設計的 `loginQrPoll` 沒有逾時語意，插件拋錯後 UI 如何處理屬 PR 8 宿主端，design §4.3、§6.4 只說 `expired` 顯示「重新產生」。
6. **`loginRefresh` 的 confirm 順序風險**：B 站第 5 步 `confirm/refresh` 會讓舊 `refresh_token` 作廢（舊版在確認前已把新憑證寫入儲存，`BAS:425-443`）；新設計的 `loginRefresh` 在插件內做完 confirm 才回傳，宿主在收到回傳之後才寫入（design §6.5）。兩者之間宿主寫入失敗，舊憑證已失效、新憑證沒落地——design 沒提這個窗口。
7. **網易請求需要自己放 `Cookie` header**：匿名 `Cookie`（2.1）由插件自己在 `fmp.http.request` 的 `headers` 帶；已有先例（`bilibili.js:197`）。`login*` 期間 jar 不存回應 cookie（design §4.3），不會把匿名值回灌。
8. **登入後網易請求才會帶憑證的前提**：網易的 `post()` 沒有 `auth`（見 §3），且舊版取流憑證帶 `os=pc; deviceId=fmp`（`netease_credentials.dart`）；新設計的注入只加憑證 cookie（`MUSIC_U`、`__csrf`），`os=pc`、`deviceId` 要由插件的 `Cookie` header 提供（同名以憑證為準，design §6.3）。這屬插件行為，PR 8 可以不做，但 PR 10 的「憑證無效」判定與 `credentialsAttached` 需要請求帶 `auth`。

## Related Specs

- `.trellis/tasks/10-08-m3-sources-accounts-devtools/design.md` §4.3、§5.2、§5.3、§6.3–§6.5
- `docs/adr/0029-login-credentials-accounts.md` 決定 2、3、7
- `docs/audit/accounts-network.md` §1（登入流程、刷新、QR 假成功）、§2（header 與加密）

## Caveats / Not Found

- 舊版沒有 B 站 QR 與網易 QR 回應的 fixture：`test/services/account/netease_account_service_test.dart`、`test/ui/pages/settings/bilibili_qr_login_tab_test.dart` 有提到 QR，但我沒讀其內容（測試的假資料不等於真實回應）。
- 網易 QR 的其他回應碼（例如風控或需要驗證）舊版沒有處理；查證要發網路請求，這次不做。
- 沒有查到 `scratchpad/musicfree`（以及其他已 clone 的專案）有 B 站或網易 QR 登入實作：搜 `qrcode`、`8821` 無結果。因此上述所有端點與碼都以舊版程式碼為唯一來源，未對照其他實作。
- 舊版 UI 頁（`bilibili_login_page.dart`、`netease_login_page.dart`）的 WebView 流程不在本檔範圍（新設計兩個音源只有 `qr`）。
