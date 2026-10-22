"""葉片直射分解：每個視角、目標櫻葉，算『直射光實得／無自身陰影時／Lambert 預期』與環境光、背光量。
  python shell_direct.py <資料夾> [變體1 變體2 ...]   （變體需有 light_<v>_<view>.png；sun0 必須有）
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze_light as A  # noqa: E402

d = sys.argv[1]
extra = sys.argv[2:]
for v in ['front', 'side', 'back', 'close']:
    if not os.path.exists(os.path.join(d, 'mask_%s.png' % v)):
        continue
    cls = A.classify(os.path.join(d, 'mask_%s.png' % v))
    alb = A.Y(A.s2l(A.load(os.path.join(d, 'albedo_%s.png' % v))))

    def L(vn):
        p = os.path.join(d, 'light_%s_%s.png' % (vn, v))
        return A.Y(A.s2l(A.load(p))) * 4 / np.maximum(alb, 0.01) if os.path.exists(p) else None

    nd = A.s2l(A.load(os.path.join(d, 'ndl_%s.png' % v)))
    ndl = nd[..., 0] * 2 - 1
    ao = nd[..., 1]
    lt = cls['leaf_t']
    ls = L('sun0')
    lb = L('base')
    lh = L('shd0')
    g = cls['terrain'] & (lb > 1.2)
    print('[%s] 受光地面 直射 %.2f 環境 %.2f' % (v, (lb - ls)[g].mean(), ls[g].mean()))
    import json as _j
    from PIL import Image as _I, ImageDraw as _D
    vi = _j.load(open(os.path.join(d, 'views.json'), encoding='utf-8'))['views'][v]
    rimg = _I.new('L', lt.shape[::-1], 0)
    _D.Draw(rimg).polygon([(p[0], p[1]) for p in vi['ground_ring'] if not p[2]], fill=255)
    ring = (np.asarray(rimg) > 0) & cls['terrain']
    row = '  樹下地面（圈內）光照 base %.2f' % lb[ring].mean()
    for vn in extra:
        lv = L(vn)
        if lv is not None:
            row += ' | %s %.2f' % (vn, lv[ring].mean())
    print(row + '  （受光地面約 %.2f、陰影約 %.2f）' % (lb[g].mean(), ls[g].mean()))
    for nm, sel in [('外緣朝陽 N·L>0.5 AO≥0.85', lt & (ndl > 0.5) & (ao >= 0.85)), ('N·L>0.3 全部', lt & (ndl > 0.3)), ('背光 N·L<−0.3', lt & (ndl < -0.3)), ('冠內 AO<0.7', lt & (ao < 0.7))]:
        if sel.sum() < 50:
            continue
        exp = (1.547 * np.maximum(ndl, 0))[sel].mean()
        row = '  %-22s n=%6d Lambert預期 %.2f | base 直射 %.2f（%3.0f%%）' % (nm, sel.sum(), exp, (lb - ls)[sel].mean(), 100 * (lb - ls)[sel].mean() / max(exp, 1e-3))
        if lh is not None:
            row += ' | 無自身陰影 %.2f' % (lh - ls)[sel].mean()
        for vn in extra:
            lv = L(vn)
            if lv is not None:
                row += ' | %s 直射 %.2f（%3.0f%%）' % (vn, (lv - ls)[sel].mean(), 100 * (lv - ls)[sel].mean() / max(exp, 1e-3))
        row += ' | 環境 %.2f' % ls[sel].mean()
        print(row)
