#!/usr/bin/env python3
# Test pictures for the DE25-Nano HDMI scan-out, written straight into /dev/fb0 (1920x1080 x8r8g8b8).
#   hdmi-test.py pattern [N]   the test picture, with step number N (0-7) in the top band
#   hdmi-test.py sweep [SECS]  step the ADV7513 clock delay (0xBA) through its 8 settings, SECS each
#   hdmi-test.py move [SECS] [RATE]   a bar moving across the ramps, RATE redraws a second
#                              (default: as fast as possible, a heavy load on the memory)
import mmap, struct, subprocess, sys, time
W, H = 1920, 1080
def px(c): return struct.pack('<I', c)
def row_of(f): return b''.join(px(f(x)) for x in range(W))
FONT = {0:"01110 10001 10011 10101 11001 10001 01110",1:"00100 01100 00100 00100 00100 00100 01110",
        2:"01110 10001 00001 00010 00100 01000 11111",3:"11110 00001 00001 01110 00001 00001 11110",
        4:"00010 00110 01010 10010 11111 00010 00010",5:"11111 10000 11110 00001 00001 10001 01110",
        6:"00110 01000 10000 11110 10001 10001 01110",7:"11111 00001 00010 00100 01000 01000 01000"}
def band_rows(n):
    g = FONT[n].split(); S = 24; rows = []
    for y in range(200):
        gy = (y - 16) // S
        def f(x):
            gx = (x - 40) // S
            if 0 <= gy < 7 and 0 <= gx < 5 and y >= 16 and x >= 40 and g[gy][gx] == '1': return 0xffffff
            k = (x - 400) // 180
            if 400 <= x and k < 8 and 40 <= y < 160 and (x - 400) % 180 < 140:
                return 0xffff00 if k == n else 0x303030
            return 0x000080
        rows.append(row_of(f))
    return rows
def body_rows():
    rows = []
    chk = [row_of(lambda x: 0xffffff if x & 1 else 0), row_of(lambda x: 0 if x & 1 else 0xffffff)]
    for y in range(200, 420): rows.append(chk[y & 1])
    pairs = [(0xff0000, 0x00ffff), (0x00ff00, 0xff00ff), (0x0000ff, 0xffff00), (0xaaaaaa, 0x555555)]
    st = row_of(lambda x: pairs[x * 4 // W][x & 1])
    for y in range(420, 640): rows.append(st)
    ramps = [row_of(lambda x: (x * 255 // (W - 1)) << 16), row_of(lambda x: (x * 255 // (W - 1)) << 8),
             row_of(lambda x: (x * 255 // (W - 1))), row_of(lambda x: (x * 255 // (W - 1)) * 0x010101)]
    for y in range(640, 860): rows.append(ramps[(y - 640) // 55])
    cols = [0xffffff, 0xffff00, 0x00ffff, 0x00ff00, 0xff00ff, 0xff0000, 0x0000ff, 0x000000]
    bars = row_of(lambda x: cols[x * 8 // W])
    for y in range(860, 970): rows.append(bars)
    hatch = [row_of(lambda x, y=y: 0xffffff if (x + y) % 4 == 0 else 0) for y in range(4)]
    for y in range(970, 1080): rows.append(hatch[y & 3])
    return rows
def fb():
    f = open('/dev/fb0', 'r+b'); return mmap.mmap(f.fileno(), W * H * 4)
def put(m, y0, rows):
    m[y0 * W * 4:(y0 + len(rows)) * W * 4] = b''.join(rows)
def i2c(reg, val=None):
    if val is None: return subprocess.run(['i2cget', '-y', '0', '0x39', hex(reg)], capture_output=True, text=True).stdout.strip()
    subprocess.run(['i2cset', '-y', '0', '0x39', hex(reg), hex(val)], check=True)
mode = sys.argv[1] if len(sys.argv) > 1 else 'pattern'
m = fb()
try: open('/sys/class/graphics/fbcon/cursor_blink', 'w').write('0')
except Exception: pass
if mode == 'pattern':
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 3
    put(m, 0, band_rows(n)); put(m, 200, body_rows()); print('pattern written, step label', n)
elif mode == 'sweep':
    secs = float(sys.argv[2]) if len(sys.argv) > 2 else 8
    bands = [band_rows(n) for n in range(8)]; put(m, 200, body_rows())
    names = ['-1.2', '-0.8', '-0.4', '0', '+0.4', '+0.8', '+1.2', '+1.6']
    for n in range(8):
        put(m, 0, bands[n]); i2c(0xba, n << 5)
        print('step %d  0xBA=0x%02x  clock delay %s ns  %s  status 0x42=%s 0x9e=%s' % (n, n << 5, names[n], time.strftime('%H:%M:%S'), i2c(0x42), i2c(0x9e)), flush=True)
        time.sleep(secs)
    put(m, 0, bands[3]); i2c(0xba, 0x60); print('end: back to step 3 (0x60, no delay)')
elif mode == 'move':
    secs = float(sys.argv[2]) if len(sys.argv) > 2 else 20
    rate = float(sys.argv[3]) if len(sys.argv) > 3 else 0
    body = body_rows(); ramp = body[440:660]; t0 = time.time(); n = 0
    while time.time() - t0 < secs:
        if rate: time.sleep(max(0, t0 + n / rate - time.time()))
        x = int((time.time() - t0) * 300) % (W - 40)
        rows = [r[:x * 4] + b'\xff\xff\xff\x00' * 40 + r[(x + 40) * 4:] for r in ramp[::55]]
        out = []
        for i in range(4): out += [rows[i]] * 55
        put(m, 640, out); n += 1
    put(m, 640, ramp); print('moved for %.0f s, %d updates (%.0f a second)' % (secs, n, n / secs))
