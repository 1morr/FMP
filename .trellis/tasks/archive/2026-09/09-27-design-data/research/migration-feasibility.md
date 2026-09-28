# 遷移可行性研究：Isar 共存、原生函式庫、flutter_secure_storage 相容性

範圍：`.trellis/tasks/09-27-design-data` 研究項目 3、4。標記慣例同
`persistence-options.md`：「查不到」＝已查但沒有可信來源；「推測」＝有間接
證據但未直接證實。

擁有者硬性要求（`.trellis/tasks/09-27-design-data/prd.md`、對照
`docs/adr/0008-rewrite-as-new-app-in-same-repo.md` 決定 3「App 身分沿用」）：
舊資料庫、登入憑證（`flutter_secure_storage`）、下載檔案、舊備份檔全部
**自動遷移**，不需要使用者手動操作。

## 1. 若換資料層：暫時依賴 isar_community 讀舊檔的可行性

### 1.1 是否可行

可行。`isar_community` 是可獨立引入的一般 Dart／Flutter 套件，不需要開啟成
「主資料層」才能用——新 App 可以只用它的 `Isar.open()` + 對應的 schema class
把舊資料庫檔案打開、讀出所有 collection 的資料，轉換寫入新資料層（drift／
ObjectBox／其他），跑完就不再需要它。這正是 FMP 現有 ADR 0007 已經驗證過的
使用方式的子集——ADR 0007 證實「一份 3.1.0+1 寫出的真實資料庫（1,534 列）的
副本能原地打開、反序列化、寫入後讀回」，代表 isar_community 讀取現行 FMP
資料庫格式沒有相容性障礙。

Schema class 定義需要與 FMP 現行 11 個 collection 的 schema id／property id
完全一致才能正確反序列化（`docs/audit/data.md` 已盤點這些定義），這部分是
「複製 FMP 現有 model 定義」而非重新設計，风险集中在把這些 class 從舊
`isar`／`isar_community` 依賴版本正確搬到新 App 的 `pubspec.yaml`。

### 1.2 isar_community 與 drift(sqlite3) 能否共存（原生函式庫衝突）

**直接證據（同一組件並存於同一 App，長期生產環境）**：Finamp 目前的
`pubspec.yaml` 同時依賴 `isar`（fork：`Komodo5197/isar-community.git`，透過
override 指向社群 fork，與 FMP 使用的 fork 系出同源但非同一個 fork）與
`hive_ce`，兩者長期並存於同一個 App 且都在生產環境使用，`main.dart` 同時
`Isar.open(...)` 與 Hive 的初始化互不干擾：

```dart
_mainLog.info("Setup hive and isar");
...
final isar = await Isar.open(
  [DownloadItemSchema, IsarTaskDataSchema, FinampUserSchema, DownloadedLyricsSchema],
  directory: ...,
  name: isarDatabaseName,
);
```

來源：https://github.com/finamp-app/finamp/blob/master/lib/main.dart

**這個證據的侷限，必須明確標註**：
- Finamp 並存的是 Isar + Hive CE，**不是** Isar + drift/sqlite3。Hive 是純
  Dart 實作，沒有自己的原生函式庫；drift/sqlite3 則會透過 native assets
  機制打包一份原生 SQLite 動態函式庫。「Isar + Hive 共存沒問題」不能直接
  證明「Isar + drift/sqlite3 共存沒問題」，因為後者牽涉兩套不同的原生函式庫
  同時存在同一個 App 進程內。
- **沒有查到**任何專案同時依賴 `isar`／`isar_community` 與
  `sqlite3`／`sqlite3_flutter_libs`／drift 的公開範例（查了 GitHub code
  search 與 pub.dev 依賴關係，沒有命中）。
- 從**技術原理**推測（標記「推測」，可信度中高）：isar 的原生函式庫符號是
  `isar_*` 前綴（`libisar.dll`／`isar_community` 對應改名為
  `libisar.dll`，依 ADR 0007「Windows 的 library 名稱從 `isar.dll` 變成
  `libisar.dll`」），sqlite3 的原生函式庫符號是 `sqlite3_*` 前綴，兩者
  函式庫命名空間不重疊，理論上不會有連結期符號衝突；分屬不同的動態函式庫檔案
  （`.so`／`.dll`），作業系統的動態載入器本身就是為多個獨立函式庫共存設計的，
  沒有已知的技術原因會讓兩者無法在同一個 App 裡同時載入。真正的風險點通常是
  Android 的 native library 打包（多個外掛都想放同名 `.so` 或使用同一個
  ABI 目錄）與建置工具鏈整合，而非執行期衝突。
- **建議**：由於是「暫時共存」（遷移完成即可移除 isar_community 依賴，不是
  永久架構），實際風險可以用一個小驗證（在 tracer bullet 階段內建置一個同時
  引入兩個依賴的最小 App，跑一次 `flutter build apk`／`flutter build windows`
  確認建置與啟動皆正常）在成本很低的情況下排除，不需要在研究階段就下定論；
  若驗證失敗，退路是把遷移模組拆成獨立的 Dart 執行檔／腳本（不進 Flutter App
  bundle），只在遷移那一次性流程中跑，執行完即丟棄，徹底避開打包期衝突。

### 1.3 打包體積影響

**沒有查到**具體的位元組數字（isar_community 原生函式庫加 sqlite3 原生
函式庫同時打包會增加多少 APK/安裝檔大小），需要實測才能有確切數字。可以
給出量級推測（標記「推測」）：isar 原生函式庫按平台通常是數 MB 等級
（ADR 0007 提到的目標 ABI 是 Android `arm64-v8a`／`armeabi-v7a`／`x86_64`
與 Windows `x86_64`），sqlite3 原生函式庫本身通常也是 1 MB 內的等級，兩者
同時打包對現代 App 的總安裝檔大小（通常數十 MB 起跳）影響比例不大，但如果
是**永久性**同時依賴（而非遷移用完即丟），仍建議實測後再下結論。由於本研究
的情境是「臨時遷移用」，遷移模組完成後即可從 `pubspec.yaml` 移除
`isar_community` 依賴，之後的正式版打包不受影響。

### 1.4 Android 16 KB page-size 對齊：sqlite3（Dart 套件）現況

ADR 0007 已確認 isar_community 的 Android library 是 16 KB 對齊
（`docs/adr/0007-isar-stays-on-v3.md`）。查證 sqlite3（Dart 套件）本身：

- `sqlite3.dart`（simolus3/sqlite3.dart）的 CHANGELOG 沒有直接提及
  「16KB」「page size」「16384」等字樣（已查，無命中）——**這點單獨查證是
  「查不到」**。
- 但 GitHub Issues 上有多筆關於此套件與 16 KB page-size 的討論並且**都已
  關閉**：
  - #308「16KB page size not supported」——維護者
    （simolus3）在留言中說明：「I've added 16 KiB page size support somewhat
    recently (last year I believe)」，指向的是 `sqlite3_flutter_libs` 這個
    外掛套件本身的原生函式庫版本問題；回報者最後查明是**專案依賴了另一個
    過舊的 `sqlite3-native-library` Android 版本**，不是 `sqlite3.dart`／
    `sqlite3_flutter_libs` 本身缺乏支援，更新依賴版本後解決並關閉此 issue。
    來源：https://github.com/simolus3/sqlite3.dart/issues/308
  - #320「16KB Page Size Support Warning」、#321「Google Play's 16 KB page
    size compatibility」、#257「Failed to load dynamic library ... 16KiB
    page size」——皆為同一類問題（依賴版本過舊或 Google Play 檢查腳本誤判），
    均已關閉。
- **結論（推測，可信度中高）**：`sqlite3`／`sqlite3_flutter_libs` 上游已在
  約 2024–2025 年間修好 16 KB 對齊問題，只要依賴版本夠新（本研究建議的方案是
  透過 native assets 自動打包的最新 `sqlite3` v3.x，而非舊版
  `sqlite3_flutter_libs`），16 KB 對齊應該沒有問題。但**沒有查到**官方對
  「native-asset 打包管線（build hooks）產出的 binary 是否沿用同一套已修好
  對齊問題的原生原始碼與建置腳本」的明確重申文件——這點技術上兩者本來就是
  同一套上游 C 原始碼，只是打包／分發機制不同，可信度高但不是 100% 官方
  明文保證，仍標記為「推測」。建議在設計文件定案前，用
  `developer.android.com` 官方提供的 ELF alignment 檢查腳本
  （https://developer.android.com/guide/practices/page-sizes#alignment-use-script）
  對 tracer bullet 階段產出的 APK 實測一次，取得確定結論而非依賴文件推測。

### 1.5 其他專案常見的「一次性遷移模組」模式

從 Finamp 案例（雖然遷移方向與 FMP 相反，但模式本身可直接借鑑）歸納出兩種
模式，FMP 可依情境擇一：

- **模式 A：搬移後保留旧資料，靠旗標防止重跑**（Finamp
  `FinampUserHelper.migrateFromHive()`）：
  ```dart
  Future<void> migrateFromHive() async {
    await Hive.openBox<FinampUser>("FinampUsers");
    await Hive.openBox<String>("CurrentUserId");
    var currentUserId = Hive.box<String>("CurrentUserId").get("CurrentUserId");
    if (currentUserId != null) {
      var currentUser = Hive.box<FinampUser>("FinampUsers").get(currentUserId);
      if (currentUser != null) {
        _isar.writeTxnSync(() {
          _isar.finampUsers.putSync(currentUser, saveLinks: false);
        });
      }
    }
  }
  ```
  呼叫端由 `hasCompletedIsarUserMigration` 設定旗標防止重複執行，**不刪除**
  舊的 Hive box——舊資料留在磁碟上，只是不再被讀取。
- **模式 B：搬移後清掉舊儲存**（Finamp 同一個 codebase 內的
  `_migrateThemeModeLocale`）：複製完成後明確呼叫
  `oldThemeModeBox.deleteFromDisk()`／`oldLocaleBox.deleteFromDisk()`，
  再標記完成旗標。
  來源（模式 A、B 皆出自）：
  https://github.com/finamp-app/finamp/blob/master/lib/services/finamp_user_helper.dart
  、`lib/main.dart` 同檔。

FMP 的情境（自動遷移整個舊資料庫、憑證、下載檔、備份檔，且擁有者要求
「自動」而非使用者手動觸發）比較貼近**模式 A** 再加上「遷移驗證通過才刪除
舊檔」的保守版本：先用旗標＋完整性檢查確認新資料層內容與舊資料庫一致，才
清理舊 Isar 檔案，避免遷移中途失敗導致資料兩邊都不完整。這與
`docs/adr/0008-rewrite-as-new-app-in-same-repo.md` 決定 5「切換」條款一致
（「舊資料自動遷移在真實資料副本上驗證過之後」才刪除舊專案）——但那條講的是
「刪除舊 App 程式碼」的時機，遷移模組本身「何時刪除使用者裝置上的舊資料庫
檔案」是另一個需要在 design.md 明訂的獨立決策點。

## 2. flutter_secure_storage

### 2.1 五平台支援與各平台後端

| 平台 | 後端套件 | 實際儲存機制 | 來源 |
|---|---|---|---|
| Android | 內建於主套件 | Android Keystore + EncryptedSharedPreferences | https://pub.dev/packages/flutter_secure_storage |
| iOS | 內建於主套件 | Keychain | https://pub.dev/packages/flutter_secure_storage |
| macOS | 內建於主套件 | Keychain | https://pub.dev/packages/flutter_secure_storage |
| **Windows** | `flutter_secure_storage_windows` | **混合式**：每個 key 的值用 AES-GCM 加密後存成獨立 `.secure` 檔案，放在 App 的 support 目錄；AES-GCM 的加密金鑰本身存在 **Windows Credential Manager**（不是常見誤解的「純 DPAPI」） | https://pub.dev/documentation/flutter_secure_storage_windows/latest |
| **Linux** | `flutter_secure_storage_linux` | 透過 **libsecret**（`org.freedesktop.Secret`／`org.freedesktop.portal.Secret`），需要有執行中的 keyring 服務（`gnome-keyring`、`kwalletmanager`，或輕量的 `secret-service`）；支援 Flatpak／沙盒環境（走 portal）；新版 Freedesktop runtime（25.08+）／GNOME 49／KDE 6.10+ 已內建 libsecret，App 不必自行編譯進去 | https://pub.dev/packages/flutter_secure_storage |

FMP 目標第一版平台是 Android＋Windows，兩者後端都已查證：Android 走
Keystore-backed EncryptedSharedPreferences，Windows 走上述混合式機制，皆為
成熟、持續維護的官方後端，沒有查到相容性風險。Linux（未來平台）需要注意
執行環境必須有 keyring 服務在跑，這是 Linux 桌面環境的外部依賴，不是套件
本身的問題——若目標是 AppImage／Flatpak 散布，需要在該平台的 child task
額外驗證 keyring 服務的可用性假設是否成立。

### 2.2 新版能否讀舊版寫入的值（10.x → 最新版）

**沒有查到**官方文件或 CHANGELOG 對「跨大版本讀取相容性」的明確保證聲明
（例如「10.x 寫入的值保證能被最新版讀取」這類逐字聲明）。從技術層面推斷
（標記「推測」，可信度中）：

- Android／iOS／macOS 三個平台的底層儲存機制（Keystore、Keychain）本身是
  作業系統管理的服務，不是套件自己控制的檔案格式，只要金鑰／識別子命名規則
  沒有跨版本改變，理論上舊版寫入的值可以被新版正常讀出——這类风险主要來自
  套件本身是否在某次大版本更新中**改變了 key 的命名空間或加密參數**，而非
  作業系統層面的問題。
- Windows／Linux 後端因為是套件自己實作的邏輯（AES-GCM 檔案格式、libsecret
  schema），版本間相容性完全取決於這兩個聯邦套件（
  `flutter_secure_storage_windows`、`flutter_secure_storage_linux`）自己的
  CHANGELOG 有沒有做過破壞性格式變更——這點需要在真正決定升級版本號之前，
  針對目標新版本逐一讀過這兩個套件從 10.x 到最新版之間的 CHANGELOG 找
  「BREAKING」「format change」「migration」等字樣，本研究**尚未逐版讀完
  完整 CHANGELOG**，標記為此項研究的已知缺口，建議設計 migration 模組時
  另外花時間做這個逐版 CHANGELOG 檢查，或更保守地採用「用舊版本讀出全部值→
  用新版本重新寫入」的顯式遷移步驟，完全繞開「新版本能不能讀舊版本格式」
  這個問題本身。

### 2.3 FMP 舊版為何刻意停在 10.x

對舊專案根目錄 `pubspec.yaml` 執行 `grep -n -B3 -A3 flutter_secure_storage`，
找到明文理由（一手證據，非推測）：

```
# 「10.x 發過一版」不等於「每個安裝都遷移過」—— 沒跑過 10.x 的安裝一升到 11.x
# 就讀不出憑證，只因 `SecureKeyValueStore` 的防護才降級成重新登入而不是崩潰。
# `.github/dependabot.yml` 因此 ignore 它的大版本。
flutter_secure_storage: ^10.3.1  # Cookie/Token 安全儲存
```

來源：`C:\Users\Roxy\orca\FMP\pubspec.yaml:70-73`（現行舊專案根目錄）。

**這是本研究對「新版能否讀舊版寫入的值」最直接、最具體的一手證據**，比
2.2 節的官方文件推測更可信，且結論是**否定**的一個具體案例：從
`flutter_secure_storage` 10.x 升到 11.x 存在已知的讀取相容性斷層——
**不是「每個裝置都會壞」，而是「沒有實際跑過 10.x 版本程式碼的安裝，一旦
直接升級到 11.x 就讀不出用舊格式寫入的憑證」**。FMP 現行程式碼靠自製的
`SecureKeyValueStore` 包裝層吸收了這個問題，讀取失敗時的行為降級成「要求
使用者重新登入」而不是讓 App 崩潰，把資料遺失的後果限制在「使用者體感是
被登出」而非資料損毀或當機。`.github/dependabot.yml` 也因此手動 ignore 這個
套件的大版本升級 PR，是刻意的、有記錄的決定，不是疏漏。

**對新 App 的設計意涵**：
1. 這個案例直接證明「假設新版能讀舊版格式」是不安全的預設——即使同一個套件
   的同一個大版本區間內（10.x→11.x）都可能出現讀取斷層，遑論新 App 若選用
   更新的大版本。
2. 新 App 若要讀取舊 App 用 `flutter_secure_storage` 10.x 寫入的憑證，最
   穩妥的路徑是：新 App 的遷移模組**暫時也依賴 `flutter_secure_storage`
   10.x**（與舊 App 完全相同的版本）去讀出憑證明文，讀出後立刻用新 App
   正式採用的版本（可以是最新版）重新寫入，寫入格式由新版本自己決定，
   不依賴任何「跨版本讀舊格式」的隱含假設。這與舊 App 現行的
   `SecureKeyValueStore` 保護精神一致：讀取失敗要降級成「要求重新登入」而
   非讓遷移流程整個中止或崩潰，若讀取失敗，新 App 應该允許使用者用登入
   流程重新取得憑證，而不是把整個資料遷移判定為失敗。
3. `docs/adr/0008-rewrite-as-new-app-in-same-repo.md` 決定 3「App 身分沿用」
   確保新 App 與舊 App 共用 Android Keystore／Windows Credential Manager
   的存取範圍（同一個 `applicationId`／簽名金鑰），這是「新 App 能不能讀到
   舊 App 憑證」的**前提**（身分不同，作業系統層面就不會授權存取），本節談
   的是「身分符合的前提下，套件版本間的格式相容性」這個獨立的第二層風險。
