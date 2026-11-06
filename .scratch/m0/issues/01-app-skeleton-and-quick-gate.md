# 01: app 骨架與快速閘門

**What to build:** 新版的 `app/` 在 macOS、iOS 模擬器、Android 模擬器、Windows（`winpc`）都建得起來，啟動後顯示佔位首頁。同時接上快速閘門：`dart run tool/check.dart --quick`（format、analyze、單元測試）、改到 `app/` 的 commit 由 pre-commit 自動跑它、依賴規則測試、零聯網防線。舊版不受影響。這張票也實測 `winpc` 經 SSH 建置、啟動、截圖傳回的做法（brief §17）。

讀：plan §0、§1.2、§1.3、§2、§3、§4；brief §4、§12、§17；事實 K5、T1、T2；spec〈共同規則〉

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `app/` 照 plan §1.2 建好四平台專案與空的模組目錄，身分是 `com.personal.fmp.dev`；M0 只設 dev 身分，不建 flavor（正式身分留到發佈的里程碑）。
- [ ] 佔位首頁顯示 App 名稱，字串經 slang，zh-TW、zh-CN、en 齊全；Riverpod 全域關閉自動重試（事實 K5），有測試釘住。
- [ ] `dart run tool/check.dart --quick` 跑 format、analyze、單元測試，任一失敗就非零退出。
- [ ] `.githooks/pre-commit` 只在 staged 檔案含 `app/` 時跑 `--quick`；只改舊版或文件的 commit 不跑。啟用方式（`core.hooksPath`）寫進 `AGENTS.md`。
- [ ] 依賴規則測試照 plan §1.3：`ui` 不碰 `data`、`plugins` 內部與平台套件；只有 `data/` import drift；只有 `platform/` import 平台套件與用 `Platform.isXxx`；Dart 端沒有音源識別碼的字面值分支。測試檔內雙向變異驗證：造違規會紅，改無關的格式或命名不會紅。
- [ ] 零聯網：測試裡任何真實連線直接報錯（`HttpOverrides`），有測試證明；`live` tag 預設跳過。
- [ ] 文件閘門（`--quick` 的一步）：progress.md 里程碑表裡還沒驗收的里程碑，它的 `.scratch/<里程碑>/issues/` 有一張 `*-acceptance.md`；已驗收的不查（驗收後補的票不影響）。雙向變異驗證：拿掉驗收票會紅，改票的內文、標題或編號不會紅。`AGENTS.md`〈Skills〉里程碑開工第 2 步那句補上「由 `check.dart` 的文件檢查守」。
- [ ] 舊版不受影響：根目錄的 `flutter analyze`、`dart format`、`flutter test` 與 `ci.yml` 的步驟在有 `app/` 的情況下照舊通過（本機跑一遍 `ci.yml` 的指令並貼輸出）。
- [ ] 四平台實跑，讀回畫面看到佔位首頁；Windows 經 SSH 用排程工作在桌面工作階段建置、啟動，截圖傳回 Mac。
- [ ] `winpc` 的做法（同步工作樹、建置、啟動、截圖傳回）寫進 plan §2；brief §17 那條改成指向 plan §2。
- [ ] 加的依賴版本寫進 plan §1.4；`AGENTS.md`〈目錄〉補上 `app/` 與 `.githooks/`。
