"""證明搬文件沒有丟東西：來源檔被刪掉的每一行，都在某個目的地檔裡找得到。

    python docs_moved_lines.py <基準 commit> <來源檔>... -- <目的地檔>...

里程碑封存時用：基準是封存前的 commit（通常是 HEAD），來源是 docs/progress.md 與 docs/decisions.md，
目的地是 docs/archive/<里程碑>.md。「被刪掉的行」是 `git diff <基準> -- <來源檔>` 刪的行。
比對時去掉頭尾空白；空行與表格的分隔列（`| --- | --- |`）不算；Markdown 連結目標開頭的 `./`、`../` 不算，
所以搬到深一層、連結多了 `../` 的行仍然對得上。
輸出一行 `刪 N 行，找到 N，遺失 N`，遺失的每行再印一行 `  遺失：<那一行>`。遺失 0 exit 0，否則 exit 1；用法不對 exit 2。
只用標準函式庫。
"""

import re
import subprocess
import sys
from pathlib import Path

TABLE_RULE = re.compile(r"^\|(\s*:?-+:?\s*\|)+$")
LINK_PREFIX = re.compile(r"(\]\()(?:\.{1,2}/)+")


def normalized(line: str) -> str:
    return LINK_PREFIX.sub(r"\1", line.strip())


def removed_lines(diff: str) -> list:
    """unified diff 刪掉的行，去掉空行與表格分隔列。"""
    out = []
    for raw in diff.splitlines():
        if not raw.startswith("-") or raw.startswith("---"):
            continue
        line = raw[1:].strip()
        if line and not TABLE_RULE.match(line):
            out.append(line)
    return out


def missing_lines(removed, destinations) -> list:
    present = {normalized(line) for text in destinations for line in text.splitlines()}
    return [line for line in removed if normalized(line) not in present]


def main(argv) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    if "--" not in argv or argv.index("--") < 2 or argv.index("--") == len(argv) - 1:
        print(__doc__, file=sys.stderr)
        return 2
    cut = argv.index("--")
    base, sources, destinations = argv[0], argv[1:cut], argv[cut + 1:]
    diff = subprocess.run(["git", "diff", "--no-color", "-U0", base, "--", *sources], capture_output=True, check=True).stdout.decode("utf-8")
    removed = removed_lines(diff)
    lost = missing_lines(removed, (Path(p).read_text(encoding="utf-8") for p in destinations))
    print(f"刪 {len(removed)} 行，找到 {len(removed) - len(lost)}，遺失 {len(lost)}")
    for line in lost:
        print(f"  遺失：{line}")
    return 1 if lost else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
