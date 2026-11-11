# 05b: 實驗：玻璃三級的四平台可行性

**What to build:** 決定設計稿的玻璃元件在 Flutter 怎麼做，讓 M1 拆票時知道每個平台做得到哪一級。設計稿把玻璃分成三級（`docs/design/DESIGN.md` §1.4：折射、standard、minimal），和事實 K10 的定義不同；brief §17 的退路（只用 `BackdropFilter`）做不出折射級。這張票重驗 K10、在四平台實測候選做法，結論給擁有者確認後寫回 brief、plan 與 `DESIGN.md`。2026-11-11 D 定稿後補開（plan〈待決〉P5）。

讀：brief §2.3、§11、§15、§17〈玻璃的 Flutter 實作〉、事實 K10；`docs/design/DESIGN.md` §1（材質）、§5（外殼）、〈稿內不一致與實作注意〉第 1 項；plan §1.4、§2、〈待決〉P5；spec〈共同規則〉的實驗規則

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 實驗程式在 `scripts/experiments/` 底下，可重跑，附怎麼跑的說明；換版本時能重量。
- [ ] 重驗事實 K10：`cupertino_ui` 是否已在 pub 發佈 Liquid Glass、社群玻璃套件的現況、四個平台各用哪個 renderer；更新 K10 的寫法、出處與查證日期。
- [ ] 候選至少包括：已發佈的官方或社群玻璃套件、用核心 Flutter 的 `BackdropFilter` 自己做。每個候選在四平台實測做得到設計稿的哪一級（折射、模糊加飽和、實心退路），結果做成表，含版本號與平台；以讀回的截圖為準。
- [ ] 玻璃元件浮在 1000 首以上的列表上方捲動時，用 profile build 量幀時間，對照 brief §15「長列表捲動不掉幀」；量出哪一級可以留在捲動中的列表上方。
- [ ] 查四個平台的「降低透明度」系統設定讀不讀得到（`DESIGN.md` §1.4 的 minimal 退路）。
- [ ] 結論草稿（用哪個做法、每個平台的最高級、捲動時怎麼降級、已知限制）先給擁有者確認；確認後寫進 brief §18（事實）、brief §17 移除〈玻璃的 Flutter 實作〉並把決定寫進 §11、plan §1.4 與〈待決〉P5 刪除、`DESIGN.md` §1.4、〈9〉與〈稿內不一致與實作注意〉的對應條目改成實測結果。
- [ ] 如果沒有一個候選在 iOS、Android 做得出折射級：停下來回報，不自己改設計稿。
