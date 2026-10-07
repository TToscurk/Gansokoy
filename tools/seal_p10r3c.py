"""P10 R3c / R3c.1 Activity baseline seal writer (user ART_APPROVED 2026-10-07).
Seals the approved Activity vocabulary and usage rules — not a promise that each NPC keeps this action forever.
Reads the live overlay ASSIGN (parsed from npc_activity_overlay.gd) and writes godot/data/village_v2_p10r3c_seal.json.
Verify: godot --headless --path godot --script res://tools/verify_p10_activity.gd -- --seal
Usage: python tools/seal_p10r3c.py
"""
import glob, hashlib, json, os, re
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(R)
sha = lambda f: hashlib.sha256(open(f, 'rb').read()).hexdigest()
OV = 'godot/scripts/npc_activity_overlay.gd'
src = open(OV, encoding='utf-8').read()
block = src[src.index('const ASSIGN={') + len('const ASSIGN='):src.index('\n}\n', src.index('const ASSIGN={')) + 2]
assign = json.loads(block)
grip = re.search(r'var cup_grip:=Vector3\(([^)]*)\)', src).group(1)
axis = re.search(r'var cup_axis:=Vector3\(([^)]*)\)', src).group(1)
A = 'docs/art_review/village_v2_p10_population/'
prov_files = glob.glob(A + 'activity_candidates_r1/*_download.json') + glob.glob(A + 'activity_r1c1/candidates/*_download.json')
prov = {}
for f in prov_files:
    j = json.load(open(f, encoding='utf-8'))
    prov[(j['character'], j['clip'])] = (f.replace('\\', '/'), j)
assignments, anim = {}, {}
for path, a in assign.items():
    cid, clip = a[1], a[2]
    g = f'godot/animations/npc_activity_p10/{cid}/{clip}_grounded.res'
    s = f'godot/animations/npc_activity_p10/{cid}/src/{clip}.fbx'
    pf, pj = prov[(cid, clip)]
    anim[g] = sha(g); anim[s] = sha(s); anim[pf] = sha(pf)
    for glb in ('activity_candidates.glb', 'drink_ab_candidates.glb', 'readability_candidates.glb'):
        gp = f'godot/animations/npc_activity_p10/{cid}/{glb}'
        if os.path.exists(gp):
            anim[gp] = sha(gp)
    assignments[path] = {'type': a[0], 'npc': cid, 'clip': clip, 'slot': a[3], 'options': a[4] if len(a) > 4 else {},
                         'mixamo': {'name': pj['name'], 'product': pj['product'], 'character_uuid': pj['character_uuid'],
                                    'model_id': pj['motion']['model-id'], 'params': pj['motion']['params'], 'inplace': pj['motion']['inplace']},
                         'arm_space': pj['arm_space']}
frozen = {f: sha(f) for f in [
    OV, 'godot/maps/village_v2/activity_p10.tscn', 'godot/tools/verify_p10_activity.gd',
    'godot/tools/probe_p10_drink_ab2.gd', 'godot/tools/probe_p10_drink_dump.gd', 'godot/tools/probe_p10_r3c1_contact.gd',
    'godot/tools/probe_p10_readability.gd', 'godot/tools/shot_p10_r3c1_motion.gd', 'godot/tools/shot_p10_drink_ab.gd',
    'tools/fit_p10_drink_cup.py', 'tools/build_p10_activity_r1.py', 'tools/build_p10_drink_ab.py', 'tools/build_p10_r3c1.py',
    'tools/mixamo_fetch_r3c1.py', 'tools/seal_p10r3c.py']}
frozen.update(anim)
evidence = {}
for pat in [A + 'activity_r1c1/gate/*', A + 'activity_r1c1/contact_final.json', A + 'activity_r1c1/readability_baseline.json',
            A + 'activity_r1/drink_ab/drink_ab2_final.json', A + 'activity_r1/drink_ab/drink_ab2_old.json', A + 'activity_r1/drink_ab/cup_fit_B1.json',
            A + 'activity_r1/final_gate/*']:
    for f in sorted(glob.glob(pat)):
        evidence[f.replace('\\', '/')] = sha(f)
images = {}
for pat in [A + 'activity_r1c1/review/*', A + 'activity_r1/final_review/*']:
    for f in sorted(glob.glob(pat)):
        images[f.replace('\\', '/')] = sha(f)
seal = {
    'schema': 1, 'phase': 'P10 R3c Mixamo Activity Pack + R3c.1 Readability Pass', 'status': 'ART_APPROVED',
    'approved_by': 'user', 'approved_date': '2026-10-07',
    'approval_source': '使用者 2026-10-07：「P10 R3c.1 Readability Pass = ART_APPROVED」＋「可以將 R3c / R3c.1 作為目前核准的 Activity baseline 封存」',
    'scope': '封存的是目前的 Activity vocabulary 與使用規則（指派・動作資產・Mixamo 來源・arm-space・道具與握持參數・可讀性擺位・淘汰清單・gate 證據），'
             '不代表未來每個 NPC 永久固定在這個動作。R3d 起可沿用此 vocabulary 指派給新人口；改動既有指派／參數需使用者授權並 reseal。',
    'baseline': {'population': 16, 'r3b_seal': 'godot/data/village_v2_p10r3b_seal.json', 'r3b_unchanged': True,
                 'mount': 'village_v2.tscn Population/ActivityP10（Population/PopulationP10 之後，exactly 1）'},
    'verdicts': [
        'Sit：約 10 m 直接讀取，通過（W4 藥草婆婆＋紅毛氈縁台）',
        'Carry／Talk：約 19 m 單張靜態較弱、動態可讀出捧貨＋交談＝可接受的 distance-dependent readability',
        '不要求每個 Activity 在 19 m 靜態截圖像 icon 一樣可辨識',
        'W3 Drink 保留 B1（drinking_im1_a030＋新杯握持），不再磨',
        'S4 walking carry 維持淘汰，不再嘗試救',
        '縁台座高 0.285 m 接受，不因理論座高重做',
        'W1／W2 不在主要 review view 不構成 blocker'],
    'assignments': assignments,
    'props': {'cup': {'grip_LeftHand_axes': [float(x) for x in grip.split(',')], 'axis_LeftHand_axes': [float(x) for x in axis.split(',')],
                      'mesh': 'overlay tea_cup()（lathed yunomi 0.027→0.036 × 0.072 m、底蓋あり）'},
              'crate_S2': assignments['MainStreet/S2_yaoya_m01']['options'],
              'bench_W4': assignments['MarketWest/W4_yakusou_f01']['options']},
    'readability_placement': {'probe': 'godot/tools/probe_p10_readability.gd', 'baseline': A + 'activity_r1c1/readability_baseline.json',
                              'rule': 'Activity は六類審圖鏡位で実際に見える住人へ（被擋・畫面外の住人には付けない）'},
    'rejected_candidates': [
        {'what': 'W3 drinking_a030（A）', 'why': '喝時低頭 48°、上臂 104°、杯進臉 3.1 cm、杯到眼高 1.30 s／循環'},
        {'what': 'W3 watercooler_a030（B2）', 'why': '杯距嘴 4.6 cm（沒真的喝）、臉／袖／軀幹命中、hold 段前傾'},
        {'what': '舊杯握持（0.020,0,0.022／−hand.x）', 'why': '杯進臉、指陷杯 1.9 cm、喝時杯轉過水平'},
        {'what': 'M6 takigi box_idle', 'why': '道具貫穿三角形（R3c）'},
        {'what': 'M4 Carry／M5 Sit／W1・W2 Talk の位置', 'why': '審圖鏡位で被擋・畫面外（27–69 px）→ R3c.1 で回 baseline／移設'},
        {'what': 'S4 Holding Walk＋木箱', 'why': '重定向後雙手在腰側，木箱穿骨盆 13 cm'},
        {'what': 'S4 Walking With Shopping Bag', 'why': '步速 0.92 m/s、patrol 1.32 m/s → 要快 44% 才不滑腳；patrol 速度不改'},
        {'what': 'M2 talk_twohands', 'why': '遠距反而比 talk_general 不明顯'}],
    'frozen': frozen, 'evidence': evidence, 'art_review_images': images,
    'child_seals': {f: sha(f) for f in ['godot/data/village_v2_p10r3b_seal.json', 'godot/data/village_v2_p10_npclib_seal.json']},
}
out = 'godot/data/village_v2_p10r3c_seal.json'
open(out, 'wb').write((json.dumps(seal, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))
print('sealed', out, 'frozen', len(frozen), 'evidence', len(evidence), 'images', len(images), 'assignments', len(assignments))
