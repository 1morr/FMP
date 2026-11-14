"""印出一個里程碑各張票留在 `## Comments` 之後的紀錄：`Session 紀錄：`、`決定：`、`變更：`。票是這些紀錄唯一的來源。

    python ticket_notes.py <里程碑的目錄名，例如 m0> [repo 根目錄，預設目前目錄]
    python ticket_notes.py <里程碑的目錄名> [repo 根目錄] --archive
    python ticket_notes.py <里程碑的目錄名> [repo 根目錄] --changelog

不加參數：每張留了紀錄的票一段，第一行 `<里程碑> <票號> <標題>（<日期>）`，底下每條紀錄縮排兩格。做票前用它看先前的票定過什麼。
`--archive`：里程碑封存時用，印兩段照貼進 `docs/archive/<里程碑>.md`：
  `## Session 紀錄` 底下是表格的列 `| <日期> | <里程碑> <票號> | <做了什麼> | |`，接在搬過去的那張表後面；
  `## 決定` 底下是 `- <日期> <里程碑> 票 <票號>（<決定者>）：<決定>`。
`--changelog`：里程碑驗收時用，印要併進 `CHANGELOG.md`〈[Unreleased]〉的條目：依 Keep a Changelog 的分類分段
  （`### Added` …），每條 `- **<功能>**：<一句>`，來自票上的 `變更：<分類>｜<功能>｜<一句>`；`變更：無` 與格式不對的行不印。
日期取 `Session 紀錄：<YYYY-MM-DD> …` 開頭的那一個，同一張票的決定用同一天；沒寫日期的舊票用票檔最後一次 commit 的日期，
不在 git 裡就用檔案的修改日期。里程碑寫成目錄名大寫（`m1.5` → `M1.5`），不是里程碑的工作照目錄名。依日期、票號排序。
找不到 `.scratch/<目錄名>/issues/` exit 1。只用標準函式庫。
"""

import datetime
import re
import subprocess
import sys
from pathlib import Path

SESSION_NOTE, DECISION_NOTE = "Session 紀錄：", "決定："
CHANGE_NOTE = "變更："
KINDS = ("Added", "Changed", "Deprecated", "Removed", "Fixed", "Security")
CHANGE = re.compile(r"^變更：(%s)｜([^｜]+)｜(.+)$" % "|".join(KINDS))
COMMENTS = "## Comments"
DATE = re.compile(r"^(\d{4}-\d{2}-\d{2})\s+(.*)$")
DECIDER = re.compile("（(使用者定|使用者同意|Agent 定)）")
MILESTONE_DIR = re.compile(r"^m\d+(\.\d+)?$", re.I)
NUMBER = re.compile(r"^(\d+[a-z]?)-")


def label_of(name: str) -> str:
    return name.upper() if MILESTONE_DIR.match(name) else name


def committed_on(path: Path) -> str:
    """票檔最後一次 commit 的日期；不在 git 裡就是檔案的修改日期。"""
    try:
        r = subprocess.run(["git", "-C", str(path.parent), "log", "-1", "--format=%as", "--", path.name],
                           capture_output=True, text=True, timeout=10)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return datetime.date.fromtimestamp(path.stat().st_mtime).isoformat()


def ticket_notes(path: Path) -> dict:
    """一張票的紀錄：{number, title, date, sessions: [一句], decisions: [(一句, 決定者)], changes: [(分類, 功能, 一句)]}。
    只讀 `## Comments` 之後的行。"""
    text = path.read_text(encoding="utf-8")
    title = next((l.lstrip("# ").strip() for l in text.split("\n") if l.startswith("# ")), path.stem)
    number = NUMBER.match(path.name)
    out = {"number": number.group(1) if number else path.stem, "title": re.sub(r"^\S+[:：]\s*", "", title), "date": "",
           "sessions": [], "decisions": [], "changes": []}
    for line in text.split("\n" + COMMENTS, 1)[1].split("\n") if "\n" + COMMENTS in text else []:
        if line.startswith(SESSION_NOTE):
            rest = line[len(SESSION_NOTE):].strip()
            dated = DATE.match(rest)
            if dated:
                out["date"], rest = out["date"] or dated.group(1), dated.group(2)
            out["sessions"].append(rest)
        elif line.startswith(DECISION_NOTE):
            rest = line[len(DECISION_NOTE):].strip()
            decider = DECIDER.search(rest)
            out["decisions"].append((DECIDER.sub("", rest).strip(), decider.group(1) if decider else ""))
        elif CHANGE.match(line.strip()):
            out["changes"].append(tuple(part.strip() for part in CHANGE.match(line.strip()).groups()))
    if not out["date"] and (out["sessions"] or out["decisions"]):
        out["date"] = committed_on(path)
    return out


def notes(root: Path, name: str) -> list:
    """里程碑裡留了紀錄的票，依日期、票號排序。"""
    found = [ticket_notes(p) for p in sorted((root / ".scratch" / name / "issues").glob("*.md"))]
    return sorted((t for t in found if t["sessions"] or t["decisions"] or t["changes"]), key=lambda t: (t["date"], t["number"]))


def archive(root: Path, name: str) -> tuple:
    """(session 表的列, 〈決定〉的條目)，照貼進封存檔。"""
    label, rows, decided = label_of(name), [], []
    for t in notes(root, name):
        for said in t["sessions"]:
            rows.append("| %s | %s %s | %s | |" % (t["date"], label, t["number"], said.replace("|", "\\|")))
        for said, decider in t["decisions"]:
            decided.append("- %s %s 票 %s%s：%s" % (t["date"], label, t["number"], f"（{decider}）" if decider else "", said))
    return rows, decided


def changelog(root: Path, name: str) -> list:
    """要併進 CHANGELOG.md〈[Unreleased]〉的行：有條目的分類各一段，段與段之間空一行。"""
    found = [change for t in notes(root, name) for change in t["changes"]]
    out = []
    for kind in KINDS:
        entries = [f"- **{feature}**：{said}" for k, feature, said in found if k == kind]
        if entries:
            out += ([""] if out else []) + [f"### {kind}", *entries]
    return out


def main(argv) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    flags = [a for a in argv if a.startswith("--")]
    args = [a for a in argv if not a.startswith("--")]
    if not 1 <= len(args) <= 2 or len(flags) > 1 or any(f not in ("--archive", "--changelog") for f in flags):
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    name, root = args[0], Path(args[1]) if len(args) == 2 else Path.cwd()
    if not (root / ".scratch" / name / "issues").is_dir():
        print(f"找不到 .scratch/{name}/issues/", file=sys.stderr)
        return 1
    if flags == ["--changelog"]:
        print("\n".join(changelog(root, name)))
        return 0
    if flags:
        rows, decided = archive(root, name)
        print("\n".join(["## Session 紀錄", *rows, "", "## 決定", *decided]))
        return 0
    found = notes(root, name)
    for t in found:
        print(f"{label_of(name)} {t['number']} {t['title']}（{t['date']}）")
        for said in t["sessions"]:
            print(f"  {SESSION_NOTE}{said}")
        for said, decider in t["decisions"]:
            print(f"  {DECISION_NOTE}{said}" + (f"（{decider}）" if decider else ""))
        for change in t["changes"]:
            print(f"  {CHANGE_NOTE}" + "｜".join(change))
    if not found:
        print(f"{label_of(name)} 的票還沒有留紀錄")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
