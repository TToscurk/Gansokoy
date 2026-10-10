# P11 R2B limited reseal: R3b/R3c frozen hash of the two NPC behaviour scripts + child_seals cascade.
# Run from godot/:  python tools/p11r2b/reseal_npc_behavior.py
import json, glob, hashlib, os

def sha(p):
    return hashlib.sha256(open('../' + p, 'rb').read()).hexdigest()

REASON = {
    'godot/scripts/npc_population_actor.gd': 'P11 R2B TASK04（使用者 2026-10-11 指示）：巡回の折返を最短弧に（rotate_toward が ±π を跨ぐと最大ほぼ 1 周回る）、振り向き中は walk clip で足踏み。人數・位置・朝向・path・mode・速度は不変。',
    'godot/tools/verify_village_v2_population_core.gd': 'P11 R2B TASK03：Drink を時々の動作にしたため、Idle 中の杯の非表示を許可（飲む間の非表示は従来どおり違反）。limited verifier correction、判定の緩和は Idle 相のみ。',
    'godot/scripts/npc_activity_overlay.gd': 'P11 R2B TASK03（使用者 2026-10-11 指示）：Drink が idle slot に入り永久に飲み続けていた → 基線 Idle を既定、25–45 秒に 1 回だけ承認済み drink clip を再生、杯は飲む間だけ表示。clip・握持・割り当ては不変。',
}
files = sorted(f.replace(chr(92), '/') for f in glob.glob('data/village_v2_*seal.json'))
seals = {f: json.load(open(f, encoding='utf-8')) for f in files}

def write(f):
    raw = open(f, encoding='utf-8').read()
    ind = 1 if raw.startswith('{\n "') else 2
    open(f, 'w', encoding='utf-8', newline='\n').write(json.dumps(seals[f], ensure_ascii=False, indent=ind) + '\n')

for f, d in seals.items():
    fr = d.get('frozen', {})
    upd = {k: [h, sha(k)] for k, h in fr.items() if k in REASON and sha(k) != h}
    if upd:
        before = hashlib.sha256(open(f, 'rb').read()).hexdigest()
        for k, (a, b) in upd.items():
            fr[k] = b
        d.setdefault('reseal_history', []).append({
            'kind': 'P11_R2B_LIMITED_NPC_BEHAVIOR_FIX', 'at': '2026-10-11', 'frozen': upd,
            'seal_file_before': before, 'approved_by': 'user（P11 R2B 指示 §6 limited reseal）',
            'reason': ' '.join(REASON[k] for k in upd)})
        write(f)
        print('frozen reseal', f, list(upd))

for it in range(10):
    moved = False
    for f, d in seals.items():
        cs = d.get('child_seals', {})
        upd = {k: [h, sha(k)] for k, h in cs.items()
               if k.startswith('godot/data/village_v2_p10') and os.path.exists('../' + k) and sha(k) != h}
        if upd:
            before = hashlib.sha256(open(f, 'rb').read()).hexdigest()
            for k, (a, b) in upd.items():
                cs[k] = b
            d.setdefault('reseal_history', []).append({
                'kind': 'P11_R2B_CHILD_NPC_CASCADE', 'at': '2026-10-11', 'child_seals': upd,
                'seal_file_before': before, 'approved_by': 'user（P11 R2B 指示 §6）',
                'reason': 'P11 R2B：子封存（R3b／R3c の NPC 挙動 limited reseal）の雜湊だけ追従、本封存の内容は不変。'})
            write(f)
            print('cascade', it, f, list(upd))
            moved = True
    if not moved:
        break
