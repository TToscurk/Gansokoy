extends SceneTree
## 香霖堂周遭環境：魔法之森邊緣的林中空地。
##
##   Godot --headless --path godot --script tools/gen_kourindou_forest.gd
##
## 產出 maps/kourindou/gen/forest_ring.tscn，由 kourindou.tscn 實例化。
## 加法：不動 Shop / Junk / Lamps / Terrain，只換植被層。
##
## ── 尺度是實測的，不是猜的 ──
## gobkit 是公分單位，而且**各件的原始尺度並不一致**：×0.01 之後
## TreeHigh 只有 8.5 m（該 20-30 m）、Grass 卻有 3.8 m（該 0.3-0.6 m）。
## 所以每一類都用「目標高度 ÷ 實測本地高度」各自算縮放，不套單一係數。
## 本地高度由 probe_gobkit_scale.gd 量出，寫死在下表——若換資產要重量。
##
## ── 佈局 ──
## 林中空地：店在中央，樹林從半徑 22 m 開始密集環繞，越外圍越密，
## 形成「被森林包住」的封閉感。空地內只有低矮草木，保持視線通透。

const OUT := "res://maps/kourindou/gen/forest_ring.tscn"
const SRC := "res://assets/_incoming/gobkit_nature"

## 店的保留區（probe_kourindou_site.gd 實測）：x -7.9~11.9, z -13.2~2.0。
## 取中心與半徑，外加緩衝——植被不得進入。
const SHOP_CENTRE := Vector2(2.0, -5.6)
const SHOP_CLEAR := 16.0     # 店本體最大跨距 19.7/2 ≈ 10，加 6 m 生活空間

## 地形範圍 140×140 m，但邊界牆在更內側；植被鋪到 ±62 m 就好。
const FIELD := 62.0
## 空地半徑：這個距離內不種喬木，只有草與小灌木。
const CLEARING := 22.0

## 每一類：資產名、實測本地高(cm)、目標高(m)、數量、最小間距(m)、
##         起始半徑(m)、是否只在空地外
const LAYERS := [
	# 主林：三種高樹交錯，構成環繞感
	["TreeHigh001", 849.11, 24.0, 90, 7.0, CLEARING, true],
	["TreeHigh002", 790.01, 22.0, 80, 7.0, CLEARING, true],
	["TreeHigh003", 800.64, 26.0, 70, 7.5, CLEARING, true],
	# 中層樹：填補樹冠下的空隙，離店近一點
	["TreeMed001", 596.26, 14.0, 60, 6.0, CLEARING - 4.0, true],
	["TreeMed002", 744.78, 16.0, 50, 6.0, CLEARING - 4.0, true],
	# 矮樹：空地邊緣的過渡
	["TreeLow001", 432.27, 8.0, 45, 5.0, CLEARING - 8.0, true],
	["TreeLow003", 400.11, 7.0, 40, 5.0, CLEARING - 8.0, true],
	# 灌木：可以進空地，但不擋動線
	["Bush001", 139.59, 1.6, 120, 3.0, 0.0, false],
	["Bush002", 165.59, 1.9, 90, 3.0, 0.0, false],
	# 岩石：散落，有的半埋
	["Rock001", 212.94, 1.8, 40, 4.0, 0.0, false],
	["Rock002", 218.86, 1.4, 35, 4.0, 0.0, false],
	["Rock003", 205.12, 2.2, 25, 5.0, CLEARING, false],
]

## 亂數種子固定：同樣的輸入必須產生同樣的森林，否則沒辦法做 A/B 比較。
const SEED := 20260904

var _root: Node3D
## 每一層各自的已放位置。
##
## ⚠ 不能全層共用一份。第一版用單一 _placed，於是 TreeHigh001 放完 90 棵
## 之後，TreeHigh003 的每個候選點都落在別人的 7.5 m 內，一棵都放不下
## （實測 TreeHigh003 和 Rock003 都是 0）。樹和樹之間本來就可以互相穿插，
## 需要保持距離的是「同一種資產」——否則整片林子會變成單一樹種。
var _placed := {}


func _init() -> void:
	_root = Node3D.new()
	_root.name = "ForestRing"

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	var total := 0
	for layer in LAYERS:
		var asset: String = layer[0]
		var local_h: float = layer[1]
		var target_h: float = layer[2]
		var count: int = layer[3]
		var spacing: float = layer[4]
		var r_min: float = layer[5]
		var outside_only: bool = layer[6]

		var path := "%s/%s.glb" % [SRC, asset]
		if not ResourceLoader.exists(path):
			print("[FOREST] ✗ 缺資產 %s" % asset)
			continue
		var ps := ResourceLoader.load(path, "PackedScene") as PackedScene

		# 縮放＝目標高 ÷ 本地高。本地是公分，所以這個數字看起來很小。
		var s: float = target_h / local_h

		var group := Node3D.new()
		group.name = asset
		_root.add_child(group)
		group.owner = _root
		_placed[asset] = PackedVector2Array()

		# 樹冠會互相穿插，但**樹幹不行**。同層用 spacing 隔開；跨層則只要求
		# 不撞樹幹（喬木彼此 2.5 m），這樣林子有層次又不會有兩棵長在同一點。
		var trunk_guard: float = 2.5 if asset.begins_with("Tree") else 0.0

		var made := 0
		var tries := 0
		while made < count and tries < count * 60:
			tries += 1
			# 環形分布：外圍機率高，做出「越遠越密」的包圍感
			var ang := rng.randf() * TAU
			var t := rng.randf()
			var rad: float = lerpf(r_min, FIELD, sqrt(t))
			var p := Vector2(cos(ang), sin(ang)) * rad

			if p.distance_to(SHOP_CENTRE) < SHOP_CLEAR:
				continue
			if outside_only and p.length() < CLEARING:
				continue
			if not _far_enough(asset, p, spacing):
				continue
			if trunk_guard > 0.0 and not _trunk_clear(p, trunk_guard):
				continue

			var inst := ps.instantiate() as Node3D
			inst.name = "%s_%02d" % [asset, made]
			# 高度變化 ±12%：同一個模型重複 90 次，尺寸完全一致會很假。
			# 美術規格的通則是「同系內的參數化變化」，這是最低成本的一種。
			var vary: float = s * rng.randf_range(0.88, 1.12)
			inst.scale = Vector3(vary, vary, vary)
			inst.rotation.y = rng.randf() * TAU
			# gobkit 的原點在底部（probe 確認），所以 y=0 就是站在地面上。
			# 地形起伏 3.28 m，這裡先放 y=0，之後由 snap 工具貼地。
			inst.position = Vector3(p.x, 0.0, p.y)
			group.add_child(inst)
			inst.owner = _root
			_placed[asset].append(p)
			made += 1

		print("[FOREST] %-14s %3d 棵  縮放 %.4f → 高 %.1f m（±12%%）" % [
			asset, made, s, target_h])
		total += made

	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err != OK:
		push_error("pack failed %d" % err)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	err = ResourceSaver.save(packed, OUT)
	print("[FOREST] 寫入 %s：%d 件（err=%d）" % [OUT, total, err])
	quit(0)


func _far_enough(asset: String, p: Vector2, d: float) -> bool:
	for q in _placed[asset]:
		if p.distance_to(q) < d:
			return false
	return true


## 任何喬木的樹幹都不能離另一棵太近，跨層也一樣。
func _trunk_clear(p: Vector2, d: float) -> bool:
	for k in _placed:
		if not String(k).begins_with("Tree"):
			continue
		for q in _placed[k]:
			if p.distance_to(q) < d:
				return false
	return true
