"""R3c W3 Drink A/B thin runner.

Bakes only the two new Mixamo drink candidates for chaya_f01 into a separate
GLB so the existing activity_candidates.glb / drinking_a030 (candidate A) stays
byte-identical. Reuses the sealed world-space baker and grounding tool unchanged.
"""
from pathlib import Path
import subprocess, json, hashlib
ROOT = Path(__file__).resolve().parents[1]
G = ROOT / 'godot'
OUT = ROOT / 'docs/art_review/village_v2_p10_population/activity_r1/drink_ab'
OUT.mkdir(parents=True, exist_ok=True)
BLENDER = 'D:/Blender/blender-5.2.1-windows-x64/blender.exe'
GODOT = 'D:/Godot/Godot_v4.7.2-stable_win64_console.exe'
CID = 'chaya_f01'
CLIPS = ['drinking_im1_a030', 'watercooler_a030']
folder = G / f'animations/npc_activity_p10/{CID}'
srcs = [folder / 'src' / f'{c}.fbx' for c in CLIPS]
glb = folder / 'drink_ab_candidates.glb'
target = G / f'characters/npc/{CID}/{CID}.glb'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
runs = []

def run(name, cmd):
    p = subprocess.run(cmd, capture_output=True)
    (OUT / f'{name}.log').write_bytes(p.stdout + p.stderr)
    runs.append({'name': name, 'command': cmd, 'exit': p.returncode})
    if p.returncode:
        (OUT / 'drink_ab_runs.json').write_text(json.dumps(runs, ensure_ascii=False, indent=2), encoding='utf-8')
        raise SystemExit(f'{name} failed {p.returncode}')

run('bake', [BLENDER, '-b', '-P', str(G / 'assets/blender/npc/build_npc_mixamo_anim.py'), '--', str(target), str(glb)] + [f'{p.stem}={p}' for p in srcs])
old = (G / f'characters/npc/{CID}/anim/{CID}_anim.glb.import').read_text()
nodes = old[old.index('"nodes": {'):old.index('\ngltf/naming_version=')].strip()
sub = '"animations": {\n' + ',\n'.join('"' + c + '": {"save_to_file/enabled": true, "save_to_file/path": "res://animations/npc_activity_p10/' + CID + '/' + c + '.res", "save_to_file/keep_custom_tracks": false, "settings/loop_mode": 1}' for c in CLIPS) + '\n},\n' + nodes
imp = '[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[deps]\nsource_file="res://animations/npc_activity_p10/' + CID + '/drink_ab_candidates.glb"\n\n[params]\nnodes/root_scale=1.0\nnodes/apply_root_scale=true\nanimation/import=true\nanimation/fps=30\nanimation/remove_immutable_tracks=true\nskins/use_named_skins=true\n_subresources={\n' + sub + '\ngltf/naming_version=2\n'
Path(str(glb) + '.import').write_text(imp)
run('import', [GODOT, '--headless', '--path', str(G), '--import'])
run('ground', [GODOT, '--headless', '--path', str(G), '--script', 'res://tools/build_npc_anim_grounded.gd', '--',
               f'--dir=res://animations/npc_activity_p10/{CID}', f'--npc=res://characters/npc/{CID}/{CID}.glb', '--clips=' + ','.join(CLIPS)])
files = sorted(folder.glob('*.res')) + [folder / 'activity_candidates.glb', glb] + srcs + [folder / 'src/drinking_a030.fbx']
summary = {'runs': runs, 'sha256': {str(f.relative_to(ROOT)).replace('\\', '/'): sha(f) for f in files}}
(OUT / 'drink_ab_runs.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
print('DRINK AB BAKE PASS', CLIPS)
