"""從 repo 現在的檔案算出下一步：等使用者決定的事、現在要下的指令、後面還排著什麼。

    python next_step.py [repo 根目錄，預設目前目錄]

每個 session 結尾跑它，把輸出原樣貼給使用者；使用者問「接下來做什麼」時也跑它。只讀不寫，永遠 exit 0。輸出三段，沒有內容的段不印：

    等你決定（2）
      - M1 票 03：<題目>（.scratch/m1/issues/03-x.md）
      - <題目>（docs/progress.md 最後一列，2026-01-05）
    現在
      /implement .scratch/m1/issues/04-y.md
      M1 票 04 <標題>。開一個新的 session 貼上這條指令。
    之後
      - M1 還有 3 張票，最後一張是驗收票；驗收後是 /1morr:checkpoint M1
      - docs-diet 文件瘦身：5 張票，排在 M1 之後
      - M2 匯出：還沒拆票

怎麼算：
  等你決定  docs/progress.md 最後一列的「下一步」以「等使用者：」開頭的那一句；還沒結束的工作裡，沒做完的票在 `## Comments` 之後
            以「等使用者：」開頭的行，而且它後面沒有「決定：」行（回答寫成一行「決定：…（使用者定）」，那一題就不再列）
  現在      「目前的工作」是 docs/roadmap.md 里程碑表裡狀態以「進行中」開頭的那一列；沒有的話，是第一個有票沒做完、而且狀態寫的
            「排在 <某一列> 之後」那一列已經結束（或沒寫排在誰之後）的列。它的第一張沒做完、擋它的票都做完（或不做）、沒在等使用者
            的票就是現在要做的；同時有兩張以上做得了的，另印整批跑的指令。
            目前的工作沒有票可做時，照 docs/progress.md 最後一列的「下一步」（訪談、寫架構、拆票、回顧這些沒有票的階段靠它）。
            progress.md 在等使用者時，先印那一題，指令標成「答完之後」。
  之後      目前的工作剩幾張票；狀態寫「排在 … 之後」的工作；還沒拆票的里程碑（照表的順序）
只用標準函式庫。
"""

import re
import sys
from pathlib import Path

ROADMAP, PROGRESS, SCRATCH = "docs/roadmap.md", "docs/progress.md", ".scratch"
MILESTONES, SESSIONS, STEP = "里程碑", "Session 紀錄", "下一步"
ACTIVE, CLOSED = "進行中", ("已驗收", "不做")
WAITING, DECISION_NOTE = "等使用者：", "決定："
COMMENTS = "\n## Comments"
AFTER = re.compile(r"排在\s*`?([^\s`，。；、]+)`?\s*之後")
STATUS = re.compile(r"^\**Status:?\**:?\s*(\S.*?)\s*$", re.I)
BLOCKED = re.compile(r"^\**Blocked by:?\**:?\s*(.*)$", re.I)
DROPPED = re.compile(r"^(wontfix|cancelled|canceled)", re.I)
NUMBER = re.compile(r"^(\d+[a-z]?)-")
MILESTONE_DIR = re.compile(r"^m\d+(\.\d+)?$", re.I)
ACCEPTANCE_SUFFIXES = ("-acceptance.md", "-close.md")
CELL_SPLIT = re.compile(r"(?<!\\)\|")
COMMAND = re.compile(r"`(/[^`\s][^`]*)`")


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return ""


def table(text: str, title: str) -> list:
    """`## <title>` 段裡第一張表的每一列：[{表頭欄名: 內容}]；欄數和表頭不一樣的列不讀。"""
    lines, inside, fenced = [], False, False
    for line in text.split("\n"):
        if line.lstrip().startswith("```"):
            fenced = not fenced
        if not fenced and line.startswith("## "):
            inside = line[3:].strip() == title
        elif inside and line.strip().startswith("|"):
            lines.append([c.strip().replace("\\|", "|") for c in CELL_SPLIT.split(line.strip().strip("|"))])
        elif inside and lines:
            break
    if len(lines) < 2:
        return []
    return [dict(zip(lines[0], cells)) for cells in lines[2:] if len(cells) == len(lines[0])]


def open_questions(text: str) -> list:
    """票的 `## Comments` 之後還沒回答的「等使用者：」：最後一行「決定：」之後的那幾題。"""
    out = []
    for line in text.split(COMMENTS, 1)[1].split("\n") if COMMENTS in text else []:
        if line.startswith(DECISION_NOTE):
            out = []
        elif line.startswith(WAITING) and line[len(WAITING):].strip():
            out.append(line[len(WAITING):].strip())
    return out


def ticket(path: Path) -> dict:
    text = read(path)
    lines = text.split("\n")
    title = next((l.lstrip("# ").strip() for l in lines if l.startswith("# ")), path.stem)
    status, blocked = "", []
    for l in lines:
        if l.startswith("## "):
            break
        m = STATUS.match(l)
        if m and not status:
            status = m.group(1).strip("* ")
        m = BLOCKED.match(l)
        if m:
            blocked = re.findall(r"\d+[a-z]?", m.group(1))
    number = NUMBER.match(path.name)
    closed = status.lower().startswith("done") or bool(DROPPED.match(status))
    return {"file": path.name, "number": number.group(1) if number else path.stem, "title": re.sub(r"^\S+\s*[:：—-]\s*", "", title),
            "closed": closed, "blocked": blocked, "waiting": [] if closed else open_questions(text)}


def works(root: Path) -> list:
    """里程碑表的每一列：{name, label, dir, status, after, tickets}，照表的順序。"""
    out = []
    for row in table(read(root / ROADMAP), MILESTONES):
        name = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", row.get(MILESTONES, "")).replace("`", "").strip()
        if not name:
            continue
        directory = name.split()[0].lower()
        status = row.get("狀態", "").strip()
        after = AFTER.search(status)
        issues = root / SCRATCH / directory / "issues"
        out.append({"name": name, "label": name.split()[0], "dir": directory, "status": status,
                    "after": after.group(1).lower() if after else "", "after_name": after.group(1) if after else "",
                    "tickets": [ticket(p) for p in sorted(issues.glob("*.md"))] if issues.is_dir() else []})
    return out


def is_closed(work: dict) -> bool:
    return work["status"].startswith(CLOSED)


def left(work: dict) -> list:
    return [t for t in work["tickets"] if not t["closed"]]


def current(listed: list):
    """目前的工作：進行中的那一列；沒有就是第一個有票沒做完、排在它前面的那一列已經結束的。"""
    for w in listed:
        if w["status"].startswith(ACTIVE):
            return w
    by_dir = {w["dir"]: w for w in listed}
    for w in listed:
        if not is_closed(w) and left(w) and (w["after"] not in by_dir or is_closed(by_dir[w["after"]])):
            return w
    return None


def doable(work: dict) -> list:
    """做得了的票：沒做完、擋它的票都做完（或不做、或不在這個目錄）、沒在等使用者。"""
    closed = {t["number"] for t in work["tickets"] if t["closed"]}
    known = {t["number"] for t in work["tickets"]}
    return [t for t in left(work) if not t["waiting"] and all(b in closed or b not in known for b in t["blocked"])]


def last_step(root: Path):
    """(progress.md 最後一列的下一步, 那一列的日期)；沒有就是 ("", "")。"""
    rows = table(read(root / PROGRESS), SESSIONS)
    return (rows[-1].get(STEP, "").strip(), rows[-1].get("日期", "")) if rows else ("", "")


def path_of(work: dict, t: dict) -> str:
    return f"{SCRATCH}/{work['dir']}/issues/{t['file']}"


def report(root: Path) -> dict:
    """{waiting: [一行], command, why, later: [一行]}"""
    listed = works(root)
    step, date = last_step(root)
    held = step.startswith(WAITING)
    waiting = [f"{w['label']} 票 {t['number']}：{q}（{path_of(w, t)}）"
               for w in listed if not is_closed(w) for t in w["tickets"] for q in t["waiting"]]
    if held:
        waiting.append(f"{step[len(WAITING):].strip()}（{PROGRESS} 最後一列，{date}）")
    now = current(listed)
    ready = doable(now) if now else []
    command, why = "", ""
    if ready:
        t = ready[0]
        command = f"/implement {path_of(now, t)}"
        why = f"{now['label']} 票 {t['number']} {t['title']}。開一個新的 session 貼上這條指令。"
        if not now["status"].startswith(ACTIVE):
            why += f"\n先把 {ROADMAP} 里程碑表裡 {now['label']} 那一列的狀態改成「{ACTIVE}」。"
        if len(ready) > 1:
            why += f"\n同時做得了的有 {len(ready)} 張，要整批跑：/1morr:ticket-coordinator {SCRATCH}/{now['dir']}/issues"
        if held:
            why = "先回答上面 docs/progress.md 那一題；答完之後才是這條指令。\n" + why
    elif now and left(now):
        stuck = left(now)
        asked = [t for t in stuck if t["waiting"]]
        why = (f"{now['label']} 剩下的票都在等你回答上面的題。" if len(asked) == len(stuck) else
               f"{now['label']} 還有 {len(stuck)} 張票沒做完，但每一張不是在等你回答，就是被還沒做完的票擋著："
               + "、".join(f"票 {t['number']}（擋它的：{'、'.join(t['blocked']) or '無'}）" for t in stuck if not t["waiting"]))
    elif held:
        why = "先回答上面那一題；開一個新的 session 回答。"
    elif step:
        found = COMMAND.search(step)
        command = found.group(1) if found else ""
        why = (f"{PROGRESS} 最後一列（{date}）寫的下一步" + ("。開一個新的 session 貼上這條指令。" if found else f"：{step}"))
    else:
        why = f"{PROGRESS} 還沒有 session 紀錄，也沒有可以做的票。"
    return {"waiting": waiting, "command": command, "why": why, "later": later(listed, now, ready)}


def later(listed: list, now, ready: list) -> list:
    out = []
    if now and left(now):
        rest = len(left(now)) - (1 if ready else 0)
        last = now["tickets"][-1]
        accept = MILESTONE_DIR.match(now["dir"]) and last["file"].endswith(ACCEPTANCE_SUFFIXES) and not last["closed"]
        if rest > 0:
            out.append(f"{now['label']} 還有 {rest} 張票" + ("，最後一張是驗收票（你要親手試）；驗收後是 /1morr:checkpoint " + now["label"] if accept else ""))
        elif accept:
            out.append(f"這張是 {now['label']} 的驗收票（你要親手試）；驗收後是 /1morr:checkpoint {now['label']}")
    for w in listed:
        if w is now or is_closed(w):
            continue
        if left(w):
            out.append(f"{w['name']}：{len(left(w))} 張票，" + (f"排在 {w['after_name']} 之後" if w["after"] else f"{ROADMAP} 沒寫它排在誰之後"))
        elif not w["tickets"]:
            out.append(f"{w['name']}：還沒拆票")
    return out


def render(found: dict) -> str:
    out = []
    if found["waiting"]:
        out += [f"等你決定（{len(found['waiting'])}）", *(f"  - {w}" for w in found["waiting"])]
    out.append("現在")
    if found["command"]:
        out.append(f"  {found['command']}")
    out += [f"  {line}" for line in found["why"].split("\n")]
    if found["later"]:
        out += ["之後", *(f"  - {l}" for l in found["later"])]
    return "\n".join(out)


def main(argv) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")  # Windows 終端機預設不是 UTF-8
    print(render(report(Path(argv[0]) if argv else Path.cwd())))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
