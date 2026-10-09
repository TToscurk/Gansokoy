extends RefCounted
## P8 Farmland pilot（r4 refinement）：凍結階面 X 377–431、Z 4–62，7 塊長年人工耕作形成的水田。
## r6：全區 12 平台塊由 village_v2_farmland_zone.gd 自動生成，plan()／build() 各接一行（pilot 本身不重生）。
## 不是 2×3 網格：渠西 3 塊／渠東 4 塊、兩側內埂互不對齊（無十字路口）。r4 拆掉連續圓角外框：
## 外埂依田各自成段（T／L 接頭、錯位台階），沿凍結農路（FarmPath_1 x=372、FarmPath_4 z=0）的西／南緣
## 平直、內側（北／東）依開墾先後凸凹；內渠輕微偏折，土唇沿渠垂直平移。不改 P1 地形與 P2／P7 水系；
## 可見網格在 village_v2_farmland_visual.gd。
## 碰撞：每條田埂一個 StaticBody3D，沿中心線每 ≤1.2 m 一個 BoxShape3D——高度、橫向偏移、寬度都取
## bund_eval()（與可見網格同一函式），缺口／踩踏凹口也同步；底貼凍結階面。

const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const Visual := preload("res://tools/village_v2_farmland_visual.gd")
const WATER_LIFT := 0.045      # 田面水位基準（相對凍結階面）
const WATER_TOL := 0.002       # 水位誤差上限（沿用 r2 gate 門檻，不放寬）
const CH_WATER_S := 0.078      # 內渠水位（分水堰上游／下游）：高於所有田面水與水口缺口 → 自流入田
const CH_WATER_N := 0.070
const CH_WATER_HALF := 0.48    # 渠水網格半寬（邊緣藏進土唇坡；可見水面約 ±0.3）
const CHECK_WEIR_Z := 34.3
const LIP_OFF := 0.66          # 渠側土唇中心離渠中心（兩唇碰撞間淨開口 0.85 m，沿用 r2 gate）
const DRAIN_OFF := 0.83        # 北排水溝中心離北外埂中心
const DRAIN_HALF := 0.47       # 排水溝水面半寬（邊緣藏進兩側坡）
const DRAIN_LIP_OFF := 1.50    # 排水溝北唇中心
const DRAIN_WATER_LIFT := 0.03
const INLET_CREST := 0.060     # 水口缺口底（介於田水與渠水之間）
const OUTLET_CREST := 0.022    # 落水口缺口底（堰板頂決定上游水位）
const CORNER_R := 0.9          # 折角圓角半徑上限（渠唇、排水溝；田埂依類別 BUND_CLASS.r）
const COLL_STEP := 1.2         # 碰撞盒最大長度
# 田埂斷面：base_half＝腳寬一半、h＝高、stand_half＝碰撞頂寬一半
# r＝折角圓角半徑（外埂較尖：舊田角是踩出來的鈍角，不是整圈圓弧）
const BUND_CLASS := {
	"outer": {"base_half": 0.48, "h": 0.25, "stand_half": 0.28, "r": 0.4},
	"outer_grass": {"base_half": 0.62, "h": 0.19, "stand_half": 0.36, "r": 0.5},
	"lip": {"base_half": 0.36, "h": 0.26, "stand_half": 0.17, "r": 0.9},
	"inner": {"base_half": 0.38, "h": 0.20, "stand_half": 0.21, "r": 0.55},
	"ditch": {"base_half": 0.55, "h": 0.11, "stand_half": 0.22, "r": 0.9},
}
const N_JOIN := 59.9           # 北外埂接土唇的 z
# 內渠中心線（南端木樋取水口 → 北端止め堰落排水溝）：沿舊田界兩次輕微偏折（最大 15°），全程同一水位段，
# 灌排高差（CH_WATER_S／N、水口、落水口）不因平面偏折改變
const CH := [Vector2(404.6, 6.0), Vector2(404.3, 9.5), Vector2(403.2, 17.0), Vector2(402.6, 24.0), Vector2(403.3, 30.0),
	Vector2(404.9, 36.5), Vector2(405.5, 43.0), Vector2(404.7, 50.5), Vector2(404.9, 56.0), Vector2(405.4, 60.7)]
# 西緣（南→北）：各田西界錯位——W1 貼農路側平直、W2 內縮 1.7 m、W3 外凸；台階＝短斜段
const W_EDGE := [Vector2(378.4, 7.6), Vector2(378.0, 12.5), Vector2(378.3, 19.0), Vector2(378.9, 23.2),
	Vector2(380.6, 24.6), Vector2(380.9, 30.0), Vector2(380.3, 36.5), Vector2(380.0, 40.8),
	Vector2(378.6, 42.4), Vector2(377.9, 48.0), Vector2(378.4, 54.5), Vector2(379.6, 58.4)]
# 東緣（南→北）：E1 內、E2 外、E3 再外凸（後開墾的新田）、E4 收回＋東北斜切
const E_EDGE := [Vector2(426.2, 11.2), Vector2(426.6, 16.0), Vector2(426.9, 19.6),
	Vector2(428.6, 20.8), Vector2(428.9, 26.0), Vector2(428.2, 30.9),
	Vector2(430.2, 32.6), Vector2(430.8, 38.5), Vector2(430.3, 44.6),
	Vector2(428.0, 46.0), Vector2(427.1, 50.8)]
# r5 取水（2026-09-30 使用者裁示：高架只用於必要跨越段，其餘降為沿等高線的地面水路；跨路用暗渠／涵洞，水位高於路面時為伏越し）：
# R5b.1（2026-10-10 使用者 P10 FINAL CLOSEOUT「方案 B LIMITED APPROVAL」）：水車 2 は純動力（WaterLifeP10）。水車 2 から 3.30 m の受け樋へ揚げる
#   前提が無くなったので、高架落とし樋・接頭箱・受け樋枕木・支柱と其碰撞を撤去し、竜骨車 1 台（人力・踏み軸）で汲み上げる：
# 穿村水渠（P2 Canal，水位 −1.52）→ 竜骨車（取水口＝樋底下端 −1.80、水面下 0.28／吐き口＝樋底上端 0.66；傾斜 28°、樋長 5.2 m、
#   必要揚程＝水渠水面 −1.52 → 落とし桝水面 0.28 の 1.80 m、吐き口まで 2.18 m）→ 送り樋（0.53 → 0.50、桝の壁頂 0.44 の上へ張り出す）
# → 落とし桝 → 上段土渠：沿 0.20 階面等高線東流（全區擴充時兼作 S 區主渠幹線）→ 伏越し入口桝
# → 伏越し：FarmPath_1 路面 0.148 m 低於入口／出口桝水位 0.27／0.19 → 路下管段滿管、出口上湧＝封閉壓力段（非暗渠／涵洞；路面、地形不動，地上無構件）→ 出口桝
# → 下段木槽：出口桝旁起半埋於坡地、往東漸出地面架在枕木上（頂 ≤ 0.29 m，與田埂同級、可跨），沿 W1 南埂外側東流 → 樋口落進內渠南端。
# 水位：竜骨車吐き口 0.66 → 送り樋 0.53→0.50 → 落とし桝 0.28 → 上段 0.27 → 出口桝 0.19 → 木槽 0.17→0.15 → 內渠 0.078（竜骨車から先は自流）。
#   水車、水渠、P1 地形、P7 河岸は不動。
# CHUTE（r5 の高架落とし樋）は R5b.1 で撤去：生成には使わない（survey／probe の記録用に値だけ残す）。
const CHUTE := [Vector3(332.45, 3.30, 0.4), Vector3(336.3, 1.62, 2.75), Vector3(338.55, 0.47, 4.72)]   # 撤去済み（記録）   # (x, 樋底 y, z)
const CHUTE_W := 0.40            # 落とし樋外寬
const CHUTE_POST_T := [0.0, 0.55]  # 第 2 段上的支柱位置（段內比例）；第 1 段整段在岸坡上、不立柱
const BANK_X := 335.8            # 水渠岸坡（P7 河岸 kit 範圍）：不立柱、不給碰撞；受け樋頭架在水車東軸承柱上
const DROP_BOX := Vector2(338.75, 4.85)
## R5b.1 竜骨車（翻車）：位置は実測で選定（docs/art_review/village_v2_p10_rehab_impl/r5b1_irrigation/）。
##   水車 2 の回転円盤（AABB z ≤ 3.81）から 1 m 以上下流、取水口の渠底 −2.33（樋底下端の 0.53 m 下）、樋底は岸坡の地面より全長で ≥ 0.15 m 上。
const RYU_LOW := Vector3(331.00, -1.80, 4.85)    # 樋底下端（取水口、下車）
const RYU_HIGH := Vector3(335.55, 0.66, 4.85)    # 樋底上端（吐き口、上車）
const RYU_W := 0.34              # 樋外寬
const RYU_WALL := 0.22           # 側板高出底板頂
const RYU_DRUM_UP := 0.20        # 車（上下）の中心＝樋底から樋面直交方向へ 0.20
const RYU_FRAME_Z := [3.85, 5.85]  # 門形架（軸受柱＋手摺）の z
const RYU_RAIL_LIFT := 1.25      # 手摺＝踏み軸の上 1.25 m（踏み板に立って肘を掛ける高さ）
const FEED := [Vector3(335.40, 0.53, 4.85), Vector3(338.62, 0.50, 4.85)]   # 送り樋底：吐き口の下（樋の上端が 0.15 m 入り込む）→ 落とし桝の上へ張り出す
const FEED_W := 0.48
const FEED_WALL := 0.18
const FEED_LEG_X := [336.55, 337.75]
const UPPER := [Vector2(339.15, 4.95), Vector2(342.5, 5.55), Vector2(347.5, 6.2), Vector2(354.0, 6.4), Vector2(360.5, 6.3), Vector2(369.25, 6.25)]
const UPPER_LIFT := 0.07         # 上段土渠水位（相對 0.20 階面）
const UPPER_LIP := 0.62          # 上段土渠兩唇中心離渠中心
const UPPER_HALF := 0.40         # 上段土渠水面半寬
const SIPHON := [Vector2(369.7, 6.25), Vector2(374.05, 6.25)]   # 兩桝貼著路緣（淨距 0.67／0.42 m），讀成一對   # 伏越し入口桝／出口桝（FarmPath_1 x 370.8–373.2 不落任何構件）
const SIPHON_WATER := [0.27, 0.19]
const TROUGH := [Vector2(374.45, 6.25), Vector2(378.8, 6.25), Vector2(386.0, 6.3), Vector2(394.0, 6.18), Vector2(403.45, 6.22), Vector2(404.3, 6.22)]
const TROUGH_BOT := [0.11, 0.08]  # 木槽底板頂 y（起點→樋口）
const TROUGH_W := 0.42
const TROUGH_WALL := 0.14        # 側板高出底板頂
const TROUGH_DEPTH := 0.07       # 槽內水深
const CROSSINGS := [["trough", 385.3], ["trough", 397.8], ["upper", 354.0]]   # 跨渠板（x）
const LIP_W_START := 6.95        # 內渠西唇起點 z：南端 6.0–7.05 讓出木槽樋口
const SW_LIP_Z := 9.0
const SE_LIP_Z := 11.6
const SW := [Vector2(398.0, 8.4), Vector2(391.0, 7.8), Vector2(384.0, 7.9)]              # 東→西（沿 FarmPath_4 平直）
const NW := [Vector2(385.0, 59.6), Vector2(391.5, 60.4), Vector2(398.0, 60.0)]           # 西→東
const SE := [Vector2(411.0, 11.2), Vector2(418.5, 10.6), Vector2(423.8, 10.9)]            # E1 南界比 W1 北移 3 m（錯位）
const NE := [Vector2(424.0, 54.6), Vector2(418.5, 57.4), Vector2(412.0, 59.0)]           # 東→西
# 外埂分段點（接內埂處）
const W_SPLIT := [23.8, 41.6]
const E_SPLIT := [20.2, 31.7, 45.3]
# 田越し：每塊田的水源與落水去向；各田水位（上游高、下游低）
const FLOW := {"W1": ["lateral", "W2"], "W2": ["lateral", "W3"], "W3": ["lateral", "drain"],
	"E1": ["lateral", "E2"], "E2": ["lateral", "E3"], "E3": ["lateral", "E4"], "E4": ["lateral", "drain"]}
# 各田水位：凍結階面上一律 +0.045 m（各田由內渠獨立進水、獨立落水到排水溝，不做田越し高差；田間差異交給水色／混濁／藻）
const FIELD_LIFT := {"W1": 0.045, "W2": 0.045, "W3": 0.045, "E1": 0.045, "E2": 0.045, "E3": 0.045, "E4": 0.045}
# 水口（在渠側土唇上的 z）；落水口與踩踏凹口以近似世界座標指定，投影到所屬田埂
const INLET_Z := {"W1": 17.0, "W2": 32.2, "W3": 50.0, "E1": 13.5, "E2": 24.0, "E3": 39.0, "E4": 51.0}
const OUTLET := {"W1": ["InnerA", Vector2(388.5, 24.9)], "W2": ["InnerB", Vector2(392.5, 40.9)], "W3": ["OuterW3", Vector2(394.5, 60.2)],
	"E1": ["InnerC", Vector2(418.5, 18.3)], "E2": ["InnerD", Vector2(413.5, 31.9)], "E3": ["InnerE", Vector2(420.0, 45.7)], "E4": ["OuterE4", Vector2(419.0, 57.2)]}
const TREAD := [["OuterW1", Vector2(378.1, 16.0)], ["OuterW3", Vector2(378.0, 48.5)], ["OuterW1", Vector2(390.0, 7.8)],
	["OuterE1", Vector2(417.0, 10.7)], ["OuterE3", Vector2(430.7, 38.5)], ["InnerB", Vector2(385.5, 41.2)], ["InnerD", Vector2(419.0, 31.2)]]
# 常走的埂（頂面踏み固め土、少草）；其餘長草
const WALKED := ["OuterW1", "OuterW3", "OuterE1", "LipW", "LipE", "InnerB", "InnerD"]
# 畦塗り（面向田的側坡抹泥）新舊：1＝今年剛塗（平滑濕泥）、0＝多年未塗（長草）
const PLASTER := {"OuterW1": 0.85, "OuterW2": 0.3, "OuterW3": 0.7, "OuterE1": 0.9, "OuterE2": 0.25, "OuterE3": 0.15, "OuterE4": 0.6,
	"LipW": 0.5, "LipE": 0.65, "InnerA": 0.9, "InnerB": 0.45, "InnerC": 0.8, "InnerD": 0.35, "InnerE": 0.75, "DrainN": 0.0}

## 全區擴張（r6）生成器：plan() 併入全區田／田埂，build() 加全區水利碰撞，Visual.apply() 加全區可見構件
const ZONE_SCRIPT := "res://tools/village_v2_farmland_zone.gd"

static func plan() -> Dictionary:
	var lw := _lip(-1)
	var le := _lip(1)
	# 原始折線（田格回圈用）
	var raw := {}
	raw["SW"] = PackedVector2Array([_lp(-1, SW_LIP_Z)] + SW + [W_EDGE[0]])
	raw["W"] = _pa(W_EDGE)
	raw["NW"] = PackedVector2Array([W_EDGE[-1]] + NW + [_lp(-1, N_JOIN)])
	raw["SE"] = PackedVector2Array([_lp(1, SE_LIP_Z)] + SE + [E_EDGE[0]])
	raw["E"] = _pa(E_EDGE)
	raw["NE"] = PackedVector2Array([E_EDGE[-1]] + NE + [_lp(1, N_JOIN)])
	raw["InnerA"] = PackedVector2Array([_ep(W_EDGE, W_SPLIT[0]), Vector2(386.0, 24.7), Vector2(392.4, 25.2), Vector2(398.5, 25.6), _lp(-1, 26.2)])
	raw["InnerB"] = PackedVector2Array([_ep(W_EDGE, W_SPLIT[1]), Vector2(386.5, 41.2), Vector2(395.5, 40.6), _lp(-1, 39.8)])
	raw["InnerC"] = PackedVector2Array([_lp(1, 19.0), Vector2(410.0, 18.8), Vector2(416.2, 18.1), Vector2(422.0, 18.9), _ep(E_EDGE, E_SPLIT[0])])
	raw["InnerD"] = PackedVector2Array([_lp(1, 33.2), Vector2(410.5, 32.4), Vector2(416.0, 31.4), Vector2(422.0, 31.0), _ep(E_EDGE, E_SPLIT[1])])
	raw["InnerE"] = PackedVector2Array([_lp(1, 45.8), Vector2(411.0, 46.4), Vector2(417.0, 46.0), Vector2(422.5, 45.4), _ep(E_EDGE, E_SPLIT[2])])
	# 田埂（可見＋碰撞）：外埂依田各自成段，在接內埂處 T／L 相接（端點全高、互相壓疊成接頭土堆），不再是一整圈圓角框
	var b := {}
	var we := _pa(W_EDGE)
	var ee := _pa(E_EDGE)
	b["OuterW1"] = _bd(_join([raw["SW"], _slice(we, W_EDGE[0].y, W_SPLIT[0])]), "outer", ["t", "t"], 11)
	b["OuterW2"] = _bd(_slice(we, W_SPLIT[0], W_SPLIT[1]), "outer_grass", ["t", "t"], 13)
	b["OuterW3"] = _bd(_join([_slice(we, W_SPLIT[1], W_EDGE[-1].y), raw["NW"]]), "outer", ["t", "t"], 17)
	b["OuterE1"] = _bd(_join([raw["SE"], _slice(ee, E_EDGE[0].y, E_SPLIT[0])]), "outer", ["t", "t"], 23)
	b["OuterE2"] = _bd(_slice(ee, E_SPLIT[0], E_SPLIT[1]), "outer_grass", ["t", "t"], 29)
	b["OuterE3"] = _bd(_slice(ee, E_SPLIT[1], E_SPLIT[2]), "outer_grass", ["t", "t"], 31)
	b["OuterE4"] = _bd(_join([_slice(ee, E_SPLIT[2], E_EDGE[-1].y), raw["NE"]]), "outer", ["t", "t"], 19)
	b["LipW"] = _bd(_slice(lw, LIP_W_START, N_JOIN + 0.35), "lip", ["cap", "cap"], 37)
	b["LipE"] = _bd(_slice(le, CH[0].y, N_JOIN + 0.35), "lip", ["cap", "cap"], 41)
	b["InnerA"] = _bd(raw["InnerA"], "inner", ["t", "t"], 53)
	b["InnerB"] = _bd(raw["InnerB"], "inner", ["t", "t"], 59)
	b["InnerC"] = _bd(raw["InnerC"], "inner", ["t", "t"], 67)
	b["InnerD"] = _bd(raw["InnerD"], "inner", ["t", "t"], 71)
	b["InnerE"] = _bd(raw["InnerE"], "inner", ["t", "t"], 79)
	# 上段土渠兩唇（可見土埂＋碰撞走田埂管線）
	var up := _pa(UPPER)
	b["LipSupA"] = _bd(_offset_line(up, UPPER_LIP), "lip", ["cap", "cap"], 89)
	b["LipSupB"] = _bd(_offset_line(up, -UPPER_LIP), "lip", ["cap", "cap"], 97)
	# 排水溝：沿北外埂外側（W3／E4 落水 → 東端暗渠桝）；北唇也是可走的低埂
	# r4：排水溝從 W3 落水口西側才開始（不再沿整條北緣，免得與外埂形成雙層外框）
	var nw_tail: PackedVector2Array = (raw["NW"] as PackedVector2Array).slice(2)
	var ne_head: PackedVector2Array = _rev(raw["NE"]).slice(0, (raw["NE"] as PackedVector2Array).size() - 1)
	var dline := _offset_line(nw_tail, DRAIN_OFF)
	dline.append_array(_offset_line(ne_head, DRAIN_OFF))
	var dlip := _offset_line(nw_tail, DRAIN_LIP_OFF)
	dlip.append_array(_offset_line(ne_head, DRAIN_LIP_OFF))
	var dd := (ne_head[ne_head.size() - 1] - ne_head[ne_head.size() - 2]).normalized()
	dline.append(dline[dline.size() - 1] + dd * 2.4)
	dlip.append(dlip[dlip.size() - 1] + dd * 3.2)
	dline = _round(_dedupe(dline, 0.8), CORNER_R)
	b["DrainN"] = _bd(_dedupe(dlip, 0.8), "ditch", ["cap", "cap"], 83)
	# 田格回圈（原始折線）
	var f: Array = []
	f.append(_field("W1", _rev(raw["SW"]), _slice(lw, SW_LIP_Z, 26.2), raw["InnerA"], _slice(we, W_EDGE[0].y, W_SPLIT[0])))
	f.append(_field("W2", raw["InnerA"], _slice(lw, 26.2, 39.8), raw["InnerB"], _slice(we, W_SPLIT[0], W_SPLIT[1])))
	f.append(_field("W3", raw["InnerB"], _slice(lw, 39.8, N_JOIN), raw["NW"], _slice(we, W_SPLIT[1], W_EDGE[-1].y)))
	f.append(_field("E1", raw["SE"], _slice(ee, E_EDGE[0].y, E_SPLIT[0]), raw["InnerC"], _slice(le, SE_LIP_Z, 19.0)))
	f.append(_field("E2", raw["InnerC"], _slice(ee, E_SPLIT[0], E_SPLIT[1]), raw["InnerD"], _slice(le, 19.0, 33.2)))
	f.append(_field("E3", raw["InnerD"], _slice(ee, E_SPLIT[1], E_SPLIT[2]), raw["InnerE"], _slice(le, 33.2, 45.8)))
	f.append(_field("E4", raw["InnerE"], _slice(ee, E_SPLIT[2], E_EDGE[-1].y), _rev(raw["NE"]), _slice(le, 45.8, N_JOIN)))
	# 缺口：水口（渠側土唇）／落水口（下游田埂）／踩踏凹口；s＝沿圓角後中心線的弧長
	for fd: Dictionary in f:
		var n: String = fd["name"]
		var lip: String = "LipW" if n.begins_with("W") else "LipE"
		var lp := _lp(-1 if lip == "LipW" else 1, INLET_Z[n])
		b[lip]["notches"].append({"s": project_s(b[lip]["pts"], lp), "w": 0.55, "crest": INLET_CREST, "kind": "inlet", "field": n})
		var o: Array = OUTLET[n]
		b[o[0]]["notches"].append({"s": project_s(b[o[0]]["pts"], o[1]), "w": 0.45, "crest": OUTLET_CREST, "kind": "outlet", "field": n})
		fd["lift"] = FIELD_LIFT[n]
		fd["flow"] = FLOW[n]
	for t: Array in TREAD:
		b[t[0]]["notches"].append({"s": project_s(b[t[0]]["pts"], t[1]), "w": 0.8, "crest": 0.0, "kind": "tread", "field": ""})
	for bn: String in b:
		b[bn]["walked"] = bn in WALKED
		b[bn]["plaster"] = PLASTER.get(bn, 0.5)
		b[bn]["length"] = _length(b[bn]["pts"])
	# 田面：水面內緣＝回圈扣掉田埂腳（邊藏進埂坡）；插秧區再內縮
	for fd: Dictionary in f:
		fd["water"] = _minus_bunds(fd["loop"], b, 0.55)
		fd["plant"] = _minus_bunds(fd["loop"], b, 1.35)
	var P := {"bunds": b, "fields": f, "channel": _pa(CH), "drain": dline, "upper": up, "supply_posts": supply_posts()}
	load(ZONE_SCRIPT).extend(P)
	return P

static func build(layout: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "FarmlandP8"
	var plots := _group(root, "Plots")
	var bunds := _group(root, "Bunds")
	var irrigation := _group(root, "Irrigation")
	var farm := TLib.pts(layout["districts"]["Farmland"]["poly"])
	var P := plan()
	for fd: Dictionary in P["fields"]:
		var poly: PackedVector2Array = fd["water"]
		var c := _centroid(poly)
		assert(Geometry2D.is_point_in_polygon(c, farm))
		var y := TLib.farm_level(layout, c)
		var plot := _group(plots, "Plot_%s" % fd["name"])
		plot.set_meta("field_center", c)
		plot.set_meta("terrace_y", y)
		plot.set_meta("water_lift", fd["lift"])
		plot.set_meta("field_loop", fd["loop"])
		plot.set_meta("water_poly", poly)
		plot.set_meta("area_m2", absf(_area(poly)))
		plot.set_meta("flow", fd["flow"])
		if fd.get("zone", false):
			plot.set_meta("zone_block", fd["block"])
			plot.set_meta("channel_water", fd["ch_water"])
		# 量測 proxy（不可見）：放置稽核取樣用，高度＝本田實際水位
		var bb := _bbox(poly)
		var proxy := MeshInstance3D.new()
		proxy.name = "PaddyWater"
		var box := BoxMesh.new()
		box.size = Vector3(bb.size.x * 0.55, 0.004, bb.size.y * 0.55)
		proxy.mesh = box
		proxy.position = Vector3(c.x, y + float(fd["lift"]), c.y)
		proxy.visible = false
		plot.add_child(proxy)
	for name: String in P["bunds"]:
		_bund_body(bunds, name, P["bunds"][name], layout)
	_supply_body(irrigation, P["supply_posts"], layout)
	load(ZONE_SCRIPT).collision(irrigation, P)
	root.set_meta("phase", "P8 Farmland pilot")
	root.set_meta("status", "LOCAL_REVIEW")
	root.set_meta("pilot_rev", "r4 refinement: segmented outer bunds, bent lateral, MultiMesh rice")
	root.set_meta("channel_water", Vector2(CH_WATER_S, CH_WATER_N))
	root.set_meta("drain_water_lift", DRAIN_WATER_LIFT)
	Visual.apply(root, layout, P)
	return root

## 竜骨車の基準フレーム：樋底中心線 low→high の basis（+z＝上り方向、+y＝樋面直交の上）
static func ryu_basis() -> Basis:
	var a: Vector3 = RYU_LOW
	var b: Vector3 = RYU_HIGH
	var d := Vector2(b.x - a.x, b.z - a.z)
	return Basis(Vector3.UP, atan2(d.x, d.y)) * Basis(Vector3.RIGHT, atan2(a.y - b.y, d.length()))

## 上車（踏み軸）中心
static func ryu_axle() -> Vector3:
	return RYU_HIGH + ryu_basis() * Vector3(0, RYU_DRUM_UP, 0)

## 竜骨車の柱（可見網格と碰撞の共用）：[{"name", "p": Vector2, "y_bot", "y_top", "s": 断面, "tall": bool}]
static func supply_posts() -> Array:
	var out: Array = []
	var ax := ryu_axle()
	for i in 2:
		out.append({"name": "Frame_%d" % i, "p": Vector2(ax.x, float(RYU_FRAME_Z[i])), "y_bot": -0.30, "y_top": ax.y + RYU_RAIL_LIFT + 0.06, "s": 0.12, "tall": true})
	for sd in [-1, 1]:
		out.append({"name": "Stake_%d" % ((sd + 1) / 2), "p": Vector2(RYU_LOW.x - 0.10, RYU_LOW.z + sd * 0.24), "y_bot": -2.60, "y_top": -1.18, "s": 0.10, "tall": false})
	for i in FEED_LEG_X.size():
		var x: float = FEED_LEG_X[i]
		var y := lerpf(FEED[0].y, FEED[1].y, (x - FEED[0].x) / (FEED[1].x - FEED[0].x))
		for sd in [-1, 1]:
			out.append({"name": "FeedLeg_%d_%d" % [i, (sd + 1) / 2], "p": Vector2(x, FEED[0].z + sd * 0.20), "y_bot": 0.0, "y_top": y - 0.06, "s": 0.08, "tall": false})
	return out

## 木槽底板頂 y（沿木槽弧長線性下降）
static func trough_bottom(s: float, L: float) -> float:
	return lerpf(TROUGH_BOT[0], TROUGH_BOT[1], clampf(s / maxf(L, 1e-3), 0.0, 1.0))

## 取水碰撞（Irrigation/WaterSupply）：竜骨車（R5b.1）、各桝、地面木槽、跨渠板。
## 樋段兩側／上方外擴 CHUTE_CAM_PAD（TPS SpringArm 以碰撞面擋相機，外擴量＝相機與可見樋體淨距）；
## 下方不外擴（不做看不見的天花板）。木槽、桝、跨渠板頂 ≤ 0.4 m（與田埂同級、step_height 0.6 可跨），
## 四周與頂面外擴 LOW_CAM_PAD：低角度相機貼地時 SpringArm 才會在近裁面碰到可見石／板之前停下（walk --feeder 實測）。
const CHUTE_CAM_PAD := 0.3
const LOW_CAM_PAD := 0.12
static func _supply_body(parent: Node, posts: Array, layout: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "WaterSupply"
	parent.add_child(body)
	# R5b.1 竜骨車：柱（門形架は相機外擴 CHUTE_CAM_PAD、低い柱は LOW_CAM_PAD）、頭部（踏み軸＋拐木の回転域）、手摺、傾斜樋、送り樋
	var k := 0
	for po: Dictionary in posts:
		var h: float = float(po["y_top"]) - float(po["y_bot"])
		var p: Vector2 = po["p"]
		var pad := CHUTE_CAM_PAD if po["tall"] else LOW_CAM_PAD
		_coll_box(body, "Post_%02d" % k, Vector3(p.x, float(po["y_bot"]) + h * 0.5, p.y), Vector3(float(po["s"]) + 2.0 * pad, h, float(po["s"]) + 2.0 * pad), 0.0, 0.0)
		k += 1
	var ax := ryu_axle()
	var z0: float = RYU_FRAME_Z[0]
	var z1: float = RYU_FRAME_Z[1]
	var hp := 0.2      # 拐木の回転域（半径 0.38）＋相機近裁面
	_coll_box(body, "RyuHead", Vector3(ax.x, (ax.y + 0.40 + hp + 0.05) * 0.5, (z0 + z1) * 0.5), Vector3(0.80 + 2.0 * hp, ax.y + 0.40 + hp - 0.05, z1 - z0), 0.0, 0.0)
	_coll_box(body, "RyuRail", Vector3(ax.x, ax.y + RYU_RAIL_LIFT, (z0 + z1) * 0.5), Vector3(0.08 + 2.0 * CHUTE_CAM_PAD, 0.08 + 2.0 * CHUTE_CAM_PAD, z1 - z0 + 0.12), 0.0, 0.0)
	var bs := ryu_basis()
	var rl := (RYU_HIGH - RYU_LOW).length()
	var th := RYU_WALL + 0.25 + CHUTE_CAM_PAD     # 側板＋戻り側の羽根板
	var sh := CollisionShape3D.new()
	sh.name = "RyuTrough"
	var bx := BoxShape3D.new()
	bx.size = Vector3(RYU_W + 2.0 * CHUTE_CAM_PAD, th + 0.04, rl)
	sh.shape = bx
	sh.transform = Transform3D(bs, (RYU_LOW + RYU_HIGH) * 0.5 + bs * Vector3(0, th * 0.5 - 0.04, 0))
	body.add_child(sh)
	var fa: Vector3 = FEED[0]
	var fb: Vector3 = FEED[1]
	var ftop := maxf(fa.y, fb.y) + FEED_WALL - 0.02
	_coll_box(body, "Feed", Vector3((fa.x + fb.x) * 0.5, (ftop + LOW_CAM_PAD + 0.0) * 0.5, fa.z), Vector3(fb.x - fa.x + 2.0 * LOW_CAM_PAD, ftop + LOW_CAM_PAD, FEED_W + 2.0 * LOW_CAM_PAD), 0.0, 0.0)
	# 桝：落とし桝／伏越し入口桝／出口桝
	var y0 := TLib.farm_level(layout, DROP_BOX)
	_coll_box(body, "DropBox", Vector3(DROP_BOX.x, y0 + 0.08 + LOW_CAM_PAD * 0.5, DROP_BOX.y), Vector3(0.86 + 2.0 * LOW_CAM_PAD, 0.36 + LOW_CAM_PAD, 0.86 + 2.0 * LOW_CAM_PAD), 0.0, 0.0)
	for i in 2:
		var q: Vector2 = SIPHON[i]
		var top: float = float(SIPHON_WATER[i]) + 0.07 + LOW_CAM_PAD + (0.06 if i == 0 else 0.0)   # 入口桝有蓋石
		_coll_box(body, "SiphonBox_%d" % i, Vector3(q.x, (top - 0.1) * 0.5, q.y), Vector3(0.86 + 2.0 * LOW_CAM_PAD, top + 0.1, 0.86 + 2.0 * LOW_CAM_PAD), 0.0, 0.0)
	# 地面木槽
	var tl := _pa(TROUGH)
	var L := _length(tl)
	var acc := 0.0
	for i in tl.size() - 1:
		var p0 := tl[i]
		var p1 := tl[i + 1]
		var seg := p0.distance_to(p1)
		var top := trough_bottom(acc + seg * 0.5, L) + TROUGH_WALL + LOW_CAM_PAD
		var g := TLib.farm_level(layout, (p0 + p1) * 0.5)
		var dd := p1 - p0
		_coll_box(body, "Trough_%d" % i, Vector3((p0.x + p1.x) * 0.5, (g + top) * 0.5, (p0.y + p1.y) * 0.5), Vector3(TROUGH_W + 0.05 + 2.0 * LOW_CAM_PAD, top - g, seg + 0.02), atan2(dd.x, dd.y), 0.0)
		acc += seg
	# 跨渠板
	for c: Array in CROSSINGS:
		var cr := crossing(c, layout)
		_coll_box(body, "Crossing_%s_%d" % [c[0], int(c[1])], Vector3(cr["at"].x, (cr["ground"] + cr["top"] + LOW_CAM_PAD) * 0.5, cr["at"].y), Vector3(0.78 + 2.0 * LOW_CAM_PAD, cr["top"] - cr["ground"] + LOW_CAM_PAD, cr["span"] + 2.0 * LOW_CAM_PAD), 0.0, 0.0)

## 跨渠板幾何：{"at": 中心 xz, "top": 板頂 y, "span": 沿 z 長度, "ground": 地面 y}
static func crossing(c: Array, layout: Dictionary) -> Dictionary:
	var x: float = c[1]
	if c[0] == "trough":
		var tl := _pa(TROUGH)
		var z := x_to_z(tl, x)
		var s := project_s(tl, Vector2(x, z))
		var top := trough_bottom(s, _length(tl)) + TROUGH_WALL + 0.04
		return {"at": Vector2(x, z), "top": top, "span": TROUGH_W + 0.5, "ground": TLib.farm_level(layout, Vector2(x, z))}
	var up := _pa(UPPER)
	var zu := x_to_z(up, x)
	var g := TLib.farm_level(layout, Vector2(x, zu))
	return {"at": Vector2(x, zu), "top": g + float(BUND_CLASS["lip"]["h"]) + 0.03, "span": 2.0 * UPPER_LIP + 0.5, "ground": g}

## 沿 x 單調的折線：給 x 取 z
static func x_to_z(poly: PackedVector2Array, x: float) -> float:
	for i in poly.size() - 1:
		if (poly[i].x - x) * (poly[i + 1].x - x) <= 0.0:
			return lerpf(poly[i].y, poly[i + 1].y, (x - poly[i].x) / (poly[i + 1].x - poly[i].x))
	return poly[0].y if x < poly[0].x else poly[poly.size() - 1].y

static func _coll_box(body: Node, name: String, at: Vector3, size: Vector3, yaw: float, pitch: float) -> void:
	var sh := CollisionShape3D.new()
	sh.name = name
	var bx := BoxShape3D.new()
	bx.size = size
	sh.shape = bx
	sh.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), at)
	body.add_child(sh)

## 田埂參數（可見網格與碰撞共用）：沿弧長 s 的高度、寬度倍率、橫向偏移、左右不對稱、缺口／踩踏權重。
static func bund_eval(d: Dictionary, s: float) -> Dictionary:
	var salt := float(d["salt"])
	var cls: Dictionary = BUND_CLASS[d["cls"]]
	var L: float = d["length"]
	var hs := 1.0 + 0.09 * sin(s * 0.41 + salt) + 0.045 * sin(s * 1.9 + salt * 2.3) + 0.02 * sin(s * 4.7 + salt)
	var ws := 1.0 + 0.09 * sin(s * 0.53 + salt * 1.7) + 0.045 * sin(s * 1.37 + salt * 0.4)
	var off := 0.03 * sin(s * 0.87 + salt * 0.9) + 0.018 * sin(s * 2.6 + salt * 1.3)
	var asym := 0.10 * sin(s * 0.31 + salt * 2.9)
	var h := float(cls["h"]) * hs
	var tread := 0.0
	var notch := 0.0
	var notch_kind := ""
	for n: Dictionary in d["notches"]:
		var half := float(n["w"]) * 0.5
		var g := 1.0 - smoothstep(half, half + 0.22, absf(s - float(n["s"])))
		if g <= 0.0:
			continue
		if n["kind"] == "tread":
			h -= 0.055 * g
			tread = maxf(tread, g)
		else:
			h = lerpf(h, float(n["crest"]), g)
			if g > notch:
				notch = g
				notch_kind = n["kind"]
	var e := 1.0
	if d["ends"][0] == "cap":
		e = minf(e, clampf(s / 0.9, 0.0, 1.0))
	if d["ends"][1] == "cap":
		e = minf(e, clampf((L - s) / 0.9, 0.0, 1.0))
	h *= pow(sin(e * PI * 0.5), 0.6)
	ws *= lerpf(0.55, 1.0, sqrt(e))
	return {"h": h, "ws": ws, "off": off, "asym": asym, "tread": tread, "notch": notch, "notch_kind": notch_kind}

## 斷面輪廓 0..1（u＝相對腳寬；|u|>1 為埋入泥中的延伸段，回傳負值＝埋深 m）
static func profile(u: float, walked: bool) -> float:
	var a := absf(u)
	if a > 1.0:
		return -0.03 * (a - 1.0) / 0.25
	# 圓鈍埂：頂部 ±0.3 為微拱的冠，肩部 smoothstep 緩降到腳（腳部切線水平、沒有垂直壁；最大坡約 45°）
	var p := 1.0 - smoothstep(0.3, 1.0, a)
	p *= 1.0 - 0.06 * a * a
	if walked:
		p = minf(p, 0.97) / 0.97
	return p

## 折線上弧長 s 的位置與切線
static func at_s(pts: PackedVector2Array, s: float) -> Array:
	var acc := 0.0
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if s <= acc + seg or i == pts.size() - 2:
			var t := clampf((s - acc) / maxf(seg, 1e-4), 0.0, 1.0)
			return [pts[i].lerp(pts[i + 1], t), (pts[i + 1] - pts[i]).normalized()]
		acc += seg
	return [pts[pts.size() - 1], (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()]

## 點投影到折線 → 弧長
static func project_s(pts: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var best_s := 0.0
	var acc := 0.0
	for i in pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
		var dist := q.distance_to(p)
		if dist < best:
			best = dist
			best_s = acc + pts[i].distance_to(q)
		acc += pts[i].distance_to(pts[i + 1])
	return best_s

## 田埂碰撞：每 ≤COLL_STEP 一盒，缺口邊界處斷開；盒頂＝該段中點 bund_eval 高度，中心隨橫向偏移。
static func _bund_body(parent: Node, name: String, d: Dictionary, layout: Dictionary) -> void:
	var cls: Dictionary = BUND_CLASS[d["cls"]]
	var body := StaticBody3D.new()
	body.name = "Bund_%s" % name
	body.set_meta("bund_class", d["cls"])
	body.set_meta("polyline", d["pts"])
	body.set_meta("notches", d["notches"])
	body.set_meta("walked", d["walked"])
	parent.add_child(body)
	var L: float = d["length"]
	var cuts: Array = [0.0, L]
	for n: Dictionary in d["notches"]:
		if n["kind"] != "tread":
			cuts.append(float(n["s"]) - float(n["w"]) * 0.5)
			cuts.append(float(n["s"]) + float(n["w"]) * 0.5)
	cuts.sort()
	var k := 0
	for ci in cuts.size() - 1:
		var a: float = maxf(cuts[ci], 0.0)
		var z: float = minf(cuts[ci + 1], L)
		if z - a < 0.05:
			continue
		var pieces := maxi(1, ceili((z - a) / COLL_STEP))
		for pi in pieces:
			var s0 := lerpf(a, z, float(pi) / pieces)
			var s1 := lerpf(a, z, float(pi + 1) / pieces)
			var sm := (s0 + s1) * 0.5
			var ev := bund_eval(d, sm)
			var h: float = ev["h"]
			if h < 0.05:
				continue
			var p0: Vector2 = at_s(d["pts"], s0)[0]
			var p1: Vector2 = at_s(d["pts"], s1)[0]
			var am: Array = at_s(d["pts"], sm)
			var tan: Vector2 = am[1]
			var nrm := Vector2(-tan.y, tan.x)
			var mid: Vector2 = (p0 + p1) * 0.5 + nrm * float(ev["off"])
			var y := TLib.farm_level(layout, mid)
			var shape := CollisionShape3D.new()
			shape.name = "Seg_%03d" % k
			k += 1
			var box := BoxShape3D.new()
			box.size = Vector3(float(cls["stand_half"]) * 2.0 * float(ev["ws"]), h, p0.distance_to(p1) + 0.04)
			shape.shape = box
			var dir := (p1 - p0).normalized()
			shape.transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)), Vector3(mid.x, y + h * 0.5, mid.y))
			body.add_child(shape)

static func _bd(pts: PackedVector2Array, cls: String, ends: Array, salt: int) -> Dictionary:
	return {"pts": _round(pts, float(BUND_CLASS[cls]["r"])), "raw": pts, "cls": cls, "ends": ends, "notches": [], "walked": false, "salt": salt, "length": 0.0}

static func _minus_bunds(loop: PackedVector2Array, b: Dictionary, k: float) -> PackedVector2Array:
	var poly := loop
	for name: String in b:
		var cls: Dictionary = BUND_CLASS[b[name]["cls"]]
		for bp: PackedVector2Array in Geometry2D.offset_polyline(b[name]["pts"], float(cls["base_half"]) * k, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
			poly = _largest(Geometry2D.clip_polygons(poly, bp), poly)
	return poly

static func _field(name: String, bottom: PackedVector2Array, side_a: PackedVector2Array, top: PackedVector2Array, side_b: PackedVector2Array) -> Dictionary:
	# bottom／top 西→東；兩側南→北。回圈：bottom → 東側 ↑ → top 反向 → 西側 ↓
	var west := side_b
	var east := side_a
	if side_a[0].x < side_b[0].x:
		west = side_a
		east = side_b
	var loop := PackedVector2Array()
	for p in bottom:
		_push(loop, p)
	for p in east:
		_push(loop, p)
	for i in range(top.size() - 1, -1, -1):
		_push(loop, top[i])
	for i in range(west.size() - 1, -1, -1):
		_push(loop, west[i])
	if loop[0].distance_to(loop[loop.size() - 1]) < 0.05:
		loop.remove_at(loop.size() - 1)
	return {"name": name, "loop": loop}

## 折角圓角：每個內部頂點以二次 Bezier 取代（半徑 ≤ r、≤ 相鄰段 1/3）
static func _round(pts: PackedVector2Array, r: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var a := pts[i - 1]
		var b := pts[i]
		var c := pts[i + 1]
		var ri := minf(r, minf(a.distance_to(b), b.distance_to(c)) / 3.0)
		var p0 := b + (a - b).normalized() * ri
		var p2 := b + (c - b).normalized() * ri
		for k in 5:
			var t := k / 4.0
			out.append(p0.lerp(b, t).lerp(b.lerp(p2, t), t))
	out.append(pts[pts.size() - 1])
	return _dedupe(out, 0.02)

static func _join(parts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for part: PackedVector2Array in parts:
		for p in part:
			_push(out, p)
	return out

static func _rev(a: PackedVector2Array) -> PackedVector2Array:
	var out := a.duplicate()
	out.reverse()
	return out

static func _push(a: PackedVector2Array, p: Vector2) -> void:
	if a.is_empty() or a[a.size() - 1].distance_to(p) > 0.05:
		a.append(p)

static func _dedupe(a: PackedVector2Array, min_d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in a.size():
		if out.is_empty() or out[out.size() - 1].distance_to(a[i]) > min_d or i == a.size() - 1:
			out.append(a[i])
	return out

## 渠唇中心線：渠中心線（圓角後）沿法向平移 LIP_OFF（side −1＝西、+1＝東）；偏折處兩唇仍與渠等距
static func _lip(side: int) -> PackedVector2Array:
	return _offset_line(_round(_pa(CH), CORNER_R), -side * LIP_OFF)

static func _lp(side: int, z: float) -> Vector2:
	var l := _lip(side)
	return Vector2(x_at(l, z), z)

static func _ep(edge: Array, z: float) -> Vector2:
	return Vector2(x_at(_pa(edge), z), z)

## z 單調折線上某 z 的 x（兩端外夾）
static func x_at(poly: PackedVector2Array, z: float) -> float:
	if z <= poly[0].y:
		return poly[0].x
	for i in poly.size() - 1:
		if z <= poly[i + 1].y:
			return lerpf(poly[i].x, poly[i + 1].x, (z - poly[i].y) / (poly[i + 1].y - poly[i].y))
	return poly[poly.size() - 1].x

static func _slice(poly: PackedVector2Array, z0: float, z1: float) -> PackedVector2Array:
	var out := PackedVector2Array([Vector2(x_at(poly, z0), z0)])
	for p in poly:
		if p.y > z0 + 0.05 and p.y < z1 - 0.05:
			out.append(p)
	out.append(Vector2(x_at(poly, z1), z1))
	return out

static func _length(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size() - 1:
		s += poly[i].distance_to(poly[i + 1])
	return s

## 往折線左側平移 d（西→東走時左側＝+z，即北）
static func _offset_line(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size():
		var t := Vector2.ZERO
		if i > 0:
			t += (pts[i] - pts[i - 1]).normalized()
		if i < pts.size() - 1:
			t += (pts[i + 1] - pts[i]).normalized()
		t = t.normalized()
		out.append(pts[i] + Vector2(-t.y, t.x) * d)
	return out

static func _pa(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in a:
		out.append(p)
	return out

static func _largest(polys: Array, fallback: PackedVector2Array) -> PackedVector2Array:
	var best := fallback
	var best_a := -1.0
	for p: PackedVector2Array in polys:
		var a := absf(_area(p))
		if a > best_a:
			best_a = a
			best = p
	return best

static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5

static func _centroid(p: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for q in p:
		c += q
	return c / p.size()

static func _bbox(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r

static func _group(parent: Node, name: String) -> Node3D:
	var node := Node3D.new()
	node.name = name
	parent.add_child(node)
	return node
