# 統一快取庫與封面磁碟快取（M2 PR 4）

> 父任務：`.trellis/tasks/10-01-m2-full-playback`。技術設計在父任務 `design.md` §2（目錄與 lint 表）、§4.2–§4.4、§8.3 的傳遞依賴一段；本檔只列做什麼與驗收。

## 目標

封面經 PR 3 的媒體 client 下載（每跳檢查 `allowedHosts`、大小上限、逾時），存進統一快取庫，重開 App 不再重新下載。快取庫依位元組上限在寫入時淘汰（ADR 0016 §決定 2–4）。

## 做什麼

1. **平台層** `lib/platform/cache_directory/`：解析平台快取目錄下的 `fmp_cache/`（`path_provider` 只准在平台層）。平台層另外宣告：
   - 快取上限預設：Android 128 MB、Windows 256 MB；
   - 記憶體 `ImageCache`：Android 100 張／50 MB、Windows 200 張／80 MB，`main()` 在 `runApp` 前套用（沿用舊版 `lib/main.dart:156-164` 的數字）。
   - `platform_test.dart` 每平台斷言。
2. **快取模組** `lib/data/cache/`：
   - `cache.db`：第二個 drift 資料庫（`cache_database.dart`、`cache_tables.dart`），表 `cache_entries` 照 design §4.2；快照在 `drift_schemas/cache_database/`，`build.yaml` 的 `databases:` 加第二個，自己的 `schema_test`。
   - 開不起來（損壞）就刪掉 `fmp_cache/` 重建，不顯示錯誤頁；schema 升級時清空重建，不寫逐步 migration。
   - `CacheStore`：寫入後總量超過上限就依 `last_access` 由舊到新刪到上限以下，不分類別，不用計時器；提供用量、清除、`removePlugin(pluginId)`、改上限時淘汰一次的入口（PR 5 才接設定頁）。
3. **`FmpImageCacheManager`**（`lib/data/cache/image_cache_manager.dart`）：`flutter_cache_manager` 的 `CacheInfoRepository`、`FileSystem`、`FileService` 三個轉接。
   - `repo` 讀寫 `cache_entries`（`category = image`、`plugin_id` 固定）；`getObjectsOverCapacity`、`getOldObjects` 回空，淘汰只由 `CacheStore` 做。
   - `fileSystem` 指到 `fmp_cache/files/`；`fileService` 用該插件的 `MediaHttpClient`，封面上限 10 MiB。
   - 注意 PR 3 留下的：同一個 `destination` 不可同時下載兩次（共用 `.part`）；`flutter_cache_manager` 的 `WebHelper` 串流出錯時不刪寫一半的檔。確認兩者在這個接法下不會發生，或處理掉。
4. **插件層** `artworkCacheManagerProvider(pluginId)`（`lib/plugins/plugin_artwork.dart`）：組合快取庫與該插件的媒體 client（`PluginRegistry.mediaClient`）；插件更新後拿到的是新 client。
5. **UI**：`ArtworkImage`（`lib/ui/artwork/artwork_image.dart`）改用 `CachedNetworkImage`，多收 `pluginId`；解碼尺寸照舊以高（`memCacheHeight`）；`pickArtwork` 不動。所有呼叫端補 `pluginId`。
6. **lint**（`fmp_layer_imports`）：
   - `externalPackageOwners` 加 `flutter_cache_manager: lib/data/cache`、`cached_network_image: lib/ui/artwork`；
   - `restrictedImports` 加 `lib/platform/cache_directory/` 只給 `lib/data/cache/`、`lib/main.dart`；
   - 雙向變異案例寫在測試檔內，`tool/lint_sentinel.dart` 加違規行（照 `.trellis/spec/app/lints/index.md`）。
7. **文件**：`app/AGENTS.md` § 介面的封面段（拿掉 `Image.network` 那條與「M6」）、§ 網路的媒體 client 段、§ 資料（第二個資料庫的規則）改寫，每條寫閘門；需要時更新 `.trellis/spec/app/data/`、`ui/`、`platform/`。
8. **套件**：`cached_network_image`、`flutter_cache_manager` 到 pub.dev 核對當前 stable（design 寫 4.0.4／3.4.x），以 context7 或 pub cache 原始碼確認介面。

## 不做

- 設定頁「網路」組（上限、用量、清除）：PR 5。
- 移除插件的觸發點（M3）；這裡只提供並測 `removePlugin`。
- 系統媒體控制的封面（PR 16a／16b）。

## 驗收

- [ ] 測試（ADR 0016 §如何確認，不連網）：
  - 跨類別淘汰到上限以下；
  - 檔案被刪視為未命中（含 `CacheStore` 不回傳不存在的檔、淘汰器刪檔後同一張圖重新下載）；
  - 清除後用量為 0；
  - 移除插件只刪它的項目；
  - 損壞的 `cache.db` 開啟時重建；schema 升級後是空的、可寫入；`schema_test`；
  - cache manager 的 `get`／`put`／`touched` 對到 `last_access`；
  - `ArtworkImage` 以假 cache manager 的 widget 測試；
  - 平台宣告；lint 雙向案例與哨兵。
- [ ] 驗證清單全綠（父任務 implement.md 的「每個 PR 的固定流程」第 5 步），含 `build_runner` 後沒有實質變動、`lint_sentinel`。
- [ ] 建置檢查：`flutter build apk --flavor dev --debug` 後以 `zipalign -c -P 16` 確認新增的原生庫（`sqflite`）是 16KB 對齊；`flutter build windows --flavor dev --debug`。
- [ ] 實機（主對話做；真實連線，改動是網路與快取，ADR 0027 §決定 2）：兩平台搜尋 B 站一次，封面顯示；重開 App 後同一頁的封面沒有 `client: media` 的新網路紀錄；`fmp_cache/` 下有 `cache.db` 與檔案。
