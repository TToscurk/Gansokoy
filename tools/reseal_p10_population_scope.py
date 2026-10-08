"""P10 R3d／R3e limited reseal：scope-aware 人數驗證（2026-10-08 使用者承認）。

使用者裁定（2026-10-08）：「R3d 的人數檢查確實是驗證器設計錯誤，應該現在修正」——
  R3d Core＝39・R3e Outer＝12・最終村莊人口＝51；R3d 單獨載入時仍必須能驗證 39 人；
  核心驗證應檢查自己的 39 個 identity，不能拿整張場景的 NPC 總數判斷。
變更：verify_village_v2_population_core.gd／_outer.gd の scene「人數」項を scope 別の身元検査へ（共用 tools/village_v2_population_scope.gd）、
  反向（多一人・少一人・身元重複）と R3d 単獨（R3e の層を外す）を追加。NPC 配置・snapshot・生成器・場景は不変。
本スクリプト：R3d seal の凍結雜湊（verifier＋scope helper）・證據（scene log）を更新し reseal_history に前後の雜湊を記録 →
  R3e seal も同様に更新し、child_seals の R3d seal 雜湊を差し替える。
Usage: python tools/reseal_p10_population_scope.py
"""
import hashlib
import json
import os

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(R)
G = 'godot/'


def sha(f):
    return hashlib.sha256(open(f, 'rb').read()).hexdigest()


def load(f):
    return json.load(open(f, encoding='utf-8'))


def save(f, d):
    open(f, 'wb').write((json.dumps(d, ensure_ascii=False, indent=1) + '\n').encode('utf-8'))


PRE = {  # 修正前（2026-10-08 編集前に記録）
    G + 'tools/verify_village_v2_population_core.gd': '045fd6876aed79759204e364887a616a7ec7d4f19928520bcadcffae566478b2',
    G + 'tools/verify_village_v2_population_outer.gd': '8900a3ad5ee45a22175b87d218a967308bd3747c87cc998d00d6fc6c9f6df136',
    G + 'data/village_v2_p10r3d_seal.json': '6261de507438865bd89aac586a60b3262a6989e90663472e39ab1feb4a69c88a',
    G + 'data/village_v2_p10r3e_seal.json': '2d9613bb201dd31d0ba43db3132b106ad01797cb55f297e008bc0992ecfb1334',
}
SCOPE = G + 'tools/village_v2_population_scope.gd'
APPROVAL = ('使用者 2026-10-08：「R3d 的人數檢查確實是驗證器設計錯誤，應該現在修正，不必留到 P12。」'
            '「R3d Core 39・R3e Outer 12・最終村莊人口 51」「R3d 單獨載入時仍必須能驗證 39 人」「核心驗證應檢查自己的 39 個 identity、位置與配置，不能拿整張場景的 NPC 總數來判斷」')


def reseal(seal_path, verifier, evidence, extra_child=None):
    assert sha(seal_path) == PRE[seal_path], seal_path + ' が想定外に変わっている（先に確認）'
    j = load(seal_path)
    before = {verifier: j['frozen'][verifier]}
    assert before[verifier] == PRE[verifier], verifier
    j['frozen'][verifier] = sha(verifier)
    j['frozen'][SCOPE] = sha(SCOPE)
    for e in evidence:
        j['evidence'][e] = sha(e)
    child_before = {}
    if extra_child:
        for k, v in extra_child.items():
            child_before[k] = j['child_seals'][k]
            j['child_seals'][k] = v
    hist = j.setdefault('reseal_history', [])
    hist.append({
        'at': '2026-10-08', 'kind': 'SCOPE_AWARE_COUNT_FIX', 'approved_by': 'user', 'approval_source': APPROVAL,
        'reason': 'scene gate の「人數」が Population 全体の NPC 總數（R3d＝16＋23、R3e＝39＋12）で判定していた：R3e 外圍の掛載で R3d が FAIL（R3e 封存時は --seal のみ実行で未検出）。'
                  'scope 別の身元検査へ：R3d＝R3b PopulationP10＋R3d CoreP10 の snapshot 身元 39、R3e＝OuterP10 の snapshot 身元 12＋最終村人口 51（Population 全体の身元＝両 snapshot の和、scope 外・重複なし）。',
        'checks_added': ['count（scope 別の身元：人数・欠け・余分・重複・model）', 'count_neg（記憶體内：多一人／少一人／身元重複〔人数そのまま〕）']
                        + (['count_alone（R3e の層を外した R3d 単獨でも 39）'] if 'core' in verifier else []),
        'unchanged': 'NPC 配置・snapshot・生成器・overlay 場景・Activity・審圖・他の gate 項目',
        'files': {verifier: [before[verifier], j['frozen'][verifier]], SCOPE: [None, j['frozen'][SCOPE]]},
        'child_seals': {k: [child_before[k], v] for k, v in (extra_child or {}).items()},
        'evidence_added': {e: sha(e) for e in evidence},
        'seal_file_before': PRE[seal_path],
    })
    save(seal_path, j)
    return sha(seal_path)


d_seal = G + 'data/village_v2_p10r3d_seal.json'
e_seal = G + 'data/village_v2_p10r3e_seal.json'
d_new = reseal(d_seal, G + 'tools/verify_village_v2_population_core.gd',
               ['docs/art_review/village_v2_p10_population/core_r1/gate/scene_scope_fix_20261008.log'])
e_new = reseal(e_seal, G + 'tools/verify_village_v2_population_outer.gd',
               ['docs/art_review/village_v2_p10_population/outer_r1/gate/scene_scope_fix_20261008.log'],
               extra_child={d_seal: d_new})
print('R3d seal', PRE[d_seal][:12], '→', d_new[:12])
print('R3e seal', PRE[e_seal][:12], '→', e_new[:12])
