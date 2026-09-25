"""人間之里 V2 P5 Asset Reset：產生 godot/data/village_v2_asset_registry.json（資產白名單／Protected／封存登記）。
用法（repo 根目錄）：python tools/build_village_v2_asset_registry.py [--move]
  不帶 --move：重算雜湊、改寫 registry（已封存的檔以 archive/ 內的雜湊登記）。
  --move：把 archived_moved 清單搬到 archive/reference_old_assets/（先驗雜湊、不覆蓋既有檔、不刪任何檔），並寫 MANIFEST.json。
不動 git index。驗證：godot/tools/verify_village_v2_asset_reset.gd（已在 run_village_v2_regression.sh）。
Protected 資產（龍神像、火見櫓、神社關聯）的原檔不得修改；REWORK 產物另存 godot/assets/village_v2/<名>/，
過 Asset Gate 11 項後才登記到 v2_assets（依 godot/tools/verify_village_v2_hero_gate.gd 寫的 gate.json）。
"""
import hashlib, json, os, shutil, sys, glob
from pathlib import Path

R = Path(__file__).resolve().parents[1].as_posix()
G = R + '/godot'
EXT = 'D:/資產glb'
ARCH = R + '/archive/reference_old_assets'
MOVE = '--move' in sys.argv


def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def res(p):  # godot 絕對路徑 → res://
    p = p.replace('\\', '/')
    assert p.startswith(G + '/'), p
    return 'res://' + p[len(G) + 1:]


def fentry(p):
    return {'path': res(p) if p.startswith(G + '/') else p.replace('\\', '/'),
            'bytes': os.path.getsize(p), 'sha256': sha(p)}


def dentry(p):
    n = b = 0
    for root, _, files in os.walk(p):
        for f in files:
            if f.endswith('.import'):
                continue
            n += 1
            b += os.path.getsize(os.path.join(root, f))
    return {'path': res(p) if p.startswith(G + '/') else p.replace('\\', '/'), 'files': n, 'bytes': b}


def exists_only(entries):
    """共用、仍在活用的原始檔（產生腳本、神社地圖材質）：只驗存在（不得移走／刪除），不鎖雜湊。"""
    for e in entries:
        e['lock'] = 'exists'
    return entries


def models(pattern):
    """模型本體（glb/gltf/bin）逐檔雜湊；貼圖等以目錄計數保護。"""
    out = []
    for p in sorted(glob.glob(pattern)):
        if p.endswith('.import') or os.path.isdir(p):
            continue
        out.append(fentry(p.replace('\\', '/')))
    return out


protected = [
    {'group': '龍神像', 'status': 'REWORK',
     'note': '可 REWORK／拆件／重做基座／減面／修材質；原檔不得改、不得移。REWORK 產物另存新檔（assets/village_v2/）。make_props.py＝dragon_statue.glb（與 komainu_a、stone_lantern）的原始產生腳本。',
     'files': models(G + '/maps/village/gen/龍神像/龍神像*') + models(G + '/assets/_lod/龍神像*')
              + models(G + '/assets/models/dragon_statue.glb') + exists_only(models(G + '/assets/blender/make_props.py')),
     'dirs': [dentry(G + '/maps/village/gen/龍神像')],
     'external_files': models(EXT + '/地標/龍神像.glb'),
     'external_dirs': [dentry(EXT + '/Gansokoy/village-gen/龍神像')]},
    {'group': '火見櫓', 'status': 'REFERENCE ONLY',
     'note': '現有 Tripo 模型與舊程序塔樓（tower_fire/bell/bell_p/mill，同一個 LANDMARK_TOWER 槽位的候選）全數保留；木構新版另做新檔。make_shourou.py＝tower_bell_p.glb 的原始產生腳本。',
     'files': models(G + '/assets/landmark/火見櫓*') + models(G + '/assets/_lod/火見櫓*')
              + models(G + '/assets/models/tower_*.glb') + exists_only(models(G + '/assets/blender/make_shourou.py')),
     'dirs': [],
     'external_files': models(EXT + '/地標/火見橹.glb'),
     'external_dirs': []},
    {'group': '神社：鳥居／大鳥居', 'status': '博麗鳥居 REFERENCE ONLY（參道鳥居暫用參考；額牌不清版不得定稿）／大鳥居 REFERENCE ONLY／ToriGate 未評估',
     'note': '大鳥居依 Asset Reset 由 RETIRE 改為 REFERENCE ONLY（Protected 禁止 RETIRE）。',
     'files': models(G + '/assets/shrine/博麗鳥居.glb') + models(G + '/assets/landmark/大鳥居*')
              + models(G + '/assets/lowpoly_scene/ToriGate.*'),
     'dirs': [],
     'external_files': models(EXT + '/地標/大鳥居.glb') + models(EXT + '/博麗神社/博麗鳥居.glb')
                       + models(EXT + '/場景低模素材/GLTF/ToriGate.*'),
     'external_dirs': []},
    {'group': '神社：社殿與附屬（拜殿含賽錢箱／注連繩部件、本殿、手水舍、社務所、陰陽玉、石階模組、石燈籠、狛犬）',
     'status': '拜殿 REWORK（村內待 ART_REVIEW）／本殿 REFERENCE ONLY（村內）／其餘 V2 未評估',
     'note': '賽錢箱與注連繩沒有獨立模型，只存在於 拜殿.glb 內與參考圖 docs/reference/神社/。整個 assets/shrine/ 與 D:/資產glb/博麗神社/ 目錄受保護。',
     'files': models(G + '/assets/shrine/*.glb') + models(G + '/assets/shrine/props/StoneLantern.*')
              + models(G + '/assets/_lod/平台石*') + models(G + '/assets/_lod/收頭石*')
              + models(G + '/assets/_lod/袖石垣*') + models(G + '/assets/_lod/踏石*')
              + models(G + '/assets/lowpoly_scene/StoneLantern.*')
              + models(G + '/assets/models/stone_lantern.glb') + models(G + '/assets/models/komainu_a.glb')
              + models(G + '/assets/lowpoly_scene/textures/ColorAtlas.png'),
     'dirs': [dentry(G + '/assets/shrine')],
     'external_files': models(EXT + '/場景低模素材/GLTF/StoneLantern.*'),
     'external_dirs': [dentry(EXT + '/博麗神社')]},
    {'group': '神社：專用材質（注連繩、紙垂、鳥居朱、參道石、社殿台基／石階／鋪面）',
     'status': 'REFERENCE ONLY（V2 未評估）',
     'note': '神社專用部件的材質資源（.tres）；神社／稗田邸地圖仍在用，只驗存在不鎖雜湊。引用的通用石材／木材貼圖不在此列。',
     'files': exists_only([f for pat in ('shide', 'shimenawa', 'shrine_*', '參道石', '祠木', '鳥居朱')
                           for f in models(G + '/assets/materials/' + pat + '.tres')]),
     'dirs': [],
     'external_files': [],
     'external_dirs': []},
]
# 同一檔不要在兩組重複（博麗鳥居同時符合 shrine/*.glb）
seen = set()
for g in protected:
    uniq = []
    for f in g['files']:
        if f['path'] in seen:
            continue
        seen.add(f['path'])
        uniq.append(f)
    g['files'] = uniq

# ── 實體搬移：全專案零靜態引用、零動態載入、非 Protected 的舊房屋資產
move_names = {
    'hieda_main': '舊程序稗田邸主屋（28.9×13.2×22.0 m，2.5k 面，無材質）',
    'hieda_blockout': '舊程序稗田邸整區 blockout（75.6×14.4×110.5 m，22.6k 面）',
    'unomitei': '舊程序酒館（15.1×9.5×17.5 m，1.6k 面，無材質）',
    'roofline_balcony': '舊程序町家屋簷線模組（6.35 m 段）',
    'roofline_gable': '舊程序町家屋簷線模組（6.35 m 段）',
    'roofline_store': '舊程序町家屋簷線模組（6.35 m 段）',
    'roofline_udatsu': '舊程序町家屋簷線模組（6.52 m 段）',
}
archived_moved = []
for n, what in move_names.items():
    for suffix in ('.glb', '.glb.import'):
        src = f'{G}/assets/models/{n}{suffix}'
        dst = f'{ARCH}/godot/assets/models/{n}{suffix}'
        if os.path.exists(src):
            h = sha(src)
            archived_moved.append({'from': res(src), 'to': dst[len(R) + 1:], 'sha256': h,
                                   'bytes': os.path.getsize(src), 'what': what, 'classification': 'REFERENCE ONLY'})
        elif os.path.exists(dst):  # 已搬過（重跑）
            archived_moved.append({'from': 'res://assets/models/' + n + suffix, 'to': dst[len(R) + 1:],
                                   'sha256': sha(dst), 'bytes': os.path.getsize(dst), 'what': what,
                                   'classification': 'REFERENCE ONLY'})
        else:
            raise SystemExit('缺檔：' + src)

archived_in_place = [
    {'path': 'res://assets/machiya/', 'classification': 'REFERENCE ONLY（未逐件審；依 Asset Reset 一律退出 V2）',
     'contents': '大町家、小町家1、市集商家、町家、農舍、長屋、倉庫',
     'legacy_users': ['maps/slice/slice.tscn', 'maps/village/village.tscn（倉庫：tools/gen_b1_street.gd 等舊產生器）'],
     'why_not_moved': '舊 slice／村地圖仍引用；搬走會讓舊 slice 缺建築（總計畫 §52：舊 slice 保持可玩）。'},
    {'path': 'res://maps/village/gen/鈴奈庵/', 'classification': 'REFERENCE ONLY',
     'legacy_users': ['maps/slice/slice.tscn', 'maps/village/village.tscn'],
     'why_not_moved': 'NTFS junction → D:/資產glb/Gansokoy/village-gen/鈴奈庵；舊 slice 引用。'},
    {'path': 'res://maps/village/gen/霧雨店/', 'classification': 'RETIRE',
     'legacy_users': ['maps/slice/slice.tscn', 'maps/village/village.tscn'],
     'why_not_moved': 'junction；舊 slice 引用。'},
    {'path': 'res://maps/village/gen/鯢吞亭/', 'classification': 'REFERENCE ONLY',
     'legacy_users': ['maps/slice/slice.tscn', 'maps/village/village.tscn'],
     'why_not_moved': 'junction；舊 slice 引用。'},
    {'path': 'res://maps/village/gen/寺子屋/', 'classification': 'RETIRE（減面版）',
     'legacy_users': ['maps/slice/slice.tscn', 'maps/village/village.tscn'],
     'why_not_moved': 'junction；舊 slice 引用。'},
    {'path': 'res://maps/village/gen/稗田邸/', 'classification': 'RETIRE（減面版）',
     'legacy_users': ['maps/slice/slice.tscn', 'maps/village/village.tscn'],
     'why_not_moved': 'junction；舊 slice 引用。'},
] + [
    {'path': f'res://assets/_lod/{n}.glb', 'classification': 'REFERENCE ONLY',
     'legacy_users': ['maps/slice/slice.tscn（scene_perf_cull.gd 執行期依檔名換減面模型，使用減面建築=true）'],
     'why_not_moved': '動態載入；搬走舊 slice 會退回高模。'}
    for n in ['大町家', '小町家1', '市集商家', '町家', '農舍', '長屋', '倉庫', '寺子屋', '稗田底新版', '鈴奈庵', '霧雨店', '鯢吞亭']
] + [
    {'path': 'res://assets/lowpoly_scene/House_4x5.gltf', 'classification': 'REFERENCE ONLY',
     'legacy_users': [], 'why_not_moved': '素材包內件，與共用 ColorAtlas.png 綁在一起；V2 白名單已擋。'},
]

external_reference_only = [
    {'path': EXT + '/地標/' + n, 'classification': c} for n, c in [
        ('鈴奈庵.glb', 'REFERENCE ONLY'), ('霧雨店.glb', 'RETIRE'), ('鯢吞亭.glb', 'REFERENCE ONLY'),
        ('寺子屋.glb', 'REFERENCE ONLY'), ('裨田邸.glb', 'REFERENCE ONLY'), ('後院.glb', 'RETIRE')]
] + [
    {'path': EXT + '/町家/', 'classification': 'REFERENCE ONLY（大町家、小町家1、市集商家、町家、長屋、倉庫、農舍、稗田底新版）'},
    {'path': EXT + '/Gansokoy/village-gen/{鈴奈庵,霧雨店,鯢吞亭,寺子屋,稗田邸}/', 'classification': '同 junction 那 5 件'},
]
for e in external_reference_only:
    e['why_not_moved'] = '專案外的原始素材庫（可能被其他專案共用）；原地登記，V2 gate 禁止任何 D:/資產glb 路徑。'

# ── P5 新資產登記（R1 起）：只收 gate.json 與目前 entry 雜湊一致、且每項 PASS 的資產（不合格＝不登記＝V2 維持灰盒）
GATE_KEYS = ['size', 'parcel_fit', 'grounding', 'materials', 'geometry', 'pivot_scale',
             'collision', 'lod', 'performance', 'player_screenshot', 'f5_f6']
MATLIB_KEYS = ['license', 'texture_size', 'vram_compressed', 'tres_valid']
V2A = G + '/assets/village_v2'
# 使用者親自給的 ART_APPROVED（agent 不得自行加入；每筆附日期與出處）。status 只是紀錄，產生器放不放仍只看 gate＋雜湊。
ART_APPROVED = {
    'geidontei': 'ART_APPROVED（使用者 2026-09-25，R2）',
    'kirisame': 'ART_APPROVED（使用者 2026-09-25，R2）',
    'terakoya': 'ART_APPROVED（使用者 2026-09-25，R3）',
}
v2_assets, v2_rejected = [], []
for name in sorted(os.listdir(V2A)) if os.path.isdir(V2A) else []:
    gp = f'{V2A}/{name}/gate.json'
    if not os.path.exists(gp):
        continue
    with open(gp, encoding='utf-8') as f:
        gj = json.load(f)
    entry = gj['entry']
    ep = G + '/' + entry[len('res://'):]
    lib = name == '_matlib'
    keys = MATLIB_KEYS if lib else GATE_KEYS
    checks = gj.get('checks', {})
    why = []
    if not os.path.exists(ep) or sha(ep) != gj.get('entry_sha256'):
        why.append('entry 雜湊與 gate.json 不一致（gate 之後改過，需重跑 gate）')
    why += [f'{k}={checks.get(k, {}).get("result", "缺")}' for k in keys if checks.get(k, {}).get('result') != 'PASS']
    if why:
        v2_rejected.append({'id': name, 'why': why})
        continue
    e = {'id': name, 'kind': 'material_library' if lib else None, 'path': f'res://assets/village_v2/{name}',
         'entry': entry, 'entry_sha256': gj['entry_sha256'], 'gate_json': res(gp),
         'gate': {k: checks[k]['result'] for k in keys},
         'gate_date': max(checks[k]['date'] for k in keys), 'status': ART_APPROVED.get(name, 'ART_REVIEW')}
    if not lib:
        with open(f'{V2A}/{name}/asset.json', encoding='utf-8') as f:
            aj = json.load(f)
        e.update({'kind': aj['kind'], 'label': aj['budget_class'], 'landmark': aj['landmark'],
                  'asset_json': f'res://assets/village_v2/{name}/asset.json',
                  'replaces': aj['gate_spec']['anchor'] + '/' + aj['gate_spec']['replaces'],
                  'lod0_tris': aj['measured_blender']['LOD0']})
    v2_assets.append(e)

registry = {
    'version': 'p5-r3',
    'created': '2026-09-24',
    'authority': 'P5 Asset Reset 指令（使用者 2026-09-24）＋《人間之里V2全面重製計畫》；P4 Greybox 為尺寸／位置 authority，參考圖為外觀 authority。',
    'rules': [
        'V2 場景與產生器只能引用 v2_allowed 與 v2_assets；其他一律 FAIL（預設封存所有舊資產）。',
        '新資產放 res://assets/village_v2/<名>/，但**不是**白名單前綴：必須在 v2_assets 登記、Asset Gate 11 項（尺寸、地塊、接地、材質、幾何、Pivot/Scale、碰撞、LOD、效能、玩家視角截圖、F5/F6）全 PASS 才能被 V2 引用。',
        'Protected 原檔不得覆寫：任何 REWORK／重製一律另存新資產（res://assets/village_v2/<名>/），再登記 v2_assets。',
        'protected 內檔案不得移、不得刪；模型與貼圖另鎖 sha256（位元組不得變），標 lock=exists 的共用原始檔（產生腳本、神社材質）只驗存在。可 KEEP／REWORK／REFERENCE ONLY，禁止 RETIRE。',
        '封存檔不刪除；archived_moved 在 archive/reference_old_assets/，其餘原地登記。',
        'v2_assets 由本腳本從 res://assets/village_v2/<名>/gate.json 產生：gate.json 的 entry 雜湊與目前檔案一致、每項 PASS 才登記；'
        '產生器（gen_village_v2.gd _heroes）只放登記有效且雜湊一致的資產，否則維持 P4 灰盒。status＝ART_REVIEW 直到使用者核准。',
    ],
    'v2_scene': 'res://maps/village_v2/village_v2.tscn',
    'v2_generator_sources': ['res://tools/gen_village_v2.gd', 'res://tools/village_v2_freeze.gd',
                             'res://tools/village_v2_greybox_lib.gd', 'res://tools/village_v2_parcel_lib.gd',
                             'res://tools/village_v2_terrain_lib.gd', 'res://tools/village_v2_water_lib.gd',
                             'res://tools/village_v2_hero_lib.gd', 'res://maps/village_v2/layout_v2.json'],
    'v2_allowed': {
        'prefixes': ['res://maps/village_v2/', 'res://tools/village_v2_',
                     'res://tools/gen_village_v2.gd', 'res://tools/shots/village_v2_'],
        'shared_runtime': ['res://scripts/sky_system.gd', 'res://assets/textures/skybox_jinri.png',
                           'res://assets/fonts/NotoSerifTC-VF.ttf', 'res://data/village_v2.meta.json',
                           'res://scenes/main.tscn', 'res://data/village_v2_asset_registry.json'],
    },
    'v2_assets': v2_assets,
    'v2_rejected': v2_rejected,
    'protected': protected,
    'archived_moved': archived_moved,
    'archived_in_place': archived_in_place,
    'external_reference_only': external_reference_only,
    'not_in_scope': '市集、河岸、橋、植被、自然素材等舊 kit 不在本次房屋封存範圍；V2 白名單預設不允許，分別到 P7／P9／P10 走 Asset Gate。maps/shrine/ 整張神社地圖不動。',
}

if MOVE:
    for a in archived_moved:
        src = G + '/' + a['from'][len('res://'):]
        dst = R + '/' + a['to']
        if not os.path.exists(src):
            assert os.path.exists(dst) and sha(dst) == a['sha256'], dst
            continue
        assert not os.path.exists(dst), '拒絕覆蓋：' + dst
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.move(src, dst)
        assert sha(dst) == a['sha256'] and not os.path.exists(src), dst
    with open(ARCH + '/MANIFEST.json', 'w', encoding='utf-8') as f:
        json.dump({'created': '2026-09-24', 'reason': 'P5 Asset Reset：舊人間之里房屋資產退出正式流程，只作造型／比例／屋頂結構參考。',
                   'files': archived_moved}, f, ensure_ascii=False, indent=1)

os.makedirs(G + '/data', exist_ok=True)
with open(G + '/data/village_v2_asset_registry.json', 'w', encoding='utf-8', newline='\n') as f:
    json.dump(registry, f, ensure_ascii=False, indent=1)
    f.write('\n')

pf = sum(len(g['files']) for g in protected)
pe = sum(len(g['external_files']) for g in protected)
print('protected model files (repo):', pf, ' external:', pe,
      ' protected dirs:', [(d['path'], d['files']) for g in protected for d in g['dirs'] + g['external_dirs']])
done = sum(1 for a in archived_moved if os.path.exists(R + '/' + a['to']))
print('archived_moved:', len(archived_moved), f'（已在 archive/：{done}）', '本次搬移' if MOVE else '')
print('archived_in_place:', len(archived_in_place), ' external_reference_only:', len(external_reference_only))
print('v2_assets:', [(e['id'], e['kind']) for e in v2_assets], ' 未登記:', v2_rejected)
