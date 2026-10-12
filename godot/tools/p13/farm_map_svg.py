# P13 W1B：農家配置圖（SVG）。稗田邸圍牆禁區・本屋地塊・田塊・支線・道路・水車・A1／A2（出簷込み外形と本体）。
# 実行：cd godot && python tools/p13/farm_map_svg.py <out.svg>
import json, re, sys

L = json.load(open('maps/village_v2/layout_v2.json', encoding='utf-8'))
B = json.load(open('data/village_v2_p8_blocks.json', encoding='utf-8'))
PAR = json.load(open('maps/village_v2/gen/parcels.json', encoding='utf-8'))['parcels']
W = json.load(open('assets/village_v2/hieda_wall/asset.json', encoding='utf-8'))['spec']['plan_local']
src = open('tools/village_v2_farmland_zone.gd', encoding='utf-8').read()
EST = (398 + W['x0'], 398 + W['x1'], -10 + W['zn'], -10 + W['zs'])
X0, X1, Z0, Z1 = 296, 440, -70, 120
S = 5.0


def P(x, z):
    return (x - X0) * S, (z - Z0) * S


def poly(pts, **kw):
    a = ' '.join('%.1f,%.1f' % P(x, z) for x, z in pts)
    at = ' '.join('%s="%s"' % (k.replace('_', '-'), v) for k, v in kw.items())
    return '<polygon points="%s" %s/>' % (a, at)


def line(pts, **kw):
    a = ' '.join('%.1f,%.1f' % P(x, z) for x, z in pts)
    at = ' '.join('%s="%s"' % (k.replace('_', '-'), v) for k, v in kw.items())
    return '<polyline points="%s" fill="none" %s/>' % (a, at)


def rect(cx, cz, sx, sz):
    return [(cx - sx / 2, cz - sz / 2), (cx + sx / 2, cz - sz / 2), (cx + sx / 2, cz + sz / 2), (cx - sx / 2, cz + sz / 2)]


def text(x, z, t, size=13, fill='#000', anchor='start'):
    px, pz = P(x, z)
    return '<text x="%.1f" y="%.1f" font-size="%d" fill="%s" text-anchor="%s" font-family="sans-serif">%s</text>' % (px, pz, size, fill, anchor, t)


out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % ((X1 - X0) * S, (Z1 - Z0) * S + 40, (X1 - X0) * S, (Z1 - Z0) * S + 40),
       '<rect width="100%" height="100%" fill="#f4f1e8"/>']
for b in B['blocks']:
    out.append(poly(b['L'] + b['R'][::-1], fill='#cfe3b0', stroke='#8aa66a', stroke_width=1))
for r in L['roads'] + L['lanes']:
    pts = [tuple(q) for q in r['pts']]
    out.append(line(pts, stroke='#c9a46a', stroke_width=r['half_w'] * 2 * S, stroke_linecap='round', opacity=0.8))
c = L['water']['Canal']
out.append(line([tuple(q) for q in c['pts']], stroke='#7fb2d9', stroke_width=c.get('half_w', 3) * 2 * S, opacity=0.7))
i = src.find('const BRANCHES')
j = src.find('\n}', i)
for m in re.finditer(r'"pts": \[(.*?)\]\]', src[i:j], re.S):
    pts = [(float(a), float(b)) for a, b in re.findall(r'\[([\d.\-]+), ([\d.\-]+), [\d.]+, "', m.group(1))]
    out.append(line(pts, stroke='#2f7fc4', stroke_width=2 * S * 0.6, stroke_dasharray='6,3'))
for p in PAR:
    if any(X0 <= q[0] <= X1 and Z0 <= q[1] <= Z1 for q in p['footprint']):
        out.append(poly(p['footprint'], fill='#ddd', stroke='#999', stroke_width=0.8))
# 稗田邸圍牆禁區（＋12 m 余白）
ex = rect((EST[0] + EST[1]) / 2, (EST[2] + EST[3]) / 2, EST[1] - EST[0], EST[3] - EST[2])
out.append(poly(rect((EST[0] + EST[1]) / 2, (EST[2] + EST[3]) / 2, EST[1] - EST[0] + 24, EST[3] - EST[2] + 24), fill='none', stroke='#d33', stroke_width=1.5, stroke_dasharray='8,4'))
out.append(poly(ex, fill='#f2b8b8', fill_opacity=0.7, stroke='#c00', stroke_width=3))
out.append(text((EST[0] + EST[1]) / 2, (EST[2] + EST[3]) / 2, '稗田邸 圍牆內＝禁區', 16, '#900', 'middle'))
out.append(text((EST[0] + EST[1]) / 2, EST[3] + 10, '（破線＝余白 12 m）', 11, '#900', 'middle'))
for lm in L['landmarks']:
    if 'WATERWHEEL' in lm.get('id', ''):
        x, z = lm['at']
        px, pz = P(x, z)
        out.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#555"/>' % (px, pz, 3.2 * S))
        out.append(text(x + 4, z, '水車' + lm['id'][-1], 12, '#333'))
# 原 A1／A2（否決）
for nm, cx, cz, sx, sz in [('原A1（否決）', 398, -11, 9.1, 6.4), ('原A2（否決）', 383, -27, 3.6, 5.5)]:
    out.append(poly(rect(cx, cz, sx, sz), fill='none', stroke='#000', stroke_width=2, stroke_dasharray='3,3'))
    out.append(text(cx, cz - sz / 2 - 1.5, nm, 11, '#000', 'middle'))
# 新 A1／A2：出簷込み外形（薄）＋本体（濃）
for nm, cx, cz, bx, bz, ox, oz, col in [('A1 農舍主屋（茅葺）', 318, 82, 6.4, 9.1, 8.2, 10.3, '#b8860b'),
                                       ('A2 農具納屋（板葺）', 323, 71, 3.6, 5.5, 4.5, 6.1, '#6b4f2a')]:
    out.append(poly(rect(cx, cz, ox, oz), fill=col, fill_opacity=0.25, stroke=col, stroke_width=1))
    out.append(poly(rect(cx, cz, bx, bz), fill=col, fill_opacity=0.85, stroke='#222', stroke_width=1.5))
    out.append(text(cx - ox / 2 - 1, cz, nm, 13, '#222', 'end'))
# 前庭・出入り（正面＝+x → FarmPath_5）
out.append(line([(322.5, 82), (330, 78), (336, 71)], stroke='#7a5', stroke_width=3, stroke_dasharray='5,3'))
out.append(text(331, 85, '前庭→FarmPath_5', 11, '#363'))
H = (Z1 - Z0) * S
out.append('<text x="10" y="%d" font-size="13" font-family="sans-serif">緑＝P8 田塊／褐＝道路・農道／青破線＝N0・T0 支線／淡青＝水渠／灰＝地塊／赤＝稗田邸圍牆禁區（x %.1f–%.1f, z %.1f–%.1f）／北＝上（−z）、1 マス 1 m×%d px</text>' % (H + 26, EST[0], EST[1], EST[2], EST[3], int(S)))
out.append('</svg>')
open(sys.argv[1], 'w', encoding='utf-8').write('\n'.join(out))
print('wrote', sys.argv[1])
