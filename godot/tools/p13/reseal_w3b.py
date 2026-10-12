# P13 W3B limited reseal：本輪で使用者が授權した変更だけを封存へ反映する（他 session の差分は背書しない）。
#   使用者 2026-10-12「P13 WAVE 3B — FINAL CANAL ART INTEGRATION」：N0／T0 支線の土渠に W3 樣本の材質権重と泥水を正式整合、
#   farmland_p8.scn を 1 回正式に重烘、P8 limited reseal、木槽と土渠の接合・槽下の隙間の最小修正、CanalSampleP13 を除去。
#   ALLOW＝本輪の実変更だけ。それ以外の frozen 不一致が 1 件でもあれば中止（他 session・他 phase の差分を背書しない）。
#   child_seals は ALLOW から派生した seal ファイルの雜湊だけ追従（反復）。
# 実行：cd godot && python tools/p13/reseal_w3b.py [--dry]
import json, glob, hashlib, os, sys

AT = '2026-10-12'
DRY = '--dry' in sys.argv
AUTH = '使用者 2026-10-12「P13 WAVE 3B — FINAL CANAL ART INTEGRATION」：N0／T0 灌漑支線の土渠に W3 樣本の材質権重（渠底濡れ泥→内坡泥土→堤頂踏実土→外坡草）と泥水面を正式整合；farmland_p8.scn を 1 回正式重烘；P8 limited reseal；木槽と土渠の接合・槽下の暗縫の最小修正；CanalSampleP13 除去。水面高程・坡降・伏越し・道路・主要碰撞は不変。'
ALLOW = {
    # P8 封存（キー＝godot/ からの相対）
    'tools/village_v2_farmland_zone.gd':
        'branch_art：土渠の頂点ごとの地面重み（branch_bank_weights）・collar 先端の草への漸減・支線専用の泥水材質（branch_water_mat）・木槽の台（trough_bed）・木槽の口で水幅を槽内へ絞る（water_neck）',
    'tools/village_v2_farmland_visual.gd':
        '_ribbon に任意引数 wfn（頂点ごとの地面重み）・ucols（横断の列位置）・hscale（半幅の倍率）を追加。未指定の ribbon は従来と bit 同一',
    'maps/village_v2/gen/farmland_p8.scn':
        'P8 を 1 回正式に重烘（非 headless）。変更は Branches 配下の 土渠メッシュ（頂点色／UV2＋木槽の台）と 水面メッシュ（材質・木槽の口の幅）だけ。他ノードは逐ノード等価',
    # P9 R5-4 封存：ENV の P12_MEADOW_DRIFT が束縛する上游 farmland_p8.scn の雜湊（計画摘要・株数は不変であることを確認した上で更新）
    'godot/tools/verify_village_v2_environment.gd':
        'P12_MEADOW_DRIFT.upstream の farmland_p8.scn 雜湊を新しい P8 に更新（同 seed の MeadowP9 規劃の株数 114574・株位摘要 5d9ef17a… は不変＝避障入力の幾何は変わっていない）',
}
EV = 'docs/art_review/village_v2_p13/wave3b/evidence/'
EXTRA = {   # seal ファイル -> 追加の履歴フィールド
    'data/village_v2_p8_seal.json': {
        'scope': 'farmland_p8.scn の ZoneWorks/ZoneIrrigation/Branches 配下だけ（N0／T0 支線）：土渠メッシュ（頂点色 COLOR／UV2＝地面重み、T0 は木槽の台 Bed_* を追加）と水面メッシュ（材質＝泥水・T0 は木槽の口で水幅を絞る）。'
                 '田・田埂・取水（竜骨車）・水渠・主河・他の渠／溝／桝・碰撞・MultiMesh は一切触れない。',
        'measurements': {
            'nodes': '8817 → 8817、逐ノード一致 8813（MultiMesh 1844 の buffer 含む）、差分 4＝Branch_N0/Merged_0・Merged_1 と Branch_T0/Merged_1・Merged_2 のみ（期待どおり）、old のみ 0・new のみ 0',
            'earth_triangles': 'N0 1764 → 1764（位置同一、頂点色／UV2 のみ変更）／T0 2184 → 3764（失われた三角形 0、増えた 1580＝木槽の台）',
            'water_vertices': 'N0 1050 同一／T0 1488 index 同一、x/z が動いた頂点 120（最大 0.126 m＝木槽の口の絞り）、y の最大差 0.29 mm（水面高程は不変）',
            'file_bytes': '55,392,676 → 55,426,679',
            'trough_gap_before': '槽底の下面〜可見地面 3.3–21.6 cm（T0 木槽 3 本：6.1–21.6／3.3–6.8／3.3–15.3 cm、terrain_gap_probe.log）、可見地形と碰撞用 ground_h の差は最大 12 mm',
            'trough_gap_after': '槽底の下面〜台の頂 4–20 mm（実測最大 14 mm）、槽内（±0.12）の土は槽底の上面より 4.5 cm 以上下、板の外面で台は側板の下端以上',
            'pixels_same_camera': '土渠の平均輝度／周囲地面：T0 下流 0.77→0.84、N0 0.82→0.87、農田高視角 0.72→0.86；最暗 5 % 点 T0 下流 0.115→0.232；水面 >0.80 の画素率（8 方位×2 高さ・最悪 view）T0 4.59 %→0.73 %、N0 1.75 %→0.26 %',
        },
        'dependencies': {
            'updated': ['tools/village_v2_farmland_zone.gd', 'tools/village_v2_farmland_visual.gd', 'maps/village_v2/gen/farmland_p8.scn'],
            'unchanged_frozen': ['tools/village_v2_farmland_lib.gd', 'maps/village_v2/shaders/p8_paddy_water.gdshader', 'maps/village_v2/shaders/p8_paddy_plant.gdshader', 'data/village_v2_p8_blocks.json', 'data/village_v2_p8_ground.json'],
            'downstream_updated': ['tools/verify_village_v2_environment.gd（P12_MEADOW_DRIFT.upstream の farmland_p8.scn 雜湊のみ。同 seed の MeadowP9 規劃 114574 株・株位摘要 5d9ef17a… は不変を確認）'],
            'removed': ['village_v2.tscn の CanalSampleP13（ext_resource＋node）・scripts_p13/canal_sample.gd・tools/village_v2_canal_sample_lib.gd（外観の出所を 1 つに）'],
            'added': ['tools/verify_village_v2_canal_art.gd（CANAL gate＋永久反向 5 案）・run_village_v2_regression.sh に 2 行'],
        },
        'negatives': ['CANAL --negatives：uniform／gap／poke／wide／mat が各自の狙った項だけ FAIL（巻き込み 0）', 'CANAL を旧 farmland_p8.scn に実行 → C1／C3／C4a／C4c／C5 が FAIL', 'P8 --seal の永久反向：verify_village_v2_farmland.gd が記憶體で期待雜湊を 1 件竄改 → 1 件不符を検出（seals_after_reseal.log）'],
        'art_status_of_change': 'ART_REVIEW（W3 樣本の方向は使用者が 2026-10-12 に承認済み；N0／T0 正式整合の見た目は使用者の驗收待ち）。P8 本体の ART_APPROVED 2026-10-01 は変更なし',
        'evidence': [EV + n for n in ['p8_build.log', 'p8_equivalence.log', 'p8_gate_and_negatives.log', 'canal_gate.log', 'canal_gate_negatives.log', 'canal_gate_on_old_scene.log', 'pixel_stats_before_after.txt', 'glare_stats_before_after.txt', 'dark_gap_before_after.txt', 'farm_place.log',
                                    'terrain_gap_probe.log', 'branch_composition.log', 'bed_neighbors_probe.log', 'feeder.log', 'feeder_negative.log', 'branch_walk.log', 'mmbake.log', 'seals_after_reseal.log']],
    },
    'data/village_v2_p9r54_seal.json': {
        'plan_unchanged': {'meadow_count': 114574, 'meadow_digest': '5d9ef17a69aa96c6cf46628c40546912a771449e0c9400bd7879bd1d553cc53b', 'sealed_near': 114105,
                           'note': 'P8 再烘焙後も同 seed 再計算の株数・株位摘要が登記どおり（env_plan_before_hash_update.log：失敗の理由は upstream farmland_p8.scn の雜湊だけ）'},
        'evidence': [EV + 'env_plan_before_hash_update.log', EV + 'env_plan_after_hash_update.log'],
    },
}


def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


def path_of(k):
    return k if os.path.exists(k) else '../' + k


def write(f, d):
    raw = open(f, encoding='utf-8').read()
    ind = 1 if raw.startswith('{\n "') or raw.startswith('{\r\n "') else 2
    open(f, 'w', encoding='utf-8', newline='\n').write(json.dumps(d, ensure_ascii=False, indent=ind) + '\n')


files = sorted(x.replace(chr(92), '/') for x in glob.glob('data/village_v2_*seal.json'))
# 1) frozen：ALLOW 以外の不一致があれば中止
stray = []
for f in files:
    s = json.load(open(f, encoding='utf-8'))
    for k, h in s.get('frozen', {}).items():
        p = path_of(k)
        if os.path.exists(p) and sha(p) != h and k not in ALLOW:
            stray.append((f, k))
if stray:
    print('中止：本輪外の frozen 不一致', stray)
    sys.exit(1)
changed_seals = set()
for f in files:
    s = json.load(open(f, encoding='utf-8'))
    upd = {k: [h, sha(path_of(k))] for k, h in s.get('frozen', {}).items() if k in ALLOW and sha(path_of(k)) != h}
    if not upd:
        continue
    b = sha(f)
    for k, (a, n) in upd.items():
        s['frozen'][k] = n
    entry = {'kind': 'P13_W3B_LIMITED', 'date': AT, 'changed': {k: {'old': a, 'new': n} for k, (a, n) in upd.items()}, 'seal_file_before': b,
             'authorized_by': 'user', 'authorization': AUTH, 'reason': ' ／ '.join('%s：%s' % (k.split('/')[-1], ALLOW[k]) for k in upd)}
    entry.update(EXTRA.get(f, {}))
    s.setdefault('reseal_history', []).append(entry)
    print('frozen', f, list(upd))
    if not DRY:
        write(f, s)
    changed_seals.add('godot/' + f)
# 2) child_seals／sub_seals：変更した seal から派生するものだけ追従（反復）。同じ seal の履歴は 1 件に統合する
child_entry = set()
for it in range(12):
    moved = False
    for f in files:
        s = json.load(open(f, encoding='utf-8'))
        cs = s.get('child_seals', {})
        upd = {k: [h, sha(path_of(k))] for k, h in cs.items() if k in changed_seals and sha(path_of(k)) != h}
        subs = {n: e for n, e in s.get('sub_seals', {}).items() if isinstance(e, dict) and e.get('file') in changed_seals and sha(path_of(e['file'])) != e.get('sha256')}
        if not upd and not subs:
            continue
        b = sha(f)
        for k, (a, n) in upd.items():
            cs[k] = n
        for n, e in subs.items():
            upd[e['file']] = [e['sha256'], sha(path_of(e['file']))]
            e['sha256'] = upd[e['file']][1]
        hist = s.setdefault('reseal_history', [])
        if f in child_entry and hist and hist[-1].get('kind') == 'P13_W3B_CHILD_UPDATE':
            ce = hist[-1]['child_seals']
            for k, (a, n) in upd.items():
                ce[k] = [ce[k][0], n] if k in ce else [a, n]
        else:
            hist.append({'kind': 'P13_W3B_CHILD_UPDATE', 'at': AT, 'child_seals': upd, 'seal_file_before': b,
                         'approved_by': 'user（P13 WAVE 3B）', 'reason': 'P13 W3B：子封存の雜湊だけ追従、本封存の内容は不変。'})
            child_entry.add(f)
        print('cascade', it, f, [k.split('/')[-1] for k in upd])
        if not DRY:
            write(f, s)
        changed_seals.add('godot/' + f)
        moved = True
    if not moved:
        break
bad = 0
for f in files:
    s = json.load(open(f, encoding='utf-8'))
    for g in ('frozen', 'child_seals'):
        for k, h in s.get(g, {}).items():
            p = path_of(k)
            if os.path.exists(p) and sha(p) != h:
                print('MISMATCH', f, g, k)
                bad += 1
print('seal mismatch', bad, '（dry）' if DRY else '')
