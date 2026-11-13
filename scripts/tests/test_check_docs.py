"""check_docs.py 的測試：每條規則違規會紅，無關的改動不紅。
在 plugin 裡腳本在 ../scripts/，複製進專案後在上一層；兩種位置都找。

    python -m unittest discover -s <這個資料夾>
"""

import contextlib
import importlib.util
import io
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = next(p for p in (HERE.parent / "scripts" / "check_docs.py", HERE.parent / "check_docs.py") if p.is_file())
spec = importlib.util.spec_from_file_location("check_docs", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

PROGRESS = """# 進度

開頭的說明不屬於任何段。

## 寫法與封存

- 規則寫在這裡，這一段的行可以很長：%s

## Session 紀錄

| 日期 | 票 | 結果 | 下一步 |
| --- | --- | --- | --- |
| 2026-01-02 | M1 01 | 做了 a\\|b 兩件事 | 沒寫指令的舊列不檢查 |
| 2026-01-03 | M1 02 | 做完 | 新 session 下 `/implement .scratch/m1/issues/03-x.md` |

## 偏差與決定

- 2026-01-02 M1 票 01（使用者同意）：改用另一個套件，見 ADR 0003。
""" % ("長" * 300)

ROADMAP = """# 路線圖

> 開頭的說明。

## 里程碑

| 里程碑 | 目標 | 拆票前讀 | 狀態 |
| --- | --- | --- | --- |
| M0 骨架 | 閘門 | brief | 完成，[已封存](archive/M0.md) |
| M1 核心 | 第一個功能 | plan §2 | 進行中，已拆 3 張票 |
| M2 介面 | 畫面 | brief §4 | 未開工 |

## M2 介面

目標：畫面。

## 不排里程碑
"""

SPEC = "# M1\n\n## 目標\n\n## 範圍（做 / 不做）\n\n## 共同規則\n\n## 驗收\n\n### Agent 驗\n\n### 使用者試\n\n- 啟動後打一個字。\n\n## 票序\n"
TICKET = "# 01: 標題\n\nStatus: ready-for-agent\nBlocked by: None\n\n## What to build\n\n## 驗收\n\n- [ ] 條件\n\n## Comments\n"


class Repo(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="check-docs-"))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.write("docs/progress.md", PROGRESS)
        self.write("docs/roadmap.md", ROADMAP)
        self.write(".scratch/m1/spec.md", SPEC)
        self.write(".scratch/m1/issues/01-first.md", TICKET)
        self.write(".scratch/m1/issues/02-m1-acceptance.md", TICKET)

    def write(self, rel, text):
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")

    def sub(self, rel, old, new):
        text = (self.root / rel).read_text(encoding="utf-8")
        self.assertIn(old, text)
        self.write(rel, text.replace(old, new))

    def clean(self):
        self.assertEqual(m.run(self.root), [])

    def red(self, needle):
        found = m.run(self.root)
        self.assertTrue(any(needle in p for p in found), f"沒有一條違規提到「{needle}」：{found}")


class BasicsTest(Repo):
    def test_fixture_is_clean(self):
        self.clean()

    def test_main_exit_codes(self):
        self.assertEqual(m.main([str(self.root)]), 0)
        self.sub("docs/progress.md", "## 偏差與決定", "## 其他")
        with contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(m.main([str(self.root)]), 1)
        self.assertIn("2 條違規", err.getvalue())

    def test_missing_progress(self):
        (self.root / "docs/progress.md").unlink()
        self.red("找不到 docs/progress.md")

    def test_missing_roadmap(self):
        (self.root / "docs/roadmap.md").unlink()
        self.red("找不到 docs/roadmap.md")


class ProgressSectionsTest(Repo):
    def test_missing_section(self):
        self.sub("docs/progress.md", "## 寫法與封存", "## 寫法")
        self.red("缺〈寫法與封存〉")

    def test_duplicate_section(self):
        self.sub("docs/progress.md", "## 偏差與決定", "## 偏差與決定\n\n## 偏差與決定")
        self.red("出現 2 次")

    def test_wrong_order(self):
        text = (self.root / "docs/progress.md").read_text(encoding="utf-8")
        a, b = text.index("## Session 紀錄"), text.index("## 偏差與決定")
        self.write("docs/progress.md", text[:a] + text[b:] + "\n" + text[a:b])
        self.red("順序不對")

    def test_extra_section(self):
        self.sub("docs/progress.md", "## 偏差與決定", "## 待辦\n\n## 偏差與決定")
        self.red("多了〈待辦〉")

    def test_heading_in_code_block_and_h3_are_not_sections(self):
        self.sub("docs/progress.md", "- 規則寫在這裡", "### 小節\n\n```\n## 範例\n```\n\n- 規則寫在這裡")
        self.clean()


class SessionsTest(Repo):
    def test_text_outside_the_table(self):
        self.sub("docs/progress.md", "\n## 偏差與決定", "補充說明寫在表外。\n\n## 偏差與決定")
        self.red("表外不放別的字")

    def test_row_too_long(self):
        self.sub("docs/progress.md", "| 做完 |", "| " + "字" * 200 + " |")
        self.red("上限 200")

    def test_row_of_exactly_200_is_fine(self):
        row = "| 2026-01-03 | M1 02 | 做完 | 新 session 下 `/implement .scratch/m1/issues/03-x.md` |"
        self.sub("docs/progress.md", row, row.replace("做完", "做完" + "字" * (200 - len(row))))
        self.clean()

    def test_last_row_without_a_command(self):
        self.sub("docs/progress.md", "新 session 下 `/implement .scratch/m1/issues/03-x.md`", "繼續做下一張票")
        self.red("下一步")

    def test_code_that_is_not_a_command(self):
        self.sub("docs/progress.md", "新 session 下 `/implement .scratch/m1/issues/03-x.md`", "看 `docs/plan.md`")
        self.red("下一步")

    def test_waiting_for_the_user_is_fine(self):
        for step in ("等使用者：決定要不要支援 Windows", "等使用者：試用 M1"):
            with self.subTest(step):
                original = (self.root / "docs/progress.md").read_text(encoding="utf-8")
                self.sub("docs/progress.md", "新 session 下 `/implement .scratch/m1/issues/03-x.md`", step)
                self.clean()
                self.write("docs/progress.md", original)

    def test_no_rows(self):
        self.sub("docs/progress.md", "| 2026-01-02 | M1 01 | 做了 a\\|b 兩件事 | 沒寫指令的舊列不檢查 |\n", "")
        self.sub("docs/progress.md", "| 2026-01-03 | M1 02 | 做完 | 新 session 下 `/implement .scratch/m1/issues/03-x.md` |\n", "")
        self.red("沒有任何一列")

    def test_missing_next_column(self):
        self.sub("docs/progress.md", "| 日期 | 票 | 結果 | 下一步 |", "| 日期 | 票 | 結果 | 之後 |")
        self.red("「下一步」欄")

    def test_column_order_and_alignment_do_not_matter(self):
        self.sub("docs/progress.md", "| 日期 | 票 | 結果 | 下一步 |\n| --- | --- | --- | --- |", "| 日期 | 票 | 結果 | 下一步 |\n|:---|:---:|---|---:|")
        self.clean()


class DeviationsTest(Repo):
    def test_entry_without_a_date(self):
        self.sub("docs/progress.md", "- 2026-01-02 M1 票 01", "- M1 票 01")
        self.red("YYYY-MM-DD")

    def test_wrapped_entry(self):
        self.sub("docs/progress.md", "見 ADR 0003。", "見 ADR 0003。\n  第二行的補充。")
        self.red("每條一行")

    def test_entry_too_long(self):
        self.sub("docs/progress.md", "見 ADR 0003。", "見 ADR 0003。" + "字" * 200)
        self.red("上限 200")

    def test_entry_without_a_decider(self):
        self.sub("docs/progress.md", "（使用者同意）：", "：")
        self.red("決定者")

    def test_entry_with_two_deciders(self):
        self.sub("docs/progress.md", "（使用者同意）：", "（使用者同意）（Agent 定）：")
        self.red("決定者")

    def test_any_decider_anywhere_in_the_entry(self):
        for tag in m.DECIDERS:
            with self.subTest(tag):
                self.setUp()
                self.sub("docs/progress.md", "（使用者同意）：改用另一個套件，見 ADR 0003。", f"：換了套件，見 ADR 0003（{tag}）。")
                self.clean()

    def test_empty_section_is_fine(self):
        self.sub("docs/progress.md", "- 2026-01-02 M1 票 01（使用者同意）：改用另一個套件，見 ADR 0003。\n", "")
        self.clean()


class MilestonesTest(Repo):
    def test_two_active(self):
        self.sub("docs/roadmap.md", "| 完成，[已封存](archive/M0.md) |", "| 進行中，還有 1 張 |")
        self.red("最多一個")

    def test_none_active_is_fine(self):
        self.sub("docs/roadmap.md", "| 進行中，已拆 3 張票 |", "| 未開工，上一個里程碑還在進行中的檢查不算 |")
        self.clean()

    def test_missing_state_column(self):
        self.sub("docs/roadmap.md", "| 里程碑 | 目標 | 拆票前讀 | 狀態 |", "| 里程碑 | 目標 | 拆票前讀 | 備註 |")
        self.red("「狀態」欄")

    def test_missing_milestone_section(self):
        self.sub("docs/roadmap.md", "## 里程碑\n", "## 總表\n")
        self.red("缺〈里程碑〉")

    def test_other_sections_columns_and_wording_do_not_matter(self):
        self.sub("docs/roadmap.md", "## M2 介面\n\n目標：畫面。\n", "## M2 介面\n\n已開工，見 spec。\n\n## M3 發佈\n\n進行中的字出現在表外不算。\n")
        self.sub("docs/roadmap.md", "| 里程碑 | 目標 | 拆票前讀 | 狀態 |\n| --- | --- | --- | --- |", "| 狀態 | 里程碑 | 目標 | 拆票前讀 |\n| --- | --- | --- | --- |")
        self.sub("docs/roadmap.md", "| M2 介面 | 畫面 | brief §4 | 未開工 |", "| 等 M1 進行中的票做完 | M2 介面 | 畫面 | brief §4 |")
        self.clean()


class BudgetTest(Repo):
    def test_over_budget(self):
        for rel, limit in m.BUDGETS.items():
            with self.subTest(rel):
                self.setUp()
                base = (self.root / rel).read_text(encoding="utf-8") if (self.root / rel).is_file() else "# 文件\n"
                head, rest = base.split("\n", 1)  # 填在第一個 ## 之前，不屬於任何段
                pad = "字" * (limit - len(base) - 1)
                self.write(rel, f"{head}\n{pad}\n{rest}")
                self.clean()
                self.write(rel, f"{head}\n{pad}字\n{rest}")
                self.red(f"{rel}：{limit + 1} 字元")

    def test_missing_files_and_other_files_are_not_measured(self):
        self.write("docs/research/big.md", "字" * 100000)
        self.clean()


class CurrentStateTest(Repo):
    def test_ticket_number_in_brief_or_plan(self):
        for rel in (m.BRIEF, m.PLAN):
            for text in ("照 M1 票 12 的做法", "（票3）"):
                with self.subTest(rel=rel, text=text):
                    self.setUp()
                    self.write(rel, f"# 文件\n\n## 1. 節\n\n- 這一條{text}。\n")
                    self.red(f"{rel}:5：寫了票號")

    def test_other_wording_is_fine(self):
        text = "# 文件\n\n## 1. 節\n\n- 拆票後以票為準；M0 的第一張票接上；門票 3 張不是票號的寫法也不要用。\n\n```\n票 12\n```\n"
        self.write(m.BRIEF, text.replace("門票 3 張不是票號的寫法也不要用", "見 ADR 0003、事實 B3"))
        self.write(m.PLAN, text.replace("門票 3 張不是票號的寫法也不要用", "見 ADR 0003、事實 B3"))
        self.clean()

    def test_ticket_numbers_elsewhere_are_fine(self):
        self.write("docs/roadmap.md", (self.root / "docs/roadmap.md").read_text(encoding="utf-8") + "\n- 票 12 留下的項目。\n")
        self.clean()


@unittest.skipUnless(shutil.which("git"), "要 git")
class CodeRefsTest(Repo):
    def track(self):
        for args in (("init", "-q"), ("add", "-A")):
            subprocess.run(["git", "-C", str(self.root), *args], check=True, capture_output=True)

    def test_code_citing_a_section_number(self):
        for text in ("// 見 plan §3.2", "# brief §4 的規則", "/* docs/plan.md § 11 */"):
            with self.subTest(text):
                self.setUp()
                self.write("src/engine.rs", f"fn main() {{}}\n{text}\n")
                self.track()
                self.red("src/engine.rs:2：引用了 brief 或 plan 的章節號")

    def test_citing_an_adr_or_a_fact_is_fine(self):
        self.write("src/engine.rs", "// ADR 0003、事實 B3；計畫裡寫的 plan 與 brief 兩個字本身不算；§ 單獨出現也不算\n")
        self.track()
        self.clean()

    def test_docs_tickets_and_markdown_may_cite_sections(self):
        self.write("docs/notes.txt", "plan §3.2\n")
        self.write(".scratch/m1/issues/01-first.md", TICKET.replace("Blocked by: None", "Blocked by: None\n讀: plan §3.2；brief §4"))
        self.write("src/README.md", "見 plan §3.2\n")
        self.track()
        self.clean()

    def test_untracked_binary_and_non_repo_are_skipped(self):
        self.write("src/engine.rs", "// plan §3.2\n")
        self.clean()  # 不是 git repo
        subprocess.run(["git", "-C", str(self.root), "init", "-q"], check=True, capture_output=True)
        self.clean()  # 沒被追蹤
        (self.root / "src/blob.bin").write_bytes(b"\0plan \xc2\xa73.2")
        subprocess.run(["git", "-C", str(self.root), "add", "src/blob.bin"], check=True, capture_output=True)
        self.clean()


class ScratchTest(Repo):
    def test_tickets_without_spec(self):
        (self.root / ".scratch/m1/spec.md").unlink()
        self.red("沒有 spec.md")

    def test_spec_missing_a_section(self):
        self.sub(".scratch/m1/spec.md", "## 共同規則\n\n", "")
        self.red("缺〈共同規則〉")

    def test_spec_extra_sections_and_order_do_not_matter(self):
        self.write(".scratch/m1/spec.md", "# M1\n\n## 票序\n\n## 細節\n\n## 驗收\n\n###  使用者試（手機）\n\n## 共同規則\n\n## 範圍\n\n## 目標(做什麼)\n")
        self.clean()

    def test_active_spec_without_user_trial(self):
        self.sub(".scratch/m1/spec.md", "### 使用者試\n", "### 人工檢查\n")
        self.red("m1/spec.md：〈驗收〉底下要有 `### 使用者試`")

    def test_user_trial_outside_the_acceptance_section_does_not_count(self):
        self.sub(".scratch/m1/spec.md", "### 使用者試\n\n- 啟動後打一個字。\n\n## 票序\n", "## 票序\n\n### 使用者試\n")
        self.red("m1/spec.md：〈驗收〉底下要有 `### 使用者試`")

    def test_specs_outside_the_active_milestone_need_no_user_trial(self):
        old = SPEC.replace("### Agent 驗\n\n### 使用者試\n\n- 啟動後打一個字。\n\n", "")
        self.write(".scratch/m0/spec.md", old)
        self.write(".scratch/m0/issues/01-m0-acceptance.md", TICKET)
        self.write(".scratch/docs-cleanup/spec.md", old)
        self.write(".scratch/docs-cleanup/issues/01-trim.md", TICKET)
        self.clean()

    def test_milestone_without_acceptance_ticket(self):
        (self.root / ".scratch/m1/issues/02-m1-acceptance.md").rename(self.root / ".scratch/m1/issues/02-m1-close.md")
        self.red("沒有驗收票")

    def test_effort_that_is_not_a_milestone_needs_no_acceptance_ticket(self):
        self.write(".scratch/docs-cleanup/spec.md", SPEC)
        self.write(".scratch/docs-cleanup/issues/01-trim.md", TICKET)
        self.clean()

    def test_decimal_milestone_needs_one(self):
        self.write(".scratch/m1.5/spec.md", SPEC)
        self.write(".scratch/m1.5/issues/01-x.md", TICKET)
        self.red(".scratch/m1.5/issues/：沒有驗收票")

    def test_directory_without_issues_is_ignored(self):
        self.write(".scratch/notes/draft.md", "隨手記")
        self.clean()

    def test_ticket_without_status(self):
        self.sub(".scratch/m1/issues/01-first.md", "Status: ready-for-agent\n", "")
        self.red("Status:")

    def test_status_only_in_a_later_section_does_not_count(self):
        self.sub(".scratch/m1/issues/01-first.md", "Status: ready-for-agent\n", "")
        self.sub(".scratch/m1/issues/01-first.md", "## Comments\n", "## Comments\n\nStatus: done\n")
        self.red("Status:")

    def test_status_value_and_bold_do_not_matter(self):
        self.sub(".scratch/m1/issues/01-first.md", "Status: ready-for-agent", "**Status:** needs-info")
        self.clean()

    def test_done_ticket_in_the_active_milestone_needs_a_session_note(self):
        for status in ("Status: done", "**Status:** done"):
            with self.subTest(status):
                self.setUp()
                self.sub(".scratch/m1/issues/01-first.md", "Status: ready-for-agent", status)
                self.red("01-first.md：做完的票")
                self.sub(".scratch/m1/issues/01-first.md", "## Comments\n", "## Comments\n\n- code-review 沒處理的發現。\n\nSession 紀錄：閘門就位。\n偏差：改用另一個套件（使用者同意）。\n")
                self.clean()

    def test_session_note_before_comments_does_not_count(self):
        self.sub(".scratch/m1/issues/01-first.md", "Status: ready-for-agent", "Status: done")
        self.sub(".scratch/m1/issues/01-first.md", "## What to build\n", "## What to build\n\nSession 紀錄：寫錯地方。\n")
        self.red("01-first.md：做完的票")

    def test_done_tickets_outside_the_active_milestone_are_not_checked(self):
        self.write(".scratch/m0/spec.md", SPEC)
        self.write(".scratch/m0/issues/01-old.md", TICKET.replace("ready-for-agent", "done"))
        self.write(".scratch/m0/issues/02-m0-acceptance.md", TICKET.replace("ready-for-agent", "done"))
        self.write(".scratch/docs-cleanup/spec.md", SPEC)
        self.write(".scratch/docs-cleanup/issues/01-trim.md", TICKET.replace("ready-for-agent", "done"))
        self.clean()


if __name__ == "__main__":
    unittest.main()
