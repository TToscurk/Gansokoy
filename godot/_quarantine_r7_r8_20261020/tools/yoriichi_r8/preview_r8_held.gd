extends "res://tools/yoriichi_r7/preview_mixamo_src.gd"
## R8 素材預覽（持刀版）：沿用 R7 預覽工具，只多做一件事——刀顯示在手上（Sword_Hand 可見、鞘中刀隱藏），
## 讓「素材原本的雙手手勢＋真刀」直接看得到刀路。不寫任何資源／場景；AnimationTree 與控制器物理仍停用。
##   godot --path godot --fixed-fps 60 -s res://tools/yoriichi_r8/preview_r8_held.gd -- <anim_res> <out_dir_name> [side|f34|rear] [follow]

func _run() -> void:
	var t := Timer.new()
	root.add_child(t)
	_arm_sword.call_deferred()
	super._run()

func _arm_sword() -> void:
	# 等 Player 進樹（super 會在兩個 process_frame 後建立），每格強制刀在手上
	for i in 600:
		await process_frame
		var p = root.find_child("Player*", true, false)
		if p == null:
			for c in root.get_children():
				if c is CharacterBody3D:
					p = c
		if p == null:
			continue
		var sh = p.get("_sword_hand")
		var ss = p.get("_sword_sheathed")
		if sh != null:
			sh.visible = true
		if ss != null:
			ss.visible = false
