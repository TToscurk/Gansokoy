import json, sys
d = json.load(open(sys.argv[1]))
which = sys.argv[2]
x0, x1, z0, z1 = [float(v) for v in sys.argv[3:7]]
ci = {"r": 3, "g": 4, "b": 5, "a": 6, "fx": 7, "fy": 8, "wx": 9, "wy": 10, "y": 1}[sys.argv[7] if len(sys.argv) > 7 else "r"]
V = d[which]["verts"]
g = {}
for v in V:
    x, z = round(v[0]), round(v[2])
    if x0 <= x <= x1 and z0 <= z <= z1:
        g[(x, z)] = v
xs = sorted(set(k[0] for k in g))
zs = sorted(set(k[1] for k in g))
print(which, "x", xs[0], "..", xs[-1], "step", sorted(set(b - a for a, b in zip(xs, xs[1:]))))
print("   z/x " + "".join("%5d" % x for x in xs))
for z in zs:
    print("%6d " % z + "".join(("%5d" % round(g[(x, z)][ci] * 100) if (x, z) in g else "    .") for x in xs))
