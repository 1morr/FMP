# 設計第 7 項（高層）：重寫策略

## 目標

決定「全新重寫」還是「在現有程式碼上逐步替換」，以及對應的程式碼位置、分支、發版與舊版修正的路徑。
這裡只定方向；里程碑拆分在階段二最後（第 7 項定稿）做。

需求來源：parent `prd.md` 階段二第 7 項、「重構過程的約束」；`phase2-plan.md`。

## 已確認的約束（使用者已定）

- 每個 child task 一個 PR、大小可 review、附 review 指南；沒有經確認的 ADR 的設計不進程式碼。
- 功能凍結：重寫期間不加新功能。
- 完成定義：`features.md` 勾「保留」的功能全部在新架構跑通，效能不低於 `perf-baseline.md`。
- 重寫期間不發正式版本；N1（現行版資料遺失）選「先不修，重寫時處理」。
- 資料相容：資料庫、憑證、下載檔全部自動遷移，舊備份可匯入（questions.md A3）。
- 第一版目標平台 Android＋Windows，Linux／macOS／iOS 之後加入（A1）。
- 使用者全域規則：tracer bullet，每一步結束 repo 都可運作；內部改動不留相容層。

## 現況（證據）

- `lib/` 343 檔 99,063 行；最大的是 `audio_provider.dart` 2,953 行、`youtube_source.dart` 2,431 行、`download_service.dart` 2,030 行（`docs/audit/architecture.md` §2）。
- 新架構預計改動的範圍幾乎涵蓋每一層：資料層可能換庫（A2）、provider 結構（G6）、音源插件（G3）、平台層（§8）、錯誤模型（G4）、播放核心（G1、G5）。
- 可直接沿用價值高的「葉節點」邏輯：各音源的 API 呼叫、簽名與加密（`netease_crypto.dart`、WBI、InnerTube）、解析器、`TrackKey` 持久化格式（ADR 0005），以及 1,849 個離線測試中測這些行為的部分。
- 離線測試本機全過；main 的 CI 目前因一個時序測試失敗（`docs/audit/engineering.md` §12）。

## 採用的慣例

- Martin Fowler〈Strangler Fig Application〉：逐步把行為從舊系統搬到新系統，用 seam 與過渡架構讓兩者並存；他觀察到一次性整體重寫多半失敗，理由包括使用者等不了新功能、舊行為難以釐清。
- 本專案與 Fowler 前提的差異：功能凍結且不發版（使用者等新功能的壓力不存在）；舊行為已在 `docs/audit/` 盤點並經使用者逐項勾選。

## 已決定

- D1（使用者 2026-09-27）：**全新骨架＋搬運葉節點邏輯**。同一 repo 另建新 Flutter 專案，依新架構搭骨架；
  已被測試證明的底層邏輯（音源 API 呼叫、簽名與加密、解析器、`TrackKey` 格式）連同其測試搬入，不重寫。
  第一個里程碑是 tracer bullet：一個音源搜尋並播放，在 Android 與 Windows 跑通，之後逐層加能力。
  舊 App 原封不動保留，新 App 功能齊全後切換。「每個里程碑 App 都能運作」指新 App 已有的功能完整可用；
  重寫期間使用者日常使用舊版。

- D2（使用者 2026-09-27）：同一 repo 的 `main`，新專案放子目錄 `app/`（永久位置）；不開長期分支、不開新 repo。舊版緊急修正在 `main` 上改根目錄舊專案，照舊以 tag 發版，每次先問使用者。
- D3（由 A3 推出）：新 App 沿用舊 App 身分識別（Android `applicationId` `com.personal.fmp` 與簽名金鑰、Windows AppUserModelID、Inno Setup AppId），否則讀不到舊資料、舊版也無法直接升級。開發版另用身分（U9）。

## 驗收標準

- [ ] `design.md` 涵蓋目錄形狀、App 身分識別、舊版修正與發版、CI、切換條件與步驟，以及延後到定稿的項目。
- [ ] `docs/adr/0008-*.md` 依範本寫成，含被否決的選項與「如何確認」。
- [ ] `phase2-plan.md` 標記第 7 項（高層）完成。

## 範圍外（延後到第 7 項定稿）

- 里程碑拆分、第一個 tracer bullet 的音源與範圍、各里程碑驗收方式。
- CI 對新舊兩個專案的觸發策略與不穩測試的處理（第 8 項）。
