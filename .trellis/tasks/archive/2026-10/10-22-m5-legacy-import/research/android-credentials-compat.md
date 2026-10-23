# Android 實測：flutter_secure_storage 11.2.0 讀 10.3.1 寫的舊憑證

- **日期**: 2026-10-22
- **環境**: Android 模擬器 `Medium_Phone`（emulator-5554），Flutter 3.47.5
- **性質**: 拋棄式 spike。專案在 repo 之外：`<暫存目錄>\fss-probe\`，applicationId `dev.fmp.securestorageprobe`，只用假資料。測完已解除安裝並關閉模擬器。未碰 `com.personal.fmp*` 與 `127.0.0.1:16384`。
- 對應 `secure-storage-compat.md` §1.4 / §1.6 的 Android 推論。

## 結論

| 問題 | 結果 |
|---|---|
| 11.2.0 以 `FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false, migrateOnAlgorithmChange: false))`、無 `storageNamespace`，能讀 10.3.1 以 `const FlutterSecureStorage()` 寫的 4 個鍵嗎？ | **能**。4 個鍵 `equal=true`；`readAll()` 回傳 4 個鍵；`checkUpgradeStatus` 為 `ok`。 |
| 選項名稱在 11.2.0 存在嗎？ | 存在。`lib/options/android_options.dart` 有 `resetOnError`、`migrateOnAlgorithmChange`、`storageNamespace`（`sharedPreferencesName` 已移除）。 |
| 成功讀取會改動舊資料或新增檔案嗎？ | **不會**。讀取前後 `shared_prefs` 清單相同（無新檔），`FlutterSecureStorage.xml` 與 phase A 逐位元組相同，algorithm 標記檔內容不變。 |
| 讀取失敗（`resetOnError:false`）會保留舊條目嗎？ | **會**。壞掉的鍵丟 `PlatformException ... AEADBadTagException`，另外 3 個鍵仍可讀；XML 內 4 個條目都還在，且 XML 與損毀後的輸入逐位元組相同（零寫入、零刪除）。 |
| 預設選項（`resetOnError` true）遇到損毀會怎樣？ | **靜默刪掉壞掉的那個鍵**（XML 1875 -> 1686 bytes），不是整庫清空；其他鍵保留。`read` 回 `null`、無錯誤，呼叫端無法與「從未登入」區分。 |

補充：`readAll()` 在 `resetOnError:false` 下，只要任一條目壞掉就整批丟錯，所以 M5 要逐鍵 `read`，不要用 `readAll` 取值。預設選項下 `readAll` 遇到壞條目的行為這次沒測到（該鍵已被前一個單鍵 `read` 刪掉）；原始碼分析（`handleStorageError` 的 `deleteAll`）預期是清空全部，未實測。

## 做法與指令

專案：`flutter create --platforms=android --org dev.fmp --project-name securestorageprobe fss-probe`。`lib/main.dart` 以 `--dart-define=MODE=...` 切換行為，輸出 `debugPrint('PROBE ...')`：

- `MODE=write`（phase A，依賴 `flutter_secure_storage: 10.3.1`）：`const FlutterSecureStorage()` 寫入 `account_bilibili_credentials`、`account_youtube_credentials`、`account_netease_credentials`（假 JSON）與 `lyrics_ai_api_key`（`fake-key`），讀回比對。
- `MODE=safe`（依賴改 `11.2.0`）：`FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false, migrateOnAlgorithmChange: false))`，先 `checkUpgradeStatus()`，再逐鍵 `read`、最後 `readAll()`。
- `MODE=default`（11.2.0）：`const FlutterSecureStorage()`（`resetOnError` 預設 true），其餘同上。

```
flutter build apk --debug --dart-define=MODE=write     # pubspec: 10.3.1
adb -s emulator-5554 install apk-A-10.3.1.apk
adb -s emulator-5554 logcat -c
adb -s emulator-5554 shell am start -n dev.fmp.securestorageprobe/.MainActivity
adb -s emulator-5554 logcat -d -s flutter | grep PROBE
# pubspec 改 11.2.0 後
flutter build apk --debug --dart-define=MODE=safe      # 另建 MODE=default 一份
adb -s emulator-5554 install -r apk-B-safe.apk         # 升級，資料保留
MSYS_NO_PATHCONV=1 adb -s emulator-5554 shell run-as dev.fmp.securestorageprobe ls -la shared_prefs
```

## Phase A（10.3.1 寫入）

```
PROBE mode=write
PROBE A read account_bilibili_credentials ok=true
PROBE A read account_youtube_credentials ok=true
PROBE A read account_netease_credentials ok=true
PROBE A read lyrics_ai_api_key ok=true
```

`shared_prefs`：
```
-rw-rw---- 536  FlutterSecureKeyStorage.xml
-rw-rw---- 1875 FlutterSecureStorage.xml
-rw-rw---- 307  FlutterSecureStorageConfiguration:FlutterSecureStorage.xml
```
config 檔內容：`ENCRYPTED_PREFERENCES_MIGRATED=true`、`FlutterSecureSAlgorithmStorage=AES_GCM_NoPadding`、`FlutterSecureSAlgorithmKey=RSA_ECB_OAEPwithSHA_256andMGF1Padding`（舊資料已是 OAEP+GCM，與 §1.2 推論一致）。資料鍵前綴 `VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg_`。

## Phase B（`install -r` 升到 11.2.0，safe 選項，無 namespace）

```
PROBE mode=safe
PROBE checkUpgradeStatus=SecureStorageUpgradeStatus(state: ok, reason: none, entryCount: 4, willDiscardOnNextAccess: false, details: Stored data is readable.)
PROBE read account_bilibili_credentials found=true equal=true
PROBE read account_youtube_credentials found=true equal=true
PROBE read account_netease_credentials found=true equal=true
PROBE read lyrics_ai_api_key found=true equal=true
PROBE readAll keys=[account_bilibili_credentials, account_netease_credentials, account_youtube_credentials, lyrics_ai_api_key]
PROBE DONE
```

`shared_prefs` 讀取前與讀取後的清單相同（同樣三個檔、大小 536 / 1875 / 307、mtime 未變）。`FlutterSecureStorage.xml` 與 phase A 取出的副本 `diff` 無差異；config 檔內容不變。

## Phase C（損毀一個鍵，safe 選項）

流程：全新安裝 phase A 的 APK 並寫入 -> `run-as ... cat` 取出 `FlutterSecureStorage.xml`（`tr -d '\r'`）-> 用 `sed` 把 `..._account_youtube_credentials` 值的前 4 個字元（IV）換成 `AAAA` -> `adb push` 到 `/data/local/tmp/c.xml`，再 `run-as sh -c 'cat /data/local/tmp/c.xml > shared_prefs/FlutterSecureStorage.xml'` 寫回，用 `cmp` 確認寫入成功 -> `install -r apk-B-safe.apk` -> 啟動。

（第一次嘗試因每次安裝的 IV 隨機，寫死的 sed 樣式沒匹配到，未損毀；改成通用樣式重跑，下面是重跑結果。）

```
PROBE mode=safe
PROBE checkUpgradeStatus=...state: ok ... entryCount: 4 ...
PROBE read account_bilibili_credentials found=true equal=true
PROBE read account_youtube_credentials ERROR PlatformException(Exception encountered, error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT, javax.crypto.AEADBadTagException: ...
PROBE read account_netease_credentials found=true equal=true
PROBE read lyrics_ai_api_key found=true equal=true
PROBE readAll ERROR PlatformException(Exception encountered, error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT, ...
```

之後 XML 內仍有 `account_bilibili_credentials`、`account_youtube_credentials`（損毀值）、`lyrics_ai_api_key`、`account_netease_credentials` 與兩個 androidx keyset 條目；檔案大小仍 1875；`cmp` 與損毀後的輸入相同。`shared_prefs` 仍只有三個檔。

注意：`checkUpgradeStatus` 只檢查金鑰材料，單一條目密文損毀時仍回 `ok`。M5 要把「單鍵 read 丟 PlatformException」視為「憑證存在但讀不出來」，不能因預檢 `ok` 就假設都能讀。

## Phase D（同一份損毀資料，預設選項 resetOnError=true）

```
PROBE mode=default
PROBE checkUpgradeStatus=...state: ok ...
PROBE read account_bilibili_credentials found=true equal=true
PROBE read account_youtube_credentials found=false equal=false
PROBE read account_netease_credentials found=true equal=true
PROBE read lyrics_ai_api_key found=true equal=true
PROBE readAll keys=[account_bilibili_credentials, account_netease_credentials, lyrics_ai_api_key]
```

`FlutterSecureStorage.xml` 由 1875 縮為 1686 bytes，`account_youtube_credentials` 條目被刪，其餘條目與 keyset 保留；`FlutterSecureKeyStorage.xml`（536）與 config（307）未變。與預期（整庫清空）不同：單鍵 `read` 失敗只刪該鍵，且呼叫端拿到 `null`、沒有錯誤。這是靜默資料損失，所以 legacy 實例必須 `resetOnError: false`。

## 對 M5 的意義

1. `secure-storage-compat.md` §1.4 的 Android 推論成立：用不帶 namespace 的 11.2.0 實例即可讀 10.3.1 舊資料，不需 migration 旗標，不產生新檔。
2. `AndroidOptions(resetOnError: false, migrateOnAlgorithmChange: false)` 在 11.2.0 編譯、執行都正常。
3. 逐鍵 `read` 並捕捉 `PlatformException`；失敗不重試、不刪除；不要用 `readAll` 取值（任一壞條目整批失敗）。
4. 未涵蓋：只測了 emulator 上、舊資料已是 OAEP+GCM 的情境；未測 Keystore 金鑰遺失、PKCS1/CBC 舊格式、其他 API level。
