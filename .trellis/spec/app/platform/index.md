# 平台層（`app/lib/platform/`）

加或改平台能力時適用。規則（只含已實作的能力、平台判斷只在組裝點）與閘門見
`app/AGENTS.md` § 平台層；為什麼這樣分，見 ADR 0009。這裡只寫怎麼做。

## 目錄

```
lib/platform/
  platform.dart                 # 組裝點 AppPlatform：唯一判斷平台的地方
  platform_capabilities.dart    # 能力宣告 PlatformCapabilities
  <能力>/
    <能力>.dart                 # 介面（或值型別）與跨平台共用的邏輯
    <能力>_<平台>.dart          # 各平台實作；平台套件只在這裡 import
```

現有的例子：`app_data_directory/`（介面＋兩個實作）、`fonts/`（值型別＋各平台的常數）、
`connectivity/`（介面＋一個實作給兩個平台：差異都在套件的原生端時，實作檔以套件命名，
`connectivity_plus_interfaces.dart`，組裝點兩個分支各建一個）、`cache_directory/`（沒有介面的
一個類別：兩個平台只差在 path_provider 的原生端，路徑由組裝點注入；只准快取模組 import，所以
它的大小宣告另放 `cache_sizes/`）。

## 加一個能力

1. **介面**：`<能力>/<能力>.dart`。有行為的用 `abstract interface class`；只是資料的
   （像字型清單）用 `@immutable` 的值型別。介面不 import 平台套件，也不判斷平台。
2. **實作**：只替已經要在實機驗證的平台寫 `<能力>_<平台>.dart`。系統值（路徑、環境變數、
   path_provider 的呼叫）從建構子注入，實作本身不讀 `Platform`，才能在暫存目錄上測。
3. **宣告**：在 `PlatformCapabilities` 加欄位，連同 `none` 一起改。欄位表達「有沒有」或
   平台給的值；不為還沒實作的能力預留。
4. **組裝**：`platform.dart` 的 `switch` 在各平台分支建立實作並填宣告；讀
   `Platform.resolvedExecutable`、`Platform.environment` 這類值也在這裡。有實作的能力在
   `AppPlatform` 加一個欄位，並擴充建構子的 `assert`，讓宣告與實作對得上。
5. **呼叫端**：UI 看 `capabilities` 決定是否顯示入口；服務拿 `AppPlatform` 上的實作。
   `lib/platform/` 以外不判斷平台。

## 測試

- `test/platform/platform_test.dart`：`AppPlatform.assemble(TargetPlatform.x, …)` 注入平台值，
  逐平台斷言新欄位與實作型別；未驗證平台的案例斷言它仍是「沒有」。
- `test/platform/<能力>_test.dart`：直接建構各平台實作、注入路徑與 callback，在
  `Directory.systemTemp` 下跑，不讀真實 `Platform`（例子：`app_data_directory_test.dart`）。
- 使用者看得到的能力另外在 Android 模擬器與 Windows 實機驗（`app/AGENTS.md` § 實機驗證）。

## Quality Check

- `AppPlatform` 以外沒有新的平台判斷；`dart analyze --fatal-infos` 乾淨。
- 未驗證平台（Linux、macOS、iOS）沒有新的實作檔。
- 新欄位在 `platform_test.dart` 每個平台都有一個斷言。
