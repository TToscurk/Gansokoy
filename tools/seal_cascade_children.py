"""封存の子封存（child_seals）雜湊の連鎖追従（P11 R1）。

  python tools/seal_cascade_children.py            → 乾式：child_seals の記録雜湊と現在の子封存檔の雜湊が違うものを列挙するだけ
  python tools/seal_cascade_children.py --apply --kind=<KIND> --reason=<文>
        → 不一致の child_seals だけを現在値へ更新し、その封存に reseal_history（kind・old/new・seal_file_before・理由）を追記。
          子が変われば親の雜湊も変わるので、不一致が無くなるまで繰り返す（固定点）。
封存本体の凍結檔・ART_REVIEW 圖・證據・status には触れない（child_seals の雜湊だけ）。書式（indent・改行コード・末尾改行）は元のまま。
起点の封存（例：P9 FINAL）の更新は、その工作の reseal 腳本で先に行うこと（本腳本は子封存の雜湊の追従だけ）。
"""
import glob
import hashlib
import json
import os
import sys

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(R)


def sha(f):
    return hashlib.sha256(open(f, 'rb').read()).hexdigest()


def fmt(raw):
    s = raw.decode('utf-8')
    lines = s.splitlines()
    indent = 1
    if len(lines) > 1:
        indent = len(lines[1]) - len(lines[1].lstrip(' '))
    return indent, raw.count(b'\r\n') > 0, raw.endswith(b'\n')


def scan():
    out = []
    for f in sorted(glob.glob('godot/data/*_seal.json')):
        f = f.replace('\\', '/')
        d = json.load(open(f, encoding='utf-8'))
        cs = d.get('child_seals')
        if not isinstance(cs, dict):
            continue
        for k, v in cs.items():
            if not isinstance(v, str) or not os.path.exists(k):
                continue
            now = sha(k)
            if now != v:
                out.append((f, k, v, now))
    return out


apply = '--apply' in sys.argv
kind = next((a.split('=', 1)[1] for a in sys.argv if a.startswith('--kind=')), 'CHILD_CASCADE')
reason = next((a.split('=', 1)[1] for a in sys.argv if a.startswith('--reason=')), '')
rounds = 0
while True:
    mm = scan()
    if not mm:
        print('不一致 0（round %d）' % rounds)
        break
    for f, k, o, n in mm:
        print('不一致：%s child %s %s → %s' % (f, k, o[:12], n[:12]))
    if not apply:
        break
    rounds += 1
    if rounds > 12:
        print('固定点に達しない')
        sys.exit(2)
    by = {}
    for f, k, o, n in mm:
        by.setdefault(f, []).append((k, o, n))
    for f, items in by.items():
        raw = open(f, 'rb').read()
        before = sha(f)
        indent, crlf, trailing = fmt(raw)
        d = json.loads(raw.decode('utf-8'))
        hist = d.setdefault('reseal_history', [])
        ent = next((h for h in hist if isinstance(h, dict) and h.get('kind') == kind), None)
        if ent is None:
            ent = {'kind': kind, 'at': '2026-10-10', 'child_seals': {}, 'seal_file_before': before}
            hist.append(ent)
        for k, o, n in items:
            d['child_seals'][k] = n
            if k in ent['child_seals']:
                ent['child_seals'][k][1] = n
            else:
                ent['child_seals'][k] = [o, n]
        ent['approved_by'] = 'user'
        ent['reason'] = reason
        s = json.dumps(d, ensure_ascii=False, indent=indent)
        if crlf:
            s = s.replace('\n', '\r\n')
        if trailing:
            s += '\r\n' if crlf else '\n'
        open(f, 'wb').write(s.encode('utf-8'))
        print('  更新 %s：child %d 件、seal %s → %s' % (f, len(items), before[:12], sha(f)[:12]))
