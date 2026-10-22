"""各施工階段的光照關係總表（同一棵櫻、同機位、同時刻）。
  python summary.py base=b2 s1=s1 s2=s2 ...
指標（畫面亮度＝最終顯示值的相對亮度）：
  順/背   ＝ 目標櫻葉 N·L>0.3 平均 ÷ N·L<−0.3 平均（樹冠內的明暗方向感；地面的日照／陰影比在最後一欄）
  背陰冠/陰影地 ＝ 背光視角整個樹冠（看到的都是背陰面）÷ 同畫面陰影中的地面
  順光冠/受光地 ＝ 順光視角樹冠 ÷ 同畫面受光地面
  過曝％  ＝ 目標櫻葉畫素 ≥ 0.98 的比例
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze_light as A  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
rows = []
for arg in sys.argv[1:]:
    tag, d = arg.split('=')
    d = os.path.join(HERE, d)
    out = {'tag': tag}
    for v in ['front', 'side', 'back', 'close']:
        cls = A.classify(os.path.join(d, 'mask_%s.png' % v))
        fin = A.Y(A.s2l(A.load(os.path.join(d, 'final_base_%s.png' % v))))
        alb = A.Y(A.s2l(A.load(os.path.join(d, 'albedo_%s.png' % v))))
        lin = A.Y(A.s2l(A.load(os.path.join(d, 'light_base_%s.png' % v)))) * 4.0
        lit = lin / np.maximum(alb, 0.01)
        nd = A.s2l(A.load(os.path.join(d, 'ndl_%s.png' % v)))
        ndl = nd[..., 0] * 2 - 1
        lt = cls['leaf_t']
        gsun = cls['terrain'] & (lit >= 1.2)
        near = np.zeros_like(lt)
        near[int(lt.shape[0] * 0.55):, :] = True   # 畫面下半＝近處地面（遠山也是『地形』藍色，要排除）
        gsh = cls['terrain'] & (lit < 0.9) & near
        gsun = gsun & near
        out[v] = {
            'leaf': fin[lt].mean(), 'lf': fin[lt & (ndl > 0.3)].mean() if (lt & (ndl > 0.3)).sum() > 50 else np.nan,
            'lb': fin[lt & (ndl < -0.3)].mean() if (lt & (ndl < -0.3)).sum() > 50 else np.nan,
            'gsun': fin[gsun].mean() if gsun.sum() > 50 else np.nan, 'gsh': fin[gsh].mean() if gsh.sum() > 50 else np.nan,
            'clip': 100.0 * (fin[lt] >= 0.98).mean(), 'alb': alb[lt].mean(),
            'rock': fin[cls['rock']].mean() if cls['rock'].sum() > 50 else np.nan,
            'bld': fin[cls['bld']].mean() if cls['bld'].sum() > 50 else np.nan,
            'under': fin[cls['under']].mean() if cls['under'].sum() > 50 else np.nan,
            'trunk': fin[cls['bark_t']].mean(),
        }
    rows.append(out)

print('| 階段 | 櫻葉反照率 | 順光冠 | 側視 順/背 | 背光冠 | 陰影地面（順／側） | 側視背陰葉÷陰影地 | 順光冠÷受光地 | 櫻葉過曝％（順光） | 受光地面 | 樹幹（側） | 地被（順） |')
print('|---|---|---|---|---|---|---|---|---|---|---|---|')
for r in rows:
    f, s, b = r['front'], r['side'], r['back']
    print('| %s | %.2f | %.3f | %.2f | %.3f | %.3f／%.3f | %.1f | %.2f | %.1f | %.3f | %.3f | %.3f |' % (
        r['tag'], f['alb'], f['leaf'], s['lf'] / s['lb'], b['leaf'], f['gsh'], s['gsh'], s['lb'] / s['gsh'], f['leaf'] / f['gsun'], f['clip'], f['gsun'], s['trunk'], f['under']))
