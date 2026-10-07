"""NPC pipeline 規則（2026-10-06 使用者裁定）：Tripo 綁骨架後の FBX／ZIP の貼圖は原模型の貼圖と等價とみなさない。
原版 blend と骨架版 FBX を同じループで肌色サンプル比較し、再ベイクで色が壊れていれば REBAKE_CORRUPTION（読むだけ）。
blender -b <orig.blend> -P npc_rig_texture_audit.py -- <rig.fbx> <out.json> [threshold=0.05]
判定：部位ごとに「原画像で肌らしい」ループ（R>G>B・R>0.7・R−B>0.1）の平均 RGB を両画像で比べ、いずれかの channel 差 > threshold → REBAKE_CORRUPTION。
ループ順が一致しない部位は UNCHECKABLE（同じ点を比べられない）。肌ループ < 200 の部位は全ループ平均で比べる。
"""
import bpy, sys, json
import numpy as np
argv = sys.argv[sys.argv.index('--') + 1:]
RIG, OUT = argv[0], argv[1]
TH = float(argv[2]) if len(argv) > 2 else 0.05


def grab():
    d = {}
    for o in bpy.data.objects:
        if o.type != 'MESH':
            continue
        me = o.data
        uv = np.zeros(len(me.loops) * 2, dtype=np.float32)
        me.uv_layers.active.data.foreach_get('uv', uv)
        lv = np.zeros(len(me.loops), dtype=np.int32)
        me.loops.foreach_get('vertex_index', lv)
        img = next((n.image for s in o.material_slots if s.material and s.material.use_nodes for n in s.material.node_tree.nodes
                    if n.type == 'TEX_IMAGE' and n.image and n.outputs['Color'].is_linked), None)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)[:, :, :3] if img else None
        d[o.name] = (uv.reshape(-1, 2), lv, px, img.name if img else None)
    return d


def samp(p, uv):
    h, w = p.shape[:2]
    x = np.clip((uv[:, 0] % 1.0 * w).astype(int), 0, w - 1)
    y = np.clip((uv[:, 1] % 1.0 * h).astype(int), 0, h - 1)
    return p[y, x]


A = grab()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=RIG)
B = grab()
res = {'rig': RIG, 'threshold': TH, 'parts': {}, 'verdict': 'OK'}
for k, (ua, la, pa, na) in A.items():
    kb = k if k in B else next((x for x in B if k.startswith(x) or x.startswith(k[:30])), None)
    if kb is None or pa is None or B[kb][2] is None:
        res['parts'][k] = {'verdict': 'UNCHECKABLE', 'why': 'no matching mesh/texture'}
        res['verdict'] = 'UNCHECKABLE' if res['verdict'] == 'OK' else res['verdict']
        continue
    ub, lb, pb, nb = B[kb]
    if len(la) != len(lb) or not (la == lb).all():
        res['parts'][k] = {'verdict': 'UNCHECKABLE', 'why': 'loop order differs'}
        res['verdict'] = 'UNCHECKABLE' if res['verdict'] == 'OK' else res['verdict']
        continue
    sa, sb = samp(pa, ua), samp(pb, ub)
    skin = (sa[:, 0] > sa[:, 1]) & (sa[:, 1] > sa[:, 2]) & (sa[:, 0] > 0.7) & (sa[:, 0] - sa[:, 2] > 0.1)
    sel = skin if skin.sum() >= 200 else np.ones(len(sa), bool)
    ma, mb = sa[sel].mean(0), sb[sel].mean(0)
    diff = float(np.abs(ma - mb).max())
    v = 'REBAKE_CORRUPTION' if diff > TH else 'OK'
    res['parts'][k] = {'verdict': v, 'sample': 'skin' if skin.sum() >= 200 else 'all', 'n': int(sel.sum()),
                       'orig_img': na, 'rig_img': nb, 'orig_rgb': [round(float(x), 3) for x in ma], 'rig_rgb': [round(float(x), 3) for x in mb], 'max_channel_diff': round(diff, 3)}
    if v == 'REBAKE_CORRUPTION':
        res['verdict'] = v
print('RIGTEX', json.dumps(res, ensure_ascii=False))
json.dump(res, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
