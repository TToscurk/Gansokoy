"""W9 FIX 最終驗收：probe（before＝元の箱／after＝Shell・同じ見た目）の残差を分類する。
  python w9fix_classify.py probe_final.json collision_fit.json
"""
import collections, json, sys

P = json.load(open(sys.argv[1], encoding="utf-8"))["buildings"]
F = json.load(open(sys.argv[2], encoding="utf-8"))["buildings"]

tot = collections.Counter()
for r in P.values():
    for c in ("before", "after"):
        tot[(c, "ghost")] += r[c]["walk"]["ghost"]
        tot[(c, "pen")] += r[c]["walk"]["pen"]
print("walk ghost before %d → after %d ; pen before %d → after %d" % (tot[("before", "ghost")], tot[("after", "ghost")], tot[("before", "pen")], tot[("after", "pen")]))

# --- walk residuals per building (after)
print("\n[walk residual after] building shell? ghost(b→a) pen(b→a) contact-height range")
for bid, r in sorted(P.items()):
    a, b = r["after"]["walk"], r["before"]["walk"]
    if a["ghost"] or a["pen"]:
        hs = [s[5][1] for s in a["samples"] if s[5]]
        print("  %s %s g %d→%d p %d→%d  h %s" % (bid, "S" if bid in F else "-", b["ghost"], a["ghost"], b["pen"], a["pen"],
              ("%.2f..%.2f" % (min(hs), max(hs))) if hs else "-"))

# --- camera
tr = collections.Counter()
n = 0
for r in P.values():
    n += r["arm_cmp"]["n"] - r["arm_cmp"]["skipped_inside"]
    for k, v in r["arm_cmp"]["trans"].items():
        tr[k] += v
better = tr["inv>ok"] + tr["clip>ok"]
worse = tr["ok>clip"] + tr["ok>inv"] + tr["clip>inv"]
print("\n[camera] compared %d ; transitions %s" % (n, dict(sorted(tr.items()))))
print("  improved (inv>ok + clip>ok) %d ; worsened (ok>clip + ok>inv + clip>inv) %d ; inv>clip %d" % (better, worse, tr["inv>clip"]))
reg = [(bid, s) for bid, r in P.items() for s in r["arm_cmp"]["reg"]]


def cls(bid, s):
    nn = s["vis_n"]
    surf = "nohit" if not nn else ("wall" if abs(nn[1]) < 0.35 else ("under" if nn[1] < 0 else "top"))
    d = s["a"] - s["v"]
    through = s["after_who"] == ""
    if s["tk"] == "ok>inv":
        return "C0 早く止まる（ok>inv：Shell が見た目より手前）"
    if through:
        return "C1 素通り（見た目の面を抜けて 7.5 m まで何にも当たらない）"
    if d <= 1.0:
        return "C2 浅い（見た目の面の奥 ≤ 1.0 m の Shell で止まる）"
    return "C3 深い（見た目の面の奥 > 1.0 m の Shell で止まる）"


c = collections.Counter(cls(b, s) for b, s in reg)
print("  stored regression samples %d" % len(reg))
for k, v in sorted(c.items()):
    print("   ", v, k)
tgt = collections.Counter((s["vis_b"] or b) for b, s in reg)
print("  by visible building:", tgt.most_common(12))
surf = collections.Counter(("wall" if s["vis_n"] and abs(s["vis_n"][1]) < 0.35 else ("under" if s["vis_n"] and s["vis_n"][1] < 0 else "top/none")) for b, s in reg)
print("  by surface:", dict(surf))
