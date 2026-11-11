# 08: 插件宿主跑通 bilibili 搜尋

**What to build:** 在佔位搜尋頁輸入關鍵字，宿主載入隨 App 打包的 bilibili 插件，呼叫它的搜尋能力，四個平台都列出 B 站的搜尋結果（標題、作者、時長）。這張票建起插件宿主的最小完整路徑：JS 引擎（票 03 的結論）、manifest（插件能力、網域）、宿主網路 API（只放行 manifest 宣告的網域）、插件錯誤代碼轉成錯誤分類；bilibili 插件用 TypeScript 寫、esbuild 打包，產物提交，閘門檢查產物是否最新。

讀：ADR 0038；brief §5.3、§13、§18.1（事實 F1、F2、F4）、票 03 寫進 brief 的結論；plan §1.1–§1.4、§3、〈待決〉P3；`GLOSSARY.md`〈宿主與插件〉；spec〈共同規則〉

**Blocked by:** 02、03、06

**Status:** ready-for-agent

- [ ] 插件宿主的介面用 `mattpocock-skills:codebase-design` 設計，只涵蓋搜尋與之後的解析串流；完整的插件能力清單在 M1 拆票時定（plan〈待決〉P3），這張票不先定，但 manifest 的插件能力宣告要能直接加新的能力；介面與取捨記到票的 Comments，影響架構的另寫 ADR（照〈擁有者確認〉）。
- [ ] manifest 宣告插件能力與網域；插件連未宣告的網域會被宿主拒絕，有測試。插件沒有檔案系統與 socket。
- [ ] 建立 fjs 引擎時只開白名單內的內建模組，不含 `fs`、`net`、`child_process`、`fetch` 等：fjs 自帶的 fetch 會繞過宿主的網域白名單（brief 事實 K11）。由測試強制，並在測試檔內做雙向變異驗證：多開一個非白名單模組會紅，改無關的設定不紅。（擁有者 2026-11-11 在票 03 確認加入）
- [ ] 宿主網路 API 經 dio，請求與錯誤都經過票 06 的 log 與遮蔽；B 站的風控碼與 HTTP 412、429 由插件回報成固定代碼，宿主轉成「限流」（事實 F2）。
- [ ] bilibili 插件的原始碼在 `app/plugins/bilibili/`（TypeScript），esbuild 打包的產物提交；`check.dart` 完整版檢查產物與原始碼一致，造一次不一致證明會紅。開發需要的 Node 版本寫進 plan §4。
- [ ] Dart 端沒有 bilibili 專屬的分支（依賴規則測試通過）。
- [ ] 單元測試用假的宿主網路回應測搜尋結果的轉換與錯誤代碼，零聯網。
- [ ] 四平台實跑：佔位搜尋頁搜一次，讀回畫面看到結果（匿名、每平台只搜一次）。
- [ ] `dart run tool/check.dart` 完整版綠燈。
