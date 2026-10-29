#!/usr/bin/env python3
"""Regenerate the base64 PNG icons embedded in anthropic-tunnel.5s.py.
Three concentric circles, 18x18 px (SwiftBar shows images at pixel size), one colour per state.
Usage: python3 menubar/make_icons.py  (rewrites the ICONS block in the plugin)"""
import zlib, struct, base64, re, os
COLS = {"green": "#34c759", "yellow": "#007aff", "red": "#ff3b30", "grey": "#8e8e93"}
def png(w, h, rows):
    raw = b''.join(b'\x00' + bytes(r) for r in rows)
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
def icon(hexcol, size=18, ss=8):
    r, g, b = int(hexcol[1:3], 16), int(hexcol[3:5], 16), int(hexcol[5:7], 16)
    S = size * ss; c = S / 2; R = S / 2 - ss
    rings = [(R, R - 2.2 * ss), (R - 4.4 * ss, R - 6.6 * ss), (R - 9.2 * ss, 0)]
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            cov = 0
            for sy in range(ss):
                for sx in range(ss):
                    px = x * ss + sx + 0.5; py = y * ss + sy + 0.5
                    d = ((px - c) ** 2 + (py - c) ** 2) ** 0.5
                    if any(lo <= d <= hi for hi, lo in rings): cov += 1
            row += [r, g, b, int(255 * cov / (ss * ss))]
        rows.append(row)
    return base64.b64encode(png(size, size, rows)).decode()
if __name__ == "__main__":
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "anthropic-tunnel.5s.py")
    s = open(p).read()
    block = "ICONS = {\n" + "".join(f'    "{k}": "{icon(v)}",\n' for k, v in COLS.items()) + "}\n"
    s2 = re.sub(r"ICONS = \{\n(?:    \"[a-z]+\": \"[^\"]*\",\n)*\}\n", block, s)
    assert s2 != s or "ICONS = {" in s, "ICONS block not found"
    open(p, "w").write(s2); print("icons embedded")
