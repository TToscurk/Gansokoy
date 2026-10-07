"""NPC 背負い籠（竹籃／背架）を剛体化する重み修正（build_npc_tripo.py から roster の basket_fix で呼ぶ）。
使用者裁定 2026-10-07：「竹籃是硬物，不是布」— 歩くと籃が Spine／Shoulder／Arm の複数骨に引かれて捻れる。
外観・形・骨・動作は変えない。籃の頂点の重みだけを 1 本の背骨（既定 Spine2）100 % に寄せる。

選択（ビルド座標：正面 -Y、足裏 z=0、m）：
  - 背骨線 s_y(z)：Hips→Spine→Spine1→Spine2→Neck の rest head を z で線形補間
  - 背中側への張り出し dy = y − s_y(z)（+ が背中側）
  - 籃の候補：z_min < z < z_max、|x| < x_max（x_min があれば x_min < x < x_max：腰の片側に下げた籠）、支配骨が Head／Neck／手でない
  - 剛体率 t = smoothstep(behind_m, behind_m + blend_m, dy)；t=1 で 100 % bone、境界帯は元の重みと補間（継ぎ目で割れない）
重みの数値だけを変える（合計 1 に正規化済みのまま）。
"""
import numpy as np

EXCLUDE = ('Head', 'Neck', 'HeadTop_End', 'Hand', 'Thumb', 'Index', 'Middle', 'Ring', 'Pinky')


def _bn(name):
    return name.split(':')[-1].replace('mixamorig_', '')


def _smooth(e0, e1, x):
    t = np.clip((x - e0) / max(e1 - e0, 1e-6), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def spine_line(arm):
    pts = []
    for nm in ('Hips', 'Spine', 'Spine1', 'Spine2', 'Neck'):
        b = next((b for b in arm.data.bones if _bn(b.name) == nm), None)
        if b is not None:
            h = arm.matrix_world @ b.head_local
            pts.append((h.z, h.y))
    pts.sort()
    return np.array([p[0] for p in pts]), np.array([p[1] for p in pts])


def rigid_t(m, arm, P):
    """per-vertex rigid factor t in [0,1] (numpy array) — shared by the build step and the preview/audit tools"""
    me = m.data
    nv = len(me.vertices)
    co = np.array([(m.matrix_world @ v.co)[:] for v in me.vertices])
    zs, ys = spine_line(arm)
    sy = np.interp(co[:, 2], zs, ys)
    dy = co[:, 1] - sy
    names = {g.index: _bn(g.name) for g in m.vertex_groups}
    dom = []
    for v in me.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        dom.append(names.get(best.group, '') if best else '')
    ok = np.array([not any(k in d for k in EXCLUDE) for d in dom])
    xin = (co[:, 0] > P['x_min']) & (co[:, 0] < P['x_max']) if 'x_min' in P else (np.abs(co[:, 0]) < P['x_max'])
    inside = (co[:, 2] > P['z_min']) & (co[:, 2] < P['z_max']) & xin & ok
    t = _smooth(P['behind_m'], P['behind_m'] + P.get('blend_m', 0.03), dy) * inside
    if P.get('mode') == 'component':
        # Tripo meshes are split into many small UV islands. Decide per island (median dy / centroid in the box),
        # so a woven basket side that touches the back is not half rigid / half skinned (no tear inside an island).
        comp = components(me)
        tc = np.zeros(nv)
        for idx in comp:
            idx = np.asarray(idx)
            c = co[idx].mean(0)
            cin = P['z_min'] < c[2] < P['z_max'] and ((P['x_min'] < c[0] < P['x_max']) if 'x_min' in P else abs(c[0]) < P['x_max'])
            if not cin or not ok[idx].mean() > 0.5:
                continue
            if 'island_floor' in P and co[idx, 2].min() < P['island_floor']:
                continue   # cloth flaps hanging below the basket bottom are not part of the basket
            if P.get('select') == 'box':   # side-hung basket (腰籠): the island centroid inside the box is enough
                tc[idx] = 1.0 if c[1] > P.get('y_min', -1.0) else 0.0
            else:
                tc[idx] = _smooth(P['behind_m'], P['behind_m'] + P.get('blend_m', 0.03), float(np.median(dy[idx])))
        t = tc
    return t, dom


def components(me):
    nv = len(me.vertices)
    parent = list(range(nv))

    def f(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for e in me.edges:
        a, b = f(e.vertices[0]), f(e.vertices[1])
        if a != b:
            parent[a] = b
    out = {}
    for i in range(nv):
        out.setdefault(f(i), []).append(i)
    return list(out.values())


def apply(m, arm, P):
    bone = P.get('bone', 'Spine2')
    gname = next((g.name for g in m.vertex_groups if _bn(g.name) == bone), None)
    if gname is None:
        raise SystemExit('basket_fix: bone %s not in vertex groups' % bone)
    gi = m.vertex_groups[gname].index
    t, dom = rigid_t(m, arm, P)
    vg = {g.index: g for g in m.vertex_groups}
    full = part = 0
    from collections import Counter
    before = Counter()
    for v in m.data.vertices:
        tv = float(t[v.index])
        if tv <= 1e-4:
            continue
        before[dom[v.index]] += 1
        old = {g.group: g.weight for g in v.groups}
        new = {k: w * (1.0 - tv) for k, w in old.items()}
        new[gi] = new.get(gi, 0.0) + tv
        s = sum(new.values())
        for k in set(old) | set(new):
            w = new.get(k, 0.0) / s
            if w <= 1e-6:
                vg[k].remove([v.index])
            else:
                vg[k].add([v.index], w, 'REPLACE')
        full += tv >= 0.999
        part += tv < 0.999
    return {'bone': bone, 'params': P, 'rigid_verts': int(full), 'blend_verts': int(part),
            'dominant_bones_before': dict(before.most_common(8))}
