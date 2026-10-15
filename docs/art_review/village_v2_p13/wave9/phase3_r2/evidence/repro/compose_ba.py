"""P13 W9 Phase 3 R2：Before／After 審圖シートと『相機位置の比較表』を作る（Pillow）。
   python3 compose_ba.py <rawdir> <outdir>
rawdir に <tag>_<view>.png と <tag>_index.json（w7_shots.gd の出力）がある前提。
  A：A0＝元の場景（overlay 無し）・A1＝R1（0fdea17／bce7cf4）・RA＝R2b（最終）
  B：B0／B1／RB　C：C0／C1／RC　（RB2＝柴棚を外から見る自由視点・AFTER のみ）
題字の方位は index の fwd から計算（北＝−z・東＝+x）。手書きの方位は書かない。
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

RAW = sys.argv[1].rstrip('/') + '/'
OUT = sys.argv[2].rstrip('/') + '/'
os.makedirs(OUT, exist_ok=True)
FONT = ImageFont.truetype('C:/Windows/Fonts/msgothic.ttc', 20)
FONT_S = ImageFont.truetype('C:/Windows/Fonts/msgothic.ttc', 16)
NAMES16 = ['北', '北北東', '北東', '東北東', '東', '東南東', '南東', '南南東', '南', '南南西', '南西', '西南西', '西', '西北西', '北西', '北北西']


def compass(f):
    a = (math.degrees(math.atan2(f[0], -f[2])) + 360.0) % 360.0
    return NAMES16[int((a + 11.25) // 22.5) % 16]


def load_index(tag):
    d = json.load(open(RAW + tag + '_index.json', encoding='utf-8'))
    return {r['name'].split('_', 1)[1]: r for r in d}


IDX = {}


def idx(tag):
    if tag not in IDX:
        IDX[tag] = load_index(tag)
    return IDX[tag]


def boom(r):
    c, p = r['cam'], r['player']
    return math.dist(c, p)


def cell(tag, view, label, scale):
    im = Image.open(f'{RAW}{tag}_{view}.png').convert('RGB')
    im = im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)
    r = idx(tag)[view]
    cap1 = f'{label}  [{tag}_{view}]'
    if r['kind'] == 'at':
        cap2 = f"TPS・相機→{compass(r['fwd'])}向き・玩家({r['player'][0]:.1f},{r['player'][2]:.1f})・足元→相機 {boom(r):.2f} m"
    else:
        cap2 = f"自由視点・相機→{compass(r['fwd'])}向き・相機({r['cam'][0]:.1f},{r['cam'][1]:.1f},{r['cam'][2]:.1f})"
    out = Image.new('RGB', (im.width, im.height + 52), (18, 18, 18))
    out.paste(im, (0, 52))
    d = ImageDraw.Draw(out)
    d.text((6, 3), cap1, fill=(255, 215, 130), font=FONT)
    d.text((6, 28), cap2, fill=(200, 200, 200), font=FONT_S)
    return out


def sheet(path, rows, title, scale=0.5, quality=88):
    """rows＝[ [(tag, view, label), ...], ... ]"""
    rendered = []
    for row in rows:
        cs = [cell(t, v, lab, scale) for (t, v, lab) in row]
        w = sum(c.width for c in cs) + 6 * (len(cs) - 1)
        h = max(c.height for c in cs)
        line = Image.new('RGB', (w, h), (0, 0, 0))
        x = 0
        for c in cs:
            line.paste(c, (x, 0))
            x += c.width + 6
        rendered.append(line)
    W = max(r.width for r in rendered)
    H = sum(r.height for r in rendered) + 6 * (len(rendered) - 1) + 40
    sh = Image.new('RGB', (W, H), (0, 0, 0))
    d = ImageDraw.Draw(sh)
    d.text((8, 8), title, fill=(255, 255, 255), font=FONT)
    y = 40
    for r in rendered:
        sh.paste(r, (0, y))
        y += r.height + 6
    sh.save(OUT + path, quality=quality)
    print('wrote', OUT + path, sh.size)


def diff_stats(a_tag, b_tag, views):
    """a と b の同名画像の平均絶対差（0–255）。増えた枚数＝R2 で見た目が変わった鏡位の検出。"""
    out = {}
    for v in views:
        fa, fb = f'{RAW}{a_tag}_{v}.png', f'{RAW}{b_tag}_{v}.png'
        if not (os.path.exists(fa) and os.path.exists(fb)):
            continue
        ia = Image.open(fa).convert('RGB')
        ib = Image.open(fb).convert('RGB')
        if ia.size != ib.size:
            out[v] = None
            continue
        from PIL import ImageChops
        df = ImageChops.difference(ia, ib).convert('L')
        h = df.histogram()
        tot = sum(h)
        mean = sum(i * n for i, n in enumerate(h)) / tot
        frac = sum(n for i, n in enumerate(h) if i > 12) / tot
        out[v] = {'mean_abs_diff': round(mean, 3), 'frac_pixels_diff_gt12': round(frac, 5)}
    return out


def camera_compare(pairs):
    """pairs＝[(zone, before_tag, after_tag), ...] → R1 と同じ形式の比較表"""
    rows = []
    bad = []
    for zone, tb, ta in pairs:
        ib, ia = idx(tb), idx(ta)
        for v in ib:
            if v not in ia:
                continue
            rb, ra = ib[v], ia[v]
            dcam = math.dist(rb['cam'], ra['cam'])
            dpl = math.dist(rb['player'], ra['player'])
            dfwd = math.dist(rb['fwd'], ra['fwd'])
            row = {'zone': zone, 'before': tb, 'after': ta, 'view': v, 'kind': ra['kind'], 'fov': ra['fov'],
                   'dcam_m': round(dcam, 4), 'dplayer_m': round(dpl, 4), 'dfwd': round(dfwd, 5),
                   'boom_before_m': round(boom(rb), 3), 'boom_after_m': round(boom(ra), 3)}
            rows.append(row)
            if dcam > 0.02 or dpl > 0.02 or dfwd > 0.002:
                bad.append(row)
    return rows, bad


if __name__ == '__main__':
    mode = sys.argv[3] if len(sys.argv) > 3 else 'all'
    A_TPS = ['aT1', 'aT2', 'aT3', 'aT4', 'aT5', 'aT6']
    B_TPS = ['bT1', 'bT2', 'bT3', 'bT4', 'bT5', 'bT6']
    C_TPS = ['cT1', 'cT2', 'cT3', 'cT4', 'cT5', 'cT6', 'cT7']
    res = {}
    # 1) MXC_005：R1 → R2（TPS 4 枚＋斜め上＋寄り）
    a_views = ['aT2', 'aT3', 'aT5', 'aT6', 'aHi1', 'b_MXC_005']
    sheet('1_MXC005_kura_before_after.jpg',
          [[('A1', v, 'BEFORE（R1）'), ('RA', v, 'AFTER（R2b）')] for v in a_views],
          'MXC_005 白い蔵：BEFORE＝R1（ART_REVIEW ACCEPTED 版）／AFTER＝R2b（保存メッシュの実測：棟 4.61 m・壁幅 3.45 m・奥行 10.49 m・店の棟 6.98 m より 2.37 m 低い）', scale=0.5)
    # 2) RSW_071 / bT3・bT4：元の場景・R1・R2
    sheet('2_RSW071_bT3_bT4_before_after.jpg',
          [[('B0', v, 'BEFORE（元の場景）'), ('B1', v, 'R1'), ('RB', v, 'AFTER（R2b）')] for v in ['bT3', 'bT4']],
          'RSW_071 柴棚：bT3／bT4 の正式 TPS（同じ玩家位置・向き）。AFTER＝庇柱なし・壁付け腕木のみ（bT3 は庇の下に入る構図）', scale=0.36)
    # 2b) 柴棚を外から見る：R1（庇柱 3 本）と R2b（庇柱なし）の同じ自由視点＋R2b だけの外観 2 枚
    sheet('2b_RSW071_shed_exterior.jpg',
          [[('B1', 'bN71', 'R1（庇柱 3 本）'), ('RB', 'bN71', 'AFTER（R2b・庇柱なし）')],
           [('RB2', 'bShedNE', 'AFTER（R2b）・外観 1（R1 の同視点は未撮影）'), ('RB2', 'bShedE', 'AFTER（R2b）・外観 2（R1 の同視点は未撮影）')]],
          'RSW_071 柴棚の外観：庇は壁付けの腕木で受ける片持ち（深さ 1.15 m）。下の薪の積みと切り株の碰撞は残してある', scale=0.5)
    # 3) C：cT4 / cT7（元の場景・R1・R2）
    sheet('3_C_cT4_cT7_before_after.jpg',
          [[('C0', v, 'BEFORE（元の場景）'), ('C1', v, 'R1'), ('RC', v, 'AFTER（R2b）')] for v in ['cT4', 'cT7']],
          'C 区：cT4（前景の樹）／cT7（南の路肩）の正式 TPS', scale=0.36)
    # 4) 回帰：R1 と R2 の差が出た鏡位（意図しない変化の検出）
    res['diff_A_R1_vs_R2'] = diff_stats('A1', 'RA', A_TPS + ['aHi1', 'aHi2', 'aLo1', 'aLo2', 'aAxis', 'b_MKT_030', 'b_MKT_031', 'b_MXC_005', 'b_MXC_006', 'b_MXC_007'])
    res['diff_B_R1_vs_R2'] = diff_stats('B1', 'RB', B_TPS + ['bHi1', 'bHi2', 'bLo1', 'bLo2', 'bS75', 'bS76', 'bN71', 'bS74'])
    res['diff_C_R1_vs_R2'] = diff_stats('C1', 'RC', C_TPS + ['cHiS', 'cHiN', 'cHiRd', 'cEyeRd', 'cEyeS', 'cEyeW'])
    rows, bad = camera_compare([('A', 'A1', 'RA'), ('B', 'B0', 'RB'), ('B', 'B1', 'RB'), ('C', 'C1', 'RC')])
    res['camera_compare'] = {'note': '相機位置の比較。B は元の場景（B0）と R2（RB）、R1（B1）と R2（RB）の 2 通り。dcam が 2 cm を超えた鏡位を mismatch に出す。',
                             'mismatch': bad, 'rows': rows}
    json.dump(res, open(OUT + 'ba_stats.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('mismatch:', json.dumps(bad, ensure_ascii=False))
