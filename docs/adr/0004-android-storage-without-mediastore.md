# 0004 — Android 下載用所有檔案存取權與裸路徑，不用 MediaStore

- 狀態：已採納
- 日期：2026-09-24
- 影響範圍：`android/app/src/main/AndroidManifest.xml`、`lib/services/platform/storage_permission_service.dart`、`lib/services/download/`、`lib/providers/download/`

## 背景

FMP 的下載在 Android 上寫進使用者選的資料夾，寫檔用的是 `dart:io` 路徑，
不經 MediaStore 或 SAF 的 URI：

- `AndroidManifest.xml` 宣告 `MANAGE_EXTERNAL_STORAGE`，並以
  `tools:ignore="ScopedStorage"` 壓掉 lint；舊的 `READ_EXTERNAL_STORAGE` /
  `WRITE_EXTERNAL_STORAGE` 分別限 `maxSdkVersion` 32 / 29。`targetSdk` 跟隨
  Flutter SDK 的 `flutter.targetSdkVersion`。
- 權限走 app 自己的 MethodChannel（`StoragePermissionService`，對應
  `MainActivity.kt`）。API 30 以上查 `Environment.isExternalStorageManager()`，
  請求時開 `ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` 設定頁；30 以下走
  舊的執行期權限。不用 permission_handler 的原因寫在該類別的 dartdoc：它的
  Windows 插件會讓 Windows 顯示 FMP 正在使用位置。
- 下載目錄由使用者在 `DownloadPathManager.selectDirectory` 裡用
  `FilePicker.getDirectoryPath()` 選，存進 `Settings.customDownloadDir`。每個下載
  入口先檢查 `hasConfiguredPath()`，沒選過就跳 `DownloadPathSetupDialog`。
  Android 上選目錄之前先要權限，選完再寫一個 `.fmp_test` 驗證能寫。

這條路徑貫穿整個下載管線：`DownloadPathUtils.computeDownloadPath` 算出
`{baseDir}/{playlistName}/{sourceId}_{parentTitle}/P{n}.m4a` 這種階層；下載
isolate 用 `File` / `RandomAccessFile` 寫；音檔旁邊寫 metadata JSON；
`download_path_sync_service.dart` 與 `download_path_maintenance_service.dart` 以
`Directory.list` 掃描；`PlaylistDownloadInfo.downloadPath` 與
`DownloadTask.savePath` 把字串路徑存進 Isar；本機播放走
`FmpAudioService.playFile(path)`。

## 決策

**知情接受 `MANAGE_EXTERNAL_STORAGE` 加裸檔案路徑，不改 MediaStore / SAF。**
理由只有一條：擁有者決定 FMP 永遠不上架任何應用商店，只從 GitHub Releases
散佈。這個做法唯一擋掉的是商店審核，而那條路不走。

## 被否決的替代方案

### 改用 MediaStore（或 SAF）

它帶來的好處只在商店那一側。Google Play 的「所有檔案存取權」政策
（<https://support.google.com/googleplay/android-developer/answer/10467955>，
2026-09-24 查證）把這個權限列為受限權限，許可用途是檔案管理、
備份還原、防毒、文件管理等，「Media Files access」列在不許可的用途裡，媒體類
app 被導向 MediaStore API；不符資格又沒移除權限的 app 可能被下架。不上架，
這條理由就不存在。

它的成本落在整條下載管線上。MediaStore 給的是 content URI，不是路徑，而上面
背景列的每一段 —— 路徑計算、isolate 寫檔、旁邊的 metadata JSON、目錄掃描、Isar
裡的字串路徑、`playFile(path)` —— 都假設路徑。metadata JSON 還不是媒體檔，
放不進 MediaStore 的音訊集合。

## 後果

- **不能上架 Google Play。** 見上面的政策。
- **沒有權限就沒有下載目錄。** API 30 以上：`_manageExternalStorageStatus` 只會
  回 `granted` 或 `denied`（沒有 `permanentlyDenied` 這條路），`denied` 會先顯示
  說明對話框，再開系統的所有檔案存取設定頁；回來仍未授權，`selectDirectory`
  回 `null`，設定對話框留在原地，下載不會加進佇列。
- **寫檔被拒時下載會失敗，不會卡住。** 這條以前會卡：`3a413e56` 記錄
  `openWrite()` 提前開檔，scoped storage 拒絕路徑時錯誤殺掉 isolate，主 isolate
  永遠等下去，三次就佔滿所有下載名額。現在開檔改成 await，錯誤走 filesystem
  分支；`PathAccessException` 在 `lib/core/errors/user_message.dart` 對應
  `t.error.noPermission`，`3cf68582` 起下載管理頁存的是這句翻譯過的原因。
- **平台預設目錄是給舊資料的。** `getDefaultBaseDir` 在 Android 上回共用儲存區
  的 `Music/FMP`，但它的 dartdoc 寫明新下載不會落到那裡（入口都先要求選目錄），
  而且沒有所有檔案存取權時 `Music/` 其實寫不進去；留著它只是為了讓舊版寫進去
  的檔案仍能被掃描與同步。

## 重開的條件

決定要上架任何商店。那時要重做的是整條下載管線的儲存抽象，不只是換掉一個
權限宣告。
