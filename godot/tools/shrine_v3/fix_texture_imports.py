"""把 assets/shrine_v3/tex 底下所有貼圖的 .import 設成 3D 用設定（VRAM 壓縮＋mipmap；*_nor_gl → 法線圖 RGTC）。
headless 腳本不會觸發編輯器的「用在 3D 才自動轉 VRAM」偵測（預設 Lossless、無 mipmap → 遠處閃爍），所以要自己寫。
  python tools/shrine_v3/fix_texture_imports.py   然後   godot --headless --path godot --import
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', 'assets', 'shrine_v3'))


def patch(path):
    s = open(path, encoding='utf-8').read()
    orig = s
    base = os.path.basename(path)
    is_nrm = '_nor_gl' in base or '_normal' in base or base.endswith('_n.png.import')
    rep = {
        'compress/mode': '2',
        'mipmaps/generate': 'true',
        'detect_3d/compress_to': '0',
        'compress/normal_map': '1' if is_nrm else '2',
        'compress/high_quality': 'false',
    }
    for k, v in rep.items():
        s2, n = re.subn(r'^%s=.*$' % re.escape(k), '%s=%s' % (k, v), s, flags=re.M)
        if n == 0:
            s2 = s.replace('[params]\n', '[params]\n\n%s=%s\n' % (k, v), 1)
        s = s2
    if s != orig:
        open(path, 'w', encoding='utf-8', newline='\n').write(s)
        return True
    return False


def main():
    n = 0
    tot = 0
    for dp, _, fs in os.walk(ROOT):
        for f in fs:
            if f.endswith(('.jpg.import', '.png.import')):
                tot += 1
                if patch(os.path.join(dp, f)):
                    n += 1
    print('[imports] %d / %d 個 .import 已改' % (n, tot))
    # 植被 GLB：不要自動 LOD（葉卡經網格簡化會變形）
    vdir = os.path.join(ROOT, 'models', 'veg')
    k = 0
    if os.path.isdir(vdir):
        for f in os.listdir(vdir):
            if f.endswith('.glb.import'):
                p = os.path.join(vdir, f)
                s = open(p, encoding='utf-8').read()
                s2 = re.sub(r'^meshes/generate_lods=.*$', 'meshes/generate_lods=false', s, flags=re.M)
                if s2 != s:
                    open(p, 'w', encoding='utf-8', newline='\n').write(s2)
                    k += 1
    print('[imports] 植被 GLB 關閉自動 LOD：%d 個' % k)


if __name__ == '__main__':
    main()
