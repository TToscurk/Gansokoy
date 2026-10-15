"""P13 W9 Phase 3 R2：cT4 の『農舎・運河・護岸がどれだけ見えるか』を ID パスから数える（Pillow＋numpy）。
   python3 ct4_visibility.py <rawdir> <out.json> <tag:label> [<tag:label> ...]
  基準＝EnrichW9P3 を外した ID パス（Cid2off）。各 tag の農舎 A1 の見える画素数 ÷ 基準の画素数＝見える割合。
  ID パスは w7_shots.gd --id の出力（<tag>_cT4_id.png＋<tag>_idtable.json）。同じ鏡位（cT4）・同じ build の場景。
  A1＝FarmsteadP13/A1_noka、運河＝Water/Canal、護岸＝Riverbank/RB_*。C3 の樹の画面占有（EnrichW9P3/ZoneC3/C3_belt／C3_road の樹）も出す。
"""
import json
import sys

import numpy as np
from PIL import Image

RAW = sys.argv[1].rstrip('/') + '/'
OUT = sys.argv[2]
SPEC = [a.split(':', 1) for a in sys.argv[3:]]
BASE = 'Cid2off'


def load(tag):
    t = json.load(open(RAW + f'{tag}_idtable.json', encoding='utf-8'))
    bits = t['bits']
    mp = {int(k): v for k, v in t['map'].items()}
    sp = 8 if bits == 5 else 4
    im = np.array(Image.open(RAW + f'{tag}_cT4_id.png').convert('RGB')).astype(int)
    ids = ((im[..., 0] // sp) << (2 * bits)) | ((im[..., 1] // sp) << bits) | (im[..., 2] // sp)
    return ids, mp


def count(ids, mp, prefixes):
    sel = [i for i, p in mp.items() if any(p.startswith(x) for x in prefixes)]
    return int(np.isin(ids, sel).sum())


base_ids, base_map = load(BASE)
H, W = base_ids.shape
groups = {'farmhouse_A1': ['FarmsteadP13/A1_noka'], 'canal_water': ['Water/Canal'], 'riverbank_stone': ['Riverbank/RB_']}
base = {k: count(base_ids, base_map, v) for k, v in groups.items()}
res = {'frame': [W, H], 'baseline_tag': BASE, 'baseline_px': base, 'rows': []}
for tag, label in SPEC:
    ids, mp = load(tag)
    row = {'tag': tag, 'label': label, 'visible_ratio_pct': {}, 'c3_trees_screen_pct': {}}
    for k, v in groups.items():
        row['visible_ratio_pct'][k] = round(count(ids, mp, v) / max(base[k], 1) * 100.0, 1)
    trees = {}
    for i, p in mp.items():
        if p.startswith('EnrichW9P3/ZoneC3/C3_belt') or (p.startswith('EnrichW9P3/ZoneC3/C3_road') and 'broad' in p):
            c = int((ids == i).sum())
            if c:
                nm = p.split('/')[-2].split('_', 1)[1]
                trees[nm] = trees.get(nm, 0) + c
    row['c3_trees_screen_pct'] = {k: round(v / (W * H) * 100.0, 2) for k, v in sorted(trees.items(), key=lambda kv: -kv[1])}
    res['rows'].append(row)
    print(label, row['visible_ratio_pct'], row['c3_trees_screen_pct'])
json.dump(res, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
