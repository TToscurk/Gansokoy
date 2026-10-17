@tool
extends Node3D
## 丘腳社寺 E2 境內環境 overlay（`HillfootPrecinctE2`・tools/p13/w9/e2/build_hf_precinct.gd が産生）。
## 子＝Ground（sg_ground 材質の地面メッシュ・地形＋lift）。兄弟の DistrictHF（街區管線の植栽・踏石）も enabled と連動する。
## enabled=true：既存環境のうち境内に重なるものを『可逆に』抑制する（原ファイルは書かない・封存の EnvironmentP9／MeadowP9／GroundcoverP9 は無傷）。
##   1. suppress_groups（メタ）：EnvironmentP9 の E082 四目垣断片（垣・杭・低木・岩 7 件）を visible=false、EnvironmentP9/Collision の同名 <名>_c を無効。
##   2. mm_polys／mm_roots（メタ）：MeadowP9／GroundcoverP9 Chunks の MultiMesh のうち、境内多邊形（＋mm_margin）に入る実例を地面の下へ沈めて極小化
##      （行列式 ≠ 0＝MMBAKE の零行列判定に掛からない・MultiMesh 資源は複製して差し替え、元の資源は _restore で戻す）。
## enabled=false：全部元へ戻す（Before と同じ状態）。DistrictHF も隠して碰撞を無効にする。
## @tool：編輯器でも同じに抑制する（さもないと編輯器だけ垣と草が見える）。存檔前（NOTIFICATION_EDITOR_PRE_SAVE）に全部還原、存完（POST_SAVE）に再適用
##   → village_v2.tscn へ visible=false・MultiMesh 差し替えは書き込まれない。物理（碰撞の切り替え）は _ready で同期に行う（読檔直後に玩家を置く経路のため）。
@export var enabled := true:
	set(v):
		enabled = v
		if _booted or (Engine.is_editor_hint() and is_inside_tree()):
			_booted = true
			_apply(v)

var _booted := false
var _hidden: Array = []      # [Node3D, 元の visible]
var _cols: Array = []        # [CollisionShape3D, 元の disabled]
var _mms: Array = []         # [MultiMeshInstance3D, 元の MultiMesh]
var suppressed_nodes := 0
var suppressed_shapes := 0
var trimmed_mmis := 0
var trimmed_instances := 0
const SINK := 0.30            # 沈める深さ（m）
const SHRINK := 0.001         # 極小化（行列式 1e-9 ＞ MMBAKE の 1e-12）


func _ready() -> void:
	# 物理側の入れ替え（碰撞）と見た目の抑制は同期で行う：main._on_load_requested が load_map の直後に玩家を置く
	_apply(enabled)
	_booted = true


func _notification(what: int) -> void:
	# 編輯器存檔：存るのは『本腳本が触っていない』状態（編輯器でだけ起きる）
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_restore()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		if _booted:
			_apply(enabled)


func _vil() -> Node:
	return get_parent()


func _district() -> Node3D:
	return _vil().get_node_or_null("DistrictHF") as Node3D if _vil() != null else null


func _restore() -> void:
	for h in _hidden:
		if is_instance_valid(h[0]):
			(h[0] as Node3D).visible = h[1]
	_hidden.clear()
	for c in _cols:
		if is_instance_valid(c[0]):
			(c[0] as CollisionShape3D).disabled = c[1]
	_cols.clear()
	for m in _mms:
		if is_instance_valid(m[0]):
			(m[0] as MultiMeshInstance3D).multimesh = m[1]
	_mms.clear()
	suppressed_nodes = 0
	suppressed_shapes = 0
	trimmed_mmis = 0
	trimmed_instances = 0


func _hide(n: Node3D) -> void:
	_hidden.append([n, n.visible])
	n.visible = false


func _apply(on: bool) -> void:
	_restore()
	visible = on
	var dh := _district()
	if dh != null:
		_hidden.append([dh, dh.visible])
		dh.visible = on
		for cs in dh.find_children("*", "CollisionShape3D", true, false):
			_cols.append([cs, (cs as CollisionShape3D).disabled])
			(cs as CollisionShape3D).disabled = not on
	if not on:
		return
	var vil := _vil()
	if vil == null:
		return
	# 1. EnvironmentP9 の垣断片
	var col := vil.get_node_or_null("Props/EnvironmentP9/Collision")
	for gp: String in get_meta("suppress_groups", PackedStringArray()):
		var g := vil.get_node_or_null(NodePath(gp)) as Node3D
		if g == null:
			continue
		for it in g.get_children():
			if it is Node3D:
				_hide(it as Node3D)
				suppressed_nodes += 1
				if col != null:
					var sh := col.get_node_or_null(String(it.name) + "_c") as CollisionShape3D
					if sh != null:
						_cols.append([sh, sh.disabled])
						sh.disabled = true
						suppressed_shapes += 1
	# 2. MultiMesh の草株
	var polys: Array = get_meta("mm_polys", [])
	var margin := float(get_meta("mm_margin", 0.4))
	var roots: PackedStringArray = get_meta("mm_roots", PackedStringArray())
	for rp: String in roots:
		var rn := vil.get_node_or_null(NodePath(rp))
		if rn == null:
			continue
		for mmi in rn.find_children("*", "MultiMeshInstance3D", true, false):
			_trim(mmi as MultiMeshInstance3D, polys, margin)


static func _in_polys(p: Vector2, polys: Array, margin: float) -> bool:
	for poly: PackedVector2Array in polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
		if margin > 0.0:
			for i in poly.size():
				var a := poly[i]
				var b := poly[(i + 1) % poly.size()]
				var ab := b - a
				var l2 := ab.length_squared()
				var t := 0.0 if l2 == 0.0 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
				if p.distance_to(a + ab * t) <= margin:
					return true
	return false


func _trim(mmi: MultiMeshInstance3D, polys: Array, margin: float) -> void:
	var mm := mmi.multimesh
	if mm == null or mm.instance_count == 0 or mm.transform_format != MultiMesh.TRANSFORM_3D:
		return
	# 粗い棄却：節点の AABB が境内多邊形の外接矩形に触れなければ読まない
	var lb := mmi.global_transform * mm.get_aabb()
	var hit_box := false
	for poly: PackedVector2Array in polys:
		var r := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			r = r.expand(q)
		if Rect2(lb.position.x, lb.position.z, lb.size.x, lb.size.z).intersects(r.grow(margin)):
			hit_box = true
			break
	if not hit_box:
		return
	var xf := mmi.global_transform
	var idx := PackedInt32Array()
	for i in mm.instance_count:
		var w := xf * mm.get_instance_transform(i).origin
		if _in_polys(Vector2(w.x, w.z), polys, margin):
			idx.append(i)
	if idx.is_empty():
		return
	var dup := MultiMesh.new()
	dup.transform_format = mm.transform_format
	dup.use_colors = mm.use_colors
	dup.use_custom_data = mm.use_custom_data
	dup.mesh = mm.mesh
	dup.instance_count = mm.instance_count
	dup.buffer = mm.buffer.duplicate()
	dup.custom_aabb = mm.custom_aabb
	dup.visible_instance_count = mm.visible_instance_count
	dup.resource_name = mm.resource_name
	var inv_b := xf.basis.inverse()
	for i in idx:
		var t := dup.get_instance_transform(i)
		dup.set_instance_transform(i, Transform3D(t.basis.scaled(Vector3.ONE * SHRINK), t.origin + inv_b * Vector3(0.0, -SINK, 0.0)))
	_mms.append([mmi, mm])
	mmi.multimesh = dup
	trimmed_mmis += 1
	trimmed_instances += idx.size()
