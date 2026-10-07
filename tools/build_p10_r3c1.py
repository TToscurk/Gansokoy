"""R3c.1 Readability Pass thin runner (same pipeline as tools/build_p10_drink_ab.py).

Bakes only the new R3c.1 Mixamo candidates of each NPC into a separate readability_candidates.glb, so the
existing activity_candidates.glb / drink_ab_candidates.glb stay byte-identical. Reuses the sealed world-space
baker (build_npc_mixamo_anim.py) and grounding tool (build_npc_anim_grounded.gd) unchanged.
Usage: python tools/build_p10_r3c1.py
"""
from pathlib import Path
import subprocess, json, hashlib
ROOT = Path(__file__).resolve().parents[1]
G = ROOT / 'godot'
OUT = ROOT / 'docs/art_review/village_v2_p10_population/activity_r1c1/bake'
OUT.mkdir(parents=True, exist_ok=True)
BLENDER = 'D:/Blender/blender-5.2.1-windows-x64/blender.exe'
GODOT = 'D:/Godot/Godot_v4.7.2-stable_win64_console.exe'
SETS = {
    'yakusou_f01': ['sit_talk_a_a030', 'sit_talk_b_a030', 'talk_twohands_a030', 'argue_a030', 'talk_funny_a030'],
    'shufu_f01': ['talk_twohands_a030'],
    'sakanaya_m01': ['holding_walk_a038'],
    'yaoya_m01': ['box_idle_a030'],
}
import sys
ONLY = sys.argv[1:]   # optional: bake only these NPC ids (the runs.json hash list still covers every set)
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
runs = []


def run(name, cmd):
    p = subprocess.run(cmd, capture_output=True)
    (OUT / f'{name}.log').write_bytes(p.stdout + p.stderr)
    runs.append({'name': name, 'command': cmd, 'exit': p.returncode})
    if p.returncode:
        (OUT / 'runs.json').write_text(json.dumps(runs, ensure_ascii=False, indent=2), encoding='utf-8')
        raise SystemExit(f'{name} failed {p.returncode}')


for cid, clips in SETS.items():
    if ONLY and cid not in ONLY:
        continue
    folder = G / f'animations/npc_activity_p10/{cid}'
    srcs = [folder / 'src' / f'{c}.fbx' for c in clips]
    glb = folder / 'readability_candidates.glb'
    target = G / f'characters/npc/{cid}/{cid}.glb'
    run(f'bake_{cid}', [BLENDER, '-b', '-P', str(G / 'assets/blender/npc/build_npc_mixamo_anim.py'), '--', str(target), str(glb)] + [f'{p.stem}={p}' for p in srcs])
    old = (G / f'characters/npc/{cid}/anim/{cid}_anim.glb.import').read_text()
    nodes = old[old.index('"nodes": {'):old.index('\ngltf/naming_version=')].strip()
    sub = '"animations": {\n' + ',\n'.join('"' + c + '": {"save_to_file/enabled": true, "save_to_file/path": "res://animations/npc_activity_p10/' + cid + '/' + c + '.res", "save_to_file/keep_custom_tracks": false, "settings/loop_mode": 1}' for c in clips) + '\n},\n' + nodes
    imp = '[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[deps]\nsource_file="res://animations/npc_activity_p10/' + cid + '/readability_candidates.glb"\n\n[params]\nnodes/root_scale=1.0\nnodes/apply_root_scale=true\nanimation/import=true\nanimation/fps=30\nanimation/remove_immutable_tracks=true\nskins/use_named_skins=true\n_subresources={\n' + sub + '\ngltf/naming_version=2\n'
    Path(str(glb) + '.import').write_text(imp)
run('import', [GODOT, '--headless', '--path', str(G), '--import'])
for cid, clips in SETS.items():
    if ONLY and cid not in ONLY:
        continue
    run(f'ground_{cid}', [GODOT, '--headless', '--path', str(G), '--script', 'res://tools/build_npc_anim_grounded.gd', '--',
                          f'--dir=res://animations/npc_activity_p10/{cid}', f'--npc=res://characters/npc/{cid}/{cid}.glb', '--clips=' + ','.join(clips)])
files = []
for cid, clips in SETS.items():
    folder = G / f'animations/npc_activity_p10/{cid}'
    files += [folder / 'readability_candidates.glb'] + [folder / 'src' / f'{c}.fbx' for c in clips] + [folder / f'{c}_grounded.res' for c in clips]
(OUT / 'runs.json').write_text(json.dumps({'runs': runs, 'sha256': {f.relative_to(ROOT).as_posix(): sha(f) for f in files}}, ensure_ascii=False, indent=2), encoding='utf-8')
print('R3c.1 BAKE PASS', {k: len(v) for k, v in SETS.items()})
