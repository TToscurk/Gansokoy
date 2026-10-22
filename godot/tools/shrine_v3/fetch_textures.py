"""下載博麗神社 v3 用的 Poly Haven CC0 貼圖（diff / nor_gl / rough），並寫出來源清單。
  python tools/shrine_v3/fetch_textures.py
Poly Haven 全部資產為 CC0（https://polyhaven.com/license）。只下載一次；已存在且 md5 相符就跳過。
"""
import hashlib
import json
import os
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, '..', '..'))
DST = os.path.join(GODOT, 'assets', 'shrine_v3', 'tex', 'ph')
os.makedirs(DST, exist_ok=True)

# 角色 → (Poly Haven id, 解析度)
SET = {
    'grass': ('leafy_grass', '2k'),
    'forest_floor': ('leaves_forest_ground', '2k'),
    'forest_moss': ('forest_leaves_02', '1k'),
    'dirt': ('dirt_floor', '2k'),
    'trail': ('rocky_trail', '2k'),
    'mud': ('mud_forest', '1k'),
    'cliff': ('rock_face_03', '2k'),
    'mossy_rock': ('mossy_rock', '2k'),
    'granite': ('rock_boulder_dry', '2k'),
    'stone_wall': ('mossy_stone_wall', '1k'),
    'wood_old': ('plank_flooring_03', '2k'),
    'wood_dark': ('dark_wooden_planks', '2k'),
    'wood_new': ('hinoki_planks', '1k'),
    'roof_tile': ('grey_roof_tiles', '2k'),
    'straw': ('thatch_roof_angled', '1k'),
    'bark_sakura': ('sakura_bark', '1k'),
    'bark_cedar': ('japanese_cedar_bark', '1k'),
    'bark_pine': ('pine_bark', '1k'),
    'bark_broad': ('japanese_zelkova_bark', '1k'),
}
MAPS = [('Diffuse', 'diff'), ('nor_gl', 'nor_gl'), ('Rough', 'rough')]


def get_json(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'shrine-v3-fetch/1.0'})
    return json.loads(urllib.request.urlopen(req, timeout=40).read())


def md5(p):
    h = hashlib.md5()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def main():
    manifest = {}
    for role, (pid, res) in SET.items():
        files = get_json('https://api.polyhaven.com/files/' + pid)
        info = get_json('https://api.polyhaven.com/info/' + pid)
        entry = {'id': pid, 'name': info.get('name'), 'authors': list(info.get('authors', {}).keys()),
                 'license': 'CC0 1.0', 'page': 'https://polyhaven.com/a/' + pid, 'res': res, 'files': {}}
        for key, short in MAPS:
            f = files[key][res]['jpg']
            out = os.path.join(DST, '%s_%s_%s.jpg' % (pid, short, res))
            if not (os.path.exists(out) and md5(out) == f['md5']):
                req = urllib.request.Request(f['url'], headers={'User-Agent': 'shrine-v3-fetch/1.0'})
                data = urllib.request.urlopen(req, timeout=120).read()
                open(out, 'wb').write(data)
            entry['files'][short] = os.path.basename(out)
            entry.setdefault('md5', {})[short] = f['md5']
        manifest[role] = entry
        print('[tex] %-12s %s %s' % (role, pid, res))
    json.dump(manifest, open(os.path.join(DST, 'SOURCES.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('[tex] %d 組 → %s' % (len(manifest), DST))


if __name__ == '__main__':
    main()
