"""ticket_notes.py 的測試：票上留的紀錄都印得出來，日期有來源，票的其他內容不影響。
在 plugin 裡腳本在 ../scripts/，複製進專案後在上一層；兩種位置都找。

    python -m unittest discover -s <這個資料夾>
"""

import contextlib
import importlib.util
import io
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

# pre-commit hook 裡 git 會設絕對路徑的 GIT_DIR、GIT_INDEX_FILE：在暫存目錄跑的 git 繼承它們，就會改到外面那個 repo。
# 專案常用自己的 hook 跑這些測試，所以由測試自己清；測試只碰自己建的暫存 repo。
for _name in [n for n in os.environ if n.startswith("GIT_")]:
    del os.environ[_name]

HERE = Path(__file__).resolve().parent
SCRIPT = next(p for p in (HERE.parent / "scripts" / "ticket_notes.py", HERE.parent / "ticket_notes.py") if p.is_file())
spec = importlib.util.spec_from_file_location("ticket_notes", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

HEAD = "# {n}: {title}\n\nStatus: done\nBlocked by: None\n\n## What to build\n\n決定：這一行在 Comments 之前，不算。\n\n## 驗收\n\n- [x] 好了\n\n## Comments\n\n"


class TicketNotesTest(unittest.TestCase):
    def setUp(self):
        self.repo = Path(tempfile.mkdtemp(prefix="ticket-notes-")).resolve()
        self.addCleanup(shutil.rmtree, self.repo, ignore_errors=True)

    def ticket(self, rel, title, *lines):
        p = self.repo / ".scratch" / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(HEAD.format(n=p.name.split("-")[0], title=title) + "\n".join(lines) + "\n", encoding="utf-8")
        return p

    def run_it(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = m.main(list(args))
        return code, out.getvalue(), err.getvalue()

    def test_each_ticket_prints_its_notes(self):
        self.ticket("m0/issues/01-gates.md", "閘門", "code-review 留了一條沒處理的發現。", "Session 紀錄：2026-01-04 閘門就位。",
                    "決定：用 X 不用 Y（Agent 定）", "決定：埠由系統挑（使用者同意）")
        self.ticket("m0/issues/02-m0-acceptance.md", "M0 驗收")
        code, out, _ = self.run_it("m0", str(self.repo))
        self.assertEqual(code, 0)
        self.assertEqual(out, "M0 01 閘門（2026-01-04）\n  Session 紀錄：閘門就位。\n  決定：用 X 不用 Y（Agent 定）\n  決定：埠由系統挑（使用者同意）\n")

    def test_archive_lines_carry_date_milestone_and_ticket(self):
        self.ticket("m1.5/issues/02-b.md", "乙", "Session 紀錄：2026-01-05 做完 a | b。", "決定：用 X（Agent 定）")
        self.ticket("m1.5/issues/01-a.md", "甲", "Session 紀錄：2026-01-06 做完甲。")
        self.ticket("m1.5/issues/14b-c.md", "丙", "Session 紀錄：2026-01-05 做完丙。")
        self.assertEqual(m.archive(self.repo, "m1.5"), (
            ["| 2026-01-05 | M1.5 02 | 做完 a \\| b。 | |", "| 2026-01-05 | M1.5 14b | 做完丙。 | |", "| 2026-01-06 | M1.5 01 | 做完甲。 | |"],
            ["- 2026-01-05 M1.5 票 02（Agent 定）：用 X"]))
        code, out, _ = self.run_it("m1.5", str(self.repo), "--archive")
        self.assertEqual((code, out.split("\n")[0], out.strip().split("\n")[-2:]), (0, "## Session 紀錄", ["## 決定", "- 2026-01-05 M1.5 票 02（Agent 定）：用 X"]))

    def test_changelog_entries_are_grouped_by_category(self):
        self.ticket("m0/issues/01-a.md", "甲", "Session 紀錄：2026-01-04 做完甲。", "變更：Fixed｜候選列｜整季缺時問得到。", "變更：Added｜搜尋｜可以搜作品。")
        self.ticket("m0/issues/02-b.md", "乙", "Session 紀錄：2026-01-05 做完乙。", "變更： Added ｜ 搜尋 ｜ 不合格式的不印", "變更：Added｜匯出｜可以匯出。", "變更：無",
                    "變更：新增了一些東西")
        self.ticket("m0/issues/03-c.md", "丙", "Session 紀錄：2026-01-06 做完丙。", "變更：無")
        self.assertEqual(m.changelog(self.repo, "m0"), ["### Added", "- **搜尋**：可以搜作品。", "- **匯出**：可以匯出。", "", "### Fixed", "- **候選列**：整季缺時問得到。"])
        code, out, _ = self.run_it("m0", str(self.repo), "--changelog")
        self.assertEqual((code, out.split("\n")[0]), (0, "### Added"))
        self.assertIn("  變更：Fixed｜候選列｜整季缺時問得到。\n", self.run_it("m0", str(self.repo))[1])
        self.assertEqual(self.run_it("m0", str(self.repo), "--archive", "--changelog")[0], 2)

    def test_an_effort_that_is_not_a_milestone_keeps_its_directory_name(self):
        self.ticket("docs-diet/issues/01-trim.md", "瘦身", "Session 紀錄：2026-01-04 瘦了。")
        self.assertEqual(m.archive(self.repo, "docs-diet")[0], ["| 2026-01-04 | docs-diet 01 | 瘦了。 | |"])

    def test_an_undated_ticket_takes_the_date_of_its_file(self):
        p = self.ticket("m0/issues/01-gates.md", "閘門", "Session 紀錄：閘門就位。")
        os.utime(p, (1767614400, 1767614400))  # 2026-01-05 中午（UTC），±11 小時內的時區都是這一天
        self.assertEqual(m.notes(self.repo, "m0")[0]["date"], "2026-01-05")

    @unittest.skipUnless(shutil.which("git"), "要 git")
    def test_an_undated_ticket_in_git_takes_the_date_of_its_last_commit(self):
        self.ticket("m0/issues/01-gates.md", "閘門", "Session 紀錄：閘門就位。")
        env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.com", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.com",
                   GIT_AUTHOR_DATE="2026-01-03T12:00:00", GIT_COMMITTER_DATE="2026-01-03T12:00:00")
        for args in (("init", "-q"), ("add", "-A"), ("-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", "docs: t")):
            subprocess.run(["git", "-C", str(self.repo), *args], env=env, check=True, capture_output=True)
        self.assertEqual(m.notes(self.repo, "m0")[0]["date"], "2026-01-03")

    def test_no_notes_and_wrong_usage(self):
        self.ticket("m0/issues/01-gates.md", "閘門")
        self.assertEqual(self.run_it("m0", str(self.repo))[:2], (0, "M0 的票還沒有留紀錄\n"))
        self.assertEqual(self.run_it("m9", str(self.repo))[0], 1)
        self.assertEqual(self.run_it()[0], 2)
        self.assertEqual(self.run_it("m0", str(self.repo), "--nope")[0], 2)


if __name__ == "__main__":
    unittest.main()
