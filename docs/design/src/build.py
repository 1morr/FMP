"""產生 docs/design/ 的設計稿頁面。

用法：python3 -I docs/design/src/build.py
輸出：docs/design/system.html、shell-a.html、shell-b.html、index.html。
樣式在 docs/design/assets/fmp.css；這裡只組版面與示意資料。
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent

# ---------- 示意資料（假資料，不代表實際曲目數據） ----------
TRACKS = [
    ("フレグランス (Fragrance/香味)", "茉ひる", "YT", None, "3:26", "1050萬", 0),
    ("一輪花 (Nightcore)", "親親2o音樂", "YT", None, "4:02", "86萬", 1),
    ("晴天", "周杰倫", "網易", "VIP", "4:29", "", 2),
    ("【初音ミク】千本桜", "黒うさP", "B站", None, "4:04", "1203萬", 3),
    ("Lemon", "米津玄師", "網易", "VIP", "4:15", "", 4),
    ("アイドル", "YOASOBI", "網易", "試聽", "3:33", "", 5),
    ("残響散歌", "Aimer", "B站", None, "3:05", "312萬", 6),
    ("富士山下", "陳奕迅", "網易", "需登入", "4:19", "", 7),
    ("Escapism.", "RAYE", "YT", None, "4:32", "270萬", 8),
    ("夜に駆ける", "YOASOBI", "B站", None, "4:21", "880萬", 9),
    ("Die For Me", "ZAYN", "YT", None, "3:47", "330萬", 10),
    ("小幸運", "田馥甄", "網易", "VIP", "4:25", "", 11),
    ("ヒロイン", "back number", "B站", None, "5:01", "95萬", 0),
    ("Homewrecker", "sombr", "YT", None, "3:39", "270萬", 2),
]
SOURCE_NAME = {"YT": "YouTube", "B站": "Bilibili", "網易": "網易雲"}

# ---------- 圖示（自繪 SVG，同一筆畫風格） ----------
ICONS = {
    "search": "M10.5 4a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13Zm0 2a4.5 4.5 0 1 0 0 9 4.5 4.5 0 0 0 0-9Zm5.2 9.8 4 4-1.4 1.4-4-4z",
    "queue": "M4 6h12v2H4zm0 5h12v2H4zm0 5h8v2H4zm14-3 4 3-4 3z",
    "library": "M5 4h2v16H5zm4 0h2v16H9zm4.2.6 1.9-.6 4.9 15.2-1.9.6z",
    "settings": "M12 8.5a3.5 3.5 0 1 1 0 7 3.5 3.5 0 0 1 0-7Zm-1.2-6h2.4l.5 2.6 1.8.8 2.2-1.5 1.7 1.7-1.5 2.2.8 1.8 2.6.5v2.4l-2.6.5-.8 1.8 1.5 2.2-1.7 1.7-2.2-1.5-1.8.8-.5 2.6h-2.4l-.5-2.6-1.8-.8-2.2 1.5-1.7-1.7 1.5-2.2-.8-1.8-2.6-.5v-2.4l2.6-.5.8-1.8-1.5-2.2 1.7-1.7 2.2 1.5 1.8-.8z",
    "pause": "M7 5h3.5v14H7zm6.5 0H17v14h-3.5z",
    "play": "M7 4.5 19 12 7 19.5z",
    "next": "M5 5l9 7-9 7zm10 0h3v14h-3z",
    "prev": "M19 5l-9 7 9 7zM6 5h3v14H6z",
    "back": "M15.4 4.6 8 12l7.4 7.4-1.4 1.4L5.2 12 14 3.2z",
    "more": "M5 10.5a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3Zm7 0a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3Zm7 0a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3Z",
    "shuffle": "M16 4h4v4l-1.5-1.5-3.3 3.3-1.4-1.4 3.3-3.3zM4 6.6 5.4 5.2l13.1 13.1L20 16.8V20h-4l1.5-1.5L4.4 5.4zM9.8 13.4l1.4 1.4-5.8 5.8L4 19.2z",
    "repeat": "M7 7h10V4l4 4-4 4V9H9v3H7zm10 10H7v3l-4-4 4-4v3h8v-3h2z",
    "locate": "M11 2h2v3.1A7 7 0 0 1 18.9 11H22v2h-3.1A7 7 0 0 1 13 18.9V22h-2v-3.1A7 7 0 0 1 5.1 13H2v-2h3.1A7 7 0 0 1 11 5.1zm1 5a5 5 0 1 0 0 10 5 5 0 0 0 0-10Zm0 3a2 2 0 1 1 0 4 2 2 0 0 1 0-4Z",
    "volume": "M4 9h4l5-4v14l-5-4H4zm12.5-1.5a6 6 0 0 1 0 9l-1.4-1.4a4 4 0 0 0 0-6.2zm2.8-2.8a10 10 0 0 1 0 14.6l-1.4-1.4a8 8 0 0 0 0-11.8z",
    "lyrics": "M4 5h16v2H4zm0 4h10v2H4zm0 4h16v2H4zm0 4h10v2H4z",
    "speaker": "M7 3h10a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Zm5 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6Zm0-6a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3Z",
    "plus": "M11 5h2v6h6v2h-6v6h-2v-6H5v-2h6z",
    "heart": "M12 20.3 4.6 13a4.6 4.6 0 0 1 6.5-6.5l.9.9.9-.9a4.6 4.6 0 0 1 6.5 6.5z",
    "thumb": "M3 10h4v10H3zm6 10V10l4-7c1.6 0 2.5 1.2 2.1 2.7L14.5 9H20a1.8 1.8 0 0 1 1.8 2.1l-1.4 7.3A2 2 0 0 1 18.4 20z",
    "playcount": "M8 5.5 18 12 8 18.5z",
    "chev": "M8.6 4.6 16 12l-7.4 7.4 1.4 1.4 8.8-8.8L10 3.2z",
}


def sprite():
    syms = "".join(f'<symbol id="i-{k}" viewBox="0 0 24 24"><path d="{v}"/></symbol>' for k, v in ICONS.items())
    return f'<svg width="0" height="0" style="position:absolute" aria-hidden="true">{syms}</svg>'


def ic(name, cls=""):
    return f'<svg class="ic {cls}" aria-hidden="true"><use href="#i-{name}"/></svg>'


# ---------- 示意封面（自繪幾何構圖，非真實專輯封面） ----------
COVERS = [
    ("#2B2F3A", "#9AA3B5", "#E9E4D8"), ("#F1C9D9", "#7B5FA8", "#FFFFFF"), ("#2F5D50", "#C9B37E", "#F2EBDD"),
    ("#13506A", "#E85D75", "#7FD1E8"), ("#E8E1C9", "#C23B3B", "#2A2A2A"), ("#191335", "#E7537B", "#F6C1D0"),
    ("#7A1F2B", "#F0B46B", "#2B0E12"), ("#5B6770", "#D8D2C4", "#1F2529"), ("#C94F2C", "#1E1E1E", "#F3D9B1"),
    ("#0C1D3D", "#F08A8A", "#FFE3A3"), ("#1D1D1F", "#B91D2A", "#E9E9E9"), ("#DCEBDF", "#3E7C5A", "#F7C948"),
]


def cover_svg(k):
    a, b, c = COVERS[k % len(COVERS)]
    kind = (k + 3) % 4
    if kind == 0:
        art = f'<rect width="100" height="100" fill="{a}"/><circle cx="64" cy="40" r="30" fill="{b}"/><rect x="0" y="72" width="100" height="6" fill="{c}"/>'
    elif kind == 1:
        art = f'<rect width="100" height="100" fill="{a}"/><path d="M0 100 L100 18 L100 100Z" fill="{b}"/><circle cx="28" cy="30" r="12" fill="{c}"/>'
    elif kind == 2:
        art = f'<rect width="100" height="100" fill="{a}"/>' + "".join(
            f'<rect x="{12 + i * 16}" y="{70 - h}" width="9" height="{h}" fill="{b if i % 2 else c}"/>' for i, h in enumerate([22, 46, 34, 58, 28])
        )
    else:
        art = f'<rect width="100" height="100" fill="{b}"/><circle cx="50" cy="50" r="40" fill="{a}"/><circle cx="50" cy="50" r="12" fill="{c}"/>'
    return f'<svg viewBox="0 0 100 100" preserveAspectRatio="xMidYMid slice">{art}</svg>'


def cover(k, size, radius=None):
    r = f";border-radius:{radius}px" if radius is not None else ""
    return f'<span class="cv" style="width:{size}px;height:{size}px{r}">{cover_svg(k)}</span>'


def access(t):
    return {
        "VIP": '<span class="tag vip">VIP</span>',
        "試聽": '<span class="tag trial">試聽</span>',
        "需登入": '<span class="tag login">需登入</span>',
    }.get(t, "")


def track_row(i, t, cls=""):
    title, artist, src, acc, dur, plays, k = t
    meta = artist + (f" · {plays} 次播放" if plays else "")
    return (
        f'<li class="tr {cls}{" off" if acc == "需登入" else ""}"><span class="ix">{i}</span>{cover(k, 44)}'
        f'<span class="tx"><b>{title}</b><i>{meta}</i></span>'
        f'<span class="mt"><span class="tags"><span class="tag">{src}</span>{access(acc)}</span><span class="du">{dur}</span></span></li>'
    )


# ---------- 手機外框 ----------
def statusbar():
    return ('<div class="sb"><span>15:15</span><span class="sbi">'
            '<svg viewBox="0 0 18 12" width="18" height="12"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5" width="3" height="7" rx="1"/><rect x="10" y="2" width="3" height="10" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></svg>'
            '<svg viewBox="0 0 27 12" width="27" height="12"><rect x=".5" y=".5" width="23" height="11" rx="3" fill="none" stroke="currentColor" opacity=".5"/><rect x="2" y="2" width="16" height="8" rx="1.5"/><rect x="25" y="4" width="2" height="4" rx="1" opacity=".5"/></svg>'
            '</span></div>')


def phone(theme, inner, caption):
    return (f'<figure class="frame"><div class="phone {theme}">{statusbar()}{inner}<div class="homebar"></div></div>'
            f'<figcaption>{caption}</figcaption></figure>')


def spine(cls_pos, progress=0.31, sub="茉ひる · 1:04 / 3:26", compact=False):
    pct = f"{progress * 100:.0f}%"
    return (f'<div class="spine glass {cls_pos}"><span class="pl" style="width:{pct}"></span><span class="fold" style="left:{pct}"></span>'
            f'{cover(0, 32 if compact else 40)}<span class="t"><b>フレグランス (Fragrance/香味)</b><i>{sub}</i></span>'
            f'<span class="c">{ic("pause", "l")}{"" if compact else ic("next", "l")}</span></div>')


A_TABS = [("search", "搜尋"), ("queue", "佇列"), ("library", "音樂庫"), ("settings", "設定")]


def tabbar_a(active):
    items = "".join(f'<span class="ni{" on" if l == active else ""}">{ic(i)}<span>{l}</span></span>' for i, l in A_TABS)
    return f'<nav class="tabbar-a glass" aria-label="主要導覽">{items}</nav>'


def playlist_header():
    return (f'<div class="topbar">{ic("back", "l")}<span class="tb-title">音樂庫</span>{ic("more", "l")}</div>'
            f'<header class="plh">{cover(0, 96)}<div class="plh-t"><h1>通勤用</h1><p>本地歌單 · 42 首 · 2 小時 48 分</p>'
            f'<div class="plh-b"><span class="btn pri">{ic("play", "s")}播放</span><span class="btn ton">{ic("shuffle", "s")}隨機</span></div></div></header>')


def track_list(rows=TRACKS, start=1, now=1):
    return '<ul class="tl">' + "".join(track_row(start + i, t, "now" if start + i == now else "") for i, t in enumerate(rows)) + "</ul>"


def phone_a_playlist(theme):
    inner = f'<div class="scroll">{playlist_header()}{track_list()}</div>{spine("sp-a")}{tabbar_a("音樂庫")}'
    return phone(theme, inner, f"A · 歌單詳情 · {'深色' if theme == 't-dark' else '淺色'}")


NOW_ROW = (f'<li class="tr now"><span class="ix">13</span>{cover(0, 44)}<span class="tx"><b>フレグランス (Fragrance/香味)</b><i>茉ひる · 1050萬 次播放</i></span>'
           f'<span class="mt"><span class="tags"><span class="tag">YT</span></span><span class="du">1:04 / 3:26</span></span></li>')


REPEAT = {"off": ("repeat", "不循環", False), "all": ("repeat", "列表循環", True), "one": ("repeat", "單曲循環", True)}


def toggles(shuffle, repeat):
    """隨機與循環：同一組裡的兩顆圖示鈕，各自獨立開關，可以同時開。開啟時淡紫底、強調色圖示。"""
    ri, rl, ron = REPEAT[repeat]
    one = '<span class="one">1</span>' if repeat == "one" else ""
    return (f'<span class="qm"><span class="qb{" on" if shuffle else ""}" role="switch" aria-checked="{str(shuffle).lower()}" aria-label="隨機">{ic("shuffle", "s")}</span>'
            f'<span class="qb{" on" if ron else ""}" role="button" aria-label="{rl}">{ic("repeat", "s")}{one}</span></span>')


def queue_header(shuffle, repeat):
    return (f'<header class="qh"><div><h1>佇列</h1><p class="qmeta">42 首 · 剩 1 小時 52 分</p></div>'
            f'<span class="qctl"><span class="qb solo" role="button" aria-label="跳到正在播放">{ic("locate", "s")}</span>{toggles(shuffle, repeat)}</span></header>')


def queue_body(shuffle=False, repeat="off"):
    """佇列畫面永遠是播放順序。播過的在上方變淡，摺線在正在播的那首下方，不寫字。"""
    played = TRACKS[10:12]
    upcoming = TRACKS[1:9]
    return (queue_header(shuffle, repeat)
            + '<ul class="tl">' + "".join(track_row(11 + i, t, "played") for i, t in enumerate(played)) + NOW_ROW + '</ul>'
            + '<div class="foldrule" role="separator"></div>'
            + '<ul class="tl">' + "".join(track_row(14 + i, t) for i, t in enumerate(upcoming)) + '</ul>')


def phone_a_queue(theme, shuffle=False, repeat="off"):
    inner = f'<div class="scroll">{queue_body(shuffle, repeat)}</div>{spine("sp-a")}{tabbar_a("佇列")}'
    note = "隨機＋列表循環同時開：畫面是打亂後的播放順序" if shuffle else "隨機關、不循環：摺線標正在播"
    return phone(theme, inner, f"A · 佇列（{note}）· {'深色' if theme == 't-dark' else '淺色'}")


# ---------- 外殼 B（Apple Music 式） ----------
B_TABS = [("library", "音樂庫"), ("queue", "佇列"), ("settings", "設定")]


def tabbar_b(active):
    items = "".join(f'<span class="ni{" on" if l == active else ""}">{ic(i)}<span>{l}</span></span>' for i, l in B_TABS)
    return (f'<nav class="tabbar-b glass" aria-label="主要導覽">{items}</nav>'
            f'<span class="orb glass orb-search" aria-label="搜尋">{ic("search", "l")}</span>')


def phone_b(theme, collapsed):
    if collapsed:
        rows = TRACKS[3:14]
        body = (f'<div class="scroll scrolled"><ul class="tl">' + "".join(track_row(4 + i, t) for i, t in enumerate(rows)) + '</ul></div>'
                '<div class="edge"></div>'
                f'<span class="orb glass orb-tab" aria-label="音樂庫">{ic("library", "l")}</span>'
                f'{spine("sp-b-col", sub="1:04 / 3:26", compact=True)}'
                f'<span class="orb glass orb-search" aria-label="搜尋">{ic("search", "l")}</span>')
        cap = "B · 往下捲：導覽收成圓鈕"
    else:
        body = (f'<div class="scroll"><div class="topbar b">{ic("back", "l")}{ic("more", "l")}</div>'
                f'<header class="plh big">{cover(0, 96)}<div class="plh-t"><h1>通勤用</h1><p>本地歌單 · 42 首 · 2 小時 48 分</p>'
                f'<div class="plh-b"><span class="btn pri">{ic("play", "s")}播放</span><span class="btn ton">{ic("shuffle", "s")}隨機</span></div></div></header>'
                f'{track_list()}</div>{spine("sp-b")}{tabbar_b("音樂庫")}')
        cap = "B · 展開"
    return phone(theme, body, f"{cap} · {'深色' if theme == 't-dark' else '淺色'}")


# ---------- 桌面 ----------
def desk_row(i, t, now=False):
    title, artist, src, acc, dur, plays, k = t
    return (f'<li class="dr{" now" if now else ""}{" off" if acc == "需登入" else ""}"><span class="ix">{i}</span>{cover(k, 36)}'
            f'<span class="tx"><b>{title}</b><i>{artist}</i></span><span class="c-src"><span class="tag">{SOURCE_NAME[src]}</span></span>'
            f'<span class="c-acc">{access(acc)}</span><span class="c-pl">{plays or "—"}</span><span class="du">{dur}</span></li>')


def desk_table():
    head = '<div class="dh"><span>#</span><span></span><span>標題</span><span>音源</span><span>存取</span><span>播放量</span><span>時長</span></div>'
    return head + '<ul class="dl">' + "".join(desk_row(i + 1, t, i == 0) for i, t in enumerate(TRACKS)) + "</ul>"


def desk_main():
    return (f'<header class="dplh">{cover(0, 132)}<div><h1>通勤用</h1><p>本地歌單 · 42 首 · 2 小時 48 分 · 音源：Bilibili 14、YouTube 16、網易雲 12</p>'
            f'<div class="plh-b"><span class="btn pri">{ic("play", "s")}播放</span><span class="btn ton">{ic("shuffle", "s")}隨機</span><span class="btn out">{ic("plus", "s")}加入佇列</span></div></div></header>'
            f'{desk_table()}')


def desk_panel():
    return (f'<aside class="dpanel">{cover(0, 296, 10)}<h2>フレグランス (Fragrance/香味)</h2><p class="who">茉ひる · YouTube · 1 年前</p>'
            f'<div class="stats"><span>{ic("playcount", "s")}1050.7萬</span><span>{ic("thumb", "s")}8.4萬</span></div>'
            f'<h3>{ic("next", "s")}下一首</h3><div class="nxt">{cover(1, 48)}<span class="tx"><b>一輪花 (Nightcore)</b><i>親親2o音樂</i></span></div>'
            f'<h3>簡介</h3><p class="desc">フレグランス／Fragrance／香味。茉ひる & RINZO。</p></aside>')


def desk_player(cls):
    return (f'<div class="dplayer glass {cls}"><span class="pl" style="width:31%"></span><span class="fold" style="left:31%"></span>'
            f'<div class="dp-l">{cover(0, 48)}<span class="tx"><b>フレグランス (Fragrance/香味)</b><i>茉ひる</i></span>{ic("heart", "s")}</div>'
            f'<div class="dp-c"><span class="it on" aria-label="隨機：開">{ic("shuffle", "s")}</span>{ic("prev")}<span class="pp">{ic("pause", "l")}</span>{ic("next")}<span class="it on" aria-label="列表循環">{ic("repeat", "s")}</span><span class="du">1:04 / 3:26</span></div>'
            f'<div class="dp-r">{ic("lyrics", "s")}{ic("queue", "s")}{ic("speaker", "s")}{ic("volume", "s")}<span class="vol"><span></span></span></div></div>')


def titlebar():
    return '<div class="wtitle"><span class="lights"><i></i><i></i><i></i></span><span>FMP</span></div>'


def desk_a(theme):
    rail = "".join(f'<span class="rn{" on" if l == "音樂庫" else ""}">{ic(i)}<span>{l}</span></span>' for i, l in A_TABS)
    inner = (f'{titlebar()}<div class="dbody a"><nav class="rail" aria-label="主要導覽">{rail}</nav>'
             f'<main class="dmain">{desk_main()}</main>{desk_panel()}</div>{desk_player("dp-a")}')
    return (f'<figure class="frame"><div class="desk {theme}">{inner}</div>'
            f'<figcaption>A · 桌面（expanded，1280×800）· {"深色" if theme == "t-dark" else "淺色"}</figcaption></figure>')


def desk_b(theme):
    pls = [("通勤用", 0, True), ("工作背景", 2, False), ("Vocaloid", 3, False), ("網易雲 · 我喜歡的音樂", 4, False), ("匯入 · B站收藏夾", 6, False)]
    side = (f'<div class="sfield">{ic("search", "s")}<span>搜尋三個音源</span></div>'
            + "".join(f'<span class="sn">{ic(i)}<span>{l}</span></span>' for i, l in B_TABS)
            + '<p class="sh">歌單</p>'
            + "".join(f'<span class="sp{" on" if on else ""}">{cover(k, 24, 4)}<span>{n}</span></span>' for n, k, on in pls))
    inner = (f'{titlebar()}<div class="dbody b"><nav class="side" aria-label="主要導覽">{side}</nav>'
             f'<main class="dmain">{desk_main()}</main>{desk_panel()}</div>{desk_player("dp-b")}')
    return (f'<figure class="frame"><div class="desk {theme}">{inner}</div>'
            f'<figcaption>B · 桌面（內縮側欄＋浮動播放膠囊，1280×800）· {"深色" if theme == "t-dark" else "淺色"}</figcaption></figure>')


# ---------- 頁面 ----------
PAGE_CSS = """
body.doc{background:#2A2A2D;color:#EDEDEA;font:15px/1.6 var(--font);padding:40px 48px 80px}
.doc h1.pt{font-size:28px;line-height:1.25;margin-bottom:8px}
.doc .lead{max-width:72ch;color:#C8C7C2;margin-bottom:8px}
.doc .note{max-width:72ch;color:#A9A8A3;font-size:13px;margin-bottom:28px}
.doc h2.sec{font-size:20px;margin:48px 0 16px;padding-top:24px;border-top:1px solid rgba(255,255,255,.12)}
.doc .navl{display:flex;gap:16px;margin-bottom:24px;font-size:14px}
.doc .navl a{color:#CFBCFF;text-underline-offset:3px}
.row{display:flex;flex-wrap:wrap;gap:32px;align-items:flex-start;overflow-x:auto;padding:12px;margin:-12px}
.frame{flex:none}
@media (max-width:600px){body.doc{padding:24px 16px 60px}.row{flex-wrap:nowrap}.sys{grid-template-columns:minmax(0,1fr)}}
.frame figcaption{margin-top:10px;font-size:13px;color:#C8C7C2}
.phone{position:relative;width:390px;height:844px;border-radius:48px;overflow:hidden;box-shadow:0 0 0 10px #0B0B0C,0 20px 50px rgba(0,0,0,.45)}
.sb{position:absolute;top:0;left:0;right:0;z-index:5;height:50px;display:flex;align-items:center;justify-content:space-between;padding:0 30px 0 38px;font-weight:600;font-size:16px}
.sbi{display:flex;gap:6px;align-items:center}.sbi svg{fill:currentColor}
.homebar{position:absolute;z-index:6;left:50%;bottom:8px;width:134px;height:5px;border-radius:3px;background:var(--fg);transform:translateX(-50%)}
.scroll{position:absolute;inset:0;padding-top:50px;overflow:hidden}
.scroll.scrolled{padding-top:0}
.topbar{display:flex;align-items:center;justify-content:space-between;height:44px;padding:0 14px;color:var(--fg)}
.topbar .tb-title{font-size:var(--fs-title);font-weight:600}
.topbar.b{justify-content:space-between}
.plh{display:flex;gap:16px;padding:8px 20px 16px;align-items:flex-start}
.plh-t h1{font-size:var(--fs-h2);line-height:32px;font-weight:700}
.plh-t p{font-size:var(--fs-sm);color:var(--fg2);margin-top:2px}
.plh-b{display:flex;gap:8px;margin-top:12px}
.plh.big{flex-direction:column;align-items:flex-start;padding-top:0}
.plh.big h1{font-size:var(--fs-h1);line-height:38px}
.sp-a{left:12px;right:12px;bottom:104px}
.tabbar-a{position:absolute;left:12px;right:12px;bottom:30px;height:64px;border-radius:32px;display:flex;align-items:center;justify-content:space-around;padding:0 6px}
.ni{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px;font-size:var(--fs-cap);color:var(--fg2);width:78px;height:54px;border-radius:27px;font-weight:500}
.ni.on{color:var(--accent);background:var(--accent-soft)}
.sp-b{left:12px;right:12px;bottom:104px}
.tabbar-b{position:absolute;left:12px;right:76px;bottom:30px;height:64px;border-radius:32px;display:flex;align-items:center;justify-content:space-around;padding:0 6px}
.orb{position:absolute;width:56px;height:56px;border-radius:28px;display:flex;align-items:center;justify-content:center;color:var(--fg)}
.orb-search{right:12px;bottom:34px}
.orb-tab{left:12px;bottom:34px;color:var(--accent)}
.sp-b-col{left:76px;right:76px;bottom:34px;height:56px;border-radius:28px;padding:0 14px 0 12px}
.edge{position:absolute;left:0;right:0;top:0;height:96px;z-index:4;background:linear-gradient(var(--bg) 52%,transparent);-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px);-webkit-mask:linear-gradient(#000 55%,transparent);mask:linear-gradient(#000 55%,transparent)}
.qh{display:flex;align-items:flex-end;gap:12px;justify-content:space-between;padding:12px 20px 10px}
.qh h1{font-size:var(--fs-h1);line-height:38px;font-weight:700}
.qmeta{font-size:var(--fs-sm);color:var(--fg2)}
.qctl{display:flex;gap:8px;align-items:center}
/* 桌面 */
.desk{position:relative;width:1280px;height:800px;border-radius:12px;overflow:hidden;box-shadow:0 0 0 1px rgba(0,0,0,.6),0 24px 60px rgba(0,0,0,.45)}
.wtitle{height:36px;display:flex;align-items:center;gap:14px;padding:0 14px;font-size:13px;color:var(--fg2);border-bottom:1px solid var(--line)}
.lights{display:flex;gap:8px}.lights i{width:12px;height:12px;border-radius:50%;background:var(--line-strong)}
.dbody{position:absolute;top:36px;bottom:0;left:0;right:0;display:grid}
.dbody.a{grid-template-columns:76px minmax(0,1fr) 352px}
.dbody.b{grid-template-columns:256px minmax(0,1fr) 352px}
.rail{background:var(--bg2);display:flex;flex-direction:column;align-items:center;gap:6px;padding-top:14px;border-right:1px solid var(--line)}
.rn{display:flex;flex-direction:column;align-items:center;gap:3px;width:60px;padding:8px 0;border-radius:14px;font-size:var(--fs-cap);color:var(--fg2);font-weight:500}
.rn.on{color:var(--accent);background:var(--accent-soft)}
.side{margin:12px 0 12px 12px;border-radius:18px;background:var(--bg2);border:1px solid var(--line);padding:12px 10px;display:flex;flex-direction:column;gap:2px;z-index:3}
.sfield{display:flex;align-items:center;gap:8px;height:34px;padding:0 10px;border-radius:10px;background:var(--line);color:var(--fg2);font-size:var(--fs-sm);margin-bottom:8px}
.sn,.sp{display:flex;align-items:center;gap:10px;height:34px;padding:0 10px;border-radius:10px;font-size:14px;color:var(--fg)}
.sn:first-of-type{color:var(--accent);background:var(--accent-soft)}
.sp.on{background:var(--line)}
.sh{font-size:var(--fs-cap);color:var(--fg2);padding:14px 10px 4px;font-weight:600}
.dmain{overflow:hidden;padding:0 0 0 0}
.dplh{display:flex;gap:20px;align-items:flex-end;padding:22px 28px 18px}
.dplh h1{font-size:var(--fs-h1);line-height:40px;font-weight:700}
.dplh p{font-size:var(--fs-sm);color:var(--fg2)}
.dh,.dr{display:grid;grid-template-columns:28px 36px minmax(0,1fr) 84px 56px 72px 52px;column-gap:12px;align-items:center;padding:0 28px 0 16px}
.dh{height:30px;font-size:var(--fs-cap);color:var(--fg2);border-bottom:1px solid var(--line-strong);font-weight:600}
.dr{height:52px;border-bottom:1px solid var(--line)}
.dr .ix{font-size:var(--fs-meta);color:var(--fg3);text-align:right}
.dr .tx{display:flex;flex-direction:column;gap:2px;min-width:0}.dr .tx b{font-weight:500;font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.dr .tx i{font-style:normal;font-size:var(--fs-meta);color:var(--fg2)}
.dr .c-pl{font-size:var(--fs-meta);color:var(--fg2);text-align:right}.dr .du{text-align:right}
.dr.now .tx b,.dr.now .ix{color:var(--accent)}
.dr.off .tx b,.dr.off .tx i,.dr.off .du,.dr.off .ix,.dr.off .c-pl{color:var(--fg3)}.dr.off .cv{opacity:.45}
.dpanel{background:var(--bg2);border-left:1px solid var(--line);padding:24px 28px;overflow:hidden}
.dpanel h2{font-size:var(--fs-h3);line-height:1.3;margin-top:18px}
.dpanel .who{font-size:var(--fs-sm);color:var(--fg2);margin-top:4px}
.stats{display:flex;gap:24px;margin:14px 0 6px;font-size:var(--fs-sm);font-weight:600}.stats span{display:flex;align-items:center;gap:6px}
.dpanel h3{display:flex;align-items:center;gap:6px;font-size:var(--fs-sm);color:var(--fg2);margin:20px 0 10px;padding-top:16px;border-top:1px solid var(--line)}
.nxt{display:flex;gap:12px;align-items:center}.nxt .tx{display:flex;flex-direction:column;gap:2px}.nxt b{font-weight:500;font-size:14px}.nxt i{font-style:normal;font-size:var(--fs-meta);color:var(--fg2)}
.desc{font-size:var(--fs-sm);color:var(--fg2)}
.dplayer{position:absolute;display:grid;grid-template-columns:1fr auto 1fr;align-items:center;overflow:hidden;z-index:5}
.dplayer .pl{position:absolute;left:0;top:0;bottom:0;background:var(--played)}
.dplayer .fold{position:absolute;top:0;bottom:0;border-left:2px solid var(--accent);box-shadow:-1px 0 0 var(--crease-lo),1px 0 0 var(--crease-hi);-webkit-mask:var(--fold-mask);mask:var(--fold-mask)}
.dp-a{left:12px;right:12px;bottom:12px;height:72px;border-radius:18px;padding:0 20px}
.dp-b{left:280px;right:364px;bottom:14px;height:68px;border-radius:18px;padding:0 16px;grid-template-columns:minmax(0,1fr) auto auto;column-gap:16px}
.dplayer .du{white-space:nowrap}
.dp-l,.dp-c,.dp-r{position:relative;display:flex;align-items:center;gap:14px}
.dp-l .tx{display:flex;flex-direction:column;gap:2px;min-width:0}.dp-l b{font-size:14px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:200px}.dp-l i{font-style:normal;font-size:var(--fs-meta);color:var(--fg2)}
.dp-c{gap:18px}.pp{width:40px;height:40px;border-radius:20px;background:var(--fg);color:var(--bg);display:flex;align-items:center;justify-content:center}
.dp-r{justify-content:flex-end;color:var(--fg2)}
.vol{width:84px;height:4px;border-radius:2px;background:var(--line-strong);display:block}.vol span{display:block;width:70%;height:100%;border-radius:2px;background:var(--fg)}
.dp-b .dp-l b{max-width:170px}.dp-b .dp-l .ic,.dp-b .dp-c>.ic.s,.dp-b .dp-r .ic:nth-child(3),.dp-b .vol{display:none}.dp-b .dp-c{gap:14px}.dp-b .dp-r{gap:12px}
/* 系統頁 */
.sys{display:grid;grid-template-columns:repeat(2,minmax(0,560px));gap:32px}
.card{border-radius:16px;padding:24px;overflow:hidden}
.card h3{font-size:var(--fs-title);margin-bottom:14px}
.sw{display:grid;grid-template-columns:44px 1fr auto;gap:12px;align-items:center;padding:6px 0;border-bottom:1px solid var(--line);font-size:var(--fs-sm)}
.sw i{width:44px;height:28px;border-radius:6px;border:1px solid var(--line-strong)}
.sw code{font:var(--fs-meta) var(--mono);color:var(--fg2)}
.ts{display:grid;grid-template-columns:120px 1fr;gap:12px;align-items:baseline;padding:6px 0;border-bottom:1px solid var(--line)}
.ts code{font:var(--fs-meta) var(--mono);color:var(--fg2)}
.sp-demo{display:flex;align-items:flex-end;gap:10px;padding-top:6px}
.sp-demo span{display:block;background:var(--accent-soft);border:1px solid var(--accent)}
.sp-demo figure{display:flex;flex-direction:column;align-items:center;gap:6px;font:var(--fs-cap) var(--mono);color:var(--fg2)}
.wc{display:grid;grid-template-columns:1fr;gap:8px;font-size:var(--fs-sm)}
.wc div{display:grid;grid-template-columns:110px 1fr;gap:12px;padding:8px 0;border-bottom:1px solid var(--line)}
.glassdemo{position:relative;height:220px;border-radius:12px;overflow:hidden;background:var(--bg)}
.glassdemo ul{position:absolute;inset:0}
.glassdemo .spine{left:16px;right:16px;bottom:16px}
.stl{font-size:var(--fs-meta);color:var(--fg2);margin-top:8px}
.tagrow{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-bottom:12px}
.accents{display:flex;gap:10px;flex-wrap:wrap}
.accents figure{display:flex;flex-direction:column;align-items:center;gap:6px;font-size:var(--fs-cap);color:var(--fg2)}
.accents i{width:36px;height:36px;border-radius:18px;display:block;border:1px solid var(--line-strong)}
.accents .x i{opacity:.35;background-image:linear-gradient(135deg,transparent 47%,var(--fg) 47%,var(--fg) 53%,transparent 53%)!important}
"""


def html(title, body):
    return (f'<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>{title}</title><link rel="stylesheet" href="assets/fmp.css"><style>{PAGE_CSS}</style></head>'
            f'<body class="doc t-dark">{sprite()}{body}</body></html>')


def navlinks():
    return ('<nav class="navl"><a href="index.html">總覽</a><a href="system.html">設計系統</a>'
            '<a href="shell-a.html">外殼 A</a><a href="shell-b.html">外殼 B</a></nav>')


NOTE = '<p class="note">曲目、播放量與封面都是示意資料；封面是自繪的幾何圖，不是真實專輯封面。強調色用預設的 FMP 紫。</p>'


def page_shell_a():
    body = (navlinks() + '<h1 class="pt">外殼 A：舊版結構換成玻璃</h1>'
            '<p class="lead">手機是底部分頁列加上方的迷你播放器；桌面是左側導覽軌、右側詳情面板、底部播放列。位置都照舊版，只把浮在內容上的控制層換成玻璃，捲動時不收合。</p>' + NOTE
            + '<h2 class="sec">手機</h2><div class="row">' + phone_a_playlist("t-dark") + phone_a_playlist("t-light")
            + phone_a_queue("t-dark") + phone_a_queue("t-light", True, "all") + '</div>'
            + '<h2 class="sec">桌面</h2><div class="row">' + desk_a("t-dark") + desk_a("t-light") + '</div>')
    return html("FMP 設計稿 · 外殼 A", body)


def page_shell_b():
    body = (navlinks() + '<h1 class="pt">外殼 B：Apple Music 式浮動膠囊</h1>'
            '<p class="lead">手機上迷你播放器和分頁列是兩條浮動膠囊，搜尋獨立成右側圓鈕。往下捲時分頁列收成一顆顯示目前分頁的圓鈕，迷你播放器移到中間；頂部沒有實心標題列，大標題跟著內容捲走，狀態列下方漸進淡出。桌面是內縮的側欄（含搜尋與歌單，實心：它底下沒有內容捲過，玻璃在這裡只會是裝飾）和浮動玻璃播放膠囊，右側詳情面板保留。</p>'
            '<p class="note">B 的分頁是音樂庫、佇列、設定三項。第一版沒有首頁和電台，所以收合省下的主要是畫面空間；之後分頁變多，B 的好處才會明顯。</p>' + NOTE
            + '<h2 class="sec">手機</h2><div class="row">' + phone_b("t-dark", False) + phone_b("t-dark", True)
            + phone_b("t-light", False) + phone_b("t-light", True) + '</div>'
            + '<h2 class="sec">桌面</h2><div class="row">' + desk_b("t-dark") + desk_b("t-light") + '</div>')
    return html("FMP 設計稿 · 外殼 B", body)


ACCENTS = [("預設紫", "#6750A4", "#CFBCFF", True), ("靛藍", "#3F51B5", "#BAC3FF", True), ("藍", "#0061A4", "#9FCAFF", True),
           ("青綠", "#006A6A", "#4CDADA", True), ("綠", "#006E1C", "#78DC77", True), ("黃", "#F9A825", "#F9A825", False),
           ("橙", "#7C5800", "#F5BF48", True), ("紅", "#BA1A1A", "#FFB4AB", True), ("粉", "#984061", "#FFB0C8", True)]


def system_card(theme):
    name = "深色" if theme == "t-dark" else "淺色"
    colors = [("--bg", "底"), ("--bg2", "第二層底（面板、導覽軌）"), ("--fg", "主要文字"), ("--fg2", "次要文字"), ("--fg3", "序號、已播"),
              ("--accent", "強調色（互動與目前狀態）"), ("--vip", "VIP（唯一的實心標籤）"), ("--trial", "試聽")]
    sw = "".join(f'<div class="sw"><i style="background:var({v})"></i><span>{l}</span><code>{v}</code></div>' for v, l in colors)
    tags = ('<div class="tagrow"><span class="tag">B站</span><span class="tag">YT</span><span class="tag">網易</span>'
            '<span class="tag vip">VIP</span><span class="tag trial">試聽</span><span class="tag login">需登入</span></div>')
    togrow = ('<div class="tagrow" style="gap:16px">' + toggles(False, "off") + toggles(True, "all") + toggles(True, "one") + '</div>'
              '<p class="stl" style="margin:-4px 0 12px">隨機與循環是同一組裡的兩顆獨立開關：依序是兩個都關、隨機＋列表循環、隨機＋單曲循環</p>')
    btns = f'<div class="tagrow"><span class="btn pri">{ic("play", "s")}播放</span><span class="btn ton">{ic("shuffle", "s")}隨機</span><span class="btn out">{ic("plus", "s")}加入佇列</span></div>'
    demo = ('<div class="glassdemo"><ul class="tl">' + "".join(track_row(i + 1, t, "now" if i == 0 else "") for i, t in enumerate(TRACKS[:4]))
            + '</ul>' + spine("", 0.31).replace('class="spine glass "', 'class="spine glass"') + '</div>')
    return (f'<div class="card {theme}"><h3>色彩 · {name}</h3>{sw}</div>'
            f'<div class="card {theme}"><h3>元件 · {name}</h3>{tags}{btns}{togrow}'
            f'<ul class="tl">{track_row(3, TRACKS[2])}{track_row(6, TRACKS[5])}{track_row(8, TRACKS[7], "off")}</ul>'
            f'<h3 style="margin-top:20px">狀態</h3><ul class="tl">{track_row(4, TRACKS[3], "hover")}{track_row(5, TRACKS[4], "pressed")}{track_row(7, TRACKS[6], "focus")}{track_row(8, TRACKS[7], "off")}</ul>'
            f'<p class="stl">由上而下：滑鼠移入、按下、鍵盤焦點、不能播（需登入，整列變淡，點了引導登入）</p>'
            f'<div class="tagrow" style="margin-top:12px"><span class="btn pri focus">{ic("play", "s")}焦點</span><span class="btn pri dis">{ic("play", "s")}停用</span><span class="ni on focus" style="width:78px">{ic("library")}<span>焦點</span></span></div>'
            f'<h3 style="margin-top:20px">玻璃只在浮動控制層</h3>{demo}</div>')


def page_system():
    type_rows = [("32 · 大標題", "--fs-h1", 32, 700), ("26 · 頁標題", "--fs-h2", 26, 700), ("20 · 區段", "--fs-h3", 20, 700), ("17 · 標題列", "--fs-title", 17, 600),
                 ("15 · 內文、曲名", "--fs-body", 15, 500), ("13 · 說明", "--fs-sm", 13, 400), ("12 · 歌手、時長", "--fs-meta", 12, 400), ("11 · 標籤", "--fs-cap", 11, 500)]
    ts = "".join(f'<div class="ts"><code>{v}</code><span style="font-size:{px}px;font-weight:{w}">{l} 通勤用 フレグランス</span></div>' for l, v, px, w in type_rows)
    spacing = "".join(f'<figure><span style="width:{n}px;height:{n}px"></span>{n}</figure>' for n in [4, 8, 12, 16, 20, 24, 32])
    acc = "".join(f'<figure class="{"" if ok else "x"}"><i style="background:linear-gradient(90deg,{l} 50%,{d} 50%)"></i>{n}</figure>' for n, l, d, ok in ACCENTS)
    body = (navlinks() + '<h1 class="pt">設計系統：卡帶 J-card</h1>'
            '<p class="lead">介面像一張摺起來的卡帶曲目卡：曲目密排、時長對齊成一欄、一條摺線把已播和接下來分開。玻璃只用在浮在內容上的控制層，內容一律實心；層級只靠疊放，內容本身不加陰影。</p>' + NOTE
            + '<h2 class="sec">色彩與元件</h2><div class="sys">' + system_card("t-dark") + system_card("t-light") + '</div>'
            + '<h2 class="sec">字級</h2><div class="sys"><div class="card t-dark">' + ts + '</div>'
            '<div class="card t-dark"><h3>字型</h3><p class="desc" style="font-size:14px;color:var(--fg2)">一個系統字族撐全部：Apple 平台用 PingFang TC，Windows 用 Microsoft JhengHei UI，Android 用 Noto Sans TC／Roboto。數字一律等寬（tabular）；時長與計時用等寬字型，對齊成一欄。比例約 1.2，字級跟系統字級設定縮放。</p>'
            '<h3 style="margin-top:20px">間距（4pt 網格）</h3><div class="sp-demo">' + spacing + '</div>'
            '<h3 style="margin-top:20px">列高</h3><p class="desc" style="font-size:14px;color:var(--fg2)">手機曲目列 60（封面 44），桌面曲目列 52（封面 36），固定不隨內容長短變。圓角：封面 6、標籤 4、按鈕 12、書脊 16、sheet 20。</p></div></div>'
            + '<h2 class="sec">寬度分級</h2><div class="sys"><div class="card t-dark wc">'
            '<div><b>compact</b><span>&lt; 600：底部分頁列，迷你播放器在上方（A）或浮動膠囊（B）</span></div>'
            '<div><b>medium</b><span>600–839：左側收合導覽軌，播放列在底部</span></div>'
            '<div><b>expanded</b><span>≥ 840：導覽軌（A）或浮動側欄（B）＋內容＋有目前曲目時的右側詳情面板</span></div></div>'
            '<div class="card t-dark"><h3>強調色預設（左淺色、右深色）</h3><div class="accents">' + acc + '</div>'
            '<p class="desc" style="font-size:13px;color:var(--fg2);margin-top:14px">沿用舊版 9 色。黃色在淺色底上和白字、和底色的對比都不足，劃掉；其餘 8 色淺色用原值、深色用同色相的淺階。強調色只標互動與目前狀態，玻璃與底色不帶它。</p></div></div>')
    return html("FMP 設計稿 · 設計系統", body)


def page_index():
    body = (navlinks() + '<h1 class="pt">FMP 新版設計稿（D）</h1>'
            '<p class="lead">第一步：設計系統與 App 外殼。外殼出 A、B 兩版，選定後其餘頁面照選定的外殼做。決定依據見 docs/design-brief.md §11。</p>' + NOTE
            + '<ul style="line-height:2"><li><a style="color:#CFBCFF" href="system.html">設計系統</a>：色彩、字級、間距、寬度分級、玻璃與實心材質、元件</li>'
            '<li><a style="color:#CFBCFF" href="shell-a.html">外殼 A</a>：舊版結構換成玻璃</li>'
            '<li><a style="color:#CFBCFF" href="shell-b.html">外殼 B</a>：Apple Music 式浮動膠囊與捲動收合</li></ul>')
    return html("FMP 設計稿", body)


if __name__ == "__main__":
    for name, fn in [("index.html", page_index), ("system.html", page_system), ("shell-a.html", page_shell_a), ("shell-b.html", page_shell_b)]:
        (ROOT / name).write_text(fn(), encoding="utf-8")
    print("written:", ROOT)
