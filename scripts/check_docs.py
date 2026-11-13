"""檢查 docs/progress.md、docs/decisions.md、docs/roadmap.md、里程碑 spec 與票的格式。

    python check_docs.py [repo 根目錄，預設目前目錄]

全部通過 exit 0；否則每條違規印一行到 stderr、exit 1。規則：
  progress.md
    - `##` 段依序各一次：寫法與封存、Session 紀錄
    - 〈Session 紀錄〉整段是一張表（表外沒有別的字），每列不超過 200 字元
    - 最後一列的「下一步」給得出指令（含 `/…` 的行內程式碼），或以「等使用者：」開頭
  decisions.md
    - 有〈紀錄〉段，每條一行、以 `- YYYY-MM-DD ` 開頭、不超過 200 字元、標一個決定者：（使用者定）（使用者同意）（Agent 定）
  roadmap.md
    - 有〈里程碑〉段，裡面的表有「狀態」欄，狀態以「進行中」開頭的最多一個
  大小與寫法
    - 字元上限（Python `len`）：AGENTS.md 8,000、ARCHITECTURE.md 15,000、docs/progress.md 20,000、docs/design-brief.md 30,000；不存在的檔不查
    - docs/design-brief.md、ARCHITECTURE.md 不寫票號（「票 12」「票12」）；程式碼區塊裡的不算
  docs/ 的結構
    - docs/ 第一層的每個檔與資料夾，名字都出現在指令檔（AGENTS.md，沒有就看 CLAUDE.md）裡；兩個都沒有就不查
    - docs/research/ 第一層：檔名裡有日期的，日期在最後（`<主題>-YYYY-MM-DD`）；`facts-*.md` 有〈事實〉段
  程式碼
    - git 追蹤的檔，除了 Markdown、docs/、.scratch/ 與本腳本和它的測試，不引用 brief 或架構文檔的章節號（「brief §4」「architecture §3」「plan §3.2」）；
      不是 git repo 就不查
  .scratch/
    - 有 issues/ 的目錄要有 spec.md，`##` 段含：目標、範圍、共同規則、驗收、票序（標題後面可以加括號說明）
    - 里程碑目錄（m 加數字，例如 m0、m1.5）的 issues/ 要有一張 -acceptance.md 結尾的驗收票（早期專案叫收尾票的 -close.md 也算）
    - 每張票在第一個 `##` 之前有一行 `Status:`
    - roadmap.md 標「進行中」的里程碑（表的第一欄第一個詞，小寫後就是目錄名），Status 是 done 的票在 `## Comments` 之後
      有一行以 `Session 紀錄：` 開頭，以 `決定：` 開頭的行都標一個決定者；spec 的〈驗收〉底下有 `### 使用者試`
只用標準函式庫。
"""

import re
import subprocess
import sys
from pathlib import Path

PROGRESS = "docs/progress.md"
ROADMAP = "docs/roadmap.md"
DECISIONS = "docs/decisions.md"
BRIEF, ARCHITECTURE = "docs/design-brief.md", "ARCHITECTURE.md"
BUDGETS = {"AGENTS.md": 8000, ARCHITECTURE: 15000, PROGRESS: 20000, BRIEF: 30000}
TICKET_NUMBER = re.compile(r"票\s*\d")
SECTION_REF = re.compile(r"(?:architecture|plan|brief)(?:\.md)?\s*§\s*\d", re.I)
NOT_CODE = ("docs/", ".scratch/", "scripts/check_docs.py", "scripts/tests/test_check_docs.py")
MAX_SCANNED_BYTES = 1_000_000
INSTRUCTIONS = ("AGENTS.md", "CLAUDE.md")
DATED = re.compile(r"\d{4}-\d{2}-\d{2}")
DATED_LAST = re.compile(r"-\d{4}-\d{2}-\d{2}$")
FACTS = "事實"
SCRATCH = ".scratch"
MILESTONES, SESSIONS, LOG = "里程碑", "Session 紀錄", "紀錄"
STATE = "狀態"
PROGRESS_SECTIONS = ("寫法與封存", SESSIONS)
SPEC_SECTIONS = ("目標", "範圍", "共同規則", "驗收", "票序")
MAX_CHARS = 200
WAITING = "等使用者："
ACTIVE = "進行中"

COMMAND = re.compile(r"`/[^`\s][^`]*`")
DEVIATION = re.compile(r"^- \d{4}-\d{2}-\d{2} \S")
DECIDERS = ("使用者定", "使用者同意", "Agent 定")
DECIDER = re.compile("（(?:%s)）" % "|".join(DECIDERS))
DECIDER_LIST = "".join(f"（{d}）" for d in DECIDERS)
MILESTONE_DIR = re.compile(r"^m\d+(\.\d+)?$")
STATUS = re.compile(r"^\**Status:?\**:?\s*\S", re.I)
DONE = re.compile(r"^\**Status:?\**:?\s*done\b", re.I)
SESSION_NOTE, DECISION_NOTE = "Session 紀錄：", "決定："
ACCEPTANCE, USER_TRIAL = "驗收", "使用者試"
ACCEPTANCE_SUFFIXES = ("-acceptance.md", "-close.md")
CELL_SPLIT = re.compile(r"(?<!\\)\|")


def sections(text: str) -> list:
    """[(標題, [(行號, 內容), …])]；程式碼區塊裡的 ## 不算標題，第一個 ## 之前的內容不屬於任何段。"""
    out, fenced = [], False
    for number, line in enumerate(text.split("\n"), 1):
        if line.lstrip().startswith("```"):
            fenced = not fenced
        if not fenced and line.startswith("## "):
            out.append((line[3:].strip(), []))
        elif out:
            out[-1][1].append((number, line))
    return out


def cells(row: str) -> list:
    return [c.strip() for c in CELL_SPLIT.split(row.strip().strip("|"))]


def is_row(line: str) -> bool:
    return line.strip().startswith("|")


def is_separator(line: str) -> bool:
    return bool(re.fullmatch(r"\|?[\s:|-]+\|?", line.strip())) and "-" in line


def table(lines) -> tuple:
    """(表頭欄位, [(行號, 欄位), …])；沒有表就是 ([], [])。"""
    rows = [(n, l) for n, l in lines if is_row(l)]
    if not rows:
        return [], []
    return cells(rows[0][1]), [(n, cells(l)) for n, l in rows[1:] if not is_separator(l)]


def check_progress(text: str) -> list:
    out = []
    secs = sections(text)
    titles = [t for t, _ in secs]
    order = "、".join(f"〈{t}〉" for t in PROGRESS_SECTIONS)
    for title in PROGRESS_SECTIONS:
        if titles.count(title) == 0:
            out.append(f"{PROGRESS}：缺〈{title}〉段。## 段依序是{order}")
        elif titles.count(title) > 1:
            out.append(f"{PROGRESS}：〈{title}〉段出現 {titles.count(title)} 次，只能一次")
    known = [t for t in titles if t in PROGRESS_SECTIONS]
    if sorted(set(known), key=PROGRESS_SECTIONS.index) != list(dict.fromkeys(known)):
        out.append(f"{PROGRESS}：## 段的順序不對，依序是{order}")
    extra = [t for t in titles if t not in PROGRESS_SECTIONS]
    if extra:
        out.append(f"{PROGRESS}：多了〈{'〉〈'.join(extra)}〉段。細節放票與 spec，這裡只有{order}")
    by_title = {}
    for title, lines in secs:
        by_title.setdefault(title, lines)

    if SESSIONS in by_title:
        lines = by_title[SESSIONS]
        for n, l in lines:
            if l.strip() and not is_row(l):
                out.append(f"{PROGRESS}:{n}：〈{SESSIONS}〉整段是一張表，表外不放別的字")
            if len(l) > MAX_CHARS:
                out.append(f"{PROGRESS}:{n}：這一列 {len(l)} 字元，上限 {MAX_CHARS}。細節放票的 Comments")
        head, rows = table(lines)
        if "下一步" not in head:
            out.append(f"{PROGRESS}：〈{SESSIONS}〉的表要有「下一步」欄")
        elif not rows:
            out.append(f"{PROGRESS}：〈{SESSIONS}〉沒有任何一列")
        else:
            n, last = rows[-1]
            step = last[head.index("下一步")] if len(last) > head.index("下一步") else ""
            if not (COMMAND.search(step) or step.startswith(WAITING)):
                out.append(f"{PROGRESS}:{n}：最後一列的「下一步」要給下一個 session 的完整指令（寫成 `/指令 …`），"
                           f"或以「{WAITING}」開頭")

    return out


def check_decisions(text: str) -> list:
    by_title = {}
    for title, lines in sections(text):
        by_title.setdefault(title, lines)
    if LOG not in by_title:
        return [f"{DECISIONS}：缺〈{LOG}〉段"]
    out = []
    for n, l in by_title[LOG]:
        if not l.strip():
            continue
        if not DEVIATION.match(l):
            out.append(f"{DECISIONS}:{n}：〈{LOG}〉每條一行，寫成「- YYYY-MM-DD <里程碑>（<決定者>）：…」")
        elif len(DECIDER.findall(l)) != 1:
            out.append(f"{DECISIONS}:{n}：這一條要標一個決定者：{DECIDER_LIST}")
        if len(l) > MAX_CHARS:
            out.append(f"{DECISIONS}:{n}：這一條 {len(l)} 字元，上限 {MAX_CHARS}。細節放票、brief、ADR，這裡連過去")
    return out


def active_milestones(text: str):
    """(進行中的列, 違規)：〈里程碑〉表裡狀態以「進行中」開頭的列。"""
    by_title = {}
    for title, lines in sections(text):
        by_title.setdefault(title, lines)
    if MILESTONES not in by_title:
        return [], [f"{ROADMAP}：缺〈{MILESTONES}〉段"]
    head, rows = table(by_title[MILESTONES])
    if STATE not in head:
        return [], [f"{ROADMAP}：〈{MILESTONES}〉的表要有「{STATE}」欄"]
    i = head.index(STATE)
    return [r for _, r in rows if len(r) > i and r[i].startswith(ACTIVE)], []


def check_roadmap(text: str) -> list:
    active, out = active_milestones(text)
    if len(active) > 1:
        out.append(f"{ROADMAP}：有 {len(active)} 個里程碑的狀態以「{ACTIVE}」開頭，最多一個")
    return out


def active_dirs(root: Path) -> set:
    """進行中里程碑的目錄名：表的第一欄第一個詞的小寫（`M1.5 媒體庫` → `m1.5`）。"""
    if not (root / ROADMAP).is_file():
        return set()
    active, _ = active_milestones((root / ROADMAP).read_text(encoding="utf-8"))
    return {r[0].split()[0].lower() for r in active if r and r[0].split()}


def check_budgets(root: Path) -> list:
    out = []
    for rel, limit in BUDGETS.items():
        if (root / rel).is_file():
            size = len((root / rel).read_text(encoding="utf-8"))
            if size > limit:
                out.append(f"{rel}：{size} 字元，上限 {limit}（多 {size - limit}）。搬走或刪掉內容，不靠縮短措辭湊數")
    return out


def check_current_state(root: Path) -> list:
    """brief 與架構文檔只寫現況：票號留在票與 progress.md。"""
    out = []
    for rel in (BRIEF, ARCHITECTURE):
        if not (root / rel).is_file():
            continue
        fenced = False
        for n, line in enumerate((root / rel).read_text(encoding="utf-8").split("\n"), 1):
            if line.lstrip().startswith("```"):
                fenced = not fenced
            elif not fenced and TICKET_NUMBER.search(line):
                out.append(f"{rel}:{n}：寫了票號。這裡只寫現在的做法，要留證據就連到 ADR 或 docs/research/")
    return out


def check_layout(root: Path) -> list:
    out = []
    docs = root / "docs"
    guide = next((root / name for name in INSTRUCTIONS if (root / name).is_file()), None)
    if docs.is_dir() and guide is not None:
        text = guide.read_text(encoding="utf-8")
        for entry in sorted(docs.iterdir()):
            name = entry.name + ("/" if entry.is_dir() else "")
            if not entry.name.startswith(".") and name not in text:
                out.append(f"docs/{name}：{guide.name} 沒有提到它。在〈文件〉加一行說明它是什麼，或搬到 docs/legacy/、docs/archive/")
    research = docs / "research"
    for entry in sorted(research.iterdir()) if research.is_dir() else []:
        stem = entry.name if entry.is_dir() else entry.stem
        if DATED.search(stem) and not DATED_LAST.search(stem):
            out.append(f"docs/research/{entry.name}：日期放在檔名最後，寫成 <主題>-YYYY-MM-DD")
        if entry.is_file() and entry.name.startswith("facts-") and entry.suffix == ".md":
            if not any(t == FACTS for t, _ in sections(entry.read_text(encoding="utf-8"))):
                out.append(f"docs/research/{entry.name}：facts- 開頭的檔要有〈{FACTS}〉段，一條一個編號")
    return out


def tracked_files(root: Path) -> list:
    try:
        r = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], capture_output=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        return []
    return [f for f in r.stdout.decode("utf-8", "replace").split("\0") if f]


def check_code_refs(root: Path) -> list:
    """章節號只在文件與票裡用：程式碼引用了，節就搬不動。"""
    out = []
    for rel in tracked_files(root):
        if rel.lower().endswith(".md") or rel.startswith(NOT_CODE):
            continue
        p = root / rel
        if not p.is_file() or p.stat().st_size > MAX_SCANNED_BYTES:
            continue
        data = p.read_bytes()
        if b"\0" in data:
            continue
        for n, line in enumerate(data.decode("utf-8", "replace").split("\n"), 1):
            if SECTION_REF.search(line):
                out.append(f"{rel}:{n}：引用了 brief 或架構文檔的章節號。改引 ADR 編號、事實編號或節的標題")
    return out


def check_scratch(root: Path) -> list:
    out = []
    base = root / SCRATCH
    if not base.is_dir():
        return out
    active = active_dirs(root)
    for d in sorted(p for p in base.iterdir() if (p / "issues").is_dir()):
        rel = f"{SCRATCH}/{d.name}"
        spec = d / "spec.md"
        if not spec.is_file():
            out.append(f"{rel}/：有票卻沒有 spec.md，里程碑開工的第一步是寫 spec")
        else:
            secs = [(re.split(r"[（(]", t)[0].strip(), lines) for t, lines in sections(spec.read_text(encoding="utf-8"))]
            titles = [t for t, _ in secs]
            missing = [s for s in SPEC_SECTIONS if s not in titles]
            if missing:
                out.append(f"{rel}/spec.md：缺〈{'〉〈'.join(missing)}〉段")
            elif d.name in active:
                body = next(lines for t, lines in secs if t == ACCEPTANCE)
                if not any(re.match(rf"###\s*{USER_TRIAL}", l) for _, l in body):
                    out.append(f"{rel}/spec.md：〈{ACCEPTANCE}〉底下要有 `### {USER_TRIAL}`：使用者親手試什麼、怎麼啟動；沒有就寫「無」和理由")
        tickets = sorted((d / "issues").glob("*.md"))
        if MILESTONE_DIR.match(d.name) and not any(t.name.endswith(ACCEPTANCE_SUFFIXES) for t in tickets):
            out.append(f"{rel}/issues/：沒有驗收票（檔名以 -acceptance.md 結尾），它是里程碑的最後一張票")
        for t in tickets:
            text = t.read_text(encoding="utf-8")
            head = text.split("\n## ")[0].split("\n")
            if not any(STATUS.match(line) for line in head):
                out.append(f"{rel}/issues/{t.name}：第一個 ## 之前要有一行 `Status:`")
            elif d.name in active and any(DONE.match(line) for line in head):
                comments = text.split("\n## Comments", 1)
                if len(comments) < 2 or not any(l.startswith(SESSION_NOTE) for l in comments[1].split("\n")):
                    out.append(f"{rel}/issues/{t.name}：做完的票要在 `## Comments` 之後留一行「{SESSION_NOTE}<做了什麼>」，合併的人照它寫 progress.md")
                for l in (comments[1].split("\n") if len(comments) == 2 else []):
                    if l.startswith(DECISION_NOTE) and len(DECIDER.findall(l)) != 1:
                        out.append(f"{rel}/issues/{t.name}：「{DECISION_NOTE}」那一行要標一個決定者：{DECIDER_LIST}")
    return out


def run(root: Path) -> list:
    out = []
    for rel, check in ((PROGRESS, check_progress), (DECISIONS, check_decisions), (ROADMAP, check_roadmap)):
        if (root / rel).is_file():
            out += check((root / rel).read_text(encoding="utf-8"))
        else:
            out.append(f"找不到 {rel}")
    return out + check_budgets(root) + check_current_state(root) + check_layout(root) + check_code_refs(root) + check_scratch(root)


def main(argv) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")  # Windows 終端機預設不是 UTF-8
    found = run(Path(argv[0]) if argv else Path.cwd())
    for p in found:
        print(p, file=sys.stderr)
    if found:
        print(f"{len(found)} 條違規", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
