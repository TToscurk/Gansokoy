extends "res://tools/beast_path/tps_shots.gd"
## S01/S02 接縫（z=-100）專用俯視擷取：只看地面。
##   godot --path godot --script res://tools/beast_path/seam_shots.gd -- --map=beast_path --out=<dir> --hour=10 --w=1600 --h=900 --hide=forest,props
## 每個視角各拍一張原樣（<名>.png）與一張把含 forest／props 的節點隱藏後的（<名>__h1.png）。
## 後者沒有樹與道具的影子，地面色彩的任何階梯都只可能來自地表材質／接縫本身。


func _views() -> Array:
	var cx := 9.06            # 主路中心線在 z=-100 的 x（probe_s01_density 輸出的路徑取樣）
	var cz := -99.7
	var v: Array = []
	for pair in [["y_seam_road", 0.0], ["y_seam_east", 22.0], ["y_seam_west", -22.0]]:
		var nm: String = pair[0]
		var dx: float = pair[1]
		v.append({"name": nm, "free": {"cam": [cx + dx, 0.0, cz + 0.5], "look": [cx + dx, 0.0, cz - 0.2], "cam_above": 42.0, "look_above": 0.0}})
	return v


## 覆寫：精確比對節點名稱（基底類別是「名稱含子字串」，會把 S02_deep_forest 整個場景一起藏掉）
func _hide_matching(tokens: PackedStringArray) -> Array[Node3D]:
	var res: Array[Node3D] = []
	for n in main.find_children("*", "Node3D", true, false):
		var n3 := n as Node3D
		if n3.visible and tokens.has(String(n3.name)):
			n3.visible = false
			res.append(n3)
	return res
