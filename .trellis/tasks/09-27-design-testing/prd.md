# 設計：測試、閘門與開發環境（階段二第 8 項）

## 目標

為 `app/` 定下：保留哪些舊測試與 static-rule、新架構的閘門（lint、測試、CI）、零聯網的預設測試與 fixture、
腳本插件的共用契約測試、聯網冒煙測試、開發時少打真實 API 的方法，以及開發版與正式版分離（U9、單一實例）。
產出 ADR 0015。

依據：parent `prd.md` 階段二第 8 項；`phase2-plan.md` §4（測試、static-rule、單一實例三段）；
`docs/audit/questions.md` §10（四類測試你都勾「不確定」並附備註）與 U9；ADR 0008–0014 的「如何確認」段。

## 現況（審計，`docs/audit/engineering.md`）

- 約 1,849 個離線測試本機全過（2 分 48 秒）；25 支 static-rule（144 個 test）以正則比對原始碼，部分是計次預算
  （`audio_provider.dart` ≤ 2,184 行；音源分支預算 9 處但實際 50 處沒守住）。
- `dart_test.yaml` 只宣告 `live` tag、沒有預設跳過：**裸 `flutter test` 會打真實 API**（4 個 live 測試）；CI 靠 `--exclude-tags live`。
- 部分行為測試依賴 `debug*ForTesting` 掛鉤（下載服務 44 處，全專案 `debug*` 成員 75 處）。
- CI（`.github/workflows/ci.yml`）：單一專案、不做路徑過濾（理由寫在檔頭），釘 Flutter 3.47.1；validate 7 分、Android 6 分、Windows 10 分。
- 開發版與正式版共用同一個單一實例鎖與同一份資料（Windows `Documents\FMP`），開發時會動到真實資料。

## 你已表達的方向

- 測試不打真實 API；真實 API 只在 Debug 頁手動檢查或明確指定的冒煙測試（`questions.md` §10 備註）。
- 冒煙測試不進 CI（`phase2-plan.md` §4 傾向，你在順序確認時「按推薦」）。
- 只保留守「行為一致」的必要測試；static-rule 改用 Dart analyzer lint（`phase2-plan.md` §6）。
- 開發版資料隔離（U9 勾選）；單一實例保留給正式版。

## 研究結論（`research/` 三份，已抽查關鍵事實）

1. **lint**：官方 `analysis_server_plugin`（Dart 3.10+）自寫規則；`custom_lint` 已封存且依賴的舊協定在 Dart 3.13.2 棄用。
   規則測試用官方 `analyzer_testing` 的 `assertDiagnostics`／`assertNoDiagnostics`，正好是「雙向變異驗證」。
   現成工具（DCM 付費、DCL）只能做 import／呼叫限制，ADR 0013 的嚴格空 catch 與 ADR 0014 的音源 id 規則都要自寫，所以全部自寫、不引入 DCM。
   **地雷**：`flutter analyze` 目前不顯示 plugin 診斷並回報 No issues（flutter/flutter#193203，3.47.5 可重現，修復未確認進 stable）
   → CI 用 `dart analyze --fatal-infos` 並放一個必紅的哨兵檔驗證 plugin 有接上。
   官方 `empty_catches` 放行 `catch (_) {}`，不符 ADR 0013。
2. **fixture**：不用現成套件（`vcr` 系維護不明、`dartvcr` 是 `package:http` 不是 dio），自寫薄的 dio `HttpClientAdapter`
   在最底層錄製／重播；因為 adapter 層看到的請求已含憑證，寫檔前一律經 ADR 0011 的正式遮蔽函式，另有測試掃描所有 fixture 不得含未遮蔽憑證。
   JS 插件只經宿主 `http.request` 出網，契約測試只換掉宿主這一端，腳本不知道自己在測試。
3. **零聯網**：`dart_test.yaml` 對 `live` tag 設 `skip`（`presets` 解除，已查 dart-lang/test 設定文件）＋
   `flutter_test_config.dart` 用 `HttpOverrides.global` 讓建立真實 `HttpClient` 直接丟錯。
4. **契約測試在哪裡跑**：`flutter_js` 的原生 QuickJS 在 `flutter test`（純 Dart VM）不會自動載入，需先建好動態庫再指定路徑
   （`quickjs_engine` 文件同樣說明）；`integration_test` 在桌面跑真的 App 二進位則一定載得到。→ 第一個里程碑實測。
5. **開發版**：Flutter 3.47 起 Windows／Linux 有官方 `--flavor`；`pubspec.yaml` 的 `flutter: default-flavor:` 讓不帶參數的
   `flutter run` 用指定 flavor（context7 查證）。官方 flavor 只管建置輸出、視窗標題、圖示；
   Windows AppUserModelID、資料目錄、單一實例鎖名稱要自己依 `appFlavor` 接上（推測可行，未實測）。Android 用 `applicationIdSuffix`。
6. **CI**：公開 repo 的 GitHub-hosted runner 免費不限分鐘；兩個 Flutter 專案用 `dorny/paths-filter` 依專案切 job，
   不依「是不是程式碼」切（舊檔頭理由仍成立）；彙總 job 當唯一必要檢查。
7. **測試比例**：Flutter 官方不給數字，只給「單元＋widget 多、整合測試挑重要情境」。golden 用 `alchemist` 的 CI golden（Ahem 字型，跨平台一致），
   `golden_toolkit` 已停更。

## 待決定

- [ ] 插件開發迴圈與 fixture 錄製在哪裡做（App 內開發工具 vs 只有命令列）
- [ ] 開發版資料：永遠從空白開始，或可從正式版複製一份快照
- 其餘（lint 規則清單、空 catch 例外寫法、舊 static-rule 逐條去留、golden 範圍、CI 切分）屬技術選擇，放進 design.md 與最終摘要一併核准。

## 驗收條件

- [ ] ADR 0015 記錄：測試分層與保留原則、lint 閘門與 CI 指令、零聯網機制、fixture 格式與遮蔽、插件契約測試／冒煙測試／健康檢查的關係、開發版身分與資料隔離、CI 切分。
- [ ] 舊 static-rule 25 支逐條給出去向（改 lint／改測試／刪除／屬舊專案不動），附理由。
- [ ] ADR 0008（`app/` 不 import 舊專案）、0011（遮蔽測試）、0013（空 catch、原文不上畫面）、0014（契約測試、音源 id lint）的「如何確認」各自對到一個具體閘門。
- [ ] 第一個里程碑的必要驗證（`phase2-plan.md` §7）補上本項的實測項。
- [ ] `phase2-plan.md` §3 第 8 項標 ✅ 與 ADR 編號。

## 不在範圍

- 實作任何測試、lint 或 CI（屬各里程碑）。
- Debug 頁的版面與其他功能（第 4 項）；本項只定健康檢查與插件開發工具「要不要有、共用什麼」。
- 舊專案（根目錄）的測試調整，除了 CI 切分。
