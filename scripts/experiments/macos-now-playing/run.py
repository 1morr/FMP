#!/usr/bin/env python3
"""實驗用：建置一個候選、啟動、照情境操作 Now Playing，結果寫到 results/<候選>-<情境>.json。

    python3 run.py <audio_service|channel> <basic|coldstart|remote-art>

情境：
  basic       自動播放；面板的播放、暫停、上一首、下一首、seek，再用媒體鍵播放／暫停、下一首、上一首；
              最後關掉 App，看 Now Playing 有沒有清掉。
  coldstart   不自動播放（brief〈播放〉 重啟後不自動播放）：App 開著、曲目已載入但沒播過時，
              Now Playing 面板有沒有它、按媒體鍵的播放能不能叫它播。
  remote-art  封面改用本機 HTTP server 的網址（模擬 M1 的遠端封面，不連外網）。

證據三份：面板（np-panel.sh 經輔助使用 API 讀 ControlCenter 的視窗）、App 收到的指令
（App 寫的 events.jsonl）、系統 log（mediaremoted 的 Sending command、PlaybackState changed、
CanBeNowPlaying changed）。
見 README.md。
"""

import datetime as dt
import http.server
import json
import os
import pathlib
import re
import subprocess
import sys
import threading
import time

HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
BUNDLES = {
    "audio_service": "com.personal.fmp.exp.probeAudioService",
    "channel": "com.personal.fmp.exp.probeChannel",
}


def sh(*args, check=True):
    r = subprocess.run(args, capture_output=True, text=True, cwd=HERE)
    if check and r.returncode != 0:
        raise RuntimeError(f"{args}: {r.stderr.strip()}")
    return r.stdout.strip()


def panel_state(retry=True):
    """讀面板。偶爾剛點開時讀到空的（沒有標題也沒有錯誤），就等一秒重讀一次。"""
    r = subprocess.run([str(HERE / "np-panel.sh"), "state"], capture_output=True, text=True)
    if r.returncode != 0:
        return {"error": r.stderr.strip()}
    out = {}
    for line in r.stdout.splitlines():
        k, _, v = line.partition(": ")
        out[k] = v
    texts = out.get("text", "").split(" | ")
    slider = out.get("slider", "")
    pos, _, dur = slider.partition("/")
    if retry and not texts[0]:
        time.sleep(1)
        return panel_state(retry=False)
    return {
        "title": texts[0] if texts and texts[0] else None,
        "buttons": out.get("buttons", "").split(" | ") if out.get("buttons") else [],
        "position": round(float(pos), 1) if pos else None,
        "duration": float(dur) if dur else None,
        "image": out.get("image") == "true",
    }


def wait_panel(timeout=20):
    """等到 Now Playing 面板有這個 App 的曲目（App 啟動後要先產生測試曲目）。"""
    end = time.time() + timeout
    while time.time() < end:
        s = panel_state()
        if track_no(s):
            return s
        time.sleep(1)
    return panel_state()


def panel(*args):
    return sh(str(HERE / "np-panel.sh"), *args)


def mediakey(name):
    exe = HERE / "build" / "mediakey"
    src = HERE / "mediakey.swift"
    if not exe.exists() or exe.stat().st_mtime < src.stat().st_mtime:
        exe.parent.mkdir(exist_ok=True)
        sh("swiftc", "-O", "-o", str(exe), str(src))
    return sh(str(exe), name)


def track_no(state):
    m = re.search(r"曲目 (\d)", state.get("title") or "")
    return int(m.group(1)) if m else None


def moved(delta):
    """下一首、上一首的判斷：相對動作前的曲目（曲目會自己播完換下一首，不能寫死）。"""
    before = track_no(panel_state())
    return lambda s: before is not None and track_no(s) == (before - 1 + delta) % 3 + 1


class Probe:
    def __init__(self, cand, defines, raw_log):
        self.cand = cand
        app_dir = HERE / f"probe_{cand}"
        build = ["flutter", "build", "macos", "--debug"] + [f"--dart-define={k}={v}" for k, v in defines.items()]
        subprocess.run(build, cwd=app_dir, check=True, stdout=subprocess.DEVNULL)
        exe = app_dir / f"build/macos/Build/Products/Debug/probe_{cand}.app/Contents/MacOS/probe_{cand}"
        self.raw = open(raw_log, "w")
        self.proc = subprocess.Popen([str(exe)], stdout=self.raw, stderr=subprocess.STDOUT)
        self.events_path = None
        for _ in range(60):
            time.sleep(0.5)
            m = re.search(r"PROBE_FILE (.*)", pathlib.Path(raw_log).read_text())
            if m:
                self.events_path = pathlib.Path(m.group(1).strip())
                break
        if not self.events_path:
            raise RuntimeError("App 沒印出 PROBE_FILE")
        self.seen = 0

    def take_received(self):
        """取出上次取之後 App 收到的系統指令（會移動讀取位置）。"""
        if not self.events_path.exists():
            return []
        lines = [json.loads(l) for l in self.events_path.read_text().splitlines() if l]
        got = [l for l in lines[self.seen :] if l["kind"] == "received"]
        self.seen = len(lines)
        return [f"{e['name']}({e['detail']})" if "detail" in e else e["name"] for e in got]

    def quit(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            self.proc.wait(timeout=10)
        self.raw.close()


def syslog(since, bundle):
    out = subprocess.run(
        [
            "/usr/bin/log", "show", "--info", "--style", "json", "--start", since,
            "--predicate",
            'process == "mediaremoted" AND (eventMessage CONTAINS "Sending command" '
            'OR eventMessage CONTAINS "PlaybackState changed" OR eventMessage CONTAINS "CanBeNowPlaying changed")',
        ],
        capture_output=True, text=True,
    ).stdout
    rows = []
    for e in json.loads(out or "[]"):
        msg = e["eventMessage"]
        if bundle not in msg:
            continue
        t = e["timestamp"][11:23]
        if m := re.search(r"command = (\w+), .*?SenderBundleIdentifier = <([^>]*)>", msg, re.S):
            rows.append(f"{t} command {m.group(1)} from {m.group(2)}")
        elif m := re.search(r"PlaybackState changed from (\w+) to (\w+)", msg):
            rows.append(f"{t} state {m.group(1)} -> {m.group(2)}")
        elif m := re.search(r"(CanBeNowPlaying(?:Player)?) changed to (\w+)", msg):
            rows.append(f"{t} {m.group(1)} -> {m.group(2)}")
    return rows


def step(probe, steps, name, action, expect_received, check=None, wait=1.5, moved_by=None):
    if moved_by is not None:  # 下一首、上一首：動作前才量起點
        check = moved(moved_by)
        probe.take_received()
    action()
    time.sleep(wait)
    state = panel_state()
    got = probe.take_received()
    ok = got == expect_received and (check(state) if check else True)
    steps.append({"step": name, "expect": expect_received, "received": got, "panel": state, "ok": ok})
    print(f"{'OK ' if ok else 'NG '} {name}: received={got} panel={state}")


# 播放／暫停鍵（togglePlayPause）在 App 端收到什麼：audio_service 轉成 click 再呼叫 play／pause。
TOGGLE = {
    "audio_service": {"pause": ["click(media)", "pause"], "play": ["click(media)", "play"]},
    "channel": {"pause": ["togglePlayPause"], "play": ["togglePlayPause"]},
}


def run_basic(cand, steps, probe):
    wait_panel()
    s1 = panel_state()
    time.sleep(2)
    s2 = panel_state()
    shown = (
        s1.get("title") == "FMP 實驗曲目 1、測試音源 440 Hz – macOS Now Playing 實驗"
        and s1.get("image") and "pause.fill" in s1.get("buttons", [])
        and s1.get("duration") == 40.0
        and (s2.get("position") or 0) > (s1.get("position") or 0)
    )
    steps.append({"step": "顯示：標題、歌手、封面、播放中、進度前進", "panel": [s1, s2], "ok": bool(shown)})
    print(f"{'OK ' if shown else 'NG '} 顯示 {s1} -> {s2}")
    panel("shot", str(RESULTS / f"{cand}-panel.png"))
    probe.take_received()
    is_paused = lambda s: "play.fill" in s["buttons"]
    is_playing = lambda s: "pause.fill" in s["buttons"]
    step(probe, steps, "面板：暫停", lambda: panel("press", "toggle"), ["pause"], is_paused)
    step(probe, steps, "面板：播放", lambda: panel("press", "toggle"), ["play"], is_playing)
    step(probe, steps, "面板：下一首", lambda: panel("press", "next"), ["next"], moved_by=1)
    step(probe, steps, "面板：上一首", lambda: panel("press", "previous"), ["previous"], moved_by=-1)
    step(probe, steps, "面板：seek 到 30 秒", lambda: panel("seek", "30"), ["seek(30000)"], lambda s: 30 <= s["position"] < 33)
    panel("close")
    step(probe, steps, "媒體鍵：播放／暫停（暫停）", lambda: mediakey("play"), TOGGLE[cand]["pause"], is_paused)
    step(probe, steps, "媒體鍵：播放／暫停（播放）", lambda: mediakey("play"), TOGGLE[cand]["play"], is_playing)
    step(probe, steps, "媒體鍵：下一首", lambda: mediakey("next"), ["next"], moved_by=1)
    step(probe, steps, "媒體鍵：上一首", lambda: mediakey("previous"), ["previous"], moved_by=-1)
    panel("close")
    probe.quit()
    time.sleep(2)
    s = panel_state()
    # 選單列的項目還在，但內容變成「未在播放」：沒有封面、沒有進度條。
    gone = "error" not in s and s.get("title") is not None and not s.get("image") and s.get("position") is None
    steps.append({"step": "關掉 App 後 Now Playing 清掉", "panel": s, "ok": gone})
    print(f"{'OK ' if gone else 'NG '} 關掉 App: {s}")
    panel("close")


def run_coldstart(cand, steps, probe):
    # 等曲目產生、setTrack 與暫停狀態送出（App 印 setPlayback 後再多等）。
    s = wait_panel(timeout=25)
    is_ours = track_no(s) is not None
    steps.append({"step": "沒播過：Now Playing 面板是不是這個 App", "panel": s, "ok": is_ours})
    print(f"{'OK ' if is_ours else 'NG '} 沒播過：{s}")
    panel("close")
    if not is_ours:
        # 沒有 App 在 Now Playing 時，媒體鍵會被系統轉給「音樂」並把它叫起來，所以不按。
        steps.append({"step": "沒播過：媒體鍵播放／暫停", "skipped": "不是 Now Playing App，按了會叫起「音樂」", "ok": None})
        print("--  不是 Now Playing App，不按媒體鍵")
    else:
        probe.take_received()
        step(probe, steps, "沒播過：媒體鍵播放／暫停", lambda: mediakey("play"),
             TOGGLE[cand]["play"],
             lambda s: "pause.fill" in s["buttons"], wait=2)
        panel("close")
    probe.quit()
    time.sleep(1)


def run_remote_art(cand, steps, probe):
    wait_panel()
    time.sleep(2)
    s = panel_state()
    ok = bool(s.get("image"))
    steps.append({"step": "遠端封面顯示", "panel": s, "http": list(ART_REQUESTS), "ok": ok and bool(ART_REQUESTS)})
    print(f"{'OK ' if ok else 'NG '} 遠端封面：{s}")
    panel("shot", str(RESULTS / f"{cand}-remote-art-panel.png"))
    panel("close")
    probe.quit()
    time.sleep(1)


ART_REQUESTS = []


class _ArtHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        ART_REQUESTS.append(f"{self.command} {self.path} -> {args[1] if len(args) > 1 else ''}")


def serve_art(cand):
    """在 App 容器的暫存目錄起本機 HTTP server（App 啟動時才產生封面，server 先起來等）。"""
    bundle = BUNDLES[cand]
    root = pathlib.Path.home() / f"Library/Containers/{bundle}/Data/Library/Caches/{bundle}/macos-now-playing-{cand}"
    root.mkdir(parents=True, exist_ok=True)
    handler = lambda *a, **k: _ArtHandler(*a, directory=str(root), **k)
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{httpd.server_address[1]}"


def ensure_device_lock():
    """沒持共用裝置鎖時，經 app/tool/device_lock.dart 拿鎖（等別的 worktree 放掉）再重新執行自己。

    實驗會送 Escape（打到最前面的 App）、媒體鍵與面板的按鈕（控制最近出過聲的 App），
    別的 worktree 的閘門或實跑可能正開著 dev App（docs/app-development.md〈平台〉〈開發環境與閘門〉）。同一個 worktree 已持有時直接跑。
    """
    repo = sh("git", "rev-parse", "--show-toplevel")
    tool = f"{repo}/app/tool/device_lock.dart"
    if subprocess.run(["dart", tool, "--repo", str(HERE), "--held"]).returncode != 0:
        os.execvp("dart", ["dart", tool, "--repo", str(HERE), "--", sys.executable, str(HERE / "run.py"), *sys.argv[1:]])


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    ensure_device_lock()
    cand, scenario = sys.argv[1], sys.argv[2]
    if cand not in BUNDLES or scenario not in ("basic", "coldstart", "remote-art"):
        sys.exit(__doc__)
    RESULTS.mkdir(exist_ok=True)
    panel("close")
    defines = {}
    if scenario == "coldstart":
        defines["AUTOPLAY"] = "false"
    if scenario == "remote-art":
        defines["ART_BASE"] = serve_art(cand)
    since = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    probe = Probe(cand, defines, RESULTS / f"raw-{cand}-{scenario}.log")
    steps = []
    try:
        {"basic": run_basic, "coldstart": run_coldstart, "remote-art": run_remote_art}[scenario](cand, steps, probe)
    finally:
        probe.quit()  # 情境中途出錯也不留下還在播的 App，免得下一個情境讀到它
    result = {
        "candidate": cand,
        "scenario": scenario,
        "date": dt.date.today().isoformat(),
        "macos": sh("sw_vers", "-productVersion"),
        "versions": versions(cand),
        "steps": steps,
        "syslog": syslog(since, BUNDLES[cand]),
    }
    out = RESULTS / f"{cand}-{scenario}.json"
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(f"wrote {out.relative_to(HERE)}")


def versions(cand):
    lock = (HERE / f"probe_{cand}/pubspec.lock").read_text()
    out = {}
    for pkg in ("audio_service", "just_audio"):
        if m := re.search(rf"^  {pkg}:\n(?:    .*\n)*?    version: \"([^\"]+)\"", lock, re.M):
            out[pkg] = m.group(1)
    out["flutter"] = sh("flutter", "--version").splitlines()[0].split()[1]
    return out


if __name__ == "__main__":
    main()
