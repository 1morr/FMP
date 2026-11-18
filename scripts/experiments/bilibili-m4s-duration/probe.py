#!/usr/bin/env python3
"""票 06b：B 站 DASH 音訊軌（.m4s）的時長寫在哪幾個 box。

匿名，請求數：search 1（沒給 bvid 時）、pagelist 1、playurl 1，再對選到的
音訊網址發 1 次 Range 請求抓開頭 256 KB，印出 box 結構與各處的時長。不印
網址的 query。可選 --save <檔> 把整條串流存下來（多 1 次請求），給本機假
CDN 重現用；存下的檔不進 repo。

用法：probe.py [--bvid BV...] [--query lofi] [--save <檔>]
"""
import argparse, gzip, http.cookiejar, json, struct, sys, urllib.parse, urllib.request, uuid, time

UA = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
U = str(uuid.uuid4()).upper()
COOKIE = f'buvid3={U}infoc; buvid4={U}; b_nut={int(time.time())}; _uuid={U}; buvid_fp={U}'


def api(url, referer='https://www.bilibili.com/', origin='https://www.bilibili.com'):
    req = urllib.request.Request(url, headers={
        'User-Agent': UA, 'Referer': referer, 'Origin': origin, 'Cookie': COOKIE,
        'Accept-Encoding': 'gzip', 'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'})
    with urllib.request.urlopen(req, timeout=20) as r:
        body = r.read()
        if r.headers.get('Content-Encoding') == 'gzip':
            body = gzip.decompress(body)
    j = json.loads(body)
    if j.get('code') != 0:
        sys.exit(f'api code {j.get("code")}: {j.get("message")}')
    return j['data']


def media(url, rng=None):
    h = {'User-Agent': UA, 'Referer': 'https://www.bilibili.com'}
    if rng:
        h['Range'] = rng
    return urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=60)


def boxes(buf, off, end, depth=0, out=None):
    while off + 8 <= end:
        size, typ = struct.unpack('>I4s', buf[off:off + 8])
        typ = typ.decode('latin1')
        hdr = 8
        if size == 1:
            size = struct.unpack('>Q', buf[off + 8:off + 16])[0]; hdr = 16
        elif size == 0:
            size = end - off
        print(f'{"  " * depth}{typ} @{off} size={size}')
        body = buf[off + hdr:min(off + size, end)]
        if typ in ('moov', 'trak', 'mdia', 'minf', 'stbl', 'mvex', 'edts'):
            boxes(buf, off + hdr, min(off + size, end), depth + 1, out)
        elif typ in ('mvhd', 'mdhd'):
            v = body[0]
            if v == 1:
                ts, dur = struct.unpack('>IQ', body[20:32])
            else:
                ts, dur = struct.unpack('>II', body[12:20])
            print(f'{"  " * depth}  timescale={ts} duration={dur} -> {dur / ts if ts else 0:.3f}s')
        elif typ == 'mehd':
            v = body[0]
            dur = struct.unpack('>Q', body[4:12])[0] if v == 1 else struct.unpack('>I', body[4:8])[0]
            print(f'{"  " * depth}  fragment_duration={dur}')
        elif typ == 'elst':
            print(f'{"  " * depth}  elst raw={body[:40].hex()}')
        elif typ == 'sidx':
            v = body[0]
            ref_id, ts = struct.unpack('>II', body[4:12])
            if v == 0:
                ept, first = struct.unpack('>II', body[12:20]); p = 20
            else:
                ept, first = struct.unpack('>QQ', body[12:28]); p = 28
            _, count = struct.unpack('>HH', body[p:p + 4]); p += 4
            total = 0; sizes = 0; durs = []
            for i in range(count):
                rs, sd, sap = struct.unpack('>III', body[p:p + 12]); p += 12
                total += sd; sizes += rs & 0x7fffffff; durs.append(sd)
            print(f'{"  " * depth}  timescale={ts} ept={ept} first_offset={first} refs={count} '
                  f'sum_dur={total} -> {total / ts:.3f}s sum_size={sizes} '
                  f'min_dur={min(durs)} max_dur={max(durs)} first5={durs[:5]} last3={durs[-3:]}')
            if out is not None:
                out['sidx_end'] = off + size; out['sidx_size_sum'] = sizes
        elif typ == 'stsd':
            print(f'{"  " * depth}  stsd raw={body[:96].hex()}')
        off += size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bvid'); ap.add_argument('--query', default='lofi'); ap.add_argument('--save')
    a = ap.parse_args()
    bvid = a.bvid
    if not bvid:
        q = urllib.parse.quote(a.query)
        r = api(f'https://api.bilibili.com/x/web-interface/search/type?search_type=video&page=1&keyword={q}',
                'https://search.bilibili.com/', 'https://search.bilibili.com')['result'][0]
        bvid = r['bvid']
        print(f'search first: {bvid} duration={r["duration"]} author={r["author"]}')
    pages = api(f'https://api.bilibili.com/x/player/pagelist?bvid={bvid}')
    print(f'pagelist p1 duration={pages[0]["duration"]}s')
    d = api(f'https://api.bilibili.com/x/player/playurl?bvid={bvid}&cid={pages[0]["cid"]}&fnval=16')
    print(f'playurl dash.duration={d["dash"].get("duration")} timelength={d.get("timelength")}')
    for au in d['dash']['audio']:
        print(f'  audio id={au["id"]} bw={au["bandwidth"]} codecs={au["codecs"]} '
              f'SegmentBase={au.get("SegmentBase") or au.get("segment_base")}')
    best = max(d['dash']['audio'], key=lambda x: x['bandwidth'])
    url = best['baseUrl']
    p = urllib.parse.urlsplit(url)
    print(f'chosen id={best["id"]} cdn={p.scheme}://{p.netloc}{p.path}')
    with media(url, 'bytes=0-262143') as r:
        print(f'status={r.status} type={r.headers.get("Content-Type")} range={r.headers.get("Content-Range")}')
        buf = r.read()
    total = int(r.headers.get('Content-Range').split('/')[-1])
    print(f'file size={total} -> avg {total * 8 / pages[0]["duration"] / 1000:.1f} kbps over pagelist duration')
    out = {}
    boxes(buf, 0, len(buf), 0, out)
    if 'sidx_end' in out:
        print(f'sidx_end + sum_size = {out["sidx_end"] + out["sidx_size_sum"]} (file {total})')
    if a.save:
        with media(url) as r, open(a.save, 'wb') as f:
            while chunk := r.read(1 << 20):
                f.write(chunk)
        print(f'saved {a.save}')


main()
