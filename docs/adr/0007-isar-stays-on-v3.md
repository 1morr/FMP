# 0007 — Isar 停在 v3，改用 isar_community fork

- 狀態：已採納
- 日期：2026-09-25（補記；決策本身在 `35007eb0`（2026-07-05）與 `3b1c7244`（2026-09-02））
- 影響範圍：`pubspec.yaml` 的 Isar 依賴、`lib/data/models/` 的所有 collection、release 前的 native libs 檢查

## 背景

FMP 的全部持久化資料（歌單、曲目、播放紀錄、設定、佇列）都在 Isar v3。

- 上游 `isar/isar` 自 2025-07 沒有再發版。它的 generator 把 analyzer 限制在
  `<6.0.0`，整條工具鏈因此卡在 analyzer 5.13.0 / build 2.4.1，Riverpod 3 解析
  不出來。
- Isar v4 沒有 v3 → v4 的遷移工具，也沒有測過的遷移路徑；升級等於拿每一個已存在
  的 collection 冒險。

## 決策

留在 v3 的磁碟格式，依賴換成社群 fork `isar_community`（`3b1c7244`）：

- 十一個 collection 重新產生後語意相同 —— schema id、property id、index 與 link
  定義都沒變，只有格式與 generator 版本字串不同。一份 3.1.0+1 寫出的真實資料庫
  （1,534 列）的副本能原地打開、反序列化、寫入後讀回。
- analyzer 升到 10.x、build 升到 4.x，Riverpod 3 可以解析。
- fork 的 Android library 是 16 KB 對齊，符合 Android 15 的 page size 要求。

不自行升級到 v4。

## 被否決的替代方案

### 升級到 Isar v4

沒有遷移工具，而資料是使用者唯一的一份。v4 本身也未被上游宣告可用於正式環境。

### 留在上游 `isar` 3.1.0+1

工具鏈被 analyzer `<6.0.0` 釘死，Riverpod 3 與後續的 lint 升級都做不了。

## 後果

- Windows 的 library 名稱從 `isar.dll` 變成 `libisar.dll`；子視窗 plugin 的標頭
  搬到 `isar_community_flutter_libs`。
- 發版前要確認目標平台（Android `arm64-v8a` / `armeabi-v7a` / `x86_64`、Windows
  `x86_64`）的 native libs 能解析，且對應的 build job 通過。
- 驗證 schema 變更不能只看 `flutter test`：用 `test/manual/real_db_probe.dart`
  拿真實資料庫的副本前後各跑一次。

## 重開的條件

fork 停止維護到無法建置，或出現官方的 v3 → v4 遷移工具。屆時的候選是 `drift`、
`sqflite` 或 `objectbox`，任何一個都需要自己寫資料遷移。
