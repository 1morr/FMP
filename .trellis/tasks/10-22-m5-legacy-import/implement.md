# M5 執行計畫

「design §n」指本任務的 `design.md`；「§11 第 n 條」指 design 的確認清單；「決定 n」指 `prd.md` 的擁有者決定。

## 通用規則（每個 PR 子任務）

- **開工**：從最新的 `main` 開分支與 worktree；以 `task.py create "<標題>" --slug <slug> --parent .trellis/tasks/10-22-m5-legacy-import --package app --no-start` 建子任務；prd 只寫做什麼與驗收，在已核准的範圍內直接做，遇到未定的事才問。
- **合併條件**：`app/` 可編譯、`flutter test` 全綠；CI 彙總 job `CI Result` 通過；PR 描述附 review 指南。
- **實機驗證**（ADR 0027 與 2026-10-13 的修訂）：使用者看得到的 PR（6、7）照 `verify-on-device` 在 Android 模擬器驗；改到平台各自實作的（PR 4 的 Windows DPAPI、PR 6 的找舊資料與檔案對話框、PR 7 的刪除）另驗 Windows。預設用**合成的舊資料**（PR 1 的產生工具），不連網；回報寫明平台與模式。
- **擁有者的真實資料**（§11 第 10 條）：
  - 只在 PR 1 的實開檢查與驗收時用；
  - 一律先複製到 `<暫存目錄>`，用完就刪；
  - 只看筆數與略過理由，不輸出歌單名稱、曲目、帳號名稱；憑證只寫「有／沒有／讀不出」；
  - 不碰 `Documents\FMP`、`%APPDATA%\com.personal\fmp` 的原檔（只讀來複製），不碰模擬器上的 `com.personal.fmp`。
- **改 schema**：PR 2 的 v19 照 `.trellis/spec/app/data/index.md` § 改 schema 的完整流程。
- **lint**：PR 1（`isar_community` 的使用者）、PR 4（`win32`）、PR 6（`lib/main.dart` 的例外）照 `.trellis/spec/app/lints/index.md` 寫雙向變異案例，並在 `tool/lint_sentinel.dart` 加違規行。
- **收尾**：子任務 `finish` 與 `archive --no-commit --skip-branch-validation`；手動 commit；以 merge commit 合併。
- **文件**：每個 PR 更新 `app/AGENTS.md` 中自己那一層（新節「舊資料匯入」在 PR 1 建）：只寫查不到的契約與有閘門的規則，每條寫出它的閘門。
- **套件版本**：加依賴時到 pub.dev API 核對一次；`isar_community`、`isar_community_flutter_libs` 固定 3.3.2（舊庫格式），`win32` 跟 lock 檔現有的版本相容的 stable。
- **子代理模型**（全域規則）：
  - 照計畫寫程式與測試一律 sonnet；
  - `trellis-check` 審查一律 opus（每個 PR 都要它試著攻破：舊檔有沒有被寫、中途失敗是否留下半套、憑證有沒有進 log）；
  - 研究代理 sonnet；
  - 交給 sonnet 的 prompt 附完整計畫並寫明：遇到計畫沒涵蓋的設計決定就停下回報。

## 進度與交接（compact 後從這裡接）

- **狀態**（2026-10-23）：擁有者核准 design §11 的 12 條與 §10 的 ADR 改動（「照建議」）；PR 0 進行中。
- **待擁有者回覆**：無。
- **下一步**：PR 0 合併後，PR 1 與 PR 2 平行。
- **每個 PR 的固定流程**：分支 → `task.py create`（`--parent .trellis/tasks/10-22-m5-legacy-import`）→ prd 與 `implement.jsonl`／`check.jsonl`（design 的相關節、ADR 0010、相關的 `.trellis/spec/app/<layer>/index.md`、本任務的 research）→ `task.py start` → 派 `trellis-implement`（驗證清單：`dart format --output=none --set-exit-if-changed .`、`build_runner` 後沒有實質變動、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`、動到 lint 時 `dart run tool/lint_sentinel.dart`、需要時建置）→ 實機驗證 → 派 opus `trellis-check` → 後續待辦寫進本檔「留下的後續」→ 還原只有換行差異的產生檔 → 分開 commit → `finish`、`archive` → push、`gh pr create` → 等 CI → `gh pr merge --merge`。
- **地雷**（之前里程碑帶來的，仍適用）：
  - 整合測試會清 dev 資料：Windows 上跑之前先備份 `userdata-dev`。
  - 建置後 `linux/`、`macos/`、`windows/` 的 plugin registrant 只有換行差異時還原。
  - 文件引用子任務的研究檔時寫 archive 後的路徑。
- **M5 新的地雷**（預期）：
  - `isar_community_flutter_libs` 會加進 Android、Windows 的原生建置（plugin registrant 改變是預期的，要提交）；Linux、macOS、iOS 的建置 job 要確認它不擋（它有 linux、macos、ios 目錄）。
  - dev 的資料目錄在 Windows `flutter run` 時是建置產物旁的 `userdata-dev`；首次啟動匯入要先讓 `fmp.db` 不存在。

## 順序與相依

| PR | 內容 | 依賴 |
|---|---|---|
| 0 | 規劃檔、ADR 補充與更正、milestones | — |
| 1 | 舊 Isar 模型與讀取器、合成舊庫的產生工具 | 0 |
| 2 | 匯入包、暫存庫寫入與驗證、`legacy_imports`（v19） | 0 |
| 3 | 轉換器：曲目、歌單（含網址辨識）、佇列、歷史、電台、外部來源 | 1、2 |
| 4 | 舊憑證：Android 實測、平台讀取器、帳號與憑證的轉換 | 2、3 |
| 5 | 設定的轉換 | 3 |
| 6 | 啟動流程：找舊資料、dev 入口、進度與失敗頁、換上、結果對話框 | 3、4、5 |
| 7 | 設定頁：從舊版匯入（資料庫、JSON 備份）、`replaceWithImport` | 6 |
| 驗收 | 真實資料副本、兩平台端到端 | 7 |

1 與 2 可以平行；4 與 5 可以平行。

## 0. 規劃檔、ADR 與文件更正

- 本任務的 prd、design、implement、research 提交。
- design §10 標「PR 0」的：ADR 0010 補充與後果、ADR 0012 補充、ADR 0029 更正、ADR 0034「之後要注意」。
- `milestones.md`：M5 列「進行中」、範圍照 prd。
- 模型：主對話（文件，照 design 寫）。

## 1. 舊 Isar 模型與讀取器（design §2、§4.1、§9）

- 在 workspace 外的暫存 package（analyzer < 11）以 `isar_community_generator` 3.3.2 產生舊模型的 `*.g.dart`，複製進 `app/lib/legacy_import/isar/`；`README.md` 記產生步驟。
- `isar_community`、`isar_community_flutter_libs` 3.3.2 進 `app/pubspec.yaml`；`test/flutter_test_config.dart` 載入 `libisar`。
- `LegacySnapshot`（純值，全部 11 個 collection，含 M6–M8 會用的欄位）、`LegacyDatabaseReader`（複製 → 開副本 → 讀 → 關 → 刪工作目錄）。
- `test/legacy_import/fixtures/legacy_schema.json`（由舊專案的 `*.g.dart` 產生一次）與凍結閘門；合成舊庫的產生工具（測試內以舊模型寫；也給實機驗證用：`tool/legacy_fixture.dart` 寫一份合成的 `fmp_database.isar` 到指定資料夾）。
- `tool/legacy_counts.dart`：讀一份舊庫副本、只印每個 collection 的筆數（驗收用）。
- 規劃時的探針已以擁有者舊庫的副本開成功（`research/isar-copy-spike.md`，探針程式在 session 暫存目錄、不提交）；PR 1 以合成舊庫為主，`legacy_counts` 完成後以同樣的做法（複製、讀、刪副本）對一次筆數。
- Android 建置：`flutter build apk --flavor dev --debug`，以官方檢查確認 `libisar.so` 的 16KB 對齊（ADR 0010「之後要注意」）。
- 模型：sonnet（照計畫）。

## 2. 匯入包、暫存庫寫入與驗證（design §6）

- `lib/data/import/`：`ImportBundle` 的值型別、`StagingImport.write`／`verify`（首次啟動那一種：全新的庫）、`LegacyImportsRepository`。
- schema v19：`legacy_imports`、`legacy_playlist_ids`；兩張都加進 `backupExcludedTables`。
- 測試：design §9 的「暫存庫」「中途失敗」（寫入與驗證兩步）；一萬筆歷史與一萬首佇列的寫入時間記進 PR 描述。
- 模型：sonnet。

## 3. 轉換器：音樂庫（design §5.1–§5.7）

- `LegacyConverter` 的曲目、歌單（`remote_playlist_url.dart` 的網址辨識）、佇列、歷史、電台、`track_origins`；`SkipReason` 與摘要。
- 先讀 `fmp-plugins` 的 bilibili 1.10.0、youtube 1.6.0、netease 1.7.0 的 `playlistFromUrl` 與單元測試，寫表格測試（註明版本）；讀 qqmusic、netease 的 `sourceId` 格式，決定 §5.7 的比對規則。
- `fmp-plugins` 的 README 加「宿主的依賴」一節（`playlistFromUrl` 的輸出被 FMP 的舊資料匯入複製）：該 repo 的 PR，照已核可計畫直接做。
- 測試：design §9 的「轉換器」（音樂庫部分）。
- 模型：sonnet。

## 4. 舊憑證與帳號（design §0.1、§4.3、§5.8）

- Android 的相容性已在規劃時實測（`research/android-credentials-compat.md`）。
- `lib/platform/legacy_data/legacy_credential_reader.dart`：Windows（`win32` 的 `CryptUnprotectData`，解密以函式注入，可指定路徑，唯讀）、Android（先看舊 prefs 檔在不在，再以 11.2.0 舊設定實例讀）；`win32`、`ffi` 加進 lint 的 `platformPackages`。
- `integration_test/legacy_credentials_test.dart`（以 `CryptProtectData` 加密合成 JSON → 讀回），加進 CI 的 Windows 整合測試 job（新的一步）。
- `CredentialStore.writeImported`（design §5.8）；轉換器的帳號與憑證；`writeCredentials` 的實作。
- adapter 的 Windows docstring 更正。
- 測試：design §9 的「舊憑證（Windows）」「憑證的往返」、轉換器的帳號部分。
- 模型：sonnet。

## 5. 設定的轉換（design §5.9）

- 每一列對照、「只寫改過的值」、選項換算、`browse_as_logged_in` 例外、不匯入清單進摘要。
- 測試：每一列一例；值域外的原始值（`minLong`、NaN）當沒設定。
- 模型：sonnet。

## 6. 啟動流程（design §3.1、§7.1–§7.3、§8.1）

- `LegacyDataLocator`（Windows、Android 的兩個位置；dev 只看參數）；`--fmp-legacy-dir` 與 `FMP_LEGACY_DIR`（dev only，拒絕真實舊位置）。
- `LegacyImport` 介面（`lib/app/`）與實作（`lib/legacy_import/`）；`lib/main.dart` 的分支與 lint 例外。
- `LegacyImportApp`（進度、失敗頁三個按鈕）、`DatabaseErrorApp` 的重試與匯出診斷、結果對話框、殘留的暫存檔與工作目錄在啟動時清掉。
- verify-on-device 的 `references/runtime-state.md` 加 `--fmp-legacy-dir` 的帶法。
- 實機（重播：合成舊庫）：Android 與 Windows 各一次首次啟動匯入；一次失敗（給一份壞的 `fmp_database.isar`）→ 三個按鈕各試一次。
- 模型：sonnet（版面沿用既有元件，design §7 已定）。

## 7. 設定頁的從舊版匯入（design §3.2、§4.2、§6.3、§7.4）

- `LegacyBackupReader`（JSON v1–v5）。
- `DatabaseBackups.replaceWithImport`：副本、取代、帳號合併、驗證；把 `restoreStaged` 的換檔抽成共用的私有方法（還原的既有測試要照舊通過）。
- 設定頁的「從舊版匯入…」、確認框、進度對話框、沒有紀錄時的提示。
- 測試：design §9 的「JSON 備份」「設定頁的取代」「設定頁」。
- 實機（合成舊庫與合成 JSON）：Android 兩種匯入各一次（先裝好 `fmp-test`，確認取代後插件還在）；Windows 一次（重啟是平台各自實作）。
- 模型：sonnet。

## M5 驗收（7 之後）

照 design §8.2；證據寫進 `research/m5-acceptance.md`（只有筆數、略過理由、請求數）。

- [ ] Windows：真實資料庫＋憑證檔副本，首次啟動匯入，筆數比對，三個平台各一次帳號資訊請求
- [ ] Android 模擬器：真實資料庫副本，首次啟動匯入，筆數比對
- [ ] 兩平台：失敗頁、設定頁兩種匯入（合成資料）
- [ ] ADR 0010 §如何確認 與 design §9 的測試逐項對到
- [ ] 副本刪除；`milestones.md` 更新；第二個驗收項留給擁有者

## 留下的後續

- PR 1：
  - **真實資料的筆數**（2026-10-23）：以 `tool/legacy_counts.dart` 讀擁有者舊庫的副本，11 個 collection 的筆數與 `research/isar-copy-spike.md` 相同，`schemaVersion` 4；原檔的雜湊與修改時間讀前讀後相同，副本已刪。
  - **沒有設定列就讀取失敗**：libmdbx 會把小於 4 KB 的壞檔當成新的空庫打開；舊 App 每次啟動都寫 `Settings` id 0，所以讀取器在沒有設定列時拋 `LegacyReadException(step: read)`。PR 6 的「找到舊資料庫」仍只看檔案存在，壞檔走失敗頁。
  - **讀取器的 log 是回呼**（`LegacyReadLog`）：`Log` 會帶進 Flutter，`dart run tool/legacy_counts.dart` 就跑不了。PR 6 接到 `Log`。
  - **`LegacySettings` 可變、舊 migration 就地補做**：只在讀資料庫時、`schemaVersion < 4` 才補。PR 7 的 JSON 備份讀取器**不能**沿用「看 `schemaVersion` 決定補不補」（備份有自己的版本語意，design §4.2）；轉換器不改這個物件。
  - 低、沒有 repro，不修：`Isar.open` 在原生端建好實例後若初始化拋錯，實例不會被關，同一個行程裡重試會撞名（實例名固定 `fmp_database`）。PR 6 的「重試」若遇到，再以 `Isar.getInstance` 比對目錄後補關。
- PR 3：
  - **摘要分「略過」與「註記」**：`CollectionSummary` 加 `notes`（`remoteNotRecognized`、`duplicateRemote`、`importSourceMismatch`、`unverifiedPart`：資料照寫，只是提醒）；`skipped` 只放真的略過，每個 collection 都是「讀到 = 寫入 + 略過」。PR 6 的結果對話框在 `lib/app`，不必 import `lib/legacy_import` 就分得出來。
  - **佇列空了也寫播放狀態**：舊版的音量與循環模式照樣帶過來；整列都是型別預設或沒有 `PlayQueue` 列時才不寫。
  - **PR 4**：`playlist_remote.writable` 現在只要舊庫有該平台的帳號列就比對 `ownerUserId`，不管憑證有沒有匯入；PR 4 改成「真的匯入了那個平台的帳號才標可寫」。
  - 轉換器為了歷史上限的選項 import 了 `lib/settings`（純靜態函式），所以轉換器帶 Flutter 依賴，`dart run` 的工具不能引用它（目前沒有這種用法）。
- PR 7：
  - **「這台有登入」＝帳號列存在且 `active`**（2026-10-23，PR 7 審查後主對話決定；design §11 第 9 條的字面）：`invalidated` 的平台若舊版有可用的憑證就換成匯入的帳號與憑證，沒有就保留這台的列。
  - **取代的表要歸類**：`StagingImport.replacedTables` 與測試裡的保留清單合起來必須等於整個 schema（`staging_import_replace_test.dart` 的 `table classification gate`），新表沒歸類就紅。
  - **實機**（實作代理，dev、合成資料、重播）：Windows 兩種來源都驗了（本機歌單被換掉、`fmp-test` 保留、自動備份與 `fmp.db.before-import-*` 在、重啟後結果對話框、JSON 那次佇列清空）；Android 驗了 JSON 備份（經 SAF）。沒驗：Windows 上保留這台帳號（要真憑證，單元測試覆蓋）、Android 的「舊版資料庫」路徑。
  - 低、不修：換檔後寫憑證失敗只記 log，結果對話框不會列出要重新登入的平台；確認框停留期間對保留表的寫入（插件 storage、排程時間）會丟失；JSON 解析在 UI isolate；按鈕只在有檔案對話框的平台出現（Android、Windows 都有）。
- PR 6：
  - **實機**（2026-10-23，dev、合成資料、重播）：Windows 由實作代理驗（首次匯入含假 cookie 的 DPAPI 檔、結果對話框、「知道了」後不再出現、失敗頁三個按鈕、診斷包不含假 cookie 與使用者名稱）；Android 模擬器由主對話驗（首次匯入、舊庫副本雜湊不變、`legacy-import/` 清空、結果對話框、重開不再匯入、佇列與播放位置帶過來、失敗頁、以空白資料啟動）。
  - **Android 讀舊憑證後 `shared_prefs` 不變**：dev 讀不到 prod 的沙盒，實機驗不到；證據是規劃時的實測（`research/android-credentials-compat.md`），M9 的實際升級再看一次。
  - **失敗頁只顯示翻譯過的步驟**：`LegacyImportFailed.reason` 是英文，只進 log 與診斷包。`LegacyImportApp` 跟隨系統語言（獨立的小 App，還沒有設定）。
  - **匯入後首頁的首次引導會讀一次官方 index**（既有行為；沒有插件時就會讀）。
  - 低、沒有 repro，不修：rename 之後、寫憑證之前 App 被結束，帳號列在 `CredentialStore` 載入時被刪掉，但 `reloginPlatforms` 沒補記，結果對話框的帳號數會多算。
  - 結果對話框列「需要重新登入」時，插件還沒裝就只能顯示插件 id。
  - `legacyImportProvider` 的第一個讀者是 PR 7 的設定頁；`safeNote`「之後可以在設定頁再匯入」也在 PR 7 才成立。
- PR 4：
  - **單一入口**：`LegacyConverter.convert(..., credentials:, importOutputDevice:)` 回 `LegacyConversion{bundle, credentials}`；`credentials` 為空（舊 JSON 備份）就不跑帳號段。憑證只在 `LegacyConversion.credentials`（記憶體），PR 6 換上後以 `CredentialStore.writeImported` 寫。
  - **讀取器**：`LegacyCredentialReader`（`lib/platform/legacy_data/`），Windows 與 Android 兩個實作與 `NoLegacyCredentialReader`；PR 6 依平台與 flavor 選（dev 的 Android 不讀，Windows 讀 `--fmp-legacy-dir`）。PR 6 的 Android 實機要確認讀過之後 `shared_prefs` 內容不變。
  - **需要重新登入**：讀不出、缺必要 cookie、沒有 user id，以及舊帳號列 `isLoggedIn` 但憑證不在的平台；舊版已登出的平台不列。
  - **新的略過理由 `accountWithoutId`**：PR 6 的結果對話框要有它的翻譯。
  - 低、驗收時看：舊版 YouTube 帳號的 `userId` 是 channelId（`UC…`），新插件 `loginVerify` 回的是 datasync id 或 handle；備用值 `datasyncId` 可能含 `||` 沒拆。只影響顯示、遮蔽登記與 YouTube 歌單的 `writable`；擁有者的舊庫沒有 YouTube 帳號。
- PR 5：
  - `layout_state` 照實際值寫（design §5.9 那一列的 2026-10-23 補充）。
  - 舊預設改過幾次：`maxCacheSizeMB` 的歷代預設（2048、128、32，Android 新安裝 16）都當成沒改過；`audioFormatPriority` 在 v1.0.7–v1.9.x 的預設是 `aac,opus`、v1.10.0 起才是 `opus,aac` 且沒有 migration，存 `aac,opus` 的人分不出是改過還是舊預設，照寫（保留在舊版實際的行為）。
  - `convert` 多一個選用參數 `importOutputDevice`（只有 Windows 由呼叫端給真，PR 6）。
  - 排行刷新：舊值 1–14 會換成新版的 0（關閉）；舊版介面與修復都走不到這些值，只有壞掉的備份檔會出現，不處理。
- PR 2（審查時發現）：
  - **PR 7 要另一個寫入入口**：`StagingImport.write` 會先刪目標檔、建全新的庫、設定整列插入。設定頁的取代要在 `VACUUM INTO` 的副本上寫：不刪檔、先清掉要取代的表、設定只覆寫有值的欄位、合併帳號（design §6.3）。`verify` 的「匯入包沒寫的表必須是空的」改成收「保留下來的列數」。
  - **換上後才失敗的憑證**：需要重新登入的平台在寫暫存庫時就定了；`writeCredentials` 在換上之後才失敗的平台要補記進 `summary_json`。PR 4／PR 6 給 `LegacyImportsRepository` 加補記的方法。
  - **快取上限不匯入**（ADR 0016 §決定 3）：`ImportBundle` 的 `NetworkSettings` 型別帶 `cacheLimitMebibytes`，由轉換器留空；PR 3 的轉換器測試斷言它是空的。
  - `Account.avatarJson` 是原始 JSON 字串：PR 4 的轉換器以 `TracksRepository.encodeArtwork` 編碼。

## 風險與回滾點

見 design §12。回滾點：

- PR 1、3、4、5 不接進啟動流程，單獨 revert 不影響使用者；PR 4 的 `CredentialStore.writeImported` 只是新增方法。
- PR 2 加了 schema v19，合併後 revert 要另寫 v20 的 migration 刪表（design §12）。
- PR 6 之後首次啟動會匯入，壞了可以 revert PR 6（資料目錄裡已匯入的 `fmp.db` 照常可用，舊檔沒被動過）。
- PR 7 動到還原正在用的換檔程式碼，revert 時連同它一起回到原狀。
