extends Node
## 獸道 S04 陰影預算（V1.2 G）：只畫「影子碰得到戰場」的樹影。
##
## 為什麼：S04 的幀時間裡，森林陰影 pass 是最大的單項（固定時鐘、同一鏡位下全關 +29 %；其中喬木 +19 %、下層植被 < 1.2 %）。
## 陰影 pass 要把每棵樹對每一級 cascade 再畫一次。但一棵樹的影子只是地面上一條線段：
##   從樹根出發、沿光線前進方向（水平分量）延伸 h / tan(太陽仰角)。
##   10:00 仰角 68.4° → 22 m 的樹影約 9 m；07:00／17:00 仰角 24.6° → 約 49 m；且只朝背離太陽的一側。
## 這條線段（乘安全係數 slope_k 涵蓋背向坡面把影子拉長）碰不到「戰場＋緩衝」圓（半徑 margin）的樹，它的影子落在玩家看不到的地方，
## 關掉投影不會改變戰場內的畫面；太陽低時，太陽那一側的影子廊道自動保留（清晨傍晚的長影完整），背離太陽那一側才省。
## min_radius 內的樹一律投影（近、看得最清楚）；太陽 < 3°（夜／日出前後）全部保留到 max_radius。
##
## 為什麼在執行期做：樹是 prefab 實例。PackedScene.pack() 只存「該場景擁有的節點」的屬性覆寫，實例內部的 MeshInstance3D 改了存不進去
## （scripts/scene_perf_cull.gd 的檔頭有同樣的說明）。本腳本掛在 S04 場景根，由 generate_beast_path.gd 加入。
## 只改 cast_shadow（不動 transform、可見性、碰撞），S01～S03 完全不碰；沒有太陽（單獨載入地圖）時退回固定半徑 fallback_radius。

@export var margin: float = 40.0            # 戰場有效半徑 20 + 外圍 7 + 緩衝；影子線段進入這個圓才算「可能被看到」
@export var min_radius: float = 50.0        # 這個圓內的樹一律投影（TPS 鏡頭看得清楚的森林地面都在這裡面）
@export var max_radius: float = 100.0       # 與主場景 Sun 的 directional_shadow_max_distance 同值：超過也不會被畫
@export var fallback_radius: float = 60.0
@export var slope_k: float = 1.3            # 影長安全係數
@export var center: Vector2 = Vector2(4.0, -398.0)
@export var update_step_deg: float = 1.5    # 太陽仰角變化超過這個角度才重算
@export var update_az_deg: float = 4.0      # 太陽方位變化超過這個角度才重算

var _geoms: Array[GeometryInstance3D] = []
var _orig := PackedInt32Array()             # 原本的 cast_shadow
var _px := PackedFloat32Array()             # 該幾何體所屬那棵樹的世界座標 x
var _pz := PackedFloat32Array()             # 同上 z
var _dist := PackedFloat32Array()           # 到 center 的水平距離
var _hgt := PackedFloat32Array()            # 該樹的高度（m）
var _on := PackedByteArray()                # 目前是否維持原本的投影（1）
var _sun: DirectionalLight3D = null
var _elev := -999.0
var _az := -999.0
var _acc := 0.0


func _ready() -> void:
	set_process(false)
	_collect.call_deferred()


func _collect() -> void:
	var forest := get_parent().get_node_or_null("Forest")
	if forest == null:
		return
	for ch in forest.get_children():
		var c3 := ch as Node3D
		if c3 == null:
			continue
		var gs := c3.find_children("*", "GeometryInstance3D", true, false)
		var top := c3.global_position.y
		for g in gs:
			var gi := g as GeometryInstance3D
			top = maxf(top, (gi.global_transform * gi.get_aabb()).end.y)
		var h := maxf(top - c3.global_position.y, 1.0)
		var p := Vector2(c3.global_position.x, c3.global_position.z)
		for g in gs:
			var gi2 := g as GeometryInstance3D
			_geoms.append(gi2)
			_orig.append(int(gi2.cast_shadow))
			_px.append(p.x)
			_pz.append(p.y)
			_dist.append(p.distance_to(center))
			_hgt.append(h)
			_on.append(1)
	apply(true)
	set_process(true)


func _process(dt: float) -> void:
	_acc += dt
	if _acc >= 1.0:
		_acc = 0.0
		apply(false)


func _find_sun() -> void:
	_sun = null
	var best := -1.0
	for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var dl := n as DirectionalLight3D
		if dl.shadow_enabled and dl.is_visible_in_tree() and dl.light_energy > best:
			best = dl.light_energy
			_sun = dl


## 這棵樹的影子線段（樹根 → 沿 tdir 延伸 len）是否進入戰場圓
func shadow_reaches(i: int, tdir: Vector2, tan_e: float) -> bool:
	var p := Vector2(_px[i], _pz[i])
	var ab := tdir * (_hgt[i] / tan_e * slope_k)
	var t := clampf((center - p).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return (p + ab * t).distance_to(center) <= margin


## 對照／除錯用：還原所有幾何體原本的投影並停止更新
func restore_all() -> void:
	set_process(false)
	for i in _geoms.size():
		if is_instance_valid(_geoms[i]):
			_geoms[i].cast_shadow = (_orig[i] as GeometryInstance3D.ShadowCastingSetting)
		_on[i] = 1


## force＝無視變化量閾值立刻重算（測試與第一次套用用）
func apply(force: bool) -> void:
	if _geoms.is_empty():
		return
	if _sun == null or not is_instance_valid(_sun):
		_find_sun()
	var elev := -999.0
	var az := 0.0
	var tdir := Vector2.ZERO
	if _sun != null:
		var zb := _sun.global_transform.basis.z                       # 指向太陽；光的前進方向 ＝ −z
		elev = rad_to_deg(asin(clampf(zb.y, -1.0, 1.0)))
		var hz := Vector2(-zb.x, -zb.z)
		if hz.length() > 0.001:
			tdir = hz.normalized()
			az = rad_to_deg(atan2(tdir.x, tdir.y))
	if not force and absf(elev - _elev) < update_step_deg and absf(wrapf(az - _az, -180.0, 180.0)) < update_az_deg:
		return
	_elev = elev
	_az = az
	var tan_e := tan(deg_to_rad(maxf(elev, 3.0)))
	var off := 0
	for i in _geoms.size():
		var keep: bool
		if _sun == null:
			keep = _dist[i] <= fallback_radius
		elif elev < 3.0:
			keep = _dist[i] <= max_radius                              # 日出前後／夜：影子極長或是月光，全部保留
		elif _dist[i] <= min_radius:
			keep = true
		elif _dist[i] > max_radius or tdir == Vector2.ZERO:
			keep = _dist[i] <= min_radius
		else:
			keep = shadow_reaches(i, tdir, tan_e)
		if keep != (_on[i] == 1):
			_on[i] = 1 if keep else 0
			if is_instance_valid(_geoms[i]):
				_geoms[i].cast_shadow = (_orig[i] as GeometryInstance3D.ShadowCastingSetting) if keep else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _on[i] == 0:
			off += 1
	set_meta("shadow_off_geoms", off)
	set_meta("shadow_total_geoms", _geoms.size())
	set_meta("sun_elev_deg", elev)
	set_meta("sun_shadow_az_deg", az)
