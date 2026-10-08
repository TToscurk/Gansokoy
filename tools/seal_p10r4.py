"""P10 R4 Human-Use / Ambient Life Pilot seal writer（使用者 ART_APPROVED 2026-10-08：Pilot A／B／C）。
Writes godot/data/village_v2_p10r4_seal.json from the scene snapshot (godot/data/village_v2_p10r4_snapshot.json,
written by verify_village_v2_human_use.gd -- --snapshot=...).
Verify: godot --headless --path godot --script res://tools/verify_village_v2_human_use.gd -- --seal
Usage: python tools/seal_p10r4.py
"""
import glob
import hashlib
import json
import os

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(R)
G = 'godot/'


def sha(f):
    return hashlib.sha256(open(f, 'rb').read()).hexdigest()


K = G + 'assets/village_v2/humanuse_kit/'
frozen_list = [G + f for f in [
    'tools/village_v2_human_use_lib.gd', 'tools/verify_village_v2_human_use.gd', 'tools/shot_p10_human_use.gd',
    'tools/shot_p10_human_use_views.json', 'tools/shot_village_v2_topdown.gd',
    'assets/blender/village_v2/build_humanuse_kit.py',
    'maps/village_v2/gen/human_use_p10.scn', 'data/village_v2_p10r4_snapshot.json']] \
    + [K + 'src/humanuse_kit.glb', K + 'src/modules_blender.json', K + 'humanuse_kit_manifest.json'] \
    + sorted(f.replace('\\', '/') for f in glob.glob(K + 'mesh/*.res')) + ['tools/seal_p10r4.py']
A = 'docs/art_review/village_v2_p10_props/human_use_r1/'
evidence = sorted(f.replace('\\', '/') for f in glob.glob(A + 'gate/*'))
images = sorted(set(f.replace('\\', '/') for pat in [A + 'review/*', A + 'render/*.png'] for f in glob.glob(pat)))
snap = json.load(open(G + 'data/village_v2_p10r4_snapshot.json', encoding='utf-8'))
clusters = {}
for it in snap['items']:
    c = clusters.setdefault(it['cluster'], {'pilot': it['pilot'], 'anchor': it['anchor'], 'items': []})
    c['items'].append(it['id'])
seal = {
    'schema': 1, 'phase': 'P10 R4 Human-Use / Ambient Life Pilot r4（A 農田／B 住宅後巷／C 水岸）',
    'status': 'ART_APPROVED', 'approved_by': 'user', 'approved_date': '2026-10-08',
    'approval_source': '使用者 2026-10-08：「P10 R4 Human-Use Pilot A / B / C = ART_APPROVED」「P10 R4 三個 Pilot 的生活痕跡已經達到本輪目標，不需要再為 3/5 的次要鏡位反覆微調」',
    'verdicts': {
        'A': '通過：脫穀、曬穀、搬運形成完整工作流程，不再只是散落農具',
        'B': '通過：四戶有不同生活習慣，沒有變成平均堆雜物',
        'C': '通過：水車維修、米俵搬運、洗衣形成具體的用水關係'},
    'value': '這次真正值得保留的是：10 個有用途的工作群組，而不是 50 件物件的數量。',
    'non_blocking': ['B 的側面可讀性較弱（B_near2／B4_near 約 3/5）', 'C 在 15 m 只約 3/5（C_mid）',
                     '未來擴張時，以玩家常走的方向優先安排主要生活物件，不需要把每個角度都磨到 5/5'],
    'mount': 'village_v2 root 直下 HumanUseP10＝Props の次（使用者 2026-10-08 承認：獨立 overlay、與 Props 平行；不為節點分類重新封存 R3b）。Props の子は封存どおり MarketP10 → StreetP10 → MarketWestP10 → EnvironmentP9。',
    'expansion_rules': ['不要全村平均增加生活道具', '農田依照生產與運輸動線安排', '住宅依每戶生活差異安排', '水岸依水源用途安排',
                        '核心商業區已經有大量 P10 Props，不應再次重複堆放', '以玩家常走的方向優先安排主要生活物件'],
    'rule': '封存後不修改 HumanUseP10 的配置・資產・生成器，除非真正的 placement／collision bug（HUSE_ALLOW_REBAKE=1＋使用者同意＋reseal）。共用 prefab tools/village_v2_machiya_kit_prefab.gd は他 Kit と共用なので凍結しない（humanuse_kit の mesh .res／manifest を凍結）。',
    'roster': {'total': snap['total'], 'pilots': snap['pilots'], 'clusters': clusters, 'snapshot': G + 'data/village_v2_p10r4_snapshot.json',
               'assets': {'reused_items': sum(1 for it in snap['items'] if not it['id'].startswith('hu_')),
                          'new_kit': 'humanuse_kit（hu_senba・hu_tomi・hu_momiboshi・hu_tarai・hu_makiwari・hu_seoikago）'}},
    'verification': {'plan': 14, 'negatives': 16, 'build_readback': 3, 'scene': 11, 'seal': 8, 'tag': 'HUSE'},
    'frozen': {f: sha(f) for f in frozen_list},
    'evidence': {f: sha(f) for f in evidence},
    'art_review_images': {f: sha(f) for f in images},
    'child_seals': {f: sha(f) for f in [G + 'data/village_v2_p9_final_seal.json', G + 'data/village_v2_p10r1_seal.json',
                                         G + 'data/village_v2_p10r1b_seal.json', G + 'data/village_v2_p10r2_seal.json',
                                         G + 'data/village_v2_p10r3d_seal.json', G + 'data/village_v2_p10r3e_seal.json']},
}
open(G + 'data/village_v2_p10r4_seal.json', 'wb').write((json.dumps(seal, ensure_ascii=False, indent=1) + '\n').encode('utf-8'))
print('sealed frozen', len(seal['frozen']), 'evidence', len(evidence), 'images', len(images), 'children', len(seal['child_seals']))
