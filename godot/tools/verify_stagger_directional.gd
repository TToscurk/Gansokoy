extends SceneTree
## 驗收「方向性軀幹爆反應」的接線（characters/yoriichi/yoriichi_character.gd）：
##   1) 四支對齊後的 clip 真的註冊進 AnimationPlayer
##   2) AnimationTree 的 full 層真的有這四個段落節點 —— 少了它 _fire_full 會靜默不動
##   3) stagger_key_for_dir() 對 8 個方向給出正確的段落鍵（含角色轉向 90° 之後）
##   4) 關掉 stagger_directional 會退回原本單一 Stagger（不確定方向就不要猜）
##   5) 四支不是 loop，且縮放倍率（clip_len / break_time）為正
##
##   <godot_console> --path godot --headless --script res://tools/verify_stagger_directional.gd

const PLAYER_SCENE := "res://characters/yoriichi/player_yoriichi.tscn"
const KEYS := ["stagger", "stagger_front", "stagger_back", "stagger_left", "stagger_right"]

var _fail := 0
var _n := 0
var _tree: AnimationTree = null

## Tree 上真的有這個段落節點？（＝ _fire_full(key) 不會靜默失敗）
func _key_ok(key: String) -> bool:
	return _tree != null and _tree.tree_root != null and _tree.tree_root.has_node("full_sel_%s" % key)

func _init() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool, detail: String = "") -> void:
	_n += 1
	if ok:
		print("[SDIR] PASS %s  %s" % [label, detail])
	else:
		_fail += 1
		print("[SDIR] FAIL %s  %s" % [label, detail])

## 使用者看得懂的方向名 -> 期望拿到的 @export 名稱
func _expect(p: Node, yaw: float, dir: Vector3) -> String:
	p.rotation.y = yaw
	return p.stagger_key_for_dir(dir)

func _run() -> void:
	var scn: PackedScene = load(PLAYER_SCENE)
	if scn == null:
		_check("載入玩家場景", false, PLAYER_SCENE)
		quit(1)
		return
	var node := scn.instantiate()
	root.add_child(node)
	node.set_physics_process(false)
	node.set_process(false)
	for i in 12:
		await process_frame
	var p: Node = node
	if not p.has_method("stagger_key_for_dir"):
		for c in node.get_children():
			if c.has_method("stagger_key_for_dir"):
				p = c
				break
	if not p.has_method("stagger_key_for_dir"):
		_check("玩家控制器有 stagger_key_for_dir()", false, "找不到方法")
		quit(1)
		return
	_tree = node.get_node("Tree") as AnimationTree
	if _tree != null:
		_tree.active = false
	var ap := node.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer

	# 1) 註冊
	var pairs := [
		["stagger_front_anim", "stagger_front_resource"],
		["stagger_back_anim", "stagger_back_resource"],
		["stagger_left_anim", "stagger_left_resource"],
		["stagger_right_anim", "stagger_right_resource"],
	]
	var names: Array = []
	for pr in pairs:
		var nm: String = p.get(pr[0])
		var res: Animation = p.get(pr[1])
		names.append(nm)
		_check("註冊 %s" % nm, res != null and ap.has_animation(nm),
			"%d 格 / %.2f s" % [int(round(res.length * 30.0)), res.length] if res != null else "resource 為 null")
		if res != null:
			_check("%s 非 loop" % nm, res.loop_mode == Animation.LOOP_NONE, str(res.loop_mode))

	# 2) AnimationTree 的段落節點（節點名 = full_sel_<段落鍵>，不是 anim 名稱）
	for key in KEYS:
		_check("Tree 段落 full_sel_%s" % key, _key_ok(key))

	# 3) 方向 → 段落鍵（角色朝 -Z；dir = 玩家被推走的方向 → 攻擊來自 -dir）
	#    每個回傳值都必須是 Tree 上真的存在的段落 —— 這條會抓到「回傳 clip 名稱」的錯。
	var cases := [
		["前方來襲", Vector3(0, 0, 1), "stagger_front"],
		["後方來襲", Vector3(0, 0, -1), "stagger_back"],
		["左方來襲", Vector3(1, 0, 0), "stagger_left"],
		["右方來襲", Vector3(-1, 0, 0), "stagger_right"],
	]
	p.rotation.y = 0.0
	for c in cases:
		var got: String = p.stagger_key_for_dir(c[1] as Vector3)
		_check("%s → %s" % [c[0], c[2]], got == c[2], got)
		_check("%s 的段落鍵在 Tree 上存在" % c[0], _key_ok(got), got)
	# 斜向要走 45° 楔形（只檢查它落在兩個合理者之一，且該段落存在）
	var diag: String = p.stagger_key_for_dir(Vector3(1, 0, 1))
	_check("斜前方來襲 → 前或左且段落存在",
		(diag == "stagger_front" or diag == "stagger_left") and _key_ok(diag), diag)
	# 4) 轉向 90°：同一個世界方向要對到不同段落鍵（面向 -X 時 +Z 在角色左側）
	p.rotation.y = 0.0
	var a0: String = p.stagger_key_for_dir(Vector3(0, 0, -1))
	p.rotation.y = PI * 0.5
	var a90: String = p.stagger_key_for_dir(Vector3(0, 0, -1))
	_check("轉向 90° 後同一世界方向換段落",
		a0 == "stagger_back" and a90 == "stagger_left",
		"yaw0=%s yaw90=%s" % [a0, a90])
	# 5) 零向量 / 關閉開關 → 退回原本單一 stagger 段落
	p.rotation.y = 0.0
	_check("沒有方向資料 → 退回 stagger",
		p.stagger_key_for_dir(Vector3.ZERO) == "stagger",
		p.stagger_key_for_dir(Vector3.ZERO))
	p.stagger_directional = false
	_check("關掉 stagger_directional → 退回 stagger",
		p.stagger_key_for_dir(Vector3(0, 0, 1)) == "stagger",
		p.stagger_key_for_dir(Vector3(0, 0, 1)))
	p.stagger_directional = true

	# 6) 段落鍵 → clip 名稱已註冊、縮放倍率為正（clip_len / break_time）
	var bt := 2.0
	var pst: Variant = p.get("posture")
	if pst != null:
		bt = float(pst.get("break_time"))
	for key in KEYS:
		var nm2: String = p.stagger_anim_for_key(key)
		_check("段落 %s → clip %s 已註冊" % [key, nm2], ap.has_animation(nm2), nm2)
		_check("段落 %s 縮放倍率 > 0（break_time %.2f）" % [key, bt],
			ap.get_animation(nm2).length / maxf(bt, 0.05) > 0.0,
			"%.2fx  %.2f s" % [ap.get_animation(nm2).length / maxf(bt, 0.05), ap.get_animation(nm2).length])

	print("[SDIR] ===== %d 項檢查、%d 項失敗 =====" % [_n, _fail])
	quit(1 if _fail > 0 else 0)
