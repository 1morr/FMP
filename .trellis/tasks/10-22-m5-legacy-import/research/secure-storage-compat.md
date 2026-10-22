# Research: flutter_secure_storage 10.3.1 舊憑證在 11.2.0 下的可讀性

- **Query**: M5 如何讀舊版（flutter_secure_storage 10.3.1）寫下的登入憑證；Android 與 Windows 的格式、金鑰、相容性、會不會改動或刪除舊資料；dev flavor 能否讀 prod 資料的副本
- **Scope**: external（pub cache 內的套件原始碼）+ internal（兩個 repo 的 lockfile 與 adapter）
- **Date**: 2026-10-22

以下 `$PUB` = `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev`。未讀取任何真實憑證檔，也未查詢 Credential Manager。

## 摘要（結論先行）

1. **一個 Dart app 不能同時依賴 10.x 與 11.x，但也不需要。** 11.2.0 在兩個平台都能原生讀 10.3.1 寫的資料：Android 用「沒有 `storageNamespace` 的預設選項」另開一個 `FlutterSecureStorage` 實例；Windows 直接讀同一個 `.dat` 檔。ADR 0010 寫的「用 10.x 讀」前提不成立，可改為「用 11.x 的 legacy 實例唯讀」。
2. **ADR 0029 與 `flutter_secure_storage_adapter.dart` 對 Windows 的描述與 pub cache 內的原始碼不符。** 實際解析到的 `flutter_secure_storage_windows 4.2.2` 主儲存是 **DPAPI 加密的單一 JSON 檔 `flutter_secure_storage.dat`**；AES-GCM + Credential Manager + `<鍵>.secure` 只存在於「backward compatibility」舊路徑，預設關閉。見 §2.2。
3. **Windows 上新舊 App 共用同一個 `.dat`**（prod：`%APPDATA%\com.personal\fmp\flutter_secure_storage.dat`）。舊鍵與新鍵（`fmp.` 前綴）在同一個 JSON map；新 App 的寫入是「整檔載入、改一個鍵、整檔寫回」，會保留舊鍵。
4. **會破壞舊資料的只有失敗路徑：** Windows 的 `load` 在 DPAPI 解密或 JSON 解析失敗時**刪掉整個 `.dat`**（無選項可關）；Android 的 `resetOnError: true` 會在讀取失敗時刪鍵。`app/` 的 Android 已設 `resetOnError: false`，legacy 實例也必須設。

## 1. Android

### 1.1 實際解析版本

| 套件 | legacy `pubspec.lock` | `app/pubspec.lock` |
|---|---|---|
| flutter_secure_storage | 10.3.1（lock:486-493） | 11.2.0（lock:611-618） |
| flutter_secure_storage_platform_interface | 2.0.3（lock:510-517） | 2.1.1（lock:635-642） |
| flutter_secure_storage_windows | 4.1.0（lock:526-533） | 4.2.2（lock:651-658） |
| flutter_secure_storage_darwin / linux / web | 0.3.2 / 3.0.2 / 2.1.1 | 0.4.3 / 3.0.3 / 2.1.1 |

### 1.2 舊版（10.3.1）傳入的選項

`lib/core/secure_key_value_store.dart:43` 是 `const FlutterSecureStorage()`，全部預設。`lib/` 內沒有任何 `AndroidOptions`/`WindowsOptions`（grep 無結果）。

Dart 端預設（`$PUB\flutter_secure_storage-10.3.1\lib\options\android_options.dart:79-81`）：`encryptedSharedPreferences=false`、**`resetOnError=true`**、`migrateOnAlgorithmChange=true`；`storageNamespace`/`sharedPreferencesName` 為 null（送到原生端是空字串，視為未設，`FlutterSecureStorageConfig.java:95-103`）。

> 原生端 Java 預設 `resetOnError=false`（`FlutterSecureStorageConfig.java:17`），但 Dart 端永遠把 `'true'` 送過去（10.3.1 android_options.dart:80；11.2.0 android_options.dart:51 相同）。所以**舊 App 一直以 resetOnError=true 在跑**；11.x 的 `AndroidOptions()` 預設也是 true。

原生端（`$PUB\flutter_secure_storage-10.3.1\android\src\main\java\com\it_nomads\fluttersecurestorage\`）：

| 項目 | 值 | 出處 |
|---|---|---|
| 資料 SharedPreferences 檔 | `FlutterSecureStorage`（`shared_prefs/FlutterSecureStorage.xml`） | `FlutterSecureStorageConfig.java:15`、`:175-177` |
| 鍵前綴 | `VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg_<key>` | `FlutterSecureStorageConfig.java:16`；`FlutterSecureStorage.java:51` |
| 儲存加密 | AES-GCM-NoPadding（`StorageCipherImplementationGCM`，16 byte AES 金鑰） | `FlutterSecureStorageConfig.java:26`；`ciphers/StorageCipherFactory.java:87-94` |
| 金鑰包裝 | RSA/ECB/OAEP SHA-256 + MGF1（Keystore 內的 RSA 金鑰對包住 AES 金鑰） | `FlutterSecureStorageConfig.java:27` |
| Keystore alias | `<packageName>.FlutterSecureStoragePluginKeyOAEP`（無 suffix）→ prod 為 `com.personal.fmp.FlutterSecureStoragePluginKeyOAEP` | `ciphers/KeyCipherImplementationRSAOAEP.java:30` |
| 被包裝的 AES 金鑰存放 | `shared_prefs/FlutterSecureKeyStorage.xml` 內鍵 `AESVGhpcyBpcyB0aGUga2V5IGZvciBhIHNlY3VyZSBzdG9yYWdlIEFFUyBLZXkK` | `FlutterSecureStorage.java:1364`；11.2.0 `UpgradeInspector.java:52` |
| 演算法標記 | config prefs 內 `FlutterSecureSAlgorithmKey` / `FlutterSecureSAlgorithmStorage` | `ciphers/StorageCipherFactory.java:13-15` |
| EncryptedSharedPreferences | 預設不使用 | `FlutterSecureStorageConfig.java:20` |

10.x 首次存取時若沒有演算法標記，視為 v9.2.4 預設（RSA PKCS1 + AES-CBC），並依 `migrateOnAlgorithmChange=true` 重加密為 OAEP + GCM（`StorageCipherFactory.java:30-38, 51-58`）。因此**只要舊 App 在 10.x 下存取過一次 secure storage，資料就已是 OAEP+GCM**。

### 1.3 新版（11.2.0）與 `app/` 傳入的選項

`app/lib/platform/secure_storage/flutter_secure_storage_adapter.dart` 的 `androidOptions`：`AndroidOptions(resetOnError: false, storageNamespace: 'fmp' | 'fmp-dev')`，鍵再加 `fmp.`／`fmp-dev.` 前綴。

`storageNamespace` 非空時（10.3.1 與 11.2.0 的 `FlutterSecureStorageConfig.java` 皆有 `getEffectiveDataPrefsName` / `getEffectiveKeyStoragePrefsName` / `getKeyAliasSuffix`；10.3.1 在 `:175-197`）：

| 項目 | 舊版（無 namespace） | `app/` 現行（namespace `fmp`） |
|---|---|---|
| 資料 prefs 檔 | `FlutterSecureStorage` | `fmp` |
| 包裝金鑰 prefs 檔 | `FlutterSecureKeyStorage` | `FlutterSecureKeyStorage:fmp` |
| Keystore alias | `com.personal.fmp.FlutterSecureStoragePluginKeyOAEP` | `com.personal.fmp.FlutterSecureStoragePluginKeyOAEP.fmp` |

→ **用 `app/` 現行 adapter 的實例讀不到任何舊資料**（完全不同的檔與金鑰），兩者互不污染。

11.2.0 與 10.3.1 預設加密相同：AES-GCM + RSA-OAEP（11.2.0 `FlutterSecureStorageConfig.java:27-28`；`StorageCipherFactory.java:16-17`），鍵前綴預設相同（`FlutterSecureStorageConfig.java:17`）。11.0.0 移除的是 `RSA_ECB_PKCS1Padding`、`AES_CBC_PKCS7Padding`、`encryptedSharedPreferences`、`sharedPreferencesName`（11.2.0 `CHANGELOG.md:43-56`），都不是 10.3.1 的預設路徑。

### 1.4 11.2.0 能否讀 10.3.1 寫的條目？

**能。條件：**

- 用**不帶 `storageNamespace`** 的實例，例如 `FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false))`（11.x 已無 `sharedPreferencesName` 參數，不需要）。這樣原生端算出的資料檔、金鑰檔、alias 與舊版完全一致（`getEffectiveDataPrefsName` 回 `FlutterSecureStorage`；`KeyCipherImplementationRSAOAEP.java:41` alias 無 suffix）。
- 舊資料已是 OAEP+GCM（§1.2）。若標記是已移除的 PKCS1/CBC，11.x 的 `UpgradeInspector` 會回報 `legacyDataUnreadable`（11.2.0 `UpgradeInspector.java:113-124`），讀不了；legacy 現在已是 10.3.1，正常使用過的資料不會是這樣。
- 11.x 有 `checkUpgradeStatus()`（`$PUB\flutter_secure_storage-11.2.0\lib\flutter_secure_storage.dart:408`），「Read-only: it checks that key material exists before building any cipher」（`UpgradeInspector.java:18-23`），可在讀之前預檢；狀態 `ok / legacyDataUnreadable / legacyDataDiscarded / unknown`。
- 不需要任何 migration 旗標。`migrateOnAlgorithmChange` 預設 true，只在演算法標記與目前設定不同時才觸發（11.2.0 `FlutterSecureStorage.java:357-360`），兩邊都是 OAEP+GCM，不觸發。

### 1.5 與 `app/` 現行 namespace 實例並存是否互相干擾

- plugin 內以 `ns:<namespace>` 或 pref 名為 key 各自快取一個 `FlutterSecureStorage`（10.3.1 `FlutterSecureStoragePlugin.java:87-102`；11.x 同邏輯），兩個 Dart 實例互不影響。
- 11.x 的 `LegacyNamespaceKeyRecovery.recoverIfNeeded`（11.2.0 `ciphers/LegacyNamespaceKeyRecovery.java:48-116`）在 namespace 實例初始化時，會嘗試把「無 namespace 的包裝金鑰」複製到 `FlutterSecureKeyStorage:fmp`。前置條件 `hasWrappedKey(target) || !hasWrappedKey(source) || !hasEncryptedData(...)` 任一成立就 return（`:79`）；新實例的資料檔 `fmp` 在第一次寫入前是空的 → `hasEncryptedData` 為 false → 直接 return。即使觸發，也先用 `keyDecryptsOwnData` 驗證（`:95`），且「The source copy is left in place」（`:23-24`）。**只新增、不改舊來源，不會改動或刪除舊金鑰檔。**
- legacy（非 namespace）實例初始化時 recover 的方向是 namespaced→plain，`hasWrappedKey(target)` 在舊金鑰存在時為 true → return（`:79`）。

### 1.6 `resetOnError` 風險

- 讀取失敗時 `handleStorageError`：`resetOnError=true` 就 `delete(key)`（單鍵）或 `deleteAll()`（readAll）後重試（11.2.0 `FlutterSecureStorage.java:1323-1358`；呼叫點 `:62, :93, :136`）。plugin 層 catch 在 `resetOnError` 時也會 `secureStorage.deleteAll()`（11.2.0 `FlutterSecureStoragePlugin.java:271-285`）。
- 初始化金鑰不符時 `handleKeyMismatch`→`deleteAllDataAndKeys` 會**刪 Keystore 金鑰、刪資料條目、清包裝金鑰 prefs**（11.2.0 `FlutterSecureStorage.java:1016-1112`），同樣受 `resetOnError` 控制（`:1043, :1060`）。
- 因此 legacy 實例**必須** `resetOnError: false`；`app/` 現行實例已是 false（adapter `androidOptions`；ADR 0029:98 稱 `platform_test.dart` 有斷言）。
- 即使 `resetOnError=false`，11.x 仍有幾處**非破壞性**寫入：`StorageCipherFactory` 建構子在沒有演算法標記時寫入目前標記（`StorageCipherFactory.java:48-56`）；`StorageCipherImplementationGCM` 在找不到包裝金鑰時**產生新金鑰並寫入**（`StorageCipherImplementationGCM.java:47-54`）；`KeyCipherImplementationRSAOAEP` 建構子會 `createRSAKeysIfNeeded`（`:42`）。這些只在「舊資料／金鑰不存在」時發生，對已有舊資料的使用者不觸發；對沒有舊資料的新使用者，會在 legacy 檔位置留下空金鑰（無害但留痕）。M5 應先判斷舊 prefs 是否存在或用 `checkUpgradeStatus` 預檢，再決定是否建立 legacy 實例。

### 1.7 dev flavor 與 prod 的隔離（Android）

- `app/android/app/build.gradle*`：prod `applicationId = "com.personal.fmp"`（行 39），dev `applicationIdSuffix = ".dev"`（行 78）→ `com.personal.fmp.dev`。
- 資料 prefs 在各 package 私有的 `/data/data/<applicationId>/shared_prefs/`，dev 無法讀 prod 的 `FlutterSecureStorage.xml`；Keystore 金鑰屬於建立它的 App（alias 前綴也是 `getPackageName()`，`KeyCipherImplementationRSAOAEP.java:41`）。[Android Keystore 文檔](https://developer.android.com/privacy-and-security/keystore) 說明金鑰材料受保護不可抽出。**結論：dev 在 Android 上看不到 prod 的舊憑證**；沒有 root 也無法把 prefs 搬給 dev，搬了也沒有金鑰。此段屬 Android 沙箱機制，套件原始碼只間接佐證。
- 舊 App `android/app/src/main/AndroidManifest.xml:41` `allowBackup="false"`（說明在 `:26`），不存在雲端備份還原後 Keystore 金鑰消失的路徑。

## 2. Windows

### 2.1 舊版（10.3.1 → `flutter_secure_storage_windows 4.1.0`）

純 Dart FFI 實作（`$PUB\flutter_secure_storage_windows-4.1.0\lib\src\flutter_secure_storage_windows_ffi.dart`），主儲存 `DpapiJsonFileMapStorage`：

- 檔名 `flutter_secure_storage.dat`（`:234`），位置 `getApplicationSupportDirectory()`（`:252-260`）。
- 內容：整個 `Map<String,String>` 以 `jsonEncode` → UTF-8 → **`CryptProtectData`**（無額外 entropy、flags=0，即目前使用者範圍）寫入（`:383-458`）；載入用 `CryptUnprotectData`（`:300-314`）。
- 沒有 Credential Manager、沒有 AES-GCM 金鑰、不依賴 app／product 名稱；金鑰來自 Windows 使用者設定檔。
- `useBackwardCompatibility`：`WindowsOptions` 預設 `false`（`$PUB\flutter_secure_storage-10.3.1\lib\options\windows_options.dart:25`），`FlutterSecureStorage` 會把它以 `'false'` 傳下去，所以舊 App 沒有走 C++ 舊路徑。（`...ffi.dart:24-25` 的擴充 getter 對「沒給」視為 true，但 `FlutterSecureStorage` 一定會傳。）

### 2.2 新版（11.2.0 → `flutter_secure_storage_windows 4.2.2`）

- 儲存層與 4.1.0**完全相同**：同一個 `flutter_secure_storage.dat`（`$PUB\flutter_secure_storage_windows-4.2.2\lib\src\flutter_secure_storage_windows_ffi.dart:257`）、`getApplicationSupportDirectory()`（`:276`）、DPAPI（`CryptUnprotectData` / `CryptProtectData`）。差異只有改用 win32 6.0 API（CHANGELOG 4.2.0）與加 mutex（`_lock.run`，CHANGELOG 4.2.1/4.2.2）。
- `WindowsOptions` 預設 `useBackwardCompatibility=false`（11.2.0 `lib/options/windows_options.dart:25`）；`app/` adapter 未傳 `WindowsOptions`。
- 套件 README 的「AES-GCM、Credential Manager 金鑰、`.secure` 檔」（`$PUB\flutter_secure_storage_windows-4.2.2\README.md:9`）描述的是 **C++ plugin 舊路徑**（`windows/flutter_secure_storage_windows_plugin.cpp:265` Credential Manager target `key_<prefix>`；`:494`、`:560` `<鍵>.secure`），只有 `useBackwardCompatibility=true` 才會經 MethodChannel 呼叫它（ffi 檔各方法的 `options.useBackwardCompatibility` 分支，約 `:88-205`）。
- ADR 0029:43、:57 與 `flutter_secure_storage_adapter.dart` 類別註解寫的「Windows：AES-GCM `.secure` 檔、金鑰在 Credential Manager、鍵直接當檔名」，與上述原始碼不符；實際上 `app/` 在 Windows 寫的是同一個 `.dat` 內的 `fmp.`／`fmp-dev.` 前綴鍵。

### 2.3 檔案位置與 dev/prod

- `path_provider_windows 2.3.0`：`getApplicationSupportPath` = `%APPDATA%\<CompanyName>\<ProductName>`（`$PUB\path_provider_windows-2.3.0\lib\src\path_provider_windows_real.dart:119-120, 181-218`）。
- legacy `windows/runner/Runner.rc:92,98`：`com.personal` / `fmp`。`app/windows/runner/Runner.rc:92,98`：`com.personal` / `FMP_PRODUCT_NAME`（prod `fmp`、dev `fmp-dev`，依任務描述）。
- prod：新舊 App 讀寫**同一個** `%APPDATA%\com.personal\fmp\flutter_secure_storage.dat`；舊鍵（如 `account_bilibili_credentials`）無前綴，新鍵 `fmp.…`。dev：`%APPDATA%\com.personal\fmp-dev\flutter_secure_storage.dat`，與 prod 不同檔。
- DPAPI 與 app／product 名稱無關，所以**把 prod 的 `.dat` 複製到 `...\fmp-dev\` 就能被 dev 讀**（同一 Windows 使用者）。只需複製這一個檔案，**不需要任何 Credential Manager 條目**，也不會碰 prod 的條目；複製是唯讀動作。

### 2.4 11.2.0 能否原生讀舊檔？

能。`FlutterSecureStorage().read(key: 'account_bilibili_credentials')` 在 Windows 會 `load()` 整個 map 再取鍵（4.2.2 ffi `read`：`final map = await _storage.load(options); var result = map[key];`；`useBackwardCompatibility=false` 時沒有其他動作）。adapter 的 `_validKey` 與前綴只限制 `SecureStorage` 包裝層；若 M5 的 legacy reader 直接用 `FlutterSecureStorage`（不經 adapter）就能讀無前綴的舊鍵。

## 3. 是否會改動／刪除舊資料（逐項）

| 路徑 | 平台 | 是否改動 | 出處 |
|---|---|---|---|
| `read` / `readAll`（`useBackwardCompatibility=false`） | Windows | 成功時不寫、不刪 | 4.2.2 ffi `read`/`readAll` |
| `load` 時 DPAPI 解密失敗、JSON 損毀、非 object | Windows | **刪整個 `.dat`**，無選項可關 | 4.2.2 ffi `load` 內三處 `await file.delete()`（4.1.0 `:338-373`） |
| `write` 任一鍵 | Windows | 整檔載入→改一鍵→整檔寫回，其他鍵保留 | 4.2.2 ffi `write` |
| 套件的 `deleteAll()` | Windows | 刪整個 `.dat`（含舊鍵） | 4.2.2 ffi `clear` |
| `app/` adapter 的 `deleteAll()` | 兩者 | 只逐一刪 `fmp.` 前綴鍵，不碰舊鍵 | `flutter_secure_storage_adapter.dart` `deleteAll` |
| 讀取失敗且 `resetOnError=true` | Android | 刪單鍵／全部；初始化金鑰不符時刪 Keystore 金鑰與全部資料 | 11.2.0 `FlutterSecureStorage.java:1016-1112, 1323-1358`；`FlutterSecureStoragePlugin.java:271-285` |
| 演算法標記缺失／不同 | Android | 缺失：寫入標記；不同且 `migrateOnAlgorithmChange=true`：解密後以新演算法重寫（失敗且 `resetOnError=false` 只報錯不刪） | `StorageCipherFactory.java:48-56`；`FlutterSecureStorage.java:1016-1050` |
| 11.x `deleteAll` | Android | 只刪鍵前綴符合的條目 | 11.2.0 `CHANGELOG.md`（11.2.0 "scope deleteAll to the key prefix"） |

沒有「讀取即重加密」的路徑，除非演算法標記不一致。

## 4. 建議

**推薦：不引入 10.x，不自製解密；用 11.2.0 開第二個「legacy 唯讀實例」，限定在 `app/lib/legacy_import/`。**

1. Android：`FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false))`，**不傳** `storageNamespace`，鍵用舊名（`account_bilibili_credentials`、`account_youtube_credentials`、`account_netease_credentials`、`lyrics_ai_api_key`）。讀之前：
   - 先確認 `shared_prefs/FlutterSecureStorage.xml` 是否存在，或用 `checkUpgradeStatus(aOptions: …)` 預檢；沒有舊資料就不建立實例，避免 §1.6 的「新建空金鑰」副作用。
   - 預檢結果非 `ok` 時當作「憑證存在但讀不出來」（沿用舊版 `SecureStorageUnavailable` 的語意），不當成未登入，也不重試刪除。
2. Windows：同樣用 `FlutterSecureStorage()`（預設 `WindowsOptions`），舊鍵與新鍵在同一檔。讀之前先把 `flutter_secure_storage.dat` 複製為備份，以抵銷 §3「解密失敗就刪整檔」的風險；**不要呼叫套件的 `deleteAll()`**，M5 清舊憑證只能逐鍵 `delete`。
3. 兩個平台都在「匯入成功且新儲存（`app/` adapter，`fmp.` 前綴）已寫入並驗證」之後才刪舊鍵。
4. dev 驗證：
   - Windows：把 prod 的 `.dat` 副本複製到 `%APPDATA%\com.personal\fmp-dev\flutter_secure_storage.dat`（只複製檔案，不需 Credential Manager；同一 Windows 使用者即可解密）。複製真實憑證檔屬於處理真實憑證的動作，應由 owner 本人執行。
   - Android：dev（`com.personal.fmp.dev`）看不到 prod 的 prefs 或 Keystore，無法用副本驗證；只能用 legacy 的 dev 建置寫入測試憑證再測，或在 prod 建置上驗證。

取捨：

- 選項 A（推薦，11.x legacy 實例）：無額外依賴、無自製密碼學；代價是要自己守住 `resetOnError:false` 與預檢，且 Windows 解密失敗會刪檔（靠備份補）。
- 選項 B（自製 Windows reader：`CryptUnprotectData` + JSON）：格式很簡單、可行，但要新增 `win32` 直接依賴與 FFI 程式，且仍讀同一個檔，沒比 A 安全；不建議。
- 選項 C（Android 自製 Keystore reader／platform channel）：要自己實作 RSA-OAEP unwrap + AES-GCM 解密與 prefs 解析，等於重寫 `StorageCipherImplementationGCM`；成本高。不建議。
- 不可行：同時依賴 10.x 與 11.x（pub 單一版本約束）；而且兩版原生 plugin 使用同名 MethodChannel `plugins.it_nomads.com/flutter_secure_storage`（10.3.1 `FlutterSecureStoragePlugin.java:40`），也無法並存。

## Caveats / Not Found

- 未在實機驗證，以上皆為讀原始碼的結論。建議 M5 測試：在 Android 模擬器用 legacy 10.3.1 建置寫入四個鍵，再以 11.2.0 legacy 實例讀回；Windows 用自建的 `.dat`（不要用真實檔）。
- Android「dev 看不到 prod Keystore」是沙箱機制，原始碼只間接佐證。
- 若舊 App 曾從 v9 以下直升而從未在 10.x 下存取過 secure storage，資料可能仍是 PKCS1/CBC 且無標記；11.x 讀不了（`UpgradeInspector.java:113-124`）。
- 對 ADR 0029 與 adapter 註解的 Windows 描述所指出的不符，依據是 pub cache 內 4.2.2 原始碼；若實測（dev flavor 寫入後檢查 `%APPDATA%\com.personal\fmp-dev\` 是 `.dat` 還是 `*.secure`）結果不同，以實測為準。
- Windows `load` 約行號（4.2.2 ffi 的 `file.delete()` 區段、`read`/`write` 方法行）未逐行標註，只標到區段。
