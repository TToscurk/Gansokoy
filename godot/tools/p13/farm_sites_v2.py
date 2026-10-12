# P13 W1B：農舍 A1／A2 再選址（2D 候補；最終判定は Godot 実景 probe_farm_sites_v2.gd）。
# W1 の farm_sites.py の欠陥：既存建物の除外を greybox.json の中心点距離だけで行い、稗田邸（greybox に無い landmark、
#   parcels.json の P_LM_HIEDA は本屋の箱 386–420×−52–−28 のみ）と、その外周＝大宅門から張る圍牆（hieda_wall asset の
#   plan_local：門基準 x −13.5..+23.5、z 0..−50 → 世界 384.5–421.5 × −60–−10）を禁区にしていなかった。さらに候補は中心点で判定。
# 本版：footprint（出簷込み）の辺上点すべてで判定／稗田邸圍牆の外 12 m／全 parcel の外 5 m／田塊（P8 可切田平台）外・田から 15 m 内
#   （農業との関係）／支線 3 m 外／道路縁 1.5 m 外・農道縁 6 m 内／水車 15 m 外。農田 district 外へ最大 12 m はみ出し可（林縁の屋敷）。
# 実行：cd godot && python tools/p13/farm_sites_v2.py
import json, math, re

L = json.load(open('maps/village_v2/layout_v2.json', encoding='utf-8'))
B = json.load(open('data/village_v2_p8_blocks.json', encoding='utf-8'))
PAR = json.load(open('maps/village_v2/gen/parcels.json', encoding='utf-8'))['parcels']
W = json.load(open('assets/village_v2/hieda_wall/asset.json', encoding='utf-8'))['spec']['plan_local']
src = open('tools/village_v2_farmland_zone.gd', encoding='utf-8').read()
GATE = (398.0, -10.0)
EST = (GATE[0] + W['x0'], GATE[0] + W['x1'], GATE[1] + W['zn'], GATE[1] + W['zs'])


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
        dx, dz = c[0] - a[0], c[1] - a[1]
        l2 = dx * dx + dz * dz or 1e-9
        t = max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / l2))
        b = min(b, math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dz))
    return b


def rect_d(p, r):
    return math.hypot(max(r[0] - p[0], 0, p[0] - r[1]), max(r[2] - p[1], 0, p[1] - r[3]))


def bbox(f):
    return (min(q[0] for q in f), max(q[0] for q in f), min(q[1] for q in f), max(q[1] for q in f))


def edge_pts(c, sx, sz, n=5):
    P = [(c[0] + a * sx / 2, c[1] + b * sz / 2) for a, b in [(-1, -1), (1, -1), (1, 1), (-1, 1)]]
    out = [c]
    for a, b in zip(P, P[1:] + P[:1]):
        for i in range(n):
            t = i / n
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


farm = L['districts']['Farmland']['poly']
blocks = [b['L'] + b['R'][::-1] for b in B['blocks']]
pboxes = [(p['id'], bbox(p['footprint'])) for p in PAR]
i = src.find('const BRANCHES')
j = src.find('\n}', i)
brs = [[(float(a), float(b)) for a, b in re.findall(r'\[([\d.\-]+), ([\d.\-]+), [\d.]+, "', m.group(1))]
       for m in re.finditer(r'"pts": \[(.*?)\]\]', src[i:j], re.S)]
roads = [(r['name'], [tuple(q) for q in r['pts']], r['half_w'], r.get('class') == 'farm') for r in L['roads'] + L['lanes']]
wheels = [tuple(lm['at']) for lm in L['landmarks'] if 'WATERWHEEL' in lm.get('id', '')]
farm_closed = farm + [farm[0]]


def evaluate(c, sx, sz):
    E = edge_pts(c, sx, sz)
    r = {}
    r['estate'] = min(rect_d(q, EST) for q in E)
    r['parcel'] = min((min(rect_d(q, bb) for q in E), pid) for pid, bb in pboxes)
    r['in_block'] = any(pip(q, bp) for q in E for bp in blocks)
    r['block'] = min(segd(q, bp + [bp[0]]) for q in E for bp in blocks)
    r['branch'] = min(segd(q, b) for q in E for b in brs)
    rd = sorted((min(segd(q, pl) for q in E) - hw, n, fm) for n, pl, hw, fm in roads)
    r['road'] = (round(rd[0][0], 1), rd[0][1])
    fr = [x for x in rd if x[2]]
    r['farmpath'] = (round(fr[0][0], 1), fr[0][1])
    r['wheel'] = min(math.dist(q, w) for q in E for w in wheels)
    r['outside_farm'] = 0.0 if all(pip(q, farm) for q in E) else max(segd(q, farm_closed) for q in E if not pip(q, farm))
    return r


def ok(r, yard):
    return (r['estate'] >= 12 and r['parcel'][0] >= 5 and not r['in_block'] and yard <= r['block'] <= 20
            and r['branch'] >= 3 and r['road'][0] >= 1.5 and r['farmpath'][0] <= 8 and r['wheel'] >= 15 and r['outside_farm'] <= 6)


if __name__ == '__main__':
    print('稗田邸 圍牆 世界範囲 x %.1f..%.1f z %.1f..%.1f' % EST)
    for nm, c, sx, sz in [('原A1', (398, -11), 9.1, 6.4), ('原A2', (383, -27), 3.6, 5.5)]:
        r = evaluate(c, sx, sz)
        print(nm, c, '圍牆範囲までの距離 %.1f m（0＝内側）' % r['estate'])
    res = []
    for kind, sx, sz, yard in (('noka', 10.3, 7.6, 4.0), ('noka', 7.6, 10.3, 4.0), ('naya', 6.1, 4.2, 2.0), ('naya', 4.2, 6.1, 2.0)):
        for x in range(316, 575, 3):
            for z in range(-150, 160, 3):
                c0 = (x, z)
                # 安価な中心点前段フィルタ（最終判定は evaluate の footprint 辺上点）
                if rect_d(c0, EST) < 12 or any(pip(c0, bp) for bp in blocks):
                    continue
                if min(segd(c0, pl) - hw for n, pl, hw, fm in roads if fm) > 14:
                    continue
                r = evaluate(c0, sx, sz)
                if ok(r, yard):
                    res.append((kind, (sx, sz), (x, z), r))
    pick = []
    for o in res:
        if not any(p[0] == o[0] and math.dist(p[2], o[2]) < 25 for p in pick):
            pick.append(o)
    for k, s, c, r in pick:
        print(k, s, c, '圍牆 %.0f 地塊 %.1f(%s) 田 %.1f 支線 %.1f 道 %s 農道 %s 水車 %.0f 農田外 %.1f' % (
            r['estate'], r['parcel'][0], r['parcel'][1], r['block'], r['branch'], r['road'], r['farmpath'], r['wheel'], r['outside_farm']))
    print('raw', len(res), 'picked', len(pick))
    json.dump([{'kind': k, 'sx': sz_[0], 'sz': sz_[1], 'c': list(c), 'block': round(r['block'], 1), 'farmpath': r['farmpath'][1],
                'farmpath_d': r['farmpath'][0], 'estate': round(r['estate'], 1)} for k, sz_, c, r in res],
              open('../docs/art_review/village_v2_p13/wave1b/farm_candidates_2d.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    # 農家一戸＝農舍 1＋納屋 1：footprint が重ならず（間 ≥ 2 m）、中心間 8–22 m
    def rect(c, s):
        return (c[0] - s[0] / 2, c[0] + s[0] / 2, c[1] - s[1] / 2, c[1] + s[1] / 2)
    pairs = []
    for k1, s1, c1, r1 in res:
        if k1 != 'noka':
            continue
        for k2, s2, c2, r2 in res:
            if k2 != 'naya':
                continue
            a, b = rect(c1, s1), rect(c2, s2)
            gap = max(b[0] - a[1], a[0] - b[1], b[2] - a[3], a[2] - b[3])
            d = math.dist(c1, c2)
            if gap >= 2.0 and 8 <= d <= 22:
                pairs.append((r1['block'] + r2['block'] + r1['outside_farm'], c1, s1, c2, s2, round(gap, 1), r1['farmpath'], r2['farmpath']))
    pairs.sort()
    seen = []
    for p in pairs:
        if any(math.dist(p[1], q[1]) < 30 for q in seen):
            continue
        seen.append(p)
        print('PAIR 農舍', p[1], p[2], '納屋', p[3], p[4], '間', p[5], p[6], p[7])
