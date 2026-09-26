# Align specs with current code

## Goal

`.trellis/spec/` 是注入給 implement / check 子代理的規範；寫錯或寫成理想的規則會讓子代理照著寫出和 repo 不一致的程式碼。Trellis 接入存量專案的官方做法是「spec 寫現況、每條規則對得上真實實例、錯的模板比空的更糟」。這個 task 讓 spec 的每一句規範都對得上現在的程式碼。

## Background

- 逐句審查結果在 `research/spec-audit.md`：421 句中 G（有閘門）60、P（有實例）271、W（有反例或只有一例）71、I（無實例的理想 / 外來規則）15、S（與程式碼不符）4。
- 使用者已決定處理原則（2026-09-26）：S 直接修正；W 改寫成描述現況；I 刪除；A 類（程式本身的問題）這次不處理。

## Requirements

- **R1（S）** 修正 4 條與程式碼不符的敘述，依 `research/spec-audit.md` 的證據：
  - `data/persistence.md` repository provider 的例外清單補齊。
  - `shared/code-style.md` 不再宣稱 5 條 lint 都附理由。
  - `ui/index.md` 把 `context.mounted` 移出「未設閘門」清單（`use_build_context_synchronously` 在 flutter_lints 6）。
  - `ui/widgets.md` 圖片那句改成閘門實際管的範圍（loader 的尺寸級距 / `ImageTargetSizes`），**AGENTS.md § Boundaries 的 Images 那句同步修正**。
- **R2（W）** 71 條 W 改寫成描述現況：保留主流做法與範例，寫出已知例外或「多數 / 新程式碼」的限定，不再用 must / never / always 宣稱例外不存在。審查表標為「只有 1 例、建議保留」的 3 條照原樣保留。`testing/static-rules.md` 的「變異測試放在自己的 group」刪掉（引用的範本都不是這樣）。
- **R3（I）** 15 條 I 刪除。整節或整份 guide 因此變空時，一併刪掉並更新對應的 `index.md`。
- **R4** 只改 `.trellis/spec/` 與 AGENTS.md 那一句；不改 `lib/`、`test/` 的程式碼，也不為了讓規則成立去修程式。
- **R5** 每個 `index.md` 仍保有 Pre-Development Checklist 與 Quality Check 兩節，Guidelines 表與目錄內檔案一致。

## Acceptance Criteria

- [ ] `research/spec-audit.md` 的 4 條 S、71 條 W（扣除 3 條保留）、15 條 I 都已處理，對照表逐條可查。
- [ ] 改後的 spec 裡，沒有任何 must / never / always / only 類句子對應到審查表記錄的反例。
- [ ] spec 內所有反引號符號、路徑、連結、commit hash 仍存在（沿用 bootstrap 時的驗證腳本）。
- [ ] AGENTS.md 的 Images 那句與 `test/ui/static_rules/ui_consistency_static_rule_test.dart` 實際檢查的範圍一致。
- [ ] 沒有改動 `lib/`、`test/`、`tool/`。

## Out of Scope

- A 類程式問題（`AudioController` 等處 `state.error` 存 `e.toString()`、`playlistImportServiceProvider` 沒有 `onDispose`、`youtube_source.dart` 用子字串判斷平台、`netease_playlist_service.dart` 比對錯誤訊息子字串）：只記在審查表，這次不修、不開 issue。
- 為 W 規則補測試或 lint，讓它變成有閘門的規則。
- 審查表中 G 與 P 的句子。
