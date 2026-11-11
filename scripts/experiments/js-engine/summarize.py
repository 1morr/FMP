#!/usr/bin/env python3
"""實驗用：把 results/*.json 印成表。

    python3 summarize.py results/fjs-macos.json      # 一份結果的細節
    python3 summarize.py --table results/*.json      # Markdown 總表（候選 × 平台 × 測項）
"""
import json
import os
import re
import sys

CHECKS = [
    ("engine_identity", "同一引擎"),
    ("interrupt_infinite_loop", "中斷無窮迴圈"),
    ("memory_limit", "記憶體上限"),
    ("await_js_promise", "Dart await Promise"),
    ("async_host_call", "JS await Dart async"),
    ("isolate_layout", "isolate 配置"),
    ("stuck_engine_isolation", "卡住不拖累其他引擎"),
]

HERE = os.path.dirname(os.path.abspath(__file__))


def locked_version(candidate):
    """probe app 的 pubspec.lock 裡這個套件的版本（候選名稱與版本寫在兩處，這裡對照）。"""
    name = candidate.split()[0]
    lock = os.path.join(HERE, f"probe_{name}", "pubspec.lock")
    try:
        text = open(lock, encoding="utf-8").read()
    except OSError:
        return None
    m = re.search(rf"^  {re.escape(name)}:\n(?:    .*\n)*?    version: \"([^\"]+)\"", text, re.M)
    return m.group(1) if m else None


def version_warning(candidate):
    name, _, version = candidate.partition(" ")
    locked = locked_version(candidate)
    if locked and locked != version:
        return f"WARNING: result says {name} {version} but probe_{name}/pubspec.lock has {locked}"
    return None


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def detail(path):
    r = load(path)
    if "setup_error" in r:
        print(f"{path}: setup failed\n{r['setup_error']}")
        return
    print(f"{r['candidate']} on {r['platform']} ({r['at']})")
    warning = version_warning(r["candidate"])
    if warning:
        print(warning)
    for c in r["checks"]:
        mark = "PASS" if c["pass"] else "FAIL"
        print(f"  {mark} {c['id']} ({c.get('ms', '?')} ms): {c['detail']}")


def table(paths):
    rows = [load(p) for p in paths]
    print("| 候選 | 平台 | " + " | ".join(name for _, name in CHECKS) + " |")
    print("| --- | --- | " + " | ".join("---" for _ in CHECKS) + " |")
    for r in rows:
        if "setup_error" in r:
            print(f"| {r.get('slug', '?')} | ? | setup failed |")
            continue
        by_id = {c["id"]: c for c in r["checks"]}
        cells = []
        for cid, _ in CHECKS:
            c = by_id.get(cid)
            cells.append("—" if c is None else ("✅" if c["pass"] else "❌"))
        print(f"| {r['candidate']} | {r['platform']} | " + " | ".join(cells) + " |")
        warning = version_warning(r["candidate"])
        if warning:
            print(warning, file=sys.stderr)


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--table":
        table(args[1:])
    else:
        for p in args:
            detail(p)
