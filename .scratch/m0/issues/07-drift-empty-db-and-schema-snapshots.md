# 07: drift 空庫與 schema 快照

**What to build:** 新版的 drift 資料庫在四個平台都開得起來（還沒有業務資料表），並建立往後每次改 schema 都要走的流程：產生 schema 快照、寫升級測試。之後加資料表的票照這個流程走。

讀：plan §1.2、§1.3、§1.4、§3；brief §12；spec〈共同規則〉

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] 只有 `data/` import drift（依賴規則測試已涵蓋）；資料庫檔案路徑由 `platform/` 提供。
- [ ] schema 版本 1 的快照已提交；產生快照與升級測試的指令寫進 `AGENTS.md` 或 `check.dart`，快照跟程式不一致時閘門會紅（造一次不一致證明會紅）。
- [ ] 有一條升級測試的範本，下一個 schema 版本照抄即可。
- [ ] 四平台實跑，啟動時開庫成功（log 或畫面為證）。
- [ ] `dart run tool/check.dart` 完整版綠燈。
