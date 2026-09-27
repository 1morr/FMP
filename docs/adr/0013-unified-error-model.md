# 0013 — 統一錯誤模型：一個 sealed 分類、音源內轉換、只在網路層重試

- 狀態：已採納
- 日期：2026-09-27
- 影響範圍：音源插件的錯誤對應、網路層攔截器、Riverpod 設定、所有錯誤呈現（Toast、曲目狀態、背景工作狀態）

## 背景

舊專案（`docs/audit/errors.md`、`docs/audit/playback.md` §3.6）：

- 自訂例外到畫面一律變成「發生錯誤」，同時 adapter 又把 `e.toString()` 原文丟上畫面；多源搜尋只要一源成功就隱藏其他失敗；
  507 個 catch 中約 70 個是空的。
- 播放遇限流只重試一次、不退避；電台的網路錯誤顯示成「未開播」；網易任何非 200 都當登入失效。
- 播放網路錯誤的重試訊號只有一個沒人用的入口接得住。

擁有者要求的分類：網路、限流、需登入／憑證過期、風控驗證、地區／版權限制、找不到、解析失敗、不支援；並要回答
音源特有錯誤在哪裡轉換、重試／退避／限流由誰負責、哪些自動恢復／提示／只記錄。

## 考慮過的選項

- **沿用多種各自定義的例外型別**：否決，這是舊版呈現混亂的來源。
- **Flutter 官方指南的 `Result<T>` 包裝**：否決。它為 `ChangeNotifier`＋Command 架構設計；本專案用 Riverpod，
  `AsyncValue` 已承擔同樣角色，再包一層只增加轉換。
- **Riverpod 自動重試與網路層重試並存**：否決。Riverpod 3 預設失敗重試 10 次（200ms→6.4s，riverpod.dev/docs/concepts2/retry），
  疊加網路層重試會讓次數相乘。
- **各 service 自己重試**：否決，策略分散且無法一致退避。
- **把伺服器或例外原文顯示給使用者**：否決，原文只進 log。
- **實作 B 站 geetest 驗證互動**：功能凍結期間不做，記入待辦。

## 決定

1. **分類**：一個 sealed `AppError`：
   `NetworkError`、`RateLimited`、`AuthRequired`、`CredentialInvalid`、`VerificationRequired`、
   `Unavailable`（附原因：地區、版權、會員、年齡、只有試聽）、`NotFound`、`ParseError`、`Unsupported`、`UnexpectedError`。
   YouTube 的「確認你不是機器人」歸 `VerificationRequired`（NewPipeExtractor 同樣獨立處理）。
   共同欄位：音源 id、`retryable`、`retryAfter`、給使用者的 i18n 訊息 key 與參數、`expected`（預期內的不當 bug）、
   原始 error 與 stackTrace（只進 log、經遮蔽）、對應的網路紀錄 id。
2. **轉換位置**：網路層把傳輸錯誤轉成 `NetworkError`；**每個音源在自己的目錄內**以對應表把狀態碼與錯誤碼轉成 `AppError`
   （含 ADR 0012 的「憑證無效」判定）；未知例外在音源邊界包成 `UnexpectedError`。音源邊界以上只看得到 `AppError`。
3. **傳遞**：音源與 service 丟出 `AppError`；Riverpod provider 以 `AsyncValue.error` 承接，UI 以 exhaustive `switch` 呈現；
   使用者動作由呼叫端捕捉並交給呈現層。所有被處理的錯誤經 log 門面寫入（ADR 0011）。禁止空 catch 與靜默吞錯。
4. **重試只有一層**：Riverpod 自動重試全域關閉。網路層依音源宣告的策略重試：只重試冪等請求；只重試 `NetworkError`、
   `RateLimited` 與音源標為可重試者；指數退避＋全抖動、尊重 `Retry-After`、次數上限預設 2。每個音源有併發上限與最小請求間隔，
   事先避開限流。憑證刷新後重送（ADR 0012）另計。播放層的恢復策略由播放核心的 ADR 定。
5. **呈現**：

   | 類別 | 自動處理 | 使用者看到 |
   |---|---|---|
   | 網路 | 網路層重試 | 動作失敗時提示；持續離線顯示離線狀態 |
   | 限流 | 退避重試 | 仍失敗才提示「{音源} 請求太頻繁」 |
   | 需登入 | — | 提示並附「登入」 |
   | 憑證無效 | 刷新一次 | 刷新失敗才提示一次需重新登入 |
   | 風控驗證 | — | 提示並建議登入、貼上 cookie 或稍後再試 |
   | 無法取得 | — | 曲目上標示原因；播放時跳過並提示 |
   | 找不到 | — | 曲目標示「已失效」；播放時跳過並提示 |
   | 解析失敗 | — | 提示「{音源} 回應格式改變，可能需要更新」 |
   | 不支援／預期外 | — | 通用訊息（視為 bug，可回報） |

   訊息一律來自 i18n；部分成功要標出失敗的音源或項目；背景工作不跳 toast，只在對應畫面顯示狀態；
   同類別＋同音源短時間內只提示一次；開發者模式下提示附「詳細」。

採用的慣例：Dart sealed class 窮舉；NewPipe `ErrorInfo`（可重試、可回報、使用者訊息）；AWS〈Exponential Backoff And Jitter〉；
Finamp 以「類別＋來源」去重；Riverpod 官方的全域 `retry` 設定。

## 後果

- 好的：使用者看到的訊息一致且可翻譯；每個音源的錯誤行為可用 fixture 測試；重試次數可預期；修正審計的 G4、G5、C5、C6、D5、D10。
- 壞的：每個音源要維護錯誤對應表；新增錯誤原因時要改 sealed 型別與所有 exhaustive `switch`（這正是想要的強制）。
- 之後要注意：Toast 的外觀與「詳細」內容由 Toast 的設計定；播放層跳過與停止的條件由播放核心的 ADR 定；
  B 站 geetest 驗證互動列在功能凍結待辦。

## 如何確認

- 契約測試：每個音源以錄下的錯誤回應 fixture，斷言對應到的 `AppError` 類別。
- 測試：`ProviderScope` 的 retry 為關閉；網路層只對冪等請求重試、尊重 `Retry-After`。
- lint：禁止空 catch；禁止在 UI 顯示 `toString()` 之類的原文（以只接受 i18n key 的呈現 API 在型別上擋住）。
