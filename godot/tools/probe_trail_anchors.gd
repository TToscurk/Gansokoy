extends SceneTree
## 印出獸道新路線上的關鍵 t 對應世界座標 + 地面高，供任務事件重錨用。
##   Godot --headless --path godot --script tools/probe_trail_anchors.gd
##
## ⚠ 直接載入已產生的 trail.tscn 讀 meta("spine")，不重算 —— 體檢要驗
##   「場景實際長怎樣」，不是「產生器以為長怎樣」。

const SCENE := "res://maps/trail/trail.tscn"

## 名稱 → 沿主脊 t（與 gen_trail_v2.gd 的節奏表一致）
const ANCHORS := {
	"南端_人里口": 0.005,
	"入口界碑": 0.06,
	"雜木林": 0.15,
	"岩壁隘口": 0.21,
	"地藏三尊": 0.29,
	"杉林": 0.38,
	"溪谷木橋": 0.46,
	"濕林": 0.54,
	"大空地中心": 0.63,
	"空地北緣": 0.69,
	"密林_妖怪痕跡": 0.74,
	"夜雀屋台": 0.84,
	"更深": 0.92,
	"北端_神社口": 0.995,
}

func _world_of(n: Node3D, stop: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != stop:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

func _init() -> void:
	var root := (load(SCENE) as PackedScene).instantiate() as Node3D
	var spine: PackedVector2Array = root.get_meta("spine")
	var hw: PackedFloat32Array = root.get_meta("spine_half_w")
	# 地形高度：讀場景裡實際的 Terrain 網格，不重算 height_at
	var terrain: MeshInstance3D = null
	for c in root.get_children():
		if c is MeshInstance3D and str(c.name).findn("Terrain") >= 0:
			terrain = c
			break
	var verts: PackedVector3Array = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var res := int(round(sqrt(float(verts.size()))))
	var half := 120.0
	var step := 2.0 * half / float(res - 1)
	var gy := func(x: float, z: float) -> float:
		var fi: float = clampf((x + half) / step, 0.0, float(res - 1))
		var fj: float = clampf((z + half) / step, 0.0, float(res - 1))
		var i0 := int(floor(fi)); var j0 := int(floor(fj))
		var i1: int = mini(i0 + 1, res - 1); var j1: int = mini(j0 + 1, res - 1)
		var tx := fi - float(i0); var tz := fj - float(j0)
		var h00: float = verts[j0 * res + i0].y
		var h10: float = verts[j0 * res + i1].y
		var h01: float = verts[j1 * res + i0].y
		var h11: float = verts[j1 * res + i1].y
		return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
	print("[ANCHOR] 地形 %d×%d，格距 %.2f m" % [res, res, step])
	print("[ANCHOR] %-16s %8s %8s %8s %7s" % ["名稱", "x", "z", "地面y", "路半寬"])
	for k in ANCHORS:
		var t: float = ANCHORS[k]
		var f: float = t * float(spine.size() - 1)
		var i := int(floor(f))
		var j: int = mini(i + 1, spine.size() - 1)
		var p: Vector2 = spine[i].lerp(spine[j], f - float(i))
		var w: float = lerpf(hw[i], hw[j], f - float(i))
		print("[ANCHOR] %-16s %8.2f %8.2f %8.2f %7.2f" % [k, p.x, p.y, gy.call(p.x, p.y), w])
	quit(0)
