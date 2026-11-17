#!/usr/bin/env python3
"""票 06b：逐段列出 fragmented MP4 的 moof（tfdt、trun 的樣本數與時長），
找時間軸不連續的地方。讀本機檔，不聯網。

用法：fragments.py <檔> [--all]
"""
import struct, sys

path = sys.argv[1]
show_all = '--all' in sys.argv
f = open(path, 'rb')
size = f.seek(0, 2); f.seek(0)


def children(buf, off, end):
    while off + 8 <= end:
        sz, typ = struct.unpack('>I4s', buf[off:off + 8])
        yield typ.decode('latin1'), off, sz
        off += sz


expected = None; n = 0; pos = 0; issues = 0
while pos < size:
    f.seek(pos); hdr = f.read(16)
    sz, typ = struct.unpack('>I4s', hdr[:8]); typ = typ.decode('latin1')
    if sz == 1: sz = struct.unpack('>Q', hdr[8:16])[0]
    if typ == 'moof':
        f.seek(pos); moof = f.read(sz); n += 1
        tfdt = None; samples = 0; dur = 0; default_dur = None
        for t, o, s in children(moof, 8, sz):
            if t != 'traf': continue
            for t2, o2, s2 in children(moof, o + 8, o + s):
                b = moof[o2 + 8:o2 + s2]
                if t2 == 'tfhd':
                    flags = int.from_bytes(b[1:4], 'big'); p = 8
                    if flags & 1: p += 8
                    if flags & 2: p += 4
                    if flags & 8: default_dur = struct.unpack('>I', b[p:p + 4])[0]
                elif t2 == 'tfdt':
                    tfdt = struct.unpack('>Q', b[4:12])[0] if b[0] == 1 else struct.unpack('>I', b[4:8])[0]
                elif t2 == 'trun':
                    flags = int.from_bytes(b[1:4], 'big'); cnt = struct.unpack('>I', b[4:8])[0]; p = 8
                    if flags & 1: p += 4
                    if flags & 4: p += 4
                    samples += cnt
                    for _ in range(cnt):
                        d = default_dur
                        if flags & 0x100: d = struct.unpack('>I', b[p:p + 4])[0]; p += 4
                        if flags & 0x200: p += 4
                        if flags & 0x400: p += 4
                        if flags & 0x800: p += 4
                        dur += d or 0
        gap = None if expected is None else tfdt - expected
        if show_all or (gap not in (None, 0)):
            issues += gap not in (None, 0)
            print(f'#{n} @{pos} tfdt={tfdt} ({tfdt / 48000:.3f}s) samples={samples} dur={dur} gap={gap}')
        expected = tfdt + dur
    pos += sz
print(f'fragments={n} end={expected} ({expected / 48000:.3f}s) discontinuities={issues}')
