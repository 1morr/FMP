#!/usr/bin/env python3
"""Flatten the Android accessibility tree into one line per actionable/labelled node.

Prints the node class, resource id, label, clickability, and both pixel and
normalized (0..1) centers. The normalized pair feeds `orca emulator tap <x> <y>`;
the pixel pair feeds `adb shell input tap <x> <y>`.

The tree comes from `orca emulator ax` by default. With `--adb` it comes from
`adb exec-out uiautomator dump /dev/tty` instead, so Orca is not needed and no
dump file is left on the device.

Usage:
    PYTHONIOENCODING=utf-8 python ax_flatten.py [--adb] [--device emulator-5554]
                                               [--limit 40] [--grep TEXT]
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


def dump(orca: str, device: str) -> dict:
    proc = subprocess.run(
        [orca, "emulator", "ax", "--device", device, "--json"],
        capture_output=True,
    )
    payload = json.loads(proc.stdout.decode("utf-8", errors="replace"))
    if not payload.get("ok"):
        sys.exit(f"orca emulator ax failed: {payload.get('error')}")
    return payload["result"]


_BOUNDS = re.compile(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]")


def dump_adb(device: str) -> dict:
    """Read the tree with uiautomator and convert it to the shape `orca emulator ax` returns."""
    proc = subprocess.run(
        ["adb", "-s", device, "exec-out", "uiautomator", "dump", "/dev/tty"],
        capture_output=True,
    )
    text = proc.stdout.decode("utf-8", errors="replace")
    end = text.rfind("</hierarchy>")
    if end < 0:
        sys.exit(f"uiautomator dump failed: {text.strip() or proc.stderr.decode(errors='replace').strip()}")
    root = ET.fromstring(text[text.find("<"):end + len("</hierarchy>")])

    def convert(el: ET.Element) -> dict:
        m = _BOUNDS.fullmatch(el.get("bounds", ""))
        l, t, r, b = (int(v) for v in m.groups()) if m else (0, 0, 0, 0)
        return {
            "text": el.get("text", ""),
            "contentDesc": el.get("content-desc", ""),
            "clickable": el.get("clickable") == "true",
            "className": el.get("class", ""),
            "resourceId": el.get("resource-id", ""),
            "bounds": {"left": l, "top": t, "right": r, "bottom": b},
            "children": [convert(child) for child in el.findall("node")],
        }

    return {"children": [convert(child) for child in root.findall("node")]}


def walk(node: dict, width: int, height: int, depth: int = 0, out: list | None = None) -> list:
    if out is None:
        out = []
    bounds = node.get("bounds") or {}
    label = node.get("text") or node.get("contentDesc") or ""
    if label or node.get("clickable"):
        cx = (bounds.get("left", 0) + bounds.get("right", 0)) / 2
        cy = (bounds.get("top", 0) + bounds.get("bottom", 0)) / 2
        cls = (node.get("className") or "").rsplit(".", 1)[-1]
        rid = (node.get("resourceId") or "").rsplit("/", 1)[-1]
        out.append(
            "{indent}{cls} id={rid} txt={label!r} click={click} "
            "center=({cx:.0f},{cy:.0f}) norm=({nx:.3f},{ny:.3f})".format(
                indent="  " * depth,
                cls=cls,
                rid=rid,
                label=label,
                click=node.get("clickable"),
                cx=cx,
                cy=cy,
                nx=cx / width if width else 0,
                ny=cy / height if height else 0,
            )
        )
    for child in node.get("children") or []:
        walk(child, width, height, depth + 1, out)
    return out


def screen_size(device: str) -> tuple[int, int]:
    """Read the device's physical resolution; ax bounds are in those pixels."""
    proc = subprocess.run(["adb", "-s", device, "shell", "wm", "size"], capture_output=True)
    text = proc.stdout.decode("utf-8", errors="replace")
    for token in text.split():
        if "x" in token and token.replace("x", "").isdigit():
            w, h = token.split("x")
            return int(w), int(h)
    return 1080, 2400


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", default="emulator-5554")
    parser.add_argument("--orca", default="orca", help="Orca executable to use")
    parser.add_argument("--adb", action="store_true", help="read the tree with adb uiautomator, without Orca")
    parser.add_argument("--limit", type=int, default=40)
    parser.add_argument("--grep", default=None, help="only print lines containing this text")
    args = parser.parse_args()

    width, height = screen_size(args.device)
    tree = dump_adb(args.device) if args.adb else dump(args.orca, args.device)
    lines = walk(tree, width, height)
    if args.grep:
        lines = [line for line in lines if args.grep in line]
    print(f"nodes={len(lines)} screen={width}x{height}")
    print("\n".join(lines[: args.limit]))
    if len(lines) > args.limit:
        print(f"... {len(lines) - args.limit} more (raise --limit)")


if __name__ == "__main__":
    main()
