extends SceneTree
## P11 R2C B（只讀、headless、場景不載入）：既存の水車 2 竜骨車系統から N0／T0 へ低位の木槽で回せるかの地面プロファイル。
##   N0：落とし桝（水面 0.28）→ N0 進水口（要求水面 0.168）
##   T0：送り樋（樋底 0.53→0.50、水面 ≈0.55）→ T0 進水口（要求水面 0.368）
const FZ := preload("res://tools/village_v2_farmland_zone.gd")
const ROUTES := [
	["N0 ← 落とし桝", Vector2(338.9, 4.85), Vector2(352.35, -45.2), 0.28, 0.168],
	["T0 ← 送り樋", Vector2(337.0, 4.85), Vector2(330.2, 78.0), 0.55, 0.368],
]

func _init() -> void:
	for r in ROUTES:
		var a: Vector2 = r[1]
		var b: Vector2 = r[2]
		var L := a.distance_to(b)
		var prof := []
		var hi := -INF
		var over := 0
		for k in 41:
			var t := k / 40.0
			var g := FZ.ground_h(a.lerp(b, t))
			var wl := lerpf(float(r[3]), float(r[4]), t)
			prof.append(snappedf(g, 0.01))
			hi = maxf(hi, g)
			if g > wl - 0.10:
				over += 1
		var head := float(r[3]) - float(r[4])
		print("[ROUTE] %s 長 %.1f m 水頭 %.3f m（勾配 %.2f %%）地面最高 %.2f、水面−0.10 より高い地面 %d/41 点  地面 %s" % [r[0], L, head, head / L * 100.0, hi, over, str(prof)])
	quit(0)
