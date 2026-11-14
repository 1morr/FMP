"""next_step.py 的測試：每個階段都說得出下一步，等使用者的題一題不漏，兩批票照 roadmap 寫的先後。
在 plugin 裡腳本在 ../scripts/，複製進專案後在上一層；兩種位置都找。

    python -m unittest discover -s <這個資料夾>
"""

import contextlib
import importlib.util
import io
import shutil
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = next(p for p in (HERE.parent / "scripts" / "next_step.py", HERE.parent / "next_step.py") if p.is_file())
spec = importlib.util.spec_from_file_location("next_step", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

ROADMAP = "# 路線圖\n\n## 里程碑\n\n| 里程碑 | 目標 | 狀態 |\n| --- | --- | --- |\n%s\n## M2 介面\n\n| 里程碑 | 狀態 |\n| --- | --- |\n| 別段的表 | 進行中 |\n"
PROGRESS = "# 進度\n\n## Session 紀錄\n\n| 日期 | 票 | 結果 | 下一步 |\n| --- | --- | --- | --- |\n| 2026-01-02 | 框架 | 建骨架 | 新 session 下 `/舊的` |\n| 2026-01-05 | M1 開工 | 拆票 | %s |\n"
TICKET = "# {n}: {title}\n\nStatus: {status}\nBlocked by: {blocked}\n\n## 驗收\n\n- [ ] 條件\n\n## Comments\n{notes}"


class NextStepTest(unittest.TestCase):
    def setUp(self):
        self.repo = Path(tempfile.mkdtemp(prefix="next-step-")).resolve()
        self.addCleanup(shutil.rmtree, self.repo, ignore_errors=True)
        self.rows("| M0 骨架 | 閘門 | 已驗收，封存在 x |", "| M1 核心 | 第一個功能 | 進行中，已拆 4 張票 |", "| M2 介面 | 畫面 | 未開工 |")
        self.step("新 session 下 `/implement .scratch/m1/issues/01-a.md`")
        self.ticket("m0/issues/01-old.md", status="ready-for-agent")  # 已驗收的里程碑裡沒關的票不算
        self.ticket("m1/issues/01-a.md", "甲")
        self.ticket("m1/issues/02-b.md", "乙", blocked="01")
        self.ticket("m1/issues/03-c.md", "丙", blocked="01, 02")
        self.ticket("m1/issues/04-m1-acceptance.md", "M1 驗收", blocked="01, 02, 03")

    def write(self, rel, text):
        p = self.repo / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")

    def rows(self, *rows):
        self.write("docs/roadmap.md", ROADMAP % "".join(r + "\n" for r in rows))

    def step(self, text):
        self.write("docs/progress.md", PROGRESS % text)

    def ticket(self, rel, title="標題", status="ready-for-agent", blocked="None", notes=""):
        self.write(f".scratch/{rel}", TICKET.format(n=rel.split("/")[-1].split("-")[0], title=title, status=status, blocked=blocked, notes=notes))

    def done(self, *rels):
        for rel in rels:
            self.ticket(rel, status="done")

    def found(self):
        return m.report(self.repo)

    def test_the_first_ticket_nothing_blocks_is_now(self):
        f = self.found()
        self.assertEqual((f["waiting"], f["command"]), ([], "/implement .scratch/m1/issues/01-a.md"))
        self.assertIn("M1 票 01 甲。", f["why"])
        self.assertNotIn("整批", f["why"])
        self.assertEqual(f["later"], ["M1 還有 3 張票，最後一張是驗收票（你要親手試）；驗收後是 /1morr:checkpoint M1", "M2 介面：還沒拆票"])

    def test_done_dropped_and_blocked_tickets_are_skipped(self):
        self.done("m1/issues/01-a.md")
        self.ticket("m1/issues/02-b.md", status="wontfix：不需要了", blocked="01")
        self.assertEqual(self.found()["command"], "/implement .scratch/m1/issues/03-c.md")
        self.done("m1/issues/03-c.md")
        f = self.found()
        self.assertEqual((f["command"], f["later"][0]), ("/implement .scratch/m1/issues/04-m1-acceptance.md",
                                                         "這張是 M1 的驗收票（你要親手試）；驗收後是 /1morr:checkpoint M1"))

    def test_the_progress_cursor_does_not_override_the_tickets(self):
        self.done("m1/issues/01-a.md")
        self.assertEqual(self.found()["command"], "/implement .scratch/m1/issues/02-b.md")  # progress.md 還寫著 01

    def test_several_doable_tickets_offer_the_whole_queue(self):
        self.ticket("m1/issues/02-b.md", "乙")
        self.assertIn("同時做得了的有 2 張，要整批跑：/1morr:ticket-coordinator .scratch/m1/issues", self.found()["why"])

    def test_how_the_ticket_head_is_written_does_not_matter(self):
        self.write(".scratch/m1/issues/01-a.md", "# 01 — 甲\n\n**Status:** done\n\n**Blocked by:** None (can start immediately)\n\n## Comments\n")
        self.write(".scratch/m1/issues/02-b.md", "# 02 — 乙\n\n**Status:** ready-for-agent\n\n**Blocked by:** 01\n\n## 做什麼\n\nStatus: done 寫在內文不算。\n")
        f = self.found()
        self.assertEqual((f["command"], f["why"].split("。")[0]), ("/implement .scratch/m1/issues/02-b.md", "M1 票 02 乙"))

    def test_every_open_question_is_listed(self):
        self.ticket("m1/issues/01-a.md", "甲", notes="\n等使用者：上限寫死還是做成設定？\n")
        self.ticket("m1/issues/02-b.md", "乙", notes="\n等使用者：答過的。\n決定：寫死（使用者定）\n等使用者：之後又問的。\n")
        self.ticket("m1/issues/03-c.md", "丙", status="done", notes="\n等使用者：做完的票不算。\n")
        self.ticket("m0/issues/01-old.md", notes="\n等使用者：結束的里程碑不算。\n")
        self.step("等使用者：試用 M0")
        f = self.found()
        self.assertEqual(f["waiting"], ["M1 票 01：上限寫死還是做成設定？（.scratch/m1/issues/01-a.md）", "M1 票 02：之後又問的。（.scratch/m1/issues/02-b.md）",
                                        "試用 M0（docs/progress.md 最後一列，2026-01-05）"])
        self.assertEqual(f["command"], "")
        self.assertIn("在等你回答", f["why"])
        self.assertTrue(m.render(f).startswith("等你決定（3）\n  - M1 票 01：上限"))

    def test_a_waiting_ticket_is_skipped_for_one_that_can_go(self):
        self.ticket("m1/issues/01-a.md", "甲", notes="\n等使用者：上限寫死還是做成設定？\n")
        self.ticket("m1/issues/02-b.md", "乙")
        f = self.found()
        self.assertEqual((len(f["waiting"]), f["command"]), (1, "/implement .scratch/m1/issues/02-b.md"))

    def test_waiting_in_progress_holds_the_command_back(self):
        self.step("等使用者：重試上限要幾次")
        f = self.found()
        self.assertEqual(f["command"], "/implement .scratch/m1/issues/01-a.md")
        self.assertTrue(f["why"].startswith("先回答上面 docs/progress.md 那一題"))
        self.done(*(f"m1/issues/{n}" for n in ("01-a.md", "02-b.md", "03-c.md", "04-m1-acceptance.md")))
        f = self.found()
        self.assertEqual((f["command"], f["why"]), ("", "先回答上面那一題；開一個新的 session 回答。"))

    def test_without_tickets_the_last_row_of_progress_is_the_step(self):
        self.rows("| M0 骨架 | 閘門 | 未開工 |")
        shutil.rmtree(self.repo / ".scratch")
        self.step("新 session 下 `/grill-with-docs 填 docs/design-brief.md`")
        f = self.found()
        self.assertEqual((f["command"], f["later"]), ("/grill-with-docs 填 docs/design-brief.md", ["M0 骨架：還沒拆票"]))
        self.step("先想一想")
        f = self.found()
        self.assertEqual((f["command"], f["why"]), ("", "docs/progress.md 最後一列（2026-01-05）寫的下一步：先想一想"))
        (self.repo / "docs/progress.md").unlink()
        self.assertIn("還沒有 session 紀錄", self.found()["why"])
        (self.repo / "docs/roadmap.md").unlink()
        self.assertEqual(self.found()["command"], "")

    def test_a_second_queue_waits_for_the_row_it_names(self):
        self.ticket("docs-diet/issues/01-trim.md", "瘦身")
        self.rows("| M0 骨架 | 閘門 | 已驗收 |", "| docs-diet 文件瘦身 | 瘦身 | 未開工，排在 `M1` 之後 |", "| M1 核心 | 功能 | 進行中 |", "| M2 介面 | 畫面 | 未開工 |")
        f = self.found()
        self.assertEqual(f["command"], "/implement .scratch/m1/issues/01-a.md")
        self.assertIn("docs-diet 文件瘦身：1 張票，排在 M1 之後", f["later"])
        # M1 驗收之後、沒有任何一列進行中：輪到它，並提醒改狀態
        self.rows("| docs-diet 文件瘦身 | 瘦身 | 未開工，排在 M1 之後 |", "| M1 核心 | 功能 | 已驗收，封存在 x |", "| M2 介面 | 畫面 | 未開工 |")
        f = self.found()
        self.assertEqual(f["command"], "/implement .scratch/docs-diet/issues/01-trim.md")
        self.assertIn("先把 docs/roadmap.md 里程碑表裡 docs-diet 那一列的狀態改成「進行中」", f["why"])
        # 排在還沒結束的那一列之後：還輪不到，照 progress.md
        self.rows("| docs-diet 文件瘦身 | 瘦身 | 未開工，排在 M2 之後 |", "| M1 核心 | 功能 | 已驗收 |", "| M2 介面 | 畫面 | 未開工 |")
        self.assertEqual(self.found()["command"], "/implement .scratch/m1/issues/01-a.md")

    def test_main_prints_the_three_parts(self):
        self.ticket("m1/issues/01-a.md", "甲", notes="\n等使用者：上限寫死還是做成設定？\n")
        self.ticket("m1/issues/02-b.md", "乙")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = m.main([str(self.repo)])
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue(), "等你決定（1）\n  - M1 票 01：上限寫死還是做成設定？（.scratch/m1/issues/01-a.md）\n現在\n  /implement .scratch/m1/issues/02-b.md\n"
                         "  M1 票 02 乙。開一個新的 session 貼上這條指令。\n之後\n  - M1 還有 3 張票，最後一張是驗收票（你要親手試）；驗收後是 /1morr:checkpoint M1\n  - M2 介面：還沒拆票\n")
        empty = Path(tempfile.mkdtemp(prefix="next-step-empty-"))
        self.addCleanup(shutil.rmtree, empty, ignore_errors=True)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(m.main([str(empty)]), 0)


if __name__ == "__main__":
    unittest.main()
