# 設計第 2 項：統一錯誤模型

## 目標

一個 sealed 錯誤分類貫穿全 App；回答擁有者的三個問題：音源特有錯誤在哪裡轉成統一型別、重試／退避／限流由誰負責、
哪些自動恢復／提示使用者／只記錄。

需求來源：parent `prd.md` 階段二第 2 項；`questions.md` G4、G5、C5、C6、D5、D10（按推薦）；ADR 0011、0012。

## 現況（證據）

- 自訂例外到畫面一律「發生錯誤」；adapter 把 `e.toString()` 原文丟上畫面；多源搜尋隱藏失敗；507 個 catch 中約 70 個空的（`docs/audit/errors.md` §1、§4）。
- 播放限流只重試一次、不退避；電台網路錯誤顯示成未開播；網易非 200 即清憑證（`errors.md` §2–§3）。
- 重試訊號只有沒人用的入口接得住（`docs/audit/playback.md` §3.6）。

## 研究結論（`research/error-model-patterns.md`、`research/retry-and-peers.md`）

- Flutter 官方指南：`sealed Result<T>` 取代 throw，逼呼叫端處理；設計給 `ChangeNotifier`＋Command。
- Riverpod 3：失敗的 provider **預設自動重試 10 次**（200ms→6.4s），可在 `ProviderScope(retry:)` 全域關閉（已以官方文件核對：riverpod.dev/docs/concepts2/retry）。與網路層重試疊加會相乘。
- NewPipe `ErrorInfo`：可重試、可回報、使用者訊息；同一錯誤依情境升級呈現。Finamp 以「類別＋來源」去重。
- 退避：指數退避＋全抖動、尊重 `Retry-After`；只重試冪等請求；併發用 `pool`。
- 風控：B 站 -352 走 geetest 驗證（PiliPlus）；YouTube 機器人驗證在 NewPipeExtractor 是獨立例外；地區限制各自是專屬例外。

## 需求

- R1 單一 sealed `AppError`：擁有者的 8 類（網路、限流、需登入、憑證無效、風控驗證、無法取得〔地區／版權／會員／年齡／試聽〕、找不到、解析失敗）加上「不支援」與「預期外」；共同欄位見 design.md §1。
- R2 音源特有錯誤在該音源目錄內的對應表轉換；音源邊界以上只看 `AppError`。
- R3 Riverpod 自動重試全域關閉；重試只在網路層，策略由音源宣告；只重試冪等請求；退避加抖動、尊重 `Retry-After`；每音源併發上限與最小間隔。
- R4 使用者看到的訊息一律來自 i18n；部分成功要標出失敗部分；背景工作不跳 toast；同類同源錯誤去重。
- R5 禁止空 catch 與靜默吞錯（lint）。

## 待確認（見摘要）

- design.md §5「使用者看到什麼」表。
