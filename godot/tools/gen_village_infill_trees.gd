extends SceneTree
## 人間之里村內補樹：在街廓「建物之間／屋後」的空隙種可單獨選取的樹實例。
## 產出 res://maps/slice/gen/village_infill_trees.tscn，於 slice.tscn 掛一個節點。
##
## 規則（與 gen_village_trees.gd 的村緣林分工，不重疊）：
##  - 只種在障礙格網淨空 3..7 格（6..14 m）的縫隙：太窄種不下、太寬是田或
##    廣場（village 東側水田、南側空地），不該亂插樹。
##  - 主街走廊 x 232..242 全段排除——那是動線與構圖主軸。
##  - 鳥居借景走廊 SIGHT 排除。
##  - 每棵向下射線取真實地面（只打地面層 bit32），取不到就跳過。
##  - 向上射線檢查頭頂無屋簷，避免樹穿屋頂。
##  - 節點是 GLB 實例（可單獨選取），不是 MultiMesh。
##   Godot --path godot --script tools/gen_village_infill_trees.gd -- [--dry]

const OUT_SCENE := "res://maps/slice/gen/village_infill_trees.tscn"
const SRC := "res://assets/landscape/"

const CELL := 2.0
const X0 := 196.0
const X1 := 280.0
const Z0 := -90.0
const Z1 := 130.0

## 樹種：檔名、目標實高(m)、株數、彼此最小間距(m)、需要的淨空半徑(格)
## 實測（probe_village_gap_hist.gd）街廓內可用空地的淨空分布：
##   clr2(4m)=407 格  clr3(6m)=186  clr4(8m)=71  clr5(10m)=11
## 街廓是密集町家，沒有種杉木的餘裕——大樹只會穿屋頂。所以：
##   大株（櫻花/普通樹）只放 clr>=4 的少數幾處院子與辻；
##   小株（盆樹）填 clr2..3 的屋間與軒下。
# ⚠ 2026-09-17 使用者裁定：櫻花樹／楓樹／普通樹／2大衫／針葉林樹4 底部有土台底座，
#   全面下架。原配額由底部乾淨的樹種承接（鎮守之杜、針葉樹1）。
#   下架清單勿再加回，否則重跑生成會讓髒底樹長回來。
const SPECIES: Array = [
	{"file": "鎮守之杜.glb", "h": 7.0,  "n": 8,  "gap": 16.0, "clr": 4, "sv": 0.14, "seed": 7303},
	{"file": "針葉樹1.glb",  "h": 6.0,  "n": 10, "gap": 9.0,  "clr": 3, "sv": 0.18, "seed": 7302},
	{"file": "盆樹.glb",     "h": 3.0,  "n": 34, "gap": 6.0,  "clr": 2, "sv": 0.22, "seed": 7301},
]

const MAIN_ST := Rect2(232.0, -90.0, 10.0, 220.0)   # 主街動線
const SIGHT := Rect2(213.0, 94.0, 44.0, 172.0)      # 鳥居借景走廊
const CANAL := Rect2(277.0, -226.0, 20.0, 462.0)
const MAX_CLR := 7          # 超過這個淨空視為田／廣場，不種
const GROUND_MASK := 1 << 31

var _space: PhysicsDirectSpaceState3D = null
var _occ: Array = []
var _nx := 0
var _nz := 0
var _placed: Array = []
var _skip_ground := 0
var _skip_roof := 0

const SKIP_NODES := ["Terrain", "UnifiedGround", "GroundUnderlay", "BasinHills",
	"EastRiverWater", "EastRiverRevetment", "Shrubs", "Ferns", "GrassTall",
	"GrassFlower", "RiverVegetation", "VillageTrees", "VillageTrees2", "Vista"]


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	var dry := "--dry" in OS.get_cmdline_user_args()
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "trail")
	await _wait(90)
	_space = main.get_viewport().world_3d.direct_space_state
	var slice: Node = _find_slice(main)
	if slice == null:
		push_error("找不到 slice 場景根")
		quit(1)
		return
	_build_occupancy(slice)
	_seed_existing_trees(slice)

	var out := Node3D.new()
	out.name = "VillageInfillTrees"
	var total := 0
	for sp in SPECIES:
		total += _build(out, sp, dry)
	print("SKIP ground=%d roof=%d" % [_skip_ground, _skip_roof])
	print("INFILL total=%d 棵" % total)

	if dry:
		print("DRY RUN — 未寫檔")
		quit()
		return
	var ps := PackedScene.new()
	var err := ps.pack(out)
	if err == OK:
		err = ResourceSaver.save(ps, OUT_SCENE)
	print("SAVE %s err=%d" % [OUT_SCENE, err])
	quit(0 if err == OK else 1)


func _find_slice(n: Node) -> Node:
	if String(n.name) == "slice":
		return n
	for c in n.get_children():
		var r := _find_slice(c)
		if r != null:
			return r
	return null


## 把建物等障礙投影到 XZ 格網。
func _build_occupancy(slice: Node) -> void:
	_nx = int((X1 - X0) / CELL)
	_nz = int((Z1 - Z0) / CELL)
	_occ.resize(_nx * _nz)
	_occ.fill(false)
	var blockers := 0
	for top in slice.get_children():
		if String(top.name) in SKIP_NODES:
			continue
		for mi in _meshes(top):
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			if b.size.y < 0.8:
				continue
			blockers += 1
			for gx in range(maxi(int(floor((b.position.x - X0) / CELL)), 0),
					mini(int(floor((b.position.x + b.size.x - X0) / CELL)) + 1, _nx)):
				for gz in range(maxi(int(floor((b.position.z - Z0) / CELL)), 0),
						mini(int(floor((b.position.z + b.size.z - Z0) / CELL)) + 1, _nz)):
					_occ[gz * _nx + gx] = true
	print("OCC blockers=%d grid %dx%d" % [blockers, _nx, _nz])


## 既有的村緣樹（MultiMesh）也要納入間距判斷，避免新樹長在舊樹裡。
func _seed_existing_trees(slice: Node) -> void:
	var n := 0
	for mmi in _multimeshes(slice):
		# 只收樹（Trees_*），草/蕨/灌木的 MultiMesh 有 13 萬棵，
		# 全丟進間距集合會讓 _too_close 慢到不可用，而且草不擋樹。
		if not String(mmi.name).begins_with("Trees_"):
			continue
		var mm: MultiMesh = mmi.multimesh
		if mm == null:
			continue
		for i in mm.instance_count:
			var o: Vector3 = mmi.global_transform * mm.get_instance_transform(i).origin
			_placed.append([Vector2(o.x, o.z), 6.0])
			n += 1
	print("EXIST 既有樹 %d 棵納入間距" % n)


func _clearance(gx: int, gz: int, cap: int) -> int:
	for r in range(1, cap + 1):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var x := gx + dx
				var z := gz + dz
				if x < 0 or z < 0 or x >= _nx or z >= _nz:
					return r - 1
				if _occ[z * _nx + x]:
					return r - 1
	return cap


func _blocked(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	return MAIN_ST.has_point(p) or SIGHT.has_point(p) or CANAL.has_point(p)


func _too_close(x: float, z: float, gap: float) -> bool:
	for p in _placed:
		var pv: Vector2 = p[0]
		if Vector2(x - pv.x, z - pv.y).length() < maxf(gap, p[1]):
			return true
	return false


func _ground_y(x: float, z: float) -> float:
	if _space == null:
		return NAN
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, 400.0, z), Vector3(x, -400.0, z), GROUND_MASK)
	var hit: Dictionary = _space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	return (hit.position as Vector3).y


## 頭頂淨空：從地面往上打，撞到東西（屋簷）就不種。
func _headroom(x: float, y: float, z: float, need: float) -> bool:
	if _space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, y + 0.5, z), Vector3(x, y + need, z), 1)
	return _space.intersect_ray(q).is_empty()


func _build(parent: Node3D, sp: Dictionary, dry: bool) -> int:
	var scn: PackedScene = load(SRC + sp["file"])
	if scn == null:
		push_error("load failed " + sp["file"])
		return 0
	var probe := scn.instantiate() as Node3D
	var bb := _aabb_of(probe)
	probe.free()
	var base_scale: float = float(sp["h"]) / maxf(bb.size.y, 0.0001)

	var rng := RandomNumberGenerator.new()
	rng.seed = sp["seed"]
	var placed := 0
	var tries := 0
	while placed < int(sp["n"]) and tries < 40000:
		tries += 1
		var gx := rng.randi_range(1, _nx - 2)
		var gz := rng.randi_range(1, _nz - 2)
		if _occ[gz * _nx + gx]:
			continue
		var clr := _clearance(gx, gz, MAX_CLR + 1)
		if clr < int(sp["clr"]) or clr > MAX_CLR:
			continue
		var x: float = X0 + gx * CELL + rng.randf_range(0.2, CELL - 0.2)
		var z: float = Z0 + gz * CELL + rng.randf_range(0.2, CELL - 0.2)
		if _blocked(x, z):
			continue
		if _too_close(x, z, float(sp["gap"])):
			continue
		var gy := _ground_y(x, z)
		if is_nan(gy):
			_skip_ground += 1
			continue
		if not _headroom(x, gy, z, float(sp["h"]) * 0.75):
			_skip_roof += 1
			continue
		_placed.append([Vector2(x, z), float(sp["gap"])])
		placed += 1
		if dry:
			continue
		var inst := scn.instantiate() as Node3D
		inst.name = "%s_%02d" % [sp["file"].get_basename(), placed]
		parent.add_child(inst)
		inst.owner = parent
		inst.scene_file_path = SRC + sp["file"]
		var s: float = base_scale * (1.0 + rng.randf_range(-float(sp["sv"]), float(sp["sv"])))
		var b := Basis.IDENTITY.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		b = b.scaled(Vector3(s, s, s))
		# GLB 原點是 BASE（min.y=0），底邊直接落地面，再埋 0.08 m 消縫。
		inst.transform = Transform3D(b, Vector3(x, gy - 0.08 - bb.position.y * s, z))
	print("PLACE %-10s %d/%d (tries=%d, scale=%.3f)"
		% [sp["file"], placed, sp["n"], tries, base_scale])
	return placed


func _aabb_of(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(n):
		var b: AABB = mi.mesh.get_aabb()
		var p: Node = mi
		var xf := Transform3D.IDENTITY
		while p != null and p != n:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		b = xf * b
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _multimeshes(n: Node) -> Array:
	var out: Array = []
	if n is MultiMeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_multimeshes(c))
	return out
