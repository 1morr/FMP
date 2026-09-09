# 0002 — Isar 只出現在 repository 層

- 狀態：已採納
- 日期：2026-09-04
- 影響範圍：`lib/data/repositories/`、所有曾經自己持有 `Isar` 的 service

## 背景

2026-09-03 資料層整理開始時，`lib/` 裡有 152 個 repository 之外的 Isar 呼叫點。集中在三個
service：`playlist_mutation_service`（39）、`backup_service`（36）、
`data_integrity_service`（20）。

問題不是「service 碰了資料庫」這件事本身難看，而是它造成的兩個具體後果：

- **跨 collection 的原子性沒有歸屬。** `BackupService.importData` 用九筆獨立交易
  寫七個 collection，中途失敗就留下半套資料。它沒辦法把這些寫入合成一筆交易，
  因為它呼叫的 `PlaylistMutationRepository.addTracks` 自己又開一筆，而 Isar 的
  `_requireNotInTxn()` 是 **Zone 層級**判斷（`isar_common.dart:19-26`），
  交易 callback 裡間接呼叫到的任何 `writeTxn` 一律拋。
- **同一段查詢邏輯散在多處。** 沒有一個地方能回答「誰會寫 tracks」。

## 決策

**`isar.` / `_isar.` 只能出現在 `lib/data/repositories/`**，加上兩個明文豁免：

- `lib/data/database/database_migration.dart` —— 它在 `Isar.open()` 之後跑
  遷移，定義上就是拿著 `Isar` handle 的那一層。
- `lib/data/database/database_catalog.dart` —— 它的 `query: (isar) => …`
  閉包本身**就是**偵錯檢視器的內容。

`test/data/repositories/isar_boundary_static_rule_test.dart` 釘住這條規則，
allowlist 與這裡一致，並且用合成的違規字串驗證 guard 自己抓得到、也不會誤報
（isar 套件的 import 行、`Isar.minLong` 這種靜態成員、註解裡提到的呼叫）。

需要跨 collection 原子寫入的 service，改成把「要寫什麼」交給 repository。
`BackupRepository.writeImport` 是這個形狀的範例：`BackupService` 負責解析、驗證
與跳過判斷（完全不碰資料庫），repository 用一筆交易寫完所有倖存者。

需要把自己的工作併進呼叫端交易的 repository 方法，用 `InTxn` 後綴命名
（`addTracksInTxn`、`mergeDuplicateTrackMembershipsInTxn`、
`remapPlaylistTrackReferencesInTxn`）。後綴是給人看的約定，**不傳交易 handle**
—— 這些方法與呼叫端共用同一個 `_isar` 實例。

## 被否決的替代方案

### 一個 collection 一個 repository

實際的職責邊界不是這個形狀：`TrackRepository` 為了掃孤立資料要讀 `playlists`、
`playQueues` 與 `lyricsMatchs`；`DownloadRepository` 讀 `tracks`；
`PlaylistMutationRepository` 與 `DataIntegrityRepository` 各自擁有跨到五個
collection 的寫入交易。硬拆成一對一，只會把跨 collection 的交易推回 service 層
—— 也就是推回這條規則要解決的那個問題。

### 加一層 `abstract interface class Repository`

沒有第二種實作，也不需要為了測試替換（測試用真的 Isar，跑在 temp 目錄）。
Immich 加過這層，後來用 20 幾個 PR 把它刪掉。現有的具體 class 已經是那層薄抽象。

### 用 lint 而不是測試

`custom_lint` 是額外的依賴與額外的建置步驟。掃原始碼的測試在這個庫已經有四份
前例（`ui_consistency`、`list_tile_leading`、`riverpod3_static_rule`、
`source_ownership_static_rule`），跟著既有做法走。

## 後果

- repository 之外的 Isar 呼叫點：152 → **19**（`database_catalog.dart` 11、
  `database_migration.dart` 8）。當時的驗收線是「< 60」。
- 備份匯入變成原子的。這是使用者可見的行為變更：解析期失敗仍然只損失該筆，但
  **寫入期**失敗從「損失一列」變成「整份匯入不寫」，並且例外往上拋，由 UI 顯示
  失敗，而不是回一個宣稱匯入了多少筆的結果對話框。
- `database_catalog.dart` 與 `database_migration.dart` 會永遠留在豁免清單上。
  那不是沒收乾淨，是那兩個檔案定義上就是拿著 `Isar` 實例的那一層。
