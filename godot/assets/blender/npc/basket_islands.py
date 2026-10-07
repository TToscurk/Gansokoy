"""List NPC body UV-islands with centroid, size, median 'behind the spine' and mean albedo colour (read-only),
to tell a woven basket (tan/brown) from clothing. blender -b -P basket_islands.py -- <npc.glb> <z0> <z1> [min_n]
"""
import bpy, sys, os
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import basket_fix
argv = sys.argv[sys.argv.index('--') + 1:]
z0, z1 = float(argv[1]), float(argv[2])
min_n = int(argv[3]) if len(argv) > 3 else 20
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=argv[0])
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
body = max([o for o in bpy.data.objects if o.type == 'MESH'], key=lambda o: len(o.data.vertices))
me = body.data
co = np.array([(body.matrix_world @ v.co)[:] for v in me.vertices])
zs, ys = basket_fix.spine_line(arm)
dy = co[:, 1] - np.interp(co[:, 2], zs, ys)
import glob
cid = os.path.splitext(os.path.basename(argv[0]))[0]
img = bpy.data.images.load(glob.glob(os.path.join(os.path.dirname(argv[0]), 'tex', cid + '_albedo.*'))[0].replace('.import', '') if False else
                           [f for f in glob.glob(os.path.join(os.path.dirname(argv[0]), 'tex', cid + '_albedo.*')) if not f.endswith('.import')][0])
W, H = img.size
px = np.empty(W * H * 4, np.float32); img.pixels.foreach_get(px); px = px.reshape(H, W, 4)
uv = me.uv_layers.active.data
vcol = np.zeros((len(me.vertices), 3)); cnt = np.zeros(len(me.vertices))
for poly in me.polygons:
    for li in poly.loop_indices:
        u, v = uv[li].uv
        c = px[int(min(max(v, 0), 0.9999) * H), int((u % 1.0) * W), :3]
        vi = me.loops[li].vertex_index
        vcol[vi] += c; cnt[vi] += 1
vcol /= np.maximum(cnt, 1)[:, None]
for idx in basket_fix.components(me):
    idx = np.asarray(idx)
    c = co[idx].mean(0)
    if len(idx) < min_n or not (z0 < c[2] < z1):
        continue
    col = vcol[idx].mean(0)
    print('ISLAND n %4d  c (%.2f %.2f %.2f)  dy_med %.3f  rgb (%.2f %.2f %.2f)' % (len(idx), c[0], c[1], c[2], np.median(dy[idx]), *col))
# --- per-vertex colour clusters in the slab (coarse HSV bins) with their bounding boxes
import colorsys
sel = (co[:, 2] > z0) & (co[:, 2] < z1)
bins = {}
for i in np.where(sel)[0]:
    h, s_, v = colorsys.rgb_to_hsv(*vcol[i])
    key = (int(h * 12), int(s_ * 4), int(v * 4))
    bins.setdefault(key, []).append(i)
for key, idx in sorted(bins.items(), key=lambda kv: -len(kv[1]))[:14]:
    idx = np.asarray(idx)
    print('CBIN hue%3d sat%d val%d  n %5d  x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f  dy_med %.3f rgb %s' % (key[0] * 30, key[1], key[2], len(idx),
          co[idx, 0].min(), co[idx, 0].max(), co[idx, 1].min(), co[idx, 1].max(), co[idx, 2].min(), co[idx, 2].max(), np.median(dy[idx]), np.round(vcol[idx].mean(0), 2).tolist()))
