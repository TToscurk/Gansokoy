#!/usr/bin/env python3
"""village_v2.tscn の町家 Kit 暖簾（nr_noren_a–e_182）を、字入りの暖簾メッシュ（noren_text_kit）へ差し替える（文字挿入・冪等）。

  python tools/patch_village_v2_noren_text.py [--dry]

- 入力：godot/data/village_v2_noren_text.json（buildings：棟 id→cell／k_buildings：W7 batch1 の棟）
- 各 `nr_noren_?_182_N` 節点（parent＝Districts/*/Buildings/<id>/Kit/LOD0）の `mesh = ExtResource(...)` を
  noren_text_kit/mesh/nr_noren_<cell>.res へ。K 版の棟（AlbedoBatch1P13）には surface_material_override/0 に NT_Noren_K を足す。
- 節点名・transform・visibility_range は触らない（arch_w9r2 の `nr_` 接頭辞による非表示はそのまま効く）。
- 改行は CRLF のまま保つ。旧 a–e の ext_resource が未使用になれば削除する。
"""
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
SCENE = os.path.join(ROOT, 'godot', 'maps', 'village_v2', 'village_v2.tscn')
DATA = os.path.join(ROOT, 'godot', 'data', 'village_v2_noren_text.json')
KIT = 'res://assets/village_v2/noren_text_kit/'
OLD_RES = ['nr_noren_%s_182.res' % c for c in 'abcde']


def main():
    dry = '--dry' in sys.argv
    doc = json.load(open(DATA, encoding='utf-8'))
    bmap, kset = doc['buildings'], set(doc.get('k_buildings', []))
    raw = open(SCENE, 'rb').read().decode('utf-8')
    nl = '\r\n' if '\r\n' in raw else '\n'
    lines = raw.split(nl)
    # 旧 ext_resource の id
    old_ids = {}
    ext_re = re.compile(r'^\[ext_resource type="(\w+)" (?:uid="[^"]*" )?path="([^"]+)" id="([^"]+)"\]$')
    last_ext = -1
    have_new = {}
    for i, ln in enumerate(lines):
        m = ext_re.match(ln)
        if m:
            last_ext = i
            if m.group(2).split('/')[-1] in OLD_RES:
                old_ids[m.group(3)] = m.group(2).split('/')[-1]
            if m.group(2).startswith(KIT):
                have_new[m.group(2)] = m.group(3)
    node_re = re.compile(r'^\[node name="(nr_noren_\w_182_\d+)" type="MeshInstance3D" parent="Districts/\w+/Buildings/(B_\w+)/Kit/LOD0"')
    patched, skipped, missing = 0, 0, []
    need_cells, need_k = set(), False
    edits = []   # (line index of mesh, cell, kflag, bid)
    i = 0
    while i < len(lines):
        m = node_re.match(lines[i])
        if not m:
            i += 1
            continue
        bid = m.group(2)
        j = i + 1
        mesh_ln = -1
        while j < len(lines) and lines[j].strip() != '':
            if lines[j].startswith('mesh = ExtResource('):
                mesh_ln = j
            j += 1
        cell = bmap.get(bid)
        if cell is None:
            missing.append(bid)
        elif mesh_ln >= 0:
            edits.append((mesh_ln, cell, bid in kset, bid))
            need_cells.add(cell)
            need_k = need_k or (bid in kset)
        i = j
    if missing:
        print('FAIL：cell が未割当の棟', sorted(set(missing)))
        sys.exit(2)
    # 追加する ext_resource
    add = []
    ids = {}
    for c in sorted(need_cells):
        path = KIT + 'mesh/nr_noren_%s.res' % c
        if path in have_new:
            ids[c] = have_new[path]
        else:
            ids[c] = 'ntn_' + c
            add.append('[ext_resource type="ArrayMesh" path="%s" id="%s"]' % (path, ids[c]))
    kpath = KIT + 'NT_Noren_K.tres'
    kid = have_new.get(kpath, 'ntn_k')
    if need_k and kpath not in have_new:
        add.append('[ext_resource type="Material" path="%s" id="%s"]' % (kpath, kid))
    # 行の書き換え（後ろから）
    for mesh_ln, cell, kflag, bid in sorted(edits, reverse=True):
        want = 'mesh = ExtResource("%s")' % ids[cell]
        extra = ['surface_material_override/0 = ExtResource("%s")' % kid] if kflag else []
        nxt = lines[mesh_ln + 1] if mesh_ln + 1 < len(lines) else ''
        has_k = nxt.startswith('surface_material_override/0 = ExtResource("%s")' % kid)
        if lines[mesh_ln] == want and (has_k or not kflag):
            skipped += 1
            continue
        lines[mesh_ln] = want
        if kflag and not has_k:
            lines.insert(mesh_ln + 1, extra[0])
        patched += 1
    # ext_resource 追加（最後の ext_resource の後ろ。行番号は上の挿入でずれない：header は node より前）
    if add:
        lines[last_ext + 1:last_ext + 1] = add
    # 未使用になった旧 ext_resource を削除
    body = nl.join(lines)
    removed = []
    for oid, nm in old_ids.items():
        if ('ExtResource("%s")' % oid) not in body:
            removed.append(nm)
            body = body.replace('[ext_resource type="ArrayMesh" path="res://assets/village_v2/machiya_kit/mesh/%s" id="%s"]%s' % (nm, oid, nl), '')
    print('暖簾の節点：%d 差し替え／%d 済み；ext_resource 追加 %d／削除 %d %s' % (patched, skipped, len(add), len(removed), removed))
    if not dry:
        open(SCENE, 'wb').write(body.encode('utf-8'))
        print('→', SCENE)


if __name__ == '__main__':
    main()
