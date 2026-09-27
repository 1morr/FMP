# 執行計畫

本任務只產出設計與 ADR；程式在里程碑中實作。

- [x] 寫 `docs/adr/0012-network-layer-and-accounts.md`：design.md §1–§7；被否決的選項（每個 service 各自一個 dio、手動拼 Cookie header、在各 service 決定帶不帶憑證、TV 裝置碼 OAuth、只用貼上 cookie、刷新後用舊 options 重送、非 200 即清憑證、UI 與請求各讀一份登入狀態）；「如何確認」（媒體請求不帶 cookie 的契約測試、刷新後重送帶新憑證的測試、每音源「憑證無效」判定表的測試、登出與重設清憑證的測試）。併入 `CONTEXT.md` 的原則（媒體請求不帶憑證、解析串流才用憑證）。
- [x] `phase2-plan.md` 標記第 12 項完成；記下「YouTube WebView 登入是否可用」為加入 YouTube 登入的里程碑先實測項目。
- [x] 歸檔本任務。

驗證：Mermaid 以 mermaid-cli 渲染。
