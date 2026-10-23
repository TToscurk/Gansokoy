extends Node
## 阿求 正座（seiza）與坐下／起身轉場：掛在 NPC_Akyuu 底下。
##  - 衣身換成帶姿勢修正 blend shape 的網格（akyuu_kimono_seiza_cloth.res；Blender 布料模擬＋自碰撞烘成：
##    SeizaDrape＝正座、Sit###＝坐下 clip 第 ### 格的姿勢修正；見 assets/blender/akyuu/bake_akyuu_seiza_drape.py → tools/akyuu/apply_akyuu_seiza_bake.gd）
##  - 動作庫加入 "seiza"（正座循環，SeizaDrape＝1）、"seiza_sit"（站→正座）、"seiza_stand"（正座→站），
##    轉場 clip 自帶各修正形狀的權重軌道（tools/akyuu/build_akyuu_seiza_transition.gd）
##  - RESET（全部修正形狀＝0）＋ deterministic：其他沒有這些軌道的 clip（idle／walk…）自動回 0，換動作時隨交叉淡化一起淡出
## 用法：場景裡 NPC_Akyuu.animation = &"seiza" 開場就坐著；執行中 sit_down()／stand_up()（播完自動接正座／idle）
signal seated
signal stood_up

@export_file("*.res") var seiza_clip := "res://characters/akyuu/anim/seiza_idle_a030_final.res"
@export_file("*.res") var sit_clip := "res://characters/akyuu/anim/seiza_sit_final.res"
@export_file("*.res") var stand_clip := "res://characters/akyuu/anim/seiza_stand_final.res"
@export_file("*.res") var drape_mesh := "res://characters/akyuu/akyuu_kimono_seiza_cloth.res"
const SHAPE := &"SeizaDrape"

var _start_seiza := false
var _player: AnimationPlayer


func _ready() -> void:
	# 父節點（npc_visual）的 _ready 比子節點晚，會重建動作庫並播放 animation；正座要等這裡加進庫之後才播
	var p := get_parent()
	if str(p.get("animation")) == "seiza":
		_start_seiza = true
		p.set("animation", &"idle")
	_setup.call_deferred()


func is_seated() -> bool:
	return _player != null and String(_player.current_animation) in ["seiza", "seiza_sit"]


## 站 → 正座（播完自動接正座循環，發出 seated）
func sit_down() -> void:
	if _player == null or is_seated(): return
	get_parent().call("play_clip", &"seiza_sit", 0.0)


## 正座 → 站（播完自動接 idle，發出 stood_up）
func stand_up() -> void:
	if _player == null or String(_player.current_animation) != "seiza": return
	get_parent().call("play_clip", &"seiza_stand", 0.0)


func _on_finished(anim: StringName) -> void:
	if anim == &"seiza_sit":
		get_parent().call("play_clip", &"seiza", 0.0)
		seated.emit()
	elif anim == &"seiza_stand":
		get_parent().call("play_clip", &"idle")
		stood_up.emit()


func _setup() -> void:
	var p := get_parent()
	_player = p.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player == null or not _player.has_animation_library(&""):
		push_warning("AkyuuSeiza：找不到 AnimationPlayer／動作庫"); _player = null; return
	var mi := p.find_child("衣身", true, false) as MeshInstance3D
	if mi == null:
		push_warning("AkyuuSeiza：找不到衣身"); _player = null; return
	if mi.find_blend_shape_by_name(SHAPE) < 0:
		mi.mesh = load(drape_mesh)
	if mi.find_blend_shape_by_name(SHAPE) < 0:
		push_warning("AkyuuSeiza：%s 沒有 blend shape %s" % [drape_mesh, SHAPE]); _player = null; return
	var mesh_path := str(_player.get_node(_player.root_node).get_path_to(mi))
	var lib := _player.get_animation_library(&"")
	var a := (load(seiza_clip) as Animation).duplicate(true) as Animation
	var t := a.add_track(Animation.TYPE_BLEND_SHAPE)
	a.track_set_path(t, NodePath(mesh_path + ":" + str(SHAPE)))
	a.blend_shape_track_insert_key(t, 0.0, 1.0)
	a.blend_shape_track_insert_key(t, a.length, 1.0)
	a.loop_mode = Animation.LOOP_LINEAR
	for pair in [[&"seiza", a], [&"seiza_sit", load(sit_clip)], [&"seiza_stand", load(stand_clip)]]:
		if pair[1] == null: continue
		if lib.has_animation(pair[0]): lib.remove_animation(pair[0])
		lib.add_animation(pair[0], pair[1])
	var rs: Animation
	if lib.has_animation(&"RESET"):
		rs = lib.get_animation(&"RESET")
	else:
		rs = Animation.new(); rs.length = 0.001; lib.add_animation(&"RESET", rs)
	for k in mi.mesh.get_blend_shape_count():
		var tp := NodePath(mesh_path + ":" + str(mi.mesh.get_blend_shape_name(k)))
		if rs.find_track(tp, Animation.TYPE_BLEND_SHAPE) < 0:
			var r := rs.add_track(Animation.TYPE_BLEND_SHAPE)
			rs.track_set_path(r, tp)
			rs.blend_shape_track_insert_key(r, 0.0, 0.0)
	_player.deterministic = true
	if not _player.animation_finished.is_connected(_on_finished):
		_player.animation_finished.connect(_on_finished)
	# 袖子（SoftBody，Sleeves 於 deferred _build 建立，比這裡早）也加進 render layer 11：
	# 與身體同層，讓只照阿求的光（FaceFill、場景裡 reflection_mask＝layer 11 的局部環境光探針）一起照到袖子
	for g in p.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers |= 1 << 10
	if _start_seiza:
		_player.stop()   # 讓 play_clip 視為第一支動作（不從 idle 交叉淡化，開場就是坐著）
		p.call("play_clip", &"seiza", 0.0)
