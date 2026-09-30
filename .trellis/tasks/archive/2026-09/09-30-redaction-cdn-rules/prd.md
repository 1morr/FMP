# 遮蔽：補 hdnts／buvid 並合併 CDN 規則

父任務：`../09-28-m1-skeleton-tracer`（「9c 留下的後續」前兩項）。依據：ADR 0011（遮蔽函式）；9c 的錄製證據在 `../archive/2026-09/09-30-bilibili-plugin/research/notes.md`。

## 問題（都有失效條件）

1. 內建的 B 站 CDN 規則（`app/lib/core/redaction/redaction_lists.dart` 的 `_bilibiliSigned`）不含 `buvid` 與 `hdnts`。
   - 9c 第一次錄製時，串流網址帶著 `buvid=<匿名裝置 id>`，Akamai 鏡像的網址帶著 `hdnts=exp=…~hmac=…`。
   - 官方插件靠 manifest 的 `keyNames` 補上了；沒有補的插件，串流網址一進 log 或 fixture 就是原值。
2. `Redactor._redactMediaUrl` 只套用第一個符合 host 的 `MediaCdn`。內建規則排在前面，所以插件以 `addRules(mediaCdns:)` 替同一個 host 追加的參數不會生效。

## 做什麼

- `_bilibiliSigned` 加上 `buvid`、`hdnts`。
- `_redactMediaUrl` 合併所有符合的規則：參數取聯集，`signedPath` 任一條為真就套用。
- 測試，修正前都會紅：
  - Akamai 網址的 `hdnts` 與 `buvid` 被拿掉；
  - 插件規則與內建規則同時生效；
  - 任一條規則的 `signedPath` 都會生效。
- `1morr/fmp-plugins` 的 `bilibili/fixtures/resolveStream/003.json` 在內建規則變嚴格後，過不了「再遮蔽一次不變」的掃描。
  - 用同樣的轉換拿掉 CDN 網址裡的 `hdnts=***`、`buvid=***`，只動那 24 個網址，不重錄。
  - 結果和遮蔽函式的輸出相同，由掃描本身驗證。
  - 該 repo 另開 PR 合併。

## 驗收

- [ ] `app/` 驗證清單全過：format、analyze、`flutter test`、哨兵。
- [ ] 新測試在修正前會紅。
- [ ] B 站插件在 fmp-plugins 修改後的 fixture 上重播全綠。
