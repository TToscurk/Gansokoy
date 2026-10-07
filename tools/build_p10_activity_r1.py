"""R3c thin runner; reuse sealed world-space baker unchanged."""
from pathlib import Path
import subprocess, re, json, hashlib
ROOT=Path(__file__).resolve().parents[1]
G=ROOT/'godot'
OUT=ROOT/'docs/art_review/village_v2_p10_population/activity_r1'
OUT.mkdir(parents=True,exist_ok=True)
BLENDER='D:/Blender/blender-5.2.1-windows-x64/blender.exe'
GODOT='D:/Godot/Godot_v4.7.2-stable_win64_console.exe'
runs=[]
for folder in sorted((G/'animations/npc_activity_p10').iterdir()):
    if not (folder/'src').is_dir(): continue
    cid=folder.name
    clips=sorted((folder/'src').glob('*.fbx'))
    target=G/f'characters/npc/{cid}/{cid}.glb'
    glb=folder/'activity_candidates.glb'
    cmd=[BLENDER,'-b','-P',str(G/'assets/blender/npc/build_npc_mixamo_anim.py'),'--',str(target),str(glb)]+[f'{p.stem}={p}' for p in clips]
    p=subprocess.run(cmd,capture_output=True)
    (OUT/f'bake_{cid}.log').write_bytes(p.stdout+p.stderr)
    runs.append({'cid':cid,'exit':p.returncode,'command':cmd,'sources':[{'path':str(q.relative_to(ROOT)),'sha256':hashlib.sha256(q.read_bytes()).hexdigest()} for q in clips]})
    if p.returncode: raise SystemExit(p.returncode)
    old=(G/f'characters/npc/{cid}/anim/{cid}_anim.glb.import').read_text()
    nodes=old[old.index('"nodes": {'):old.index('\ngltf/naming_version=')].strip()
    sub='"animations": {\n'+',\n'.join('"'+q.stem+'": {"save_to_file/enabled": true, "save_to_file/path": "res://animations/npc_activity_p10/'+cid+'/'+q.stem+'.res", "save_to_file/keep_custom_tracks": false, "settings/loop_mode": 1}' for q in clips)+'\n},\n'+nodes
    imp='[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[deps]\nsource_file="res://animations/npc_activity_p10/'+cid+'/activity_candidates.glb"\n\n[params]\nnodes/root_scale=1.0\nnodes/apply_root_scale=true\nanimation/import=true\nanimation/fps=30\nanimation/remove_immutable_tracks=true\nskins/use_named_skins=true\n_subresources={\n'+sub+'\ngltf/naming_version=2\n'
    Path(str(glb)+'.import').write_text(imp)
(OUT/'bake_runs.json').write_text(json.dumps(runs,ensure_ascii=False,indent=2))
print('BAKE PASS',len(runs),'characters',sum(len(r['sources']) for r in runs),'clips')
