extends Control
## 玩家生命／軀幹／日之呼吸（左下角）。純程式繪製，數值全來自 CombatHUD。
##
## 幻想鄉 × 緣一 版（ui/gensokyo 規格 HEALTH / STAMINA）：
##   * 徽記：円相（墨圈）圍住日輪。日輪 12 道焰 = 日之呼吸量（亮幾道 = 幾成），
##     滿了日輪慢慢呼吸、旁邊出「C 拾參ノ型」—— 呼吸不再佔一條橫條。
##   * 生命：仍然水平閱讀、仍然分節（隻狼「還剩幾下」），但每節是一筆暗朱毛筆觸，
##     底是極淡墨痕；低血量時轉日之呼吸橙紅。
##   * 軀幹：比生命更低調的細墨線，照舊由中央往兩側長，顏色規則沿用 CombatHUD.posture_colour。

@export var bar_width := 300.0
@export var health_height := 13.0
@export var posture_height := 5.0
@export var gap := 9.0
@export var emblem_radius := 25.0

var _hud: Node = null


func _ready() -> void:
	_hud = get_parent().get_parent()


func _draw() -> void:
	if _hud == null:
		return
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	var er := emblem_radius * k
	var ec := Vector2(er, size.y - er - 4.0 * k)
	var x0 := er * 2.0 + 14.0 * k
	var bw := bar_width * k
	var hh := health_height * k
	var ph := posture_height * k
	var hy := ec.y - hh - 2.0 * k
	var py := hy + hh + gap * k * 0.6

	# --- 徽記：円相 + 日輪（呼吸量）---------------------------------------
	var breath: float = _hud.player_breath_ratio
	var full: bool = breath >= 0.999
	var pulse: float = 0.5 + 0.5 * sin(_hud._pulse * 1.6)
	# 淡墨暈底，讓徽記在亮地面上也讀得到
	draw_circle(ec, er * 1.12, Color(st.ink_black, st.hud_background * 0.55))
	GensokyoInk.enso(self, ec, er, 3.2 * k, Color(st.ink_black, 0.92), 1.7, 1.0, 0.12)
	GensokyoInk.enso(self, ec, er - 0.5 * k, 1.2 * k, Color(st.old_gold, 0.55), 1.7, 1.0, 0.16)
	var lit := int(floor(breath * 12.0 + 0.001))
	var sr := er * 0.36
	for i in 12:
		var a := -PI * 0.5 + TAU * i / 12.0
		var d := Vector2(cos(a), sin(a))
		var side := Vector2(-d.y, d.x)
		var p0 := ec + d * sr * 1.12
		var tip := ec + d * sr * 1.85 + side * sr * 0.22
		var col: Color
		if i < lit:
			col = st.accent(st.sun_accent) if not full else st.accent(st.sun_accent).lerp(Color("#F2C98A"), pulse * 0.6)
		else:
			col = Color(st.washi_ivory, 0.16)
		draw_colored_polygon(PackedVector2Array([p0 - side * sr * 0.2, tip, p0 + side * sr * 0.2]), col)
	var core := st.accent(st.dark_vermilion) if breath > 0.0 else Color(st.ink_grey, 0.7)
	if full:
		for g in 3:
			draw_circle(ec, sr * (1.3 + 0.35 * g), Color(st.sun_accent, 0.07 * pulse * (3 - g)))
		core = st.accent(st.sun_accent)
	draw_circle(ec, sr, core)
	draw_arc(ec, sr, 0, TAU, 24, Color(st.ink_black, 0.6), 1.0 * k, true)

	# --- 生命：分節毛筆觸 ---------------------------------------------------
	var seg: int = maxi(_hud.health_segments, 1)
	var seg_gap := 5.0 * k
	var seg_w: float = (bw - seg_gap * (seg - 1)) / seg
	var filled: float = _hud.player_health_ratio * seg
	var low: bool = _hud.player_health_ratio <= 0.3
	# 底：一筆淡墨痕墊在生命節下（亮地面也讀得到），收筆不超出末節太多
	GensokyoInk.stroke(self, Rect2(Vector2(x0 - 4.0 * k, hy - 2.0 * k), Vector2(bw + 8.0 * k, hh + 4.0 * k)),
		Color(st.ink_black, st.hud_background * 0.6), 0.4, 1.6 * k, 1.0, 0.1, 0.5)
	for i in seg:
		var x := x0 + i * (seg_w + seg_gap)
		var r := Rect2(Vector2(x, hy), Vector2(seg_w, hh))
		var f: float = clampf(filled - i, 0.0, 1.0)
		if f > 0.0:
			var col := st.accent(st.dark_vermilion) if not low else st.accent(st.sun_accent)
			GensokyoInk.stroke(self, r, col, 10.0 + i * 3.1, 1.6 * k, f, 0.25, 0.55)
			GensokyoInk.dry_brush(self, r, Color(st.ink_black, 0.35), 10.0 + i, f)
		else:
			GensokyoInk.stroke(self, r.grow(-1.0 * k), Color(st.washi_ivory, 0.07), 10.0 + i * 3.1, 1.2 * k, 1.0, 0.25, 0.55)

	# --- 軀幹：細墨線，中央往兩側 --------------------------------------------
	var mid := x0 + bw * 0.5
	draw_line(Vector2(x0, py + ph * 0.5), Vector2(x0 + bw, py + ph * 0.5), Color(st.ink_black, st.hud_background * 0.55), ph, true)
	var half: float = _hud.player_posture_ratio * bw * 0.5
	if half > 0.0:
		var pc: Color = _hud.posture_colour(_hud.player_posture_ratio)
		pc.a = _hud._pulse_alpha(_hud.player_posture_ratio) * 0.92
		GensokyoInk.stroke(self, Rect2(Vector2(mid - half, py), Vector2(half * 2.0, ph)), pc, 21.0, 0.8 * k, 1.0, 0.4, 0.4)
	# 中線刻度（讓「往兩側長」讀得出來）
	draw_line(Vector2(mid, py - 2.5 * k), Vector2(mid, py + ph + 2.5 * k), Color(st.washi_ivory, 0.45), 1.0, true)
	# 「C 拾參ノ型」就緒提示移到快捷列的御札格（同一件事不講兩次）。
