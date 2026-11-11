# 01: app 骨架與快速閘門

**What to build:** 新版的 `app/` 在 macOS、iOS 模擬器、Android 模擬器、Windows（`winpc`）都建得起來，啟動後顯示佔位畫面。同時接上快速閘門：`dart run tool/check.dart --quick`（format、analyze、單元測試）、改到 `app/` 的 commit 由 pre-commit 自動跑它、依賴規則測試、零聯網防線。舊版不受影響。這張票也實測 `winpc` 經 SSH 建置、啟動、截圖傳回的做法（brief §17）。

讀：plan §0、§1.2、§1.3、§2、§3、§4；brief §4、§12、§17；事實 K5、T1、T2；spec〈共同規則〉

**Blocked by:** None (can start immediately)

**Status:** done

- [x] `app/` 照 plan §1.2 建好四平台專案與空的模組目錄，身分是 `com.personal.fmp.dev`；M0 只設 dev 身分，不建 flavor（正式身分留到發佈的里程碑）。
- [x] 佔位畫面顯示 App 名稱，字串經 slang，zh-TW、zh-CN、en 齊全；Riverpod 全域關閉自動重試（事實 K5），有測試釘住。
- [x] `dart run tool/check.dart --quick` 跑 format、analyze、單元測試，任一失敗就非零退出。
- [x] `.githooks/pre-commit` 只在 staged 檔案含 `app/` 時跑 `--quick`；只改舊版或文件的 commit 不跑。啟用方式（`core.hooksPath`）寫進 `AGENTS.md`。
- [x] 依賴規則測試照 plan §1.3：`ui` 不碰 `data`、`plugins` 內部與平台套件；只有 `data/` import drift；只有 `platform/` import 平台套件與用 `Platform.isXxx`；Dart 端沒有音源識別碼的字面值分支。測試檔內雙向變異驗證：造違規會紅，改無關的格式或命名不會紅。
- [x] 零聯網：測試裡任何真實連線直接報錯（`HttpOverrides`），有測試證明；`live` tag 預設跳過。
- [x] 文件閘門（`--quick` 的一步）：progress.md 里程碑表裡還沒驗收的里程碑，它的 `.scratch/<里程碑>/issues/` 有一張 `*-acceptance.md`；已驗收的不查（驗收後補的票不影響）。雙向變異驗證：拿掉驗收票會紅，改票的內文、標題或編號不會紅。`AGENTS.md`〈Skills〉里程碑開工第 2 步那句補上「由 `check.dart` 的文件檢查守」。
- [x] 舊版不受影響：根目錄的 `flutter analyze`、`dart format`、`flutter test` 與 `ci.yml` 的步驟在有 `app/` 的情況下照舊通過（本機跑一遍 `ci.yml` 的指令並貼輸出）。
- [x] 四平台實跑，讀回畫面看到佔位畫面；Windows 經 SSH 用排程工作在桌面工作階段建置、啟動，截圖傳回 Mac。
- [x] `winpc` 的做法（同步工作樹、建置、啟動、截圖傳回）寫進 plan §2；brief §17 那條改成指向 plan §2。
- [x] 加的依賴版本寫進 plan §1.4；`AGENTS.md`〈目錄〉補上 `app/` 與 `.githooks/`。

## Comments

### 決定與取捨

- **依賴規則的例外（擁有者 2026-11-11 決定）**：plan §1.2 把音訊後端的兩個實作放在 `playback/`，§1.3 卻只准 `platform/` import 平台套件，兩者矛盾。擁有者選「§1.3 加例外」：只有 `playback/backends/` 能 import `just_audio`、`media_kit`，`playback/` 其他檔只依賴介面；另一個選項（把實作搬到 `platform/`）沒採用。plan §1.2、§1.3 與 progress.md〈偏差與決定〉已改。中間曾先做成整個 `playback/` 都可以（commit「allow audio player packages…」），之後照擁有者的補充收窄。
- **依賴規則測試的做法**：`app/test/architecture/dependency_rules.dart` 用 analyzer 解析 AST，不比對字串。`lib/` 用到的每個外部套件都要在 `packageScopes` 分類，新依賴沒分類會紅，這樣「平台套件」不用靠記性維持。`ui/` 不能碰的「`plugins` 內部」定為 `lib/plugins/src/`（Dart 的 `lib/src` 慣例）；票 08 設計插件宿主介面時若要別的切法，改這條測試。音源識別碼除了三個音源，也包含歌詞源 `lrclib`。
- **測試抓不到的繞法**（Spec 審查指出，未處理）：識別碼先存進常數再比較、`startsWith('bilibili')`、`{'bilibili': …}[id]` 查表，以及 `defaultTargetPlatform == TargetPlatform.windows`。前三種仍違反 ADR 0038 的精神，靠 code review；`defaultTargetPlatform` 要不要納入「平台層以外不得判斷平台」由擁有者決定，目前 plan §1.3 只寫 `Platform.isXxx`。
- **根目錄設定**：根目錄的 `analysis_options.yaml` 排除 `app/**`。不排除時，根目錄的 `flutter analyze` 會掃進 `app/`；CI 只對根目錄 `pub get`，`app/` 的 import 會全部解析失敗。舊版其他行為沒動。
- **Material**：pub 上已有官方拆出的 `material_ui`（1.11.0，要求 Flutter 3.47 以上），但 Flutter 3.47.5 仍內建 `package:flutter/material.dart`，`flutter create` 也用它。新版先用內建的、不加依賴；要不要改用 `material_ui`（遷移有 `dart fix --code=migrate_design_widgets`）留給擁有者在 M1 照稿切版前決定。事實寫進 brief T1。
- **身分與名稱**：bundle id、Android 的 `applicationId` 與 `namespace` 都是 `com.personal.fmp.dev`（建 flavor 時 `namespace` 要一起處理）。啟動器、視窗與選單列的名稱用「FMP Dev」，和舊版的「FMP」分得開；畫面上的 App 名稱照 slang 是「FMP」。`pubspec.yaml` 的 `version` 留 `flutter create` 的 `0.1.0+1`，brief §12 的 `2.0.0` 由發佈的里程碑設定。
- **Apple Team ID**：`flutter create` 自動把本機的 Team ID 寫進 `app/ios/Runner.xcodeproj/project.pbxproj`（Standards 審查抓到）。已拿掉，並加 `app/test/architecture/public_repo_test.dart` 防止再被寫回；模擬器與 macOS debug 建置不需要它。
- **i18n**：基準語言 zh-TW，`fallback_strategy: base_locale`。slang 的 fallback 會把漏翻默默換成 zh-TW，所以另有測試比對三個 JSON 的 key。裝置語言用 slang 的 `useDeviceLocaleSync`：zh-Hant-HK 這類沒有完全對上的中文會落到 zh-TW（同分時取第一個），zh-Hans-SG 也一樣；要分得更細時再加自訂比對。產生的 `*.g.dart` 不進 git，`--quick` 第一步先產生。
- **Riverpod 重試的測試**：Riverpod 3 的預設重試只重試 `Exception`、不重試 `Error`，所以測試丟 `Exception`（丟 `StateError` 時拿掉 `noRetry` 也不會紅）。
- **pre-commit**：git 給 hook 的 `GIT_DIR`、`GIT_INDEX_FILE` 等變數會讓 flutter 把自己的版本讀成 `0.0.0-unknown`、pub 解不出依賴，所以 hook 判斷完 staged 檔案就清掉 `GIT_*`；hook 的測試在暫存 repo 裡跑真的 `git commit`，也清掉這些變數，以免在 hook 裡跑測試時改到真正的 repo。`--no-renames` 讓「把檔案搬出 `app/`」的 commit 也會跑。啟用方式寫在 `AGENTS.md`〈目錄〉；這個 worktree 已設 `core.hooksPath`（設定和主 checkout 共用）。
- **`live` 測試**：`app/dart_test.yaml` 讓 `live` tag 預設跳過，手動跑用 `flutter test --run-skipped --tags live`。測試的零聯網防線會擋住它們，`live` 測試要用 `HttpOverrides.runWithHttpOverrides` 包一個不覆寫任何方法的 `HttpOverrides` 子類別換回真的 client（票 08、09 第一次寫 `live` 測試時會用到）。
- **`check.dart` 完整版**：不帶 `--quick` 時直接以 64 退出並說明，不會假裝通過；票 02 接上。
- **`winpc`**：腳本收在 `app/tool/winpc/`（`sync.sh`、`run_task.sh`、`build.ps1`、`shot.ps1`），做法與新怪癖寫進 plan §2，舊的「Windows 遠端」怪癖併進去。截圖會短暫搶 `winpc` 的前景，也可能夾到擁有者桌面的其他內容，截圖只留在本機暫存目錄。

### 驗證輸出

`cd app && dart run tool/check.dart --quick`（pre-commit 每次 commit 也跑）：

```text
ok   i18n (slang)
ok   format
ok   analyze
ok   test          # 00:02 +61: All tests passed!
ok   doc gate
```

故意弄壞 format 時是 `FAIL format`、退出碼 1。`live` tag：一般執行是 `+1 ~1`（`live` 測試被跳過），`--run-skipped --tags live` 時 `+1`。

四平台實跑（截圖留在本機暫存目錄，不進 repo）：

- macOS：`orca computer` 讀回視窗「FMP Dev」，畫面「FMP」「新版開發中」。
- iOS 模擬器（iPhone Duo，iOS 27.1）：`orca emulator ax` 讀到「FMP」「新版開發中」，截圖相同。
- Android 模擬器（`Medium_Phone_API_37.0`，系統語言英文）：`orca emulator ax` 讀到「FMP」「New version in development」，截圖相同。
- Windows（`winpc`，Flutter 3.47.5）：debug 與 release 都建置成功，排程工作啟動後截圖傳回 Mac，視窗「FMP Dev」，畫面「FMP」「新版開發中」。

舊版不受影響，在乾淨 clone（`git clone` 本分支）照 `ci.yml` 跑：

```text
dart format --output=none --set-exit-if-changed lib test tool   → Formatted 611 files (0 changed)
dart run build_runner build、dart run slang                      → 成功
flutter analyze                                                  → No issues found!
flutter test --coverage --exclude-tags live                     → 02:42 +1848 ~1: All tests passed!
flutter build apk --release --target-platform android-arm64     → BUILD FAILED（file_picker: compileReleaseJavaWithJavac (17) 與 compileReleaseKotlin (25) 的 JVM target 不一致）
```

APK 建置失敗是本機只有 JDK 25（`ci.yml` 用 JDK 17）：在沒有 `app/` 的 `cb37933e` 乾淨 clone 跑同樣的建置，失敗訊息完全相同，所以和 `app/` 無關。`ci.yml` 的 Windows 建置煙霧測試沒有在本機重跑（它只建根目錄的 `windows/`，`app/` 碰不到）。這兩個建置 job 要等 push 後看 GitHub 上的 `ci.yml`（M0 驗收〈舊版的 `ci.yml` 在 main 上綠燈〉）。

### code-review 未處理的發現

- Standards（判斷題）：`check.dart` 的 `_handwrittenDartFiles` 和 `readLibSources` 都是「走目錄、取 `.dart`、略過 `.g.dart`」，兩個測試檔各有一個 `_write`／`write`；分屬 tool 與測試，沒有合併。
- Standards（判斷題）：`_milestoneTable` 回傳 `List<Map<String, String>?>?`，null 同時代表「找不到表」與「欄數錯的列」；目前只有一個呼叫端，沒有另立型別。
- Standards（判斷題）：音訊播放器套件出界也回報成 `platformPackageOutsidePlatform`，規則名沒有另開。
- Spec：上面〈測試抓不到的繞法〉。

