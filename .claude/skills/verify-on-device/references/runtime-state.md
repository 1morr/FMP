# App 的狀態、資料與開發入口

## 資料目錄

解析邏輯在 `app/lib/platform/app_data_directory/`（ADR 0009 §決定 7）。下面的 `<資料目錄>` 指：

| 平台 | dev | prod |
|---|---|---|
| Windows 免安裝版（程式目錄沒有 `unins000.exe`；`flutter run`、直接跑建置產物都是這種） | 執行檔旁的 `userdata-dev\` | `userdata\` |
| Windows 安裝版（有 `unins000.exe`） | `%APPDATA%\com.personal\fmp-dev` | `%APPDATA%\com.personal\fmp` |
| Android | `/data/data/com.personal.fmp.dev/files`（`run-as com.personal.fmp.dev`） | `com.personal.fmp` 的 `files`：**不要碰** |

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
  驗證時用 `tag` 與 `message` 找（`Installed a plugin from the development entry`、
  `Development playback started`、`Look-ahead handover`、`Track audible`）。

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

原始碼：`lib/plugins/install/dev_plugin_entry.dart`、`lib/playback/dev_playback_entry.dart`。

| 入口 | 作用 |
|---|---|
| `--fmp-dev-plugin=<路徑>` 或環境變數 `FMP_DEV_PLUGIN` | 啟動時安裝該路徑的插件安裝檔（`.js`）；兩者都有時參數優先 |
| `--fmp-dev-playback` | 安裝內附的測試插件（`fmp-test`），依序播它的三首（`tone-220`、`tone-440`、`tone-880`，每首是同一個 2 秒的本機 wav，不連網） |
| `--fmp-dev-playback=<曲目鍵>` | 播指定曲目（例如 `bilibili:<BV 號>`）；重複參數播多首。插件要已安裝，或同時帶 `--fmp-dev-plugin`。要連網，屬於「真實」模式 |

- 參數不用逗號分隔（Android 的 `--esal` 會切陣列，見 `android.md`）。
- Windows 的環境變數只對該行程有效：PowerShell 用
  `$env:FMP_DEV_PLUGIN='<路徑>'; Start-Process ...; Remove-Item Env:FMP_DEV_PLUGIN`。
- 這兩個入口在 PR 12 的 UI 取代之前是驗證播放與插件的入口；之後以原始碼為準。
- 身分頁的 `Dev playback: <狀態> <第幾首>/<總數>` 是播放入口的狀態。
