# P13 W2：主街 39 棟の設計表（data/village_v2_p13_mainstreet.json）を生成する。
# 用途（role）は封存 StreetP10 の実際の店先物件（st_tag）に合わせる：shop:* → 店／res → 住居／res_work → 職人の家／物件なし → 個別判断。
# 側壁の「見える面」＝その側の外 0.8 m に他の建物 footprint が無い側 → 開口のある側壁（sdo）＋懸魚（平入）。
# 実行：cd godot && python tools/p13/design_mainstreet.py <street_usage.json>
import json, math, sys

G = json.load(open('maps/village_v2/gen/greybox.json', encoding='utf-8'))
U = json.load(open(sys.argv[1], encoding='utf-8'))
B = [b for b in G['buildings']]
MS = sorted([b for b in B if b['kind'] == 'machiya' and b['road'] == 'MainStreet'], key=lambda b: b['id'])
assert len(MS) == 39, len(MS)


def pip(p, poly):
    x, y = p
    c = False
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[i - 1]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def segd(p, poly):
    b = 1e9
    pl = poly + [poly[0]]
    for a, c in zip(pl, pl[1:]):
        dx, dz = c[0] - a[0], c[1] - a[1]
        l2 = dx * dx + dz * dz or 1e-9
        t = max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / l2))
        b = min(b, math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dz))
    return b


def visible_sides(b):
    c = (sum(p[0] for p in b['footprint']) / 4, sum(p[1] for p in b['footprint']) / 4)
    fx, fz = b['front_dir']
    n = math.hypot(fx, fz)
    fx, fz = fx / n, fz / n
    xd = (fz, -fx)                      # 局所 +x（Basis(UP,yaw) の x 軸）
    out = []
    for e in (-1.0, 1.0):
        free = 0
        for t in (-0.35, -0.15, 0.0, 0.15, 0.35):
            p = (c[0] + xd[0] * e * (b['width_m'] / 2 + 0.8) + fx * t * b['depth_m'],
                 c[1] + xd[1] * e * (b['width_m'] / 2 + 0.8) + fz * t * b['depth_m'])
            hit = any(o['id'] != b['id'] and (pip(p, o['footprint']) or segd(p, o['footprint']) < 0.4) for o in B)
            free += 0 if hit else 1
        if free >= 3:
            out.append(e)
    return out


def h(s):
    v = 0
    for ch in s:
        v = (v * 131 + ord(ch)) % 1000003
    return v


TSUMA = {'B_P_MKT_003', 'B_P_MKT_010', 'B_P_MKT_020', 'B_P_MKT_016', 'B_P_MKT_030', 'B_P_MXC_004', 'B_P_MXC_006'}
# W1B で使用者が見た 11 棟の型（plan 上書き）——W2 では側壁・上層の空白対策を全棟共通で上乗せ
PILOT = {
    'B_P_MKT_003': ('shop', '妻入りの店（角地・厨子・飯屋）', {'theme': 'mixed', 'up': 'mushi', 'sign': 'side', 'kemuri': False}),
    'B_P_MKT_005': ('large', '大店（両端本卯建・小山牆・屋根看板）', {'roof': 'low', 'udh': [-1.0, 1.0], 'dormer': True, 'sign': 'roof', 'theme': 'bengara', 'up': 'winb', 'sb': False}),
    'B_P_MKT_006': ('workshop', '竹籠製作兼販売の工房（開け放し・煙出し・板庇）', {'theme': 'open', 'kemuri': True, 'his_wood': True, 'roof': 'offb2', 'sign': 'side', 'up': 'mushis', 'cut': True, 'rec': 'none', 'rec_d': 0.0}),
    'B_P_MKT_007': ('shop', '二階の薬屋（棟偏後・板庇・袖看板）', {'roof': 'offb', 'sb': False, 'his_wood': True, 'theme': 'lattice', 'up': 'win', 'sign': 'side', 'udh': [], 'dormer': False}),
    'B_P_MKT_008': ('craft_home', '大工の家（平屋・緩勾配・煙出し）', {'roof': 'flat', 'kemuri': True, 'kiri': True, 'theme': 'koshib', 'cut': True, 'udh': [], 'dormer': False}),
    'B_P_MKT_009': ('shop', '二階退縮の茶屋（片卯建）', {'roof': 'low', 'sb': True, 'udh': [1.0], 'theme': 'lattice', 'up': 'amado'}),
    'B_P_MKT_010': ('residence', '蔵造りの住居（妻入・閉じた正面）', {'fin': 0, 'tone': 2, 'theme': 'amado', 'up': 'mushi', 'kiri': True, 'inuyarai': True, 'kemuri': False, 'sign': ''}),
    'B_P_MKT_018': ('residence', '厨子二階の住宅（平屋から上げる・虫籠窓）', {'up': 'mushi', 'theme': 'koshi', 'kemuri': True, 'roof': 'std'}),
    'B_P_MKT_019': ('shop', '質素な荒物屋（2F 退縮・板庇・棟偏後）', {'roof': 'offb2', 'sb': True, 'his_wood': True, 'theme': 'open', 'up': 'amado'}),
    'B_P_MKT_020': ('workshop', '妻入りの豆腐屋（作業場・煙出し）', {'theme': 'open', 'kemuri': True, 'his_wood': True, 'up': 'mushis'}),
    'B_P_MKT_021': ('large', '大店の薬種問屋（2F 退縮・片卯建・袖看板）', {'roof': 'offf', 'udh': [-1.0], 'sb': True, 'sign': 'side', 'theme': 'bengara', 'up': 'wins'}),
}
TRADE_JA = {'yaoya': '八百屋', 'sake': '酒屋', 'zakka': '荒物屋', 'meshi': '飯屋', 'seto': '瀬戸物屋', 'kome': '米屋', 'chaya': '茶屋', 'kusuri': '薬屋',
            'kashi': '菓子屋', 'abura': '油屋', 'tofu': '豆腐屋', 'hakimono': '履物屋', 'sakana': '魚屋'}
LARGE = {'B_P_MKT_012', 'B_P_MKT_015', 'B_P_MKT_031', 'B_P_MXC_005'}
RES = {'B_P_MKT_028', 'B_P_MXC_004'}   # 元から住居の棟だけ（店→住居は MKT_010 のみ：StreetP10 構圖の店数比を崩さない）

out = []
for b in MS:
    bid = b['id']
    items = U.get(bid, [])
    trades = sorted({i['tag'].split(':')[1] for i in items if i['tag'].startswith('shop:')})
    vis = visible_sides(b)
    e = {'id': bid, 'district': b['district'], 'tsuma': bid in TSUMA, 'visible_sides': vis, 'street_items': [i['id'] for i in items]}
    pl = {'up_period': 0}
    if bid in PILOT:
        role, cat, ov = PILOT[bid]
        pl.update(ov)
    elif bid in LARGE:
        role = 'large'
        cat = '大店（%s・両端本卯建・小山牆・屋根看板）' % (TRADE_JA.get(trades[0], '質屋') if trades else '質屋')
        pl.update({'udh': [-1.0, 1.0], 'dormer': True, 'sign': 'roof', 'theme': ['bengara', 'lattice'][h(bid) % 2], 'roof': ['low', 'offf'][h(bid + 'r') % 2]})
    elif bid in RES:
        role = 'residence'
        cat = '仕舞屋（住居・%s）' % ('妻入' if bid in TSUMA else '平入')
        pl.update({'theme': ['amado', 'koshib', 'koshi'][h(bid) % 3], 'kiri': True, 'inuyarai': True, 'sign': '', 'kemuri': h(bid + 'k') % 2 == 0})
    else:
        role = 'shop'
        cat = '%s%s' % ('妻入りの' if bid in TSUMA else '', TRADE_JA.get(trades[0], '店') if trades else '店')
    if role == 'shop' and bid not in PILOT and b['type'] != 'hiraya':
        pl['up'] = pl.get('up') or None
    pl = {k: v for k, v in pl.items() if v is not None}
    e['role'] = role
    e['cat'] = cat
    e['pl'] = pl
    if bid == 'B_P_MKT_006':
        e['no_noren'] = True
    if bid == 'B_P_MKT_018':
        e['type'] = 'zushi'
        e['roof_collision'] = True
    out.append(e)

doc = {'_note': 'P13 W2（使用者 2026-10-12 ART 方向承認）主街 39 棟の正式設計表。P4 灰盒紀錄（greybox.json）は変更しない——'
                 'ここが P4 紀錄への上書き（妻入・型）と Kit 風格計畫への上書きの唯一の来源。tools/village_v2_p13_mainstreet_lib.gd が読み、'
                 'gen_village_v2.gd と verify_village_v2_machiya_kit_gate.gd が同じ実効紀錄を使う。生成：tools/p13/design_mainstreet.py。',
       'phase': 'P13W2', 'buildings': out}
json.dump(doc, open('data/village_v2_p13_mainstreet.json', 'w', encoding='utf-8', newline='\n'), ensure_ascii=False, indent=1)
from collections import Counter
print('棟', len(out), '妻入', sum(e['tsuma'] for e in out), Counter(e['role'] for e in out), '見える側壁あり', sum(1 for e in out if e['visible_sides']))
for e in out:
    print(e['id'], e['role'], ('妻' if e['tsuma'] else '平'), e['visible_sides'], e['cat'])
