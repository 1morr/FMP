# 12: M0 驗收與封存

**What to build:** 把 spec〈驗收〉逐條對到證據，跑完里程碑的 code-review 與乾淨 checkout 上的完整閘門，請擁有者在四個平台各試一次，最後封存 M0：session 紀錄與偏差搬到 `docs/archive/M0.md`，交棒給下一個里程碑。

讀：spec〈驗收〉〈共同規則〉；`docs/progress.md` 開頭的封存規則；plan §4、§5.3；票 01–11 的 `## Comments`

**Blocked by:** 01–11 全部

**Status:** ready-for-agent

做法：

1. **里程碑 code-review**：`/code-review ca551939`（M0 開工的 commit）。Spec 軸讀 spec 與票 01–11，Standards 軸讀 `AGENTS.md`。小問題當場修。
2. **逐條對照**：spec〈驗收〉每一條對到一條測試、一次閘門輸出或一次實跑紀錄，做成表記在 Comments；缺的補上。
3. **乾淨 checkout**：`git worktree add --detach` 到暫存目錄，從零安裝後跑 `dart run tool/check.dart` 完整版。
4. **Comments 歸屬**：票 01–11 的 Comments 與這一票 code-review 沒處理的發現，逐條分成「修掉」「延後」「不做」。延後的寫進 plan 對應里程碑那一節（還沒開工的是 plan §5.x）；不做的寫理由。
5. **擁有者試用**：需要擁有者在場，開工時先約時間。擁有者在四個平台各搜一次、播一首。
6. **舊版 CI**：push main 之後確認 `ci.yml` 綠燈（push 照 `AGENTS.md` 流程）。
7. **封存**（同一個 commit）：M0 的 session 紀錄與偏差整段搬到 `docs/archive/M0.md`，逐列比對不遺失。里程碑表 M0 的備註換成封存檔的連結，加上 M1 列；plan 開頭的狀態行更新。spec 與票留在原處。progress.md 加一列這個 session 的紀錄：D 已定稿時，下一步寫 `/to-tickets docs/plan.md 拆 M1 的票`；D 還沒定稿時，寫 `等使用者：D 設計稿定稿`（plan §5.2，M1 開工前要完成）。

- [ ] 里程碑 code-review 跑完，小問題已修。
- [ ] spec〈驗收〉每一條在 Comments 有對應的證據；缺的已補。
- [ ] 乾淨 checkout 上 `check.dart` 完整版綠燈，貼輸出最後幾行。
- [ ] 票 01–11 與本票沒處理的發現逐條歸屬；延後的已寫進 plan。
- [ ] 擁有者在四個平台試用過，結果記在 Comments。
- [ ] main 上的 `ci.yml` 綠燈，貼 run 連結。
- [ ] `docs/archive/M0.md` 有 M0 全部的 session 紀錄與偏差，progress.md 只留進行中的里程碑；里程碑表與 plan 已更新。
