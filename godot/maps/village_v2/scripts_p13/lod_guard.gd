extends Node3D
## P13 Wave 8 TASK A：LOD 可視遲滯の状態初期化ガード（overlay `LodGuardP13`・子ノード 0・資源ファイルは書かない）。
##
## 症状：テレポート／初回ロード直後、LOD の切替距離の近く（Kit 町家 40／110 m、Hero 60／160 m …の ±4 m）にある物が、どの LOD も表示されないまま残る
##   （W7 で南大門鳥居が camera から 61.7 m で消え、歩いて近づくと出る）。
## 原因（W8 実測・tools/p13/w8/w8_lod_sweep.gd）：Kit／Hero／Riverbank の LOD は『首尾相接の range＋margin 4 m＋fade_mode=DISABLED』。
##   DISABLED のとき margin は遲滯（hysteresis）になり、**インスタンスごとの『可視』状態ビット**（viewport 別）で閾値が変わる：
##     可視中（bit=1）：[begin−margin, end+margin] まで見え続ける（広い）
##     非可視（bit=0）：[begin+margin, end−margin] に入って初めて見える（狭い）
##   状態ビットの初期値は 0。LOD0（end=E）と LOD1（begin=E）は非可視の閾値が『LOD0≤E−m／LOD1≥E+m』で、その間 [E−m, E+m)（幅 2m＝8 m）はどちらも出ない。
##   歩いて近づく場合は直前の LOD の状態ビットが 1 のまま隣の閾値まで見え続けるので空白は出ない（掃引の mid 情境＝鄰級から歩いて近づく場合は OFF でも gap 0 を実測）。
##   問題は『直前の可視 LOD が隣でない』とき：cold start（全部 bit=0）・遠方からのテレポート（実測：南大門 56–62 m に 8 m 幅の全空白）。
##   さらに状態ビットは『layer 判定と視錐判定を通った instance だけ』更新される（視錐の外にいる間は凍結）→ 背を向けて遠ざかった後に振り向くと、古い状態のまま現れる
##   （実測：南大門 156–162 m）。
## 修正：状態を初期化する。次のとき**その 1 幀だけ** margin を 0 にして描かせる：
##   (1) 最初の 1 幀（初回ロード）  (2) camera が 1 幀で jump_threshold m 以上動いた（テレポート）
##   (3) camera の向きが 1 幀で turn_threshold_deg 以上回った（視点リセット・ロックオン）
##   (4) 最後の初期化から向きが累積 accum_turn_deg 以上回った（ゆっくり振り向き。minimum_interval 秒で間引き）
##   → 視錐に入っている全インスタンスが厳密な範囲で判定され、ちょうど 1 級の状態ビットが 1 になる。描画後（frame_post_draw）に元の margin へ戻す
##   → 以後は元の遲滯どおり（境界でのちらつき防止は不変）。
##   2 級同時表示は作らない：margin を恒久的に変えない・range も変えない。ノードのプロパティは書き換えない（Gate が読む値は不変）。
## 費用（実測・18,225 対象）：1 回＝prime 約 4.7 ms＋restore 約 7.4 ms（RenderingServer 呼び出し・w8_lod_sweep の [W8S] 行で実測：scan 90.2／prime 4.72／restore 7.44 ms）。走査は最初の 1 回だけ約 90 ms。
##   (1)〜(3) は稀な事象（ロード・テレポート・視点リセット）。(4) だけは持続的な回転で繰り返し得る → 45° ごと・最短 1.0 秒間隔に絞って規則的な微卡頓を避ける。
## 限界（正直に）：視錐の外にあるインスタンスの状態は、どんな初期化でも更新できない（Godot の判定順）。(4) は『振り向きの途中で視錐に入った物』を ≤ accum_turn_deg（45°）以内の振り向きで直す。
## enabled=false でガードを止める（診断・永久反向用）。
@export var enabled := true
## camera が 1 幀でこれ以上動いたら状態を初期化する（m）。初期化は無害なので偽陽性は問題にならない
@export var jump_threshold := 6.0
@export var turn_threshold_deg := 35.0
@export var accum_turn_deg := 45.0
@export var minimum_interval := 1.0

var primes := 0                 ## 実行した初期化の回数
var tracked := 0                ## 対象インスタンス数（走査後）
var last_prime_usec := 0
var last_restore_usec := 0
var scan_usec := 0
var last_reason := ""

var _objs: Array = []           ## GeometryInstance3D（有効性確認用）
var _rids: Array = []           ## 各 instance の RID（ノード生存中は不変）
var _vals := PackedFloat32Array()   ## 4 要素ずつ：begin, end, begin_margin, end_margin
var _scanned := false
var _force := true              ## 最初の描画の前に必ず 1 回
var _priming := false
var _last_cam := Vector3.INF
var _last_fwd := Vector3.ZERO
var _ref_fwd := Vector3.ZERO    ## 最後の初期化時の向き
var _since_prime := 0.0


func _ready() -> void:
	_force = true
	if OS.has_environment("W8_LOD_GUARD_OFF"):
		enabled = false   # 診断専用：起動直後から止めて『素の挙動』を撮る（Before 用）。製品の流れでは未設定
	if not RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	if not RenderingServer.frame_post_draw.is_connected(_on_post_draw):
		RenderingServer.frame_post_draw.connect(_on_post_draw)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)
	if RenderingServer.frame_post_draw.is_connected(_on_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_post_draw)
	if _priming:
		_restore()


func _process(delta: float) -> void:
	_since_prime += delta


## 次の描画の前に必ず初期化する（診断・ツール用）
func prime_next_frame() -> void:
	_force = true


func _scan() -> void:
	var t0 := Time.get_ticks_usec()
	_objs.clear()
	_rids.clear()
	var vals: Array = []
	var par := get_parent()
	if par != null:
		for g in par.find_children("*", "GeometryInstance3D", true, false):
			var gi := g as GeometryInstance3D
			if gi.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED and (gi.visibility_range_begin_margin > 0.0 or gi.visibility_range_end_margin > 0.0):
				_objs.append(gi)
				_rids.append(gi.get_instance())
				vals.append(gi.visibility_range_begin)
				vals.append(gi.visibility_range_end)
				vals.append(gi.visibility_range_begin_margin)
				vals.append(gi.visibility_range_end_margin)
	_vals = PackedFloat32Array(vals)
	tracked = _objs.size()
	_scanned = true
	scan_usec = Time.get_ticks_usec() - t0


func _on_pre_draw() -> void:
	if not enabled or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var reason := ""
	if _force or not _last_cam.is_finite():
		reason = "first"
	elif p.distance_to(_last_cam) > jump_threshold:
		reason = "jump"
	elif _last_fwd != Vector3.ZERO and fwd.angle_to(_last_fwd) > deg_to_rad(turn_threshold_deg):
		reason = "flick"
	elif _ref_fwd != Vector3.ZERO and _since_prime >= minimum_interval and fwd.angle_to(_ref_fwd) > deg_to_rad(accum_turn_deg):
		reason = "accum"
	_last_cam = p
	_last_fwd = fwd
	if reason == "":
		return
	_force = false
	_ref_fwd = fwd
	_since_prime = 0.0
	last_reason = reason
	if not _scanned:
		_scan()
	var t0 := Time.get_ticks_usec()
	var n := _objs.size()
	for i in n:
		if is_instance_valid(_objs[i]):
			RenderingServer.instance_geometry_set_visibility_range(_rids[i], _vals[i * 4], _vals[i * 4 + 1], 0.0, 0.0, RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)
	_priming = true
	primes += 1
	last_prime_usec = Time.get_ticks_usec() - t0


func _on_post_draw() -> void:
	if _priming:
		_restore()


func _restore() -> void:
	var t0 := Time.get_ticks_usec()
	var n := _objs.size()
	for i in n:
		if is_instance_valid(_objs[i]):
			RenderingServer.instance_geometry_set_visibility_range(_rids[i], _vals[i * 4], _vals[i * 4 + 1], _vals[i * 4 + 2], _vals[i * 4 + 3], RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)
	_priming = false
	last_restore_usec = Time.get_ticks_usec() - t0
