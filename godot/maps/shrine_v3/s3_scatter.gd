extends Node3D
## 博麗神社 v3 執行期散佈（草叢、蕨、地被）：資料存在本節點的 meta（建圖時由 build_scene.gd 寫入），
## _ready 時依 20 m 分塊建 MultiMeshInstance3D（不把 MultiMesh 存進場景：headless 存檔會存成零矩陣）。
## meta "layers"：[{name, mesh: 路徑, vis_end: 公尺, shadow, pts: PackedFloat32Array, …}]
##   stride   每個實例幾個 float：5＝(x, y, z, yaw, scale)；7＝再加 (nx, nz) 地面法線（傾斜貼坡，落葉／苔用）
##   lod1     遠級網格路徑（可省略）；lod_sw＝換遠級的距離
##   color    實例色（乘在頂點色上；meadow_grass 類 shader 會乘）；color_var＝每個實例亮度隨機 ±

const CHUNK := 20.0

var built := 0


func _ready() -> void:
	var layers: Array = get_meta("layers", [])
	for lay in layers:
		var mesh: Mesh = load(String(lay["mesh"]))
		if mesh == null:
			push_error("[s3_scatter] 讀不到 %s" % lay["mesh"])
			continue
		var mesh1: Mesh = null
		if lay.has("lod1"):
			mesh1 = load(String(lay["lod1"]))
		var sw := float(lay.get("lod_sw", 0.0))
		var stride := int(lay.get("stride", 5))
		var pts: PackedFloat32Array = lay["pts"]
		var vis_end := float(lay.get("vis_end", 50.0))
		var shadow := bool(lay.get("shadow", false))
		var use_col: bool = lay.has("color")
		var base_col := Color.WHITE
		if use_col:
			var ca: Array = lay["color"]
			base_col = Color(float(ca[0]), float(ca[1]), float(ca[2]))
		var cvar := float(lay.get("color_var", 0.0))
		var chunks := {}
		var n := pts.size() / stride
		for i in n:
			var x := pts[i * stride]
			var z := pts[i * stride + 2]
			var key := Vector2i(int(floor(x / CHUNK)), int(floor(z / CHUNK)))
			# ⚠ 用一般 Array：字典裡的 Packed*Array 取出來 append 只改到副本（寫時複製），會得到空分塊、
			#   位置 0/0＝NaN（instance_set_transform !is_finite）而且整層草不見。
			if not chunks.has(key):
				chunks[key] = []
			(chunks[key] as Array).append(i)
		for key in chunks:
			var ids: Array = chunks[key]
			if ids.is_empty():
				continue
			var c := Vector3((key.x + 0.5) * CHUNK, 0.0, (key.y + 0.5) * CHUNK)
			var ysum := 0.0
			for k in ids.size():
				var i: int = ids[k]
				ysum += pts[i * stride + 1]
			c.y = ysum / float(ids.size())
			var xfs: Array[Transform3D] = []
			var cols: Array[Color] = []
			for k in ids.size():
				var i: int = ids[k]
				var o := i * stride
				var b := Basis(Vector3.UP, pts[o + 3]).scaled(Vector3.ONE * pts[o + 4])
				if stride >= 7:
					var nx := pts[o + 5]
					var nz := pts[o + 6]
					if absf(nx) + absf(nz) > 0.001:
						var up := Vector3(nx, sqrt(maxf(0.0, 1.0 - nx * nx - nz * nz)), nz)
						var ax := Vector3.UP.cross(up)
						if ax.length() > 1e-5:
							b = Basis(ax.normalized(), Vector3.UP.angle_to(up)) * b
				xfs.append(Transform3D(b, Vector3(pts[o], pts[o + 1], pts[o + 2]) - c))
				if use_col:
					var h := fposmod(sin(float(i) * 12.9898 + float(o) * 0.731) * 43758.5453, 1.0)
					var t := 1.0 + (h - 0.5) * 2.0 * cvar
					cols.append(Color(base_col.r * t, base_col.g * t, base_col.b * t))
			for lv in (2 if mesh1 != null else 1):
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_colors = use_col
				mm.mesh = mesh if lv == 0 else mesh1
				mm.instance_count = ids.size()
				for k in ids.size():
					mm.set_instance_transform(k, xfs[k])
					if use_col:
						mm.set_instance_color(k, cols[k])
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "%s_%d_%d%s" % [String(lay.get("name", "layer")), key.x, key.y, "" if lv == 0 else "_lod1"]
				mmi.multimesh = mm
				mmi.position = c
				if mesh1 != null and lv == 0:
					mmi.visibility_range_end = sw
				else:
					mmi.visibility_range_begin = sw if lv == 1 else 0.0
					mmi.visibility_range_end = vis_end
					mmi.visibility_range_end_margin = 6.0
					mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (shadow and lv == 0) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mmi)
			built += ids.size()
