"""docs_moved_lines.py 的測試：搬走的行都在才過，少一行就紅，無關的改動不紅。
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
SCRIPT = next(p for p in (HERE.parent / "scripts" / "docs_moved_lines.py", HERE.parent / "docs_moved_lines.py") if p.is_file())
spec = importlib.util.spec_from_file_location("docs_moved_lines", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

PROGRESS = "# 進度\n\n## Session 紀錄\n\n| 日期 | 票 | 結果 | 下一步 |\n| --- | --- | --- | --- |\n| 2026-01-02 | M0 01 | 做完，見 [票](../.scratch/m0/issues/01-x.md) | `/implement 02` |\n| 2026-01-03 | M0 02 | 驗收 | `/1morr:checkpoint M0` |\n"
DECISIONS = "# 決策\n\n## 紀錄\n\n- 2026-01-02 M0（使用者定）：用 Rust。\n- 2026-01-03 M0 票 01（Agent 定）：用 X。\n"


@unittest.skipUnless(shutil.which("git"), "要 git")
class MovedLinesTest(unittest.TestCase):
    def setUp(self):
        self.repo = Path(tempfile.mkdtemp(prefix="moved-lines-")).resolve()
        self.addCleanup(shutil.rmtree, self.repo, ignore_errors=True)
        self.write("docs/progress.md", PROGRESS)
        self.write("docs/decisions.md", DECISIONS)
        self.git("init", "-q", "-b", "main")
        self.git("add", "-A")
        self.git("commit", "-qm", "docs: before")
        # 封存：兩個檔的內容搬到深一層的封存檔，連結多一層 ../
        rows = [l for l in PROGRESS.split("\n") if l.startswith("| 2026")]
        log = [l for l in DECISIONS.split("\n") if l.startswith("- ")]
        self.archive = "# M0\n\n## Session 紀錄\n\n| 日期 | 票 | 結果 | 下一步 |\n|:---|:---|:---|:---|\n" + "\n".join(rows).replace("](../", "](../../") + "\n\n## 決定\n\n" + "\n".join(log) + "\n"
        self.write("docs/archive/M0.md", self.archive)
        self.write("docs/progress.md", PROGRESS.replace(rows[0] + "\n", "").replace(rows[1] + "\n", "| 2026-01-04 | M1 準備 | 封存了 | `/1morr:checkpoint M0` |\n"))
        self.write("docs/decisions.md", DECISIONS.replace(log[0] + "\n", "").replace(log[1] + "\n", ""))

    def write(self, rel, text):
        p = self.repo / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")

    def git(self, *args):
        env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.com", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.com")
        subprocess.run(["git", "-C", str(self.repo), "-c", "core.hooksPath=/dev/null", *args], env=env, check=True, capture_output=True)

    def run_it(self, *args):
        out, cwd = io.StringIO(), os.getcwd()
        os.chdir(self.repo)
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
                code = m.main(list(args))
        finally:
            os.chdir(cwd)
        return code, out.getvalue()

    def test_everything_moved_is_found(self):
        self.assertEqual(self.run_it("HEAD", "docs/progress.md", "docs/decisions.md", "--", "docs/archive/M0.md"),
                         (0, "刪 4 行，找到 4，遺失 0\n"))

    def test_a_lost_row_and_a_reworded_decision_are_listed(self):
        self.write("docs/archive/M0.md", self.archive.replace("| 2026-01-03 | M0 02 | 驗收 | `/1morr:checkpoint M0` |\n", "").replace("用 Rust。", "用 Rust 寫。"))
        code, out = self.run_it("HEAD", "docs/progress.md", "docs/decisions.md", "--", "docs/archive/M0.md")
        self.assertEqual(code, 1)
        lines = out.strip().split("\n")
        self.assertEqual((lines[0], sorted(lines[1:])), ("刪 4 行，找到 2，遺失 2", ["  遺失：- 2026-01-02 M0（使用者定）：用 Rust。", "  遺失：| 2026-01-03 | M0 02 | 驗收 | `/1morr:checkpoint M0` |"]))

    def test_indentation_separator_rows_and_order_do_not_matter(self):
        lines = [l for l in self.archive.split("\n") if l.strip()]
        self.write("docs/archive/M0.md", "\n\n".join("  " + l for l in reversed(lines)) + "\n")
        self.assertEqual(self.run_it("HEAD", "docs/progress.md", "docs/decisions.md", "--", "docs/archive/M0.md")[0], 0)

    def test_several_destinations_count_together(self):
        self.write("docs/archive/M0-decisions.md", "## 決定\n\n" + "\n".join(l for l in DECISIONS.split("\n") if l.startswith("- ")) + "\n")
        self.write("docs/archive/M0.md", self.archive.split("## 決定")[0])
        self.assertEqual(self.run_it("HEAD", "docs/progress.md", "docs/decisions.md", "--", "docs/archive/M0.md", "docs/archive/M0-decisions.md")[0], 0)

    def test_wrong_usage(self):
        for args in ((), ("HEAD", "docs/progress.md"), ("HEAD", "--", "docs/archive/M0.md"), ("HEAD", "docs/progress.md", "--")):
            self.assertEqual(self.run_it(*args)[0], 2)


if __name__ == "__main__":
    unittest.main()
