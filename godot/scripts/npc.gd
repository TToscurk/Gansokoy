extends Node3D
## 村民 —— 沿街道走動的路人 NPC。
##
## 為什麼不用骨架與 AnimationPlayer：Q 版角色的四肢就是硬管，蒙皮沒有意義。
## 各部位在 glb 裡是**獨立物件、樞紐擺在關節上**（見 make_chars.py），
## 這裡直接轉節點就是走路動畫。省掉「產生器要輸出動畫資料」整條管線。
##
## 使用者最早的抱怨之一是「npc 自己撞牆不會換路」。這一版還沒有尋路 ——
## 村民走的是產生器給的街道折線，本來就不會撞牆。真正的 NavMesh 尋路
## 等玩法確定（ADR-006）再接，那時 walk_test.gd 產的可站立格點圖就是現成的底。

## [{ "pts": [Vector2...], "ys": [float...] }] 街道中心線與逐節點地面高度
@export var routes: Array = []

const AXIS_FORWARD := Vector3.BACK   # 未使用；留作註記：模型朝 +X（詞彙表 FacingAxis）

var _walkers: Array = []

func _ready() -> void:
	# 產生器只能帶 meta 過來，帶不走執行期的陣列
	for c in get_children():
		if c is Node3D and c.has_meta("walk_route"):
			_register(c)

func _register(node: Node3D) -> void:
	var parts := {}
	for key in ["Body", "Head", "ArmL", "ArmR", "LegL", "LegR"]:
		var n := node.find_child(key, true, false)
		if n is Node3D:
			parts[key] = n
	_walkers.append({
		"node": node,
		"parts": parts,
		"route": int(node.get_meta("walk_route")),
		"t": float(node.get_meta("walk_t")),
		"speed": float(node.get_meta("walk_speed")),
		"phase": float(node.get_meta("walk_phase")),
		"yaw": 0.0,
		"base_y": 0.0,
		# 偶爾站著發呆（全部一直走看起來像行軍）
		"idle": 0.0,
		"idle_at": float(node.get_meta("walk_t")) + 0.12 + fmod(float(node.get_meta("walk_phase")), 0.2),
	})

func _point(ri: int, t: float) -> Dictionary:
	var r: Dictionary = routes[ri]
	var pts: Array = r.pts
	var n := pts.size() - 1
	var ft := clampf(t, 0.0, 0.999) * float(n)
	var i := int(ft)
	var f := ft - float(i)
	var a: Vector2 = pts[i]
	var b: Vector2 = pts[mini(i + 1, n)]
	var ys: Array = r.ys
	return {
		"pos": a.lerp(b, f),
		"dir": (b - a).normalized(),
		"y": lerpf(float(ys[i]), float(ys[mini(i + 1, n)]), f),
	}

func _process(delta: float) -> void:
	if routes.is_empty():
		return
	var tt := float(Time.get_ticks_msec()) * 0.001
	for w in _walkers:
		var node: Node3D = w.node
		if not is_instance_valid(node):
			continue

		# ── 走 or 停 ──
		var moving := true
		if w.idle > 0.0:
			w.idle -= delta
			moving = false
		else:
			w.t += w.speed * delta
			if w.t > 1.0:
				w.t = 1.0
				w.speed = -absf(w.speed)
			elif w.t < 0.0:
				w.t = 0.0
				w.speed = absf(w.speed)
			# 走到「發呆點」就停一下（看店、打招呼）
			if absf(w.t - w.idle_at) < 0.004:
				w.idle = 1.5 + fmod(float(w.phase), 2.5)
				w.idle_at = fmod(w.idle_at + 0.37, 1.0)

		var info := _point(w.route, w.t)
		# 靠街的一側走，不要全部走在正中央
		var side: Vector2 = Vector2(info.dir).orthogonal() * sin(float(w.phase)) * 2.2
		var p: Vector2 = Vector2(info.pos) + side
		var bob := 0.0
		var swing := 0.0
		if moving:
			# 步頻跟速度掛鉤，不然慢走會像跑步機
			var stride: float = tt * (6.0 + absf(w.speed) * 220.0) + float(w.phase)
			swing = sin(stride)
			bob = absf(sin(stride)) * 0.022
		node.global_position = Vector3(p.x, float(info.y) + bob, p.y)

		# 朝向：模型的臉朝 +X（跟鴨、鷺同一條約定）
		var fdir: Vector2 = Vector2(info.dir) * signf(w.speed)
		var want := atan2(-fdir.y, fdir.x)
		w.yaw = lerp_angle(w.yaw, want, 4.5 * delta)
		node.rotation.y = w.yaw

		var parts: Dictionary = w.parts
		# 繞 Z 轉：模型朝 +X，正角度把腳往前送
		if parts.has("LegL"):
			parts["LegL"].rotation.z = swing * 0.55
		if parts.has("LegR"):
			parts["LegR"].rotation.z = -swing * 0.55
		if parts.has("ArmL"):
			parts["ArmL"].rotation.z = -swing * 0.42
		if parts.has("ArmR"):
			parts["ArmR"].rotation.z = swing * 0.42
		if parts.has("Body"):
			parts["Body"].rotation.x = swing * 0.045          # 左右微擺
		if parts.has("Head"):
			# 停下來的時候東張西望，走路時輕微反向擺（看起來才不像木頭）
			if moving:
				parts["Head"].rotation.y = -swing * 0.10
			else:
				parts["Head"].rotation.y = sin(tt * 0.7 + float(w.phase)) * 0.55
