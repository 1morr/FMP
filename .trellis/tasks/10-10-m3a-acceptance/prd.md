# M3a 驗收

> 父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`。驗收內容照父任務 `implement.md`「## M3a 驗收」；格式照 M2 的 `archive/2026-10/10-01-m2-full-playback/research/m2-acceptance.md` 與 `m2-adr-tests.md`。M3a 的實作 PR（FMP #220–#230、fmp-plugins #4–#8）都已合併。本檔只列做什麼與驗收。

## 做什麼

1. **ADR 的測試對照**：父任務 `implement.md`「### ADR 的測試」表逐列找到測試（檔案與測試名）或 PR 描述，寫進父任務 `research/m3-adr-tests.md` 的 M3a 段（格式照 `m2-adr-tests.md`：PR 對照表、方法、對照表、找不到的列進「需要主對話決定」）。
2. **`app/AGENTS.md` 審查**：網路、插件、帳號、資料層段落與實際程式一致；每條規則有閘門（測試名對得上），或標明「沒有閘門，review 時看」。opus 審查一次，改正文件（不改程式；需要改程式的列出來）。
3. **兩平台端到端**（Android 模擬器與 Windows，dev flavor，真實）：照父任務 `implement.md` 的 8 個步驟；擁有者掃 QR、輸入 Google 密碼。證據寫進父任務 `research/m3a-acceptance.md`（平台、模式、真實請求清單；截圖不含帳號資訊）。
4. **`milestones.md`** 的 M3a 狀態與勾選；父任務 `implement.md` 的交接段更新。

## 不做

- M3b 的任何東西（PR 11 起）。
- 程式改動：驗收中發現的缺陷另開 issue 或 PR，除非是擋驗收的小修。

## 驗收

- [x] `research/m3-adr-tests.md` 的 M3a 段：上表每一列都有測試或 PR 描述的對應，或在「需要主對話決定」說明。
- [x] `app/AGENTS.md` 的審查結果寫進 PR 描述；文件與程式一致。
- [x] `research/m3a-acceptance.md`：兩平台 8 個步驟逐條的結果與真實請求清單。
- [x] `milestones.md` 的 M3a 標為完成。
