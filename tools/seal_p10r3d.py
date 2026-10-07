"""P10 R3d Village Core Population seal writer (user ART_APPROVED 2026-10-07: r1 39 人核心人口＋r1.1 Market South Entrance Cue).
Writes godot/data/village_v2_p10r3d_seal.json. Roster / positions / facing / activity / patrol / entrance cue come from the
generator snapshot (godot/data/village_v2_p10r3d_snapshot.json, written by verify_village_v2_population_core.gd -- --snapshot=...).
Verify: godot --headless --path godot --script res://tools/verify_village_v2_population_core.gd -- --seal
Usage: python tools/seal_p10r3d.py
"""
import glob, hashlib, json, os
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(R)
sha = lambda f: hashlib.sha256(open(f, 'rb').read()).hexdigest()
G = 'godot/'
frozen_list = [G + f for f in [
    'tools/village_v2_population_core_lib.gd', 'tools/village_v2_entrance_cue_lib.gd', 'scripts/npc_activity_core.gd',
    'tools/verify_village_v2_population_core.gd', 'tools/shot_p10_population_core.gd', 'tools/survey_village_v2_population_core.gd',
    'tools/shot_village_v2_population_core_views.json', 'maps/village_v2/gen/population_core_p10.tscn', 'maps/village_v2/gen/entrance_cue_p10.tscn',
    'data/village_v2_p10r3d_snapshot.json']] + ['tools/seal_p10r3d.py']
A = 'docs/art_review/village_v2_p10_population/'
evidence = sorted(set(f.replace('\\', '/') for pat in [A + 'core_r1/gate/*', A + 'core_r1_1/gate/*', A + 'core_r1/review/README.md', A + 'core_r1_1/review/README.md'] for f in glob.glob(pat)))
images = sorted(set(f.replace('\\', '/') for pat in [A + 'core_r1/review/*.jpg', A + 'core_r1/render/*.png', A + 'core_r1_1/review/*.jpg', A + 'core_r1_1/review/*.gif',
                                                     A + 'core_r1_1/r1_state/*.png', A + 'core_r1_1/r1_1/*.png'] for f in glob.glob(pat)))
snap = json.load(open(G + 'data/village_v2_p10r3d_snapshot.json', encoding='utf-8'))
by = {r['id']: r for r in snap['r3d_added']}
seal = {
    'schema': 1, 'phase': 'P10 R3d Village Core Population Expansion r1 + r1.1 Market South Entrance Cue',
    'status': 'ART_APPROVED', 'approved_by': 'user', 'approved_date': '2026-10-07',
    'approval_source': '使用者 2026-10-07：「P10 R3d = ART_APPROVED。r1 39 人核心人口配置＋r1.1 Market South Entrance Cue 正式通過。可以封存 R3d。」',
    'rule': '封存後不再修改核心人口，除非後續出現真正 collision／animation bug（CORE_ALLOW_REBAKE=1＋使用者同意＋reseal）。',
    'roster': {'total': snap['total'], 'zone_counts': snap['zone_counts'], 'r3b_baseline': 16, 'r3d_added': len(snap['r3d_added']),
               'snapshot': G + 'data/village_v2_p10r3d_snapshot.json'},
    'r3b_baseline_unchanged': {'child_seal': G + 'data/village_v2_p10r3b_seal.json', 'note': 'R3b 16 人（generator／actor／Population scene／snapshot）不變；R3d は別 overlay Population/CoreP10'},
    'added': [{k: r[k] for k in ('id', 'model', 'zone', 'trade', 'group', 'mode', 'position', 'yaw_deg') } | ({'activity': r['activity']} if 'activity' in r else {})
              | ({'patrol_endpoints': r['patrol']['endpoints'], 'patrol_path': r['patrol']['path']} if 'patrol' in r else {}) for r in snap['r3d_added']],
    'south_entrance': {
        'C6': {'role': '南の主街 → 辻 → 市の口を往復する買い物客（往＝入る・返＝出る）', 'patrol_endpoints': by['C6']['patrol']['endpoints'], 'path': by['C6']['patrol']['path']},
        'C11': {'role': '口の東の幟の脇で辻を向く呼び込み（Talk、通路を塞がない）', 'position': by['C11']['position'], 'yaw_deg': by['C11']['yaw_deg']},
        'C12': {'role': '口のすぐ内側で木箱を抱えて中橫街を向く八百屋（Carry）', 'position': by['C12']['position'], 'yaw_deg': by['C12']['yaw_deg']}},
    'entrance_cue': {'node': 'Population/EntranceCueP10', 'scene': G + 'maps/village_v2/gen/entrance_cue_p10.tscn', 'items': snap['entrance_cue'],
                     'note': '既存 market_kit の小幟「市」2 本（新資產なし、R2 不重開）、口の通路 10.7 m'},
    'mount': 'village_v2.tscn Population：PopulationP10 → ActivityP10 → CoreP10 → ActivityCoreP10 → EntranceCueP10（各 1 つ）',
    'non_blocking': ['遠距で幟の「市」の字が読めない＝expected distance limitation',
                     '静止画では個々の人の進出方向が完全には読めない（動態で読める）＝expected distance limitation',
                     '寺子屋の審圖鏡位で子と玩家角色が画面上で重なる（配置の問題ではない）'],
    'verification': {'plan': 14, 'negatives': 13, 'scene': 9, 'tag': 'CORE'},
    'frozen': {f: sha(f) for f in frozen_list},
    'evidence': {f: sha(f) for f in evidence},
    'art_review_images': {f: sha(f) for f in images},
    'child_seals': {f: sha(f) for f in [G + 'data/village_v2_p10r3b_seal.json', G + 'data/village_v2_p10r3c_seal.json', G + 'data/village_v2_p10_npclib_seal.json']},
}
open(G + 'data/village_v2_p10r3d_seal.json', 'wb').write((json.dumps(seal, ensure_ascii=False, indent=1) + '\n').encode('utf-8'))
print('sealed frozen', len(seal['frozen']), 'evidence', len(evidence), 'images', len(images))
