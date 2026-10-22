"""博麗神社 v3 樹木重複性盤點（讀 shrine_v3.tscn，不開 Godot）。
  python tools/shrine_v3/tree_inventory.py [--tscn PATH] [--json OUT]
報告：
  1. 樹種／Mesh 變體／每個 Mesh 的棵數（材質是否有每棵覆寫）
  2. 每區（石段兩側、鳥居、前庭兩側、拜殿後方、櫻林、池畔、鎮守之森…）的樹種組成與最大單一 Mesh 佔比
  3. 鄰樹重複：最近鄰同 Mesh 比例、「克隆對」（< CLONE_D m、同 Mesh、縮放差 < 8 %）、
     同 Mesh 連鎖（同 Mesh 的樹彼此 < CHAIN_D m 相連的群，≥3 棵＝重複團）
"""
import argparse
import json
import math
import os
import re
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, '..', '..'))
TREE_SPECIES = ('sakura_yama', 'momiji', 'konara', 'keyaki', 'sugi', 'akamatsu', 'shii', 'kusu', 'hinoki')
CLONE_D = 9.0
CHAIN_D = 10.0
# 玩家視點（x, z, 看向 x, z）：檢查視線裡依方位角相鄰的樹是否連續 ≥3 棵同型
VIEWS = {
    '石段腳': (0.3, 47.2, 0.0, 8.0), '石段中段': (0.6, 33.0, 0.0, 12.0), '鳥居往南': (0.0, 1.0, 0.0, 70.0),
    '前庭→拜殿': (0.0, -2.0, 0.0, -23.0), '拜殿側': (11.0, -14.5, 0.0, -23.0), '拜殿後櫻林': (-7.5, -40.5, 3.0, -25.0),
    '櫻林林床': (-2.0, -36.0, -12.0, -48.0), '池塘': (8.0, -51.0, 17.5, -42.0), '前庭往西南': (-6.0, -4.0, -150.0, 160.0),
}


def species_of(mesh):
    b = os.path.basename(mesh).replace('.res', '')
    return re.sub(r'_v3.*$', '', b), b


def load(tscn):
    ext = {}
    nodes = []
    cur = None
    for line in open(tscn, encoding='utf-8'):
        line = line.rstrip('\r\n')
        m = re.match(r'\[ext_resource type="ArrayMesh".*path="([^"]+)" id="([^"]+)"', line)
        if m:
            ext[m.group(2)] = m.group(1)
            continue
        m = re.match(r'\[node name="([^"]+)" type="([^"]+)"(?: parent="([^"]*)")?', line)
        if m:
            cur = {'name': m.group(1), 'type': m.group(2), 'parent': m.group(3) or ''}
            nodes.append(cur)
            continue
        if line.startswith('['):
            cur = None
            continue
        if cur is None:
            continue
        m = re.match(r'mesh = ExtResource\("([^"]+)"\)', line)
        if m:
            cur['mesh'] = ext.get(m.group(1), '')
        m = re.match(r'transform = Transform3D\(([^)]*)\)', line)
        if m:
            cur['xf'] = [float(v) for v in m.group(1).split(',')]
        if line.startswith('instance_shader_parameters/'):
            cur.setdefault('ip', {})[line.split('/')[1].split(' =')[0]] = line.split('= ')[1]
        if line.startswith('material_override') or line.startswith('surface_material_override'):
            cur['mat_override'] = True
    trees = []
    for n in nodes:
        if n['type'] != 'MeshInstance3D' or 'mesh' not in n or 'xf' not in n:
            continue
        sp, var = species_of(n['mesh'])
        if not sp.startswith(TREE_SPECIES):
            continue
        a = n['xf']
        # Basis 列優先：xx, xy, xz, yx, yy, yz, zx, zy, zz；origin
        s = math.sqrt(a[0] ** 2 + a[3] ** 2 + a[6] ** 2)
        yaw = math.degrees(math.atan2(a[2], a[0])) % 360
        trees.append({'name': n['name'], 'parent': n['parent'], 'species': sp, 'mesh': var, 'x': a[9], 'y': a[10], 'z': a[11],
                      'scale': s, 'yaw': yaw, 'ip': n.get('ip', {}), 'mat_override': n.get('mat_override', False)})
    return trees


def same_outline(a, b):
    return a['species'] == b['species'] and abs(a['hw'] - b['hw']) < 0.18 and abs(a['h'] / b['h'] - 1.0) < 0.25


def zone_of(t):
    x, z = t['x'], t['z']
    if abs(x) < 15 and 9.5 < z < 52:
        return '石段兩側'
    if abs(x) < 16 and 2 <= z <= 14 and t['y'] > 27:
        return '鳥居周圍'
    if math.hypot((x - 17.5) / 1.0, (z + 42.5) / 1.0) < 16:
        return '池塘周圍'
    if -34 < z < 2 and 14 < abs(x) < 34 and t['y'] > 25:
        return '前庭兩側'
    if abs(x) < 16 and -50 < z <= -25:
        return '拜殿後方'
    if -84 < z <= -27 and -30 < x < 30:
        return '櫻花林'
    if x >= 27 or z <= -84:
        return '鎮守之森（東・北）'
    if x <= -27:
        return '西坡'
    if z >= 11:
        return '南坡'
    return '其他'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tscn', default=os.path.join(GODOT, 'maps', 'shrine_v3', 'shrine_v3.tscn'))
    ap.add_argument('--json')
    ap.add_argument('--veg', default=os.path.join(GODOT, 'assets', 'shrine_v3', 'models', 'veg'), help='各 Mesh 的 .json（算高寬比）')
    a = ap.parse_args()
    T = load(a.tscn)
    hw = {}
    hmax = {}
    for t in T:
        t['zone'] = zone_of(t)
        if t['mesh'] not in hw:
            j = json.load(open(os.path.join(a.veg, t['mesh'] + '.json'), encoding='utf-8'))
            w = 0.5 * ((j['aabb_max'][0] - j['aabb_min'][0]) + (j['aabb_max'][2] - j['aabb_min'][2]))
            hw[t['mesh']] = j['aabb_max'][1] / max(w, 0.1)
            hmax[t['mesh']] = j['aabb_max'][1]
        t['hw'] = hw[t['mesh']]
        t['h'] = hmax[t['mesh']] * t['scale']
    n = len(T)
    out = {'n': n}
    print('# 樹木盤點：%s\n' % os.path.basename(a.tscn))
    print('樹 %d 棵（不含灌木、蕨、草）。每棵的材質覆寫：%d 棵；每棵 shader 參數：%s\n' % (
        n, sum(t['mat_override'] for t in T), dict(Counter(k for t in T for k in t['ip']))))
    sp = Counter(t['species'] for t in T)
    mv = defaultdict(Counter)
    for t in T:
        mv[t['species']][t['mesh']] += 1
    print('## 1. 樹種與 Mesh 變體\n')
    print('| 樹種 | 棵數 | Mesh 變體 | 各變體棵數 |')
    print('|---|---|---|---|')
    for s_, c in sp.most_common():
        print('| %s | %d | %d | %s |' % (s_, c, len(mv[s_]), '、'.join('%s %d' % (k.split('_v3_')[-1], v) for k, v in sorted(mv[s_].items()))))
    meshes = Counter(t['mesh'] for t in T)
    print('\n樹種 %d、Mesh %d；棵數最多的 Mesh：%s。' % (len(sp), len(meshes), '、'.join('%s %d' % kv for kv in meshes.most_common(4))))
    sc = [t['scale'] for t in T]
    print('縮放範圍 %.2f–%.2f；平均每個 Mesh 被 %.1f 棵共用（同 Mesh＝同一個輪廓，只差旋轉與縮放）。' % (min(sc), max(sc), n / len(meshes)))
    out['species'] = dict(sp)
    out['meshes'] = dict(meshes)
    # 區域
    print('\n## 2. 各區組成\n')
    print('| 區 | 棵數 | 樹種組成 | 最多的 Mesh（佔比） |')
    print('|---|---|---|---|')
    zones = defaultdict(list)
    for t in T:
        zones[t['zone']].append(t)
    out['zones'] = {}
    for zn, L in sorted(zones.items(), key=lambda kv: -len(kv[1])):
        c = Counter(t['species'] for t in L)
        mm = Counter(t['mesh'] for t in L).most_common(1)[0]
        print('| %s | %d | %s | %s %.0f %% |' % (zn, len(L), '、'.join('%s %d' % kv for kv in c.most_common()), mm[0], 100.0 * mm[1] / len(L)))
        out['zones'][zn] = {'n': len(L), 'species': dict(c), 'top_mesh': mm[0], 'top_share': mm[1] / len(L)}
    # 鄰樹
    print('\n## 3. 鄰樹重複\n')
    nn_same = 0
    nn_same_sp = 0
    clones = []
    for i, t in enumerate(T):
        best, bd = None, 1e9
        for j, u in enumerate(T):
            if i == j:
                continue
            d = math.hypot(t['x'] - u['x'], t['z'] - u['z'])
            if d < bd:
                bd, best = d, u
            if j > i and d < CLONE_D and t['mesh'] == u['mesh'] and abs(t['scale'] / u['scale'] - 1) < 0.08:
                clones.append((t, u, d))
        nn_same += best['mesh'] == t['mesh']
        nn_same_sp += best['species'] == t['species']
    print('最近鄰同 Mesh：%d / %d（%.0f %%）；最近鄰同樹種：%.0f %%。' % (nn_same, n, 100.0 * nn_same / n, 100.0 * nn_same_sp / n))
    print('克隆對（< %.0f m、同 Mesh、縮放差 < 8 %%）：%d 對；按區：%s。' % (CLONE_D, len(clones), dict(Counter(c[0]['zone'] for c in clones))))
    # 連鎖
    par = list(range(n))

    def f(i):
        while par[i] != i:
            par[i] = par[par[i]]
            i = par[i]
        return i
    for i, t in enumerate(T):
        for j in range(i + 1, n):
            u = T[j]
            if t['mesh'] == u['mesh'] and math.hypot(t['x'] - u['x'], t['z'] - u['z']) < CHAIN_D:
                par[f(i)] = f(j)
    groups = defaultdict(list)
    for i in range(n):
        groups[f(i)].append(T[i])
    big = sorted([g for g in groups.values() if len(g) >= 3], key=len, reverse=True)
    print('同 Mesh 連鎖群（彼此 < %.0f m 相連、≥ 3 棵）：%d 群、共 %d 棵；最大 %s。' % (
        CHAIN_D, len(big), sum(len(g) for g in big), '、'.join('%s×%d（%s）' % (g[0]['mesh'], len(g), g[0]['zone']) for g in big[:6])))
    out.update({'nn_same_mesh': nn_same / n, 'nn_same_species': nn_same_sp / n, 'clone_pairs': len(clones),
                'chain_groups': len(big), 'chain_trees': sum(len(g) for g in big), 'chain_max': len(big[0]) if big else 0})
    # 視線
    print('\n## 4. 玩家視線裡的連續同輪廓（視角 100°、70 m 內，依方位角排序；方位差 < 10° 視為並排）\n')
    print('同輪廓＝同樹種、Mesh 高寬比（AABB 高 ÷ 平均寬）差 < 0.18、實際樹高（含縮放）差 < 25 %：只差縮放的變體算同一個輪廓。\n')
    tot = 0
    rows = []
    for vn, (vx, vz, ax, az) in VIEWS.items():
        fwd = math.atan2(az - vz, ax - vx)
        L = []
        for t in T:
            d = math.hypot(t['x'] - vx, t['z'] - vz)
            if 2.0 < d < 70.0:
                ang = math.atan2(t['z'] - vz, t['x'] - vx) - fwd
                ang = (ang + math.pi) % (2 * math.pi) - math.pi
                if abs(ang) < math.radians(50):
                    L.append((math.degrees(ang), t))
        L.sort(key=lambda q: q[0])
        runs = []
        cur = [L[0]] if L else []
        for q in L[1:]:
            if same_outline(q[1], cur[-1][1]) and q[0] - cur[-1][0] < 10.0:
                cur.append(q)
            else:
                if len(cur) >= 3:
                    runs.append(cur)
                cur = [q]
        if len(cur) >= 3:
            runs.append(cur)
        tot += len(runs)
        rows.append('| %s | %d | %d | %s |' % (vn, len(L), len(runs), '、'.join('%s×%d' % ('／'.join(sorted({q[1]['mesh'].split('_v3_')[0] + '_' + q[1]['mesh'].split('_v3_')[1] for q in r})), len(r)) for r in runs) or '—'))
    print('| 視點 | 視野內樹數 | ≥3 連續同型 | 明細 |')
    print('|---|---|---|---|')
    print('\n'.join(rows))
    out['sightline_runs'] = tot
    # 紅楓
    mo = [t for t in T if t['species'] == 'momiji']
    print('\n紅楓 %d 棵：%s；leaf_sat 覆寫 %d 棵。' % (len(mo), dict(Counter(t['zone'] for t in mo)), sum('leaf_sat' in t['ip'] for t in mo)))
    if a.json:
        json.dump(out, open(a.json, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main()
