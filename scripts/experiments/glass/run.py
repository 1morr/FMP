#!/usr/bin/env python3
"""實驗用（M0 票 05b）：在 macOS、iOS 模擬器或 Android 模擬器建置 probe，逐個候選截圖並量捲動幀時間。

    python3 run.py <macos|ios|android>          # 全部候選；結果 results/<平台>.json、對照圖 results/<平台>-sheet.jpg
    VARIANTS=own-refract,own-blur python3 run.py macos   # 只跑部分候選（結果檔名加 -partial）
    MODE=a11y python3 run.py macos              # 只讀無障礙旗標（降低透明度），結果 results/<平台>-a11y.json

建置：macOS、Android 用 profile（brief〈效能與品質指標〉 量幀用 profile）；iOS 模擬器 Flutter 只能建 debug，幀時間只供參考。
建置只寫 probe/build/，在鎖外做；裝 App 到截圖整段持有共用裝置鎖（docs/development.md〈平台〉），經
app/tool/device_lock.dart 重新執行本檔的 --device 階段（同一個 worktree 已持鎖時直接跑）。
完整截圖存在 SHOT_DIR（預設新的暫存目錄，不進 repo），results/ 只放裁切後的對照圖。
環境變數：IOS_DEVICE（模擬器 UDID，預設 booted）、IOS_SHOT_ARGS（iPhone Duo 要 --display=1）、ANDROID_SERIAL（預設第一台 emulator-*）。
Windows 用 run-windows.sh。
"""

import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
PROBE = HERE / "probe"
RESULTS = HERE / "results"
REPO = pathlib.Path(subprocess.check_output(["git", "-C", str(HERE), "rev-parse", "--show-toplevel"], text=True).strip())
APPLE_BUNDLE = "com.personal.fmpx.glassProbe"
ANDROID_ID = "com.personal.fmpx.glass_probe"
MAC_APP = PROBE / "build/macos/Build/Products/Profile/glass_probe.app"
TIMEOUT_S = 400


def run(*args, **kw):
    return subprocess.run(args, check=True, **kw)


def out(*args):
    return subprocess.check_output(args, text=True)


def defines():
    d = []
    for k in ("VARIANTS", "MODE", "SCENE_HOLD_MS", "SCROLL_MS"):
        if os.environ.get(k):
            d.append(f"--dart-define={k}={os.environ[k]}")
    return d


def build(plat):
    run("flutter", "pub", "get", cwd=PROBE, stdout=subprocess.DEVNULL)
    if plat == "macos":
        run("flutter", "build", "macos", "--profile", *defines(), cwd=PROBE)
    elif plat == "ios":
        run("flutter", "build", "ios", "--simulator", "--debug", *defines(), cwd=PROBE)
    elif plat == "android":
        run("flutter", "build", "apk", "--profile", *defines(), cwd=PROBE)
    else:
        sys.exit(f"unknown platform: {plat}")


def result_name(plat):
    if os.environ.get("MODE") == "a11y":
        return f"{plat}-a11y"
    if os.environ.get("VARIANTS"):
        return f"{plat}-partial"
    return plat


# ---------------------------------------------------------------- device phase


class Device:
    """Launch, follow PROBE_* lines, screenshot, stop."""

    def __init__(self, plat, shots):
        self.plat = plat
        self.shots = shots
        self.raw = shots / f"raw-{plat}.log"
        self.proc = None
        if plat == "android":
            serial = os.environ.get("ANDROID_SERIAL")
            if not serial:
                devs = [l.split()[0] for l in out("adb", "devices").splitlines()[1:] if l.strip().endswith("device")]
                emus = [d for d in devs if d.startswith("emulator-")]
                if not emus:
                    sys.exit("no Android emulator")
                serial = emus[0]
            self.adb = ["adb", "-s", serial]
        if plat == "ios":
            self.dev = os.environ.get("IOS_DEVICE", "booted")

    def start(self):
        if self.plat == "macos":
            exe = MAC_APP / "Contents/MacOS/glass_probe"
            self.proc = subprocess.Popen([str(exe)], stdout=open(self.raw, "w"), stderr=subprocess.STDOUT)
        elif self.plat == "ios":
            run("xcrun", "simctl", "install", self.dev, str(PROBE / "build/ios/iphonesimulator/Runner.app"))
            # iOS 的 print 進系統 log：改讀 App 容器 tmp/ 裡的狀態檔與結果檔。
            self.tmp = pathlib.Path(out("xcrun", "simctl", "get_app_container", self.dev, APPLE_BUNDLE, "data").strip()) / "tmp"
            for f in ("glass-probe-status.json", "glass-probe.json"):
                (self.tmp / f).unlink(missing_ok=True)
            run("xcrun", "simctl", "launch", "--terminate-running-process", self.dev, APPLE_BUNDLE, stdout=subprocess.DEVNULL)
        else:
            run(*self.adb, "install", "-r", str(PROBE / "build/app/outputs/flutter-apk/app-profile.apk"), stdout=subprocess.DEVNULL)
            run(*self.adb, "logcat", "-c")
            run(*self.adb, "shell", "am", "start", "-n", f"{ANDROID_ID}/.MainActivity", stdout=subprocess.DEVNULL)

    def lines(self):
        if self.plat == "macos":
            return self.raw.read_text(errors="replace").splitlines()
        if self.plat == "android":
            text = out(*self.adb, "logcat", "-d", "-s", "flutter:I")
            self.raw.write_text(text)
            return text.splitlines()
        lines = []
        st = self.tmp / "glass-probe-status.json"
        if st.exists():
            try:
                lines.append("PROBE_STATUS " + st.read_text())
            except OSError:
                pass
        return lines

    def status(self):
        st = None
        for l in self.lines():
            m = re.search(r"PROBE_STATUS (\{.*\})", l)
            if m:
                try:
                    st = json.loads(m.group(1))
                except json.JSONDecodeError:
                    pass
        return st

    def screenshot(self, name):
        path = self.shots / f"{self.plat}-{name}.png"
        if self.plat == "macos":
            state = json.loads(out("orca", "computer", "get-app-state", "--app", APPLE_BUNDLE, "--json"))
            src = state["result"]["screenshot"]["path"]
            run("cp", src, str(path))
        elif self.plat == "ios":
            # iPhone Duo（雙螢幕）要 IOS_SHOT_ARGS=--display=1（docs/development.md〈平台〉）。
            extra = os.environ.get("IOS_SHOT_ARGS", "").split()
            run("xcrun", "simctl", "io", self.dev, "screenshot", *extra, str(path), stdout=subprocess.DEVNULL)
        else:
            with open(path, "wb") as f:
                run(*self.adb, "exec-out", "screencap", "-p", stdout=f)
        return path

    def results(self):
        if self.plat == "ios":
            f = self.tmp / "glass-probe.json"
            return json.loads(f.read_text()) if f.exists() else None
        env, variants = None, []
        for l in self.lines():
            m = re.search(r"PROBE_ENV (\{.*\})", l)
            if m:
                env = json.loads(m.group(1))
            m = re.search(r"PROBE_RESULT (\{.*\})", l)
            if m:
                variants.append(json.loads(m.group(1)))
        return {"env": env, "variants": variants} if env else None

    def stop(self):
        if self.plat == "macos" and self.proc:
            self.proc.terminate()
        elif self.plat == "ios":
            subprocess.run(["xcrun", "simctl", "terminate", self.dev, APPLE_BUNDLE], capture_output=True)
        elif self.plat == "android":
            subprocess.run([*self.adb, "shell", "am", "force-stop", ANDROID_ID], capture_output=True)


def device_phase(plat, shots):
    d = Device(plat, shots)
    d.start()
    shot_of = {}
    deadline = time.time() + TIMEOUT_S
    try:
        while time.time() < deadline:
            st = d.status()
            if st and st.get("phase") == "scene":
                key = st["variant"]
                if key not in shot_of:
                    time.sleep(0.5)
                    shot_of[key] = str(d.screenshot(key))
                    print(f"shot {key}", flush=True)
            if st and st.get("phase") == "done":
                break
            time.sleep(0.4)
        else:
            print("timed out", file=sys.stderr)
        if os.environ.get("MODE") == "a11y":
            shot_of["a11y"] = str(d.screenshot("a11y"))
        res = d.results()
    finally:
        d.stop()
    return res, shot_of


# ---------------------------------------------------------------- contact sheet


def sheet(plat, res, shot_of, dest):
    """Crop the dock (bottom 190 logical px, 400 logical px wide) of each shot at native resolution; 2 per row, JPEG."""
    from PIL import Image, ImageDraw

    dpr = res["env"]["devicePixelRatio"]
    tiles = []
    for v in res["variants"]:
        p = shot_of.get(v["variant"])
        if not p:
            continue
        im = Image.open(p).convert("RGB")
        w, h = im.size
        cw = int(min(w, 400 * dpr))
        x0 = (w - cw) // 2 if w > 400 * dpr else 0
        tile = im.crop((x0, int(h - 190 * dpr), x0 + cw, h))
        # Normalise to 2x so tiles from different DPRs line up.
        tile = tile.resize((int(tile.width * 2 / dpr), int(tile.height * 2 / dpr)), Image.LANCZOS)
        ImageDraw.Draw(tile).text((10, 6), f"{plat} {v['variant']}", fill="white", stroke_width=3, stroke_fill="black", font_size=28)
        tiles.append(tile)
    if not tiles:
        return
    cols = 2
    tw, th = max(t.width for t in tiles), max(t.height for t in tiles)
    rows = (len(tiles) + cols - 1) // cols
    out_im = Image.new("RGB", (tw * cols, th * rows), "black")
    for i, t in enumerate(tiles):
        out_im.paste(t, ((i % cols) * tw, (i // cols) * th))
    out_im.save(dest, quality=88)


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--sheet":
        # run-windows.sh: python3 run.py --sheet windows <result.json> <shots dir> <dest>
        plat, res_path, shots, dest = sys.argv[2], sys.argv[3], pathlib.Path(sys.argv[4]), sys.argv[5]
        res = json.loads(pathlib.Path(res_path).read_text(encoding="utf-8-sig"))
        shot_of = {p.stem.removeprefix(f"{plat}-"): str(p) for p in shots.glob(f"{plat}-*.png")}
        if res.get("variants"):
            sheet(plat, res, shot_of, dest)
        return
    if len(sys.argv) >= 3 and sys.argv[1] == "--device":
        plat, shots = sys.argv[2], pathlib.Path(sys.argv[3])
        res, shot_of = device_phase(plat, shots)
        (shots / "device-result.json").write_text(json.dumps({"res": res, "shots": shot_of}))
        return
    plat = sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__)
    shots = pathlib.Path(os.environ.get("SHOT_DIR") or tempfile.mkdtemp(prefix="glass-"))
    shots.mkdir(parents=True, exist_ok=True)
    build(plat)
    # 碰共用裝置：經包裝指令持鎖再跑 --device 階段。
    run("dart", "run", "tool/device_lock.dart", "--", sys.executable, str(HERE / "run.py"), "--device", plat, str(shots),
        cwd=REPO / "app")
    got = json.loads((shots / "device-result.json").read_text())
    res, shot_of = got["res"], got["shots"]
    print(f"screenshots: {shots}")
    if not res:
        sys.exit(f"no result; see {shots}/raw-{plat}.log")
    RESULTS.mkdir(exist_ok=True)
    name = result_name(plat)
    (RESULTS / f"{name}.json").write_text(json.dumps(res, indent=2, ensure_ascii=False) + "\n")
    if res["variants"]:
        sheet(plat, res, shot_of, RESULTS / f"{name}-sheet.jpg")
    print(json.dumps(res, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
