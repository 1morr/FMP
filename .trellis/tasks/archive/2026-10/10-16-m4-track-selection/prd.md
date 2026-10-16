# M4 PR 5 多選

> M4 的 PR 5（`../10-15-m4-library-sync/implement.md` § 5）。設計在 `../10-15-m4-library-sync/design.md` §10.7；決定在 ADR 0033（多選）、ADR 0024（快捷鍵、焦點三區）、ADR 0018 §決定 4（佇列上限、Mix 禁止規則）。另有 PR 2、3 留下的兩件（implement.md「留下的後續」）。

## 做什麼

- `lib/ui/tracks/track_selection.dart`（共用）：長按或「⋯」選單的「選取」進入；頂端換成選取列（已選 n 首、全選、取消、動作）；Esc 或返回離開；鍵盤 Ctrl+A 全選（只在選取模式內、輸入框裡不作用）、Shift＋點選範圍選取（桌面）。
- 動作：加入佇列（超過 10,000 首整批拒絕；Mix 中照 M3 的禁止規則）、加入歌單（PR 3 的對話框）、從本機歌單移除（只在本機歌單詳情）。遠端的兩個動作在 PR 14。
- 用在：歌單詳情（群組標題不是項目，依 `PlaylistEntryRow` 判斷）、搜尋（影片列與分 P 列；多分 P 影片的取法照「加入歌單…」）、歷史。佇列不用。探索在 PR 21。
- PR 2 留下：expanded 以上的音樂庫格狀拖曳沒有螢幕閱讀器／鍵盤的替代操作——決定要不要加（例如卡片的 semantics custom actions「上移／下移」），做或不做都寫理由。
- PR 3 留下：歌單詳情裡單獨的分 P 列在手機寬度會截掉「· P2…」——決定要不要兩行。
- 字串三語言；guideline；文件：`app/AGENTS.md` § 介面、`.trellis/spec/app/ui/index.md`。

## 驗收

- 測試：三頁的進入與離開（長按、選單、Esc、返回鍵）、動作的結果（加入佇列、加入歌單、從本機歌單移除只動選到的項目）、上限與 Mix 規則、快捷鍵（Ctrl+A 只在選取模式內、輸入框裡不作用、Shift 範圍）、guideline。
- `dart format`、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過。
- 實機（主對話做）：重播（Android）：搜尋結果多選三首加入歌單；歷史多選加入佇列；詳情多選移除。Windows：Shift 範圍選取、Ctrl+A（打字前關輸入法，見 verify-on-device 的 windows.md）。
