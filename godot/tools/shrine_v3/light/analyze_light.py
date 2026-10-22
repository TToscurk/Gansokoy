"""博麗神社 v3 植被光照診斷：分析 probe_light.gd 的輸出。
  python analyze_light.py <資料夾> [--json out.json]
所有亮度＝Rec.709 相對亮度（把 PNG 的 sRGB 解碼回線性後算）。
  final ：遊戲畫面（ACES＋曝光＋glow＋霧之後，顯示值）
  light ：光照係數＝線性畫面亮度（×4 還原曝光 0.25）÷ 反照率；1.0＝白色表面在能量 1 的光下正面受光
  albedo：材質反照率（線性）
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

W709 = np.array([0.2126, 0.7152, 0.0722])
CODES = {
    'leaf_t': (1, 0, 0), 'bark_t': (0, 1, 0), 'leaf_o': (1, 1, 0), 'bark_o': (0, 1, 1), 'under': (1, 0.5, 0),
    'rock': (1, 0, 1), 'bld': (1, 1, 1), 'terrain': (0, 0, 1), 'paving': (0.5, 0, 1),
}


def s2l(a):
    a = a / 255.0
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def l2s(v):
    return np.where(v <= 0.0031308, v * 12.92, 1.055 * np.power(np.maximum(v, 0), 1 / 2.4) - 0.055)


def load(p):
    return np.asarray(Image.open(p).convert('RGB')).astype(np.float64)


def classify(mask_png):
    m = load(mask_png) / 255.0
    out = {}
    for k, c in CODES.items():
        cs = l2s(np.array(c, float))
        d = np.abs(m - cs).max(axis=2)
        out[k] = d < 0.06
    return out


def Y(img_lin):
    return img_lin @ W709


def stat(a, sel):
    v = a[sel]
    if v.size < 30:
        return None
    return {'n': int(v.size), 'mean': float(v.mean()), 'p10': float(np.percentile(v, 10)), 'p50': float(np.median(v)), 'p90': float(np.percentile(v, 90))}


def analyze(d):
    info = json.load(open(os.path.join(d, 'views.json'), encoding='utf-8'))
    res = {'info': {k: info[k] for k in ('tree', 'crown_r', 'H', 'sun_dir', 'sun_energy', 'env')}, 'views': {}}
    for v, vi in info['views'].items():
        if not os.path.exists(os.path.join(d, 'mask_%s.png' % v)):
            continue
        cls = classify(os.path.join(d, 'mask_%s.png' % v))
        h, w = cls['leaf_t'].shape
        ring = Image.new('L', (w, h), 0)
        pts = [(p[0], p[1]) for p in vi['ground_ring'] if not p[2]]
        if len(pts) >= 3:
            ImageDraw.Draw(ring).polygon(pts, fill=255)
        under_ring = np.asarray(ring) > 0
        fin = Y(s2l(load(os.path.join(d, 'final_base_%s.png' % v))))
        alb = Y(s2l(load(os.path.join(d, 'albedo_%s.png' % v))))
        lin = Y(s2l(load(os.path.join(d, 'light_base_%s.png' % v)))) * 4.0
        lit = lin / np.maximum(alb, 0.01)
        ndl_img = s2l(load(os.path.join(d, 'ndl_%s.png' % v)))
        ndl = ndl_img[..., 0] * 2.0 - 1.0
        ao = ndl_img[..., 1]
        lt = cls['leaf_t']
        sel = {
            '目標櫻葉 全部': lt,
            '  順光面 N·L>0.3': lt & (ndl > 0.3),
            '  側光面 |N·L|≤0.3': lt & (np.abs(ndl) <= 0.3),
            '  背光面 N·L<−0.3': lt & (ndl < -0.3),
            '  樹冠內部 AO<0.7': lt & (ao < 0.7),
            '  樹冠外緣 AO≥0.85': lt & (ao >= 0.85),
            '目標樹幹': cls['bark_t'],
            '樹下地面（樹冠投影圈內）': cls['terrain'] & under_ring,
            '  其中陰影內': cls['terrain'] & under_ring & (lit < 0.9),
            '樹冠外受光地面': cls['terrain'] & ~under_ring & (lit >= 1.2),
            '陰影中的地面（全畫面）': cls['terrain'] & (lit < 0.9),
            '岩石': cls['rock'],
            '下層植被／地被': cls['under'],
            '其他樹葉': cls['leaf_o'],
            '建築／道具': cls['bld'],
            '參道石段／柵': cls['paving'],
        }
        rv = {}
        for k, s in sel.items():
            rv[k] = {'final': stat(fin, s), 'light': stat(lit, s), 'albedo': stat(alb, s)}
        # 變體：只看 final 的平均（同一組遮罩）
        var = {}
        for fn in sorted(os.listdir(d)):
            if fn.startswith('final_') and fn.endswith('_%s.png' % v) and not fn.startswith('final_base_'):
                vn = fn[len('final_'):-len('_%s.png' % v)]
                fv = Y(s2l(load(os.path.join(d, fn))))
                lv_p = os.path.join(d, 'light_%s_%s.png' % (vn, v))
                lv = Y(s2l(load(lv_p))) * 4.0 / np.maximum(alb, 0.01) if os.path.exists(lv_p) else None
                var[vn] = {}
                for k, s in sel.items():
                    if s.sum() >= 30:
                        var[vn][k] = {'final': float(fv[s].mean()), 'light': float(lv[s].mean()) if lv is not None else None}
        rv['_variants'] = var
        res['views'][v] = rv
    return res


def fmt(res):
    out = []
    i = res['info']
    out.append('太陽方向 %s 能量 %.3f；環境 %s' % (np.round(i['sun_dir'], 3).tolist(), i['sun_energy'], json.dumps(i['env'], ensure_ascii=False)))
    for v, rv in res['views'].items():
        out.append('\n## 視角 %s' % v)
        out.append('| 區域 | 畫素 | 畫面亮度 mean (p10/p90) | 光照 mean | 反照率 mean |')
        out.append('|---|---|---|---|---|')
        for k, s in rv.items():
            if k.startswith('_') or s['final'] is None:
                continue
            f, l, a = s['final'], s['light'], s['albedo']
            out.append('| %s | %d | %.3f (%.3f/%.3f) | %.2f | %.3f |' % (k, f['n'], f['mean'], f['p10'], f['p90'], l['mean'], a['mean']))
        var = rv['_variants']
        if var:
            keys = ['目標櫻葉 全部', '  順光面 N·L>0.3', '  背光面 N·L<−0.3', '  樹冠內部 AO<0.7', '樹下地面（樹冠投影圈內）', '樹冠外受光地面', '岩石', '建築／道具']
            out.append('\n變體（只關一項）→ 畫面亮度相對 base 的變化 %')
            out.append('| 變體 | ' + ' | '.join(k.strip() for k in keys) + ' |')
            out.append('|---|' + '---|' * len(keys))
            for vn, vv in var.items():
                row = []
                for k in keys:
                    b = rv.get(k, {}).get('final')
                    if b is None or k not in vv:
                        row.append('—')
                    else:
                        row.append('%+.0f%%' % (100.0 * (vv[k]['final'] / max(b['mean'], 1e-6) - 1.0)))
                out.append('| %s | %s |' % (vn, ' | '.join(row)))
    return '\n'.join(out)


if __name__ == '__main__':
    d = sys.argv[1]
    r = analyze(d)
    if '--json' in sys.argv:
        json.dump(r, open(sys.argv[sys.argv.index('--json') + 1], 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(fmt(r))
