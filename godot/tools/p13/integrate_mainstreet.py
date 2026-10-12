# P13 W2：village_v2.tscn の主街 39 棟の Kit（と住居化 3 棟の Frontage）を原位置で差し替え、MKT_018 の碰撞を厨子二階の簷へ合わせる。
# 入力：tools/p13/dump_mainstreet_kits.gd の JSON（Godot が組んだ節點記述）。他の 148 棟・他のノードのテキストは一切変えない。
# 実行：cd godot && python tools/p13/integrate_mainstreet.py <kits39.json>
import json, re, sys, hashlib

SCENE = 'maps/village_v2/village_v2.tscn'
D = json.load(open(sys.argv[1], encoding='utf-8'))['buildings']
raw = open(SCENE, 'rb').read().decode('utf-8')
NL = '\r\n' if '\r\n' in raw else '\n'
before_sha = hashlib.sha256(raw.encode('utf-8')).hexdigest()

# ブロック分割（行頭 '[' で始まる見出し単位）
parts = re.split(r'(?m)^(?=\[)', raw)
head_re = re.compile(r'^\[node name="([^"]+)" type="([^"]+)" parent="([^"]+)"')
ext_re = re.compile(r'^\[ext_resource type="([^"]+)"(?: uid="[^"]*")? path="([^"]+)" id="([^"]+)"\]')

path_to_ext = {}
last_ext = -1
for i, p in enumerate(parts):
    m = ext_re.match(p)
    if m:
        path_to_ext.setdefault(m.group(2), m.group(3))
        last_ext = i

targets = {}
for bid, e in D.items():
    par = e['kit'][0]['parent']                     # Districts/X/Buildings/BID
    targets[par + '/Kit'] = e['kit']
    if e['frontage']:
        targets[par + '/Frontage'] = e['frontage']

new_ext = []


def ext_id(path):
    if path not in path_to_ext:
        nid = 'p13w2_%d' % (len(new_ext) + 1)
        path_to_ext[path] = nid
        new_ext.append('[ext_resource type="ArrayMesh" path="%s" id="%s"]%s' % (path, nid, NL))
    return path_to_ext[path]


def render(nodes):
    out = []
    for n in nodes:
        s = '[node name="%s" type="%s" parent="%s"]%s' % (n['name'], n['type'], n['parent'], NL)
        for k, v in n['props']:
            if v.startswith('@MESH:'):
                v = 'ExtResource("%s")' % ext_id(v[6:])
            s += '%s = %s%s' % (k, v, NL)
        out.append(s + NL)
    return out


done = set()
res = []
skip_prefix = None
for p in parts:
    m = head_re.match(p)
    if m:
        full = m.group(3) + '/' + m.group(1)
        if skip_prefix and (m.group(3) == skip_prefix or m.group(3).startswith(skip_prefix + '/')):
            continue
        skip_prefix = None
        if full in targets:
            res.extend(render(targets[full]))
            done.add(full)
            skip_prefix = full
            continue
    else:
        skip_prefix = None if not p.startswith('[node') else skip_prefix
    res.append(p)
assert done == set(targets), (len(done), len(targets), set(targets) - done)
txt = ''.join(res)

# 新しい ext_resource を最後の ext_resource の直後へ
if new_ext:
    i = txt.find(NL + NL, max(m.end() for m in re.finditer(r'(?m)^\[ext_resource [^\n]*', txt)) - 1)
    lines = txt.split(NL)
    li = max(k for k, l in enumerate(lines) if l.startswith('[ext_resource '))
    lines[li + 1:li + 1] = [l.rstrip(NL) for l in new_ext]
    txt = NL.join(lines)

# MKT_018：碰撞箱を厨子二階の簷（3.9）へ。底＝ground_lo−embed−base_h（P4 と同式）、その他の棟は不変
G = json.load(open('maps/village_v2/gen/greybox.json', encoding='utf-8'))
L = json.load(open('maps/village_v2/layout_v2.json', encoding='utf-8'))
embed = float(L['greybox']['embed'])
fixed = []
for b in G['buildings']:
    e = D.get(b['id'])
    if not e or abs(float(e['eave']) - float(b['eave_m'])) < 1e-6:
        continue
    bot = float(b['ground_lo']) - embed - float(b['base_h'])
    par = 'Districts/%s/Buildings/%s' % (b['district'], b['id'])
    m = re.search(r'\[node name="Shape" type="CollisionShape3D" parent="%s"[^\]]*\]\r?\ntransform = Transform3D\(([^)]*)\)\r?\nshape = SubResource\("([^"]+)"\)' % re.escape(par), txt)
    assert m, b['id']
    assert txt.count('SubResource("%s")' % m.group(2)) == 1, '共有 shape'
    vals = [float(x) for x in m.group(1).split(',')]
    old_y = vals[10]
    vals[10] = (float(e['eave']) + bot) * 0.5
    tr = 'Transform3D(%s)' % ', '.join(('%s' % repr(round(x, 7))).rstrip('0').rstrip('.') if x != int(x) else str(int(x)) for x in vals)
    txt = txt[:m.start(1)] + tr[len('Transform3D('):-1] + txt[m.end(1):]
    sm = re.search(r'(\[sub_resource type="BoxShape3D" id="%s"\]\r?\nsize = Vector3\()([^)]*)(\))' % re.escape(m.group(2)), txt)
    sz = [float(x) for x in sm.group(2).split(',')]
    old_h = sz[1]
    sz[1] = float(e['eave']) - bot
    txt = txt[:sm.start(2)] + ', '.join(repr(round(x, 7)) for x in sz) + txt[sm.end(2):]
    fixed.append((b['id'], old_h, sz[1], old_y, vals[10]))

open(SCENE, 'wb').write(txt.encode('utf-8'))
print('差し替え', len(done), '（Kit %d・Frontage %d）新 ext_resource %d、碰撞 %s' % (
    sum(1 for t in done if t.endswith('/Kit')), sum(1 for t in done if t.endswith('/Frontage')), len(new_ext), fixed))
print('sha', before_sha[:12], '->', hashlib.sha256(txt.encode('utf-8')).hexdigest()[:12])
