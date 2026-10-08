# PR 2 實機紀錄

日期：2026-10-08。模式：**真實，匿名**。插件：`fmp-plugins/netease/netease.js`，以 `--fmp-dev-plugin` 安裝。

## `X-Real-IP`

- 實作時以 Node 各發 1 次（不帶）：搜尋（`/api/cloudsearch/pc`）200 有結果；取流（eapi，歌曲 139774）200 有網址。
- 上機時歌曲 `5257138`、`400876427` 的取流回 `Unavailable(copyright)`。以 Node 對 `400876427` 各發 1 次：不帶 → `data[0].code` 404、`fee` 0、`flag` 257、沒有網址；帶 `118.88.88.88` → 320 kbps mp3。網路出口在大陸以外時，有地區限制的歌要靠它。插件改為只在取流送；搜尋不送（`test/search.test.js`、`test/resolve.test.js` 守）。
- 錄 fixture：搜尋、取流各 1（第一次不帶、改完重錄一次帶）。

## Android（`Medium_Phone`，API 37）

- 搜尋「Jay Chou」2 次（改插件前後各 1）：`cloudsearch/pc` 200，20 筆。
- 取流：改前 2 次（都 `copyright`）；改後 `400876427` → `mp3` 320 kbps（https 的 m701 CDN），請求到出聲 3151 ms。
- 試聽：搜尋「Taylor Swift」1 次，`19292984`（`fee` 1）取流回 `Unavailable(membership)`；Node 帶 header 再查 1 次：`code` -110、沒有網址、沒有 `freeTrialInfo`。匿名拿不到試聽片段，延到登入後（M3a 驗收）。另以 Node 搜尋 1 次找 VIP 歌。

## Windows（dev debug，media_kit）

- 搜尋「Jay Chou」1 次；`5257138` 取流 1 次 → `mp3` 128 kbps（本機設定為低音質），請求到出聲 616 ms。
