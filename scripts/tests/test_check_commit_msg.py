"""check_commit_msg.py 的測試。在 plugin 裡腳本在 ../scripts/，複製進專案後在上一層；兩種位置都找。

    python -m unittest discover -s <這個資料夾>
"""

import contextlib
import importlib.util
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

# pre-commit hook 裡 git 會設絕對路徑的 GIT_DIR、GIT_INDEX_FILE：在暫存目錄跑的 git 繼承它們，就把假檔案寫進外面那個 repo 的
# index、把它的 config 改成 core.bare = true。專案常用自己的 hook 跑這些測試，所以由測試自己清；測試只碰自己建的暫存 repo。
for _name in [n for n in os.environ if n.startswith("GIT_")]:
    del os.environ[_name]

HERE = Path(__file__).resolve().parent
SCRIPT = next(p for p in (HERE.parent / "scripts" / "check_commit_msg.py", HERE.parent / "check_commit_msg.py") if p.is_file())
spec = importlib.util.spec_from_file_location("check_commit_msg", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class SubjectTest(unittest.TestCase):
    def ok(self, subject):
        self.assertEqual(m.problems(subject), [], subject)

    def bad(self, subject):
        self.assertNotEqual(m.problems(subject), [], subject)

    def test_accepts_conventional_subjects(self):
        for s in ("feat: add search", "fix(parser): keep the last token", "feat(api)!: drop v1 routes",
                  "docs: 說明安裝步驟", "chore: bump 3 dependencies", "refactor(core): x" + "y" * 50):
            self.ok(s)

    def test_accepts_git_default_messages(self):
        self.ok("Merge branch 'main' into t04")
        self.ok('Revert "feat: add search"')
        self.ok("Merge branch 'a-very-long-branch-name-that-goes-on-and-on-past-the-seventy-two-character-limit'")

    def test_rejects_unknown_type_or_shape(self):
        for s in ("add search", "feature: add search", "feat:add search", "feat (api): add", "feat():  add", "merge: ticket 01 x", ""):
            self.bad(s)

    def test_rejects_capitalised_subject(self):
        self.bad("feat: Add search")
        self.bad("fix(parser): Keep the last token")

    def test_rejects_trailing_period(self):
        self.bad("feat: add search.")
        self.ok("feat: add search for v1.2")

    def test_length_limit_is_72(self):
        self.ok("feat: " + "a" * 66)
        self.bad("feat: " + "a" * 67)

    def test_type_inside_scope_or_subject_is_not_a_type(self):
        self.bad("(feat): add search")
        self.bad("add feat: search")


class FileTest(unittest.TestCase):
    def run_file(self, text):
        with tempfile.TemporaryDirectory() as d, contextlib.redirect_stderr(io.StringIO()):
            p = Path(d) / "MSG"
            p.write_text(text, encoding="utf-8")
            return m.main([str(p)])

    def test_reads_the_first_non_comment_line(self):
        self.assertEqual(self.run_file("# 請輸入 commit message\n\nfeat: add search\n\nBody Starts With A Capital.\n"), 0)

    def test_body_does_not_rescue_a_bad_subject(self):
        self.assertEqual(self.run_file("Add search\n\nfeat: add search\n"), 1)

    def test_subject_flag(self):
        self.assertEqual(m.main(["--subject", "fix: handle empty input"]), 0)
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(m.main(["--subject", "Fix stuff"]), 1)


@unittest.skipUnless(shutil.which("git"), "要 git")
class HookTest(unittest.TestCase):
    """在真的 repo 裝上 commit-msg hook：一般 commit 照規則擋，合併票的訊息放行。"""

    def setUp(self):
        self.repo = Path(tempfile.mkdtemp(prefix="commit-msg-hook-")).resolve()
        self.addCleanup(shutil.rmtree, self.repo, ignore_errors=True)
        self.git("init", "-q", "-b", "main")
        hooks = self.repo / "hooks"
        hooks.mkdir()
        hook = hooks / "commit-msg"
        hook.write_text('#!/bin/sh\nexec "%s" "%s" "$1"\n' % (sys.executable, SCRIPT), encoding="utf-8")
        hook.chmod(0o755)
        self.git("config", "core.hooksPath", str(hooks))
        self.commit("a.txt", "docs: start")

    def git(self, *args, check=True):
        env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.com", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.com")
        return subprocess.run(["git", "-C", str(self.repo), *args], env=env, capture_output=True, text=True, check=check)

    def commit(self, name, message, check=True):
        (self.repo / name).write_text(name, encoding="utf-8")
        self.git("add", name)
        return self.git("commit", "-q", "-m", message, check=check)

    def branch_with_a_commit(self):
        self.git("checkout", "-q", "-b", "t01")
        self.commit("b.txt", "feat: add b")
        self.git("checkout", "-q", "main")

    def test_ticket_merge_message_is_accepted(self):
        self.branch_with_a_commit()
        r = self.git("merge", "--no-ff", "-m", "merge: ticket 01 b", "t01", check=False)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.git("log", "-1", "--format=%s").stdout.strip(), "merge: ticket 01 b")

    def test_same_message_outside_a_merge_is_rejected(self):
        r = self.commit("c.txt", "merge: ticket 01 b", check=False)
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.git("log", "-1", "--format=%s").stdout.strip(), "docs: start")

    def test_ordinary_commits_still_follow_the_rule_after_a_merge(self):
        self.branch_with_a_commit()
        self.git("merge", "--no-ff", "-m", "merge: ticket 01 b", "t01")
        self.assertNotEqual(self.commit("d.txt", "Add d", check=False).returncode, 0)
        self.assertEqual(self.commit("d.txt", "feat: add d").returncode, 0)


if __name__ == "__main__":
    unittest.main()
