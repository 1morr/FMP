# 0008 — 重寫：在同一 repo 的 `app/` 另建新專案，搬運葉節點邏輯

> 補充（2026-09-27）：音源相關的邏輯不搬運 Dart 程式碼，改以舊程式碼為規格、用 JS 腳本重寫並放在獨立插件庫，見 [ADR 0014](0014-script-source-plugins.md)。其他葉節點（例如 `TrackKey` 格式）照本 ADR 搬運。

- 狀態：已採納
- 日期：2026-09-27
- 影響範圍：repo 目錄結構、`.github/workflows/`、`orca.yaml`、`AGENTS.md`、App 身分識別、舊版發版流程

## 背景

FMP 經過多輪 AI agent 自主修改（`lib/` 343 檔 99,063 行），擁有者已不清楚程式實際在做什麼。
2026-09 的現況審計（`docs/audit/`）顯示，新架構要改動的範圍幾乎涵蓋每一層：
資料層可能換庫、音源要插件化、平台差異要收進單一平台層、錯誤模型要統一、
2,953 行的 `AudioController` 要拆（`docs/audit/architecture.md`、`docs/audit/questions.md`）。

限制條件（擁有者已定）：重寫期間功能凍結、不發正式版；舊資料庫、憑證、下載檔全部自動遷移；
第一版目標平台 Android＋Windows；每個任務一個可 review 的 PR。

## 考慮過的選項

### 選項 A：在現有程式碼上逐步替換（Strangler Fig）

一塊一塊換成新架構，新舊並存，每次合併後現行 App 都完整可用。
優點：沒有「新 App 功能不齊」的階段。
缺點：幾乎每一層都要換，換資料層期間新舊兩套資料存取必須同步；過渡程式碼大量出現且最後要丟，
違反「內部改動不留相容層」；舊架構的循環依賴與上帝類別會拖住新設計；PR 較難 review。

### 選項 B：全新骨架＋搬運葉節點邏輯（採用）

同一 repo 另建新 Flutter 專案，依新架構搭骨架；已被測試證明的葉節點邏輯（音源 API 呼叫、
簽名與加密、解析器、`TrackKey` 持久化格式）連同測試複製進來再依新介面調整。
優點：沒有過渡層；新架構不受舊形狀牽制；避開整體重寫最大的風險——把能用的東西重寫一遍再寫壞。
缺點：新 App 功能齊全前，擁有者日常仍用舊版；repo 裡暫時有兩個 Flutter 專案。

### 位置的子選項

- **長期 `rewrite` 分支**：`main` 乾淨，但分支越久最後合併越痛，舊版修正要同步兩邊。否決。
- **另開新 repo**：完全隔離，但 issue、release、Actions secrets 與自動更新的 release 來源都要搬。否決。
- **同一 repo 的 `main`、子目錄 `app/`**：採用。

## 決定

1. **全新骨架＋搬運葉節點邏輯**（選項 B）。葉節點是**複製**，`app/` 不 import 根目錄舊專案的任何程式碼。
   第一個里程碑是 tracer bullet：一個音源能搜尋並播放，在 Android 與 Windows 跑通，之後逐層加能力。
2. **位置**：同一 repo 的 `main`，新專案在 `app/`，這也是它的永久位置；舊專案留在根目錄、凍結。
   `app/` 有自己的 `AGENTS.md`（agents.md 慣例：agent 讀離它最近的那一份）。
3. **App 身分沿用**：新 App 使用與舊 App 相同的身分識別——Android `applicationId` `com.personal.fmp`
   （`android/app/build.gradle.kts:29`）與同一把簽名金鑰、Windows AppUserModelID `com.personal.fmp`
   （`windows/runner/main.cpp:43`）、Inno Setup AppId（`pubspec.yaml:121-122`）。
   只有同一身分，Android 上才讀得到舊 App 私有目錄的資料庫與 Keystore 保護的憑證，舊版也才能直接升級。
   開發版另用身分，與正式版分開。
4. **舊版緊急修正**：在 `main` 上改根目錄舊專案、走一般 PR、照舊以 `vX.Y.Z` tag 發版；每次先經擁有者同意。
5. **切換**：`docs/audit/features.md` 中勾「保留」的功能全部在 `app/` 跑通、效能不低於
   `docs/audit/perf-baseline.md`、舊資料自動遷移在真實資料副本上驗證過之後，以一個 PR 刪除根目錄舊專案與
   `docs/audit/`，並把 `release.yml`、`ci.yml`、`orca.yaml`、`tool/release/` 改指向 `app/`。
   新 App 的第一個正式版本號接在舊版之後，經應用內更新送達，首次啟動執行自動遷移。

採用的慣例：以 Martin Fowler〈Strangler Fig Application〉為對照；他反對整體重寫的主要理由
（使用者等不了新功能、舊行為難以釐清）在這裡不成立——功能凍結且不發版，舊行為已盤點並經擁有者逐項勾選。
主幹開發（不開長期分支）與 agents.md 的巢狀 `AGENTS.md` 慣例。

## 後果

- 好的：每個里程碑是可 review 的小 PR，直接合進 `main`；沒有過渡程式碼；舊版隨時可以緊急修正並發版。
- 壞的：重寫期間 CI 要跑兩個專案，時間變長；兩份 `AGENTS.md` 要各自寫清楚適用範圍；
  新 App 功能齊全前不能取代舊版。
- 之後要注意：新 App 的身分識別一旦與舊版不同就無法自動遷移，任何改動 `applicationId`、簽名、AppId 的變更都必須另立 ADR。
  CI 依專案切分，舊專案的測試只在根目錄變動時跑、不擋 `app/` 的 PR（ADR 0015）。

## 如何確認

- `app/` 不得 import 根目錄舊專案：lint `fmp_layer_imports`（ADR 0015）。
- App 身分識別：測試斷言 prod flavor 的身分值與上列一致（ADR 0015）；切換前的里程碑另加一項檢查，比對 `app/` 的 `applicationId`、AppUserModelID、Inno Setup AppId 與上列現值一致。
- 切換條件：切換 PR 的 review 指南逐項列出 `features.md` 勾「保留」的功能與效能量測結果。
