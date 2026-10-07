"""P10 R2 Main Street r5 seal writer (user ART_APPROVED 2026-10-07).
Seals the current main-street props / street-life baseline: street_kit (32 構件＋atlas ST_Street) + Props/StreetP10 overlay
(gen/street_p10.scn) + generator / gate + archived ART_REVIEW images + evidence. Not reopened by later population phases.
Verify: godot --headless --path godot --script res://tools/verify_village_v2_street.gd -- --seal
Usage: python tools/seal_p10r2.py
"""
import glob, hashlib, json, os
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(R)
sha = lambda f: hashlib.sha256(open(f, 'rb').read()).hexdigest()
K = 'godot/assets/village_v2/street_kit/'
frozen_list = [
    'godot/tools/village_v2_street_lib.gd', 'godot/tools/verify_village_v2_street.gd',
    'godot/assets/blender/village_v2/build_street_kit.py', 'tools/build_village_v2_street_atlas.py',
    K + 'atlas.json', K + 'street_kit_atlas.png', K + 'street_kit_manifest.json', K + 'ST_Street.tres', K + 'src/modules_blender.json',
    'godot/maps/village_v2/gen/street_p10.scn', 'godot/tools/shot_village_v2_street_views.json',
    'godot/tools/village_v2_text_facing_lib.gd', 'godot/tools/audit_village_v2_text_facing.gd',
] + sorted(f.replace('\\', '/') for f in glob.glob(K + 'mesh/*.res'))
D = 'docs/art_review/village_v2_p10_props/'
images = sorted(f.replace('\\', '/')[len(D):] for f in glob.glob(D + 'r2/*.jpg'))
evidence = sorted(f.replace('\\', '/')[len(D):] for f in glob.glob(D + 'evidence/street_*.log') + [D + 'evidence/p10r2_cross_regression.log']
                  + glob.glob(D + 'r2_status_20261007/*.log') + glob.glob(D + 'text_facing/*.json') + glob.glob(D + 'text_facing/*.log'))
seal = {
    'phase': 'P10 R2 Main Street / Street Life r5',
    'status': 'ART_APPROVED', 'approved_by': 'user', 'approved_at': '2026-10-07',
    'approval_source': '使用者 2026-10-07：「P10 R2 Main Street r5 = ART_APPROVED，可以正式 seal。封存的是目前主街 props / street-life baseline，不再因人口階段重開 R2 本體。」',
    'scope': 'street_kit（32 構件＋atlas ST_Street）＋Props/StreetP10 overlay（gen/street_p10.scn；124 件、NPC activity anchors 65）；主街店頭外溢・巷口道標・市の入口・作業場・井戸端・干し竿・農田交界',
    'renderer': 'Forward+',
    'non_blocking': [
        '南側から「市」の字が小さい＝non-blocking。R2 では招牌サイズを変えない；R3d の greeter／vendor NPC・shopper movement・delivery／carry・entrance clustering で導引を補う。R3d ART_REVIEW 後も南側で市場が読めなければ小型 entrance-cue pass（R2 本體は重開しない）。',
        '看板と箱物が「店の飾り」寄り・吊り提灯の綱が細い・暗い樽桶（P13）'],
    'post_review_fix': '2026-10-07 使用者指示「旗子或其他物件字樣從反面看字是反的 請修正」：幟 3・大幟「市 此方」の裏面 UV を左右反轉（build_street_kit.py の裏の quad）。字の向き監査 audit_village_v2_text_facing.gd --strict で鏡像 0。構図・配置・overlay は不変（street_p10.scn は mesh を外部參照）。',
    'frozen': {f: sha(f) for f in frozen_list},
    'art_review_images': {f: sha(D + f) for f in images},
    'evidence': {f: sha(D + f) for f in evidence},
}
open('godot/data/village_v2_p10r2_seal.json', 'wb').write((json.dumps(seal, ensure_ascii=False, indent=1) + '\n').encode('utf-8'))
print('sealed frozen', len(seal['frozen']), 'images', len(images), 'evidence', len(evidence))
