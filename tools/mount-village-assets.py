"""Restore HEAD village asset folders outside the repo; mount via NTFS junctions.
Dry-run by default. --apply never overwrites existing files or nonempty folders.
Does not stage, commit, or touch Blender sources. Requires local Git/LFS objects.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GODOT = ROOT / 'godot'
EXTERNAL = Path('D:/資產glb/Gansokoy/village-gen')

def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])

def source_data(path):
    data = git('show', 'HEAD:' + path)
    if data.startswith(b'version https://git-lfs.github.com/spec/v1'):
        oid = re.search(rb'oid sha256:([0-9a-f]{64})', data)[1].decode()
        obj = ROOT / '.git/lfs/objects' / oid[:2] / oid[2:4] / oid
        if not obj.is_file():
            raise RuntimeError('Missing local LFS object: ' + path + ' ' + oid)
        data = obj.read_bytes()
        if hashlib.sha256(data).hexdigest() != oid:
            raise RuntimeError('LFS hash mismatch: ' + path)
    return data

def main():
    apply = argparse.ArgumentParser()
    apply.add_argument('--apply', action='store_true')
    args = apply.parse_args()
    scene = (GODOT / 'maps/slice/slice.tscn').read_text(encoding='utf-8')
    refs = sorted(set(re.findall(r'path="(res://maps/village/gen/[^\"]+\.glb)"', scene)))
    folders = sorted(set(str(Path(p[6:]).parent).replace('\\', '/') for p in refs))
    tracked = git('ls-tree', '-r', '--name-only', '-z', 'HEAD', '--', *['godot/' + p for p in folders]).decode().split('\0')
    jobs = []
    for path in filter(None, tracked):
        relative = Path(path).relative_to('godot/maps/village/gen')
        target = EXTERNAL / relative
        data = source_data(path)
        digest = hashlib.sha256(data).hexdigest()
        if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() != digest:
            raise RuntimeError('External target differs; refusing overwrite: ' + str(target))
        jobs.append((target, data, digest))
    for folder in folders:
        local = GODOT / folder
        if local.exists() and any(local.iterdir()):
            raise RuntimeError('Local folder not empty: ' + str(local))
    interaction = GODOT / 'maps/slice/slice_interactions.tscn'
    interaction_data = None if interaction.exists() else source_data('godot/maps/slice/slice_interactions.tscn')
    print(json.dumps({'files': len(jobs), 'bytes': sum(len(d) for _, d, _ in jobs), 'folders': folders,
                      'restore_interaction': interaction_data is not None, 'apply': args.apply}, ensure_ascii=False, indent=2))
    if not args.apply:
        return
    for target, data, digest in jobs:
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            target.write_bytes(data)
        assert hashlib.sha256(target.read_bytes()).hexdigest() == digest
    for folder in folders:
        local = GODOT / folder
        target = EXTERNAL / Path(folder).relative_to('maps/village/gen')
        if local.exists():
            local.rmdir()  # Only empty dirs; nonempty is rejected above.
        local.parent.mkdir(parents=True, exist_ok=True)
        proc = subprocess.run(['cmd.exe', '/d', '/c', 'mklink', '/J', str(local), str(target)], capture_output=True)
        if proc.returncode:
            raise RuntimeError(repr(proc.stdout + proc.stderr))
        assert local.is_dir() and os.path.samefile(local, target)
    if interaction_data is not None:
        interaction.write_bytes(interaction_data)
        assert interaction.read_bytes() == interaction_data
    manifest = {'source_revision': git('rev-parse', 'HEAD').decode().strip(),
                'external_root': str(EXTERNAL), 'junctions': folders,
                'files': [{'path': str(p.relative_to(EXTERNAL)), 'sha256': h, 'bytes': len(d)} for p, d, h in jobs]}
    (EXTERNAL / 'mount-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print('VERIFIED: external bytes and junction targets; no git index changes.')

if __name__ == '__main__':
    main()
