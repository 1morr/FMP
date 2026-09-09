# 0001 — 每源設定收成一份清單，音源改用字串 id

- 狀態：已採納
- 日期：2026-09-03
- 影響範圍：`lib/data/models/`、`lib/data/sources/`、備份格式、schema v1 → v2

## 背景

兩件事在 Phase 3 一起做，因為它們共用同一批呼叫點：

1. `enum SourceType { bilibili, youtube, netease }` 是封閉的。Phase 9.1 要支援
   外掛音源，封閉 enum 擋在那之前。
2. `Settings` 上有六個具名的每源欄位（三個 `*StreamPriority`、三個
   `use*AuthForPlay`）。加第四個音源要改六處宣告、四份備份清單、偵錯檢視器，
   而且每一處都是複製貼上。

封閉 enum 還有一個當下就會咬人的問題：**它會靜默改寫資料**。Isar 生成的
反序列化器對認不得的字串一律回 fallback：

```dart
_TracksourceTypeValueEnumMap[reader.readStringOrNull(offsets[23])] ??
    SourceType.bilibili
```

五個持久化欄位（`Track` / `PlayHistory` / `RadioStation` / `Playlist` /
`Account`）各有一處，加上手寫的 `backup_service.dart` 與 `download_scanner.dart`
兩處，共 **7 條**路徑會把未知音源改寫成 bilibili。生成碼那五處不改欄位型別就修不掉。

## 決策

### 音源 id 用字串常數

`enum SourceType` 刪除，改成 `SourceIds`（`lib/data/models/source_ids.dart`）：
一組 `static const String` 加一份 `values` 清單。持久化欄位型別從 `SourceType`
換成 `String`，欄位名稱不變。

**磁碟格式逐位元不變**：`@Enumerated(EnumType.name)` 本來就寫字串，生成的
`PropertySchema(id: 23, name: r'sourceType', type: IsarType.string)` 改動前後
完全相同，只是讀取端少了那張 enum 對照表。不需要 migration。

顯示名稱改走 slang 的 flat map：

```dart
static String displayNameFor(String sourceId) {
  final value = t['importPlatform.$sourceId'];
  return value is String ? value : sourceId;   // 查不到就回原始 id
}
```

第四個音源只要加一筆 i18n 就有名字。這順帶消掉了三份重複的顯示名稱 switch
與三份圖示 switch。

### 每源設定收成 `@embedded` 清單

六個具名欄位換成 `List<SourceSettingsEntry> sourceSettings`，每筆是
`{sourceId, streamPriority, useAuthForPlay}`。讀寫走
`Settings.streamPriorityFor(id)` / `useAuthForPlay(id)` 與對應的 setter。

## 被否決的替代方案

### `extension type const SourceType(String id)` —— 技術上不可行

這個做法能讓約 1,270 處引用原封不動，是最有吸引力的一條路。它行不通，而且是
從 generator 原始碼證實的，不是推論：

`isar_type.dart:12-38` 的 `_primitiveIsarType` 用 `isDartCoreString` 判斷型別。
extension type 的 `DartType` 帶的是 `ExtensionTypeElement`，不是 `dartCoreString`，
所以五個持久化欄位會在 `isar_analyzer.dart:283` 被拒：
`'Unsupported type. Please annotate the property with @ignore.'`

退而求其次的「欄位存 `String`、app 層包 extension type」會在每個模型欄位讀取處
（約 200 個）製造顯式轉換，比全部改成 `String` 更差。

### 維持 enum，只修那兩處手寫的 fallback

修不掉生成碼裡的五處。那五處正是資料靜默改寫真正發生的地方。

### `Map<String, SourceSettings>`

當初的路線圖提的是這個形狀。Isar 的 `@embedded` 不支援
`Map<String, @embedded>`，只支援 `List`。實際交付的是
`List<SourceSettingsEntry>`，查表由 `Settings` 上的私有 helper 負責。

順帶一提，`@embedded` 物件有個必須記住的坑（`track.dart:128/200/212` 早有註解）：
**改值必須建新的物件與新的 list**，就地改欄位 Isar 偵測不到。`_putEntry` 因此
每次都重建整份清單。

### 把每源設定存成 JSON 字串（`hotkeyConfig` 的做法）

`@embedded` 讓偵錯檢視器能逐欄位列出、備份 DTO 能結構化對映。JSON 字串兩者都做不到。

## 後果

### 降級是無損的

v1 → v2 的遷移**只搬不刪**：六個舊欄位保留、標上
`@Deprecated('read only by the v1 to v2 migration; removed in schema v3')`，
遷移把值折進 `sourceSettings` 之後**刻意不清空**。

理由：使用者裝回舊版 APK 時，舊版讀的是那六個欄位。如果折疊時清空了它們，舊版的
`repairSettingsInvariants` 會把使用者的選擇覆蓋成預設值。降級時真正會丟的只有
`sourceSettings` / `schemaVersion` 與面板欄位本身。

舊欄位不能提早刪掉還有一個硬性理由：遷移是在 `Isar.open(fmpDatabaseSchemas)`
**之後**才跑的。欄位一旦從 `settings.dart` 消失，生成的反序列化器裡就沒有它，
遷移程式碼根本讀不到，三筆 entry 會全部拿到空值 —— 那是直接的使用者設定遺失。

`analysis_options.yaml` 打開了 `deprecated_member_use_from_same_package`，讓
「只有遷移能讀那六個欄位」變成編譯器規則，而不是註解自律。

### 失去編譯期窮盡檢查

19 個 `switch` 沒有了 enum 的窮盡保證。每一個都逐一決定了未知 id 的行為，
沒有用 `default:` 草草帶過：

| 位置 | 未知 id 的行為 | 理由 |
|---|---|---|
| `source_http_policy.dart` 三處 | 空 map | 未知源不該拿到任何來源專屬 header |
| `source_auth_context.dart` | `null` | 無認證 |
| `remote_playlist_edit_controller.dart` | 改回 nullable | 隨便挑一個 adapter 會把歌曲寫進別的平台的歌單，那是不可復原的遠端寫入 |
| `account_provider.dart` 等三處 | `false` / 不顯示 / 空清單 | 未知源沒有帳號 |
| `icon_helpers.dart` / `source_badge.dart` | `Icons.link` | 沿用既有 fallback |
| `settings.dart` / `base_source.dart` | 查表取預設 | 見 `kDefaultStreamPriorityBySource` |

`setUseAuthForPlay` 與 `_fetchPlaylists` 對未知 id **拋錯而不是靜默 no-op**：
呼叫端會先做樂觀狀態更新，靜默忽略會讓開關看起來開著、其實沒存；回空歌單清單
則會在畫面上謊稱「這個帳號沒有歌單」。

### 排程理由的更正

當初的路線圖把這件事排進 Phase 3c，理由是「併進批次 schema
變更，邊際成本近零」。**這個前提不成立**：`@Enumerated(EnumType.name)` 本來就寫
字串，這項改動不改磁碟格式、不需要 migration、不碰備份格式、不碰 catalog，它與
那個批次共用的成本是 **0**。

真正的理由是「Phase 9.1 的前置 ＋ 修掉 7 條靜默改寫路徑」。使用者在看過實際規模
（177 個檔案、約 1,270 處改動）之後仍決定本輪做完。
