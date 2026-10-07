"""NPC 前掛け（apron）の重み修正（主婦 shufu_f01 用、build_npc_tripo.py から roster の weight_fix で呼ぶ）。
外観・形・長さ・骨は変えない。前掛け正面の下半分で「片側の太腿に引かれる」重みを Hips へ移し、中央→端で滑らかに戻す。
  - 対象：本体の最大連結成分のうち、正面側（y < front_y）・hem_z < z < waist_z の頂点（正面＝-Y、足裏 z=0、m）
  - 太腿系（LeftUpLeg／RightUpLeg／LeftLeg／RightLeg）の重みを係数 k(x, z) 倍、減った分を Hips へ
      k = 1 − strength · c(|x|) · v(z)
      c(|x|)＝中央 1 → 端 0（smoothstep(center_x, edge_x, |x|) の反転）＝中央は Hips 主体、端は太腿を残す
      v(z)  ＝腰（waist_z）付近 0 → 下（full_z 以下）1 の smoothstep（腰との境で段差を作らない）
  - 正規化（合計 1）。重みの数値だけを変える。
"""
import math
import numpy as np
THIGH = ('LeftUpLeg', 'RightUpLeg', 'LeftLeg', 'RightLeg')


def _bn(name):
    return name.split(':')[-1].replace('mixamorig_', '')


def _smooth(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def components(me):
    nv = len(me.vertices)
    par = list(range(nv))

    def f(x):
        while par[x] != x:
            par[x] = par[par[x]]
            x = par[x]
        return x
    for p in me.polygons:
        vs = list(p.vertices)
        for a in vs[1:]:
            ra, rb = f(vs[0]), f(a)
            if ra != rb:
                par[ra] = rb
    return np.array([f(i) for i in range(nv)])


def regions(body, front_y=-0.06, z_lo=0.30, z_hi=0.95):
    """前掛け正面の面・股引の頂点・前掛け下端中央の頂点（測定用）"""
    me = body.data
    comp = components(me)
    main = np.bincount(comp).argmax()
    co = np.array([body.matrix_world @ v.co for v in me.vertices])
    gname = {g.index: _bn(g.name) for g in body.vertex_groups}
    legw = np.zeros(len(me.vertices))
    for i, v in enumerate(me.vertices):
        legw[i] = sum(g.weight for g in v.groups if gname[g.group] in THIGH)
    # 股引＝最大成分以外で、脚の重みが主で 0.2<z<0.9 にまたがる最大の成分
    best, bn = None, 0
    for c in set(comp.tolist()):
        idx = np.where(comp == c)[0]
        if c == main or len(idx) < 50:
            continue
        if legw[idx].mean() > 0.8 and co[idx, 2].min() < 0.4 and co[idx, 2].max() > 0.7 and len(idx) > bn:
            best, bn = c, len(idx)
    trouser = np.where(comp == best)[0].tolist() if best is not None else []
    apron_faces = [p.index for p in me.polygons if comp[p.vertices[0]] == main and all(co[v, 1] < front_y and z_lo < co[v, 2] < z_hi for v in p.vertices)]
    av = sorted(set(v for i in apron_faces for v in me.polygons[i].vertices))
    hem_z = min(co[v, 2] for v in av) if av else 0
    hem = sorted(av, key=lambda v: abs(co[v, 0]) + 2.0 * (co[v, 2] - hem_z))[:3]   # 下端中央に最も近い 3 頂点
    return {'comp': comp, 'main': main, 'co': co, 'trouser_verts': trouser, 'apron_faces': apron_faces, 'apron_verts': av, 'apron_hem_center': hem}


def apply(body, reg, P):
    if P.get('mode') == 'side_split':
        return apply_side_split(body, reg, P)
    if P.get('mode') == 'clearance':
        return apply_clearance(body, reg, P)
    me = body.data
    co, comp, main = reg['co'], reg['comp'], reg['main']
    vg = {_bn(g.name): g for g in body.vertex_groups}
    hips = vg['Hips']
    thighs = [vg[n] for n in THIGH if n in vg]
    gidx = {g.index: _bn(g.name) for g in body.vertex_groups}
    changed, moved, maxk = 0, 0.0, 0.0
    for i, v in enumerate(me.vertices):
        if comp[i] != main:
            continue
        x, y, z = co[i]
        if y >= P['front_y'] or not (P['hem_z'] < z < P['waist_z']):
            continue
        c = 1.0 - _smooth(P['center_x'], P['edge_x'], abs(x))
        vz = 1.0 - _smooth(P['full_z'], P['waist_z'], z)
        vy = _smooth(P['front_y'], P['front_y'] - P['front_ramp'], y)   # 側面への回り込みで段差を作らない
        k = 1.0 - P['strength'] * c * vz * vy
        if k >= 0.999:
            continue
        w = {gidx[g.group]: g.weight for g in v.groups}
        tsum = sum(w.get(n, 0.0) for n in THIGH)
        if tsum <= 1e-6:
            continue
        for g in thighs:
            n = _bn(g.name)
            if w.get(n, 0.0) > 0:
                g.add([i], w[n] * k, 'REPLACE')
        hips.add([i], w.get('Hips', 0.0) + tsum * (1 - k), 'REPLACE')
        changed += 1
        moved += tsum * (1 - k)
        maxk = max(maxk, 1 - k)
    # 正規化
    for i in range(len(me.vertices)):
        gs = me.vertices[i].groups
        s = sum(g.weight for g in gs)
        if s > 0 and abs(s - 1) > 1e-4:
            for g in gs:
                g.weight = g.weight / s
    return {'changed_verts': changed, 'thigh_weight_moved_to_hips': round(float(moved), 3), 'max_reduction': round(float(maxk), 3), 'params': P}


def apply_side_split(body, reg, P):
    """比較用：前掛け正面の太腿の左右配分を、中央の狭い帯（±split_w）で滑らかに切り替える（Hips の重みは触らない）。
    中央が左右の太腿 50/50 で遅れ、前に出た膝が突き抜ける場合の検証用。"""
    me = body.data
    co, comp, main = reg['co'], reg['comp'], reg['main']
    vg = {_bn(g.name): g for g in body.vertex_groups}
    gidx = {g.index: _bn(g.name) for g in body.vertex_groups}
    changed = 0
    for i, v in enumerate(me.vertices):
        if comp[i] != main:
            continue
        x, y, z = co[i]
        if y >= P['front_y'] or not (P['hem_z'] < z < P['waist_z']):
            continue
        vz = 1.0 - _smooth(P['full_z'], P['waist_z'], z)
        vy = _smooth(P['front_y'], P['front_y'] - P['front_ramp'], y)
        a = P['strength'] * vz * vy
        if a <= 1e-3:
            continue
        w = {gidx[g.group]: g.weight for g in v.groups}
        L = w.get('LeftUpLeg', 0) + w.get('LeftLeg', 0)
        R = w.get('RightUpLeg', 0) + w.get('RightLeg', 0)
        t = L + R
        if t <= 1e-6:
            continue
        sL = _smooth(-P['split_w'], P['split_w'], x)   # +x＝キャラの左（中央 x=0 で左右 50/50 の対称な勾配）
        hc = P.get('hips_center', 0.0) * (1.0 - _smooth(P.get('center_x', 0.0), P.get('edge_x', 0.1), abs(x)))   # 中央だけ一部を Hips へ
        Ln, Rn = t * ((1 - a) * L / t + a * sL), t * ((1 - a) * R / t + a * (1 - sL))
        if hc > 0:
            hv = a * hc * (Ln + Rn)
            Ln, Rn = Ln * (1 - a * hc), Rn * (1 - a * hc)
            vg['Hips'].add([i], w.get('Hips', 0.0) + hv, 'REPLACE')
        for side, tot, new in (('Left', L, Ln), ('Right', R, Rn)):
            up, lo = w.get(side + 'UpLeg', 0), w.get(side + 'Leg', 0)
            ru = up / tot if tot > 1e-6 else 1.0
            for nm, val in ((side + 'UpLeg', new * ru), (side + 'Leg', new * (1 - ru))):
                if nm in vg and (val > 1e-5 or w.get(nm, 0) > 0):
                    vg[nm].add([i], val, 'REPLACE')
        changed += 1
    return {'changed_verts': changed, 'params': P}


def apply_clearance(body, reg, P):
    """使用者裁定（2026-10-06）：重み only は FAIL。前掛け下半分の幾何だけを前（-Y）へ逃がし、膝との前後の隙間を増やす。
    腰の付け根・上半分・長さ・UV・骨は不変。重みは左右対称の太腿勾配（side_split、Hips 追加なし）を併用。
      offset(x, y, z) = offset_m · vz(z) · vx(|x|) · vy(y)
      vz：waist_z〜top_z は 0、top_z → peak_z で smoothstep 0→1、peak_z → 下端 hem で 1 → hem_keep（裾を少し戻して板状に反らせない）
      vx：|x| ≤ flat_x で 1、edge_x へ smoothstep で 0（中央を尖らせず横は滑らかに）
      vy：front_y からの正面側への ramp（側面への回り込みで段差を作らない）"""
    rep_w = apply_side_split(body, reg, P['weights']) if P.get('weights') else None
    me = body.data
    co, comp, main = reg['co'], reg['comp'], reg['main']
    av = reg['apron_verts']
    hem = min(co[v, 2] for v in av)
    inv = body.matrix_world.inverted().to_3x3()
    from mathutils import Vector
    moved, mx = 0, 0.0
    for i in range(len(me.vertices)):
        if comp[i] != main:
            continue
        x, y, z = co[i]
        if y >= P['front_y'] or z >= P['top_z'] or z < hem - 1e-4:
            continue
        if z >= P['peak_z']:
            vz = 1.0 - _smooth(P['peak_z'], P['top_z'], z)
        else:
            t = (P['peak_z'] - z) / max(1e-6, P['peak_z'] - hem)
            vz = 1.0 - (1.0 - P['hem_keep']) * _smooth(0.0, 1.0, t)
        vx = 1.0 - _smooth(P['flat_x'], P['edge_x'], abs(x))
        vy = _smooth(P['front_y'], P['front_y'] - P['front_ramp'], y)
        d = P['offset_m'] * vz * vx * vy
        if d <= 1e-5:
            continue
        me.vertices[i].co += inv @ Vector((0.0, -d, 0.0))
        moved += 1
        mx = max(mx, d)
    me.update()
    return {'weights': rep_w, 'moved_verts': moved, 'max_offset_m': round(float(mx), 4), 'apron_hem_z': round(float(hem), 3), 'params': {k: v for k, v in P.items() if k != 'weights'}}
