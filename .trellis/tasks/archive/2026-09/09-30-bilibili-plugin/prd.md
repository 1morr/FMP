# fmp-plugins 與 B 站插件（M1 PR 9c）

父任務：`../09-28-m1-skeleton-tracer`（implement「9.」的 9c；擁有者決定 5、6、8）。前兩個 PR：
- 9a（#183）：執行環境，封存在 `../archive/2026-09/09-30-js-runtime/`；
- 9b（#184）：契約執行器，封存在 `../archive/2026-09/09-30-plugin-contract/`。

依據：
- ADR 0014 §決定 6：插件庫；
- ADR 0015 §決定 4–6 與兩則 2026-09-30 更正；
- ADR 0027 §決定 2：真實連線的條件；
- 父任務 design §4。

## 做什麼

1. **建立公開 repo `1morr/fmp-plugins`**（擁有者決定 5），本機 clone 在與 FMP 同層的 `fmp-plugins/`。
   - 第一個 commit 直接進 `main`，內容：
     - `README.md`：繁中，寫明開發中、與 FMP 的關係、跑契約測試的指令；
     - `LICENSE`：MIT，與 FMP 相同；
     - `.gitattributes`、`.gitignore`。
   - B 站插件走該 repo 的 PR 合併，照 design §4。
   - CI、`index.json`、插件頁都留在 M3。
2. **`bilibili/` 插件**，只有 `search` 與 `resolveStream` 兩個能力。
   - 形式：單一安裝檔 `bilibili.js`，開頭帶 `==FMP Plugin==` manifest（決定 6）。
   - 行為以舊專案 `lib/data/sources/bilibili_source.dart`（search、getAudioStream 及相關私有方法）為規格，用 JS 重寫（ADR 0008 檔頭補充）。重點：
     - WBI 簽名，md5 來自宿主的 `crypto`；
     - 匿名 `buvid` 存在插件自己的 `storage`；
     - `Referer` 與 `User-Agent` 的要求；
     - 優先取 DASH 音訊；
     - 錯誤碼對到結構化錯誤。
   - 串流的 headers 只帶播放需要的（Referer、User-Agent），不帶 Cookie（ADR 0012）。
   - `allowedHosts` 只列實際用到的網域。
   - 要登入才有的東西（高音質等）不在 M1。
3. **`checks.json`**：每能力一條案例。
   - `search` 用常見關鍵字；
   - `resolveStream` 用一支長期存在、公開、無地區限制的影片。
4. **錄製 fixture**（決定 8、ADR 0027 §決定 2）：
   - 用 9b 的錄製模式對 B 站真實連線錄一次，只做最少請求。
   - 寫檔前經過遮蔽。
   - 錄完用重播模式跑契約測試，要全綠。
   - 逐檔人工確認沒有 cookie、token、buvid 或簽名的原值，也沒有個人資訊。
   - 回報「模式：真實」與做了哪些請求。
5. **FMP 端**：只有文件與任務紀錄。
   - M1 交接段寫明 fmp-plugins 的位置、B 站插件的 commit，以及怎麼在 dev App 裝它（開發入口）。
   - 若 9b 的執行器接 B 站時需要修正，另開 FMP 的修正，不混在這裡。
6. **PR 8 的後續**：觀察伺服器回不合法的 `Set-Cookie` 時，請求會不會變成 `UnexpectedError`，記下結論。

## 驗收

- [ ] `1morr/fmp-plugins` 是公開 repo，`main` 上有 README 與 LICENSE。B 站插件經該 repo 的 PR 合併。
- [ ] 在 FMP 的 `app/` 內執行 `FMP_PLUGIN_DIR=<fmp-plugins>/bilibili flutter test test/plugins/contract/contract_test.dart`，重播全綠。
- [ ] fixture 經人工逐檔檢查，沒有憑證原值。
- [ ] Windows dev App 用開發入口裝上 B 站插件，身分頁列出它。真正的搜尋與播放在 PR 10、12 驗。
- [ ] 真實連線的請求次數與內容寫進回報。
