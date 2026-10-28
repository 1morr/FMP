# App 的狀態、資料與開發入口

## 資料目錄

解析邏輯在 `app/lib/platform/app_data_directory/`（ADR 0009 §決定 7）。下面的 `<資料目錄>` 指：

| 平台 | dev | prod |
|---|---|---|
| Windows 免安裝版（程式目錄沒有 `unins000.exe`；`flutter run`、直接跑建置產物都是這種） | 執行檔旁的 `userdata-dev\` | `userdata\` |
| Windows 安裝版（有 `unins000.exe`） | `%APPDATA%\com.personal\fmp-dev` | `%APPDATA%\com.personal\fmp` |
| Android | `/data/data/com.personal.fmp.dev/files`（`run-as com.personal.fmp.dev`） | `com.personal.fmp` 的 `files`：**不要碰** |
| macOS | `~/Library/Application Support/com.personal.fmp.dev` | `~/Library/Application Support/com.personal.fmp` |

dev 解析到舊版正式資料的位置（Windows 的 `Documents\FMP`、`%APPDATA%\com.personal\fmp`、Android 的
`com.personal.fmp` 沙盒）會在啟動時拋 `LegacyDataLocationException`：視窗開了但內容空白。

內容：

- `fmp.db`：drift 的 SQLite（沒開 WAL，只有這一個檔）。表 `appearance_settings`、
  `installed_plugins`（`id`、`version`、`manifest_json`、`script`、`installed_at` 是 UTC epoch 毫秒）、
  `plugin_storage`（`plugin_id`、`key`、`value`，外鍵 cascade）。SQL 的欄位名是 snake_case，
  不是 Dart 的 getter 名。之後的里程碑會加表，以 `lib/data/database/tables.dart` 為準。
- `logs/fmp.jsonl`（與輪替的 `fmp.1.jsonl`、`fmp.2.jsonl`）：JSON Lines，單檔 2MB，已經過遮蔽。
  每行 `{"time","level","tag","message","fields"}`，例如
  `{"level":"info","tag":"app","message":"App started","fields":{"flavor":"dev","buildMode":"debug"}}`。
  驗證時用 `tag` 與 `message` 找（`App started` 的 `flavor`、`dataDirectory`，
  `Installed a plugin from the development entry`、`Track requested`、`Look-ahead handover`、
  `Track audible`、`Search failed`、`Playback stopped`）。`dataDirectory` 含使用者名稱，引用時改成
  `<資料目錄>`。

## 讀狀態

優先讀 log 與資料庫，而不是畫面。資料庫要在 App 關掉（或至少沒在寫）時讀；有 `sqlite3` 命令列時：

```bash
sqlite3 <資料目錄>/fmp.db "select id, version, installed_at from installed_plugins"
```

Android 把 `fmp.db` 拉回來讀，要用 `exec-out`（`adb shell` 會改掉二進位內容，檔案變大、打不開）：
`adb exec-out run-as com.personal.fmp.dev cat files/fmp.db > <暫存目錄>/fmp.db`。
Dart VM Service（`flutter run` 印的 URI）可讀活的物件；URI 是本機除錯憑證，回報只寫埠與用途。

## 清成乾淨狀態

**先看再刪，只刪 dev 的。**

1. 先確認路徑：Windows 是 `build\windows\x64\dev\runner\<模式>\userdata-dev`（路徑裡要有 `dev`），
   Android 是 `com.personal.fmp.dev`。`ls` 一次，內容是 `fmp.db`、`logs`（Android 另有
   `profileInstalled`）才刪。
2. 關掉 App，再刪：Windows 刪 `userdata-dev\` 整個目錄（或只刪 `fmp.db` 保留 log）；
   Android `adb shell pm clear com.personal.fmp.dev`（只清 dev 這個 package）。執行前再看一次
   package 名稱以 `.dev` 結尾：少了 `.dev` 清掉的是舊版的資料，無法復原。
3. 不要對 `userdata\`、`%APPDATA%\com.personal\fmp`、`Documents\FMP`、`com.personal.fmp` 做任何刪除。

## 開發入口（只在 dev flavor；prod 一律忽略）

原始碼：`lib/plugins/install/dev_plugin_entry.dart`。播放一律走 UI：搜尋頁選音源、搜尋、點一首
是臨時播放（不進佇列、播完回到佇列）；要排佇列用每首的選單（右鍵、長按或尾端「⋯」）的
「下一首播放」「加入佇列」，再按播放列的播放。

| 入口 | 作用 |
|---|---|
| `--fmp-dev-plugin=<路徑>` 或環境變數 `FMP_DEV_PLUGIN` | 啟動時安裝該路徑的插件安裝檔（`.js`）；兩者都有時參數優先。已安裝同 id 的視為更新 |

| 插件 | 安裝檔 | 模式 |
|---|---|---|
| 測試插件 `fmp-test`（音源名稱 `FMP Test Plugin`） | `app/test/fixtures/plugins/test_plugin/test_plugin.js` | 重播：搜尋任何關鍵字都回三首（第一頁兩首、「載入更多」第三首），串流是 dev 版內附的 2 秒 wav，不連網；關鍵字剛好是 `fail` 時搜尋以限流失敗，用來看錯誤提示；`missing`、`preview`、`flaky`、`unavailable` 造播放恢復的情境（前瞻開不起來、試聽、重試與等網路、跳過），說明在旁邊的 `README.md` |
| 僅元資料的測試插件 `fmp-test-meta`（音源名稱 `FMP Test Metadata Plugin`） | `app/test/fixtures/plugins/test_meta_plugin/test_meta_plugin.js` | 重播：只有 `importPlaylist`，認 `https://fmp.test/meta/<id>`，不連網；`meta-basic`（6 首，4 首匹配得到 `fmp-test`、2 首匹配不到）、`meta-truncated`（最後一頁 `truncated`）、`meta-broken`（第 2 頁失敗）給匯入預覽頁；要先裝 `fmp-test` 當匹配目標（兩個都要時分兩次以入口安裝，裝好的留在清單上），說明在旁邊的 `README.md` |
| B 站 `bilibili` | `fmp-plugins/bilibili/bilibili.js`（與 FMP 同層的 clone） | 真實：搜尋與解析都連網，照 SKILL.md 只做最少的操作 |

- Windows 直接給絕對路徑；Android 要先複製進 App 的私有目錄（`android.md`）。
- Windows 的環境變數只對該行程有效：PowerShell 用
  `$env:FMP_DEV_PLUGIN='<路徑>'; Start-Process ...; Remove-Item Env:FMP_DEV_PLUGIN`。
- 裝好的插件留在 `installed_plugins`，之後不帶參數啟動也會載入。

## 舊資料匯入的入口（M5，只在 dev flavor；prod 一律忽略）

原始碼：`lib/platform/legacy_data/legacy_dev_entry.dart`。首次啟動（`<資料目錄>` 沒有 `fmp.db`）時，dev 只讀這個入口指的資料夾，不讀真實的舊資料位置。

| 入口 | 作用 |
|---|---|
| `--fmp-legacy-dir=<資料夾>` 或環境變數 `FMP_LEGACY_DIR` | 資料夾裡的 `fmp_database.isar`（必要）當作舊資料庫；Windows 另讀可選的 `flutter_secure_storage.dat`（DPAPI，同一個 Windows 使用者才解得開）。兩者都有時參數優先 |

- 合成舊庫（編造的資料，不含真實內容）：在 `app/` 執行 `dart run tool/legacy_fixture.dart <暫存目錄>/legacy-copy`。
  **只用合成資料或擁有者自己備好的副本**；資料夾不可等於或位於 `Documents\FMP`、`%APPDATA%\com.personal\fmp`、`com.personal.fmp` 的沙盒，否則啟動記 log 後照空資料啟動。
- Windows：先備份 `userdata-dev\`（`Copy-Item -Recurse`），再清空它（讓 `fmp.db` 不存在），然後帶參數啟動：
  `.\fmp.exe --fmp-legacy-dir=<暫存目錄>\legacy-copy`（或 `flutter run -d windows --flavor dev --dart-entrypoint-args=--fmp-legacy-dir=...`）。驗完把備份還原回 `userdata-dev\`。
- Android：資料夾要在 dev App 的私有目錄裡。`adb push <暫存目錄>/legacy-copy/fmp_database.isar /data/local/tmp/`，再
  `adb shell run-as com.personal.fmp.dev mkdir -p files/legacy-copy` 與
  `adb shell "run-as com.personal.fmp.dev cp /data/local/tmp/fmp_database.isar files/legacy-copy/"`，
  先 `pm clear com.personal.fmp.dev`（`clear` 會清掉 `files/`，所以 `pm clear` 在複製之前），參數給 `files/legacy-copy` 的絕對路徑
  （`/data/user/0/com.personal.fmp.dev/files/legacy-copy`），帶法同 `--fmp-dev-plugin`（見 `android.md`）。dev 的 Android 不讀憑證。
- 看結果：log 的 tag `legacy-import`（`Legacy data found; importing`、`Legacy data staged`、`Legacy data imported`、`Importing the legacy data failed`），資料庫的 `legacy_imports.summary_json`。
  結果對話框只出現一次：按「知道了」之後重開不再出現。
