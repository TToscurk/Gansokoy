extends Node
class_name HaoriJiggle

## 羽織即時彈簧骨：讓袖、下襬、流蘇隨玩家移動甩動。
##
## 掛在角色的 Skeleton3D 底下即可（骨頭名稱以 bone_prefix 開頭者自動納入）。
## 每根骨獨立以 Verlet 質點模擬：質點跟著骨頭的靜止位置被彈簧拉回，
## 慣性與重力造成落後 → 視覺上就是布料被帶動再垂回。
##
## 烘焙動畫不需要它；這是給即時戰鬥用的（衝刺、急停、居合皆會反應）。

@export var skeleton_path: NodePath = ^".."
@export var bone_prefix: String = "HAORI_"
@export var enabled: bool = true

@export_group("手感")
## 彈簧硬度：越高越快回到靜止姿勢（布料越硬挺）。
@export_range(0.0, 200.0, 0.5) var stiffness: float = 60.0
## 阻尼：越高擺動越快停止。
@export_range(0.0, 40.0, 0.1) var damping: float = 7.5
## 額外重力下墜（公尺/秒²）。注意 rest 姿勢已經是垂下的羽織，
## 這裡只是再多一點點墜感；靜態下垂量 = gravity / stiffness 公尺，
## 設太高會讓布料一開始就貼到偏移上限（看起來像折了 90°）。
@export_range(0.0, 30.0, 0.1) var gravity: float = 2.5
## 空氣阻力：角色移動時布料被氣流帶動的程度。
## 有效加速度 ≈ air_drag × 12 × 角色速度(m/s)；
## 0.035 在 7 m/s 衝刺下約 3 m/s²，擺幅落在 15~20°，是布料該有的量。
@export_range(0.0, 1.0, 0.005) var air_drag: float = 0.035
## 最大偏移（公尺）：防止布料穿模或飛太遠。
## 設太小會讓高速衝刺時布料被夾在上限（看起來像卡住不動），
## 0.35 可讓 7 m/s 全速衝刺仍然是自然擺動。
@export_range(0.0, 1.0, 0.01) var max_offset: float = 0.35
## 整體強度，0 = 完全關閉效果（可用於過場/特寫）。
@export_range(0.0, 2.0, 0.01) var blend: float = 1.0

@export_group("分部位倍率")
@export_range(0.0, 3.0, 0.05) var sleeve_scale: float = 1.0
@export_range(0.0, 3.0, 0.05) var hem_scale: float = 0.75
@export_range(0.0, 3.0, 0.05) var tassel_scale: float = 1.35

var _skel: Skeleton3D
var _bones: PackedInt32Array = PackedInt32Array()
var _scales: PackedFloat32Array = PackedFloat32Array()
var _lengths: PackedFloat32Array = PackedFloat32Array()
var _rest: Array[Transform3D] = []
var _pos: PackedVector3Array = PackedVector3Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _prev_origin: Vector3 = Vector3.ZERO
var _ready_done: bool = false


func _ready() -> void:
	_skel = get_node_or_null(skeleton_path) as Skeleton3D
	if _skel == null:
		push_warning("HaoriJiggle: skeleton_path 沒指到 Skeleton3D，已停用。")
		set_physics_process(false)
		return
	_collect_bones()
	if _bones.is_empty():
		push_warning("HaoriJiggle: 找不到前綴為 '%s' 的骨頭，已停用。" % bone_prefix)
		set_physics_process(false)
		return
	_prev_origin = _skel.global_transform.origin
	_ready_done = true


func _collect_bones() -> void:
	_bones.clear()
	_scales.clear()
	_lengths.clear()
	_rest.clear()
	_pos.clear()
	_vel.clear()
	for i in _skel.get_bone_count():
		var bn := _skel.get_bone_name(i)
		if not bn.begins_with(bone_prefix):
			continue
		_bones.append(i)
		_scales.append(_part_scale(bn))
		var rest := _skel.get_bone_global_rest(i)
		_rest.append(rest)
		# 骨長：優先取第一個子骨的距離；末端骨（鏈尾）沒有子骨，
		# 改用「與父骨的距離」推估。
		# 注意：rest 位於 skeleton 的區域空間，若 GLB 帶著未套用的縮放
		# （AccuRig/FBX 常見的 0.01），這裡量到的長度會差好幾個數量級，
		# 必須換算到世界尺度，才能和世界空間的偏移量 off 相比。
		var blen := 0.0
		for c in _skel.get_bone_children(i):
			blen = (_skel.get_bone_global_rest(c).origin - rest.origin).length()
			break
		if blen <= 0.001:
			var par := _skel.get_bone_parent(i)
			if par >= 0:
				blen = (rest.origin - _skel.get_bone_global_rest(par).origin).length()
		var world_scale: float = _skel.global_transform.basis.get_scale().y
		_lengths.append(maxf(blen * world_scale, 0.02))
		# 狀態存「相對靜止位置的偏移」（公尺），靜止時為零
		_pos.append(Vector3.ZERO)
		_vel.append(Vector3.ZERO)


func _part_scale(bone_name: String) -> float:
	if bone_name.contains("Sleeve"):
		return sleeve_scale
	if bone_name.contains("Tassel"):
		return tassel_scale
	if bone_name.contains("Hem"):
		return hem_scale
	return 1.0


## 重新讀取分部位倍率（在編輯器調整 @export 後呼叫，或切換角色時）。
func refresh() -> void:
	if _skel == null:
		return
	for k in _bones.size():
		_scales[k] = _part_scale(_skel.get_bone_name(_bones[k]))


func _physics_process(delta: float) -> void:
	if not _ready_done or not enabled or delta <= 0.0:
		return
	if blend <= 0.001:
		for k in _bones.size():
			_skel.set_bone_pose_rotation(_bones[k], Quaternion.IDENTITY)
		return

	var skel_xform := _skel.global_transform
	var origin := skel_xform.origin
	# 角色本身的位移速度 → 氣流把布料往後帶。
	# 這是角色移動唯一該影響布料的管道：狀態存的是「相對靜止位置的偏移」，
	# 所以角色平移不會直接變成偏移（否則彈簧永遠追不上等速移動的目標，
	# 偏移會卡死在上限，看起來像布料僵住）。
	var body_vel := (origin - _prev_origin) / delta
	_prev_origin = origin

	var basis_inv := skel_xform.basis.orthonormalized().inverse()
	# 一律在「公尺」尺度運算：骨架可能帶著未套用的縮放（AccuRig 0.01），
	# 區域座標會是公分等級，力的單位就全部對不上。
	var local_wind := basis_inv * body_vel
	var local_down := basis_inv * Vector3.DOWN

	for k in _bones.size():
		var bone: int = _bones[k]
		var amount: float = _scales[k] * blend
		if amount <= 0.001:
			_skel.set_bone_pose_rotation(bone, Quaternion.IDENTITY)
			continue

		# 狀態 = 相對靜止位置的偏移（公尺），靜止時為零向量
		var off: Vector3 = _pos[k]
		var v: Vector3 = _vel[k]

		# 彈簧 + 阻尼 + 重力 + 氣流（重力與氣流都不乘 stiffness，
		# 否則調硬度會連帶放大外力，參數互相打架）
		var accel := -off * stiffness
		accel -= v * damping
		accel += local_down * gravity
		accel -= local_wind * air_drag * 12.0 * amount

		v += accel * delta
		off += v * delta

		# 限制最大偏移，避免穿模
		var lim := max_offset * amount
		if off.length() > lim:
			off = off.normalized() * lim
			v *= 0.5

		_pos[k] = off
		_vel[k] = v

		if off.length_squared() < 1e-10:
			_skel.set_bone_pose_rotation(bone, Quaternion.IDENTITY)
			continue

		# 把偏移換算成這根骨的旋轉：骨頭靜止時指向 rest 的 +Y，
		# 被拉扯後指向「骨頭原點 → 被拖曳的位置」。用骨長當基準，
		# 偏移多少就轉多少，不做人工放大。
		var bone_len: float = maxf(_lengths[k], 0.01)
		var rest_dir: Vector3 = (skel_xform.basis.orthonormalized() * _rest[k].basis.orthonormalized()).y.normalized()
		var pulled: Vector3 = (rest_dir * bone_len + off).normalized()
		if pulled.length_squared() < 1e-8:
			continue
		# 世界空間的「轉向」換回骨頭的區域空間
		var swing := Quaternion(rest_dir, pulled)
		var rest_basis_local: Basis = _rest[k].basis.orthonormalized()
		var world_rest: Basis = skel_xform.basis.orthonormalized() * rest_basis_local
		var q_local := Quaternion(world_rest.inverse() * Basis(swing) * world_rest)
		_skel.set_bone_pose_rotation(bone, q_local)


## 瞬間把布料歸位（傳送、切場景、復活後呼叫，避免布料從舊位置飛過來）。
func snap_to_rest() -> void:
	if not _ready_done:
		return
	for k in _bones.size():
		_pos[k] = Vector3.ZERO
		_vel[k] = Vector3.ZERO
		_skel.set_bone_pose_rotation(_bones[k], Quaternion.IDENTITY)
	_prev_origin = _skel.global_transform.origin
