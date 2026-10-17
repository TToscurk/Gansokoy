extends RefCounted
## 街區管線（方案 C，2026-10-16 使用者裁定）的 Godot 端共用庫。
##   Godot 唯讀匯出參考（district_context.gd）→ Blender MCP 組街區（district_blender.py）→ manifest（Godot 世界座標）
##   → 本庫 bake 成 overlay（district_build.gd）→ district_verify.gd 檢查。
## manifest（res://data/district/<ID>.json）是 source of truth（TYPE B 輸入）；本庫與三支工具都不寫 village_v2.tscn。
## 擺放判定直接沿用 W9（w9_lib.why／ground_y）與 W9 Phase 3 的資產／碰撞規則（w9p3_lib.bundle／dims），不另寫一套。
## 座標：manifest 一律 Godot 世界座標（Y-up、公尺）。Blender（Z-up）換算只在 district_blender.py 內做：
##   Godot (x, y, z) → Blender (x, -z, y)；yaw → rotation_euler.z；scale (sx, sy, sz) → (sx, sz, sy)。
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const P3 := preload("res://tools/p13/w9/w9p3_lib.gd")
const HU := preload("res://tools/village_v2_human_use_lib.gd")
const SL := preload("res://tools/village_v2_street_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")

const FORMAT := "gansokoy.district_manifest.v1"
## bake の規則（節点構成・碰撞・meta）を変えたら上げる。district_build.gd は manifest sha とこれが同じ overlay を書き直さない
## （Godot 4.7 は節点ごとに新しい unique_id を振るので、同じ入力でも .scn のバイトが毎回変わる → 無駄な差分を出さない）。
const BAKE_VERSION := "district_bake.v1"
const SPACE := "godot_world_y_up_m"
const SCENE := "res://maps/village_v2/village_v2.tscn"
const MANIFEST_DIR := "res://data/district/"
const GEN_DIR := "res://maps/village_v2/gen/"
const TEST_DIR := "res://tests/district/"
const FLAG_KEYS := ["hang", "band", "recess", "meadow_ok", "allow_rootp", "soft", "gap", "nov", "on_frontage"]
const MODES := ["ground", "soft", "wall", "gap"]

## 街區表。rect＝Godot 世界 (x, z) 範圍；seed＝先前 GDScript 規劃的同區 overlay（第一次進 Blender 的起點，之後以 manifest 為準）。
## arm_lanes／keep_clear 沿用 W9 Phase 8（w9p8_lib.ARM_LANES、verify_w9p8.KEEP_CLEAR）。
const DISTRICTS := {
	"B8": {"name": "東北聚落（龍神橋の東・香霖堂口・RNE）", "rect": Rect2(410.0, -250.0, 95.0, 70.0),
		"seed_scene": "res://maps/village_v2/gen/enrich_w9p8.scn", "seed_zone": "ZoneB8", "supersedes": ["EnrichW9P8:ZoneB8"],
		"arm_lanes": {"B8_nelane": [Vector2(424.0, -205.0), Vector2(438.0, -216.0), Vector2(456.0, -236.0), Vector2(470.0, -241.0)],
			"B8_nesouth": [Vector2(438.0, -216.0), Vector2(458.0, -208.0), Vector2(474.0, -192.0), Vector2(490.0, -188.0)]},
		"keep_clear": {"PORTAL_KOURINDOU": Vector2(428.0, -205.0)}},
	## B8 の試点（W9 Blender-first pilot）：RNE_002／003／004 の 3 戸と裏の共有地。seed は B8 manifest の rect 内（再利用・src に元 vid）。
	## 掛載するなら B8 の同範囲と二重にしない（supersedes）。ref_buildings＝座標換算の検査に使う既存建物（context.glb で REF_ 名）。
	"B8P": {"name": "東北聚落の試点（RNE_002–004 の三戸と裏の共有地）", "rect": Rect2(442.0, -241.0, 33.0, 31.0),
		"seed_manifest": "res://data/district/B8.json", "supersedes": ["EnrichW9P8:ZoneB8（rect 内）", "DistrictB8（rect 内）"],
		"ref_buildings": ["B_P_RNE_002", "B_P_RNE_003", "B_P_RNE_004"],
		"arm_lanes": {"B8P_nelane": [Vector2(438.0, -216.0), Vector2(456.0, -236.0), Vector2(472.0, -241.3)],
			"B8P_nesouth": [Vector2(438.0, -216.0), Vector2(458.0, -208.0)],
			"B8P_back": [Vector2(452.0, -212.5), Vector2(462.0, -216.0), Vector2(475.0, -218.5)]},
		"keep_clear": {"PORTAL_KOURINDOU": Vector2(428.0, -205.0)}},
	"A8": {"name": "稗田邸の西（中橫街の東端・田埂道・大宅の西塀）", "rect": Rect2(360.0, -58.0, 30.0, 52.0),
		"seed_scene": "res://maps/village_v2/gen/enrich_w9p8.scn", "seed_zone": "ZoneA8", "supersedes": ["EnrichW9P8:ZoneA8"],
		"arm_lanes": {"A8_cross_end": [Vector2(352.0, -35.2), Vector2(380.0, -36.0)], "A8_farmpath": [Vector2(372.0, -33.0), Vector2(372.0, -2.0)]},
		"keep_clear": {"PORTAL_HIEDA1F": Vector2(398.0, 2.0), "akyuu_record": Vector2(398.0, -4.0)}},
	## E2（2026-10-17 使用者）：丘腳社寺（LANDMARK_HILLFOOT_TEMPLE，社殿 12.0×11.4 m 在 (228, −170)）的境內環境。rect＝社寺整地面（y 1.20）＋西側水溝＋東／北丘腳＋丘腳街南緣。
	## 社寺本體・碰撞不動；既有 EnvironmentP9／MeadowP9／GroundcoverP9 不改（掛載後由 HillfootPrecinctE2 可逆抑制）。無 seed（原環境不是這條管線產的）；
	## 不設 keep_clear（石段前要鋪踏石；前庭留白由 verify_hf_precinct.gd 的前庭多邊形規則管）。
	"HF": {"name": "丘腳社寺 境內環境（參道・前庭・境界植栽）", "rect": Rect2(206.0, -190.0, 44.0, 42.0),
		"supersedes": [],
		"arm_lanes": {"HF_approach": [Vector2(228.0, -148.5), Vector2(228.0, -158.0), Vector2(228.0, -165.0)],
			"HF_front_cross": [Vector2(219.5, -161.5), Vector2(236.5, -161.5)],
			"HF_west_flank": [Vector2(220.0, -163.0), Vector2(220.0, -176.0)],
			"HF_east_flank": [Vector2(236.5, -163.0), Vector2(236.5, -176.0)]},
		## 掛載後 HillfootPrecinctE2 會可逆抑制的既有 EnvironmentP9 組（hf_precinct_lib.gd SUPPRESS_GROUPS 與此相同，verify_hf_precinct.gd 檢查一致）。
		## context／build／verify 用 prepare_scene 在『記憶體內』先拿掉這些節點與其碰撞，W9.why 才不會把它們當占用（env）。
		"suppress": ["Props/EnvironmentP9/edge/E082_fence_frag"],
		## 掛載済みの境內地面 overlay（地形 +3.2 cm 的可見面）併入 W9.top_h：踏石・植栽才會座在『看得見的地面』上，而不是埋在它下面（見 attach_surface）。
		"surface": "HillfootPrecinctE2/Ground",
		"keep_clear": {}},
}
const KEEP_R := 6.0
const Y_SNAP_TOL := 0.10        # 接地（W9 verify と同じ）
const Y_BLENDER_TOL := 0.30     # Blender の高さ表と Godot の接地の差（超えたら context が古い）
const AABB_TOL := 0.05          # Blender で量った world AABB と Godot で再計算した world AABB の差（軸換算の検査）
const XF_TOL := 0.01
## Runtime World AABB（頂点ベース：Blender で頂点を変換した aabb_v ↔ Godot で bake 済み節点の LOD0 頂点を global_transform で変換）。
## 許容値の決め方（固定）：B8P の制御往復（work/district/B8P/calibration.json：yaw 0／37°／143°・非一様 scale）を
## district_verify.gd --calibrate で実測 → 許容値＝max(1 mm, 実測最大 × 10) を切り上げ。district を評価する前に決め、FAIL を理由に広げない。
## 制御往復の実測（2026-10-16、B8P calibration.json 36 件：seed 33＋st_ido yaw 0／w9_kido yaw 36.9°／kr_kuruma yaw 143.2°・scale 1.1×0.9×1.25）：
##   M5b runtime 頂点 AABB の差 min 0.107 mm・max 0.076 mm・寸法 0.153 mm → 0.002 m
##   既存建物 3 棟（yaw −132.0°／−132.0°／−161.6°・mesh0 scale 5.4×0.69×10.01 等）context.glb 経由の頂点 AABB 差 0.210 mm → 0.003 m
const RT_AABB_TOL := 0.002
const REF_AABB_TOL := 0.003     # 既存建物（context.glb 経由）の頂点 AABB：Blender ↔ Godot（同じ規則）
const TERRAIN_FLOAT_TOL := 0.05 # 足元の最低点で地形より上に浮いてよい量（godot-asset-placement-validation の flush 0.05）
const TERRAIN_EMBED_REVIEW := 0.30  # 斜面で一辺が埋まる量がこれを超えたら REVIEW（小物が地面に沈んで見える）

static var _aabb_cache := {}


## 頂点ベースの world AABB（回転した箱の AABB ではなく、変換後の頂点の min／max）
static func tight_aabb(mesh: Mesh, xf: Transform3D) -> AABB:
	var f := mesh.get_faces()
	if f.is_empty():
		return xf * mesh.get_aabb()
	var a := AABB(xf * f[0], Vector3.ZERO)
	for i in range(1, f.size()):
		a = a.expand(xf * f[i])
	return a


## bake 済み item 節点の LOD0（visibility_range_begin＝0 の MeshInstance）の runtime 頂点 AABB
static func node_rt_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.visibility_range_begin > 0.001:
			continue
		var a := tight_aabb(mi.mesh, mi.global_transform)
		out = a if first else out.merge(a)
		first = false
	return out


static func manifest_path(d: String) -> String:
	return MANIFEST_DIR + d + ".json"


static func overlay_path(d: String) -> String:
	return GEN_DIR + "district_%s.scn" % d.to_lower()


static func node_name(d: String) -> String:
	return "District" + d


## 街區が「掛載後の世界」で判定されるよう、街區表の suppress（既存 overlay の抑制対象）を記憶内で取り除く（場景ファイルは書かない）。
## 節点そのものと、EnvironmentP9/Collision にある同名の <名>_c 碰撞箱を free する。戻り値＝取り除いた節点数。
static func prepare_scene(v: Node3D, d: String) -> int:
	var n := 0
	var col := v.get_node_or_null("Props/EnvironmentP9/Collision")
	for path: String in (DISTRICTS[d] as Dictionary).get("suppress", []):
		var node := v.get_node_or_null(path)
		if node == null:
			continue
		if col != null:
			for ch in node.get_children():
				var sh := col.get_node_or_null(String(ch.name) + "_c")
				if sh != null:
					col.remove_child(sh)
					sh.free()
		node.get_parent().remove_child(node)
		node.free()
		n += 1
	return n


## district 表 "surface"（場景內的 overlay Ground 節點路徑）：其 MeshInstance3D 中被覆（UV2.y）平均 ≥ 0.5 的三角形放進 C["SURF"]，
## 由本檔的 top_h／ground_y（W9 同名函式的包裝）一併當作『見えている最上面』——踏石・植栽才會座在看得見的地面上，不會埋在它下面。
## 注意：不能併入 C["F"]（W9.why 把 F 當『店先帯』＝不可放置，整個境內會變成 frontage）。沒掛載（節點不存在）→ 不加（回傳 0）。回傳三角形數。
static func attach_surface(C: Dictionary, v: Node3D, d: String) -> int:
	var path: String = String((DISTRICTS[d] as Dictionary).get("surface", ""))
	if path == "":
		return 0
	var mi := v.get_node_or_null(path) as MeshInstance3D
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return 0
	var arr := mi.mesh.surface_get_arrays(0)
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var U2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var IDX: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	for t in range(0, IDX.size(), 3):
		if (U2[IDX[t]].y + U2[IDX[t + 1]].y + U2[IDX[t + 2]].y) / 3.0 >= 0.5:
			faces.append(V[IDX[t]])
			faces.append(V[IDX[t + 1]])
			faces.append(V[IDX[t + 2]])
	var S := RLib.TriSampler.new()
	S.add(faces, RLib.rel_xf(mi, v))
	C["SURF"] = S
	return faces.size() / 3


## W9.top_h ＋ 區域專屬面（C["SURF"]，沒有就等於 W9.top_h）
static func top_h(C: Dictionary, p: Vector2) -> float:
	var h := W9.top_h(C, p)
	if C.has("SURF"):
		var f: float = (C["SURF"] as RLib.TriSampler).h(p.x, p.y)
		if not is_nan(f):
			h = maxf(h, f)
	return h


## W9.ground_y（中心＋足元各點的最小值）の top_h 差し替え版
static func ground_y(C: Dictionary, it: Dictionary) -> float:
	if not C.has("SURF"):
		return W9.ground_y(C, it)
	var hs: Array = [top_h(C, it["p"])]
	for q in W9.foot(it):
		hs.append(top_h(C, q))
	return float(hs.min())


static func test_scene_path(d: String) -> String:
	return TEST_DIR + "district_%s_test.tscn" % d.to_lower()


static func work_dir(d: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("../work/district/" + d).simplify_path()


# ─────────────────────────── 資産 ───────────────────────────

static func lod0_path(id: String) -> String:
	var b: Array = P3.bundle(id, 1.0)
	if b.is_empty():
		return ""
	var p := String((b[0] as Array)[0])
	return p if ResourceLoader.exists(p) else ""


## W9／P3 で置ける資産 id（LOD0 が実在するものだけ）
static func asset_ids() -> PackedStringArray:
	P3.register_dims()
	var seen := {}
	for id: String in W9._dims:
		seen[id] = true
	for id in W9.VEG:
		seen[id] = true
	for d: Dictionary in [P3.TREES, P3.BAMBOO, P3.SHRUB2]:
		for id: String in d:
			seen[id] = true
	var out := PackedStringArray()
	for id: String in seen:
		if id == "_probe" or id.ends_with("_l1"):
			continue
		if lod0_path(id) != "":
			out.append(id)
	out.sort()
	return out


static func mesh_aabb(id: String) -> AABB:
	if not _aabb_cache.has(id):
		var m := load(lod0_path(id)) as Mesh
		_aabb_cache[id] = m.get_aabb() if m != null else AABB()
	return _aabb_cache[id]


static func collides(id: String, it: Dictionary) -> bool:
	if id == "farm_shed" or P3.TREES.has(id):
		return true
	if id in P3.NO_COLLIDE or id in W9.NO_COLLIDE or bool(it.get("hang", false)):
		return false
	return float(W9.dims(id)[4]) * float(it.get("sy", 1.0)) >= 0.35


# ─────────────────────────── manifest ↔ W9 item ───────────────────────────

static func item_xf(it: Dictionary) -> Transform3D:
	var sc := Vector3(float(it.get("sx", 1.0)), float(it.get("sy", 1.0)), float(it.get("sz", 1.0)))
	var p: Vector2 = it["p"]
	return Transform3D(Basis(Vector3.UP, float(it["yaw"])) * Basis.from_scale(sc), Vector3(p.x, float(it["y"]), p.y))


static func item_from_entry(e: Dictionary, district: String) -> Dictionary:
	var pos: Array = e["pos"]
	var sc: Array = e.get("scale", [1.0, 1.0, 1.0])
	var it := {"vid": String(e["vid"]), "id": String(e["asset"]), "p": Vector2(float(pos[0]), float(pos[2])), "y": float(pos[1]),
		"yaw": float(e.get("yaw", 0.0)), "sx": float(sc[0]), "sy": float(sc[1]), "sz": float(sc[2]),
		"mode": String(e.get("mode", "ground")), "b": String(e.get("b", "")), "cluster": String(e.get("cluster", "misc")), "zone": district,
		"who": String(e.get("who", "")), "why": String(e.get("why", "")), "kind": String(e.get("kind", "reuse")),
		"feature": String(e.get("feature", "")), "ground": String(e.get("ground", "snap"))}
	for f in e.get("flags", []):
		it[String(f)] = true
	return it


static func entry_from_item(it: Dictionary, vid: String) -> Dictionary:
	var fl: Array = []
	for f: String in FLAG_KEYS:
		if bool(it.get(f, false)):
			fl.append(f)
	var a := item_xf(it) * mesh_aabb(String(it["id"]))
	var p: Vector2 = it["p"]
	return {"vid": vid, "asset": String(it["id"]), "cluster": String(it.get("cluster", "misc")), "mode": String(it.get("mode", "ground")),
		"pos": [snappedf(p.x, 0.0001), snappedf(float(it["y"]), 0.0001), snappedf(p.y, 0.0001)], "yaw": snappedf(float(it["yaw"]), 0.000001),
		"scale": [snappedf(float(it.get("sx", 1.0)), 0.0001), snappedf(float(it.get("sy", 1.0)), 0.0001), snappedf(float(it.get("sz", 1.0)), 0.0001)],
		"aabb": aabb_arr(a), "flags": fl, "b": String(it.get("b", "")), "who": String(it.get("who", "")), "why": String(it.get("why", "")),
		"kind": String(it.get("kind", "reuse")), "feature": String(it.get("feature", "")), "ground": "fixed" if bool(it.get("hang", false)) else "snap"}


static func aabb_arr(a: AABB) -> Array:
	return [snappedf(a.position.x, 0.0001), snappedf(a.position.y, 0.0001), snappedf(a.position.z, 0.0001),
		snappedf(a.end.x, 0.0001), snappedf(a.end.y, 0.0001), snappedf(a.end.z, 0.0001)]


static func load_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return j if j is Dictionary else {}


static func file_sha256(path: String) -> String:
	return FileAccess.get_sha256(path)


# ─────────────────────────── 判定（W9 と同じ述語） ───────────────────────────

static func why_mode(it: Dictionary) -> String:
	if bool(it.get("soft", false)):
		return "soft"
	var m := String(it.get("mode", "ground"))
	return "wall" if (m == "wall" or m == "gap") else "ground"


## verify_w9p8._check と同じ：W9.why（道・建物・戸口・水・田・封存物・NPC・Hero…）＋接地
static func check(C: Dictionary, it: Dictionary) -> String:
	var w := W9.why(C, it, [], why_mode(it))
	if w != "":
		return w
	var hang := bool(it.get("hang", false))
	var gy := ground_y(C, it)
	if not hang:
		if absf(float(it["y"]) - gy) > Y_SNAP_TOL:
			return "float(%.2f vs ground %.2f)" % [float(it["y"]), gy]
	elif String(it.get("b", "")) != "":
		var fy := float((C["bld_y"] as Dictionary).get(String(it["b"]), 0.0)) + W9.FLOOR_Y
		var dy := float(it["y"]) - fy
		if dy < -0.7 or dy > 2.2:
			return "hang_height(%.2f)" % dy
	elif absf(float(it["y"]) - gy) > 0.15:
		return "hang_float(%.2f)" % (float(it["y"]) - gy)
	return ""


static func reason_key(w: String) -> String:
	if w == "":
		return "ok"
	return w.split("(")[0].split(":")[0]


## why() の走査を街區の近くだけに絞った C の浅い複製（context の大量の probe 用。判定そのものは同じ）
static func local_context(C: Dictionary, r: Rect2) -> Dictionary:
	var g := r.grow(24.0)
	var C2 := C.duplicate(false)
	C2["bld"] = (C["bld"] as Array).filter(func(b: Dictionary) -> bool: return g.has_point(b["o"]))
	C2["trunks"] = (C["trunks"] as Array).filter(func(t: Vector2) -> bool: return g.has_point(t))
	C2["npc"] = (C["npc"] as Array).filter(func(t: Vector2) -> bool: return g.has_point(t))
	C2["env_anchor"] = (C["env_anchor"] as Array).filter(func(t: Vector2) -> bool: return g.has_point(t))
	C2["npc_paths"] = (C["npc_paths"] as Array).filter(func(pts: PackedVector2Array) -> bool:
		for q in pts:
			if g.has_point(q):
				return true
		return false)
	C2["backdoor"] = (C["backdoor"] as Array).filter(func(bp: PackedVector2Array) -> bool: return g.has_point(bp[0]))
	C2["market"] = (C["market"] as Array).filter(func(m: Dictionary) -> bool: return g.has_point(m["p"]))
	return C2


# ─────────────────────────── manifest の検査 ───────────────────────────

static func schema_errors(M: Dictionary, ids: PackedStringArray) -> Array:
	var e: Array = []
	if String(M.get("format", "")) != FORMAT:
		e.append("format=%s（要 %s）" % [M.get("format", ""), FORMAT])
	if String(M.get("space", "")) != SPACE:
		e.append("space=%s（要 %s：Blender 座標のまま書かれた manifest）" % [M.get("space", ""), SPACE])
	var d := String(M.get("district", ""))
	if not DISTRICTS.has(d):
		e.append("district=%s は DISTRICTS に無い" % d)
	var items: Variant = M.get("items")
	if not (items is Array) or (items as Array).is_empty():
		e.append("items が空")
		return e
	var seen := {}
	for x: Variant in items:
		if not (x is Dictionary):
			e.append("item が Dictionary でない")
			continue
		var it: Dictionary = x
		var vid := String(it.get("vid", ""))
		if vid == "":
			e.append("vid 空")
		elif seen.has(vid):
			e.append("vid 重複 %s" % vid)
		seen[vid] = true
		if not (String(it.get("asset", "")) in ids):
			e.append("%s：asset %s は登録資産に無い（新規メッシュは Kit パイプラインで登録してから）" % [vid, it.get("asset", "")])
		var pos: Variant = it.get("pos")
		if not (pos is Array) or (pos as Array).size() != 3:
			e.append("%s：pos が [x,y,z] でない" % vid)
		var sc: Variant = it.get("scale", [1, 1, 1])
		if not (sc is Array) or (sc as Array).size() != 3 or (sc as Array).any(func(s: Variant) -> bool: return float(s) <= 0.0):
			e.append("%s：scale が正の 3 値でない" % vid)
		if not (String(it.get("mode", "ground")) in MODES):
			e.append("%s：mode %s" % [vid, it.get("mode", "")])
		if not (String(it.get("ground", "snap")) in ["snap", "fixed"]):
			e.append("%s：ground %s" % [vid, it.get("ground", "")])
		var ab: Variant = it.get("aabb")
		if not (ab is Array) or (ab as Array).size() != 6:
			e.append("%s：aabb が 6 値でない" % vid)
	return e


## Blender で量った world AABB と、同じ資産・同じ変換から Godot で再計算した world AABB の差（軸・原点・scale の換算の検査）
static func aabb_delta(e: Dictionary, district: String) -> float:
	var it := item_from_entry(e, district)
	var a := item_xf(it) * mesh_aabb(String(it["id"]))
	var g := aabb_arr(a)
	var m: Array = e["aabb"]
	var worst := 0.0
	for k in 6:
		if k == 1 or k == 4:
			continue     # 高さは build で接地し直すので比較しない（pos.y の差は別に検査）
		worst = maxf(worst, absf(float(g[k]) - float(m[k])))
	return worst


static func in_rect(e: Dictionary, r: Rect2) -> bool:
	var pos: Array = e["pos"]
	return r.has_point(Vector2(float(pos[0]), float(pos[2])))


## baseline（前の manifest）との差：vid ごとに added／removed／changed／same
static func diff(old: Dictionary, now: Dictionary) -> Dictionary:
	var a := {}
	for e: Dictionary in old.get("items", []):
		a[String(e["vid"])] = e
	var out := {"added": [], "removed": [], "changed": [], "same": []}
	var seen := {}
	for e: Dictionary in now.get("items", []):
		var vid := String(e["vid"])
		seen[vid] = true
		if not a.has(vid):
			(out["added"] as Array).append(vid)
			continue
		var o: Dictionary = a[vid]
		var same := String(o["asset"]) == String(e["asset"]) and absf(float(o["yaw"]) - float(e["yaw"])) < 1e-4
		for k in 3:
			same = same and absf(float(o["pos"][k]) - float(e["pos"][k])) < 1e-3 and absf(float(o["scale"][k]) - float(e["scale"][k])) < 1e-4
		same = same and String(o.get("mode", "")) == String(e.get("mode", "")) and str(o.get("flags", [])) == str(e.get("flags", []))
		(out["same"] if same else out["changed"]).append(vid)
	for vid: String in a:
		if not seen.has(vid):
			(out["removed"] as Array).append(vid)
	return out


# ─────────────────────────── bake（P3.bake と同じ資産・碰撞規則、街區用の節点構成） ───────────────────────────

## items（item_from_entry 済み・y は接地済み）→ overlay。節点名＝vid。meta は W9 と同じ w9_* ＋ district_*
static func bake(district: String, items: Array, manifest_sha: String) -> Node3D:
	P3.register_dims()
	var root := Node3D.new()
	root.name = node_name(district)
	var clusters := {}
	for it: Dictionary in items:
		var cl := String(it["cluster"])
		if not clusters.has(cl):
			clusters[cl] = []
		(clusters[cl] as Array).append(it)
	var names: Array = clusters.keys()
	names.sort()
	var cl_nodes := {}
	for cl: String in names:
		var c := Vector3.ZERO
		for it: Dictionary in clusters[cl]:
			c += Vector3((it["p"] as Vector2).x, float(it["y"]), (it["p"] as Vector2).y)
		c /= float((clusters[cl] as Array).size())
		var n := Node3D.new()
		n.name = cl.validate_node_name()
		n.position = c
		root.add_child(n)
		cl_nodes[cl] = n
	var col := StaticBody3D.new()
	col.name = "Collision"
	root.add_child(col)
	var meshes := {}
	var ns := 0
	for it: Dictionary in items:
		var id := String(it["id"])
		var parent: Node3D = cl_nodes[String(it["cluster"])]
		var node := Node3D.new()
		node.name = String(it["vid"]).validate_node_name()
		var yaw := float(it["yaw"])
		var sc := Vector3(float(it["sx"]), float(it["sy"]), float(it["sz"]))
		var wxf := item_xf(it)
		node.transform = parent.transform.affine_inverse() * wxf
		for k in ["who", "why", "cluster", "zone", "kind", "feature", "b", "mode"]:
			node.set_meta("w9_" + k, String(it.get(k, "")))
		node.set_meta("w9_id", id)
		var fl := PackedStringArray()
		for fk: String in FLAG_KEYS:
			if bool(it.get(fk, false)):
				fl.append(fk)
		node.set_meta("w9_flags", ",".join(fl))
		node.set_meta("district_vid", String(it["vid"]))
		node.set_meta("district_ground", String(it.get("ground", "snap")))
		parent.add_child(node)
		for lv in P3.bundle(id, sc.y):
			var path := String(lv[0])
			if not meshes.has(path):
				meshes[path] = load(path)
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % node.get_child_count()
			mi.mesh = meshes[path]
			mi.visibility_range_begin = float(lv[1])
			mi.visibility_range_end = float(lv[2])
			if not bool(lv[3]):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		# 碰撞（P3.bake と同じ規則）
		if id == "farm_shed":
			var ba := Basis(Vector3.UP, yaw)
			for sh: Array in P3.SHED_COLL:
				var bx := BoxShape3D.new()
				bx.size = Vector3(float(sh[2]) + 0.06, float(sh[3]), float(sh[2]) + 0.06)
				var cs := CollisionShape3D.new()
				cs.name = "%s_c%d" % [node.name, ns]
				cs.shape = bx
				cs.transform = Transform3D(ba, wxf.origin + ba * Vector3(float(sh[0]), float(sh[3]) * 0.5, float(sh[1])))
				col.add_child(cs)
				ns += 1
		elif P3.TREES.has(id):
			var cy := CylinderShape3D.new()
			cy.radius = float((P3.TREES[id] as Array)[1]) * sc.x * 0.9
			cy.height = 3.2
			var cs2 := CollisionShape3D.new()
			cs2.name = "%s_c" % node.name
			cs2.shape = cy
			cs2.transform = Transform3D(Basis.IDENTITY, wxf.origin + Vector3(0.0, 1.6, 0.0))
			col.add_child(cs2)
			ns += 1
		elif collides(id, it):
			var d: Array = W9.dims(id)
			var bx2 := BoxShape3D.new()
			bx2.size = Vector3((float(d[3]) - float(d[0])) * absf(sc.x), float(d[4]) * sc.y, (float(d[5]) - float(d[2])) * absf(sc.z))
			var cs3 := CollisionShape3D.new()
			cs3.name = "%s_c" % node.name
			cs3.shape = bx2
			var ba2 := Basis(Vector3.UP, yaw)
			cs3.transform = Transform3D(ba2, wxf.origin + ba2 * Vector3((float(d[0]) + float(d[3])) * 0.5 * sc.x, float(d[4]) * sc.y * 0.5, (float(d[2]) + float(d[5])) * 0.5 * sc.z))
			col.add_child(cs3)
			ns += 1
	root.set_meta("district", district)
	root.set_meta("items", items.size())
	root.set_meta("clusters", cl_nodes.size())
	root.set_meta("shapes", ns)
	root.set_meta("manifest_sha256", manifest_sha)
	root.set_meta("bake_version", BAKE_VERSION)
	root.set_meta("art_revision", "District %s（Blender 街區管線・ART_REVIEW 前）" % district)
	return root


## bake 済み overlay の item 節点（vid → Node3D）
static func overlay_nodes(own: Node) -> Dictionary:
	var out := {}
	for n in own.find_children("*", "Node3D", true, false):
		if n.has_meta("district_vid"):
			out[String(n.get_meta("district_vid"))] = n
	return out


# ─────────────────────────── 三角形の貫通（AABB は初篩だけ） ───────────────────────────

static func _world_tris(mesh: Mesh, xf: Transform3D, box: AABB) -> PackedVector3Array:
	var out := PackedVector3Array()
	var f := mesh.get_faces()
	for i in range(0, f.size(), 3):
		var a := xf * f[i]
		var b := xf * f[i + 1]
		var c := xf * f[i + 2]
		var tb := AABB(a, Vector3.ZERO).expand(b).expand(c)
		if tb.intersects(box):
			out.append(a)
			out.append(b)
			out.append(c)
	return out


## A の辺 × B の三角形、B の辺 × A の三角形（verify の壁際 probe と同じ考え方）。戻り値＝交差数（max_hits で打ち切り）
static func tri_hits(ma: Mesh, xa: Transform3D, mb: Mesh, xb: Transform3D, max_hits := 4) -> int:
	var box := (xa * ma.get_aabb()).intersection(xb * mb.get_aabb())
	if box.size == Vector3.ZERO or not box.has_volume():
		return 0
	var ta := _world_tris(ma, xa, box.grow(0.01))
	var tb := _world_tris(mb, xb, box.grow(0.01))
	if ta.is_empty() or tb.is_empty():
		return 0
	var hits := 0
	for pair in [[ta, tb], [tb, ta]]:
		var E: PackedVector3Array = pair[0]
		var T: PackedVector3Array = pair[1]
		for i in range(0, E.size(), 3):
			for k in 3:
				var p0 := E[i + k]
				var p1 := E[i + (k + 1) % 3]
				for j in range(0, T.size(), 3):
					if Geometry3D.segment_intersects_triangle(p0, p1, T[j], T[j + 1], T[j + 2]) != null:
						hits += 1
						if hits >= max_hits:
							return hits
	return hits
