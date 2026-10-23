# 舊憑證：平台讀取器、帳號與憑證的轉換

## 目標

M5 PR 4（上層 `implement.md` § 4；design §0.1、§2.3、§4.3、§5.8、§9「憑證的往返」「舊憑證」）：唯讀讀出舊版存的三個帳號憑證，轉成新版的帳號列與 `LoginCredentials`，並提供換上後寫進 `CredentialStore` 的公開入口。還沒接進啟動流程（PR 6）。

範圍、做法都已由擁有者核准（2026-10-23，design §11 第 9、11 條）。計畫沒涵蓋、會改變行為、範圍或對外介面的決定，停下回報，不自行拍板。

## 現況（以程式碼為準）

- `lib/plugins/accounts/credential_store.dart`：`CredentialStore`，鍵 `credentials.<插件 id>`（`_key`，:103），寫入以 `jsonEncode(credentials.toJson())`（:323）；載入時把沒有憑證的帳號列刪掉（design §3.1 引的 :176-185）。`LoginCredentials` 在 `login_credentials.dart`。
- `lib/platform/secure_storage/flutter_secure_storage_adapter.dart`：11.2.0 的 adapter；類別註解對 Windows 的描述錯了（:13-14，ADR 0029 決定 5 的 2026-10-23 更正）。
- `win32` 6.4.0、`ffi` 2.2.0 目前是間接依賴（`pubspec.lock`）。lint `fmp_layer_imports` 的 `platformPackages`（`app/packages/fmp_lints/lib/src/rules/layer_imports.dart:45`）列出只准 `lib/platform` 用的套件。
- CI 的 Windows 整合測試 job（`.github/workflows/ci.yml` 約 :540-552）已有 `integration_test/secure_storage_test.dart` 一步。
- PR 3 的 `LegacyConverter`（`lib/legacy_import/legacy_converter.dart`）分段轉換，帳號段還沒有；`playlist_remote.writable` 目前只看舊庫有沒有該平台的帳號列（上層 `implement.md`「留下的後續」PR 3）。
- 上層 `research/android-credentials-compat.md`：Android 上 11.2.0 以「無 `storageNamespace`、`resetOnError: false`、`migrateOnAlgorithmChange: false`」讀 10.3.1 的資料的實測；`research/secure-storage-compat.md`：Windows 的 `.dat` 格式。

## 需求

1. **依賴與 lint**：`win32`、`ffi` 改成直接依賴（與 lock 現有版本相容的 stable），加進 `platformPackages`（只准 `lib/platform`）。lint 的雙向變異案例照 `.trellis/spec/app/lints/index.md`，並在 `tool/lint_sentinel.dart` 加違規行。
2. **`LegacyCredentialReader`**（`lib/platform/legacy_data/`）：
   - 介面：給要讀的舊鍵名清單（由 `lib/legacy_import` 傳入，鍵名字面值只能寫在那裡），每個鍵回「有值（字串）／沒有／讀不出」。
   - **Windows**：讀指定目錄的 `flutter_secure_storage.dat` 的位元組 → `CryptUnprotectData`（無 entropy）→ UTF-8 → JSON map → 取鍵。檔案不在：全部「沒有」；解不開或 JSON 壞：全部「讀不出」。**只讀，不寫不刪**。解密是注入的函式；預設實作以 `win32` 呼叫 `CryptUnprotectData` 並以 `LocalFree` 釋放。
   - **Android**：先看 `<資料>/shared_prefs/FlutterSecureStorage.xml` 在不在（路徑由呼叫端或平台層提供），不在就全部「沒有」、**不建立**套件實例；在的話以 `FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false, migrateOnAlgorithmChange: false))`（不帶 `storageNamespace`）逐鍵 `read`，拋例外當「讀不出」。不用 `readAll`（一個壞條目就整批失敗）。選項照 11.2.0 的 API 核對（context7 或 pub cache 原始碼）。
   - 其他平台：全部「沒有」。
   - log 只寫鍵名與結果類別，不寫值。
3. **`CredentialStore.writeImported(SecureStorage, String pluginId, LoginCredentials)`**（design §5.8 最後一點）：公開的靜態方法，共用 `_key` 與編碼，匯入端不另抄一份。
4. **轉換器的帳號段**（design §5.8）：
   - 輸入：snapshot 的 `Account` 列與讀取器的結果；輸出：`ImportBundle.accounts`（`Account`，`avatarJson` 以 `TracksRepository.encodeArtwork` 編碼）與記憶體裡的 `Map<String, LoginCredentials>`（不進 `ImportBundle`，不落地）。`convert` 的回傳要能同時帶出兩者（例如一個轉換結果型別），呼叫端是 PR 6。
   - 舊憑證 JSON 的欄位 → cookie 名稱照 design §5.8 的表；**先對照官方插件的登入程式碼再確認一次 cookie 名稱**（`fmp-plugins` 的 bilibili、netease、youtube 的 login），對不上就停下回報。空字串不寫成 cookie；缺必要 cookie 算讀不出。
   - 讀不出或缺必要 cookie 的平台：不寫帳號，加進 `summary.reloginPlatforms`。帳號列與憑證一定成對。
   - `user_id`、`display_name`、`avatar_json`、`status`、`logged_in_at`、`last_refresh_at` 照 §5.8；`accountWithoutId` 略過。
   - **`playlist_remote.writable`**：改成「該平台的帳號真的匯入了，且 `ownerUserId` 等於它的 `user_id`」。
5. **adapter 的類別註解**：Windows 的描述照 ADR 0029 決定 5 的更正改寫。
6. **測試**（design §9）：
   - Windows 讀取器（Linux 上以假的解密）：缺檔、缺鍵、壞 JSON、解密失敗 → 結果與「檔案位元組與修改時間不變」。
   - Windows 整合 `integration_test/legacy_credentials_test.dart`：以 `CryptProtectData` 加密合成的 JSON（假 cookie）寫到暫存目錄 → 讀回相同；加進 CI 的 Windows 整合 job（`secure_storage_test.dart` 之後一步）。
   - Android：選項（`resetOnError: false`、`migrateOnAlgorithmChange: false`、沒有 namespace）與「沒有舊 prefs 檔就不建立實例」（實例的建立可注入）。
   - 憑證往返：`writeImported` 寫入 → 以真的 `CredentialStore` 載入（帳號列在庫裡）→ 帳號與憑證成對、`isLoggedIn` 為真。
   - 轉換器：三個平台的欄位對照、空字串、缺必要 cookie、讀不出、沒有 id、`writable` 的新規則；憑證值不出現在 log 與 `summary`。
7. **文件**：`app/AGENTS.md` § 舊資料匯入加憑證的唯讀讀法與閘門；`.trellis/spec/app/platform/index.md` 若有平台能力清單就補上。

## 不做

找舊資料的位置（PR 6 的 `LegacyDataLocator`）、換上後實際呼叫 `writeImported`、補記換上後才失敗的平台（PR 6）、設定（PR 5）。**不讀擁有者的真實憑證檔**（`%APPDATA%\com.personal\fmp\flutter_secure_storage.dat`、模擬器上的 `com.personal.fmp`）：測試只用合成資料與假 cookie。

## 驗收

- 測試全綠；`dart run build_runner build --delete-conflicting-outputs` 後沒有實質變動、`dart format --output=none --set-exit-if-changed lib test tool integration_test`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`、`dart run tool/lint_sentinel.dart`。
- Windows 上本機跑一次 `flutter test integration_test/legacy_credentials_test.dart -d windows`（只用合成資料；跑之前備份 `userdata-dev`，跑完還原）。
- 回報：改了哪些檔、cookie 名稱與插件程式碼的對照（檔名與行號）、`convert` 的回傳形狀、計畫沒涵蓋而做了判斷的地方。
