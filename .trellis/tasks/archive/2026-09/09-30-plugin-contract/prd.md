# 插件契約執行器與 fixture 重播（M1 PR 9b）

父任務：`../09-28-m1-skeleton-tracer`（implement「9.」的 9b）。前一個 PR：9a（#183，封存在 `../archive/2026-09/09-30-js-runtime/`）。

依據：

- ADR 0015 §決定 4（檢查案例一份四用）、§5（fixture）、§6（契約執行器）、§7（App 內插件開發工具）；
- ADR 0014 §如何確認（契約測試）；
- ADR 0011（遮蔽）、0012（媒體請求不帶憑證、只連 manifest 網域）、0013（錯誤對到 `AppError` 類別）；
- ADR 0027 §決定 2（真實連線的條件）。

## 做什麼

1. **fixture 的錄製與重播**：放在 `SourceHttpClient` 最底層的 dio `HttpClientAdapter`，接 PR 8 的 `createAdapter` 注入點。
   - 一次請求與回應存成一個 JSON 檔，內容是 `meta`、`request`、`response`。欄位形狀參考 WireMock 的 stub mapping。
   - 錄製：寫檔前一律經正式的遮蔽函式（ADR 0011）。
   - 重播：
     - 比對 method、排序後的 URL、請求順序；
     - 被遮蔽的欄位不參與比對；
     - 比對不到就讓測試失敗，不發真實請求。
   - 錯誤案例可手改 fixture，並在 `meta` 標記。
2. **`checks.json`**：每插件每能力最多一條檢查案例，內容是能力名、輸入、期望。
   - 期望分兩種：成功時的形狀條件，例如至少 N 筆、欄位非空；錯誤時的 `AppError` 類別。
   - 格式寫進 `fmp-plugin.d.ts` 的旁邊或同一份文件，給插件作者看。
3. **契約執行器**：原定放在 `app/packages/plugin_contract/`，實作時改放 `app/test/plugins/contract/`（理由見 `research/notes.md`，ADR 0015 §決定 6 已補更正）；用重播跑一個插件目錄裡的每個案例，並斷言：
   - 能力與匯出一致；
   - DTO 驗證通過；
   - 案例的期望；
   - 錯誤對到 `AppError` 類別；
   - 媒體請求不帶憑證（M1 沒有媒體 client，就對 `resolveStream` 回傳的 headers 做檢查，寫明）；
   - 只連 manifest 宣告的網域；
   - 插件的 log 經過遮蔽。

   執行方式：
   - QuickJS 要在 `flutter test` 裡跑（9a 的結論），所以執行器以 `flutter test` 為入口，插件目錄用參數或環境變數傳入；
   - `1morr/fmp-plugins` 的 CI 以固定的 FMP 版本執行；
   - 指令寫進 `app/AGENTS.md` 與 `.trellis/spec/app/plugins/index.md`。
4. **`app/` 內的案例**：
   - 9a 的測試插件 `fmp-test` 補上 `checks.json`。
   - 另外加一個會發 HTTP 請求的測試插件，網域用 `*.test`，fixture 手寫，讓重播、網域、遮蔽的斷言真的被執行到。
   - 執行器自己的測試要有雙向變異驗證：造出違規讓它失敗，例如連到清單外的網域、log 沒遮蔽、期望不符、fixture 比對不到；再改一個無關處證明它不會失敗。
5. **fixture 掃描**：`app/` 內所有 fixture 都不得有未遮蔽的憑證（ADR 0015 §如何確認）。
   - 用遮蔽函式重跑一次，結果要和原檔相同；
   - 另外比對常見憑證欄位。
   - 要有雙向變異驗證。
6. **CI**：`app` job 加上契約執行器的步驟，或確認它已包含在 `flutter test` 內，二擇一並寫明。
7. **錄製模式**（擁有者 2026-09-30 決定，見父任務 prd 決定 8）：
   - 執行器加錄製模式：真實連線跑同一份 `checks.json`，經遮蔽後寫進插件目錄的 `fixtures/`。
   - 打上 `live` tag，只有明確帶 `--run-skipped --tags live` 才執行，CI 不跑。
   - 只給不需要登入的案例用；需要登入的錄製留在 App 內（M3）。
   - 本 PR 不對真實音源執行錄製，錄製模式的測試用本機假伺服器或假 adapter。實際錄 B 站在 9c。
   - ADR 0015 §決定 7 補一句更正：命令列可以做免登入的錄製。

## 驗收

- [ ] `app/` 驗證清單全過：
  - format；
  - build_runner 後沒有實質變動；
  - `dart analyze --fatal-infos`、`flutter analyze`；
  - `flutter test`；
  - 哨兵。
- [ ] 執行器對兩個測試插件都通過。每種違規都有會紅的測試，也有證明不會誤紅的測試。
- [ ] fixture 掃描有雙向變異驗證。
- [ ] CI 的 `app` job 綠，而且跑到契約執行器。
- [ ] 錄製模式：對本機假伺服器錄出的 fixture 經過遮蔽，再用重播模式跑同一份案例會通過；不帶 `--tags live` 時不執行。
- [ ] 用執行器跑外部插件目錄的指令寫進文件，並實際跑過一次：把測試插件複製到 `app/` 外的暫存目錄。
