# 設定（`app/lib/settings/`）

加設定組或設定欄位時適用。規則（欄位為空＝沒設定過、改預設不需 migration）與閘門見
`app/AGENTS.md` § 設定；為什麼這樣分組，見 ADR 0011 §決定 7。這裡只寫怎麼做。

## 一組設定的形狀

以外觀（`appearance_settings.dart`）為例：

| 層 | 位置 | 內容 |
|---|---|---|
| 表 | `lib/data/database/tables.dart` | 單列表，`id` 加 `CHECK (id = 1)`，欄位全部 `nullable()` |
| repository | `lib/data/repositories/<組>_settings_repository.dart` | 值型別（欄位全可空）、`read`、`watch`、`write`（只寫有給的欄位） |
| provider | `lib/data/providers.dart` | `<組>SettingsRepositoryProvider`，讀 `appDatabaseProvider` |
| Notifier | `lib/settings/<組>_settings.dart` | 監看那一列，對外給套用預設後的值與 `stored` |

- Notifier 用 `StreamNotifier`，`build()` 回傳 `repository.watch().map(...)`；預設值只在
  這個 `map` 裡套用（`resolveAppearance` 這類純函式），不寫回資料庫。
- 對外的值型別同時帶「生效值」與 `stored`（使用者設定過的值），設定頁用 `stored` 的
  `null` 顯示「跟隨系統／預設」。
- 資料層自己要用設定值時（快取上限），直接訂閱 repository 的 `watch()`，預設從同一個來源
  （平台宣告）取，不 import `lib/settings/`：設定層在資料層之上，`fmp_layer_imports` 擋反方向
  （例子：`cacheStoreProvider`）。
- 播放控制器要用設定值時（臨時播放回佇列的兩個值），組裝點 `playback_providers.dart` 包一個
  provider 讀 Notifier（`temporaryReturnSettingsProvider`），控制器建構時拿到「當下讀一次」的
  函式；組裝點 `ref.listen` 它讓資料庫的值先讀出來，不用 `watch`（改設定不重建控制器）。
- 一組的表可以先建好全部欄位（「播放」組，design §3.3）：repository 的 `write`／`clear` 涵蓋
  全部，Notifier 的生效值型別與 setter 只放已經有人用的欄位。
- 設定方法一個欄位一個，只寫那個欄位（`repository.write(themeMode: ...)`）。參數可空，
  `null` 是「清回沒設定過」，走 `repository.clear(themeMode: true)`：`write` 的 `null`
  表示「沒給、不動」，兩者不能共用一個方法。

## 加一個設定欄位

1. **表**：在該組的表加一個 `nullable()` 欄位；列舉照 `spec/app/data` 的寫法存寫死的
   字串。
2. **schema**：照 `.trellis/spec/app/data/index.md` § 改 schema 做完整流程：
   `schemaVersion` 加一、`build_runner`、`make-migrations` 存快照、`onUpgrade`、三種
   migration 測試。新欄位在舊資料上是 `NULL`，也就是「沒設定過」，migration 不填值。
3. **repository**：值型別加欄位（含 `==`、`hashCode`、`toString`），`write` 加一個
   可省略的參數，用 `Value.absentIfNull`；`clear` 加一個 `bool` 參數，寫 `Value(null)`。
4. **Notifier**：生效值型別加欄位，在解析函式裡寫 `stored.x ?? 預設`；加一個 setter
   （`null` 呼叫 `clear`）。
5. **預設值**：只寫在解析函式的呼叫處。之後改預設只改這一處，不需要 migration。
6. **測試**：
   - repository：讀回寫入的值、部分寫入不動其他欄位、`stored format` 釘住字面值；
   - Notifier：沒設定時讀到預設；設定後讀到使用者值；
   - 改預設：同一份 `stored` 用兩組預設解析，使用者值不變、未設定的跟著新預設；
   - 只寫改動的欄位：寫一個欄位後直接查表，其他欄位仍是 `NULL`；
   - 清回未設定：`clear` 後直接查表是 `NULL`，其他欄位不動，讀到的回到預設。

## 測試寫法

- 用 `ProviderContainer.test(overrides: [appDatabaseProvider.overrideWithValue(memoryDatabase())])`。
- 讀 `StreamNotifier` 的連續值：`container.listen(provider, ..., fireImmediately: true)`
  把 `AsyncData` 轉進 `StreamController`，再用 `StreamIterator` 一個一個取（例子：
  `test/settings/appearance_settings_test.dart` 的 `appearances`）。
- 系統語言用 `TestWidgetsFlutterBinding.instance.platformDispatcher.localesTestValue`
  （整份偏好清單；`localeTestValue` 只改 `locale`，不會改 `locales`）設定，
  `addTearDown(clearLocalesTestValue)`；設定時會觸發 `didChangeLocales`，所以也能測
  「執行中跟著變」。

## Quality Check

- 表的新欄位是 `nullable()`，migration 沒有填預設值。
- 預設值沒有出現在 `lib/data/`。
- 上面第 6 步的五種測試都在。
