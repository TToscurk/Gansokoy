@tool
extends Node3D
## P13 W9 Round 2：建築外形サンプル overlay（`ArchW9R2P13`・tools/p13/w9/build_w9r2.gd が産生）。
## 子＝建築 id ごとの Node3D（body と同じ transform）＋ L0／L1 メッシュ。metadata：body_path（village 直下から）、hide（カテゴリごとの接頭辞）。
## enabled=true：該当建築の Kit 構件のうち hide0／hide12 の接頭辞に合うものを非表示にし、新メッシュを見せる。
##   材質は建築自身の Kit 構件に付いている覆寫（W7 Albedo／W8 LodCal）を同じ基底材質の面にコピーする（隣と明度がずれない）。
## enabled=false：非表示にした Kit 構件を元の visible に戻し、新メッシュを隠す（Before と同じ状態）。
## @tool（2026-10-17）：編輯器裡也套用同樣的隱藏，否則編輯器同時畫舊 Kit 與新外形 → 屋頂兩層互穿、共面構件閃爍（z-fighting）。
##   存檔前（NOTIFICATION_EDITOR_PRE_SAVE）先全部還原、存完（POST_SAVE）再套回 → village_v2.tscn 不會被寫進 visible=false／材質覆寫。
##   編輯器裡不動庇柱碰撞（_posts 只在遊戲中切換）。驗證：tools/p13/w9/verify_editor_tool_overlays.gd。
## W9 FIX（2026-10-17）：外形が変わった 22 棟は <id>/Shell（collision_fit.json の箱）を持つ。有効の間は body の元の箱を無効・Shell を有効にする
##   （_shell）。編輯器でも同じに切り替える＝碰撞 gizmo が遊戲中の実際の碰撞を表す。存檔前は _restore で元の disabled に戻る。
@export var enabled := true:
	set(v):
		enabled = v
		if _booted or (Engine.is_editor_hint() and is_inside_tree()):
			_booted = true
			_apply(v)

var _booted := false
var _hidden: Array = []      # [MeshInstance3D, 元の visible]
var _mats: Array = []        # [MeshInstance3D, surface, 元の override]
var _cols: Array = []        # [CollisionShape3D, 元の disabled]（_shell が切り替えたもの）
var hidden_count := 0
var copied_surfaces := 0
var r1_hidden := 0
## W9 R1（EnrichW9P13）が壁・軒に『吊った』物のうち、R2 で作り直した正面・庇と重なるもの（簾・吊柿・杉玉・笊・草履）。R2／R2.1 の 16 棟でだけ隠す（暖簾・地面の物は残す）。
const R1_HANG := ["sudare", "kaki", "sugi", "zaru", "zori"]


func _ready() -> void:
	# 碰撞の入れ替えだけは同期で行う（W9 FIX 生存期間）：_boot は W7／W8 の材質を待って 2 フレーム遅れる。その間に物理フレームが走ると
	# 元の箱が効いたまま——読檔（main._on_load_requested：load_map の直後に玩家を置く）で、修正で歩けるようになった所に立っていた玩家が
	# 押し出された（w9fix_lifecycle_real.gd：MXC_007 の見世で 0.44 m）。_apply は _restore→_shell を同期で行うので二重にならない。
	if enabled:
		_shell()
	_boot.call_deferred()


func _boot() -> void:
	# W7 AlbedoBatch1P13／W8 LodCalBatch1P13 は call_deferred で apply する → それより後で材質を読む
	await get_tree().process_frame
	await get_tree().process_frame
	_booted = true
	_apply(enabled)


func _notification(what: int) -> void:
	# 編輯器存檔：存的是『沒有被本腳本改過』的原狀態（只在編輯器發生；遊戲中不會收到）
	# _ready で碰撞だけ先に入れ替えるので、_boot 前（2 フレーム）の存檔でも元へ戻す（_restore は空なら何もしない）
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_restore()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		if _booted:
			_apply(enabled)
		elif enabled:
			_shell()


func _restore() -> void:
	r1_hidden = 0
	for h in _hidden:
		if is_instance_valid(h[0]):
			(h[0] as Node3D).visible = h[1]
	_hidden.clear()
	for a in _mats:
		if is_instance_valid(a[0]):
			(a[0] as MeshInstance3D).set_surface_override_material(int(a[1]), a[2])
	_mats.clear()
	for c in _cols:
		if is_instance_valid(c[0]):
			(c[0] as CollisionShape3D).disabled = c[1]
	_cols.clear()
	hidden_count = 0
	copied_surfaces = 0


func _kit_meshes(kit: Node, lods: Array) -> Array:
	var out: Array = []
	for l: int in lods:
		var g := kit.get_node_or_null("LOD%d" % l)
		if g:
			for c in g.get_children():
				if c is MeshInstance3D:
					out.append(c)
	return out


func _posts(on: bool) -> void:
	## 庇柱・玄関柱の碰撞（Posts/PostN）：overlay が有効の間だけ有効。Before（enabled=false）では柱が無いので碰撞も無し。
	for c in get_children():
		var sb := c.get_node_or_null("Posts")
		if sb == null:
			continue
		for cs in sb.get_children():
			if cs is CollisionShape3D:
				(cs as CollisionShape3D).set_deferred("disabled", not on)


func _shell() -> void:
	## 元の箱（Kit の外形に合わせた body/Shape）→ 作り直した外形の箱（<id>/Shell）。disabled は直接切り替える
	## （set_deferred だと _restore→_shell の連続呼び出しで『元の値』を取り違える）。
	var vil := get_parent()
	for b in get_children():
		var sh := b.get_node_or_null("Shell")
		var body := vil.get_node_or_null(NodePath(String(b.get_meta("body_path", ""))))
		if sh == null or body == null:
			continue
		for cs in body.get_children():
			if cs is CollisionShape3D:
				_cols.append([cs, (cs as CollisionShape3D).disabled])
				(cs as CollisionShape3D).disabled = true
		for cs in sh.get_children():
			if cs is CollisionShape3D:
				_cols.append([cs, (cs as CollisionShape3D).disabled])
				(cs as CollisionShape3D).disabled = false


func _apply(on: bool) -> void:
	_restore()
	visible = on
	if not Engine.is_editor_hint():
		_posts(on)
	if not on:
		return
	_shell()
	var vil := get_parent()
	var r1 := vil.get_node_or_null("EnrichW9P13")
	if r1 != null:
		var ids := {}
		for c in get_children():
			ids[String(c.get_meta("body_path", "")).get_file()] = c.get_meta("keep_r1", PackedStringArray())   # 隠さない種類（Phase 7：017 の杉玉）
		for z in r1.get_children():
			for cl in z.get_children():
				for it in cl.get_children():
					var fb := String(it.get_meta("w9_b", ""))
					var ft := String(it.get_meta("w9_feature", ""))
					if it is Node3D and ids.has(fb) and R1_HANG.has(ft) and not (ids[fb] as PackedStringArray).has(ft):
						_hidden.append([it, (it as Node3D).visible])
						(it as Node3D).visible = false
						r1_hidden += 1
	for b in get_children():
		if not b is Node3D:
			continue
		var body := vil.get_node_or_null(NodePath(String(b.get_meta("body_path", "")))) as Node3D
		if body == null:
			continue
		var kit := body.get_node_or_null("Kit")
		if kit == null:
			continue
		for lod in 3:
			var pre: PackedStringArray = b.get_meta("hide0" if lod == 0 else "hide12", PackedStringArray())
			var g := kit.get_node_or_null("LOD%d" % lod)
			if g == null or pre.is_empty():
				continue
			var all_but_base := pre.has("*")       # 全面置換：base（基礎）以外の Kit 構件を全部隠す
			for mi in g.get_children():
				if not mi is MeshInstance3D:
					continue
				if all_but_base:
					if not String(mi.name).begins_with("base"):
						_hidden.append([mi, (mi as MeshInstance3D).visible])
						(mi as MeshInstance3D).visible = false
						hidden_count += 1
					continue
				for p in pre:
					if String(mi.name).begins_with(p):
						_hidden.append([mi, (mi as MeshInstance3D).visible])
						(mi as MeshInstance3D).visible = false
						hidden_count += 1
						break
		# 材質の覆寫をコピー：L0 ← Kit LOD0、L1 ← Kit LOD1／LOD2
		for lm in b.get_children():
			if not lm is MeshInstance3D:
				continue
			var src := _kit_meshes(kit, [0] if String(lm.name) == "L0" else [1, 2])
			var mesh := (lm as MeshInstance3D).mesh
			for si in mesh.get_surface_count():
				var base := mesh.surface_get_material(si)
				if base == null:
					continue
				var done := false
				for s in src:
					var sm := (s as MeshInstance3D).mesh
					for sj in sm.get_surface_count():
						if sm.surface_get_material(sj) == base:
							var ov := (s as MeshInstance3D).get_surface_override_material(sj)
							if ov != null:
								_mats.append([lm, si, (lm as MeshInstance3D).get_surface_override_material(si)])
								(lm as MeshInstance3D).set_surface_override_material(si, ov)
								copied_surfaces += 1
								done = true
								break
					if done:
						break
