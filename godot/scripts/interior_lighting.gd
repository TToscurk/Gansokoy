extends Node
class_name InteriorLighting
## 室內補光：把稗田邸這類封閉町家從「看不見路」拉到可遊玩亮度。
##
## 為什麼需要這支：室內是密閉屋頂，太陽光進不來，場景自帶的環境光
## `ambient_light_energy = 0.73` 搭配 `sky_contribution = 0.43` 表示
## 近半亮度來自天空——但屋內看不到天空，於是實測畫面平均亮度只有 0.08，
## 六成以上的像素接近純黑。
##
## 作法刻意保守：**不動任何既有燈具**（那是美術調過的氛圍），只加
##   1. 環境光補正（提高 ambient、降低對天空的依賴）
##   2. 幾盞低強度、大範圍的「室內天光」補燈，均勻抬起暗部
## 這樣夜晚的燈籠、障子透光等美術意圖都還在，只是不再全黑。

## 室內環境光能量。0.73 是原值（依賴天空），室內要自己給。
@export var ambient_energy := 2.10
## 環境光對天空的依賴。室內看不到天空，調低才有效。
@export_range(0.0, 1.0, 0.05) var sky_contribution := 0.08
## 補光色：微暖的和紙散射色，不要純白（會洗掉木構的色溫）。
@export var fill_color := Color(1.0, 0.93, 0.82)
## 每盞補燈的強度。刻意低——要的是抬暗部，不是打亮。
@export var fill_energy := 0.85
## 每盞補燈的照射半徑。
@export var fill_range := 16.0
## 補燈掛的高度（公尺，相對房間地板）。
@export var fill_height := 2.4
## 補燈的水平間距；房間長寬除以它決定盞數。
@export var fill_spacing := 9.0
## 補燈總數上限，避免大場景爆燈。
@export var max_fills := 12
## 天花板／梁架是室內最大片的暗面：補燈全裝在人高，梁上永遠不亮。
## 額外加一層朝上的補燈把天花板打起來。
@export var light_ceiling := true
@export var ceiling_energy := 0.45
@export var ceiling_range := 12.0

var _added: Array[Node] = []


## 對一棵場景樹套用室內補光。回傳實際加了幾盞補燈。
func apply(map_root: Node3D, fallback_env: Environment = null) -> int:
	_lift_ambient(map_root, fallback_env)
	return _add_fill_lights(map_root)


func _lift_ambient(map_root: Node3D, fallback_env: Environment) -> void:
	var env: Environment = null
	for n in map_root.find_children("*", "WorldEnvironment", true, false):
		var we := n as WorldEnvironment
		if we.environment != null:
			# 複製再改，免得動到磁碟上的共用資源。
			we.environment = we.environment.duplicate()
			env = we.environment
			break
	if env == null:
		env = fallback_env
	if env == null:
		return
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = fill_color.lerp(Color(0.72, 0.76, 0.85), 0.35)
	env.ambient_light_energy = ambient_energy
	env.ambient_light_sky_contribution = sky_contribution


## 依房間水平範圍鋪一層低強度補燈。用 mesh 的 AABB 推算室內範圍，
## 不靠人工填座標——每層房間大小不同。
func _add_fill_lights(map_root: Node3D) -> int:
	var bounds := AABB()
	var first := true
	for n in map_root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		# 跳過異常巨大的網格（遠景山、天空盒）——它們會把範圍撐爛。
		if b.size.x > 120.0 or b.size.z > 120.0:
			continue
		if first:
			bounds = b
			first = false
		else:
			bounds = bounds.merge(b)
	if first:
		return 0

	var holder := Node3D.new()
	holder.name = "InteriorFillLights"
	map_root.add_child(holder)
	_added.append(holder)

	var nx: int = maxi(1, int(ceil(bounds.size.x / fill_spacing)))
	var nz: int = maxi(1, int(ceil(bounds.size.z / fill_spacing)))
	# 先夾總數，再算實際間距，避免大房間爆燈。
	while nx * nz > max_fills:
		if nx >= nz:
			nx -= 1
		else:
			nz -= 1
		if nx < 1 or nz < 1:
			nx = 1
			nz = 1
			break

	var floor_y := bounds.position.y
	var count := 0
	for ix in nx:
		for iz in nz:
			var fx: float = bounds.position.x + bounds.size.x * (float(ix) + 0.5) / float(nx)
			var fz: float = bounds.position.z + bounds.size.z * (float(iz) + 0.5) / float(nz)
			var l := OmniLight3D.new()
			l.name = "Fill_%d_%d" % [ix, iz]
			l.light_color = fill_color
			l.light_energy = fill_energy
			l.omni_range = fill_range
			l.omni_attenuation = 0.8
			# 補光不投影：它代表的是散射光，投影會讓室內出現假陰影。
			l.shadow_enabled = false
			l.global_position = Vector3(fx, floor_y + fill_height, fz)
			holder.add_child(l)
			count += 1

			# 天花板補燈：裝在人高之上、貼近梁架，把室內最大片的暗面抬起來。
			if light_ceiling:
				var cl := OmniLight3D.new()
				cl.name = "FillCeil_%d_%d" % [ix, iz]
				cl.light_color = fill_color
				cl.light_energy = ceiling_energy
				cl.omni_range = ceiling_range
				cl.omni_attenuation = 1.0
				cl.shadow_enabled = false
				# 房間頂高由 AABB 決定，略低於天花板免得燈嵌進屋瓦。
				var ceil_y: float = minf(bounds.position.y + bounds.size.y - 0.4,
					floor_y + fill_height + 2.6)
				cl.global_position = Vector3(fx, ceil_y, fz)
				holder.add_child(cl)
				count += 1
	return count
