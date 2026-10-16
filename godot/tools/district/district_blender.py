"""district_blender.py — 人間之里 街區管線（方案 C）の Blender 端。

使用者の開いている Blender（GUI）で Blender MCP の execute_blender_code から読み込む：

    ns = {}
    exec(open(r"D:/神社/shrine/godot/tools/district/district_blender.py", encoding="utf-8").read(), ns)
    D = ns["District"]("B8")          # work/district/B8/ の context.json・assets.json を読む
    D.load_all()                       # 地面（高さ表＋置けない所の色）・context.glb・資産ライブラリ
    D.seed()                           # 既存 manifest があればそれ、無ければ context の seed_items から配置
    D.place("st_ido", 428.6, -217.4, yaw=0.67, cluster="B8_well")   # 以後は Godot 座標で置く／動かす
    D.check()                          # Blender 側の初篩（置けない所・接地・重なり・範囲外）
    D.export_manifest()                # → godot/data/district/B8.json（source of truth）
    bpy.app.driver_namespace["district"] = D   # 次の呼び出しで再利用

座標の約束（固定・資産ごとに変えない）：
    Godot (x, y, z) → Blender (x, -z, y)；yaw（Godot の Y 軸回り）→ rotation_euler.z；
    scale (sx, sy, sz) → Blender (sx, sz, sy)。メートル、unit scale 1.0、原点＝足元（BASE）。
manifest は Godot 世界座標で書く。Godot 側は換算しない。

してはいけないこと：scene の全消去、使用者の既存オブジェクトの変更、資産メッシュの直接編集
（ライブラリのメッシュは共有。新しい形が要るなら Kit パイプラインで資産登録してから）、
X/Y 軸の回転（manifest は yaw だけ）。
"""
import bpy
import bmesh
import datetime
import hashlib
import json
import math
import os
from mathutils import Vector

FORMAT = "gansokoy.district_manifest.v1"
SPACE = "godot_world_y_up_m"
REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else r"D:/神社/shrine/godot/tools/district", "..", "..", ".."))
LIB_PREFIX = "DLIB_"
NAN = -9999.0
OK_COLOR = (0.55, 0.62, 0.50, 1.0)
BAD_COLOR = (0.85, 0.25, 0.20, 1.0)
WATER_COLOR = (0.20, 0.40, 0.75, 1.0)


def g2b(x, y, z):
    return Vector((x, -z, y))


def b2g(v):
    return (v.x, v.z, -v.y)


def _col(name, parent=None):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(c)
    return c


class District:
    def __init__(self, did, work_dir=None, manifest_path=None):
        self.id = did
        self.dir = work_dir or os.path.join(REPO, "work", "district", did)
        with open(os.path.join(self.dir, "context.json"), encoding="utf-8") as f:
            self.ctx = json.load(f)
        with open(os.path.join(self.dir, "assets.json"), encoding="utf-8") as f:
            self.assets = json.load(f)["assets"]
        if self.ctx.get("space") != SPACE:
            raise ValueError("context.json の space が %s でない" % SPACE)
        self.manifest_path = manifest_path or self.ctx["manifest"]
        self.rect = self.ctx["rect"]              # [x, z, w, d]（Godot）
        H = self.ctx["heights"]
        self.h0, self.hs, self.hnx, self.hnz, self.hv = H["origin"], H["step"], H["nx"], H["nz"], H["h"]
        Rz = self.ctx["reasons"]
        self.r0, self.rs, self.rnx, self.rnz = Rz["origin"], Rz["step"], Rz["nx"], Rz["nz"]
        self.legend, self.rg, self.rsoft = Rz["legend"], Rz["ground"], Rz["soft"]
        self.root = _col("District_%s" % did)
        # 参考（唯読・書き出さない）と作業（書き出す）を分ける。作業は種類ごとの子 collection。
        self.col_ctx = _col("REFERENCE_EXISTING_VILLAGE_%s" % did, self.root)
        self.col_ctx.hide_select = True
        self.col = _col("DISTRICT_%s_WORK" % did, self.root)
        self.sub = {k: _col("DISTRICT_%s_%s" % (did, k), self.col) for k in ("STRUCTURES", "PROPS", "VEGETATION")}

    def _sub_for(self, asset):
        """書き出しには影響しない整理用の分類：植物／大きな構造物（塀・木戸・下屋・棚・井戸・柵）／小物"""
        a = self.assets[asset]
        if a["kind"] in ("veg", "tree", "bamboo", "shrub"):
            return self.sub["VEGETATION"]
        ab = a["aabb"]
        w, h, d = ab[3] - ab[0], ab[4] - ab[1], ab[5] - ab[2]
        return self.sub["STRUCTURES"] if (max(w, d) >= 1.8 or h >= 1.7) else self.sub["PROPS"]

    def objects(self):
        return list(self.col.all_objects)

    # ───────────── 高さ・理由表 ─────────────
    def height(self, x, z):
        fx = (x - self.h0[0]) / self.hs
        fz = (z - self.h0[1]) / self.hs
        i = max(0, min(self.hnx - 2, int(math.floor(fx))))
        j = max(0, min(self.hnz - 2, int(math.floor(fz))))
        tx, tz = min(1.0, max(0.0, fx - i)), min(1.0, max(0.0, fz - j))
        v = [self.hv[(j + b) * self.hnx + (i + a)] for b in (0, 1) for a in (0, 1)]
        if any(h <= NAN + 1 for h in v):
            ok = [h for h in v if h > NAN + 1]
            return min(ok) if ok else 0.0
        return (v[0] * (1 - tx) + v[1] * tx) * (1 - tz) + (v[2] * (1 - tx) + v[3] * tx) * tz

    def reason(self, x, z, soft=False):
        i = int(round((x - self.r0[0]) / self.rs))
        j = int(round((z - self.r0[1]) / self.rs))
        if i < 0 or j < 0 or i >= self.rnx or j >= self.rnz:
            return "outside"
        return self.legend[(self.rsoft if soft else self.rg)[j * self.rnx + i]]

    # ───────────── 足元（W9.foot と同じ形） ─────────────
    def foot(self, asset, x, z, yaw, sx, sz, soft=False):
        a = self.assets[asset]
        ex = (math.cos(yaw), -math.sin(yaw))
        ez = (math.sin(yaw), math.cos(yaw))
        if soft and a["kind"] in ("veg",):
            r = (0.3 if asset.startswith("young") else 0.35) * max(sx, sz)
            x0, x1, z0, z1 = -r, r, -r, r
        else:
            d = a["foot"]
            x0, x1 = sorted((d[0] * sx, d[3] * sx))
            z0, z1 = d[2] * sz, d[5] * sz
        return [(x + ex[0] * u + ez[0] * w, z + ex[1] * u + ez[1] * w) for (u, w) in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))]

    def ground_y(self, asset, x, z, yaw, sx, sz, soft=False):
        pts = [(x, z)] + self.foot(asset, x, z, yaw, sx, sz, soft)
        return min(self.height(px, pz) for px, pz in pts)

    # ───────────── 読み込み ─────────────
    def load_all(self, glb=True):
        self.build_ground()
        if glb:
            self.load_context_glb()
        self.load_library()

    def build_ground(self):
        name = "CTX_%s_ground" % self.id
        old = bpy.data.objects.get(name)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        vs = []
        for j in range(self.hnz):
            for i in range(self.hnx):
                h = self.hv[j * self.hnx + i]
                x, z = self.h0[0] + i * self.hs, self.h0[1] + j * self.hs
                vs.append(bm.verts.new(g2b(x, h if h > NAN + 1 else 0.0, z)))
        col = bm.loops.layers.color.new("nogo")
        for j in range(self.hnz - 1):
            for i in range(self.hnx - 1):
                q = [vs[j * self.hnx + i], vs[j * self.hnx + i + 1], vs[(j + 1) * self.hnx + i + 1], vs[(j + 1) * self.hnx + i]]
                try:
                    f = bm.faces.new(q)
                except ValueError:
                    continue
                cx = self.h0[0] + (i + 0.5) * self.hs
                cz = self.h0[1] + (j + 0.5) * self.hs
                r = self.reason(cx, cz)
                c = OK_COLOR if r in ("ok", "outside") else BAD_COLOR
                for lp in f.loops:
                    lp[col] = c
        bm.normal_update()
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        self.col_ctx.objects.link(ob)
        ob.hide_select = True
        # 水面
        cells = self.ctx.get("water", {}).get("cells", [])
        if cells:
            wn = "CTX_%s_water" % self.id
            old = bpy.data.objects.get(wn)
            if old:
                bpy.data.objects.remove(old, do_unlink=True)
            wm = bpy.data.meshes.new(wn)
            bm = bmesh.new()
            s = self.hs * 0.5
            for i, j, h in cells:
                x, z = self.h0[0] + i * self.hs, self.h0[1] + j * self.hs
                q = [bm.verts.new(g2b(x + dx, h, z + dz)) for dx, dz in ((-s, -s), (s, -s), (s, s), (-s, s))]
                bm.faces.new(q)
            bm.to_mesh(wm)
            bm.free()
            wo = bpy.data.objects.new(wn, wm)
            wo.color = WATER_COLOR
            self.col_ctx.objects.link(wo)
            wo.hide_select = True
        return ob

    def _import_glb(self, path):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        return [o for o in bpy.data.objects if o not in before]

    def load_context_glb(self):
        path = os.path.join(self.dir, "context.glb")
        if not os.path.exists(path):
            return 0
        new = self._import_glb(path)
        for o in new:
            for c in list(o.users_collection):
                c.objects.unlink(o)
            self.col_ctx.objects.link(o)
            o.hide_select = True
        return len(new)

    def load_library(self):
        """assets.glb → 資産ごとのメッシュ（DLIB_<id>、world 変換を焼き込み・fake user）。インポートしたオブジェクトは消す。"""
        have = {m.name[len(LIB_PREFIX):] for m in bpy.data.meshes if m.name.startswith(LIB_PREFIX)}
        if all(a in have for a in self.assets):
            return 0
        new = self._import_glb(os.path.join(self.dir, "assets.glb"))
        n = 0
        for o in new:
            if o.type == "MESH":
                aid = o.name.rsplit(".", 1)[0] if o.name.rsplit(".", 1)[-1].isdigit() else o.name
                if aid in self.assets and aid not in have:
                    me = o.data.copy()
                    me.transform(o.matrix_world)
                    me.name = LIB_PREFIX + aid
                    me.use_fake_user = True
                    have.add(aid)
                    n += 1
        for o in new:
            bpy.data.objects.remove(o, do_unlink=True)
        return n

    def _mesh(self, asset):
        me = bpy.data.meshes.get(LIB_PREFIX + asset)
        if me is None:
            raise KeyError("資産 %s のライブラリメッシュが無い（load_library、または district_context.gd -- --assets=all）" % asset)
        return me

    # ───────────── 配置（Godot 座標） ─────────────
    def _next_vid(self):
        n = 0
        for o in self.objects():
            v = o.get("d_vid", "")
            if v.startswith(self.id + "_") and v[len(self.id) + 1:].isdigit():
                n = max(n, int(v[len(self.id) + 1:]))
        return "%s_%04d" % (self.id, n + 1)

    def place(self, asset, x, z, yaw=0.0, s=1.0, y=None, vid=None, cluster="misc", mode=None, flags=(), b="", who="", why="",
              kind="reuse", feature="", scale=None, ground=None, src=""):
        if asset not in self.assets:
            raise KeyError("未登録の資産 %s" % asset)
        sx, sy, sz = scale or (s, s, s)
        flags = list(flags)
        if mode is None:
            mode = "soft" if self.assets[asset]["kind"] in ("veg", "tree", "bamboo", "shrub") else "ground"
        if mode == "soft" and "soft" not in flags:
            flags.append("soft")
        hang = "hang" in flags
        if ground is None:
            ground = "fixed" if hang else "snap"
        if y is None:
            y = self.ground_y(asset, x, z, yaw, sx, sz, "soft" in flags)
        vid = vid or self._next_vid()
        if bpy.data.objects.get(vid):
            raise KeyError("vid %s は既にある" % vid)
        ob = bpy.data.objects.new(vid, self._mesh(asset))
        self._sub_for(asset).objects.link(ob)
        ob.location = g2b(x, y, z)
        ob.rotation_euler = (0.0, 0.0, yaw)
        ob.scale = (sx, sz, sy)
        for k, v in (("vid", vid), ("asset", asset), ("cluster", cluster), ("mode", mode), ("flags", ",".join(flags)), ("b", b),
                     ("who", who), ("why", why), ("kind", kind), ("feature", feature), ("ground", ground), ("src", src)):
            ob["d_" + k] = v
        return ob

    def move(self, vid, x=None, z=None, yaw=None, s=None, snap=True):
        # DIST のオブジェクトは親なし → location／rotation_euler／scale がそのまま world（matrix_world の更新待ちに頼らない）
        ob = bpy.data.objects[vid]
        gx, gy, gz = b2g(ob.location)
        x = gx if x is None else x
        z = gz if z is None else z
        if yaw is not None:
            ob.rotation_euler = (0.0, 0.0, yaw)
        if s is not None:
            ob.scale = (s, s, s)
        y = gy
        if snap and ob.get("d_ground", "snap") == "snap":
            flags = [f for f in ob.get("d_flags", "").split(",") if f]
            y = self.ground_y(ob["d_asset"], x, z, ob.rotation_euler.z, ob.scale.x, ob.scale.y, "soft" in flags)
        ob.location = g2b(x, y, z)
        return ob

    def remove(self, vid):
        ob = bpy.data.objects.get(vid)
        if ob:
            bpy.data.objects.remove(ob, do_unlink=True)

    def snap_all(self):
        n = 0
        for ob in self.objects():
            if ob.get("d_ground", "snap") == "snap":
                self.move(ob.name)
                n += 1
        return n

    def from_entries(self, entries, replace=False):
        if replace:
            for ob in self.objects():
                bpy.data.objects.remove(ob, do_unlink=True)
        n = 0
        for e in entries:
            if bpy.data.objects.get(e["vid"]):
                continue
            px, py, pz = e["pos"]
            sc = e.get("scale", [1.0, 1.0, 1.0])
            self.place(e["asset"], px, pz, yaw=e.get("yaw", 0.0), y=py, vid=e["vid"], cluster=e.get("cluster", "misc"), mode=e.get("mode", "ground"),
                       flags=e.get("flags", []), b=e.get("b", ""), who=e.get("who", ""), why=e.get("why", ""), kind=e.get("kind", "reuse"),
                       feature=e.get("feature", ""), scale=tuple(sc), ground=e.get("ground", "snap"), src=e.get("src", ""))
            n += 1
        return n

    def seed(self, replace=False):
        """既存 manifest（source of truth）があればそれを、無ければ context の seed_items（先行 GDScript overlay）を置く"""
        if os.path.exists(self.manifest_path):
            with open(self.manifest_path, encoding="utf-8") as f:
                return self.from_entries(json.load(f)["items"], replace)
        return self.from_entries(self.ctx.get("seed_items", []), replace)

    # ───────────── 状態・検査 ─────────────
    def _state(self, ob):
        mw = ob.matrix_world
        loc, rot, sc = mw.decompose()
        e = rot.to_euler("XYZ")
        gx, gy, gz = b2g(loc)
        return {"vid": ob.get("d_vid", ob.name), "asset": ob.get("d_asset", ""), "x": gx, "y": gy, "z": gz, "yaw": e.z,
                "tilt": max(abs(e.x), abs(e.y)), "sx": sc.x, "sy": sc.z, "sz": sc.y, "mode": ob.get("d_mode", "ground"),
                "flags": [f for f in ob.get("d_flags", "").split(",") if f], "ground": ob.get("d_ground", "snap"),
                "lib": ob.type == "MESH" and ob.data.name.startswith(LIB_PREFIX), "ob": ob}

    @staticmethod
    def _sat(p, q):
        for poly in (p, q):
            for k in range(4):
                ax = (-(poly[(k + 1) % 4][1] - poly[k][1]), poly[(k + 1) % 4][0] - poly[k][0])
                pa = [ax[0] * x + ax[1] * z for x, z in p]
                qa = [ax[0] * x + ax[1] * z for x, z in q]
                if max(pa) <= min(qa) + 1e-6 or max(qa) <= min(pa) + 1e-6:
                    return False
        return True

    def check(self, verbose=True):
        """Blender 側の初篩。最終判定は Godot の district_verify.gd（W9.why・三角形・SpringArm）。"""
        bpy.context.view_layer.update()      # 置いた直後は matrix_world が未更新（全部原点に見える）
        R = self.rect
        issues = []
        sts = [self._state(o) for o in self.objects()]
        feet = {}
        for st in sts:
            vid = st["vid"]
            if not st["lib"]:
                issues.append((vid, "not_library_mesh（資産ライブラリ以外のメッシュは書き出せない）"))
                continue
            if st["tilt"] > 1e-3:
                issues.append((vid, "tilt %.3f rad（manifest は yaw だけ）" % st["tilt"]))
            if not (R[0] <= st["x"] <= R[0] + R[2] and R[1] <= st["z"] <= R[1] + R[3]):
                issues.append((vid, "outside_rect"))
            soft = "soft" in st["flags"]
            fp = self.foot(st["asset"], st["x"], st["z"], st["yaw"], st["sx"], st["sz"], soft)
            feet[vid] = (fp, st)
            if "hang" in st["flags"] or st["mode"] in ("wall", "gap"):
                continue           # 壁付け・宅間は Godot 側だけで判定
            bad = set()
            for (px, pz) in fp + [(st["x"], st["z"])]:
                r = self.reason(px, pz, soft)
                if r not in ("ok", "outside", "overlap"):
                    bad.add(r)
            if bad:
                issues.append((vid, "nogo:" + ",".join(sorted(bad))))
            if st["ground"] == "snap":
                gy = self.ground_y(st["asset"], st["x"], st["z"], st["yaw"], st["sx"], st["sz"], soft)
                if abs(st["y"] - gy) > self.ctx["tolerances"]["y_snap"]:
                    issues.append((vid, "ground %.2f vs %.2f" % (st["y"], gy)))
        keys = sorted(feet)
        for i, a in enumerate(keys):
            fa, sa = feet[a]
            if "nov" in sa["flags"] or "hang" in sa["flags"]:
                continue
            for b in keys[i + 1:]:
                fb, sb = feet[b]
                if "nov" in sb["flags"] or "hang" in sb["flags"]:
                    continue
                if abs(sa["x"] - sb["x"]) > 8 or abs(sa["z"] - sb["z"]) > 8:
                    continue
                if self._sat(fa, fb):
                    issues.append((a, "overlap:" + b))
        kc = self.ctx.get("keep_clear", {})
        for st in sts:
            for k, p in kc.items():
                if math.hypot(st["x"] - p[0], st["z"] - p[1]) < self.ctx.get("keep_r", 6.0):
                    issues.append((st["vid"], "keep_clear:" + k))
        if verbose:
            print("[district.check] %s：%d 件中 問題 %d" % (self.id, len(sts), len(issues)))
            for vid, w in issues[:40]:
                print("   ", vid, w)
        return issues

    # ───────────── 頂点 AABB・参考の検査 ─────────────
    @staticmethod
    def vert_aabb(ob):
        """頂点ベースの world AABB（Godot 座標）。回転した箱の AABB ではなく、matrix_world で変換した頂点の min／max"""
        mw = ob.matrix_world
        mn = [1e30, 1e30, 1e30]
        mx = [-1e30, -1e30, -1e30]
        for v in ob.data.vertices:
            g = b2g(mw @ v.co)
            for k in range(3):
                if g[k] < mn[k]:
                    mn[k] = g[k]
                if g[k] > mx[k]:
                    mx[k] = g[k]
        return mn + mx

    def validate_reference(self, tol=None, verbose=True):
        """座標換算の検査：context.glb の既存建物（REF_<名>__<k>、Godot→glTF→Blender）を Blender で測り、
        Godot が context.json に書いた同じ頂点 AABB・mesh0 の位置／yaw／scale と比べる（g2b／b2g を使わない経路と使う経路の突き合わせ）。"""
        bpy.context.view_layer.update()
        tol = self.ctx.get("tolerances", {}).get("ref_aabb", 0.0) if tol is None else tol
        rows = []
        for r in self.ctx.get("ref_objects", []):
            obs = sorted([o for o in self.col_ctx.objects if o.name.startswith("REF_%s__" % r["name"]) and o.type == "MESH"], key=lambda o: o.name)
            if not obs:
                rows.append({"name": r["name"], "ok": False, "why": "context.glb に REF_ が無い"})
                continue
            ab = None
            for o in obs:
                a = self.vert_aabb(o)
                ab = a if ab is None else [min(ab[k], a[k]) for k in range(3)] + [max(ab[k + 3], a[k + 3]) for k in range(3)]
            d_ab = max(abs(ab[k] - r["aabb_v"][k]) for k in range(6))
            m0 = next((o for o in obs if o.name.split(".")[0] == "REF_%s__0" % r["name"]), obs[0])
            loc, rot, sc = m0.matrix_world.decompose()
            e = rot.to_euler("XYZ")
            g = b2g(loc)
            d_pos = max(abs(g[k] - r["mesh0_origin"][k]) for k in range(3))
            d_yaw = abs((e.z - r["mesh0_yaw"] + math.pi) % (2 * math.pi) - math.pi)
            gsc = (sc.x, sc.z, sc.y)
            d_sc = max(abs(gsc[k] - r["mesh0_scale"][k]) for k in range(3))
            ok = len(obs) == r["n_meshes"] and d_ab <= tol and d_pos <= tol and d_yaw <= 1e-4 and d_sc <= 1e-3
            rows.append({"name": r["name"], "meshes": len(obs), "expect": r["n_meshes"], "d_aabb": d_ab, "d_pos": d_pos, "d_yaw": d_yaw,
                         "d_scale": d_sc, "yaw_deg": math.degrees(r["mesh0_yaw"]), "scale": r["mesh0_scale"], "ok": ok, "tilt": max(abs(e.x), abs(e.y))})
        if verbose:
            for x in rows:
                print("[district.ref]", x)
        return rows

    # ───────────── 書き出し ─────────────
    def export_manifest(self, path=None, allow_issues=False):
        """manifest（Godot 世界座標）を書く。内容（items と context）が前回と同じなら書き換えない（決定的な書き出し）。"""
        path = path or self.manifest_path
        issues = self.check(verbose=False)
        hard = [i for i in issues if i[1].startswith(("not_library_mesh", "tilt"))]
        if hard:
            raise ValueError("書き出せない：%s" % hard[:10])
        if issues and not allow_issues:
            print("[district.export] 注意：Blender 初篩の問題 %d 件（Godot verify で最終判定）" % len(issues))
        items = []
        for ob in sorted(self.objects(), key=lambda o: o.get("d_vid", o.name)):
            st = self._state(ob)
            corners = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
            g = [b2g(c) for c in corners]
            mn = [min(p[k] for p in g) for k in range(3)]
            mx = [max(p[k] for p in g) for k in range(3)]
            it = {"vid": st["vid"], "asset": st["asset"], "cluster": ob.get("d_cluster", "misc"), "mode": st["mode"],
                  "pos": [round(st["x"], 4), round(st["y"], 4), round(st["z"], 4)], "yaw": round(st["yaw"], 6),
                  "scale": [round(st["sx"], 4), round(st["sy"], 4), round(st["sz"], 4)],
                  "aabb": [round(v, 4) for v in mn + mx], "aabb_v": [round(v, 4) for v in self.vert_aabb(ob)],
                  "flags": st["flags"], "b": ob.get("d_b", ""),
                  "who": ob.get("d_who", ""), "why": ob.get("d_why", ""), "kind": ob.get("d_kind", "reuse"),
                  "feature": ob.get("d_feature", ""), "ground": st["ground"]}
            if ob.get("d_src", ""):
                it["src"] = ob.get("d_src", "")
            items.append(it)
        items = json.loads(json.dumps(items))
        with open(os.path.join(self.dir, "context.json"), "rb") as f:
            csha = hashlib.sha256(f.read()).hexdigest()
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                old = json.load(f)
            if old.get("items") == items and old.get("context_sha256") == csha:
                print("[district.export] 変更なし（%d 件）→ %s は書き換えない" % (len(items), path))
                return path
        M = {"format": FORMAT, "space": SPACE, "district": self.id, "name": self.ctx.get("name", ""),
             "generated_by": "godot/tools/district/district_blender.py export_manifest",
             "generated_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
             "blender": bpy.app.version_string, "context_sha256": csha, "scene_sha256": self.ctx.get("scene_sha256", ""),
             "supersedes": self.ctx.get("supersedes", []), "n_items": len(items),
             "blender_check": {"issues": len(issues), "sample": ["%s %s" % i for i in issues[:20]]}, "items": items}
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(M, f, ensure_ascii=False, indent=1)
        print("[district.export] %d 件 → %s" % (len(items), path))
        return path

    def save_blend(self):
        """作業 .blend を work/ にコピー保存（使用者の現在のファイルは変えない）"""
        p = os.path.join(self.dir, "%s.blend" % self.id)
        bpy.ops.wm.save_as_mainfile(filepath=p, copy=True)
        return p

    def teardown(self):
        """街區の collection と DLIB メッシュを消す（作業は先に export_manifest／save_blend すること）"""
        for o in self.objects() + list(self.col_ctx.all_objects):
            bpy.data.objects.remove(o, do_unlink=True)
        for c in list(self.sub.values()) + [self.col, self.col_ctx, self.root]:
            bpy.data.collections.remove(c)
        for m in list(bpy.data.meshes):
            if m.name.startswith(LIB_PREFIX) or (m.users == 0 and m.name.startswith("CTX_%s" % self.id)):
                m.use_fake_user = False
                if m.users == 0:
                    bpy.data.meshes.remove(m)
