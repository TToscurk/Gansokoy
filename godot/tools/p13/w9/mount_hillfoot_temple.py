#!/usr/bin/env python3
"""人間之里 V2：丘腳社寺 Hero（hillfoot_temple）掛進 village_v2.tscn（使用者 2026-10-17「把這個模組加到地圖上並加上相符的建築碰撞」）。

  python godot/tools/p13/w9/mount_hillfoot_temple.py --attach   # 寫入（先確認沒有開 Godot 編輯器）
  python godot/tools/p13/w9/mount_hillfoot_temple.py --check    # 唯讀：確認掛載狀態
  python godot/tools/p13/w9/mount_hillfoot_temple.py --cancel   # TASK E FINAL（2026-10-18）：社寺取消→移除 Hero／灰盒（village_v2.tscn 重生後要再跑）
  python godot/tools/p13/w9/mount_hillfoot_temple.py --check-cancelled

做的事＝產生器 gen_village_v2.gd::_heroes() 對「registry 登記、Asset Gate 11 項全 PASS」的 anchor 型 Hero 會做的同一件事
（village_v2_hero_lib.gd place(remove_placeholder=true)），但只改文字、不重生整村（重生會丟掉 W9 掛的 overlay）：
  1. ext_resource 加 hillfoot_temple.scn
  2. Landmarks/LANDMARK_HILLFOOT_TEMPLE 加 metadata/hero_asset
  3. P0 佔位 Block（Mesh＋Shape，18×9×12 灰盒）整段移除，換成 Hero 實例（metadata/phase "P5"，與產生器輸出相同）
  4. 只被 Block 用到的三個 sub_resource 一併移除
每一步都要求原文字恰好出現一次，否則不寫。還原：git checkout 或掛載前備份。
"""
import sys

SCENE = __file__.replace('\\', '/').rsplit('/tools/', 1)[0] + '/maps/village_v2/village_v2.tscn'
NL = '\r\n'
EXT_ID = 'w9_hillfoot_temple'
EXT = '[ext_resource type="PackedScene" path="res://assets/village_v2/hillfoot_temple/hillfoot_temple.scn" id="%s"]' % EXT_ID
ANCHOR = 'Landmarks/LANDMARK_HILLFOOT_TEMPLE'
HERO = '[node name="Hero" parent="%s" instance=ExtResource("%s")]' % (ANCHOR, EXT_ID)
SUBS = ['StandardMaterial3D_56mkv', 'BoxMesh_q7m4q', 'BoxShape3D_by7iv']


def blocks(lines):
    """[(start, end)) 以 '[' 開頭的段落。"""
    idx = [i for i, l in enumerate(lines) if l.startswith('[')]
    return [(a, idx[k + 1] if k + 1 < len(idx) else len(lines)) for k, a in enumerate(idx)]


def state(text):
    return {'ext': text.count(EXT), 'hero': text.count(HERO),
            'block': text.count('[node name="Block" type="StaticBody3D" parent="%s"' % ANCHOR),
            'meta': text.count('metadata/hero_asset = "hillfoot_temple"'),
            'subs': sum(text.count('[sub_resource type="%s" id="%s"]' % (s.split('_')[0], s)) for s in SUBS)}


def attach():
    raw = open(SCENE, 'rb').read().decode('utf-8')
    assert NL in raw
    st = state(raw)
    if st['ext'] or st['hero'] or st['meta']:
        sys.exit('[HILLFOOT_MOUNT] 已有（部分）掛載 %s → 不寫，先人工確認' % st)
    lines = raw.split(NL)
    # 1. ext_resource：接在最後一個 ext_resource 之後
    last_ext = max(i for i, l in enumerate(lines) if l.startswith('[ext_resource'))
    lines.insert(last_ext + 1, EXT)
    # 2.–3. anchor／Block
    a_hdr = [i for i, l in enumerate(lines) if l.startswith('[node name="LANDMARK_HILLFOOT_TEMPLE" type="Node3D" parent="Landmarks"')]
    assert len(a_hdr) == 1, a_hdr
    bl = blocks(lines)
    a0, a1 = [b for b in bl if b[0] == a_hdr[0]][0]
    ph = [i for i in range(a0, a1) if lines[i] == 'metadata/placeholder = true']
    assert len(ph) == 1, ph
    lines.insert(ph[0] + 1, 'metadata/hero_asset = "hillfoot_temple"')
    bl = blocks(lines)
    rm = [b for b in bl if lines[b[0]].startswith('[node ') and (
        'parent="%s"' % ANCHOR in lines[b[0]] or 'parent="%s/Block"' % ANCHOR in lines[b[0]])]
    names = [lines[b[0]].split('"')[1] for b in rm]
    assert names == ['Block', 'Mesh', 'Shape'], names
    assert rm[0][1] == rm[1][0] and rm[1][1] == rm[2][0], rm
    used = ''.join(lines[rm[0][0]:rm[2][1]])
    for s in SUBS:
        assert ('SubResource("%s")' % s) in used, s
    lines[rm[0][0]:rm[2][1]] = [HERO, 'metadata/phase = "P5"', '']
    # 4. sub_resource（只在 Block 用）
    rest = NL.join(lines)
    for s in SUBS:
        assert rest.count('SubResource("%s")' % s) == 0, s
    bl = blocks(lines)
    drop = [b for b in bl if any(lines[b[0]] == '[sub_resource type="%s" id="%s"]' % (s.split('_')[0], s) for s in SUBS)]
    assert len(drop) == 3, drop
    for b in sorted(drop, reverse=True):
        del lines[b[0]:b[1]]
    out = NL.join(lines)
    open(SCENE, 'wb').write(out.encode('utf-8'))
    print('[HILLFOOT_MOUNT] 寫入 %s：%s' % (SCENE, state(out)))


CANCEL_META = 'metadata/cancelled = "使用者 2026-10-18 TASK E FINAL：丘腳社寺取消，原地改為自然林（DistrictHF）"'


def cancel():
    """TASK E FINAL（使用者 2026-10-18）：社寺取消。從場景拿掉 Hero 實例（或重生後的 P0 灰盒 Block＋3 sub_resource）與其 ext_resource，
    anchor 節點本身留著（空 Node3D・無網格・無碰撞；layout_v2.json 封存不改，其他 gate 仍找得到地標座標），加 metadata/cancelled。
    資產檔（hillfoot_temple/）不動。gen_village_v2.gd 重生 village_v2.tscn 後要再跑一次（與其他 overlay 的 --attach 同）。"""
    raw = open(SCENE, 'rb').read().decode('utf-8')
    assert NL in raw
    lines = raw.split(NL)
    a_hdr = [i for i, l in enumerate(lines) if l.startswith('[node name="LANDMARK_HILLFOOT_TEMPLE" type="Node3D" parent="Landmarks"')]
    assert len(a_hdr) == 1, a_hdr
    bl = blocks(lines)
    rm = [b for b in bl if lines[b[0]].startswith('[node ') and (
        'parent="%s"' % ANCHOR in lines[b[0]] or 'parent="%s/' % ANCHOR in lines[b[0]])]
    names = [lines[b[0]].split('"')[1] for b in rm]
    assert names in (['Hero'], ['Block', 'Mesh', 'Shape'], []), names
    for b in sorted(rm, reverse=True):
        del lines[b[0]:b[1]]
    rest = NL.join(lines)
    bl = blocks(lines)
    drop = [b for b in bl if any(lines[b[0]] == '[sub_resource type="%s" id="%s"]' % (s.split('_')[0], s) for s in SUBS)
            and rest.count('SubResource("%s")' % lines[b[0]].split('"')[3]) == 0]
    for b in sorted(drop, reverse=True):
        del lines[b[0]:b[1]]
    lines = [l for l in lines if l != EXT]
    a0, a1 = [b for b in blocks(lines) if lines[b[0]].startswith('[node name="LANDMARK_HILLFOOT_TEMPLE"')][0]
    body = [l for l in lines[a0:a1] if l != 'metadata/hero_asset = "hillfoot_temple"' and not l.startswith('metadata/cancelled')]
    while body and body[-1] == '':
        body.pop()
    body += [CANCEL_META, '']
    lines[a0:a1] = body
    out = NL.join(lines)
    assert out.count('hillfoot_temple.scn') == 0
    open(SCENE, 'wb').write(out.encode('utf-8'))
    print('[HILLFOOT_MOUNT] 取消：移除 %s・sub_resource %d・ext_resource → %s' % (names, len(drop), state(out)))


def check_cancelled():
    st = state(open(SCENE, 'rb').read().decode('utf-8'))
    raw = open(SCENE, 'rb').read().decode('utf-8')
    ok = st == {'ext': 0, 'hero': 0, 'block': 0, 'meta': 0, 'subs': 0} and raw.count(CANCEL_META) == 1
    print('[HILLFOOT_MOUNT] %s %s' % ('CANCELLED' if ok else 'NOT_CANCELLED', st))
    return ok


def check():
    st = state(open(SCENE, 'rb').read().decode('utf-8'))
    ok = st == {'ext': 1, 'hero': 1, 'block': 0, 'meta': 1, 'subs': 0}
    print('[HILLFOOT_MOUNT] %s %s' % ('OK' if ok else 'NOT_MOUNTED', st))
    return ok


if __name__ == '__main__':
    for a_ in sys.argv:
        if a_.startswith('--scene='):   # 測試用：對場景副本操作
            SCENE = a_.split('=', 1)[1]
    if '--cancel' in sys.argv:
        cancel()
        sys.exit(0 if check_cancelled() else 1)
    if '--check-cancelled' in sys.argv:
        sys.exit(0 if check_cancelled() else 1)
    if '--attach' in sys.argv:
        attach()
        sys.exit(0 if check() else 1)
    sys.exit(0 if check() else 1)
