extends Node3D
## P10 R4c Prop Fix Pilot（overlay `PropFixP10`，由 tools/verify_village_v2_prop_fix.gd --build 產生）。
## _ready：把村裡所有 street_kit st_hasa（＋_l1）MeshInstance3D 的 mesh 換成 r4c_kit st_hasa_v2（＋_l1）；enabled=false 還原。
## 只換 mesh（位置／朝向／件數不動）；封存的 street_kit 檔不改。
@export var swaps: Dictionary = {}   # 原 mesh 路徑 → 新 Mesh
## R4c A2 必要最小的擺放調整：節點路徑（相對 village 根）→ 新的世界 xz 與 y（Vector3）；件數不變、只動被指名的件
@export var moves: Dictionary = {}
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)

var _done: Array = []   # [MeshInstance3D, 原 Mesh]
var _moved: Array = []  # [Node3D, 原 global_transform]
var swapped := 0
var moved := 0


func _ready() -> void:
	if enabled:
		apply.call_deferred(true)


func apply(on: bool) -> void:
	for d in _done:
		if is_instance_valid(d[0]):
			(d[0] as MeshInstance3D).mesh = d[1]
	_done.clear()
	for d in _moved:
		if is_instance_valid(d[0]):
			(d[0] as Node3D).global_transform = d[1]
	_moved.clear()
	swapped = 0
	moved = 0
	if not on:
		return
	for p in moves:
		var nd := get_parent().get_node_or_null(NodePath(String(p))) as Node3D
		if nd == null:
			continue
		_moved.append([nd, nd.global_transform])
		var t := nd.global_transform
		t.origin = moves[p]
		nd.global_transform = t
		moved += 1
	for mi in get_parent().find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null or not swaps.has(m.resource_path):
			continue
		_done.append([mi, m])
		(mi as MeshInstance3D).mesh = swaps[m.resource_path]
		swapped += 1
