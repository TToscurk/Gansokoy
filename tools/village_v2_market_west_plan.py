"""P10 R1b Market West Rework：平面規劃図（verify_village_v2_market_west.gd -- --dump=<json> の出力から描く）。
  python tools/village_v2_market_west_plan.py <dump.json> <out.png>
地図は x 196–242・z −60–−18（北が上＝−z）。凡例・説明は地図の外の右の欄（地図の物は欄に入らない）。
"""
import json
import math
import sys

from PIL import Image, ImageDraw, ImageFont

D = json.load(open(sys.argv[1], encoding='utf-8'))
OUT = sys.argv[2]
X0, X1, Z0, Z1 = 196.0, 242.0, -60.0, -18.0
S = 26
MW_, MH_ = int((X1 - X0) * S), int((Z1 - Z0) * S)
HEAD, PAD, LEG_W = 70, 24, 640
F = 'C:/Windows/Fonts/msjh.ttc'
fT = ImageFont.truetype(F, 28)
fM = ImageFont.truetype(F, 19)
fS = ImageFont.truetype(F, 16)
fN = ImageFont.truetype(F, 17)

# ── 地図（独立したキャンバス → 外へはみ出さない）
mp = Image.new('RGB', (MW_, MH_), (246, 242, 232))
dr = ImageDraw.Draw(mp, 'RGBA')


def P(x, z):
    return ((x - X0) * S, (z - Z0) * S)


def poly(pts, fill=None, outline=None, width=1):
    dr.polygon([P(*p) for p in pts], fill=fill, outline=outline, width=width)


def rect(r, fill=None, outline=None, width=1):
    x, z, w, h = r
    dr.rectangle([P(x, z), P(x + w, z + h)], fill=fill, outline=outline, width=width)


def label(x, z, s, font=fS, fill=(20, 20, 20), bg=(255, 255, 255, 220)):
    px, pz = P(x, z)
    lines = s.split('\n')
    hh = font.size + 3
    tw = max(dr.textlength(t, font=font) for t in lines)
    th = hh * len(lines)
    if bg:
        dr.rectangle([px - tw / 2 - 4, pz - th / 2 - 2, px + tw / 2 + 4, pz + th / 2 + 2], fill=bg)
    for i, t in enumerate(lines):
        dr.text((px, pz - th / 2 + hh * (i + 0.5)), t, font=font, fill=fill, anchor='mm')


def num(x, z, n):
    px, pz = P(x, z)
    dr.ellipse([px - 13, pz - 13, px + 13, pz + 13], fill=(255, 255, 255, 240), outline=(20, 20, 20), width=2)
    dr.text((px, pz), str(n), font=fN, fill=(20, 20, 20), anchor='mm')


for pr in D['parcels']:
    poly(pr['c'], outline=(185, 175, 155, 255), width=1)
rect((196.0, -23.0, 46.0, 6.0), fill=(214, 200, 170, 255))
for z in range(-60, -22):
    x = 204 - 0.12 * (z + 80)
    rect((x - 1.5, z, 3.0, 1.0), fill=(214, 200, 170, 255))
cols = {'roji1': (232, 218, 186, 255), 'roji2': (232, 218, 186, 255)}
for k, r in D['floor'].items():
    rect(r, fill=cols.get(k, (224, 196, 146, 255)))
for b in D['bld']:
    poly(b['c'], fill=(160, 160, 160, 255), outline=(95, 95, 95, 255))
for m in D['market']:
    poly(m['c'], fill=(120, 150, 205, 210), outline=(60, 90, 150, 255))
for k, r in D['lanes'].items():
    rect(r, outline=(40, 140, 60, 255), width=2)
tcol = {'nikai': (150, 60, 40, 255), 'zushi': (190, 110, 60, 255), 'hiraya': (205, 165, 115, 255)}
names = {'aramono': '荒物', 'gofuku': '呉服', 'seto': '瀬戸物', 'kanbutsu': '乾物', 'kashi': '菓子', 'chaya': '茶屋', 'kome': '米屋', 'yaoya': '八百屋',
         'okeya': '桶屋\n仕事場', 'sakaya': '酒屋'}
tn = {'nikai': '總二階', 'zushi': '厨子', 'hiraya': '平屋'}
for s in D['shops']:
    rect(s['rect'], fill=tcol[s['type']], outline=(60, 30, 20, 255), width=2)
    x, z, w, h = s['rect']
    label(x + w / 2, z + h / 2, names.get(s['trade'], s['trade']) + '\n' + tn[s['type']], fM, (255, 255, 255), None)
    if s['door']:
        dx, dz = s['door']
        dr.ellipse([P(dx - 0.28, dz - 0.28), P(dx + 0.28, dz + 0.28)], fill=(255, 230, 80, 255), outline=(120, 90, 0, 255))
ccol = {'disp': (215, 95, 40, 230), 'awn': (40, 90, 175, 230), 'sign': (185, 30, 30, 235), 'work': (125, 85, 30, 235),
        'back': (110, 110, 60, 225), 'pave': (120, 120, 120, 200)}
for it in D['items']:
    if it['id'].startswith('ms_kido') or it['tag'] in ('wall', 'over'):
        continue
    c = ccol.get(it['tag'], (100, 100, 100, 200))
    for pl in it['polys']:
        poly(pl, fill=c)
# 吊り提灯（綱＝破線＋提灯）と軒提灯・吊るし物（壁際の点）
for it in D['items']:
    x, z = it['p']
    if it['id'] == 'ms_tsuna_chochin':
        if abs(z - (-44.6)) < 0.5:
            a, b = (x, -47.4), (x, -41.8)
        else:
            a, b = (x - 2.25, z), (x + 2.25, z)
        n = 12
        for i in range(n):
            if i % 2 == 0:
                dr.line([P(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n),
                         P(a[0] + (b[0] - a[0]) * (i + 1) / n, a[1] + (b[1] - a[1]) * (i + 1) / n)], fill=(200, 30, 30, 255), width=3)
        for i in range(5):
            t = (i + 1) / 6
            q = P(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            dr.ellipse([q[0] - 5, q[1] - 5, q[0] + 5, q[1] + 5], fill=(220, 40, 40, 255) if i % 2 == 0 else (255, 250, 235, 255), outline=(80, 0, 0))
    elif it['tag'] == 'wall':
        q = P(x, z)
        dr.ellipse([q[0] - 5, q[1] - 5, q[0] + 5, q[1] + 5], fill=(220, 40, 40, 255), outline=(80, 0, 0))
# 木戸：柱 2 本（黒い四角）＋冠木（線）
for it in D['items']:
    if it['id'].startswith('ms_kido') and len(it['polys']) == 2:
        cs = [[sum(q[0] for q in pl) / 4, sum(q[1] for q in pl) / 4] for pl in it['polys']]
        dr.line([P(*cs[0]), P(*cs[1])], fill=(20, 20, 20, 255), width=2)
        for c in cs:
            q = P(*c)
            dr.rectangle([q[0] - 6, q[1] - 6, q[0] + 6, q[1] + 6], fill=(20, 20, 20, 255))
# 視線
for key in ('sight_alley', 'sight_market'):
    a, b = D[key]
    if key == 'sight_alley':
        b = [a[0], -47.4]
    dr.line([P(*a), P(*b)], fill=(200, 30, 160, 255), width=2)


def arrow(pts, col=(30, 110, 200, 255)):
    for i in range(len(pts) - 1):
        dr.line([P(*pts[i]), P(*pts[i + 1])], fill=col, width=4)
    (x0, z0), (x1, z1) = pts[-2], pts[-1]
    ang = math.atan2(z1 - z0, x1 - x0)
    tip = P(x1, z1)
    for sgn in (1, -1):
        q = (tip[0] - 18 * math.cos(ang + sgn * 0.45), tip[1] - 18 * math.sin(ang + sgn * 0.45))
        dr.line([tip, q], fill=col, width=4)


# 主な歩く筋
arrow([(200.0, -44.6), (225.5, -44.6)])
arrow([(228.6, -21.5), (228.6, -40.5)])
arrow([(228.6, -44.6), (232.3, -47.2), (232.3, -51.4), (238.0, -51.4)])
for a in D['anchors']:
    x, z = a['p']
    dr.ellipse([P(x - 0.13, z - 0.13), P(x + 0.13, z + 0.13)], fill=(30, 160, 60, 255))
NUM = [(1, 226.0, -25.2), (2, 231.6, -31.6), (3, 200.6, -47.6), (4, 234.4, -47.0), (5, 226.6, -48.6), (6, 214.9, -43.0), (7, 226.0, -58.4),
       (8, 208.8, -29.0), (9, 219.6, -30.0), (10, 237.4, -42.0)]
for n, x, z in NUM:
    num(x, z, n)
label(220.0, -20.0, '中橫街（CrossStreetMid）／表店の列（既存）', fS, (90, 70, 40), (246, 236, 214, 230))
label(198.4, -54.0, '西\n小\n路', fS, (90, 70, 40), (246, 236, 214, 230))
dr.line([P(197.0, -19.0), P(207.0, -19.0)], fill=(20, 20, 20), width=3)
label(202.0, -19.6, '10 m', fS, (20, 20, 20), None)
label(198.5, -58.8, '北 ↑', fM, (20, 20, 20), (255, 255, 255, 200))

# ── 全体（見出し＋地図＋右の欄）
W = PAD + MW_ + PAD + LEG_W
H = HEAD + MH_ + PAD
img = Image.new('RGB', (W, H), (250, 248, 242))
img.paste(mp, (PAD, HEAD))
g = ImageDraw.Draw(img)
g.rectangle([0, 0, W, HEAD - 8], fill=(60, 50, 40))
g.text((PAD, HEAD / 2 - 4), 'P10 R1b Market West Rework — 市集西通り（裏通り）平面規劃　（generator の plan をそのまま描画）', font=fT, fill=(255, 255, 255), anchor='lm')
g.rectangle([PAD, HEAD, PAD + MW_, HEAD + MH_], outline=(60, 60, 60), width=2)
lx = PAD + MW_ + PAD + 6
ly = HEAD + 4
g.text((lx, ly), '凡例', font=fM, fill=(20, 20, 20))
ly += 30


def sw(kind, c, s):
    global ly
    if kind == 'box':
        g.rectangle([lx, ly, lx + 26, ly + 18], fill=c, outline=(60, 60, 60))
    elif kind == 'dot':
        g.ellipse([lx + 7, ly + 3, lx + 19, ly + 15], fill=c, outline=(60, 60, 60))
    elif kind == 'line':
        g.line([(lx, ly + 9), (lx + 26, ly + 9)], fill=c, width=3)
    elif kind == 'outline':
        g.rectangle([lx, ly, lx + 26, ly + 18], outline=c, width=2)
    elif kind == 'gate':
        g.line([(lx, ly + 9), (lx + 26, ly + 9)], fill=c, width=2)
        g.rectangle([lx - 3, ly + 3, lx + 9, ly + 15], fill=c)
        g.rectangle([lx + 17, ly + 3, lx + 29, ly + 15], fill=c)
    g.text((lx + 38, ly + 9), s, font=fS, fill=(20, 20, 20), anchor='lm')
    ly += 25


sw('box', (150, 60, 40), '新しい店：總二階（町家 Kit で組む）')
sw('box', (190, 110, 60), '新しい店：厨子二階（町家 Kit）')
sw('box', (205, 165, 115), '新しい店：平屋の仕事場（町家 Kit）')
sw('dot', (255, 230, 80), '戸口（開いた店の間；前 1.2 m は空ける）')
sw('box', (160, 160, 160), '既存の建物（P4／P6、不動）')
sw('box', (120, 150, 205), '市集 MarketP10 の構件（封存・不動）')
sw('box', (224, 196, 146), '通りの床（踏み固め土、P7 地面 shader）')
sw('box', (232, 218, 186), '路地の床')
sw('box', (215, 95, 40), '陳列（店先外溢）')
sw('box', (40, 90, 175), '日除け幕の竹竿')
sw('box', (185, 30, 30), '看板・行灯・幟・道標')
sw('box', (125, 85, 30), '仕事場（桶屋）')
sw('box', (110, 110, 60), '後場・補充の荷')
sw('box', (120, 120, 120), '敷石（延段・飛石）')
sw('dot', (220, 40, 40), '軒提灯・吊るし物（壁掛け）')
sw('line', (200, 30, 30), '吊り提灯（綱、破線）')
sw('gate', (20, 20, 20), '木戸（柱 2 本＋冠木）')
sw('outline', (40, 140, 60), '歩く通り（何も置かない）')
sw('line', (30, 110, 200), '主な歩く筋')
sw('line', (200, 30, 160), '視線（gate で検査）')
sw('dot', (30, 160, 60), 'NPC activity anchor（R3 用）')
ly += 8
g.text((lx, ly), '番号', font=fM, fill=(20, 20, 20))
ly += 28
key = ['① 主の口：中橫街の路地に木戸「市 この奥」＋提灯',
       '② 路地の一膳飯の下屋「めし」＋吊り提灯＋石の延段',
       '③ 西の口：西小路から木戸（藍の水引幕）',
       '④ 市集側の木戸（市集の北西角から）',
       '⑤ 辻の茶屋＝主の口からの視線の突き当たり',
       '　（番傘・緋毛氈の縁台・幟；東の妻に「だんご」の下屋）',
       '⑥ 通りの中ほど：呉服（總二階）と通りを渡す吊り提灯',
       '⑦ 後場：井戸・薪・干し棚・天水桶・木箱',
       '⑧ 路地 1（道標「市此方」・飛石）　⑨ 路地 2',
       '⑩ 市集 MarketP10（封存）']
for s in key:
    g.text((lx, ly), s, font=fS, fill=(20, 20, 20))
    ly += 23
ly += 10
g.text((lx, ly), '規劃', font=fM, fill=(20, 20, 20))
ly += 28
para = ['主通道：西小路 → 東西の通り → 辻 → クランク → 市集',
        '　店の正面どうし 5.6 m、中央 2.8 m は何も置かない',
        '店列：北 6 棟（日向・連続 0.94）＝主の店列、',
        '　南 4 棟（日陰・路地 2 本で 3 塊・連続 0.74）',
        '主次：總二階 2（呉服・酒屋）＞厨子 7＞平屋の仕事場 1',
        '後場：北の店の裏（⑦）、辻に届いた荷',
        '敷地：南の店＝中橫街の表店 RSW_002–004 の敷地の',
        '　後ろ半分（裏店）。地塊の形・既存建物・市集は不動']
for s in para:
    g.text((lx, ly), s, font=fS, fill=(30, 30, 30))
    ly += 23
img.save(OUT)
print(OUT, img.size)
