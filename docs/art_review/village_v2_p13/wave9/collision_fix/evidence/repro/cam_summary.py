"""W9 FIX 最終驗收：TPS 相機實プレイ確認の集計。python cam_summary.py <dir>
各脚（路線×腕の向き×俯仰）で BEFORE→AFTER を比べ、gameplay 影響で分類：
  REG_SIG  ：AFTER で連続 pen または hidden が BEFORE より 0.25 s 以上長い（壁の中が 1/4 秒以上映る／玩家が見えない）
  REG_MIN  ：0.05–0.25 s 長い（数フレーム・歩きながらは一瞬）
  SNAP+    ：急な寄り（1 フレーム 1.5 m 以上）の回数が増えた
  BETTER   ：連続 pen／hidden が 0.05 s 以上短くなった
  SAME     ：その他
"""
import glob, json, sys, collections

d = sys.argv[1]
rows = []
phys = []
for f in sorted(glob.glob(d + "/cam_*.json")):
    J = json.load(open(f, encoding="utf-8"))
    phys.append(J.get("__phys_ms"))
    for bid, legs in J.items():
        if bid.startswith("__") or bid.endswith("__shots"):
            continue
        for r in legs:
            rows.append((bid, r))
print("legs", len(rows), "phys", phys)


def cls(r):
    b, a = r["before"], r["after"]
    dp = a["pen_run"] - b["pen_run"]
    dh = a["hid_run"] - b["hid_run"]
    worst = max(dp, dh)
    if worst >= 0.25:
        return "REG_SIG"
    if worst >= 0.05:
        return "REG_MIN"
    if a["snap"] > b["snap"]:
        return "SNAP+"
    if min(dp, dh) <= -0.05:
        return "BETTER"
    return "SAME"


per = collections.defaultdict(collections.Counter)
tot = collections.Counter()
sig = []
for bid, r in rows:
    c = cls(r)
    per[bid][c] += 1
    tot[c] += 1
    if c in ("REG_SIG",):
        sig.append((bid, r))
print("total", dict(tot))
for bid in per:
    agg = collections.Counter()
    for b2, r in rows:
        if b2 != bid:
            continue
        for cfg in ("before", "after"):
            for k in ("pen_t", "hid_t", "short_t"):
                agg[(cfg, k)] += r[cfg][k]
            agg[(cfg, "snap")] += r[cfg]["snap"]
            agg[(cfg, "reach")] += 1 if r[cfg]["reached"] else 0
    print("%-12s %s | pen %.1f→%.1f s hid %.1f→%.1f s short %.1f→%.1f s snap %d→%d reach %d→%d/36" % (
        bid, dict(per[bid]), agg[("before", "pen_t")], agg[("after", "pen_t")], agg[("before", "hid_t")], agg[("after", "hid_t")],
        agg[("before", "short_t")], agg[("after", "short_t")], agg[("before", "snap")], agg[("after", "snap")], agg[("before", "reach")], agg[("after", "reach")]))
print("\nREG_SIG legs:")
for bid, r in sig:
    b, a = r["before"], r["after"]
    print("  %s %s %s p%.2f  pen run %.2f→%.2f  hid run %.2f→%.2f  who %s  end_lx %s→%s" % (bid, r["route"], r["arm"], r["pitch"], b["pen_run"], a["pen_run"], b["hid_run"], a["hid_run"], a["pen_who"], b["end_lx"], a["end_lx"]))
print("\nreach changed:")
for bid, r in rows:
    if r["before"]["reached"] != r["after"]["reached"]:
        print("  %s %s %s p%.2f reach %s→%s end_lx %s→%s" % (bid, r["route"], r["arm"], r["pitch"], r["before"]["reached"], r["after"]["reached"], r["before"]["end_lx"], r["after"]["end_lx"]))
