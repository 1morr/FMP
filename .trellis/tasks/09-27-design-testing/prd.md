# 設計：測試、閘門與開發環境（階段二第 8 項）

## 目標

為 `app/` 定下：保留哪些舊測試與 static-rule、新架構的閘門（lint、測試、CI）、零聯網的預設測試與 fixture、
腳本插件的共用契約測試、聯網冒煙測試、開發時少打真實 API 的方法，以及開發版與正式版分離（U9、單一實例）。
產出 ADR 0015。技術設計見 `design.md`，執行步驟見 `implement.md`，研究見 `research/`。

依據：parent `prd.md` 階段二第 8 項；`phase2-plan.md` §4（測試、static-rule、單一實例三段）；
`docs/audit/questions.md` §10（四類測試你都勾「不確定」並附備註）與 U9；ADR 0008–0014 的「如何確認」段。

## 現況（審計，`docs/audit/engineering.md`）

- 約 1,849 個離線測試本機全過（2 分 48 秒）；25 支 static-rule（144 個 test）以正則比對原始碼，部分是計次預算
  （`audio_provider.dart` ≤ 2,184 行；音源分支預算 9 處但實際 50 處沒守住）（§5）。
- `dart_test.yaml` 只宣告 `live` tag、沒有預設跳過：**裸 `flutter test` 會打真實 API**（4 個 live 測試）；CI 靠 `--exclude-tags live`。
- 部分行為測試依賴 `debug*ForTesting` 掛鉤（下載服務 44 處，全專案 `debug*` 成員 75 處）。
- CI（`.github/workflows/ci.yml`）：單一專案、不做路徑過濾（理由寫在檔頭 `:3-7`），釘 Flutter 3.47.1（`:28`）；validate 7 分、Android 6 分、Windows 10 分。
- 開發版與正式版共用同一個單一實例鎖與同一份資料（Windows `Documents\FMP`，`database_provider.dart:49-52`），開發時會動到真實資料。
- 備份匯出／匯入已存在且不含帳號與 Cookie（`docs/audit/features.md` §12）。

## 研究結論摘要（`research/` 三份，關鍵事實已抽查）

- lint 用官方 `analysis_server_plugin` 自寫；`custom_lint` 已封存。`flutter analyze` 目前不顯示插件診斷（flutter/flutter#193203）。
- fixture 錄製／重播自寫在 dio `HttpClientAdapter` 層；現成套件不合 dio 或維護不明。
- 零聯網用 `dart_test.yaml` tag skip＋`HttpOverrides`（dart-lang/test 設定文件查證）。
- `flutter_js` 的 QuickJS 在 `flutter test` 不會自動載入（`quickjs_engine` 文件）；桌面 `integration_test` 一定載得到。
- Flutter 3.47 起 Windows／Linux 有官方 flavor；`default-flavor` 可設預設 flavor（context7 查證）。
- 公開 repo 的 CI 免費不限分鐘；Flutter 官方不給測試比例；golden 用 `alchemist`（`golden_toolkit` 停更）。

## 決定

1. **檢查案例一份四用**：每插件每能力最多一條案例，用於契約測試（重播，進 CI）、冒煙測試（真實連線、手動）、
   Debug 頁健康檢查（真實連線、App 內）、錄製（遮蔽後存 fixture）。冒煙測試不進任何 CI、不排程（你先前按推薦確認）。
2. **插件開發在 App 內**（2026-09-27 選 A）：開發者模式下從資料夾載入、重新載入、跑案例看 log、用 App 內登入錄 fixture、每插件切換真實／錄製／重播；
   命令列只負責重播。從資料夾載入先只在桌面平台。
3. **開發版資料預設空白**（2026-09-27 選 A）：要真實資料時用舊資料匯入（選資料夾副本）或還原正式版備份，不另做快照功能；
   開發版拒絕直接讀舊版正式資料位置。Android 的舊資料遷移驗證在模擬器以 prod flavor 做。
4. 技術選擇（`design.md`）：測試分層與原則（§1）、lint L1–L10 與接線哨兵（§2）、fixture 格式／遮蔽／契約執行器／測試插件（§3）、
   零聯網（§4）、flavor 與身分（§5）、舊 static-rule 逐條去向（§6）、CI 依專案切分（§7）、第一個里程碑實測（§8）。

## 驗收條件

- [ ] ADR 0015 記錄決定 1–4 的原則與理由，含被否決的方案（DCM／`custom_lint`、現成 VCR 套件、排程冒煙測試、命令列限定的插件開發、開發版快照）。
- [ ] 舊 static-rule 25 支＋`test/workflows/` 逐條有去向與理由（`design.md` §6）。
- [ ] ADR 0008、0009、0010、0011、0013、0014 的「如何確認」中待測試策略落實的閘門，各自對到一條規則名或測試。
- [ ] `phase2-plan.md` §7 加入 `design.md` §8 的實測項；§3 第 8 項標 ✅ 與 ADR 編號；§10 交接段更新。
- [ ] `git grep "測試策略 ADR" docs/adr` 無遺留指向。

## 不在範圍

- 實作任何測試、lint 或 CI（屬各里程碑）。
- Debug 頁與插件開發工具的版面（第 4 項）；播放核心、歌詞、背景任務、UI、發版相關規則的細節（第 13、15、16、5、19 項）。
- 舊專案（根目錄）的測試調整，除了 CI 切分。
