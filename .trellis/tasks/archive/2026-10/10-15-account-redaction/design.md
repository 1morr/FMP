# #264 與 #254 準備工作：帳號識別值的遮蔽設計

日期：2026-10-15。只做設計，兩個 repo 都沒改。行號以目前的 `fix/app-live-info-reregister` 與 `fmp-plugins` 工作目錄為準。

## 0. 結論

**不要動鍵名名單**（`builtInKeyNames` 與各 manifest 的 `redaction.keyNames` 都不加 `mid`、`uid`、`vmid`、`uname`、`face`）。
改用「**帳號本身的值**」來遮：

1. **全 App（#264）**：`CredentialStore` 登記憑證時，連同帳號列的 `userId` 一起當已知值登記到 `Redactor`，登出時一起取消。
   B 站、網易雲、YouTube 自己的 id 不管出現在 query、路徑、log 訊息或錯誤報告，都會被遮掉；別的 UP 主的 `mid` 不受影響。
2. **純數字的已知值只在數字邊界比對**（`Redactor`）：自己的 id 不會把較長數字中間的一段換掉，例如 `aid=9123456780` 變成 `aid=9***0`。
   要是被換掉，App 內錄的 fixture 重播時會對不上。
3. **只在錄製時處理（#254）**：`recordCase` 寫檔前，以 `LoginAccount` 的 `userId`、`displayName`、頭像把錄到的流量換成替代值。
   頭像換成同主機的 `https://<host>/***`，插件仍認得它，login 案例的 `nonEmpty: avatar` 照樣過。
   做法跟 `ip_scrub.dart` 一樣：在 `Redactor` 之後、寫檔之前。`accountLeaks` 留著當最後一道檢查，頭像改用「主機＋路徑」比對，補上網易雲漏掉的那種情況。

這樣 #254 的準備工作就不用改 manifest，插件也不用升版（`.js` 不變）。#264 也不用重錄任何 fixture。

---

## 1. 請求的 query 記在哪裡、body 有沒有記

| 出口 | 位置 | 內容 |
|---|---|---|
| 網路紀錄（記憶體歷史與 log 檔） | `app/lib/core/network/network_log.dart:54` 先 `log.redactUrl(uri)`；`:66` 寫 `'query': shown.query` | method、host、path、**query**、status 等。`:34` 明寫「不記 body」，與 ADR 0011 §決定 4（`docs/adr/0011-settings-and-logging.md:39-40`）、否決記 body（`:23`）一致 |
| 欄位再遮一次 | `app/lib/core/logging/log.dart:69`（`redactUrl`）、`:156`（`_redactor.redactValue(fields)`） | `query` 是字串欄位，會再經過鍵名比對與已知值的逐字替換 |
| 誰寫網路紀錄 | `app/lib/core/network/interceptors.dart:355`（插件 API）、`media_http_client.dart`、host fetch | — |
| 錯誤報告（詳細頁、複製、GitHub 回報） | `app/lib/core/errors/error_report.dart:116-138` 用網路紀錄組回 `host+path?query` 再遮一次；`:201` 整份 Markdown 輸出前又遮一次 | 只有網址，沒有 body |
| 診斷包 | `app/lib/app/diagnostics/diagnostics_service.dart:88-90` 把全部 log 檔用**目前的** redactor 重遮（`redactLogFiles`） | 網路紀錄的 query 也在包裡 |
| Debug 頁資料庫瀏覽 | `app/lib/data/repositories/database_inspector.dart:138` 每個值經 `redact` | `accounts.user_id`、`display_name` 會顯示出來（只在畫面上） |
| fixture（錄製） | `app/lib/core/network/fixture/fixture.dart:102-129` | **request body、response body 都會錄**，經 `redact` 或 `redactValue` |
| 插件自己的 log | `fmp.log`、`console` → `Log` | 例如 B 站 `plugin.js:733` 的 `{ uid: anchor.mid }`（這是別人的 id） |

**結論**：query 會進網路紀錄、錯誤報告、診斷包。body 只在 fixture 裡出現。

## 2. B 站自己的 mid 現在有沒有被 DedeUserID 遮到

**有，但有三個前提。**

- 插件存的 cookie：`fmp-plugins/bilibili/src/plugin.js:784-785`。`CREDENTIAL_COOKIES` 含 `DedeUserID`，而且 `REQUIRED_COOKIES` 規定一定要有，所以憑證裡必有它（`:840-842`）。
- `loginVerify` 的 `userId` 是 nav 回應的 `String(data.mid)`（`:893`）。依 B 站慣例 `DedeUserID` 等於 mid：舊專案的 `getUserMid()` 就是直接回 `dedeUserId`（`lib/services/account/bilibili_account_service.dart:276-279`），然後當 `up_mid` 送出（`lib/services/account/bilibili_favorites_service.dart:55,70`）。
- 登記時機（`app/lib/plugins/accounts/credential_store.dart`）：
  - 啟動：`_load` `:112` → `_read` `:166-206` → `_set` `:246-253` 呼叫 `credentials.registerWith`。請求會先等 `ready`，所以不會在登記之前送出。
  - 登入：`save` `:283-290`。刷新：`replace` `:307-322`。失效：`invalidate` `:347-362`。登出：`_forget` `:257-259` 取消登記。
  - 插件端也會登記：`_login` 在執行 `loginVerify` 或 `loginRefresh` **之前**就登記傳入的憑證，之後不取消（`app/lib/plugins/script_source_plugin.dart:219`）；刷新得到的新值也登記（`:178`）。
  - `registerWith` 會略過短於 4 個字元的值（`app/lib/plugins/accounts/login_credentials.dart:43-49`，`Redactor.minimumSecretLength = 4`，`redactor.dart:28`）。

**前提與副作用**：

1. mid 至少 4 位數才會登記（只有極早期的帳號不到 4 位，可以忽略）。
2. **文字裡是子字串比對**：`redactor.dart:175` 的 `result.replaceAll(secret, '***')` 沒有邊界，所以 `aid=9123456780` 會變成 `aid=9***0`。
   結構化欄位裡的數字則是整個值相等才算（`:200`，`_secrets.contains('$value')`）。
3. 這是「巧合」不是設計：它靠的是 B 站剛好把 mid 放在 cookie 裡。網易雲、YouTube 沒有這種 cookie（見 §3）。

## 3. 網易雲、YouTube 自己的 id

- **網易雲**：憑證只有 `MUSIC_U` 與 `__csrf`（`fmp-plugins/netease/src/login.js:74-76`），兩個都是不透明的 token，**不含 uid**，所以今天 uid 沒有被登記。
  - 舊專案讀歌單：`user/playlist` 的 `{'uid': userId, ...}` 包在 `api/linux/forward` 的加密 `eparams` body 裡（`lib/services/account/netease_playlist_service.dart:48,73,261`）。body 不進網路紀錄，`eparams` 也在內建名單上。
  - 但 M4 新插件選哪個端點還沒定：`/api/user/playlist?uid=`（query）、`/api/v1/user/detail/<uid>`（路徑）都有可能。鍵名名單遮不到路徑。
  - 宿主拿得到 uid：`loginVerify` → `accountOf` 的 `userId = profile.userId ?? account.id`（`login.js:104-107`），存在 `accounts.user_id`（`app/lib/plugins/accounts/account_service.dart:117`、`app/lib/data/repositories/account_repository.dart:23`）。
- **YouTube**：`userId` 優先用 datasync id（純數字），其次是頻道 handle，最後是帳號名稱（`fmp-plugins/youtube/src/login.js:50-58`）。innertube 是 POST body，query 裡沒有 id，但 header 或回應裡可能有 datasync id。
- **B 站其他帶 id 的請求**：舊專案還有 `getMedalWallRooms(targetId: mid)`（`bilibili_account_service.dart:526-530`）、`bilibili_live_client.dart:370` 的 `{'mid': uid}`，帶的都是自己的 mid。

**結論**：三個音源自己的 id 都在 `accounts.user_id`，而且在 `CredentialStore._set` 的每個呼叫點（`:206`、`:290`、`:322`、`:362`）手上都有這一列 `Account`，可以直接登記。

## 4. #254 的準備工作與 UP 主 mid 的衝突

- 現在的閘門：`app/lib/plugins/dev/case_runner.dart:339-355`。只有在結果是 `LoginAccount` 時，才用 `accountLeaks`（`:368-392`）檢查錄到的流量裡還有沒有 `userId`、`displayName`、頭像網址，有就不寫。
- 鍵名是「以名稱結尾」比對，對 fixture、log 一律生效（`redactor.dart:214-217`；契約掃描 `app/test/plugins/contract/credential_scan.dart:63-66` 用同一份名單）。
- 現有 fixture 含這些鍵的數量（實際 grep 結果）：

| 鍵 | 檔案 |
|---|---|
| `mid` | `bilibili/fixtures/{login,resolveStream/002,search/001,trackDetail/002}.json` |
| `uid` | `bilibili/fixtures/{live/001,002,003,search/001}.json` |
| `uname` | `bilibili/fixtures/{live/003,login/001,search/001}.json` |
| `face` | 5 個 B 站 fixture，加上 `youtube/fixtures/{mix/003,trackDetail/003}.json` |

**照 issue 的寫法加鍵名，會發生這些事：**

1. 契約測試**立刻變紅**：`scanFixture` 的第二道檢查（`credential_scan.dart` 的 `unredactedInJson`）會把上面這些檔案的 `mid`、`uid`、`face` 報成「沒遮」，第一道「再遮一次會變」也一樣。
   要重錄所有相關案例，但非登入案例只能在命令列錄，而且會打 B 站真實端點（風控）。
2. 重錄之後**語意壞掉**：
   - `face`：trackDetail 的 `uploaderAvatar` 來自 `data.owner.face`（`bilibili/src/plugin.js:525`）。被換成 `***` 後 `artwork('***')` 回 `[]`（`:259-264`），而 `checks.json` 的 trackDetail 期望 `nonEmpty: uploaderAvatar` → **失敗**。
   - `mid`：直播搜尋用 `nonNegativeInt(item.mid)`，是 null 就 `continue`（`:709-711`），主播全被略過。M4 的 UP 主頁與藝人 id 也要用別人的 `mid`，契約根本測不到。
   - 自己的 login 案例：`face` → `***` 會讓 `loginVerify` 的 avatar 變成空的，而 `bilibili/checks.json` 的 login 期望 `nonEmpty: ["userId","displayName","avatar"]` → 失敗。
3. **網易雲的閘門有漏洞**：`artwork()` 會把 `http` 改成 `https`，再加上 `?param=NyN`（`netease/src/plugin.js:112-117`）。
   但回應裡的原值是 `http://p1.music.126.net/...jpg`（見 `netease/fixtures/login/001.json`）。`accountLeaks` 拿正規化後的網址做 `contains`，**找不到原值**，所以真實的頭像會被寫進 fixture。

**另外**：今天 B 站 login 案例的 `mid` 其實已經被 DedeUserID 遮掉了。App 內錄製用的是主 redactor（`app/lib/plugins/dev/dev_case_runs.dart:221,333`），而主 redactor 已登記 App 的憑證。所以 #254 真正卡住的是 `uname` 與 `face`。

## 5. 建議的設計

### 5.1 原則

**遮帳號，就用帳號本身的值，不用鍵名。** 鍵名分不出「自己」和「別人」。帳號的值宿主本來就有（`accounts` 列、`LoginAccount`），而且跟所在位置無關：query、路徑、body、log 訊息都一樣。

### 5.2 落點 A：`userId` 當已知值（#264）

- `CredentialStore._set(pluginId, credentials, status)` 改成接 `Account account`（或至少接 `account.userId`）。登記 `credentials.values` 再加上 `account.userId`（短於 4 個字元就略過，規則和 `registerWith` 相同）。
- `_Entry` 要記住登記過的 `userId`，`_forget` 時一起 `unregisterSecret`。這樣重新登入成另一個帳號時，舊 id 才會取消登記。
- B 站的 `userId` 等於 DedeUserID，登記兩次也無害（`_secrets` 是 Set）。取消時兩者同時取消，行為一致。
- **只登記 `userId`，不登記 `displayName`、頭像**：
  - log、網路紀錄裡本來就不會出現名稱和頭像（不記 body）。
  - 名稱若當成全域子字串遮，可能誤遮一般文字。例如有人名叫 `music`，`music.163.com` 會變成 `***.163.com`，連錄製網址的主機都會壞掉。
  - 2 到 3 個字的中文名字又短於下限，根本不會登記。
  - ADR 0011 §決定 6 的「診斷包不含帳號名稱」，靠的是診斷包本來就不收帳號資訊（`diagnostics_service.dart:242-254` 只收 `loggedIn` 與 `credentials` 狀態）。

### 5.3 落點 B：純數字的已知值只在數字邊界比對（`Redactor`）

- `redact()` 的已知值迴圈（`redactor.dart:174-176`）：值全是數字時，改用 `(?<![0-9])<值>(?![0-9])`；其他已知值維持子字串比對。全數字的值 URL 編碼後不變，`_forms` 不用改。
- 為什麼要一起做：落點 A 讓網易雲的 uid 也成為已知值，16c 與 M4 又是第一次在 App 內帶憑證錄 fixture。只要數字中間有一段被換掉，`fixtureUrlMatches`（`fixture.dart:283-313`）就對不上，因為它只認整段是 `***` 的路徑段或 query 值。
  失效條件寫得出來（見 §7 的測試），所以不算沒有 repro 的修復。
- 覆蓋面沒有縮小：前後是字母或符號的照樣遮（`uid12345678`、`mid=12345678&`、`"12345678||"`）。
- 可以拆開做：主對話若想讓 #264 的 PR 只有落點 A，落點 B 可以單獨一個 PR，但要在 16c 錄製之前合併。

### 5.4 落點 C：錄製時處理帳號值（#254）

- 在 `lib/plugins/dev/` 新增 `scrubAccount(List<HttpFixture>, LoginAccount) → List<HttpFixture>`。放在 plugins 層，因為 `core` 不能 import `LoginAccount`。
  做法是走一遍 `HttpFixture.toJson()` → 換值 → `HttpFixture.fromJson`（`fixture.dart:51`）：
  - `userId`、`displayName`：與 `accountLeaks.found` 用**同一套比對規則**（字串完全相等，或 4 個字元以上時包含；數字是字面相等）。比對到就換成 `***`。
    完全相等不會切到其他文字，所以 2 個字的中文名字也處理得到。
  - 頭像：網址的**主機＋路徑**（不分 scheme、不看 query）等於帳號某個頭像網址的主機＋路徑時，換成 `<原 scheme>://<原主機>/***`。
    三個插件在重播時都還認得這個網址：B 站 `isAllowedHttps` 只看主機（`plugin.js:344-347`）；網易雲的 `toHttps` 加 `isAllowedHttps`；YouTube 的 `AVATAR_URL`（`youtube/src/login.js:14`）。所以 login 的 `nonEmpty: avatar` 仍然成立。
- `recordCase` 的順序（`case_runner.dart:339-361`）：`run.matched` → 如果結果是 `LoginAccount`，先 `scrubAccount(transport.recorded, account)` → 再用 `accountLeaks` 檢查**換過的結果** → `writeFixtures` 寫換過的結果。
- `accountLeaks` 保留作最後一道檢查，頭像改用主機＋路徑比對，補上 §4 第 3 點的漏洞。錯誤訊息裡「請把欄位加進 `manifest.redaction.keyNames`」的提示要改掉。
- `userId` 在全域 redactor 已經被落點 A 遮掉；落點 C 再處理一次，是為了涵蓋短於 4 個字元的 id，也讓兩邊的規則對稱。

### 5.5 否決的方案

| 方案 | 否決的理由 |
|---|---|
| 把 `mid`、`uid`、`vmid` 加進 `builtInKeyNames`（照 #264 原文） | §4：現有 9 個左右的 fixture 會立刻變紅；重錄後 UP 主相關的資料（直播搜尋、M4 藝人 id）測不到。也遮不到路徑裡的 id、網易雲的 `userId`；YouTube 的 id 用的不是這些名字 |
| 在 manifest 的 `redaction.keyNames` 加 `uname`、`mid`、`face`（照 #254 原文） | 一樣是鍵名，套用到同一個插件的**所有** fixture：`face` 會讓 trackDetail 變紅，`uname` 會遮掉主播名稱。名單「只增不減」，加進主 redactor 之後也影響 App 內所有 log |
| 網路紀錄專用、只看 query 的鍵名名單 | 等於有第二套遮蔽規則，違反 ADR 0011 §決定 3「唯一一個」，要新 ADR。也遮不到路徑，還會把使用者瀏覽的 UP 主 id 一起遮掉，而那是除錯有用的資訊（見 §9 第 1 點） |
| 把 `displayName`、頭像也登記成全域已知值 | §5.2：誤遮主機名稱與一般文字；短名字登記不了 |

## 6. 要改的檔案

**FMP（`app/`）**

- `lib/plugins/accounts/credential_store.dart`：`_set` 與 `_Entry` 加上 `userId` 的登記與取消，四個呼叫點（`:206`、`:290`、`:322`、`:362`）傳入 `Account`；類別 doc（`:65-67`）同步更新。
- `lib/core/redaction/redactor.dart`：已知值迴圈改成全數字值走數字邊界；`registerSecret` 的 doc 補一句。
- `lib/plugins/dev/case_runner.dart`：新增 `scrubAccount`（或拆成 `lib/plugins/dev/account_scrub.dart`）；`recordCase` 改順序；`accountLeaks` 的頭像改主機＋路徑比對；錯誤訊息改寫。
- `app/AGENTS.md`：
  - `:558-561`：已知值除了憑證，還有帳號 `userId`；純數字值看數字邊界。
  - `:821-823`：帳號 § 遮蔽要列入 `userId`，閘門的測試名稱也要改。
  - `:1063-1065`：把「要插件加 keyNames」改成「`recordCase` 寫檔前以帳號值換掉，`accountLeaks` 是最後一道」。
- `.trellis/spec/app/plugins/index.md:155-158`：同上，刪掉「加進 keyNames（例如 `uname`、`mid`、`face`）」。

**fmp-plugins**：本設計**不用改**。16c 時仍要照 #254 先刪掉 `login/001.json`（`meta.edited`）再錄。`.js` 沒變，所以不用升版（README 的「版本」一節）。

## 7. 測試

依 CLAUDE.md，行為變更要同時補測試，每條新規則都要在測試裡兩個方向都證明。

1. **`test/plugins/accounts/credential_store_test.dart` 的 `redaction` 群組**
   - `the account's userId is registered on load, save, replace and invalidate, and cancelled on delete`：用類似網易雲的憑證（cookie 裡沒有 id），`userId: '12345678'`，斷言 `redact('up_mid=12345678')` 等於 `'up_mid=***'`；`delete` 之後原樣。
     變異：把 `_set` 裡的登記拿掉，這個測試就紅。
   - 重新登入成另一個帳號：舊 id 不再被遮，新 id 被遮。變異：`_forget` 不取消 `userId`，這個測試就紅。
   - `userId` 短於 4 個字元時略過而且不拋錯（對齊 `registerWith`）。
   - 網路紀錄：登入後呼叫 `writeNetworkRecord`，網址帶 `?vmid=12345678`，斷言記憶體歷史的 `query` 是 `vmid=***`。#264 的情境要有端到端的守護。
2. **`test/core/redaction/redactor_test.dart` 的 `known credential values`**
   - 以已登記的 `12345678` 為例：
     - 要遮：`mid=12345678&`、`/space/12345678/`、`"12345678||"`、`uid12345678`、`12345678abc`。
     - 要保留：`9123456780`、`123456789`。
     - 非數字的已知值仍照子字串遮（`xSECRETy` → `x***y`）。
   - 兩個方向的變異：
     - 拿掉邊界（回到 `replaceAll`）→「保留」那組變紅。
     - 改用 `\b` 邊界 → `uid12345678` 那組變紅。
     - 改用 `\b` 時 `12345678abc` 也會紅：`8` 和 `a` 都是 `\w`，兩者之間沒有詞邊界。
     - 改成套用到所有已知值 → `xSECRETy` 那組變紅。
3. **`test/plugins/dev/dev_case_runs_test.dart`**
   - 現有的 `writes the fixture once the plugin redacts those fields`（`:546`，靠 `keyNames: ['uname','mid']`）改成 `scrubs the account and writes the fixtures`：manifest 不加 keyNames，寫出的檔案裡沒有 `Tester`，`mid` 是 `***`，`face` 是 `https://example.test/***`。
     再用**重播**跑同一個 login 案例，斷言通過（`nonEmpty` 仍成立），守住「契約仍然過」。
   - 現有的 `writes nothing while the account shows in the responses`（`:525`）：換掉之後端到端已經不會觸發。改成 `accountLeaks` 的單元測試：
     - 原值是 `http://…/a.jpg`、帳號頭像是 `https://…/a.jpg?param=1y1` → 抓得到（守 §4 第 3 點）。
     - 只有別人的 `face` 或 `mid` → 不報。
   - `scrubAccount` 的單元測試：
     - 2 個字的 `displayName` 完全相等時會換；它包含在較長字串裡時不換（與閘門的規則一致）。
     - 別人的頭像（主機相同、路徑不同）不換。
     - 變異：把 scrub 從 `recordCase` 拿掉，第一個測試會紅，錯誤訊息會出現。
4. **回歸**：三個插件的契約測試在本機用 `FMP_PLUGIN_DIR` 各跑一次。這個設計沒改鍵名名單，`credential_scan` 不受影響，預期全綠；B 站還要另外跑 `npm test`。

## 8. ADR 與文件

- **需要 ADR 的更正，不需要新 ADR**（照 repo 的「更正（日期，PR）：…」格式，例如 `docs/adr/0015-testing-gates-and-dev-environment.md:66-70`）：
  - ADR 0029 §決定 5（`docs/adr/0029-login-credentials-accounts.md:61`）「載入、寫入時登記遮蔽」：登記的除了憑證值，還有 `accounts.user_id`。
    理由：網易雲、YouTube 的 id 不在 cookie 裡，原本「憑證值就涵蓋帳號 id」的前提只有 B 站成立。這屬於事實上的錯誤。
  - ADR 0011 §決定 3（`docs/adr/0011-settings-and-logging.md:35-36`）「已知憑證值逐字替換」：加一句指向 0029 的更正，並註明純數字值看數字邊界。
  - 主對話若認為「帳號 id 當已知值」是新的跨模組決定，而不是事實更正，就改開一份小 ADR。我判斷更正就夠：機制（已知值逐字替換）沒變，只是擴大登記的範圍。
- 錄製時的換值不用寫 ADR。前例是 `ip_scrub`：它只寫在 `app/AGENTS.md:60-61` 與 spec，沒有 ADR。ADR 0015 §決定 5「寫檔前一律經正式遮蔽函式」仍然成立，換值是在那之後多做的一步。

## 9. 留給擁有者決定的事（產品決定，不是技術問題）

1. **別人的 id 要不要遮**：#264 原文的 `mid`、`uid`、`vmid` 也會遮到使用者瀏覽的 UP 主或主播 id（例如 `x/space/wbi/arc/search?mid=<UP 主>`、直播 `uids[]=`）。
   這些 id 查不到使用者的帳號，但看得出使用者在看什麼。本設計**不遮**：回報「某 UP 主頁打不開」時需要它。擁有者如果認為瀏覽紀錄也算隱私，就需要網路紀錄專用的 query 名單，而那要新 ADR（§5.5）。
2. **login fixture 裡其他的帳號欄位**：閘門只認得 `userId`、`displayName`、頭像。真實回應還有其他欄位：
   - B 站 nav：硬幣、等級、VIP、`email_verified`、`mobile_verified`、`wallet.mid`。`wallet.mid` 落點 C 會換掉。
   - 網易雲 `account/get`：`account.userName`、`createTime`、`vipType`。依記憶 `userName` 可能是手機號的樣子（`1_<號碼>`），**沒有實測**。
   - YouTube `account_menu`：切換帳號的清單可能帶 email 或副標。
   這些欄位只出現在帳號端點，是鍵名真正適合的場合（例如網易雲的 `userName`）。但要不要遮、遮哪些，要擁有者在 16c 錄完之後**逐檔看過**再決定。建議 16c 把「人工看過 login fixture」列為提交前的步驟。
3. **YouTube 的 `userId` 可能退回 handle 或帳號名稱**（`youtube/src/login.js:57`）。落點 A 會把它當全域已知值。在「寧可多遮也不漏」的政策下可以接受，但同名的一般文字會被遮。

## 10. M4 要接手的（不在這次範圍）

- `recordCase` 的換值與閘門目前只在結果是 `LoginAccount` 時執行。M4 出現「需要登入、但不是 login」的案例時（例如收藏、歌單），回應裡自己建立的歌單的 `creator` 就是自己的名字、id 和頭像，**今天沒有任何閘門會擋**。
  那時要讓 `recordCase` 從 `accounts` 列取得帳號（和 PR 16b 留下的第 1 條「隔離環境帶憑證」一起做）。
- 那時重播的網址裡，自己的 id 在 fixture 裡是整段 `***`，`fixtureUrlMatches` 會把它當萬用值，CI 用假憑證重播仍然對得上。

## 11. issue 的處置建議

- #264 與 #254 的「開始前」一段，都建議改成本設計的寫法：#264 從「加鍵名」改成「登記帳號 id」；#254 刪掉「manifest 加 keyNames」，改成「依賴錄製時換值」，並加上 §9 第 2 點的人工檢查。
- 在 issue 上留言或改內容會留下公開紀錄，依全域規則**要先問擁有者**。
