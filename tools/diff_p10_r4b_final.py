"""P10 R4b A/B FINAL：C 除去後の A/B 視點を承認時（r3）の審圖と画素比較する（唯讀、證據用）。
Usage: uv run --with pillow --with numpy python tools/diff_p10_r4b_final.py <final_render_dir> <out.json>
  比較対象：docs/art_review/village_v2_p10_props/human_use_exp_b1/render/<view>_<state>.png（r3、使用者が審圖した版）
  出力：視點×状態ごとの平均・最大差（0–255）と差 > 24 の画素率、差の bbox。
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
R3 = ROOT / 'docs/art_review/village_v2_p10_props/human_use_exp_b1/render'
FIN = Path(sys.argv[1])
out = []
for f in sorted(FIN.glob('*.png')):
    a = np.asarray(Image.open(R3 / f.name).convert('RGB'), dtype=np.int16)
    b = np.asarray(Image.open(f).convert('RGB'), dtype=np.int16)
    d = np.abs(a - b).max(axis=2)
    m = d > 24
    ys, xs = np.nonzero(m)
    out.append({'image': f.name, 'mean': round(float(d.mean()), 3), 'max': int(d.max()), 'px_gt24_pct': round(100.0 * float(m.mean()), 4),
                'bbox_gt24': [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())] if m.any() else None})
# BEFORE（擴張を隠す）は C 除去の影響を受けない＝別 run の揺れ（風の shader・NPC の idle・雲）の基準。
# 視點ごとに AFTER／NPC OFF の差が BEFORE の差をどれだけ超えるか（excess）を出す。
by = {}
for o in out:
    v, st = o['image'][:-4].rsplit('_', 1)
    by.setdefault(v, {})[st] = o
views = []
for v, d in sorted(by.items()):
    nb = d.get('before', {}).get('px_gt24_pct', 0.0)
    ex = max(d[k]['px_gt24_pct'] - nb for k in ('after', 'npcoff') if k in d)
    views.append({'view': v, 'noise_before_pct': nb, 'after_pct': d.get('after', {}).get('px_gt24_pct'), 'npcoff_pct': d.get('npcoff', {}).get('px_gt24_pct'),
                  'excess_pct': round(ex, 4)})
res = {'note': 'C 除去後（A/B FINAL build）の A/B 視點 vs 承認時 r3 審圖。BEFORE（擴張なし）の差＝run 間の揺れ（風・NPC idle）＝基準；excess＝AFTER／NPC OFF が基準を超えた分（C の件が写っていた所）。',
       'n': len(out), 'max_mean': max(o['mean'] for o in out), 'max_px_gt24_pct': max(o['px_gt24_pct'] for o in out),
       'max_excess_pct': max(v['excess_pct'] for v in views), 'views': views, 'images': out}
Path(sys.argv[2]).write_text(json.dumps(res, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
print('n', res['n'], 'max mean', res['max_mean'], 'max px>24 %', res['max_px_gt24_pct'], 'max excess %', res['max_excess_pct'])
for v in sorted(views, key=lambda v: -v['excess_pct'])[:8]:
    print(v)
