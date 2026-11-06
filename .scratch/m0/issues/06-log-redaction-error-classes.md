# 06: log 門面、遮蔽與錯誤分類

**What to build:** 新版的單一 log 門面，在四個平台都寫出 log 檔並輪替；單一遮蔽函式，cookie、token、簽名網址等敏感值一律變成 `***`；錯誤分類的 sealed 骨架，之後插件與播放的錯誤都轉成這些類別。這張票不做 Toast 與匯出診斷。

讀：brief §13、§14；plan §1.2、§1.3、§3；`AGENTS.md`〈公開 repo〉；spec〈共同規則〉

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] log 門面寫檔並輪替（2MB × 3），release 版保留 info 級；log 檔路徑由 `platform/` 提供，有測試。
- [ ] 遮蔽函式涵蓋 cookie、Authorization 類 header、token、帶簽名參數的網址；log 寫入前一律經過它。單元測試列出每一類輸入與遮蔽後的樣子，也證明不該遮的內容不被改。
- [ ] 錯誤分類照 brief §13：網路、限流、需登入、憑證失效、需驗證、不可用（地區、版權、需會員、只有試聽）、找不到、解析失敗、不支援。
- [ ] 四平台實跑，啟動後在該平台的 log 路徑讀到 log 檔。
- [ ] `dart run tool/check.dart` 完整版綠燈。
