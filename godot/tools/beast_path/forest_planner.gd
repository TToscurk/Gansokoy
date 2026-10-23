extends RefCounted
## 獸道 森林規劃器（V0.1；V1.2 改成「分區獨立亂數＋S01–S03 凍結」）：只產生「擺放資料」，不建節點。
## 樹／灌木／竹一律重用人間之里 V2 已核准的 veg_kit／bamboo_kit prefab（不另做樹）。
##
## 設計重點（規格書「植被分布：樹種混合、不等距、不規則疏密」「自然分群與林隙」）：
##   1. 密度＝場景基準（跨場景邊界平滑過渡）× 低頻群落雜訊（群與林隙）× 林帶加權（stands）× 路緣疏化。
##   2. 樹種＝場景樹種比例 × 林帶偏好 × 邊緣幼樹；每種樹有多個變體（不只旋轉縮放同一個）。
##   3. 禁區：主路／支線／溪／鋪石／空地（clearings）／BOSS 圓／道具佔位／陡坡。
##   4. 釘點（pins）精確擺放：門樹、抓痕樹、古木、注連繩雙杉、櫻群、楓。
##   5. 同 seed 同結果（layout.forest.seed）。
##
## V1.2 E（共用亂數問題）：
##   V1.1 以前只有一條亂數序列、全圖格子一起洗牌；任何一區的「被禁區擋掉／被樹距擋掉」結果一變，
##   後面所有格子的抽樣都跟著位移 → 改 S04 會把 S01–S03 的樹全部重抽（實測 86% 位置不同）。
##   現在：(a) 每區用自己的亂數序列（種子＝layout seed ⊕ 區名 FNV-1a），固定順序 S01→S04，
##   一區的任何規則變動不會影響其他區；(b) layout.forest.freeze 指向的凍結檔（V0.1 使用者審過的 S01–S03 擺放，
##   含場景存檔的 transform）原樣載入，不重新抽樣；凍結檔雜湊對不上就拒絕（freeze_error）。

const BPLib := preload("res://tools/beast_path/bp_lib.gd")
const S01Forest := preload("res://tools/beast_path/s01_forest.gd")      # S01 R1：S01 候選規劃（只管 S01；S02／S03／S04 不經過它）

const VEG_DIR := "res://assets/village_v2/veg_kit/trees/"
const BAM_DIR := "res://assets/village_v2/bamboo_kit/trees/"
const VEG_SRC := "res://assets/village_v2/veg_kit/src/modules_blender.json"
const BAM_SRC := "res://assets/village_v2/bamboo_kit/src/modules_blender.json"

## 樹種 → 變體（權重）、縮放範圍、最小樹距、是否佔路（碰撞用）
const SPECIES := {
	"cedar": {"v": {"sugi_a": 0.36, "sugi_b": 0.24, "sugi_c": 0.28, "hinoki_a": 0.06, "hinoki_b": 0.06}, "s": [0.82, 1.16], "gap": 3.2},
	"broadleaf": {"v": {"keyaki_a": 0.2, "konara_a": 0.26, "konara_b": 0.2, "shii_a": 0.2, "enoki_a": 0.14}, "s": [0.85, 1.22], "gap": 3.8},
	"maple": {"v": {"momiji_a": 0.3, "momiji_b": 0.4, "momiji_c": 0.3}, "s": [0.9, 1.3], "gap": 3.0},
	"cherry": {"v": {"sakura_somei": 0.4, "sakura_yama": 0.35, "sakura_shidare": 0.25}, "s": [0.82, 1.1], "gap": 3.6},
	"sapling": {"v": {"young_broad_a": 0.36, "young_broad_b": 0.34, "young_sugi": 0.3}, "s": [0.8, 1.3], "gap": 1.9},
}
const UNDER := {"shrub_a": 0.34, "tsutsuji_a": 0.2, "fern_a": 0.34, "sasa_a": 0.12}
const BAMBOO := {"take_mature": 0.34, "take_thick": 0.16, "take_thin": 0.2, "take_young": 0.14, "take_lean": 0.08, "take_broken": 0.05, "take_dead": 0.03}
const BAMBOO_MULT := 3.0           # layout 的 density 是「叢」；竹林要讀起來像林，視覺密度乘 3（白模調整，見報告）

const ZONES := ["S01", "S02", "S03", "S04"]

var lib: BPLib
var kit: Dictionary = {}            # id → {h, r, ymin, group, kit: "veg"|"bam"}
var trees: Array = []               # [{id, x, z, y, s, yaw, r, scene, kind, pin, (xf, frozen)}]
var claw_marks: Array = []          # [{p: Vector3(base), r, yaw}]
var stats: Dictionary = {}
var freeze_error := ""              # 非空＝凍結檔壞了／雜湊對不上（產生器看到就中止）
var frozen_scenes: Array = []       # 實際凍結的區
var _frozen: Dictionary = {}        # scene → Array[Dictionary]（V0.1 的擺放，含 xf）
## V1.3：S04＝V1.2 凍結（layout.forest.freeze_s04）。逐棵原樣載入；只有和 V1.3 局部修改衝突的才動（見 _adopt_v12_s04）
var _frozen_s04: Array = []
var s04_kept := 0
var s04_reground: Array = []         # [{id, x, z, dy}]
var s04_dropped: Array = []          # [{id, x, z, why}]
var drop_boxes: Array = []           # generator 給：崖面岩塊的世界 AABB（樹幹撞到就剔除）
var s01_info: Dictionary = {}        # S01 R1：候選規劃的統計（模式、分帶數量、被剔除數…）
var s01_wall: Dictionary = {}        # S01 R2：谷壁點綴（岩露頭／碎石／土袋／露根；s01_wall.gd 規劃，生成器建造）
var _hist_s01: Array = []            # S01 R1：V0.1 凍結檔的 S01（380 筆，歷史基準；候選的『重播』與背景林帶來源）
var _zone := ""                     # 正在規劃的區

var _rng := RandomNumberGenerator.new()
var _n1 := FastNoiseLite.new()
var _n2 := FastNoiseLite.new()
var _n3 := FastNoiseLite.new()
var _hash: Dictionary = {}          # 4 m 格 → Array[idx into _placed]
var _placed: Array = []             # [{p, r, gap}]
var _fp_hash: Dictionary = {}
var _clear: Array = []              # [{c, r, id}]
var _stands: Array = []
var _fcfg: Dictionary = {}
var _foot: Array = []
var _landmark := Vector2(1e9, 1e9)
var _bamboo_zones: Array = []
var _nclr := FastNoiseLite.new()    # V1.2：空地邊界的方位角噪聲（讓 BOSS 空地不是正圓）


func setup(lib_: BPLib, footprints: Array) -> void:
	lib = lib_
	_fcfg = (lib.L["forest"] as Dictionary).duplicate(true)
	_foot = footprints
	_rng.seed = int(_fcfg["seed"])
	_n1.seed = int(_fcfg["seed"]) + 1
	_n1.frequency = 0.016
	_n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n2.seed = int(_fcfg["seed"]) + 2
	_n2.frequency = 0.045
	_n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n3.seed = int(_fcfg["seed"]) + 3
	_n3.frequency = 0.11
	_n3.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_load_kit(VEG_SRC, "veg")
	_load_kit(BAM_SRC, "bam")
	_nclr.seed = int(_fcfg["seed"]) + 55
	_nclr.frequency = 1.0
	_nclr.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_clear.clear()
	for c: Dictionary in _fcfg["clearings"]:
		var ce := {"id": c["id"], "c": _pt(c["c"]), "r": float(c["r"])}
		if c.has("wobble"):
			ce["wob"] = c["wobble"]
		_clear.append(ce)
	_bamboo_zones.clear()
	for z: Dictionary in _fcfg["bamboo_zones"]:
		_bamboo_zones.append({"c": _pt(z["c"]), "r": float(z["r"])})
	_stands.clear()
	for s: Dictionary in _fcfg["stands"]:
		_stands.append({"id": s["id"], "c": _pt(s["c"]), "r": float(s["r"]), "sp": String(s["species"]), "boost": float(s["boost"])})
	for i in _foot.size():
		var f: Dictionary = _foot[i]
		var key := _cell(f["p"], 6.0)
		if not _fp_hash.has(key):
			_fp_hash[key] = []
		(_fp_hash[key] as Array).append(i)


func _load_kit(path: String, which: String) -> void:
	var src: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (src is Dictionary):
		push_error("讀不到 %s" % path)
		return
	for tid: String in (src as Dictionary)["trees"]:
		var info: Dictionary = (src as Dictionary)["trees"][tid]
		var a0: Array = info["lods"][0]["aabb"]
		var col: Array = info.get("collision", [])
		kit[tid] = {"h": float(a0[1][1]) - float(a0[0][1]), "ymin": float(a0[0][1]), "r": float(col[0]["r"]) if not col.is_empty() else 0.0,
			"group": String(info.get("group", "")), "kit": which, "wx": float(a0[1][0]) - float(a0[0][0])}


func scene_path(tid: String) -> String:
	return (VEG_DIR if String(kit[tid]["kit"]) == "veg" else BAM_DIR) + tid + ".tscn"


func _pt(c: Variant) -> Vector2:
	if c is Array:
		return Vector2(float(c[0]), float(c[1]))
	return lib.resolve(c as Dictionary)["p"]


func _cell(p: Vector2, sz: float) -> Vector2i:
	return Vector2i(int(floor(p.x / sz)), int(floor(p.y / sz)))


# ---------------------------------------------------------------- 場景基準密度
func _scene_base(z: float) -> float:
	var dens: Dictionary = _fcfg["density_per_100m2"]
	var ids: Array = ZONES.duplicate()
	if _zone != "":
		# V1.2：內插只看「自己和更靠前的區」→ 後面的區（例如 S04）改密度，不會牽動這區的樹
		ids = ZONES.slice(0, ZONES.find(_zone) + 1)
	var bounds: Array = []
	for id: String in ids:
		for r: Dictionary in lib.rects:
			if String(r["id"]) == id:
				bounds.append((r["rect"] as Rect2))
	# 場景中心 z 之間做 smoothstep 內插 → 無階梯
	var mids: Array = []
	for b: Rect2 in bounds:
		mids.append(b.position.y + b.size.y * 0.5)
	if z >= mids[0]:
		return float(dens[ids[0]])
	for i in range(1, ids.size()):
		if z >= mids[i]:
			var u := smoothstep(0.0, 1.0, (z - mids[i]) / (mids[i - 1] - mids[i]))
			return lerpf(float(dens[ids[i]]), float(dens[ids[i - 1]]), u)
	return float(dens[ids[ids.size() - 1]])


func _scene_key(p: Vector2) -> String:
	var sdf := lib.mask_sdf(p)
	if sdf > 4.0:
		return "wall"
	return lib.scene_id_of_z(p.y)


func _stand_f(p: Vector2, sp: String = "") -> float:
	var best := 0.0
	for s: Dictionary in _stands:
		if sp != "" and String(s["sp"]) != sp:
			continue
		var d := p.distance_to(s["c"])
		if d < float(s["r"]):
			var t := 1.0 - (d / float(s["r"])) * (d / float(s["r"]))
			best = maxf(best, t * t)
	return best


## 空地的有效半徑。V1.2：layout 的空地可帶 wobble {amp, min, k1, k2}——半徑隨方位角起伏（林舌伸進來、林緣退開），
## 但不會小於 min（戰鬥圓 r=22 之外留的最小淨空）。方位角相依，所以空地邊界是不規則的瓣狀，不是正圓。
func clear_radius(c: Dictionary, p: Vector2) -> float:
	var r0 := float(c["r"])
	if not c.has("wob"):
		return r0
	var w: Dictionary = c["wob"]
	var d: Vector2 = p - (c["c"] as Vector2)
	var th := atan2(d.x, -d.y)
	var k1 := float(w.get("k1", 1.6))
	var k2 := float(w.get("k2", 3.9))
	var n := 0.62 * _nclr.get_noise_2d(cos(th) * k1 + 5.0, sin(th) * k1 - 2.0) + 0.38 * _nclr.get_noise_2d(cos(th) * k2 - 9.0, sin(th) * k2 + 4.0)
	return maxf(r0 + float(w["amp"]) * n * 1.6, float(w["min"]))


func _clear_dist(p: Vector2) -> float:
	var best := 1e9
	for c: Dictionary in _clear:
		best = minf(best, p.distance_to(c["c"]) - clear_radius(c, p))
	return best


# ---------------------------------------------------------------- 禁區
func _blocked(p: Vector2, rt: float, loose: bool = false) -> bool:
	var x := p.x
	var z := p.y
	if x < -107.0 or x > 107.0 or z < -487.0 or z > 27.0:
		return true
	var dmain := lib.sample_arr(lib.DM, x, z)
	var hw := lib.sample_arr(lib.WM, x, z)
	var ncfg: Dictionary = _fcfg["near_path"]
	if dmain < hw + float(ncfg["clear_extra"]) + rt:
		return true
	if lib.sample_arr(lib.DB, x, z) < float(_fcfg["branch_clear_extra"]) + rt:
		return true
	if lib.sample_arr(lib.DS, x, z) < 1.4 + rt:
		return true
	if lib.sample_arr(lib.PV, x, z) > 0.12:
		return true
	# V1.1：BOSS 戰鬥圓與破鳥居高台不再是「鋪石」（PV＝0），改用明確的圓禁區——否則 loose 模式的林下會長進戰鬥圓
	for t: Dictionary in lib._terraces:
		var tid := String(t["id"])
		if (tid == "boss_floor" or tid == "torii_broken_platform") and p.distance_to(t["c"] as Vector2) < float(t["r"]) + 0.4 + rt:
			return true
	if _clear_dist(p) < 0.0 and not loose:
		return true
	if lib.slope_deg_at(x, z) > 50.0:
		return true
	# 道具佔位
	var k := _cell(p, 6.0)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(k.x + dx, k.y + dz)
			if _fp_hash.has(key):
				for i: int in _fp_hash[key]:
					var f: Dictionary = _foot[i]
					if p.distance_to(f["p"]) < float(f["r"]) + rt:
						return true
	return false


## layer：t＝樹（含釘點／地標／枯木）、b＝竹、u＝林下。
##   樹↔樹：max(兩者 gap)；竹↔竹：0.9 m；林下↔林下：0.75 m；
##   樹幹只擋竹／林下到「樹幹半徑＋0.45 m」（不能把樹距 3~4 m 硬套在灌木上）。
func _too_close(p: Vector2, gap: float, layer: String = "t", self_r: float = 0.0) -> bool:
	var k := _cell(p, 4.0)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var key := Vector2i(k.x + dx, k.y + dz)
			if not _hash.has(key):
				continue
			for i: int in _hash[key]:
				var q: Dictionary = _placed[i]
				var d := p.distance_to(q["p"])
				var ql := String(q["layer"])
				if layer == "t":
					if ql == "t":
						if d < maxf(gap, float(q["gap"])):
							return true
					elif d < self_r + 0.4:
						return true
				elif ql == "t":
					if d < float(q["r"]) + 0.45:
						return true
				elif ql == layer:
					if d < gap:
						return true
				elif d < 0.4:
					return true
	return false


func _register(p: Vector2, r: float, gap: float, layer: String = "t") -> void:
	_placed.append({"p": p, "r": r, "gap": gap, "layer": layer})
	var key := _cell(p, 4.0)
	if not _hash.has(key):
		_hash[key] = []
	(_hash[key] as Array).append(_placed.size() - 1)


# ---------------------------------------------------------------- 取樣
func _wpick(weights: Dictionary) -> String:
	var tot := 0.0
	for k: String in weights:
		tot += float(weights[k])
	var r := _rng.randf() * tot
	for k: String in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return String(weights.keys()[0])


func _species_weights(key: String, p: Vector2) -> Dictionary:
	var mix: Dictionary = (_fcfg["species_mix"] as Dictionary)[key]
	var w := {}
	for sp: String in mix:
		w[sp] = float(mix[sp])
	for s: Dictionary in _stands:
		var d := p.distance_to(s["c"])
		if d < float(s["r"]):
			var t := 1.0 - (d / float(s["r"])) * (d / float(s["r"]))
			var sp := String(s["sp"])
			if w.has(sp):
				w[sp] = float(w[sp]) * (1.0 + 3.0 * (float(s["boost"]) - 1.0) * t * t)
			else:
				w[sp] = 0.05 * (1.0 + 3.0 * (float(s["boost"]) - 1.0) * t * t)
	if w.has("maple") and p.distance_to(_landmark) < 18.0:
		w["maple"] = float(w["maple"]) * 0.12
	# 林緣（空地邊 8 m 內）幼樹偏多
	var cd := _clear_dist(p)
	if cd > 0.0 and cd < 8.0 and w.has("sapling"):
		w["sapling"] = float(w["sapling"]) * 2.4
	return w


func _density(p: Vector2, key: String) -> float:
	var dens: Dictionary = _fcfg["density_per_100m2"]
	var wall := float(dens["wall"])
	var base := _scene_base(p.y)
	var sdf := lib.mask_sdf(p)
	var d := lerpf(base, wall, smoothstep(-8.0, 8.0, sdf))
	# 群與林隙
	var g := 1.0 + 0.95 * _n1.get_noise_2d(p.x, p.y) + 0.55 * _n2.get_noise_2d(p.x, p.y) + 0.22 * _n3.get_noise_2d(p.x, p.y)
	g = clampf(g, 0.05, 2.4)
	g = pow(g, 1.25)
	d *= g
	# 林帶
	var sf := _stand_f(p)
	var boost := 1.0
	for s: Dictionary in _stands:
		var dd := p.distance_to(s["c"])
		if dd < float(s["r"]):
			var t := 1.0 - (dd / float(s["r"])) * (dd / float(s["r"]))
			boost = maxf(boost, 1.0 + 0.6 * (float(s["boost"]) - 1.0) * t * t)
	d *= boost
	# 路緣疏化
	var ncfg: Dictionary = _fcfg["near_path"]
	var dmain := lib.sample_arr(lib.DM, p.x, p.y)
	var hw := lib.sample_arr(lib.WM, p.x, p.y)
	var edge := dmain - hw
	if edge < float(ncfg["thin_within"]):
		var keep := lerpf(float(ncfg["keep"]), 0.9, sf)
		d *= lerpf(keep, 1.0, smoothstep(float(ncfg["clear_extra"]), float(ncfg["thin_within"]), edge))
	# 空地邊緣漸淡
	var cd := _clear_dist(p)
	if cd < 5.0:
		d *= smoothstep(0.0, 5.0, cd) * 0.85 + 0.15
	return d


func _in_bamboo(p: Vector2) -> bool:
	for z: Dictionary in _bamboo_zones:
		if p.distance_to(z["c"]) < float(z["r"]) * 0.88:
			return true
	return false


func _kit_h(id: String) -> float:
	return float((kit[id] as Dictionary)["h"])


func _add_tree(id: String, p: Vector2, s: float, yaw: float, kind: String, pin: String = "") -> void:
	var k: Dictionary = kit[id]
	var slope := lib.slope_deg_at(p.x, p.y)
	var y := lib.h_at(p.x, p.y) - 0.05 - 0.012 * slope
	trees.append({"id": id, "x": p.x, "z": p.y, "y": y, "s": s, "yaw": yaw, "r": float(k["r"]) * s, "scene": lib.scene_id_of_z(p.y), "kind": kind, "pin": pin})


## ---------------------------------------------------------------- 分區亂數／凍結
## FNV-1a（32 bit）：同 seed、同區名 → 同序列；改別區不影響這區
func zone_seed(sc: String) -> int:
	var h := 2166136261
	for b: int in sc.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return (int(_fcfg["seed"]) * 1000003 + h) & 0x7FFFFFFF


## 驗證器用：關掉凍結（測「不靠凍結檔、純靠分區亂數」時各區是否互不影響）
func set_freeze(on: bool) -> void:
	var fz: Dictionary = _fcfg.get("freeze", {})
	fz["enabled"] = on
	_fcfg["freeze"] = fz
	# V1.3：S04＝V1.2 凍結也一起關（否則擾動 S04 規則時 S04 不會變，對照組失效）
	var fz4: Dictionary = _fcfg.get("freeze_s04", {})
	if not fz4.is_empty():
		fz4["enabled"] = on
		_fcfg["freeze_s04"] = fz4


## 驗證器用：只擾動 S04 的規則（加一塊空地、把密度拉高）→ 其他區的結果必須一點都不變
func perturb_s04() -> void:
	var cl: Array = _fcfg["clearings"]
	cl.append({"id": "_perturb", "c": [-30.0, -420.0], "r": 9.0})
	(_fcfg["density_per_100m2"] as Dictionary)["S04"] = float((_fcfg["density_per_100m2"] as Dictionary)["S04"]) * 1.35
	_clear.append({"id": "_perturb", "c": Vector2(-30.0, -420.0), "r": 9.0})


func _load_frozen() -> void:
	_frozen.clear()
	frozen_scenes.clear()
	freeze_error = ""
	_frozen_s04.clear()
	_load_frozen_s04()
	if freeze_error != "":
		return
	var fz: Dictionary = _fcfg.get("freeze", {})
	if fz.is_empty() or not bool(fz.get("enabled", true)):
		return
	var path := String(fz["file"])
	if not FileAccess.file_exists(path):
		freeze_error = "凍結檔不存在：%s" % path
		return
	var sha := FileAccess.get_sha256(path)
	if sha != String(fz["sha256"]):
		freeze_error = "凍結檔雜湊對不上：%s（layout 記 %s，實際 %s）" % [path, String(fz["sha256"]), sha]
		return
	var src: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (src is Dictionary) or not (src as Dictionary).has("scenes"):
		freeze_error = "凍結檔格式不對：%s" % path
		return
	var sc: Dictionary = (src as Dictionary)["scenes"]
	for id: String in fz["scenes"]:
		if not sc.has(id):
			freeze_error = "凍結檔缺 %s" % id
			return
		_frozen[id] = sc[id]
		frozen_scenes.append(id)


## V1.3：S04 森林＝V1.2 凍結檔。雜湊對不上就拒絕（同 S01–S03 的規則）。
func _load_frozen_s04() -> void:
	var fz: Dictionary = _fcfg.get("freeze_s04", {})
	if fz.is_empty() or not bool(fz.get("enabled", true)):
		return
	var path := String(fz["file"])
	if not FileAccess.file_exists(path):
		freeze_error = "S04 凍結檔不存在：%s" % path
		return
	var sha := FileAccess.get_sha256(path)
	if sha != String(fz["sha256"]):
		freeze_error = "S04 凍結檔雜湊對不上：%s（layout 記 %s，實際 %s）" % [path, String(fz["sha256"]), sha]
		return
	var src: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (src is Dictionary) or not ((src as Dictionary).get("scenes", {}) as Dictionary).has("S04"):
		freeze_error = "S04 凍結檔格式不對：%s" % path
		return
	_frozen_s04 = (src as Dictionary)["scenes"]["S04"]


## V1.3：V1.2 的 S04 擺放原樣載入（場景存檔的 transform，逐位元同 V1.2），只有和 V1.3 局部修改衝突的才動：
##   · 落點地面高度變了（崖頂河道重挖）→ 只改 y（重新落地）；
##   · 落進禁區（新的崖口岩腳、河道、陡坡…同一套 _blocked 規則）或樹幹撞到崖面岩塊 → 剔除；
##   · 不補新樹（補樹＝重抽樣 → 整區的抽樣序列連鎖改變，等於把 V1.2 的配置打掉）。
##   釘點（門樹、注連繩雙杉、古楓…）位置由 layout 決定，只會重新落地、不剔除。
func _adopt_v12_s04() -> void:
	s04_kept = 0
	s04_reground.clear()
	s04_dropped.clear()
	for e: Dictionary in _frozen_s04:
		var id := String(e["id"])
		if not kit.has(id):
			freeze_error = "S04 凍結檔的樹 %s 不在 veg_kit／bamboo_kit 裡" % id
			return
		var k: Dictionary = kit[id]
		var s := float(e["s"])
		var xf: Array = (e["xf"] as Array).duplicate()
		var px := float(xf[9])
		var pz := float(xf[11])
		var py := float(xf[10])
		var kind := String(e["kind"])
		var rr := float(k["r"]) * s
		var p := Vector2(px, pz)
		var why := ""
		match kind:
			"tree": why = "禁區" if _blocked(p, rr) else ""
			"bamboo", "under": why = "禁區" if _blocked(p, 0.1, true) else ""
			"dead": why = "禁區" if _blocked(p, 0.3) else ""
		if why == "" and kind != "bamboo" and kind != "under":
			for bx: AABB in drop_boxes:
				var g := bx.grow(rr + 0.15)
				if g.has_point(Vector3(px, py + 0.6, pz)) or g.has_point(Vector3(px, py + 2.5, pz)):
					why = "崖面岩塊"
					break
		if why != "" and kind != "pin" and kind != "landmark":
			s04_dropped.append({"id": id, "x": snappedf(px, 0.01), "z": snappedf(pz, 0.01), "why": why})
			continue
		var ny := lib.h_at(px, pz) - 0.05 - 0.012 * lib.slope_deg_at(px, pz)
		if absf(ny - py) > 0.02:
			s04_reground.append({"id": id, "x": snappedf(px, 0.01), "z": snappedf(pz, 0.01), "dy": snappedf(ny - py, 0.001)})
			py = ny
			xf[10] = ny
		else:
			s04_kept += 1
		trees.append({"id": id, "x": px, "z": pz, "y": py, "s": s, "yaw": float(e["yaw"]), "r": rr,
			"scene": "S04", "kind": kind, "pin": String(e["pin"]), "xf": xf, "frozen": true})
		match kind:
			"pin": _register(p, rr, 3.0 + rr * 2.0)
			"landmark": _register(p, rr, 4.5)
			"tree": _register(p, rr, _species_gap(id), "t")
			"bamboo": _register(p, 0.05, 0.9, "b")
			"under": _register(p, 0.05, 0.75, "u")
			"dead": _register(p, 0.3, 3.5, "t")


func _species_gap(id: String) -> float:
	for sp: String in SPECIES:
		if (SPECIES[sp]["v"] as Dictionary).has(id):
			return float(SPECIES[sp]["gap"])
	return 3.0


## 凍結區：原樣加進 trees（保持 V0.1 順序），並登記進最小樹距表，讓活著的區在接縫附近避開它們
func _adopt_frozen(sc: String) -> void:
	_adopt_entries(sc, _frozen[sc])


## 把凍結檔格式的條目（含 xf）原樣加進 trees 並登記樹距。S01 R1 的候選規劃也用它載入歷史條目（重播／保留的背景林）。
func _adopt_entries(sc: String, entries: Array) -> void:
	for e: Dictionary in entries:
		var id := String(e["id"])
		if not kit.has(id):
			freeze_error = "凍結檔的樹 %s 不在 veg_kit／bamboo_kit 裡" % id
			return
		var k: Dictionary = kit[id]
		var s := float(e["s"])
		var px := float(e["x"])
		var pz := float(e["z"])
		var py := float(e["y"])
		var kind := String(e["kind"])
		if kind == "pin":
			# 釘點的 x／z／y／s 不吃亂數（layout 的位置、高度與 kit 高度決定）→ 重算出和 V0.1 當時完全相同的雙精度值，
			# 注連繩等拿「樹」當錨點的東西才會逐位元回到 V0.1（凍結檔裡的值是四捨五入過的）
			var pins: Array = _fcfg["pins"]
			for idx in pins.size():
				if String((pins[idx] as Dictionary)["id"]) == String(e["pin"]):
					var info := _pin_info(pins[idx], idx)
					var pp: Vector2 = info["p"]
					var xf0: Array = e["xf"]
					if absf(pp.x - float(xf0[9])) > 1e-3 or absf(pp.y - float(xf0[11])) > 1e-3 or String(info["id"]) != id:
						freeze_error = "凍結的釘點 %s 與 layout 不符（位置差 %.4f m）" % [String(e["pin"]), Vector2(pp.x - float(xf0[9]), pp.y - float(xf0[11])).length()]
						return
					px = pp.x
					pz = pp.y
					s = float(info["s"])
					py = lib.h_at(pp.x, pp.y) - 0.05 - 0.012 * lib.slope_deg_at(pp.x, pp.y)
		var rr := float(k["r"]) * s
		var p := Vector2(px, pz)
		trees.append({"id": id, "x": px, "z": pz, "y": py, "s": s, "yaw": float(e["yaw"]), "r": rr,
			"scene": sc, "kind": kind, "pin": String(e["pin"]), "xf": e["xf"], "frozen": true})
		match kind:
			"pin": _register(p, rr, 3.0 + rr * 2.0)
			"landmark": _register(p, rr, 4.5)
			"tree": _register(p, rr, _species_gap(id), "t")
			"bamboo": _register(p, 0.05, 0.9, "b")
			"under": _register(p, 0.05, 0.75, "u")
			"dead": _register(p, 0.3, 3.5, "t")


## S01 R1：候選規劃是否啟用（layout.forest.s01_candidate.enabled，且 S01 不在現行凍結區）
func s01_candidate_on() -> bool:
	var c: Dictionary = _fcfg.get("s01_candidate", {})
	return bool(c.get("enabled", false)) and not _frozen.has("S01")


## S01 R1：讀歷史凍結檔的 S01 條目（雜湊照樣檢查；不論 freeze.enabled，因為候選要用它當『重播』與背景林來源）
func _load_s01_history() -> void:
	_hist_s01.clear()
	var fz: Dictionary = _fcfg.get("freeze", {})
	if fz.is_empty():
		freeze_error = "S01 候選需要 layout.forest.freeze（歷史凍結檔）"
		return
	var path := String(fz["file"])
	if not FileAccess.file_exists(path):
		freeze_error = "凍結檔不存在：%s" % path
		return
	var sha := FileAccess.get_sha256(path)
	if sha != String(fz["sha256"]):
		freeze_error = "凍結檔雜湊對不上：%s（layout 記 %s，實際 %s）" % [path, String(fz["sha256"]), sha]
		return
	var src: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (src is Dictionary) or not ((src as Dictionary).get("scenes", {}) as Dictionary).has("S01"):
		freeze_error = "凍結檔缺 S01：%s" % path
		return
	_hist_s01 = (src as Dictionary)["scenes"]["S01"]


func _plan_s01_candidate() -> void:
	s01_info = S01Forest.plan(self, _fcfg["s01_candidate"])


func _zone_z_range(sc: String) -> Vector2:
	for r: Dictionary in lib.rects:
		if String(r["id"]) == sc:
			var t: Rect2 = r["tile"]
			return Vector2(maxf(t.position.y, -487.0), minf(t.end.y, 27.0))
	return Vector2(-487.0, 27.0)


func _count_stats() -> Dictionary:
	var c := {"pins": 0, "trees": 0, "bamboo": 0, "under": 0, "dead": 0}
	for t: Dictionary in trees:
		match String(t["kind"]):
			"pin", "landmark": c["pins"] += 1
			"tree": c["trees"] += 1
			"bamboo": c["bamboo"] += 1
			"under": c["under"] += 1
			"dead": c["dead"] += 1
	c["total"] = trees.size()
	return c


## ---------------------------------------------------------------- 主流程
func plan() -> void:
	trees.clear()
	claw_marks.clear()
	_placed.clear()
	_hash.clear()
	_load_frozen()
	if freeze_error != "":
		push_error(freeze_error)
		return
	s01_info = {}
	s01_wall = {}
	if s01_candidate_on():
		_load_s01_history()
		if freeze_error != "":
			push_error(freeze_error)
			return
	# 地標（古楓）位置先定下來：S04 的樹種權重要用（與哪一區被凍結無關）
	var lm: Dictionary = lib.L["boss_arena"]["landmark"]
	_landmark = lib.arena_pos(float(lm["deg"]), float(lm["r"]))
	# 抓痕不吃亂數（位置只由釘點的 h／樹幹半徑／離路方向決定）→ 不論該區凍不凍結都在這裡算
	_make_claw_marks()
	# 1) 凍結區原樣載入
	for sc: String in ZONES:
		if _frozen.has(sc):
			_adopt_frozen(sc)
			if freeze_error != "":
				push_error(freeze_error)
				return
	# 1b) V1.3：S04＝V1.2 凍結（只剔除／重新落地與 V1.3 局部修改衝突的）
	if not _frozen_s04.is_empty():
		_adopt_v12_s04()
		if freeze_error != "":
			push_error(freeze_error)
			return
	# 2) 其餘各區：獨立亂數序列、固定順序 S01→S04
	for sc: String in ZONES:
		if _frozen.has(sc):
			continue
		if sc == "S04" and not _frozen_s04.is_empty():
			continue
		_zone = sc
		_rng.seed = zone_seed(sc)
		if sc == "S01" and s01_candidate_on():
			_plan_s01_candidate()                 # S01 R1：候選規劃取代舊的 S01 抽樣（S02／S03／S04 此時已原樣載入並登記樹距）
			if freeze_error != "":
				push_error(freeze_error)
				return
			continue
		_place_pins(sc)
		_fill_trees(sc)
		_fill_bamboo(sc)
		_fill_under(sc)
		_fill_dead(sc)
	_zone = ""
	_wild_pass()
	stats = _count_stats()


func _pin_info(pin: Dictionary, idx: int) -> Dictionary:
	var at := lib.resolve(pin["at"])
	var id := ""
	match String(pin["species"]):
		"cedar": id = "sugi_a"
		"broadleaf": id = "keyaki_a"
		"maple": id = "momiji_b"
		"cherry": id = ["sakura_somei", "sakura_yama", "sakura_shidare"][idx % 3]
		"old_broadleaf": id = "kusu_hero"
		_: id = "keyaki_a"
	return {"p": at["p"], "id": id, "s": float(pin["h"]) / _kit_h(id)}


func _make_claw_marks() -> void:
	var pins: Array = _fcfg["pins"]
	for idx in pins.size():
		var pin: Dictionary = pins[idx]
		if not (pin.get("marks", []) as Array).has("claw"):
			continue
		var info := _pin_info(pin, idx)
		var p: Vector2 = info["p"]
		# 抓痕：樹幹朝路的一面，離地 1.1~2.2 m
		var q := lib.main.q(p)
		var to_path: Vector2 = ((q["pos"] as Vector2) - p).normalized()
		var rr := float((kit[String(info["id"])] as Dictionary)["r"]) * float(info["s"])
		claw_marks.append({"p": Vector3(p.x + to_path.x * rr * 0.98, lib.h_at(p.x, p.y), p.y + to_path.y * rr * 0.98), "n": Vector3(to_path.x, 0, to_path.y), "r": rr, "id": String(pin["id"])})


func _place_pins(sc: String) -> void:
	var pins: Array = _fcfg["pins"]
	for idx in pins.size():
		var pin: Dictionary = pins[idx]
		var info := _pin_info(pin, idx)
		var p: Vector2 = info["p"]
		if lib.scene_id_of_z(p.y) != sc:
			continue
		var id := String(info["id"])
		var s := float(info["s"])
		_add_tree(id, p, s, _rng.randf() * TAU, "pin", String(pin["id"]))
		var rr := float((kit[id] as Dictionary)["r"]) * s
		_register(p, rr, 3.0 + rr * 2.0)
	# BOSS 空地地標（古楓）：和釘點一起先登記，之後的樹不會長在它身上
	if lib.scene_id_of_z(_landmark.y) == sc:
		var lm: Dictionary = lib.L["boss_arena"]["landmark"]
		var lid := "momiji_b"
		var ls := float(lm["h"]) / _kit_h(lid)
		_add_tree(lid, _landmark, ls, 0.7, "landmark", "arena_landmark")
		_register(_landmark, float((kit[lid] as Dictionary)["r"]) * ls, 4.5)


func _fill_trees(sc: String) -> void:
	var zr := _zone_z_range(sc)
	var cells: Array = []
	var step := 2.5
	var x := -107.0
	while x < 107.0:
		var z := zr.x
		while z < zr.y:
			cells.append(Vector2(x, z))
			z += step
		x += step
	# 洗牌（避免最小樹距拒絕有方向偏差）
	for i in range(cells.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Vector2 = cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	for c: Vector2 in cells:
		var p := c + Vector2(_rng.randf() * step, _rng.randf() * step)
		if lib.scene_id_of_z(p.y) != sc:
			continue
		var key := _scene_key(p)
		var d := _density(p, key)
		if _rng.randf() > d * step * step / 100.0:
			continue
		if _in_bamboo(p) and _rng.randf() < 0.9:
			continue
		var weights := _species_weights(key, p)
		var spn := _wpick(weights)
		var spec: Dictionary = SPECIES[spn]
		var id := _wpick(spec["v"])
		var s := lerpf(float(spec["s"][0]), float(spec["s"][1]), _rng.randf())
		var rt := float((kit[id] as Dictionary)["r"]) * s
		if _blocked(p, rt):
			continue
		var gap := float(spec["gap"])
		if _too_close(p, gap, "t", rt):
			continue
		_add_tree(id, p, s, _rng.randf() * TAU, "tree")
		_register(p, rt, gap, "t")


func _fill_bamboo(sc: String) -> void:
	for z: Dictionary in _fcfg["bamboo_zones"]:
		var c := _pt(z["c"])
		if lib.scene_id_of_z(c.y) != sc:
			continue
		var R := float(z["r"])
		var dens := float(z["density"]) * BAMBOO_MULT
		var cnt := int(dens * PI * R * R / 100.0 * 0.62)
		var tries := 0
		var placed := 0
		while placed < cnt and tries < cnt * 12:
			tries += 1
			var ang := _rng.randf() * TAU
			var rad := R * sqrt(_rng.randf())
			var p := c + Vector2(cos(ang), sin(ang)) * rad
			# 外緣漸稀
			if _rng.randf() > 1.0 - smoothstep(0.62 * R, R, rad):
				continue
			var id := _wpick(BAMBOO)
			var s := _rng.randf_range(0.9, 1.15)
			if lib.scene_id_of_z(p.y) != sc or _blocked(p, 0.1, true) or _too_close(p, 0.9, "b"):
				continue
			_add_tree(id, p, s, _rng.randf() * TAU, "bamboo")
			_register(p, 0.05, 0.9, "b")
			placed += 1


func _fill_under(sc: String) -> void:
	# 林下：灌木／蕨／笹，成叢（2~5 株，半徑 1.6 m 內）。S01 稀、S02~S04 多；路緣略多（人走出來的邊）
	var dens := {"S01": 0.5, "S02": 3.8, "S03": 3.0, "S04": 2.6}
	var zr := _zone_z_range(sc)
	var step := 4.0
	var x := -105.0
	while x < 105.0:
		var z := maxf(zr.x, -485.0)
		while z < minf(zr.y, 25.0):
			var p := Vector2(x + _rng.randf() * step, z + _rng.randf() * step)
			z += step
			if lib.scene_id_of_z(p.y) != sc:
				continue
			var base := float(dens[sc])
			var sdf := lib.mask_sdf(p)
			if sdf > 12.0:
				continue                                  # 玩區外牆：林下看不到，不放
			var g := clampf(1.0 + 0.9 * _n2.get_noise_2d(p.x + 400.0, p.y - 90.0) + 0.5 * _n3.get_noise_2d(p.x, p.y), 0.0, 2.4)
			var dmain := lib.sample_arr(lib.DM, p.x, p.y) - lib.sample_arr(lib.WM, p.x, p.y)
			var edge_boost := 1.0 + 0.8 * (1.0 - smoothstep(1.2, 7.0, dmain))
			var prob := base * g * edge_boost * step * step / 100.0 / 3.2
			if sc == "S04":
				# V1.2 C：空地邊緣（有效半徑 −1.5 … +9 m）林下加厚——蕨、灌木、杜鵑探進空地；空地內側稀疏成島，不鋪滿
				var cdist := _clear_dist(p)
				if cdist < -1.5:
					prob *= 0.30
				elif cdist < 9.0:
					prob *= 1.0 + 1.1 * (1.0 - smoothstep(-1.5, 9.0, cdist))
				prob *= _rock_foot_boost(p)
			if _rng.randf() > prob:
				continue
			var m := _rng.randi_range(3, 7)
			for i in m:
				var q := p + Vector2(_rng.randf_range(-1.6, 1.6), _rng.randf_range(-1.6, 1.6))
				var id := _wpick(UNDER)
				if id == "sasa_a" and sc != "S03" and _rng.randf() < 0.7:
					id = "fern_a"
				var s := _rng.randf_range(0.8, 1.3)
				if lib.scene_id_of_z(q.y) != sc or _blocked(q, 0.1, true) or _too_close(q, 0.75, "u"):
					continue                                  # 叢的成員跨過接縫就不收（否則 S04 的灌木會長進 S03 的場景）
				_add_tree(id, q, s, _rng.randf() * TAU, "under")
				_register(q, 0.05, 0.75, "u")
		x += step


## V1.2 C：岩腳的蕨與灌木裙——離岩石（岩壁岩／崖腳岩／根岩）落地線 0.2~4 m 內林下機率最多 +130 %，岩才像長在林子裡
func _rock_foot_boost(p: Vector2) -> float:
	var k := _cell(p, 6.0)
	var best := 99.0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(k.x + dx, k.y + dz)
			if not _fp_hash.has(key):
				continue
			for i: int in _fp_hash[key]:
				var f: Dictionary = _foot[i]
				var id := String(f["id"])
				if id.begins_with("arena_wall") or id.begins_with("arena_flank") or id.begins_with("arena_rootrock"):
					best = minf(best, p.distance_to(f["p"]) - float(f["r"]))
	if best > 4.0:
		return 1.0
	return 1.0 + 1.3 * (1.0 - smoothstep(0.2, 4.0, best))


func _fill_dead(sc: String) -> void:
	# 枯立木 snag：S02/S04 偶見（每場景 3~6 棵），遠離路
	var want := {"S02": 5, "S03": 3, "S04": 4}
	if not want.has(sc):
		return
	var rect := Rect2()
	for r: Dictionary in lib.rects:
		if String(r["id"]) == sc:
			rect = r["rect"]
	var tries := 0
	var got := 0
	while got < int(want[sc]) and tries < 400:
		tries += 1
		var p := Vector2(rect.position.x + _rng.randf() * rect.size.x, rect.position.y + _rng.randf() * rect.size.y)
		if lib.sample_arr(lib.DM, p.x, p.y) - lib.sample_arr(lib.WM, p.x, p.y) < 7.0:
			continue
		if _blocked(p, 0.3) or _too_close(p, 3.5, "t", 0.3):
			continue
		_add_tree("snag_a", p, _rng.randf_range(0.9, 1.3), _rng.randf() * TAU, "dead")
		_register(p, 0.3, 3.5, "t")
		got += 1


## ================================================================ 荒野化（2026-10-18 S01–S03 環境重製）
## layout.forest.wild：在既有規劃（凍結的 S02／S03、S01 候選、S04 V1.2 凍結）之後「只加不改」——
## 加樹（高低混種、微傾）、竹叢、枯立木；S01 的櫻換成野生闊葉／杉（櫻＝觀賞公園感）。
## 獨立亂數（wild.seed），只落在 S01–S03；禁區與樹距沿用 _blocked／_too_close（路、支線、溪、鋪石、道具腳印、空地、陡坡），
## 所以主路淨空、S04 的樹與所有凍結條目都不受影響。enabled＝false＝回到原規劃。
func _wild_pass() -> void:
	var wcfg: Dictionary = _fcfg.get("wild", {})
	if not bool(wcfg.get("enabled", false)):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(wcfg.get("seed", 18101))
	var info := {"swap": 0, "tree": {}, "bamboo": {}, "dead": {}}
	# 1) 櫻 → 野生樹（同高度）
	var sw: Dictionary = wcfg.get("cherry_swap", {})
	for t: Dictionary in trees:
		var sc := String(t["scene"])
		if not sw.has(sc) or not String(t["id"]).begins_with("sakura"):
			continue
		var opts: Dictionary = sw[sc]
		var nid := ""
		var tot := 0.0
		for k: String in opts:
			tot += float(opts[k])
		var r0 := rng.randf() * tot
		for k: String in opts:
			r0 -= float(opts[k])
			if r0 <= 0.0:
				nid = k
				break
		if nid == "" or not kit.has(nid):
			continue
		var s_new := clampf(float(t["s"]) * _kit_h(String(t["id"])) / _kit_h(nid), 0.7, 1.4)
		t["id"] = nid
		t["s"] = s_new
		t["r"] = float((kit[nid] as Dictionary)["r"]) * s_new
		t.erase("xf")
		t["frozen"] = false
		info["swap"] = int(info["swap"]) + 1
	# 2) 加樹
	var zc: Dictionary = wcfg.get("zones", {})
	var step := 2.5
	for sc: String in ["S01", "S02", "S03"]:
		if not zc.has(sc):
			continue
		var z: Dictionary = zc[sc]
		var zr := _zone_z_range(sc)
		var dens_pts: Array = z["dens"]              # [[z, 每 100 m² 株數], …]（z 由北往南遞增或任意順序，線性內插）
		var mix: Dictionary = z["mix"]
		var near_m: Array = z.get("near_m", [30.0, 48.0])   # 離路緣 near_m[0] 以內全額，到 near_m[1] 降到 far_k
		var far_k := float(z.get("far_k", 0.3))
		var lean_p := float(z.get("lean_p", 0.4))
		var lean_deg := float(z.get("lean_deg", 5.0))
		rng.seed = _wild_seed(int(wcfg.get("seed", 18101)), "tree_" + sc)
		var cells: Array = []
		var x := -107.0
		while x < 107.0:
			var zz := zr.x
			while zz < zr.y:
				cells.append(Vector2(x, zz))
				zz += step
			x += step
		for i in range(cells.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: Vector2 = cells[i]
			cells[i] = cells[j]
			cells[j] = tmp
		var n_add := 0
		for c: Vector2 in cells:
			var pp := c + Vector2(rng.randf() * step, rng.randf() * step)
			if lib.scene_id_of_z(pp.y) != sc or _wild_seam(pp):
				continue
			var d := _wild_dens(dens_pts, pp.y)
			var de := minf(lib.sample_arr(lib.DM, pp.x, pp.y) - lib.sample_arr(lib.WM, pp.x, pp.y), lib.sample_arr(lib.DB, pp.x, pp.y))
			d *= lerpf(1.0, far_k, smoothstep(float(near_m[0]), float(near_m[1]), de))
			d *= clampf(1.0 + 0.6 * _n2.get_noise_2d(pp.x * 1.3 + 211.0, pp.y * 1.3 - 77.0), 0.25, 1.6)   # 疏密成塊，不均勻撒點
			if rng.randf() > d * step * step / 100.0:
				continue
			var spn := ""
			var tot2 := 0.0
			for k2: String in mix:
				tot2 += float(mix[k2])
			var r1 := rng.randf() * tot2
			for k2: String in mix:
				r1 -= float(mix[k2])
				if r1 <= 0.0:
					spn = k2
					break
			if spn == "" or not SPECIES.has(spn):
				continue
			var spec: Dictionary = SPECIES[spn]
			var id := _wpick_r(rng, spec["v"])
			var sc_s := lerpf(float(spec["s"][0]), float(spec["s"][1]), rng.randf())
			var rt := float((kit[id] as Dictionary)["r"]) * sc_s
			if _blocked(pp, rt):
				continue
			if spn != "sapling" and de - rt < float(z.get("big_edge_m", 0.0)):
				continue                                    # 大樹的樹幹離路緣至少 big_edge_m：第三人稱相機（在路上、玩家後方）不貼樹幹；路緣由幼樹與林下收窄
			var gap := float(spec["gap"]) * float(z.get("gap_k", 0.8))
			if _too_close_wild(pp, gap, rt):
				continue
			_add_tree(id, pp, sc_s, rng.randf() * TAU, "tree")
			if rng.randf() < lean_p:
				var a := rng.randf() * TAU
				(trees[trees.size() - 1] as Dictionary)["lean"] = [cos(a), sin(a), deg_to_rad(rng.randf_range(1.5, lean_deg))]
			_register(pp, rt, gap, "t")
			n_add += 1
		(info["tree"] as Dictionary)[sc] = n_add
	# 3) 竹叢（荒れた竹藪；loose 禁區＝可貼近林緣，但不進路／溪／道具）
	for bz: Dictionary in wcfg.get("bamboo", []):
		rng.seed = _wild_seed(int(wcfg.get("seed", 18101)), "bamboo_" + String(bz.get("id", "?")))
		var c2 := _pt(bz["c"])
		var sc2 := lib.scene_id_of_z(c2.y)
		var R := float(bz["r"])
		var cnt := int(float(bz["density"]) * BAMBOO_MULT * PI * R * R / 100.0 * 0.62)
		var placed := 0
		var tries := 0
		while placed < cnt and tries < cnt * 12:
			tries += 1
			var ang := rng.randf() * TAU
			var rad := R * sqrt(rng.randf())
			var q := c2 + Vector2(cos(ang), sin(ang)) * rad
			if rng.randf() > 1.0 - smoothstep(0.55 * R, R, rad):
				continue
			if lib.scene_id_of_z(q.y) != sc2 or _wild_seam(q) or _blocked(q, 0.1, true) or _too_close(q, 0.9, "b"):
				continue
			_add_tree(_wpick_r(rng, BAMBOO), q, rng.randf_range(0.9, 1.15), rng.randf() * TAU, "bamboo")
			_register(q, 0.05, 0.9, "b")
			placed += 1
		(info["bamboo"] as Dictionary)[String(bz.get("id", "?"))] = placed
	# 4) 枯立木（路緣 3 m 外起就可能出現）
	var snags: Dictionary = wcfg.get("snags", {})
	for sc3: String in snags:
		var rect := Rect2()
		for rr: Dictionary in lib.rects:
			if String(rr["id"]) == sc3:
				rect = rr["rect"]
		rng.seed = _wild_seed(int(wcfg.get("seed", 18101)), "snag_" + sc3)
		var got := 0
		var tr := 0
		while got < int(snags[sc3]) and tr < 2000:
			tr += 1
			var p3 := Vector2(rect.position.x + rng.randf() * rect.size.x, rect.position.y + rng.randf() * rect.size.y)
			var de3 := lib.sample_arr(lib.DM, p3.x, p3.y) - lib.sample_arr(lib.WM, p3.x, p3.y)
			if de3 < 3.0 or de3 > 26.0 or lib.scene_id_of_z(p3.y) != sc3 or _wild_seam(p3):
				continue
			if _blocked(p3, 0.3) or _too_close(p3, 3.0, "t", 0.3):
				continue
			_add_tree("snag_a", p3, rng.randf_range(0.9, 1.35), rng.randf() * TAU, "dead")
			_register(p3, 0.3, 3.0, "t")
			got += 1
		(info["dead"] as Dictionary)[sc3] = got
	stats_wild = info
	print("[wild] ", info)


## 荒野化的樹距：只看新樹自己的 gap（不吃既有樹存的大 gap）＋樹幹外緣至少 0.6 m——密林 2–3 m 的樹距；竹／林下照 _too_close 規則
func _too_close_wild(p: Vector2, gap: float, rt: float) -> bool:
	var k := _cell(p, 4.0)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var key := Vector2i(k.x + dx, k.y + dz)
			if not _hash.has(key):
				continue
			for i: int in _hash[key]:
				var q: Dictionary = _placed[i]
				var d := p.distance_to(q["p"])
				if String(q["layer"]) == "t":
					if d < maxf(gap, float(q["r"]) + rt + 0.6):
						return true
				elif d < rt + 0.4:
					return true
	return false


var stats_wild: Dictionary = {}


## S03／S04 接縫往北 6 m 內不加東西：S04 的樹（凍結或重抽）最大樹距＋半徑 < 6 m → S04 規則改動不會改變 S03 的荒野化結果
func _wild_seam(p: Vector2) -> bool:
	var zr := _zone_z_range("S04")
	return p.y < zr.y + 6.0


func _wild_seed(base: int, key: String) -> int:
	var h := 2166136261
	for b: int in key.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return (base * 1000003 + h) & 0x7FFFFFFF


func _wild_dens(pts: Array, z: float) -> float:
	var a: Array = pts.duplicate()
	a.sort_custom(func(u: Array, v: Array) -> bool: return float(u[0]) < float(v[0]))
	if z <= float(a[0][0]):
		return float(a[0][1])
	for i in range(1, a.size()):
		if z <= float(a[i][0]):
			var t := (z - float(a[i - 1][0])) / (float(a[i][0]) - float(a[i - 1][0]))
			return lerpf(float(a[i - 1][1]), float(a[i][1]), t)
	return float(a[a.size() - 1][1])


func _wpick_r(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var tot := 0.0
	for k: String in weights:
		tot += float(weights[k])
	var r := rng.randf() * tot
	for k: String in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return String(weights.keys()[0])
