extends Node3D
## 水邊生態 —— 鴨子沿水路游、鯉魚在水下擺尾、鷺鷥站岸邊偶爾理羽。
## 產生器（gen_village.gd）把路徑點與水面高度寫進 meta，這裡只管動。
##
## 設計取捨：不用 AnimationPlayer 或骨架 —— 這些是遠景小物，
## 用程式算位移與擺動最省，而且產生器不必輸出動畫資料。

## [{ "pts": [Vector2...], "y": float }] 水路中心線與水面高度
@export var paths: Array = []
## 各自的巡游狀態：{ node, path_i, t, speed, dir, phase, kind }
var _swimmers: Array = []

const KIND_DUCK := 0
const KIND_KOI := 1

func _ready() -> void:
	# 產生器在每個游動物件上標了 meta（swim_kind / swim_t / swim_speed），
	# 這裡自動收集 —— 場景存檔只會帶 meta，帶不走執行期的陣列。
	for c in get_children():
		if c is Node3D and c.has_meta("swim_kind"):
			register(c, int(c.get_meta("swim_kind")), 0,
				float(c.get_meta("swim_t")), float(c.get_meta("swim_speed")))

func register(node: Node3D, kind: int, path_i: int, t: float, speed: float) -> void:
	_swimmers.append({
		"node": node, "kind": kind, "path_i": path_i, "t": t,
		"speed": speed, "phase": randf() * TAU, "yaw": 0.0,
	})

func _path_point(pi: int, t: float) -> Dictionary:
	var p: Dictionary = paths[pi]
	var pts: Array = p.pts
	var n := pts.size() - 1
	var ft := clampf(t, 0.0, 0.999) * float(n)
	var i := int(ft)
	var f := ft - float(i)
	var a: Vector2 = pts[i]
	var b: Vector2 = pts[mini(i + 1, n)]
	var pos := a.lerp(b, f)
	return { "pos": pos, "dir": (b - a).normalized(), "y": float(p.y) }

func _process(delta: float) -> void:
	if paths.is_empty():
		return
	var tt := float(Time.get_ticks_msec()) * 0.001
	for s in _swimmers:
		var node: Node3D = s.node
		if not is_instance_valid(node):
			continue
		s.t += s.speed * delta
		# 走到底就掉頭（水路是有限長的）
		if s.t > 1.0:
			s.t = 1.0
			s.speed = -absf(s.speed)
		elif s.t < 0.0:
			s.t = 0.0
			s.speed = absf(s.speed)
		var info := _path_point(s.path_i, s.t)
		# 在水路寬度內左右擺一點，不要排成一直線
		var dirv: Vector2 = info.dir
		var side: Vector2 = dirv.orthogonal() * sin(tt * 0.35 + s.phase) * 2.4
		var pos: Vector2 = Vector2(info.pos) + side
		var y: float = info.y
		if s.kind == KIND_DUCK:
			y += sin(tt * 1.6 + s.phase) * 0.025          # 浮沉
		else:
			y -= 0.35 + sin(tt * 0.9 + s.phase) * 0.12    # 鯉魚在水面下
		node.global_position = Vector3(pos.x, y, pos.y)
		var want := atan2(dirv.x * signf(s.speed), dirv.y * signf(s.speed))
		s.yaw = lerp_angle(s.yaw, want, 2.0 * delta)
		node.rotation.y = s.yaw
		if s.kind == KIND_KOI:
			node.rotation.z = sin(tt * 3.4 + s.phase) * 0.18   # 擺尾
		else:
			node.rotation.z = sin(tt * 1.1 + s.phase) * 0.05
