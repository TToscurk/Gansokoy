#!/usr/bin/env python3
"""人間之里 V2：丘腳社寺 E2 境內環境 overlay を village_v2.tscn に掛ける（使用者 2026-10-17 TASK E2）。

  python godot/tools/p13/w9/e2/mount_hf_precinct.py --attach    # 寫入（先確認沒有開 Godot 編輯器）
  python godot/tools/p13/w9/e2/mount_hf_precinct.py --detach    # 拆掉（還原為掛載前的文字）
  python godot/tools/p13/w9/e2/mount_hf_precinct.py --check     # 唯讀：確認掛載狀態

掛的東西（root 直下・DevLayerGate（最後の子）の直前）：
  DistrictHF          街區管線 HF の植栽・踏石（gen/district_hf.scn）
  HillfootPrecinctE2  地面メッシュ＋可逆抑制 script（gen/hillfoot_precinct_e2.scn）
village_v2.tscn は gen_village_v2.gd が産生する TYPE B：再産生したら --attach をやり直す（他の overlay の --attach と同じ）。
文字編輯のみ・各段『原文字がちょうど期待回数』でなければ書かない。--detach は --attach の逆（往復で元のバイト列に戻ることを --selftest が確認）。
"""
import sys

SCENE = __file__.replace('\\', '/').rsplit('/tools/', 1)[0] + '/maps/village_v2/village_v2.tscn'
EXT_D = '[ext_resource type="PackedScene" path="res://maps/village_v2/gen/district_hf.scn" id="e2_district_hf"]'
EXT_P = '[ext_resource type="PackedScene" path="res://maps/village_v2/gen/hillfoot_precinct_e2.scn" id="e2_precinct"]'
NODE_D = '[node name="DistrictHF" parent="." instance=ExtResource("e2_district_hf")]'
NODE_P = '[node name="HillfootPrecinctE2" parent="." instance=ExtResource("e2_precinct")]'
GATE = '[node name="DevLayerGate" parent="." type="Node"]'


def state(text):
    return {'ext_d': text.count(EXT_D), 'ext_p': text.count(EXT_P), 'node_d': text.count(NODE_D), 'node_p': text.count(NODE_P),
            'gate': text.count(GATE)}


def read():
    raw = open(SCENE, 'rb').read().decode('utf-8')
    nl = '\r\n' if '\r\n' in raw else '\n'
    return raw, nl


def attach_text(raw, nl):
    st = state(raw)
    if st['ext_d'] or st['ext_p'] or st['node_d'] or st['node_p']:
        raise SystemExit('[HF_MOUNT] 已有（部分）掛載 %s → 不寫，先人工確認' % st)
    if st['gate'] != 1:
        raise SystemExit('[HF_MOUNT] DevLayerGate 行が %d 件（期待 1）→ 不寫' % st['gate'])
    lines = raw.split(nl)
    exts = [i for i, l in enumerate(lines) if l.startswith('[ext_resource')]
    assert exts, 'ext_resource 無し'
    lines[exts[-1] + 1:exts[-1] + 1] = [EXT_D, EXT_P]
    g = lines.index(GATE)
    lines[g:g] = [NODE_D, '', NODE_P, '']
    return nl.join(lines)


def detach_text(raw, nl):
    lines = raw.split(nl)
    for ln in (EXT_D, EXT_P):
        assert lines.count(ln) == 1, ln
        lines.remove(ln)
    k = lines.index(NODE_D)
    assert lines[k + 1] == '' and lines[k + 2] == NODE_P and lines[k + 3] == '', lines[k:k + 4]
    del lines[k:k + 4]
    return nl.join(lines)


def check():
    raw, _ = read()
    st = state(raw)
    ok = st == {'ext_d': 1, 'ext_p': 1, 'node_d': 1, 'node_p': 1, 'gate': 1}
    # 順序：DistrictHF → HillfootPrecinctE2 → DevLayerGate（DevLayerGate が最後の子のまま）
    if ok:
        a, b, c = raw.index(NODE_D), raw.index(NODE_P), raw.index(GATE)
        ok = a < b < c
    print('[HF_MOUNT] %s %s' % ('OK' if ok else 'NOT_MOUNTED', st))
    return ok


if __name__ == '__main__':
    for a_ in sys.argv:
        if a_.startswith('--scene='):
            SCENE = a_.split('=', 1)[1]
    if '--selftest' in sys.argv:
        raw, nl = read()
        full = {'ext_d': 1, 'ext_p': 1, 'node_d': 1, 'node_p': 1, 'gate': 1}
        if state(raw) == full:       # 掛載済み：detach→attach で元に戻る
            t = detach_text(raw, nl)
            assert attach_text(t, nl) == raw, '往復でバイト列が戻らない'
            assert state(t) == {'ext_d': 0, 'ext_p': 0, 'node_d': 0, 'node_p': 0, 'gate': 1}
        else:                        # 未掛載：attach→detach で元に戻る
            t = attach_text(raw, nl)
            assert detach_text(t, nl) == raw, '往復でバイト列が戻らない'
            assert state(t) == full
        print('[HF_MOUNT] selftest OK（往復でバイト列が元に戻る；ファイルは書かない）')
        sys.exit(0)
    if '--attach' in sys.argv:
        raw, nl = read()
        out = attach_text(raw, nl)
        open(SCENE, 'wb').write(out.encode('utf-8'))
        print('[HF_MOUNT] 寫入 %s' % SCENE)
        sys.exit(0 if check() else 1)
    if '--detach' in sys.argv:
        raw, nl = read()
        out = detach_text(raw, nl)
        open(SCENE, 'wb').write(out.encode('utf-8'))
        print('[HF_MOUNT] 拆除 %s' % SCENE)
        sys.exit(0)
    sys.exit(0 if check() else 1)
