"""P10 R3e Outer Village Population seal writer (user ART_APPROVED 2026-10-07: 外圍 12 人＝外圍最終人口基準).
Writes godot/data/village_v2_p10r3e_seal.json from the generator snapshot (godot/data/village_v2_p10r3e_snapshot.json,
written by verify_village_v2_population_outer.gd -- --snapshot=...).
Verify: godot --headless --path godot --script res://tools/verify_village_v2_population_outer.gd -- --seal
Usage: python tools/seal_p10r3e.py
"""
import glob, hashlib, json, os
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(R)
sha = lambda f: hashlib.sha256(open(f, 'rb').read()).hexdigest()
G = 'godot/'
frozen_list = [G + f for f in [
    'tools/village_v2_population_outer_lib.gd', 'scripts/npc_activity_outer.gd', 'tools/verify_village_v2_population_outer.gd',
    'tools/shot_p10_population_outer.gd', 'tools/shot_village_v2_population_outer_views.json',
    'maps/village_v2/gen/population_outer_p10.tscn', 'data/village_v2_p10r3e_snapshot.json']] + ['tools/seal_p10r3e.py']
A = 'docs/art_review/village_v2_p10_population/outer_r1/'
evidence = sorted(set(f.replace('\\', '/') for pat in [A + 'gate/*', A + 'review/README.md', A + 'render/route_counts.json'] for f in glob.glob(pat)))
images = sorted(set(f.replace('\\', '/') for pat in [A + 'review/*.jpg', A + 'review/*.png', A + 'render/*.png'] for f in glob.glob(pat)))
snap = json.load(open(G + 'data/village_v2_p10r3e_snapshot.json', encoding='utf-8'))
seal = {
    'schema': 1, 'phase': 'P10 R3e Outer Village Population Pilot r1',
    'status': 'ART_APPROVED', 'approved_by': 'user', 'approved_date': '2026-10-07',
    'approval_source': '使用者 2026-10-07：「P10 R3e Outer Village Population = ART_APPROVED。12 人外圍人口配置正式通過。不再增加外圍 NPC 數量。」「可以封存 R3e」',
    'final_baseline': '外圍 12 人＝外圍最終人口基準；核心 39＋外圍 12＝51 個有明確用途的 NPC instance。人口梯度：核心區最密 → 主街／市場外圍明顯下降 → 農田／水車／後巷零星 → 森林／山腳無人＝正式方向。',
    'do_not': ['不再增加外圍人口', '不把人口塞進森林', '不增加山腳居民', '不為農田另開 animation production', '不填滿所有 anchors'],
    'rule': '封存後不修改外圍人口，除非真正 collision／animation bug（OUTER_ALLOW_REBAKE=1＋使用者同意＋reseal）。',
    'roster': {'outer_total': snap['outer_total'], 'core_total': snap['core_total'], 'total': snap['total'], 'zone_counts': snap['zone_counts'],
               'snapshot': G + 'data/village_v2_p10r3e_snapshot.json', 'core_snapshot': G + 'data/village_v2_p10r3d_snapshot.json'},
    'outer': [{k: r[k] for k in ('id', 'model', 'zone', 'trade', 'group', 'anchor', 'mode', 'position', 'yaw_deg', 'distance_from_core_m')}
              | ({'activity': r['activity']} if 'activity' in r else {})
              | ({'patrol_endpoints': r['patrol']['endpoints'], 'patrol_path': r['patrol']['path']} if 'patrol' in r else {}) for r in snap['outer']],
    'density_bands': snap['density_bands'],
    'forbidden_zones': {'rule': snap['forbidden'], 'allowed_boxes_xzwh': snap['zone_boxes'], 'zone_ranges': snap['zone_ranges']},
    'mount': 'village_v2.tscn Population：PopulationP10 → ActivityP10 → CoreP10 → ActivityCoreP10 → EntranceCueP10 → OuterP10 → ActivityOuterP10（各 1 つ）',
    'non_blocking': ['水車旁兩人與水輪／樹樁在畫面上視覺重疊（無穿模）', '井邊角色靠近井柱（無穿模）',
                     '農田目前沒有專用農作動畫（站立・短距離走動・搬收成；不硬套城市動作）'],
    'verification': {'plan': 14, 'negatives': 13, 'scene': 6, 'seal': 9, 'tag': 'OUTER'},
    'frozen': {f: sha(f) for f in frozen_list},
    'evidence': {f: sha(f) for f in evidence},
    'art_review_images': {f: sha(f) for f in images},
    'child_seals': {f: sha(f) for f in [G + 'data/village_v2_p10r3d_seal.json', G + 'data/village_v2_p10r3c_seal.json',
                                         G + 'data/village_v2_p10r3b_seal.json', G + 'data/village_v2_p10_npclib_seal.json']},
}
open(G + 'data/village_v2_p10r3e_seal.json', 'wb').write((json.dumps(seal, ensure_ascii=False, indent=1) + '\n').encode('utf-8'))
print('sealed frozen', len(seal['frozen']), 'evidence', len(evidence), 'images', len(images))
