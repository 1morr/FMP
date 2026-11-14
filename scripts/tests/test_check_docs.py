"""check_docs.py 的測試：每條規則違規會紅，無關的改動不紅。
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

# pre-commit hook 裡 git 會設絕對路徑的 GIT_DIR、GIT_INDEX_FILE：在暫存目錄跑的 git 繼承它們，就把假檔案寫進外面那個 repo 的
# index、把它的 config 改成 core.bare = true。專案常用自己的 hook 跑這些測試，所以由測試自己清；測試只碰自己建的暫存 repo。
for _name in [n for n in os.environ if n.startswith("GIT_")]:
    del os.environ[_name]

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
""" % ("長" * 300)

DECISIONS = """# 決策紀錄

開頭的說明不屬於任何段。

## 寫法

- 這一段的行可以很長、不必是清單：%s

## 紀錄

- 2026-01-02 M1 票 01（使用者同意）：改用另一個套件，見 ADR 0003。
""" % ("長" * 300)

ROADMAP = """# 路線圖

> 開頭的說明。

## 里程碑

| 里程碑 | 目標 | 拆票前讀 | 狀態 |
| --- | --- | --- | --- |
| M0 骨架 | 閘門 | brief | 已驗收，封存在 [`docs/archive/M0.md`](archive/M0.md) |
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
        self.write("docs/decisions.md", DECISIONS)
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

    def row(self, name, state="未開工"):
        """在里程碑表加一列。"""
        self.sub("docs/roadmap.md", "| M2 介面 | 畫面 | brief §4 | 未開工 |\n", f"| M2 介面 | 畫面 | brief §4 | 未開工 |\n| {name} | 目標 | — | {state} |\n")

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
        self.sub("docs/progress.md", "## Session 紀錄", "## 其他")
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
        self.sub("docs/progress.md", "## 寫法與封存", "## 寫法與封存\n\n## 寫法與封存")
        self.red("出現 2 次")

    def test_wrong_order(self):
        text = (self.root / "docs/progress.md").read_text(encoding="utf-8")
        a, b = text.index("## 寫法與封存"), text.index("## Session 紀錄")
        self.write("docs/progress.md", text[:a] + text[b:] + "\n" + text[a:b])
        self.red("順序不對")

    def test_extra_section(self):
        self.sub("docs/progress.md", "## Session 紀錄", "## 偏差與決定\n\n## Session 紀錄")
        self.red("多了〈偏差與決定〉")

    def test_heading_in_code_block_and_h3_are_not_sections(self):
        self.sub("docs/progress.md", "- 規則寫在這裡", "### 小節\n\n```\n## 範例\n```\n\n- 規則寫在這裡")
        self.clean()


class SessionsTest(Repo):
    def test_text_outside_the_table(self):
        self.write("docs/progress.md", (self.root / "docs/progress.md").read_text(encoding="utf-8") + "\n補充說明寫在表外。\n")
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


class DecisionsTest(Repo):
    def test_entry_without_a_date(self):
        self.sub("docs/decisions.md", "- 2026-01-02 M1 票 01", "- M1 票 01")
        self.red("YYYY-MM-DD")

    def test_wrapped_entry(self):
        self.sub("docs/decisions.md", "見 ADR 0003。", "見 ADR 0003。\n  第二行的補充。")
        self.red("每條一行")

    def test_entry_too_long(self):
        self.sub("docs/decisions.md", "見 ADR 0003。", "見 ADR 0003。" + "字" * 200)
        self.red("上限 200")

    def test_entry_without_a_decider(self):
        self.sub("docs/decisions.md", "（使用者同意）：", "：")
        self.red("決定者")

    def test_entry_with_two_deciders(self):
        self.sub("docs/decisions.md", "（使用者同意）：", "（使用者同意）（Agent 定）：")
        self.red("決定者")

    def test_any_decider_anywhere_in_the_entry(self):
        for tag in m.DECIDERS:
            with self.subTest(tag):
                self.setUp()
                self.sub("docs/decisions.md", "（使用者同意）：改用另一個套件，見 ADR 0003。", f"：換了套件，見 ADR 0003（{tag}）。")
                self.clean()

    def test_empty_section_is_fine(self):
        self.sub("docs/decisions.md", "- 2026-01-02 M1 票 01（使用者同意）：改用另一個套件，見 ADR 0003。\n", "")
        self.clean()

    def test_missing_file_or_section(self):
        self.sub("docs/decisions.md", "## 紀錄", "## 清單")
        self.red("docs/decisions.md：缺〈紀錄〉")
        (self.root / "docs/decisions.md").unlink()
        self.red("找不到 docs/decisions.md")

    def test_other_sections_are_free_form(self):
        self.sub("docs/decisions.md", "## 寫法\n", "## 怎麼寫\n\n沒有日期的一行。\n\n## 附註\n")
        self.clean()


class MilestonesTest(Repo):
    def test_two_active(self):
        self.sub("docs/roadmap.md", "| 已驗收，封存在 [`docs/archive/M0.md`](archive/M0.md) |", "| 進行中，還有 1 張 |")
        self.red("最多一個")

    def test_none_active_is_fine(self):
        self.sub("docs/roadmap.md", "| 進行中，已拆 3 張票 |", "| 未開工，上一個里程碑還在進行中的檢查不算 |")
        self.clean()

    def test_missing_state_column(self):
        self.sub("docs/roadmap.md", "| 里程碑 | 目標 | 拆票前讀 | 狀態 |", "| 里程碑 | 目標 | 拆票前讀 | 備註 |")
        self.red("「狀態」欄")

    def test_missing_name_or_goal_column(self):
        self.sub("docs/roadmap.md", "| 里程碑 | 目標 | 拆票前讀 | 狀態 |", "| 階段 | 做什麼 | 拆票前讀 | 狀態 |")
        self.red("的表要有「里程碑」「目標」欄")

    def test_missing_milestone_section(self):
        self.sub("docs/roadmap.md", "## 里程碑\n", "## 總表\n")
        self.red("缺〈里程碑〉")

    def test_other_sections_columns_and_wording_do_not_matter(self):
        self.sub("docs/roadmap.md", "## M2 介面\n\n目標：畫面。\n", "## M2 介面\n\n已開工，見 spec。\n\n## M3 發佈\n\n進行中的字出現在表外不算。\n")
        text = (self.root / "docs/roadmap.md").read_text(encoding="utf-8")
        rows = [l for l in text.split("\n") if l.startswith("|")]
        for row in rows:  # 狀態欄搬到最前面
            cells = row.strip("|").split("|")
            text = text.replace(row, "|" + "|".join(cells[-1:] + cells[:-1]) + "|")
        self.write("docs/roadmap.md", text)
        self.sub("docs/roadmap.md", "| 未開工 | M2 介面 | 畫面 | brief §4 |", "| 未開工，等 M1 進行中的票做完 | M2 介面 | 畫面 | brief §4 |")
        self.clean()


class MilestoneStateTest(Repo):
    def test_state_that_starts_with_another_word(self):
        for state in ("完成，[已封存](archive/M0.md)", "2026-01-02 驗收", "[`docs/archive/M0.md`](archive/M0.md)", "待驗收", ""):
            with self.subTest(state=state):
                self.write("docs/roadmap.md", ROADMAP.replace("已驗收，封存在 [`docs/archive/M0.md`](archive/M0.md)", state))
                self.red("docs/roadmap.md:9：狀態要以「未開工」、「進行中」、「已驗收」、「不做」其中一個開頭")

    def test_what_follows_the_word_is_free(self):
        self.sub("docs/roadmap.md", "| 未開工 |", "| 不做：併進 M1（2026-01-05 使用者定） |")
        self.sub("docs/roadmap.md", "已驗收，封存在 [`docs/archive/M0.md`](archive/M0.md)", "已驗收（2026-01-02）")
        self.clean()


class ArchiveTest(Repo):
    ARCHIVE = "# M0\n\n## Session 紀錄\n\n| 日期 | 票 | 結果 | 下一步 |\n| --- | --- | --- | --- |\n| 2026-01-01 | M0 01 | 做完 | 舊列的下一步不查，長度也不查：%s |\n\n## 決定\n\n- 2026-01-01 M0（使用者定）：用 Rust。\n\n## 使用者試\n\n- 啟動後打一個字：可以。\n" % ("長" * 300)

    def setUp(self):
        super().setUp()
        self.write("docs/archive/M0.md", self.ARCHIVE)

    def test_archive_fixture_is_clean(self):
        self.clean()

    def test_missing_sections(self):
        self.sub("docs/archive/M0.md", "## Session 紀錄", "## 紀錄")
        self.red("docs/archive/M0.md：缺〈Session 紀錄〉")
        self.write("docs/archive/M0.md", self.ARCHIVE.replace("## 決定", "## 其他"))
        self.red("docs/archive/M0.md：缺〈決定〉")

    def test_archived_decisions_keep_the_format(self):
        for old, new, needle in (("（使用者定）", "", "決定者"), ("- 2026-01-01 M0", "- M0", "YYYY-MM-DD"), ("用 Rust。", "用 Rust。" + "字" * 200, "上限 200")):
            with self.subTest(needle):
                self.write("docs/archive/M0.md", self.ARCHIVE.replace(old, new))
                self.red(needle)

    def test_archive_without_the_user_trial(self):
        for old, new in (("## 使用者試\n\n- 啟動後打一個字：可以。\n", ""), ("- 啟動後打一個字：可以。\n", ""), ("## 使用者試", "### 使用者試")):
            with self.subTest(old=old, new=new):
                self.write("docs/archive/M0.md", self.ARCHIVE.replace(old, new))
                self.red("docs/archive/M0.md：缺〈使用者試〉段")

    def test_how_the_user_trial_is_written_and_where_it_sits_do_not_matter(self):
        body = self.ARCHIVE.split("## 使用者試")[0]
        self.write("docs/archive/M0.md", "# M0\n\n## 使用者試\n\n代測：使用者不在，四個平台都由 agent 測，沒有人聽過聲音。\n\n" + body.split("# M0\n\n", 1)[1])
        self.clean()

    def test_the_old_section_name_and_extra_sections_are_left_alone(self):
        self.write("docs/archive/M0.md", self.ARCHIVE.split("## 使用者試")[0].replace("## 決定\n\n- 2026-01-01 M0（使用者定）：用 Rust。", "## 偏差與決定\n\n- 2026-01-01 沒有決定者也很長：%s\n  - 還有子項。\n\n## plan §11\n\n舊的範圍。" % ("長" * 300)))
        self.clean()

    def test_other_files_in_archive_are_not_checked(self):
        self.write("docs/archive/notes.txt", "隨手記")
        self.clean()


class AdrTest(Repo):
    def setUp(self):
        super().setUp()
        self.write("docs/adr/0001-own-core.md", "# 核心自己寫\n\n理由。\n")
        self.write("docs/adr/template.md", "<!-- 範本 -->\n")
        self.write("docs/adr/.gitkeep", "")

    def test_adr_fixture_is_clean(self):
        self.clean()

    def test_badly_named_adr(self):
        for name in ("1-own-core.md", "0002_Own_Core.md", "adr-0002.md", "0002-.md"):
            with self.subTest(name):
                self.setUp()
                self.write(f"docs/adr/{name}", "# 標題\n")
                self.red(f"docs/adr/{name}：檔名寫成")

    def test_adr_without_a_title(self):
        self.write("docs/adr/0002-two-backends.md", "狀態：已採用\n\n# 標題在後面\n")
        self.red("docs/adr/0002-two-backends.md：第一行要是")
        self.write("docs/adr/0002-two-backends.md", "\n# 兩個後端\n\n內文怎麼寫不管。\n")
        self.clean()


class LayoutTest(Repo):
    GUIDE = "# Demo\n\n## 文件\n\n- `docs/progress.md`、`docs/roadmap.md`、`docs/decisions.md`、`docs/research/`\n"

    def setUp(self):
        super().setUp()
        self.write("AGENTS.md", self.GUIDE)
        self.write("docs/research/facts-rime.md", "# 事實：Rime\n\n## 事實\n\n- **R1** 來源。\n")

    def test_fixture_with_instructions_is_clean(self):
        self.clean()

    def test_a_doc_the_instructions_do_not_mention(self):
        self.write("docs/notes.md", "# 筆記\n")
        self.red("docs/notes.md：AGENTS.md 沒有提到它")
        self.write("docs/design/index.html", "<p>")
        self.red("docs/design/：AGENTS.md 沒有提到它")
        self.write("AGENTS.md", self.GUIDE + "- `docs/notes.md`：筆記。\n- `docs/design/`：設計稿。\n")
        self.clean()

    def test_claude_md_counts_when_there_is_no_agents_md(self):
        (self.root / "AGENTS.md").rename(self.root / "CLAUDE.md")
        self.clean()
        self.write("docs/notes.md", "# 筆記\n")
        self.red("docs/notes.md：CLAUDE.md 沒有提到它")

    def test_without_an_instruction_file_or_for_hidden_and_nested_entries_nothing_is_checked(self):
        self.write("docs/.gitkeep", "")
        self.write("docs/research/anything.md", "# 主題\n")
        self.write("docs/research/trial-2026-01-02/log.txt", "ok")
        self.clean()
        (self.root / "AGENTS.md").unlink()
        self.write("docs/notes.md", "# 筆記\n")
        self.clean()

    def test_research_date_must_come_last(self):
        self.write("docs/research/2026-01-02-audit.md", "# 審計\n")
        self.red("docs/research/2026-01-02-audit.md：日期放在檔名最後")
        (self.root / "docs/research/2026-01-02-audit.md").rename(self.root / "docs/research/audit-2026-01-02.md")
        self.clean()

    def test_facts_file_needs_a_facts_section(self):
        self.write("docs/research/facts-rime.md", "# 事實：Rime\n\n## 清單\n\n- 沒有編號。\n")
        self.red("docs/research/facts-rime.md：facts- 開頭的檔要有〈事實〉段")


class BudgetTest(Repo):
    def test_over_budget(self):
        for rel, limit in m.BUDGETS.items():
            with self.subTest(rel):
                self.setUp()
                base = (self.root / rel).read_text(encoding="utf-8") if (self.root / rel).is_file() else "# 文件\n提到 progress.md、roadmap.md、decisions.md。\n"
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
        for rel in (m.BRIEF, m.ARCHITECTURE):
            for text in ("照 M1 票 12 的做法", "（票3）"):
                with self.subTest(rel=rel, text=text):
                    self.setUp()
                    self.write(rel, f"# 文件\n\n## 1. 節\n\n- 這一條{text}。\n")
                    self.red(f"{rel}:5：寫了票號")

    def test_other_wording_is_fine(self):
        text = "# 文件\n\n## 1. 節\n\n- 拆票後以票為準；M0 的第一張票接上；門票 3 張不是票號的寫法也不要用。\n\n```\n票 12\n```\n"
        self.write(m.BRIEF, text.replace("門票 3 張不是票號的寫法也不要用", "見 ADR 0003、事實 B3"))
        self.write(m.ARCHITECTURE, text.replace("門票 3 張不是票號的寫法也不要用", "見 ADR 0003、事實 B3"))
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
        for text in ("// 見 plan §3.2", "# brief §4 的規則", "/* docs/plan.md § 11 */", "// ARCHITECTURE.md §2"):
            with self.subTest(text):
                self.setUp()
                self.write("src/engine.rs", f"fn main() {{}}\n{text}\n")
                self.track()
                self.red("src/engine.rs:2：引用了 brief 或架構文檔的章節號")

    def test_citing_an_adr_or_a_fact_is_fine(self):
        self.write("src/engine.rs", "// ADR 0003、事實 B3、architecture〈依賴規則〉；plan 與 brief 兩個字本身不算；§ 單獨出現也不算\n")
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
        self.row("docs-cleanup 文件瘦身")
        self.clean()

    def test_milestone_without_acceptance_ticket(self):
        (self.root / ".scratch/m1/issues/02-m1-acceptance.md").rename(self.root / ".scratch/m1/issues/02-m1-wrap-up.md")
        self.red("沒有驗收票")

    def test_a_close_ticket_counts_as_the_acceptance_ticket(self):
        (self.root / ".scratch/m1/issues/02-m1-acceptance.md").rename(self.root / ".scratch/m1/issues/02-m1-close.md")
        self.clean()

    def test_effort_that_is_not_a_milestone_needs_no_acceptance_ticket(self):
        self.write(".scratch/docs-cleanup/spec.md", SPEC)
        self.write(".scratch/docs-cleanup/issues/01-trim.md", TICKET)
        self.row("docs-cleanup 文件瘦身")
        self.clean()

    def test_decimal_milestone_needs_one(self):
        self.write(".scratch/m1.5/spec.md", SPEC)
        self.write(".scratch/m1.5/issues/01-x.md", TICKET)
        self.row("M1.5 插入的")
        self.red(".scratch/m1.5/issues/：沒有驗收票")

    def test_directory_with_tickets_missing_from_the_roadmap(self):
        self.write(".scratch/docs-cleanup/spec.md", SPEC)
        self.write(".scratch/docs-cleanup/issues/01-trim.md", TICKET)
        self.red(".scratch/docs-cleanup/：docs/roadmap.md 的里程碑表沒有列它")
        self.row("`docs-cleanup`")
        self.clean()

    def test_how_the_roadmap_row_is_worded_does_not_matter(self):
        self.sub("docs/roadmap.md", "| M1 核心 | 第一個功能 |", "| M1 換了名字的核心（第二版） | 改寫過的目標 |")
        self.sub("docs/roadmap.md", "| M2 介面 | 畫面 | brief §4 | 未開工 |\n", "")
        self.clean()

    def test_without_a_roadmap_table_the_listing_is_not_checked(self):
        self.sub("docs/roadmap.md", "## 里程碑", "## 階段")
        self.assertEqual(m.run(self.root), ["docs/roadmap.md：缺〈里程碑〉段"])

    def test_directory_without_issues_is_ignored(self):
        self.write(".scratch/notes/draft.md", "隨手記")
        self.clean()

    def test_ticket_without_acceptance_criteria(self):
        for old, new in (("## 驗收\n\n- [ ] 條件\n", "- [ ] 條件\n"), ("- [ ] 條件\n", "條件寫成一句話。\n"), ("## 驗收", "## Acceptance criteria")):
            with self.subTest(old=old, new=new):
                self.write(".scratch/m1/issues/01-first.md", TICKET.replace(old, new))
                self.red("m1/issues/01-first.md：要有 `## 驗收` 段")

    def test_how_the_criteria_are_ticked_and_what_else_the_ticket_holds_do_not_matter(self):
        self.write(".scratch/m1/issues/01-first.md", TICKET.replace("- [ ] 條件\n", "說明。\n\n* [x] 條件\n  - [ ] 子項\n").replace("## What to build", "## 為什麼"))
        self.clean()

    def test_tickets_of_a_closed_milestone_need_no_criteria(self):
        self.write(".scratch/m0/spec.md", SPEC)
        self.write(".scratch/m0/issues/01-m0-acceptance.md", "# 01\n\n**Status:** done\n\n- [x] 舊格式沒有驗收段\n")
        self.clean()
        self.sub("docs/roadmap.md", "已驗收，封存在", "未開工，還沒做完，原本寫封存在")
        self.red("m0/issues/01-m0-acceptance.md：要有 `## 驗收` 段")

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
                self.sub(".scratch/m1/issues/01-first.md", "## Comments\n", "## Comments\n\n- code-review 沒處理的發現。\n\nSession 紀錄：2026-01-04 閘門就位。\n決定：改用另一個套件（使用者同意）。\n")
                self.clean()

    def test_session_note_needs_a_date(self):
        for note in ("Session 紀錄：閘門就位。", "Session 紀錄：1 月 4 日閘門就位。", "Session 紀錄：2026-01-04"):
            with self.subTest(note):
                self.write(".scratch/m1/issues/01-first.md", TICKET.replace("ready-for-agent", "done") + f"\n{note}\n")
                self.red("01-first.md：做完的票")
        self.write(".scratch/m1/issues/01-first.md", TICKET.replace("ready-for-agent", "done") + "\n隨便一句。\nSession 紀錄：2026-01-04 閘門就位，細節見上。\n")
        self.clean()

    def test_decision_line_on_a_done_ticket_has_a_length_limit(self):
        done = TICKET.replace("ready-for-agent", "done") + "\nSession 紀錄：2026-01-04 做完。\n"
        self.write(".scratch/m1/issues/01-first.md", done + "決定：" + "長" * 149 + "（Agent 定）\n")
        self.red("01-first.md：「決定：」那一行 161 字元")
        self.write(".scratch/m1/issues/01-first.md", done + "決定：" + "長" * 148 + "（Agent 定）\n" + "別的行不限長度" * 40 + "\n")
        self.clean()

    def test_decision_line_on_a_done_ticket_needs_one_decider(self):
        self.sub(".scratch/m1/issues/01-first.md", "Status: ready-for-agent", "Status: done")
        for line in ("決定：改用另一個套件。", "決定：改用另一個套件（使用者定）（Agent 定）。"):
            with self.subTest(line):
                self.write(".scratch/m1/issues/01-first.md", TICKET.replace("ready-for-agent", "done") + f"\nSession 紀錄：2026-01-04 做完。\n{line}\n")
                self.red("01-first.md：「決定：」那一行要標一個決定者")
        self.write(".scratch/m1/issues/01-first.md", TICKET.replace("ready-for-agent", "done") + "\nSession 紀錄：2026-01-04 做完。\n- 這一行提到決定：但不是開頭。\n")
        self.clean()

    def test_with_a_changelog_a_done_ticket_says_what_changed_for_the_user(self):
        done = TICKET.replace("ready-for-agent", "done") + "\nSession 紀錄：2026-01-04 做完。\n"
        self.write(".scratch/m1/issues/01-first.md", done)
        self.clean()  # 沒有 CHANGELOG.md 的 repo 不要求
        self.write("CHANGELOG.md", "# Changelog\n\n## [Unreleased]\n")
        self.red("01-first.md：做完的票要在 `## Comments` 之後留至少一行「變更：」")
        for line in ("變更：新增搜尋", "變更：Add｜搜尋｜可以搜。", "變更：Added｜搜尋", "變更：Added｜｜可以搜。", "變更：Added|搜尋|可以搜。"):
            with self.subTest(line):
                self.write(".scratch/m1/issues/01-first.md", done + line + "\n")
                self.red("01-first.md：「變更：」那一行寫成")
        for lines in ("變更：無", "變更：Added｜搜尋｜可以搜。\n變更：Fixed｜候選列｜整季缺時問得到。"):
            with self.subTest(lines):
                self.write(".scratch/m1/issues/01-first.md", done + lines + "\n- 這一行提到變更：但不是開頭。\n")
                self.clean()

    def test_session_note_before_comments_does_not_count(self):
        self.sub(".scratch/m1/issues/01-first.md", "Status: ready-for-agent", "Status: done")
        self.sub(".scratch/m1/issues/01-first.md", "## What to build\n", "## What to build\n\nSession 紀錄：2026-01-04 寫錯地方。\n")
        self.red("01-first.md：做完的票")

    def test_done_tickets_outside_the_active_milestone_are_not_checked(self):
        self.write(".scratch/m0/spec.md", SPEC)
        self.write(".scratch/m0/issues/01-old.md", TICKET.replace("ready-for-agent", "done"))
        self.write(".scratch/m0/issues/02-m0-acceptance.md", TICKET.replace("ready-for-agent", "done"))
        self.write(".scratch/docs-cleanup/spec.md", SPEC)
        self.write(".scratch/docs-cleanup/issues/01-trim.md", TICKET.replace("ready-for-agent", "done"))
        self.row("docs-cleanup 文件瘦身")
        self.clean()



class ChangelogTest(Repo):
    GOOD = ("# Changelog\n\n說明裡的清單不算條目：\n\n- 隨便一行\n\n## [Unreleased]\n\n升級說明可以是段落。\n\n### Added\n\n"
            "- **搜尋**：可以搜作品，\n  續行縮排。\n  - 子項不查。\n\n### Fixed\n\n- **候選列**: 半形冒號也收。\n\n"
            "## [0.1.0] - 2026-01-02\n\n- 已發版的段落只查標題\n\n### Changed\n\n- 舊條目不必有功能名\n\n## [0.0.1-rc1] - 2026-01-01 [YANKED]\n")

    def test_a_repo_without_a_changelog_is_not_checked(self):
        self.clean()

    def test_keep_a_changelog_layout_passes(self):
        self.write("CHANGELOG.md", self.GOOD)
        self.clean()

    def test_unreleased_section_is_required(self):
        self.write("CHANGELOG.md", self.GOOD.replace("## [Unreleased]", "## [0.2.0] - 2026-01-03"))
        self.red("CHANGELOG.md：缺 `## [Unreleased]`")

    def test_version_headings(self):
        for heading in ("## 0.1.0 - 2026-01-02", "## [0.1.0]", "## [0.1.0] 2026-01-02", "## 未發版"):
            with self.subTest(heading):
                self.write("CHANGELOG.md", self.GOOD.replace("## [0.1.0] - 2026-01-02", heading))
                self.red("CHANGELOG.md:21：`##` 標題寫成")

    def test_categories_are_the_six_of_keep_a_changelog(self):
        self.write("CHANGELOG.md", self.GOOD.replace("### Fixed", "### 修正"))
        self.red("CHANGELOG.md:17：分類只能是")
        self.write("CHANGELOG.md", self.GOOD.replace("### Changed", "### Improved"))
        self.red("CHANGELOG.md:25：分類只能是")

    def test_unreleased_entries_name_a_feature_under_a_category(self):
        for entry in ("- 修了搜尋", "- **搜尋** 可以搜", "- 搜尋：可以搜"):
            with self.subTest(entry):
                self.write("CHANGELOG.md", self.GOOD.replace("- **搜尋**：可以搜作品，", entry))
                self.red("CHANGELOG.md:13：條目寫成 `- **<功能>**：<一句>`")
        self.write("CHANGELOG.md", self.GOOD.replace("升級說明可以是段落。", "- **搜尋**：還沒有分類。"))
        self.red("CHANGELOG.md:9：條目要放在某個分類底下")

    def test_code_blocks_are_skipped(self):
        self.write("CHANGELOG.md", self.GOOD.replace("升級說明可以是段落。", "```\n## 隨便\n### 隨便\n- 隨便\n```"))
        self.clean()


if __name__ == "__main__":
    unittest.main()
