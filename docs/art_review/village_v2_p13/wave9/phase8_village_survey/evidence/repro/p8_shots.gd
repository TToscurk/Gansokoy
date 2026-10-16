extends "res://tools/p13/w6/w6_base.gd"
## [scratch copy for P13 W9 Phase 8 survey: + --show=Debug,QuestAnchors（正式流程不隱藏的除錯層，ReviewStart 會隱藏）] P13 Wave 7 撮影ハーネス（唯読・場景ファイルは書かない）。W6 の共通ハーネス（正式 main.tscn → ReviewStart → village_v2、実際の玩家と
## TPS 相機、10:00、Forward+、1600×900）を継承し、代表鏡位を 1 プロセスでまとめて撮る。
##   godot --path . --script res://tools/p13/w7/w7_shots.gd -- <outdir/> <tag> [--at=name:x,z,tx,tz;…] [--free=name:cx,cy,cz,tx,ty,tz,fov;…]
##                                                              [--disable=NodeA,NodeB] [--id]
##   --at     ：玩家を (x,z) に置き (tx,tz) 方向を向かせた通常 TPS（w6_survey2 と同じ規約。W6 の ab_* と同じ座標なら同機位）
##   --free   ：自由相機（俯瞰・近接）。玩家は隠す。fov 省略＝55
##   --disable：root 直下の指定 overlay を enabled=false にして撮る（Before 用）
##   --remove ：root 直下の指定 overlay を碰撞ごと取り除いて撮る（その overlay が無い元の場景の SpringArm を見るため）
##   --id     ：同じ鏡位の ID パス（各画素＝どの節点が描いたか）も撮る
##   --swap=Name=res://path.scn  ：root 直下の overlay Name を、別の（旧版の）シーンの instance に差し替えてから撮る（Before 用・同ハーネスで比較するため）
##   --lodcycle ：--free の各鏡位を、全町家の LOD0／LOD1／LOD2 を強制的に 1 つずつ見せて 3 枚撮る（<tag>_<name>_L0／_L1／_L2）。距離による LOD 切替・hysteresis に依存しない
## 出力：<tag>_<name>.png ＋ <tag>_index.json（相機記録）＋ --id のとき <tag>_<name>_id.png／<tag>_idtable.json
const SA2 := preload("res://tools/village_v2_shrine_approach_lib.gd")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var tag := args[1]
	var want_id := false
	var disables: Array = []
	var shows: Array = []
	var mounts: Array = []   # [name, res path, after]（記憶の中だけで overlay を掛ける：village_v2.tscn は書かない）
	var removes: Array = []  # root 直下の overlay を碰撞ごと取り除く（Phase 4 R1b：『その overlay が無い元の場景』の相機を撮るため）
	var swaps: Array = []   # [name, res path]
	var lodcycle := false
	var ats: Array = []     # [name, Vector2 pos, Vector2 tgt]
	var frees: Array = []   # [name, Vector3 pos, Vector3 tgt, fov]
	for a: String in args:
		if a == "--id":
			want_id = true
		elif a == "--lodcycle":
			lodcycle = true
		elif a.begins_with("--swap="):
			var sw := a.trim_prefix("--swap=").split("=", false, 1)
			swaps.append([sw[0], sw[1]])
		elif a.begins_with("--disable="):
			disables.append_array(a.trim_prefix("--disable=").split(",", false))
		elif a.begins_with("--mount="):
			var mt := a.trim_prefix("--mount=").split("=", false, 1)
			var pa := mt[1].split("@")
			mounts.append([mt[0], pa[0], pa[1] if pa.size() > 1 else ""])
		elif a.begins_with("--show="):
			shows.append_array(a.trim_prefix("--show=").split(",", false))
		elif a.begins_with("--remove="):
			removes.append_array(a.trim_prefix("--remove=").split(",", false))
		elif a.begins_with("--at="):
			for it: String in a.trim_prefix("--at=").split(";", false):
				var kv := it.split(":")
				var c := kv[1].split(",")
				ats.append([kv[0], Vector2(float(c[0]), float(c[1])), Vector2(float(c[2]), float(c[3]))])
		elif a.begins_with("--free="):
			for it: String in a.trim_prefix("--free=").split(";", false):
				var kv2 := it.split(":")
				var c2 := kv2[1].split(",")
				frees.append([kv2[0], Vector3(float(c2[0]), float(c2[1]), float(c2[2])), Vector3(float(c2[3]), float(c2[4]), float(c2[5])), float(c2[6]) if c2.size() > 6 else 55.0])
	DirAccess.make_dir_recursive_absolute(out)
	cl = SA2.centerline()
	await _boot()
	for rn: String in removes:
		var rnode := vil.get_node_or_null(NodePath(rn))
		if rnode != null:
			vil.remove_child(rnode)
			rnode.free()
			print("[W7S] removed ", rn)
		else:
			print("[W7S] remove: node not found ", rn)
	if not removes.is_empty():
		for i in 4:
			await physics_frame
	for dn: String in disables:
		var dnode := vil.get_node_or_null(NodePath(dn))
		if dnode != null:
			if "enabled" in dnode:
				dnode.set("enabled", false)
			else:
				# enabled を持たない純粋な overlay（W9 以降）：見えなくする（撮影用。碰撞は止めない）
				(dnode as Node3D).visible = false
			print("[W7S] disabled ", dn)
		else:
			print("[W7S] disable: node not found ", dn)
	for sw2: Array in swaps:
		var old := vil.get_node_or_null(NodePath(String(sw2[0])))
		if old == null:
			print("[W7S] swap: node not found ", sw2[0])
			continue
		var ix := old.get_index()
		old.set("enabled", false)
		vil.remove_child(old)
		old.free()
		var inst := (load(String(sw2[1])) as PackedScene).instantiate()
		inst.name = String(sw2[0])
		vil.add_child(inst)
		vil.move_child(inst, ix)
		print("[W7S] swapped ", sw2[0], " ← ", sw2[1], " (index ", ix, ")")
	for mt2: Array in mounts:
		var inst2 := (load(String(mt2[1])) as PackedScene).instantiate()
		inst2.name = String(mt2[0])
		vil.add_child(inst2)
		var after_n := vil.get_node_or_null(NodePath(String(mt2[2]))) if String(mt2[2]) != "" else null
		if after_n != null:
			vil.move_child(inst2, after_n.get_index() + 1)
		print("[W7S] mounted (memory only) ", mt2[0], " ← ", mt2[1], " index ", inst2.get_index())
	if not mounts.is_empty():
		for i in 4:
			await physics_frame
	for sn: String in shows:
		var snode := vil.get_node_or_null(NodePath(sn))
		if snode != null:
			(snode as Node3D).visible = true
			print("[W7S] shown ", sn)
	await _frames(6)
	var index: Array = []
	for i in ats.size():
		var at: Array = ats[i]
		var p0: Vector2 = at[1]
		var face := (Vector2(at[2]) - p0).normalized()
		await _tpw(p0, face)
		var nm := "%s_%s" % [tag, at[0]]
		await _shot(nm, 6)
		var rec := cam_record()
		rec["name"] = nm
		rec["kind"] = "at"
		index.append(rec)
	if not frees.is_empty():
		_free_begin()
		for fr: Array in frees:
			if lodcycle:
				for k in 3:
					_force_lod(k)
					var nm3 := "%s_%s_L%d" % [tag, fr[0], k]
					await _free(nm3, fr[1], fr[2], fr[3])
					var rec3 := cam_record()
					rec3["name"] = nm3
					rec3["kind"] = "free_lod%d" % k
					index.append(rec3)
				continue
			var nm2 := "%s_%s" % [tag, fr[0]]
			await _free(nm2, fr[1], fr[2], fr[3])
			var rec2 := cam_record()
			rec2["name"] = nm2
			rec2["kind"] = "free"
			index.append(rec2)
		await _free_end()
	if want_id:
		if lodcycle:
			_force_lod(-1)   # 非表示の LOD 節点には ID 材質が配られないので、id_begin の前に全 LOD を表示状態にしておく
		var n := id_begin()
		print("[W7S] ID パス：節点 ", n, " bits ", _id_bits)
		await _frames(6)
		for at2: Array in ats:
			var q: Vector2 = at2[1]
			await _tpw(q, (Vector2(at2[2]) - q).normalized())
			await _shot("%s_%s_id" % [tag, at2[0]], 6)
		if not frees.is_empty():
			_free_begin()
			for fr2: Array in frees:
				if lodcycle:
					for k2 in 3:
						_force_lod(k2)
						await _free("%s_%s_L%d_id" % [tag, fr2[0], k2], fr2[1], fr2[2], fr2[3])
					continue
				await _free("%s_%s_id" % [tag, fr2[0]], fr2[1], fr2[2], fr2[3])
			await _free_end()
		id_end()
		id_table_save(out + tag + "_idtable.json")
	var f := FileAccess.open(out + tag + "_index.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(index, "\t") + "\n")
	f.close()
	print("[W7S] DONE ", index.size())
	quit(0)


## 全町家の Kit を LOD<k> だけにする（visibility_range を無効化して距離切替・hysteresis に依存しない）。診断専用。
func _force_lod(k: int) -> void:
	var n := 0
	for b in vil.get_node("Districts").find_children("B_*", "Node3D", true, false):
		var kit := b.get_node_or_null("Kit")
		if kit == null:
			continue
		for li in 3:
			var ln := kit.get_node_or_null("LOD%d" % li) as Node3D
			if ln == null:
				continue
			ln.visible = (k < 0) or (li == k)
			for g in ln.find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).visibility_range_begin = 0.0
				(g as GeometryInstance3D).visibility_range_end = 0.0
			n += 1
	print("[W7S] forced LOD", k, " on ", n, " lod nodes")
