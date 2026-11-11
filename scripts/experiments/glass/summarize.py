#!/usr/bin/env python3
"""實驗用（M0 票 05b）：把 results/<平台>.json 印成 Markdown 表（README〈結果〉用）。

    python3 summarize.py results/macos.json [results/android.json …]
"""

import json
import sys


def main():
    for path in sys.argv[1:]:
        r = json.load(open(path))
        e = r["env"]
        print(f"\n### {path}\n")
        print(
            f"{e['platform']} · {e['os']} · {e['buildMode']} · shaderFilterSupported={e['shaderFilterSupported']}"
            f" · {e['refreshRate']:.0f} Hz（預算 {1000 / e['refreshRate']:.1f} ms）· DPR {e['devicePixelRatio']}\n"
        )
        print("| 候選 | 幀數／應有 | build p50／p99 | raster p50／p90／p99／max | > 16.7 ms | > 預算 |")
        print("| --- | --- | --- | --- | --- | --- |")
        for v in r["variants"]:
            b, ra = v["buildMs"], v["rasterMs"]
            print(
                f"| {v['variant']} | {v['frames']}／{v['expectedFrames']} | {b['p50']:.1f}／{b['p99']:.1f} |"
                f" {ra['p50']:.1f}／{ra['p90']:.1f}／{ra['p99']:.1f}／{ra['max']:.1f} | {v['over16_7ms']} | {v['overBudget']} |"
            )


if __name__ == "__main__":
    main()
