"""P10 R5b.1 Irrigation Source Reconstruction：P8 limited reseal（使用者 2026-10-10 P10 FINAL CLOSEOUT「R5b.1 灌溉：方案 B LIMITED APPROVAL」）。

  python tools/seal_p8_r5b1.py   → data/village_v2_p8_seal.json の frozen の変わった 3 件だけ更新し reseal_history に記録、
                                   P8 封存を子に持つ R4b（data/village_v2_p10r4b_seal.json の child_seals）だけ追従更新
  検証：Godot --headless --path godot --script res://tools/verify_village_v2_farmland.gd -- --seal（雜湊＋記憶體竄改反向）、
        verify_village_v2_human_use_exp.gd --seal（R4b）

使用者裁定（原文）：「允許 P8 limited correction」「以一台竜骨車作為優先方案，先確認約 1.8 m 揚程、進出水高度與實際水路連通」
  「正式移除失去功能的架高落とし樋、無效支柱及相關碰撞」「保留原本水車 2 的純動力功能」「修正 FEEDER Gate 所指出的實際場景問題」
  「僅修改必要的 P8 內容與下游依賴，記錄 limited reseal history」「不允許重做整個農田或河流系統」
P8 の status（ART_APPROVED 2026-10-01）は変えない。竜骨車そのものの見た目は ART_REVIEW（使用者未核准）として記録する。
冪等：同じ kind の記録があれば old は最初の値を保持し、new だけ現在値に更新する。
"""
import hashlib
import json
import os

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(R)
SEAL = 'godot/data/village_v2_p8_seal.json'
EV = 'docs/art_review/village_v2_p10_rehab_impl/r5b1_irrigation/impl/'
KIND = 'R5B1_IRRIGATION_SOURCE_RYUKOTSU'


def sha(f):
    return hashlib.sha256(open(f, 'rb').read()).hexdigest()


d = json.load(open(SEAL, encoding='utf-8'))
changed = {}
for k, v in d['frozen'].items():
    now = sha('godot/' + k)
    if now != v:
        changed[k] = {'old': v, 'new': now}
hist = d.setdefault('reseal_history', [])
ent = next((h for h in hist if h.get('kind') == KIND), None)
if ent is None:
    ent = {'kind': KIND, 'date': '2026-10-10', 'changed': {}}
    hist.append(ent)
for k, c in changed.items():
    if k in ent['changed']:
        ent['changed'][k]['new'] = c['new']
    else:
        ent['changed'][k] = c
    d['frozen'][k] = c['new']
ent.update({
    'authorized_by': 'user',
    'authorization': '使用者 2026-10-10 P10 FINAL CLOSEOUT「2. R5b.1 灌溉：方案 B LIMITED APPROVAL」：允許 P8 limited correction；'
                     '以一台竜骨車作為優先方案；正式移除失去功能的架高落とし樋、無效支柱及相關碰撞；僅修改必要的 P8 內容與下游依賴，記錄 limited reseal history。',
    'reason': '水車 2 が純動力（P10 R5b ROUND 3）になり、r5 の取水鎖「水渠 → 水車 2 受け樋 3.30 → 高架落とし樋 → 落とし桝」は水源を失った。'
              'ROUND 3 では WaterLifeP10 が runtime で高架樋を隠し碰撞を止めていた（P8 FEEDER post_collision FAIL：可見支柱 4 本に碰撞なし）。'
              'P8 生成器で高架落とし樋・接頭箱・受け樋枕木・支柱と其碰撞（可見 6 群・碰撞 3）を撤去し、竜骨車 1 台（人力・踏み軸）＋送り樋で '
              '水渠水面 −1.52 から落とし桝（水面 0.28）へ汲み上げる。落とし桝以下（上段土渠・伏越し・木槽・內渠）は不変。',
    'scope': 'P8 farmland_p8.scn の FieldDetails/WaterSupply（Chute_0／Chute_1／ChuteJoint／HeadBearer／Support_00／Support_01 → Ryukotsu）と '
             'Irrigation/WaterSupply の碰撞形（Post_00／Post_01／Chute_1 → 竜骨車の Post_00–07・RyuHead・RyuRail・RyuTrough・Feed）だけ。'
             'その他 8677 ノード（MultiMesh 1844 を含む）は逐ノード等価（変換・網格配列・材質・MultiMesh バッファ・碰撞形・meta）。',
    'measurements': {'canal_water': -1.52, 'canal_bed_at_intake': -2.33, 'intake_trough_bottom': -1.80, 'discharge_trough_bottom': 0.66,
                     'drop_box_water': 0.288, 'required_lift_m': 1.81, 'design_lift_to_discharge_m': 2.18, 'incline_deg': 28.4,
                     'trough_length_m': 5.17, 'bank_clearance_min_m': 0.18, 'feed_trough_clearance_min_m': 0.24,
                     'water_chain': [-1.52, 0.66, 0.59, 0.56, 0.288, 0.278, 0.27, 0.19, 0.18, 0.15, 0.078]},
    'art_status_of_change': 'ART_REVIEW（竜骨車の見た目は使用者未核准；P8 本体の ART_APPROVED 2026-10-01 は変更なし）',
    'dependencies': {
        'updated': ['tools/village_v2_farmland_lib.gd', 'tools/village_v2_farmland_visual.gd', 'maps/village_v2/gen/farmland_p8.scn'],
        'unchanged_frozen': [k for k in d['frozen'] if k not in changed],
        'downstream_updated': ['tools/walk_village_v2_farmland.gd（FEEDER：系統狀態・水源連通・他層干渉を追加、既存項目は不変）',
                               'tools/village_v2_water_life_lib.gd・maps/village_v2/scripts_p10/water_life.gd・maps/village_v2/gen/water_life_p10.scn'
                               '（WaterLifeP10 の P8 runtime 非表示／碰撞停止を撤去；R5b は未封存）',
                               'tools/verify_village_v2_water_life.gd（WLF 項目 4・反向 N7／N8 を「P8 に触れない・高架部材は竜骨車だけ」へ）'],
        'downstream_resealed': ['data/village_v2_p10r4b_seal.json（child_seals の P8 封存雜湊のみ；R4b の 40 件・生成器・overlay・scene gate は不変、kind R5B1_CHILD_P8_UPDATE）'],
        'not_affected': ['水車 1／3（WW1／WW3 の zone 取水は不変）', 'P2 水渠・P1 地形・P7 河岸（RB_10_0 と干渉 0）', 'P9 WatersideP9（Irrigation の網格は不変）',
                         'P10 R4 HUSE（Irrigation の網格は不変）', 'NPC 51'],
    },
    'negatives': ['FEEDER supply_system_state：ROUND 3 の状態（runtime で隠した部材・止めた碰撞）→ FAIL（feeder_round3_state.log）',
                  'WLF N7（高架落とし樋が P8 に残る）・N8（overlay が P8 を隠す）→ FAIL',
                  '--seal：記憶體で期待雜湊を 1 件竄改 → 1 件不符を検出'],
    'evidence': [EV + f for f in ['p8_build.log', 'p8_equivalence.log', 'feeder.log', 'feeder_round3_state.log', 'wlf_plan_negatives.log', 'wlf_build.log', 'wlf_scene.log', 'p8_seal_after.log']],
})
open(SEAL, 'wb').write((json.dumps(d, ensure_ascii=False, indent=1) + '\n').encode('utf-8'))
print('P8 reseal：changed %d → %s' % (len(changed), ', '.join(changed)))
for k, c in ent['changed'].items():
    print('  %s %s → %s' % (k, c['old'][:12], c['new'][:12]))

# ── R4b：child_seals に P8 封存を持つ → 追従（R4b の内容は不変：scene gate 0 失敗を確認してから実行）
R4B = 'godot/data/village_v2_p10r4b_seal.json'
P8K = 'godot/data/village_v2_p8_seal.json'
r4b_before = sha(R4B)
b = json.load(open(R4B, encoding='utf-8'))
old_child = b['child_seals'][P8K]
new_child = sha(SEAL)
if old_child != new_child:
    rh = b.setdefault('reseal_history', [])
    e2 = next((h for h in rh if h.get('kind') == 'R5B1_CHILD_P8_UPDATE'), None)
    if e2 is None:
        e2 = {'at': '2026-10-10', 'kind': 'R5B1_CHILD_P8_UPDATE', 'child_seals': {P8K: [old_child, new_child]}, 'seal_file_before': r4b_before}
        rh.append(e2)
    else:
        e2['child_seals'][P8K][1] = new_child
    e2.update({'approved_by': 'user',
               'approval_source': '使用者 2026-10-10 P10 FINAL CLOSEOUT：「R5b.1 灌溉：方案 B LIMITED APPROVAL」「允許 P8 limited correction」「進行必要的 affected-seal reseal，不修改無關封存」',
               'reason': 'R4b は P8 封存を子に持つ（A 農田群が P8 の田・畦に依存）。P8 limited reseal（R5B1_IRRIGATION_SOURCE_RYUKOTSU：水車 2 東岸の取水構件だけ）に追従。'
                         'R4b の 40 件・生成器・overlay は不変；R4b scene gate 0 失敗（docs/art_review/village_v2_p10_final_closeout/regression/full_regression.log）。'})
    b['child_seals'][P8K] = new_child
    open(R4B, 'wb').write((json.dumps(b, ensure_ascii=False, indent=1) + '\n').encode('utf-8'))
    print('R4b child：P8 %s → %s（R4b seal %s → %s）' % (old_child[:12], new_child[:12], r4b_before[:12], sha(R4B)[:12]))
else:
    print('R4b child：P8 封存雜湊は一致（変更なし）')
