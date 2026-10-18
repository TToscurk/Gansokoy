class_name WindSecondaryMotion
extends SkeletonModifier3D
## Wind V2 Phase F：可重用的生物二次運動（頭髮／尾巴／布條／袖／羽毛／耳）。WIND_V2_REVIEW。
##
## 用法：當成 Skeleton3D 的子節點（SkeletonModifier3D），給一份 SecondaryMotionProfile（骨鏈清單）。
## 每幀在動畫之後執行（SkeletonModifier3D 的處理順序＝AnimationMixer 之後）：
##   1. 讀「本幀動畫姿勢」——若本骨本幀沒被動畫寫過，用上一幀寫入前保存的基準姿勢（不會累積偏移）。
##   2. 每根骨一個小角度彈簧（世界空間軸角向量 θ）：θ'' = k(θ* − θ) − 2ζ√k θ'
##        θ*＝(骨方向 × F)·g，F＝風（Wind.sample_wind，扣掉身體速度＝相對空氣）·wind_influence
##                         − 身體加速度·inertia（含轉向的向心加速度）＋ 下垂 gravity
##      沿鏈權重由根到梢遞增；整條鏈末端最大偏擺 max_angle_deg。
##   3. 依序（根→梢）把 R(θ) 套在骨頭的世界姿態上，換回局部姿勢寫入。
## 等級：-1＝自動（依主相機距離：profile.enhanced_dist／lightweight_dist）、0＝關、1＝輕量（30 Hz、單步）、2＝增強（每幀、子步）。
## 安全：骨鏈名稱只是線索——root→tip 必須是真的父子鏈且骨長 > 0，否則該鏈停用並警告一次；
##   全部失效＝整個元件不動骨架（不影響動畫）。不修改匯入資料、不改權重、不改 AnimationTree。

@export var profile: SecondaryMotionProfile
@export_range(-1, 2) var tier := -1
## 身體節點（量速度／加速度／轉向）；空＝骨架的父節點
@export var body_path: NodePath

var _chains: Array = []          # [{res, bones:PackedInt32Array, dirs:Array[Vector3], theta:Array[Vector3], omega:Array[Vector3]}]
var _body: Node3D
var _prev_pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _acc := Vector3.ZERO
var _have_prev := false
var _acc_t := 0.0
var _base := {}                  # bone → Quaternion（寫入前的動畫姿勢）
var _written := {}               # bone → Quaternion（上次寫入值）
var _valid := false
var _warned := {}
var current_tier := 0


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	_chains.clear()
	_valid = false
	var sk := get_skeleton()
	if sk == null or profile == null:
		return
	for c in profile.chains:
		var ch := _validate_chain(sk, c)
		if not ch.is_empty():
			_chains.append(ch)
	_valid = not _chains.is_empty()
	_body = get_node_or_null(body_path) as Node3D if not body_path.is_empty() else sk.get_parent() as Node3D


## 父子鏈驗證：從 tip 往上走必須遇到 root；每根骨的 rest 長度（到子骨的距離）> 1 mm。
func _validate_chain(sk: Skeleton3D, c: SecondaryChain) -> Dictionary:
	var r := sk.find_bone(c.root_bone)
	var t := sk.find_bone(c.tip_bone)
	if r < 0 or t < 0:
		_warn_once(c, "找不到骨頭 %s／%s" % [c.root_bone, c.tip_bone])
		return {}
	var path := PackedInt32Array()
	var b := t
	while b >= 0:
		path.insert(0, b)
		if b == r:
			break
		b = sk.get_bone_parent(b)
	if b != r:
		_warn_once(c, "%s 不是 %s 的祖先（不是同一條骨鏈）" % [c.root_bone, c.tip_bone])
		return {}
	var dirs: Array = []
	for i in path.size():
		var bi := path[i]
		var d := Vector3.ZERO
		if i + 1 < path.size():
			d = sk.get_bone_rest(path[i + 1]).origin
		else:
			# 末端骨：沿用自己 rest 位移方向（相對父骨）；退而求其次用 +Y
			d = sk.get_bone_rest(bi).origin
			d = d if d.length() > 1e-4 else Vector3.UP * 0.05
		if d.length() < 1e-3:
			_warn_once(c, "骨 %s 的 rest 長度為 0" % sk.get_bone_name(bi))
			return {}
		dirs.append(d.normalized())
	var th: Array = []
	var om: Array = []
	for i in path.size():
		th.append(Vector3.ZERO)
		om.append(Vector3.ZERO)
	return {"res": c, "bones": path, "dirs": dirs, "theta": th, "omega": om}


func _warn_once(c: SecondaryChain, msg: String) -> void:
	var k := "%s/%s" % [c.label, msg]
	if not _warned.has(k):
		_warned[k] = true
		push_warning("[WindSecondaryMotion] %s：%s（此鏈停用，動畫不受影響）" % [c.label if c.label != "" else c.root_bone, msg])


func chain_count() -> int:
	return _chains.size()


func _pick_tier() -> int:
	if tier >= 0:
		return tier
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	var sk := get_skeleton()
	if cam == null or sk == null:
		return 1
	var d := cam.global_position.distance_to(sk.global_position)
	if d < profile.enhanced_dist:
		return 2
	if d < profile.lightweight_dist:
		return 1
	return 0


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or not _valid or delta <= 0.0:
		return
	current_tier = _pick_tier()
	_track_body(delta)
	# 基準姿勢：動畫本幀寫過就用新的；沒寫過（停在上次我們寫入的值）就還原保存的基準 → 不累積
	for ch in _chains:
		for b in ch["bones"]:
			var cur := sk.get_bone_pose_rotation(b)
			if _written.has(b) and cur.is_equal_approx(_written[b]):
				sk.set_bone_pose_rotation(b, _base[b])
			else:
				_base[b] = cur
	if current_tier == 0:
		for ch in _chains:
			for i in (ch["theta"] as Array).size():
				ch["theta"][i] = Vector3.ZERO
				ch["omega"][i] = Vector3.ZERO
		_written.clear()
		return
	# 積分（等級決定頻率／子步）
	var steps := 1
	var dt := delta
	if current_tier == 1:
		_acc_t += delta
		var h := 1.0 / maxf(profile.lightweight_hz, 1.0)
		if _acc_t < h:
			_apply(sk)
			return
		dt = _acc_t
		_acc_t = 0.0
	else:
		steps = maxi(1, profile.enhanced_substeps)
		dt = delta / float(steps)
	var w := get_node_or_null("/root/Wind")
	for ch in _chains:
		var c: SecondaryChain = ch["res"]
		if c.min_tier > current_tier:
			continue
		var n := (ch["bones"] as PackedInt32Array).size()
		for i in n:
			var b: int = ch["bones"][i]
			var gp := sk.global_transform * sk.get_bone_global_pose(b)
			var bone_dir: Vector3 = (gp.basis * (ch["dirs"][i] as Vector3)).normalized()
			var air := Vector3.ZERO
			if w != null:
				air = (w.sample_wind(gp.origin, 1.0) as Vector3)
			air -= _vel
			var f := air * (c.wind_influence * 0.06) - _acc * (c.inertia * 0.05) + Vector3.DOWN * c.gravity
			var weight := float(i + 1) / float(n)
			var lim := deg_to_rad(c.max_angle_deg) * weight / float(n) * 1.6
			var tgt := bone_dir.cross(f)
			if tgt.length() > lim:
				tgt = tgt.normalized() * lim
			var k := c.stiffness
			var cd := 2.0 * c.damping * sqrt(k)
			var th: Vector3 = ch["theta"][i]
			var om: Vector3 = ch["omega"][i]
			for s in steps:
				# 半隱式：先速度後位置
				om += (k * (tgt - th) - cd * om) * dt
				th += om * dt
			if th.length() > lim * 1.5:
				th = th.normalized() * lim * 1.5
				om *= 0.5
			ch["theta"][i] = th
			ch["omega"][i] = om
	_apply(sk)


## 根→梢把 R(θ) 套在世界姿態上（G' = R·G → L' = P⁻¹·R·P·L），寫回局部旋轉
func _apply(sk: Skeleton3D) -> void:
	var skb := sk.global_transform.basis.orthonormalized()
	for ch in _chains:
		var c: SecondaryChain = ch["res"]
		if c.min_tier > current_tier:
			continue
		var bones: PackedInt32Array = ch["bones"]
		for i in bones.size():
			var b := bones[i]
			var th: Vector3 = ch["theta"][i]
			var q: Quaternion = _base[b] if _base.has(b) else sk.get_bone_pose_rotation(b)
			if th.length() > 1e-6:
				var p := sk.get_bone_parent(b)
				var pg := skb * (sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis())
				var r := Basis(th.normalized(), th.length())
				var local := Basis(q)
				var nb := (pg.inverse() * r * pg * local).orthonormalized()
				q = nb.get_rotation_quaternion()
			sk.set_bone_pose_rotation(b, q)
			_written[b] = q


func _track_body(delta: float) -> void:
	var src: Node3D = _body if _body else get_skeleton()
	if src == null:
		return
	var p := src.global_position
	if not _have_prev:
		_prev_pos = p
		_have_prev = true
		return
	var v := (p - _prev_pos) / delta
	_prev_pos = p
	var a := (v - _vel) / delta
	var k := 1.0 - exp(-delta / 0.08)
	_acc = _acc.lerp(a, k)
	_vel = _vel.lerp(v, 1.0 - exp(-delta / 0.04))


## 骨名探索（只是線索）：符合樣式且父骨不符合者＝鏈根，沿唯一符合的子骨走到底。回傳 SecondaryChain 陣列（尚未驗證）。
static func discover(sk: Skeleton3D, pattern := "(?i)^(hair|tail|cloth|sleeve|feather|mane|ear|ruff)") -> Array:
	var re := RegEx.create_from_string(pattern)
	var out: Array = []
	for b in sk.get_bone_count():
		var nm := sk.get_bone_name(b)
		if re.search(nm) == null:
			continue
		var p := sk.get_bone_parent(b)
		if p >= 0 and re.search(sk.get_bone_name(p)) != null:
			continue
		var tip := b
		while true:
			var kids := sk.get_bone_children(tip)
			var nxt := -1
			for kd in kids:
				if re.search(sk.get_bone_name(kd)) != null:
					nxt = kd if nxt == -1 else -2
			if nxt < 0:
				break
			tip = nxt
		var c := SecondaryChain.new()
		c.label = nm
		c.root_bone = nm
		c.tip_bone = sk.get_bone_name(tip)
		out.append(c)
	return out
