extends "res://characters/yoriichi/yoriichi_character_r6.gd"
## R6.1 候選控制器「Yoriichi R6.1 Final Candidate Refinement」（只給 player_yoriichi_r61.tscn 用）。
## 正式 yoriichi_character.gd、R5 子類、R6 子類 yoriichi_character_r6.gd 一行不改；R6 場景保留為對照基準。
## R6.1 的變更幾乎都在資料層（make_r61_candidate.gd 寫進場景）：
##   - 角色模型換成候選 GLB v24_r61/yoriichi_v24_r61.glb（只改袖段與袴的蒙皮權重；骨架、骨名、網格、材質、比例不變）
##   - 跳躍 起跳／空中／落地 換成新來源（Mixamo「Unarmed Jump」，視線鎖在待機高度；起跳時間參數與 R6 相同）
##   - 拔刀斬 R6.1 版（只把出鞘段水平化；逆袈裟主斬線、總長、命中窗不變）、握刀指形 R6.1 版、雙手左握 R6.1 版
## 重斬命中判定時序沿用 R6（本輪不改，差異另以文件記錄）。
##
## 唯一的程式變更：拔刀斬「移動取消」的接續點。
##   R5 在 upper 層只每 6 格建一個納刀尾段起點，移動取消時取「≤ 目前格」的最近起點，片段時間會倒退最多 5 格
##   （R6 實測：f81 取消 → 退回 f76.5，已入鞘的刀在手上重新出現約 0.1 s，再入鞘一次；f75 取消 → 退回 f70）。
##   R6.1 在既有起點之間補上逐格起點，取消直接從當格接續：不倒退、不重播入鞘。取消的條件、時機與輸入反應不變。
@export var r61_tail_every_frame := true


func _r5_install() -> void:
	super._r5_install()
	if not r61_tail_every_frame or not r5_enabled or _tree == null or r5_quickdraw_resource == null:
		return
	var root := _tree.tree_root as AnimationNodeBlendTree
	var usel := root.get_node("upper_sel") as AnimationNodeTransition
	var a := r5_quickdraw_resource
	var have := {}
	for t in _r5_tails:
		have[t] = true
	for f in range(r5_cancel_frame, _r5_n - 4):
		if have.has(f):
			continue
		var ui := usel.input_count
		usel.input_count = ui + 1
		var key := "r5_tail_%d" % f
		usel.set_input_name(ui, key)
		usel.set_input_reset(ui, true)
		root.add_node("upper_sel_" + key, _clip_node(R5_ANIM, float(f) / _r5_fps, a.length))
		root.connect_node("upper_sel", ui, "upper_sel_" + key)
		_r5_tails.append(f)
	_r5_tails.sort()

## 已知未解（R5／R6 同樣存在，本輪只量測、未修）：取消交接的前 2 格右臂會偏離同一格的拔刀斬姿勢約 40–49°
## （0.067 s；R6 在 f70 對齊格取消也一樣）。曾試 upper_sel 0 秒切入、full 層延後 2 格淡出，偏差只往後移、未消失，
## 已撤回，避免無效的改動。
