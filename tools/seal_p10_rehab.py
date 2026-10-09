"""P10 R5–R6 Environmental Rehabilitation：ART_APPROVED 4 工作包の封存＋R4／R4b limited reseal（使用者 2026-10-09 ROUND 3 FINAL ART DIRECTION）。

  python tools/seal_p10_rehab.py            → data/village_v2_p10r5c_seal.json／p10r5a／p10r6a／p10r4c を書き、R4／R4b を limited reseal
  検証：各工作包の gate `--seal`（verify_village_v2_edge_closure／road_base／albedo_pilot／prop_fix）、R4＝verify_village_v2_human_use.gd --seal、
        R4b＝verify_village_v2_human_use_exp.gd --seal。

使用者裁定（原文）：「以下項目正式 ART_APPROVED：R5c Boundary Closure／R5a Road Base 416 m Pilot／R6a Kit Material 24 Buildings Pilot／
  R4c Straw Geometry Pilot」「允許開始這四項的正式整合及必要 limited reseal」「目前只核准 Pilot 範圍，不代表已批准全村套用」
  「R4c 更新稻架模型和必要的 A2 位置，僅重新封存實際受影響的依賴」「所有 reseal 須保留前後 hash、原因、依賴及反向測試」
R5b 灌溉と R6b 石階は未核准＝本スクリプトの対象外（SEALED にしない）。
冪等：R4／R4b の reseal_history は同じ kind の記録があれば追記しない（新しい値で上書きしない；前の値＝PRE）。
"""
import glob
import hashlib
import json
import os

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(R)
G = 'godot/'
A = 'docs/art_review/village_v2_p10_rehab_impl/'
DATE = '2026-10-09'
APPROVAL = ('使用者 2026-10-09 P10 R5–R6 ROUND 3 FINAL ART DIRECTION：「以下項目正式 ART_APPROVED：R5c Boundary Closure、R5a Road Base 416 m Pilot、'
            'R6a Kit Material 24 Buildings Pilot、R4c Straw Geometry Pilot」「允許開始這四項的正式整合及必要 limited reseal」'
            '「目前只核准 Pilot 範圍，不代表已批准全村套用」')


def sha(f):
    return hashlib.sha256(open(f, 'rb').read()).hexdigest()


def files(*pats):
    out = set()
    for p in pats:
        for f in glob.glob(p, recursive=True):
            if os.path.isfile(f):
                out.add(f.replace('\\', '/'))
    return sorted(out)


def hashed(lst):
    return {f: sha(f) for f in lst}


def save(path, d):
    open(path, 'wb').write((json.dumps(d, ensure_ascii=False, indent=1) + '\n').encode('utf-8'))


def load(path):
    return json.load(open(path, encoding='utf-8'))


COMMON = {'schema': 1, 'status': 'ART_APPROVED', 'approved_by': 'user', 'approved_date': DATE, 'approval_source': APPROVAL,
          'scope': 'Pilot 範囲のみ（全村套用は未承認）', 'reseal_history': []}
INT = A + 'integration/'

PKG = {
    'p10r5c': {
        'phase': 'P10 R5c World Edge Closure（世界邊界：frame 外 Vista＋內側林帶）',
        'overlay': 'res://maps/village_v2/gen/edge_closure_p10.scn', 'node': 'EdgeClosureP10', 'mount_after': 'HumanUseExpansionP10',
        'rule': '封存後は EdgeClosureP10 の生成器・overlay・林帯の数を変えない（使用者：既有遠景與邊界效果を保持、林帯を増やさない）。--build／--attach は拒否（EDGE_ALLOW_REBAKE=1＝使用者 reopen 時だけ）。veg_kit（P9 R1 封存）は參照のみ。',
        'frozen': [G + 'tools/village_v2_edge_closure_lib.gd', G + 'tools/verify_village_v2_edge_closure.gd', G + 'maps/village_v2/gen/edge_closure_p10.scn',
                   G + 'tools/village_v2_rehab_seal.gd', G + 'tools/shot_village_v2_rehab_r5c_views.json', 'tools/seal_p10_rehab.py'],
        'evidence': files(A + 'r5c/*.log', A + 'r5c/*.json', INT + 'r5c/*.log'),
        'images': files(A + 'r5c/*.png', A + 'r5c/pairs/*'),
        'tag': 'EDGE',
    },
    'p10r5a': {
        'phase': 'P10 R5a Road Base 416 m Pilot（FarmPath_1・FarmPath_4・南橫街の田の区間：地形なり・不揃いの幅・蛇行・使われ方；P7 FarmlandTerrain 踩み固め重み 577 頂点の局部修正；pilot ground shader）',
        'overlay': 'res://maps/village_v2/gen/road_base_p10.scn', 'node': 'RoadBaseP10', 'mount_after': 'PropFixP10',
        'rule': ('正式生成流程＝gen_village_v2.gd（P1–P7、不変）→ 封存 overlay を順に掛載（… → PropFixP10 → RoadBaseP10）。RoadBaseP10 の生成器（village_v2_road_base_lib.gd）が'
                 '元の road_*.res／terrain_farmlandterrain.res（frozen の sha＝不変の前提）から道 3 本＋地形（COLOR.r だけ 577 頂点）を決定的に再生成し、runtime で差し替える。'
                 '`--seal` が記憶體内で再生成して封存 overlay と配列一致を検証（再現性）。gen 再生成で元の res が変わったら seal が FAIL＝RoadBase を再検証・再封存。'
                 '依存：GroundPilotP10（pilot ground shader：田格外溢の除去と再生道の轍・路肩草）。--build／--attach は拒否（RDB_ALLOW_REBAKE=1＝使用者 reopen 時だけ）。'),
        'frozen': [G + 'tools/village_v2_road_base_lib.gd', G + 'tools/verify_village_v2_road_base.gd', G + 'maps/village_v2/scripts_p10/road_base.gd',
                   G + 'maps/village_v2/gen/road_base_p10.scn', G + 'tools/diag_village_v2_road_band.gd',
                   G + 'tools/village_v2_ground_pilot_lib.gd', G + 'tools/verify_village_v2_ground_pilot.gd', G + 'maps/village_v2/scripts_p10/ground_pilot.gd',
                   G + 'maps/village_v2/gen/ground_pilot_p10.scn', G + 'maps/village_v2/shaders_p10/ground_p10_pilot.gdshader',
                   G + 'maps/village_v2/gen/road_farmpath_1.res', G + 'maps/village_v2/gen/road_farmpath_4.res', G + 'maps/village_v2/gen/road_crossstreetsouth.res',
                   G + 'maps/village_v2/gen/terrain_farmlandterrain.res', G + 'tools/shot_village_v2_rehab_rdb_views.json',
                   G + 'tools/village_v2_rehab_seal.gd', 'tools/seal_p10_rehab.py'],
        'evidence': files(A + 'round2/r5a_road/*.log', A + 'round2/r5a_ground_shader/*.log', A + 'round3/r5a_road/*.log',
                          A + 'round3/r5a_road/band_diag*/*.json', A + 'round3/r5a_road/band_diag*/*.log', A + 'r5a_ground/*.log', INT + 'r5a/*.log'),
        'images': files(A + 'round3/r5a_road/panels/*', A + 'round3/r5a_road/band_diag*/*_sheet.jpg', A + 'round3/r5a_road/*.png'),
        'tag': 'RDB',
    },
    'p10r6a': {
        'phase': 'P10 R6a Kit Material 24 Buildings Pilot（方案 A：町家 Kit 專用校正材質＋區域調色盤 14 変体・登記表；漆喰 0.70・木 0.75・基石 0.65・Kit atlas 分類；瓦不校正）',
        'overlay': 'res://maps/village_v2/gen/albedo_pilot_p10.scn', 'node': 'AlbedoPilotP10', 'mount_after': 'EdgeClosureP10',
        'rule': ('Pilot 24 棟だけ（187 棟の全村套用は未承認）。合法変体＝maps/village_v2/kit_cal_p10/kit_material_variants.json の登記＋本封存の frozen sha；'
                 'P6 Kit Gate「4 材質」は登記変体・登記 Pilot 建物・基底一致・sha＝本封存のときだけ override を許可（任意 override は FAIL のまま）。'
                 '_matlib・Kit 原檔は不変。--build／--attach は拒否（ALB_ALLOW_REBAKE=1＝使用者 reopen 時だけ）。'),
        'frozen': [G + 'tools/village_v2_albedo_pilot_lib.gd', G + 'tools/verify_village_v2_albedo_pilot.gd', G + 'maps/village_v2/scripts_p10/albedo_pilot.gd',
                   G + 'maps/village_v2/gen/albedo_pilot_p10.scn', G + 'tools/village_v2_kit_material_lib.gd', G + 'tools/verify_village_v2_kit_material.gd',
                   G + 'tools/verify_village_v2_machiya_kit_gate.gd', G + 'tools/shot_village_v2_rehab_alb_views.json',
                   G + 'tools/village_v2_rehab_seal.gd', 'tools/seal_p10_rehab.py']
                  + files(G + 'maps/village_v2/kit_cal_p10/*.tres', G + 'maps/village_v2/kit_cal_p10/*.gdshader', G + 'maps/village_v2/kit_cal_p10/*.json'),
        'evidence': files(A + 'r6a_albedo/*.log', A + 'r6a_albedo/*.json', A + 'round3/r6a_kit_material/*.log', A + 'round3/r6a_kit_material/*.json',
                          INT + 'r6a/*.log', INT + 'r6a/manifest_route_attempt/*.log'),
        'images': files(A + 'r6a_albedo/*.png', A + 'r6a_albedo/pairs/*', A + 'round3/r6a_kit_material/panels/*'),
        'tag': 'ALB',
    },
    'p10r4c': {
        'phase': 'P10 R4c Straw Geometry Pilot（st_hasa → st_hasa_v2：竿×稲束の穿插 0；A2 背負い籠 東へ 1.0 m の最小移位）',
        'overlay': 'res://maps/village_v2/gen/prop_fix_p10.scn', 'node': 'PropFixP10', 'mount_after': 'ShrineApproachP10',
        'rule': ('PropFixP10 が runtime で st_hasa（＋_l1）18 個を st_hasa_v2 に差し替え、A2 籠 1 件だけ移位。street_kit・R2／R4／R4b の baked overlay は不変。'
                 '影響を受ける封存＝R4（snapshot の A2 位置・HUSE scene gate の mesh 判定）、R4b（R4 封存を子に持つ）→ limited reseal。R2 StreetP10 の封存 gate は不影響（--seal PASS）。'
                 '--build／--attach は拒否（R4C_ALLOW_REBAKE=1＝使用者 reopen 時だけ）。'),
        'frozen': [G + 'tools/verify_village_v2_prop_fix.gd', G + 'maps/village_v2/scripts_p10/prop_fix.gd', G + 'maps/village_v2/gen/prop_fix_p10.scn',
                   G + 'tools/shot_village_v2_rehab_r4c_views.json', G + 'tools/village_v2_rehab_seal.gd', 'tools/seal_p10_rehab.py']
                  + files(G + 'maps/village_v2/gen/r4c/*.res', G + 'assets/village_v2/r4c_kit/src/*.json', G + 'assets/village_v2/r4c_kit/src/*.glb',
                          G + 'assets/blender/village_v2/build_hasa_v2.py'),
        'evidence': files(A + 'r4c_props/*.log', A + 'r4c_props/*.json', INT + 'r4c/*.log'),
        'images': files(A + 'r4c_props/*.png', A + 'r4c_props/pairs/*'),
        'tag': 'R4C',
    },
}

for name, p in PKG.items():
    path = G + 'data/village_v2_%s_seal.json' % name
    missing = [f for f in p['frozen'] if not os.path.exists(f)]
    assert not missing, (name, missing)
    old = load(path) if os.path.exists(path) else {}
    d = dict(COMMON)
    d.update({'phase': p['phase'], 'overlay': p['overlay'], 'node': p['node'], 'mount_after': p['mount_after'], 'rule': p['rule'],
              'verification': {'tag': p['tag'], 'seal': 'verify %s --seal（雜湊・掛載・固有 live 検査・竄改反向）' % p['tag']},
              'frozen': hashed(p['frozen']), 'evidence': hashed(p['evidence']), 'art_review_images': hashed(p['images']), 'child_seals': {}})
    d['reseal_history'] = old.get('reseal_history', [])
    save(path, d)
    print('sealed', name, 'frozen', len(d['frozen']), 'evidence', len(d['evidence']), 'images', len(d['art_review_images']))

# ── R4 limited reseal（A2 位置＝PropFixP10 の移位後、HUSE scene gate の mesh 判定に R4c 登記の st_hasa_v2）
PRE = {  # 2026-10-09 integration 前（commit fd1b442 時点）の値
    G + 'data/village_v2_p10r4_seal.json': '0c428cfdb2e52e013f7eed65ccc209333949719c195b836f4721f6828367b6a6',
    G + 'data/village_v2_p10r4_snapshot.json': '971e2dd8d8a4c066a28b8690d87d6e2678ba99c26462a5ce9c731fb57814a45e',
    G + 'tools/verify_village_v2_human_use.gd': 'f22f3aa35da17b0236dd6dcead17a339b7e1881ab7196c90efe2867cf9f22906',
    G + 'data/village_v2_p10r4b_seal.json': '00a8311778555f302e1300a9454f95c01ab99cbf52e677e335e9ba954f99d8cd',
}
r4 = G + 'data/village_v2_p10r4_seal.json'
r4b = G + 'data/village_v2_p10r4b_seal.json'
r4c_seal = G + 'data/village_v2_p10r4c_seal.json'
j = load(r4)
hist = j.setdefault('reseal_history', [])
if not any(h.get('kind') == 'R4C_STRAW_GEOMETRY_A2' for h in hist):
    assert sha(r4) == PRE[r4], 'R4 seal が想定外に変わっている'
    hist.append({'at': DATE, 'kind': 'R4C_STRAW_GEOMETRY_A2', 'approved_by': 'user', 'approval_source': APPROVAL + '「R4c 更新稻架模型和必要的 A2 位置，僅重新封存實際受影響的依賴」',
                 'reason': ('P10 R4c（PropFixP10、封存 data/village_v2_p10r4c_seal.json）が A2 背負い籠 PilotA/A2_dakkoku/006_hu_seoikago を東へ 1.0 m 移す'
                            '（TPS 視線で千歯扱きを塞いでいた；接地＝TerrainCollision）。st_hasa → st_hasa_v2 の mesh 差し替え（位置・朝向・件数は不変）。'),
                 'changed': {'snapshot': 'PilotA/A2_dakkoku/006_hu_seoikago position [347.65, 0.145, -3.3] → [348.65, 0.144, -3.3]（他 49 件・who／why・yaw は不変）',
                             'verifier': 'HUSE scene「個別ノード」：mesh は kit の .res、または PropFixP10 swaps に登記された差し替え先（st_hasa_v2／_l1）だけ合法＋反向（kit 外 BoxMesh → 検出）'},
                 'unchanged': 'human_use_p10.scn（baked）・生成器・humanuse_kit・審圖・他の gate 項目',
                 'files': {G + 'data/village_v2_p10r4_snapshot.json': [PRE[G + 'data/village_v2_p10r4_snapshot.json'], None],
                           G + 'tools/verify_village_v2_human_use.gd': [PRE[G + 'tools/verify_village_v2_human_use.gd'], None]},
                 'seal_file_before': PRE[r4]})
h = [x for x in hist if x.get('kind') == 'R4C_STRAW_GEOMETRY_A2'][0]
for f in [G + 'data/village_v2_p10r4_snapshot.json', G + 'tools/verify_village_v2_human_use.gd']:
    j['frozen'][f] = sha(f)
    h['files'][f][1] = j['frozen'][f]
for e in files(INT + 'r4_reseal/*.log'):
    j['evidence'][e] = sha(e)
j['child_seals'][r4c_seal] = sha(r4c_seal)
h['child_seals_added'] = {r4c_seal: j['child_seals'][r4c_seal]}
save(r4, j)
print('R4 reseal', PRE[r4][:12], '→', sha(r4)[:12])

jb = load(r4b)
hb = jb.setdefault('reseal_history', [])
if not any(x.get('kind') == 'R4C_CHILD_R4_UPDATE' for x in hb):
    assert sha(r4b) == PRE[r4b], 'R4b seal が想定外に変わっている'
    hb.append({'at': DATE, 'kind': 'R4C_CHILD_R4_UPDATE', 'approved_by': 'user', 'approval_source': APPROVAL,
               'reason': 'R4b gate は R4 snapshot（A2）を独立に検証し、R4 封存を子に持つ → R4 limited reseal（R4C_STRAW_GEOMETRY_A2）に追従。R4b の 40 件・生成器・overlay は不変。',
               'child_seals': {r4: [PRE[r4], None]}, 'seal_file_before': PRE[r4b]})
x = [x for x in hb if x.get('kind') == 'R4C_CHILD_R4_UPDATE'][0]
jb['child_seals'][r4] = sha(r4)
x['child_seals'][r4][1] = jb['child_seals'][r4]
for e in files(INT + 'r4b_reseal/*.log'):
    jb['evidence'][e] = sha(e)
save(r4b, jb)
print('R4b reseal', PRE[r4b][:12], '→', sha(r4b)[:12])
