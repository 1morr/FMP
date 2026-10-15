# M4 PR 2 導覽重排、首頁、音樂庫、本機歌單

> M4 的 PR 2（`../10-15-m4-library-sync/implement.md` § 2）。設計在 `../10-15-m4-library-sync/design.md` §10.1–§10.3、§10.5；決定在 ADR 0033 §決定 5、6、8，ADR 0024（導覽、斷點、焦點三區、快捷鍵）、ADR 0031 §決定 3 的 M4 更正、ADR 0030 §決定 12 的 M4 補充。擁有者決定 2：導覽「首頁｜搜尋｜音樂庫｜電台｜設定」，歷史移進音樂庫。

## 做什麼

- **導覽**：`ShellDestination { home, search, library, radio, settings }`；compact、medium／expanded、large 三種導覽元件同一組、同順序；App 開在首頁。每個目的地一個巢狀 `Navigator`（放在 `IndexedStack` 裡），內頁（歷史，之後的歌單詳情、探索）在內容區內開，導覽與播放列留著。系統返回鍵與 Esc（不在輸入框時）先 pop 目前目的地的 `Navigator`，到根才交給原本的行為；再點一次目前的導覽項回到該目的地的根。焦點三區與快捷鍵不變（Ctrl+F 先切到搜尋再聚焦）。
- **首頁**（本 PR 只有）：最近播放區塊（`play_history` 最新 20 筆、不去重，點一下臨時播放，「查看全部」在首頁的巢狀導覽裡開歷史頁）；沒有任何已啟用、具 `search` 能力的插件時顯示 `plugin_onboarding` 的同一個引導元件；全部沒有內容時顯示說明（「搜尋並播放歌曲，或匯入歌單」）。我的歌單、電台區塊在 PR 4，排行在 PR 21。
- **音樂庫**：頂端「歷史」一列（在音樂庫的巢狀導覽裡開歷史頁）；歌單卡（封面、名稱、首數、本機標記），compact 是清單、expanded 以上是格狀；拖曳排序後整批寫 `sort_order`；工具列「新增」（「匯入」在 PR 8b）；空的時候說明怎麼建立。
- **歌單卡選單**（本機歌單）：全部加入佇列、隨機加入（打亂後加入佇列）、編輯、刪除（確認框）。超過 10,000 首的加入整批拒絕（`QueueFull`，ADR 0018 §決定 4）。
- **建立與編輯對話框**：名稱（必填）、描述、封面（預設第一首的封面；「自訂」以圖片網址，「使用預設」清回）。
- `lib/library/playlist_service.dart`：只有本機歌單的部分（建立、編輯、刪除、排序、加入佇列、隨機加入）。
- 字串三語言（slang）；新頁面加進 guideline 測試；離線照常顯示本機資料。
- 文件：`app/AGENTS.md` § 介面（導覽、巢狀導覽、首頁、音樂庫）、`.trellis/spec/app/ui/index.md`。

## 驗收

- 測試：五個導覽項 × 三種寬度（取代 ADR 0031 的四項測試）；App 開在首頁；巢狀導覽的返回鍵與 Esc、再點導覽項回根；快捷鍵群組（Ctrl+F 切到搜尋並聚焦、F6 三區）；首頁引導的出現與消失；首頁最近播放與「查看全部」；音樂庫的建立、編輯、排序、刪除；「全部加入佇列」超過上限拒絕；guideline；`toast_layering_test.dart` 加巢狀導覽裡的頁。
- `dart format`、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過。
- 實機（重播，dev flavor＋`fmp-test`）：Android 模擬器：建兩張歌單、改名、排序、刪一張；從首頁「查看全部」進歷史再返回；清掉 dev 資料後首頁出現引導。Windows：large 寬度的導覽與巢狀導覽、Esc 返回；`toast_layering_test.dart` 兩平台。
