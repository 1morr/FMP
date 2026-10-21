# importPlaylist 的截斷旗標與 Spotify、QQ 官方 id

## 目標

M4 PR 17、18 的 FMP 端（上層 `implement.md` § 17、18，design §4.8，ADR 0032 §決定 2、8、9）。

PR 17 開頭的實測（2026-10-21，匿名）：Spotify embed 頁的 `__NEXT_DATA__` 還在，但每張歌單最多只給前 100 首、沒有總數欄位；用頁面裡的匿名 token 呼叫 `api.spotify.com` 回 429（`QUOTA_EXCEEDED`）。擁有者決定（2026-10-21）：**匯入前 100 首並提示**——契約加一個選填欄位，讓插件說「我能讀的已經讀完，但遠端歌單可能更長」。

## 需求

- **契約**（ADR 0032 §決定 9 的同步點，同一個 PR 全改）：
  - `PlaylistPage` 加選填 `truncated?: boolean`：只能出現在最後一頁（`cursor` 為空）；`true`＝插件已讀完它讀得到的，遠端歌單可能還有更多（例如 Spotify embed 頁只給前 100 首）。
  - `app/lib/plugins/types/fmp-plugin.d.ts` 的註解寫清楚語意與「只在最後一頁」。
  - `app/lib/plugins/source_dto.dart`：`PlaylistPage.truncated`（`bool`，預設 `false`）、`sourceDtoShapes` 加 `'truncated': false`（選填）；`truncated == true` 而 `cursor` 不為空時拒收（照該檔現有的驗證錯誤寫法）。
  - `FmpChecks` 與 `checkShapes` 若列舉了 `PlaylistPage` 的欄位就跟著加；沒有就不動。
- **刷新**（`app/lib/library/playlist_refresher.dart`）：最後一頁 `truncated` 視為不完整——只新增與更新、不移除不重排、標「上次刷新：部分完成」（ADR 0019 §決定 2）。目前沒有能播的插件會回 `truncated`，這是讓語意在兩條路一致。
- **官方 id**：`app/packages/fmp_lints/lib/src/rules/source_id_literal.dart` 的 `officialPluginIds` 加 `spotify`、`qqmusic`；lint 測試加一個 `spotify` 或 `qqmusic` 字面量會被抓的案例（雙向：無關的字串不被抓的案例若已有就沿用）。
- **文件**：
  - ADR 0032 §決定 2 末尾加「補充（2026-10-21，M4 PR 17）」一段：`truncated` 的語意、只在最後一頁、刷新視為不完整、外部匯入（匯入預覽，PR 19）照常進匹配並在預覽頁提示「來源只提供了部分曲目」；起因是 Spotify embed 頁的 100 首上限（擁有者 2026-10-21 決定）。
  - design.md §4.8 的 Spotify 那條補實測結果與 `truncated`；§17 第 18 條後加一句：`truncated` 不算讀取失敗，外部匯入照常進匹配並提示。
  - 上層 `implement.md` § 17 的 FMP 那項打勾並註明在本 PR；§ 18 的 FMP 那項打勾；§ 19 的測試清單加「最後一頁 `truncated` 時照常匹配並顯示提示」。
  - `.trellis/spec/app/plugins/index.md` 若有 `PlaylistPage` 欄位的說明就補。

## 驗收

- 測試：DTO（`truncated` 接受、缺省為 `false`、帶非空 `cursor` 拒收、型別錯拒收）；刷新（最後一頁 `truncated` → 部分完成、不移除、不重排）；lint 測試；`dart run tool/lint_sentinel.dart`。
- `dart format --output=none --set-exit-if-changed lib test integration_test tool`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過（Windows 上兩個 `trackDetail` CRLF 失敗是既有的）。

## 不做

- 匯入預覽頁的提示 UI（PR 19）。
- 插件本身（`fmp-plugins` 的 PR）。
