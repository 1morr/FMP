# 20: M1 驗收與封存

Status: ready-for-agent
Blocked by: 01–19、05b、05c、05d、06b、08b
讀: `docs/agents/milestone.md`〈驗收票〉；spec〈驗收〉；`python3 scripts/ticket_notes.py m1`

## What to build

照 `docs/agents/milestone.md`〈驗收票〉做：code-review、spec〈驗收〉的 Agent 驗逐條對到證據、各票沒處理的發現歸位、擁有者試用、封存到 `docs/archive/M1.md` 並把各票的 `變更：` 組進 `CHANGELOG.md`。擁有者試用要在場，開工時先約時間。

## 驗收

- [ ] 從 M1 開工的 commit 起跑過 `mattpocock-skills:code-review`，發現都歸了位。
- [ ] spec〈驗收〉的 Agent 驗每一條都有證據；乾淨的 checkout 跑完整閘門綠燈。
- [ ] Windows 補驗（2026-11-18 擁有者定暫時跳過所有 Windows，`docs/decisions.md`）：擁有者說 winpc 恢復後，完整閘門含 Windows 綠，並補跑跳過期間各票的 Windows 實跑：票 10 的 `persist_run`／`restore_run`、票 11 的重新解析，以及之後各票 Comments 裡記「Windows 跳過」的項目（`python3 scripts/ticket_notes.py m1` 搜「Windows 跳過」）。
- [ ] 擁有者照 spec〈使用者試〉試過並說可以了（或委託代測，記在 `docs/decisions.md`）。
- [ ] `docs/archive/M1.md` 建好，`docs_moved_lines.py` 印「遺失 0」，`CHANGELOG.md` 已更新；roadmap、progress.md 照〈驗收票〉改好。

## Comments
