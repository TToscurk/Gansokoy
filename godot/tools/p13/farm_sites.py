# P13 W2（只讀・提案用）：農舍／納屋の候補地を格網 3 m で探す（2D、layout／P8 blocks／支線／greybox だけ）。
# 条件：東農田 district 内／P8 可切田平台塊の外 1.5 m／支線中心 ±(半径+2.5) 外／全道路の縁から 1.5 m 以上・農道の縁 5 m 以内（出入り）／
#   水車 12 m 外／既存建物中心から 8 m 外。地形高低差・碰撞は shot_farm_proposal.gd の実景で目視確認。
# 実行：cd godot && python tools/p13/farm_sites.py
import json, math, re

L = json.load(open('maps/village_v2/layout_v2.json', encoding='utf-8'))
B = json.load(open('data/village_v2_p8_blocks.json', encoding='utf-8'))
G = json.load(open('maps/village_v2/gen/greybox.json', encoding='utf-8'))
src = open('tools/village_v2_farmland_zone.gd', encoding='utf-8').read()


def pip(p, poly):
    x, y = p
    c = False
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[i - 1]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def segd(p, pl):
    b = 1e9
    for a, c in zip(pl, pl[1:]):
        ax, az = a
        dx, dz = c[0] - ax, c[1] - az
        l2 = dx * dx + dz * dz or 1e-9
        t = max(0, min(1, ((p[0] - ax) * dx + (p[1] - az) * dz) / l2))
        b = min(b, math.hypot(p[0] - ax - t * dx, p[1] - az - t * dz))
    return b


farm = L['districts']['Farmland']['poly']
blocks = [b['L'] + b['R'][::-1] for b in B['blocks']]
i = src.find('const BRANCHES')
j = src.find('\n}', i)
brs = [[(float(a), float(b)) for a, b in re.findall(r'\[([\d.\-]+), ([\d.\-]+), [\d.]+, "', m.group(1))]
       for m in re.finditer(r'"pts": \[(.*?)\]\]', src[i:j], re.S)]
roads = [(r['name'], [tuple(q) for q in r['pts']], r['half_w'], r.get('class') == 'farm') for r in L['roads'] + L['lanes']]
wheels = [tuple(lm['at']) for lm in L['landmarks'] if 'WATERWHEEL' in lm.get('id', '')]
bld = [tuple(sum(p[k] for p in b['footprint']) / 4 for k in (0, 1)) for b in G['buildings']]
out = []
for kind, rr in (('noka', 5.6), ('naya', 3.3)):
    for x in range(320, 561, 3):
        for z in range(-140, 151, 3):
            c = (x, z)
            if not pip(c, farm) or any(pip(c, bp) for bp in blocks):
                continue
            if min(segd(c, bp + [bp[0]]) for bp in blocks) < rr + 1.5 or min(segd(c, b) for b in brs) < rr + 2.5:
                continue
            fd, fn, bad = 1e9, '', False
            for n, pl, hw, fm in roads:
                d = segd(c, pl) - hw
                if d < rr + 1.5:
                    bad = True
                    break
                if fm and d < fd:
                    fd, fn = d, n
            if bad or fd > rr + 5:
                continue
            wd = min(math.dist(c, w) for w in wheels)
            if wd < 12 + rr or min(math.dist(c, b) for b in bld) < rr + 8:
                continue
            out.append((kind, c, fn, round(fd, 1), round(wd)))
pick = []
for o in out:
    if not any(p[0] == o[0] and math.dist(p[1], o[1]) < 15 for p in pick):
        pick.append(o)
for p in pick:
    print(p)
print('raw', len(out), 'picked', len(pick))
