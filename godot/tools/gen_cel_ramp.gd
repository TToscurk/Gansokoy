extends SceneTree
## 光影分層（cel-shading）：用 Environment 的色彩校正漸層把連續明暗切成階梯。
##
##   Godot --headless --path godot --script tools/gen_cel_ramp.gd
##
## 為什麼走這條路而不是改材質：
##   slice 的建築材質全部內嵌在 Meshy GLB 裡（70 棟町家 + 14 地標），逐一
##   換成自訂 shader 等於重做整套資產匯入，而且 ART_APPROVED 過的東西不能
##   隨便動。Environment.adjustment_color_correction 吃一張 GradientTexture1D，
##   在 tonemap 之後對**最終亮度**做查表——把那張表做成階梯，畫面的明暗就
##   從連續變成分層，材質、光照、陰影全部原封不動。
##
## 階數與轉折點是可調的：`階數` 決定切幾層，`柔和度` 決定每階邊界要多硬。
## 0 = 純硬邊（最強烈的賽璐珞感），0.5 = 半軟，1.0 = 幾乎回到連續。

const OUT_DIR := "res://assets/materials/cel"

## 每一組：檔名尾綴、階數、柔和度、暗部保底（避免陰影全黑成一塊）
const VARIANTS := [
	["2階_硬", 2, 0.04, 0.10],
	["3階_硬", 3, 0.04, 0.08],
	["3階_柔", 3, 0.16, 0.08],
	["4階_柔", 4, 0.14, 0.06],
]


func _init() -> void:
	var dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)

	for v in VARIANTS:
		var name: String = v[0]
		var steps: int = v[1]
		var soft: float = v[2]
		var floor_lift: float = v[3]

		var g := Gradient.new()
		g.offsets = PackedFloat32Array()
		g.colors = PackedColorArray()
		# 先清掉 Gradient 預設的兩個點
		while g.get_point_count() > 0:
			g.remove_point(0)

		# 每一階：在階界前後各放一個點，距離 = 柔和度。
		# 階的「值」取該階中點，這樣整體亮度不會被推高或壓低。
		for i in steps:
			var lo := float(i) / float(steps)
			var hi := float(i + 1) / float(steps)
			var mid := (lo + hi) * 0.5
			# 暗部保底：最暗那階抬高一點，陰影裡才留得住材質。
			# 全黑一塊是 cel-shading 最常見的失敗，美術規格 §1 要的是
			# 「高調明亮」，不是壓暗。
			var val: float = lerpf(mid, 1.0, floor_lift * (1.0 - mid))
			g.add_point(maxf(lo + soft, 0.0), Color(val, val, val))
			g.add_point(minf(hi - soft, 1.0), Color(val, val, val))

		var tex := GradientTexture1D.new()
		tex.gradient = g
		tex.width = 256
		# use_hdr：色彩校正在 tonemap 之後套用，SDR 就夠；但關掉會讓
		# 高光被夾到 1.0 之前就先量化，亮部的階會提早出現。
		tex.use_hdr = true

		var path := "%s/cel_ramp_%s.tres" % [OUT_DIR, name]
		var err := ResourceSaver.save(tex, path)
		print("[RAMP] %s  階數=%d 柔和度=%.2f 保底=%.2f  → %s (err=%d)" % [
			name, steps, soft, floor_lift, path, err])

	print("[RAMP] done")
	quit(0)
