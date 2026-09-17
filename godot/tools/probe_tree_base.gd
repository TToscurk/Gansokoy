extends SceneTree
## 量 assets/landscape/ 每棵樹的「底部乾淨度」。
## 判準（全部用頂點實測，不靠肉眼）：
##   base_r   = 最低 3% 高度帶的水平半徑（含泥塊／底盤）
##   trunk_r  = 25%~35% 高度帶的水平半徑（乾淨樹幹）
##   ratio    = base_r / trunk_r ；>2.5 代表底部掛了一坨泥塊/底座
##   ymin     = 最低點 Y（>0.05 m 代表懸空；<-0.05 代表沉進地下）
##   loose    = 最低帶裡離中心 >1.5×trunk_r 的頂點比例（碎塊/浮根）

const LS := "res://assets/landscape/"
const FILES := ["普通樹.glb", "大衫.glb", "2大衫.glb", "針葉樹1.glb",
	"針葉樹2glb.glb", "針葉林樹3.glb", "針葉林樹4.glb", "盆樹.glb",
	"櫻花樹.glb", "楓樹.glb", "松樹.glb", "鎮守之杜.glb", "竹垣.glb"]

func _init() -> void:
	_run.call_deferred()

func _collect(node: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if node is Node3D:
		t = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in verts:
				out.append(t * v)
	for c in node.get_children():
		_collect(c, t, out)

func _run() -> void:
	print("%-12s %7s %7s %7s %7s %7s %7s  %s" % ["檔名", "高m", "ymin", "base_r", "trunk_r", "ratio", "loose%", "判定"])
	for f in FILES:
		var path: String = LS + f
		if not ResourceLoader.exists(path):
			print("%-12s 缺檔" % f)
			continue
		var inst: Node = (load(path) as PackedScene).instantiate()
		var pts: Array = []
		_collect(inst, Transform3D.IDENTITY, pts)
		inst.free()
		if pts.is_empty():
			print("%-12s 無頂點" % f)
			continue
		var ymin: float = INF
		var ymax: float = -INF
		for p in pts:
			ymin = minf(ymin, p.y)
			ymax = maxf(ymax, p.y)
		var h: float = ymax - ymin
		# 水平中心用 25~35% 帶的重心（樹幹中心），避免樹冠偏心干擾
		var lo: float = ymin + h * 0.25
		var hi: float = ymin + h * 0.35
		var c := Vector2.ZERO
		var n := 0
		for p in pts:
			if p.y >= lo and p.y <= hi:
				c += Vector2(p.x, p.z)
				n += 1
		if n > 0:
			c /= float(n)
		var trunk_r := 0.0
		for p in pts:
			if p.y >= lo and p.y <= hi:
				trunk_r = maxf(trunk_r, Vector2(p.x, p.z).distance_to(c))
		var band: float = ymin + h * 0.03
		var base_r := 0.0
		var loose := 0
		var bn := 0
		for p in pts:
			if p.y <= band:
				var d: float = Vector2(p.x, p.z).distance_to(c)
				base_r = maxf(base_r, d)
				bn += 1
				if trunk_r > 0.0001 and d > trunk_r * 1.5:
					loose += 1
		var ratio: float = base_r / maxf(trunk_r, 0.0001)
		var loose_pct: float = 100.0 * float(loose) / maxf(float(bn), 1.0)
		var verdict := "乾淨"
		var flags: Array = []
		if ratio > 2.5:
			flags.append("底盤/泥塊 x%.1f" % ratio)
		if loose_pct > 40.0:
			flags.append("散碎%.0f%%" % loose_pct)
		if ymin > 0.05:
			flags.append("懸空%.2fm" % ymin)
		elif ymin < -0.05:
			flags.append("沉沒%.2fm" % ymin)
		if not flags.is_empty():
			verdict = " / ".join(flags)
		print("%-12s %7.2f %7.2f %7.2f %7.2f %7.2f %7.1f  %s" % [f, h, ymin, base_r, trunk_r, ratio, loose_pct, verdict])
	quit()
