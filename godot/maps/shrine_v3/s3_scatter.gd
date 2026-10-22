extends Node3D
## 博麗神社 v3 執行期散佈（草叢、蕨）：資料存在本節點的 meta（建圖時由 build_scene.gd 寫入），
## _ready 時依 20 m 分塊建 MultiMeshInstance3D（不把 MultiMesh 存進場景：headless 存檔會存成零矩陣）。
## meta "layers"：[{mesh: 路徑, vis_end: 公尺, pts: PackedFloat32Array(x, y, z, yaw, scale, …)}]

const CHUNK := 20.0

var built := 0


func _ready() -> void:
	var layers: Array = get_meta("layers", [])
	for lay in layers:
		var mesh: Mesh = load(String(lay["mesh"]))
		if mesh == null:
			push_error("[s3_scatter] 讀不到 %s" % lay["mesh"])
			continue
		var pts: PackedFloat32Array = lay["pts"]
		var vis_end := float(lay.get("vis_end", 50.0))
		var shadow := bool(lay.get("shadow", false))
		var chunks := {}
		var n := pts.size() / 5
		for i in n:
			var x := pts[i * 5]
			var z := pts[i * 5 + 2]
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
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = ids.size()
			var c := Vector3((key.x + 0.5) * CHUNK, 0.0, (key.y + 0.5) * CHUNK)
			var ysum := 0.0
			for k in ids.size():
				var i: int = ids[k]
				ysum += pts[i * 5 + 1]
			c.y = ysum / float(ids.size())
			for k in ids.size():
				var i: int = ids[k]
				var b := Basis(Vector3.UP, pts[i * 5 + 3]).scaled(Vector3.ONE * pts[i * 5 + 4])
				mm.set_instance_transform(k, Transform3D(b, Vector3(pts[i * 5], pts[i * 5 + 1], pts[i * 5 + 2]) - c))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%d" % [String(lay.get("name", "layer")), key.x, key.y]
			mmi.multimesh = mm
			mmi.position = c
			mmi.visibility_range_end = vis_end
			mmi.visibility_range_end_margin = 6.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			built += ids.size()
