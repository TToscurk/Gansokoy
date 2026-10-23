extends "res://characters/yoriichi/yoriichi_character_r62.gd"
## R7 候選控制器（只給 player_yoriichi_r7.tscn 用；正式與 R4–R6.2 控制器一行不改）。
## 第一階段重製的攻擊：輕攻擊三段（各自獨立 clip）、重斬（八相→踏込袈裟）、蓄力架勢（脇構え）與蓄力釋放（切り上げ）、快速拔刀斬。
## 骨架、模型、握刀 IK（R6.2）、移動、拔納刀、防禦沿用 R6.2。
## 日之呼吸：R7 P2 新製八型（另含 REF02 碧羅之天＝2、REF04 幻日虹＝11）。以下為原六型說明：
## 日之呼吸：R7 P2 新製六型（REF01 圓舞＝1、REF07 陽華突＝8、REF12 炎舞＝12、REF03 烈日虹鏡＝3、REF08 飛輪陽炎＝6、
## REF11 日暈之龍・頭舞＝9；數字為 legacy ID）可發動；
## P3 空中四型也走 R7_FORMS；未安裝的資源與十三型仍拒絕，不回退舊動畫。
## 所有 R7 動畫 metadata r7_art_status = ART_REVIEW。
@export var r7_light_01_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_light_01.res")
@export var r7_light_02_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_light_02.res")
@export var r7_light_03_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_light_03.res")
## 輕攻擊播放倍率（clip 以 30 fps 製作、實際 0.50／0.55／0.65 s）
@export var r7_light_speed := 2.0
## 快速拔刀斬播放倍率（116 格 ÷ 30 ÷ 2.0 ≈ 1.93 s）
@export var r7_quickdraw_speed := 2.0
## 日之呼吸型（舊動作）在 R7 候選中停用（R7_FORMS 列出的新製型不受此開關影響）
@export var r7_forms_enabled := false
## R7 P2 日之呼吸（新製、ART_REVIEW）。clip 30 fps 製作，×2.0 播放：0.72／0.78／1.10 s
@export var r7_sun_01_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_sun_enbu.res")
## R7 P5 REF01 圓舞 右鍵分支（Mixamo Sword And Shield High Attack 改造的地面旋身橫斬，ART_REVIEW）。null → 不登錄、REF01 右鍵回父類行為。
@export var r7_sun01_rmb_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_sun01_rmb_spincut.res")
@export var r7_sun_07_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_sun_youkatotsu.res")
@export var r7_sun_12_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_sun_enbu_double.res")
## 陽華突的疾跑起手版（最後一步左腳煞車落地、右腳直接跨入弓步；上半身與站立版相同）
@export var r7_sun_07_run_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_sun_youkatotsu_run.res")
## R7 P2 第二批：REF03 烈日虹鏡（legacy 3）、REF08 飛輪陽炎（legacy 6）、REF11 日暈之龍・頭舞（legacy 9）
@export var r7_sun_03_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_sun_retsujitsu.res")
@export var r7_sun_08_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_sun_hirin_kagerou.res")
@export var r7_sun_11_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_sun_nichirin_dragon.res")
## 頭舞近距離版（三步縮為 0.45 倍、刀路與時間相同）：前方目標／障礙物走不完整段 1.15 m 時使用
@export var r7_sun_11_near_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_sun_nichirin_dragon_near.res")
## R7 P2 第三批：REF02 碧羅之天（legacy 2）、REF04 幻日虹（legacy 11，避線、無傷害）
@export var r7_sun_02_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_sun_hekira.res")
@export var r7_sun_04_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_sun_genjitsu.res")
## 幻日虹近距離版（側跨縮為 0.28 倍）：左側有牆／障礙物、走不完整段 0.96 m 時使用
@export var r7_sun_04_near_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_sun_genjitsu_near.res")
## P3 資源可稍後生成；只在安裝時讀取，不在物理熱路徑 load。
@export var r7_sun_05_resource: Animation = null
@export var r7_sun_06_resource: Animation = null
@export var r7_sun_09_resource: Animation = null
## REF09 版本開關："mx" = Mixamo twist_flip 改造版（R7_Sun09_ShayouTenshinMX，新動畫名／新 transition key）；
## "p31" = P3.1 REF09 原版（一鍵回退）。環境變數 R7_REF09_VARIANT 可在擷取時覆寫。只影響 id 5。
@export_enum("mx", "p31") var r7_ref09_variant := "mx"
@export var r7_sun_10_resource: Animation = null
## 幻日虹收尾轉向目標的最大角速度（度／秒）；0 = 不轉
@export var r7_evade_face_speed := 540.0
## 診斷：幻日虹結束時面向與目標方向的夾角（度）；-1 = 沒有目標
var r7_face_err := -1.0
## R7K 架勢基準（2026-10-19，ART_REVIEW）：雙手袈裟斬，以型 ID 101 走同一套 R7 型流程（命中掃掠／根位移／取消）。
## R7 場景不設（null → 不登錄）；player_yoriichi_r7k.tscn 指定 r7k_kesa_2h.res。
@export var r7k_kesa_resource: Animation = null
## R7K 拔刀／納刀（含左手鞘引き、出鞘後移向刀柄、納刀對口與沿鞘軸納入）；R7 場景維持 null（不改變 R7 行為）。
@export var r7k_draw_resource: Animation = null
@export var r7k_sheathe_resource: Animation = null
@export var r7k_draw_speed := 1.1
@export var r7k_sheathe_speed := 1.0
var _r7k_ds_ready := false
var _r7k_ds_active := false
var _r7k_ds_is_draw := true
var _r7k_ds_lower_on := false
var _r7k_ds_rw := 0.0
var _r7k_ds_lw := 0.0
var _r7k_d_saya := PackedFloat32Array()
var _r7k_d_clip := PackedFloat32Array()
var _r7k_d_vis := PackedByteArray()
var _r7k_d_lw := PackedFloat32Array()
var _r7k_d_rw := PackedFloat32Array()
var _r7k_d_n := 0
var _r7k_s_saya := PackedFloat32Array()
var _r7k_s_clip := PackedFloat32Array()
var _r7k_s_vis := PackedByteArray()
var _r7k_s_lw := PackedFloat32Array()
var _r7k_s_rw := PackedFloat32Array()
var _r7k_s_n := 0
## 日之呼吸後段的閃避／架刀取消（R7 候選限定；正式控制器的型仍不可取消）：R7_FORMS.cancel 起，且所有命中窗已結束、著地、刀在手
@export var r7_form_late_cancel := true
## R7 型的命中改用刀身掃掠：每個物理步把上一步與這一步的刀段（BladeBase→BladeTip，沿用父類的兩個 Marker3D）
## 以 Transform3D 插值切 3 段，連成薄凸體做 intersect_shape，命中仍交給父類 _on_hit_target（同一個去重、傷害、受擊流程）。
## false = 父類舊判定（刀上 r0.40 膠囊 overlap）。只作用於 R7_FORMS；輕攻擊／重斬本輪仍是舊膠囊。
@export var r7_blade_sweep := true
## 刀身實測（_sword_hand 本地、縮放前；yoriichi_sword mesh 逐 5 cm 切片量得，2026-10-19）：鍔在 y≈0.10，
## 刃從 0.12 到切先 1.085，有反り（中線 x 由 0 漸增到 0.078）、刀身寬約 0.046（本地 x）、厚約 0.013（本地 z）。
## 父類 BladeBase/BladeTip（0,0.1）→（0,1.05）是直線且短 3.5 cm，掃掠改用這條中線。
const R7_BLADE_LINE := [Vector3(0.0, 0.12, 0.0), Vector3(0.006, 0.40, -0.003), Vector3(0.025, 0.70, -0.006),
	Vector3(0.048, 0.90, -0.010), Vector3(0.074, 1.085, -0.014)]
const R7_BLADE_HALF_W := 0.023
const R7_BLADE_HALF_T := 0.007
## 診斷：R7 型每個物理步的刀段（世界座標），擷取工具讀出後離線比對真實接觸
var r7_blade_trace: Array = []   ## [clock, hit_group, [5 刀身中線點, Neck, Head]]
var _r7_skel: Skeleton3D = null
## 診斷：掃掠幾何查詢耗時累計（µs，不含命中後處理）與呼叫次數（每個窗內物理步一次＝12 次凸包查詢）
var r7_sweep_usec := 0
var r7_sweep_calls := 0
var r7_sweep_hits: Array = []   ## 診斷：[clock, hit_group, collider 名, 類別]
var _r7_prev_hand := Transform3D()
var _r7_prev_in_win := false   ## 上一個物理步的手變換已記錄（同一個動作內）
## 陽華突的近距離版（前方目標／牆在 ~1 m 內：短步、淺弓步、位移 0.28 m）
@export var r7_sun_07_near_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_sun_youkatotsu_near.res")
## 型的實際位移（clip metadata r7_root_fwd：每格前進量 m）→ CharacterBody3D。前方有目標時在接觸前停住：
## 停止距離 = 目標距離 − 自身半徑 − 目標半徑 − 此餘量（牆與其他障礙交給碰撞）
@export_range(0.0, 0.5, 0.01) var r7_root_stop_margin := 0.10
@export_range(0.0, 1.0, 0.05) var r7_root_target_cone := 0.80   ## 目標方向與面向的 cos 下限（0.8 ≈ ±37°）
@export var r7_sun_speed := 2.0
## 疾跑中發動（陽華突）時保留的前衝比例與秒數（腳在 clip 裡紮地；只做短暫煞停滑行，不是位移技）
@export_range(0.0, 1.0, 0.05) var r7_sun_carry := 0.35
@export var r7_sun_carry_time := 0.14
## legacy ID → R7 新製型。cancel = 可接下一招的進度（製作卡 9.3），fade = 收勢淡回秒數
var R7_AIR_PATHS := {
	10: "res://characters/yoriichi/v24/anims_r7/r7_sun_kasha.res",
	4: "res://characters/yoriichi/v24/anims_r7/r7_sun_shakkotsu.res",
	5: "res://characters/yoriichi/v24/anims_r7/r7_sun_shayou_tenshin.res",
	7: "res://characters/yoriichi/v24/anims_r7/r7_sun_kiki_onkou.res",
}
var R7_FORMS := {
	10: {"anim": "R7_Sun05_Kasha", "key": "r7_sun05", "ref": "REF05", "cancel": 0.70, "fade": 0.20, "air": true},   # P3.1：觸地 f58＋12 格＝f70／101 格
	4: {"anim": "R7_Sun06_Shakkotsu", "key": "r7_sun06", "ref": "REF06", "cancel": 0.72, "fade": 0.12, "air": true},
	5: {"anim": "R7_Sun09_ShayouTenshin", "key": "r7_sun09", "ref": "REF09", "cancel": 0.74, "fade": 0.12, "air": true},
	7: {"anim": "R7_Sun10_KikiOnkou", "key": "r7_sun10", "ref": "REF10", "cancel": 0.82, "fade": 0.12, "air": true},
	1: {"anim": "R7_Sun01_Enbu", "key": "r7_sun01", "ref": "REF01", "cancel": 0.70, "fade": 0.20},
	8: {"anim": "R7_Sun07_Youkatotsu", "key": "r7_sun07", "ref": "REF07", "cancel": 0.58, "fade": 0.22,
		"run_anim": "R7_Sun07_YoukatotsuRun", "run_key": "r7_sun07r", "near_anim": "R7_Sun07_YoukatotsuNear", "near_key": "r7_sun07n"},
	12: {"anim": "R7_Sun12_EnbuDouble", "key": "r7_sun12", "ref": "REF12", "cancel": 0.82, "fade": 0.22},
	3: {"anim": "R7_Sun03_Retsujitsu", "key": "r7_sun03", "ref": "REF03", "cancel": 0.72, "fade": 0.22},
	6: {"anim": "R7_Sun08_HirinKagerou", "key": "r7_sun08", "ref": "REF08", "cancel": 0.66, "fade": 0.20},
	101: {"anim": "R7K_Kesa2H", "key": "r7k_kesa", "ref": "R7K", "cancel": 0.62, "fade": 0.20},
	# REF01 右鍵分支：只由 REF01 期間右鍵進入（_r7_rmb_*）。branch＝不發 form_executed、不播型音效（不新增音效）；
	# 不在 SunBreathing.FORMS → 不扣呼吸、無冷卻、傷害＝一般重斬基數（與 R7K 101 同一套政策）。
	102: {"anim": "R7_Sun01_RmbSpinCut", "key": "r7_sun01rmb", "ref": "REF01_RMB", "cancel": 0.78, "fade": 0.22, "branch": true},
	2: {"anim": "R7_Sun02_Hekira", "key": "r7_sun02", "ref": "REF02", "cancel": 0.82, "fade": 0.28},
	# 幻日虹（v3 0.85 s，含 0.17 s 低位備戰停留）：無敵窗以絕對時間 0.11–0.33 s 對齊原規格 [0.16,0.48)×0.68 s → 進度 [0.128,0.386)；
	# face_win 對齊右腳收步騰空 f27.5–32.5；取消門檻沿用已確認的 0.70（＋位移結束）。
	# 幻日虹：無命中窗；evade = 無敵窗（進度）；不往前方目標停步（是往旁邊離開攻擊線）；收尾轉向目標；位移走完才可取消
	11: {"anim": "R7_Sun04_Genjitsu", "key": "r7_sun04", "ref": "REF04", "cancel": 0.70, "fade": 0.30, "stop_root": true,
		"no_target_stop": true, "evade": [0.128, 0.386], "face_win": [0.55, 0.63], "face_pivot": "mixamorig_LeftToeBase",
		"near_anim": "R7_Sun04_GenjitsuNear", "near_key": "r7_sun04n"},
	9: {"anim": "R7_Sun11_NichirinDragon", "key": "r7_sun11", "ref": "REF11", "cancel": 0.78, "fade": 0.22, "stop_root": true,
		"near_anim": "R7_Sun11_NichirinDragonNear", "near_key": "r7_sun11n"},
}
## 一次滯空只能使用一個空中型；只在實際落地重設，不在受擊／型結束重設。
enum R7AirPhase { NONE, AIR_ACTION, AIR_HOLD, WAIT_CONTACT, LAND_RECOVER }
var r7_air_phase := R7AirPhase.NONE
var r7_air_exit := ""
var _r7_air_used := false
var _r7_air_launched := false
var _r7_air_left_floor := false
var _r7_air_takeoff := 0.0
var _r7_air_takeoff_v := 0.0
var _r7_air_contact := 0.0
var _r7_air_hold := 0.0
var _r7_air_wait := 0.0
var _r7_air_hold_done := false
var _r7_air_step_v := Vector3.ZERO
var _r7_air_ik_saved := {}
var _r7_air_node: AnimationNodeAnimation = null
var _r7_followup_left := 0.0
var _r7_wins: Array = []
var _r7_win_idx := -1
var _r7_trail_def := {}
var _r7_form_on := false
var _r7_form_saved_move := 0.5
var _r7_followup := ""
## 測試記錄用：目前所在的命中組（1 起算；0 = 不在任何命中窗內）
var r7_hit_group := 0
var _r7_root := PackedFloat32Array()
var _r7_root_side := PackedFloat32Array()   ## 側向位移（角色右 +）；空 = 只有前後
var _r7_root_dir := Vector3.ZERO
var _r7_root_right := Vector3.ZERO
var _r7_root_req := 0.0
var _r7_root_req_s := 0.0
var _r7_root_cap := INF
## 測試記錄用：本次型的實際位移上限（m；INF = 無目標限制）與使用的版本
var r7_root_cap_used := -1.0
var r7_form_variant := ""
## false = 關閉刀光與蓄力火焰（審本體用）
@export var r7_vfx_enabled := true

## 移動中的輕攻擊：上半身專用版（骨盆由 locomotion 接管、胸廓扭轉限 ±32°；v2 起）
@export var r7_light_01_move_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_light_01_move.res")
@export var r7_light_02_move_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_light_02_move.res")
@export var r7_light_03_move_resource: Animation = preload("res://characters/yoriichi/v24/anims_r7/r7_light_03_move.res")

const R7_LIGHT := ["R7_Light01", "R7_Light02", "R7_Light03"]
const R7_LIGHT_M := ["R7_Light01M", "R7_Light02M", "R7_Light03M"]
var _r7_hit := PackedInt32Array([-1, -1])
var _r7_rel_on := false
## 最近一段輕攻擊用的是哪一版（"atk1" / "atk1m"…），測試記錄用
var r7_last_light_key := ""
var _r7_hit_speed := 1.0
var _r7_trail_on := false


## R7 專用握柄指形（tools/yoriichi_r7/solve_grip_r7.gd 解出；共用的 r62_grip.json 不動）
const R7_GRIP_JSON := "res://characters/yoriichi/v24_r7/r7_grip.json"
@export var r7_grip_fingers_enabled := true
## R7 P5 普通跳躍（空白鍵）：mx＝Sword And Shield Running Jump 三段候選（v24_r7/jump_mx/r7_jump_mx_*.res）；r61＝舊版（場景 jump/fall/land_resource）。
## 環境變數 R7_JUMP_VARIANT=r61|mx 可覆寫。只換 JumpStart／Fall／Land 的 clip；起跳速度、重力、空中控制、碰撞、時間倍率全部不變。
@export_enum("mx", "r61") var r7_jump_variant := "mx"
const R7_JUMP_MX := {
	"jump": ["R7_Jump_MX", "res://characters/yoriichi/v24_r7/jump_mx/r7_jump_mx_start.res"],
	"fall": ["R7_Fall_MX", "res://characters/yoriichi/v24_r7/jump_mx/r7_jump_mx_air.res"],
	"land": ["R7_Land_MX", "res://characters/yoriichi/v24_r7/jump_mx/r7_jump_mx_land.res"],
}
## 快速拔刀斬被打斷時：刀身露出比例 ≥ 此值 → 留在手上（持刀狀態）；否則回鞘
@export_range(0.0, 1.0, 0.05) var r7_qd_interrupt_keep_ratio := 0.6


func _ready():
	var _ev := OS.get_environment("R7_REF09_VARIANT")
	if _ev in ["mx", "p31"]:
		r7_ref09_variant = _ev
	if r7_ref09_variant == "mx":
		# MX：123 格（觸地 f68）→ 取消點＝觸地＋12 格＝f80 / 122 ≈ 0.66；收勢淡出 0.20
		R7_FORMS[5] = {"anim": "R7_Sun09_ShayouTenshinMX", "key": "r7_sun09mx", "ref": "REF09", "cancel": 0.66, "fade": 0.20, "air": true}
		R7_AIR_PATHS[5] = "res://characters/yoriichi/v24/anims_r7/r7_sun_shayou_tenshin_mx.res"
		r7_sun_09_resource = null
	var _jv := OS.get_environment("R7_JUMP_VARIANT")
	if _jv in ["mx", "r61"]:
		r7_jump_variant = _jv
	if r7_jump_variant == "mx":
		# 新動畫名 → 父類 _add_animation_resource 不會撞到舊 clip；JumpStart 的 clip 長度取自 jump_anim_resource。
		jump_anim = R7_JUMP_MX.jump[0]
		jump_anim_resource = load(R7_JUMP_MX.jump[1])
		fall_anim = R7_JUMP_MX.fall[0]
		fall_resource = load(R7_JUMP_MX.fall[1])
		land_anim = R7_JUMP_MX.land[0]
		land_resource = load(R7_JUMP_MX.land[1])
	r5_speed = r7_quickdraw_speed
	r5_cancel_frame = int(r5_quickdraw_resource.get_meta("r6_cancel_frame", 80)) if r5_quickdraw_resource else 80
	super._ready()
	if r7_jump_variant == "mx" and _anim.has_animation(fall_anim):
		# 父類把 Fall 設成 LOOP_LINEAR；MX 空中段是「頂點→落地前 0.41 s ＋ 4 s 緩擺」，循環會從腳伸直跳回頂點姿勢 → 改不循環（超過停在末格）。
		_anim.get_animation(fall_anim).loop_mode = Animation.LOOP_NONE
	_r7_install()
	_r7_install_grip()


func _r7_install_grip() -> void:
	if not r7_grip_fingers_enabled or _r62_ik == null or not FileAccess.file_exists(R7_GRIP_JSON):
		return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(R7_GRIP_JSON))
	_r62_ik.right_fingers = _r62_quats(d.get("right_fingers", {}))
	_r62_ik.left_fingers = _r62_quats(d.get("left_fingers", {}))


## 快速拔刀斬中途結束（受擊、閃避等打斷）：依當下刀身露出量決定刀在手上或鞘中，
## 不再一律瞬間回鞘（R5 原行為：狀態始終是 SHEATHED → 刀出鞘後被打也會一格跳回鞘裡）。
func _r5_end() -> void:
	var fr := _r62_qd_fr
	var keep := false
	if fr >= 0.0 and _r5_n > 0:
		var f := clampi(int(floor(fr)), 0, _r5_n - 1)
		var mx := 0.0      # 拔刀段最大露出長（clip_y ≥ 50 = 刀已完全在手上）
		for v in _r5_clip:
			if v < 50.0:
				mx = maxf(mx, v)
		if _r5_vis[f] == 1 and mx > 0.0:
			var c := _r5_clip[f]
			keep = c >= 50.0 or (c / mx) >= r7_qd_interrupt_keep_ratio
	super._r5_end()
	if keep:
		sword_state = SwordState.DRAWN
		_apply_sword_visibility()


func _r7_install() -> void:
	if _tree == null:
		return
	var res := [r7_light_01_resource, r7_light_02_resource, r7_light_03_resource]
	for i in 3:
		_add_animation_resource(R7_LIGHT[i], res[i])
	var root := _tree.tree_root as AnimationNodeBlendTree
	for sel in ["upper_sel", "lower_sel"]:
		for i in 3:
			var nn := "%s_atk%d" % [sel, i + 1]
			if root.has_node(nn):
				var n := root.get_node(nn) as AnimationNodeAnimation
				n.animation = R7_LIGHT[i]
				n.use_custom_timeline = false
	# 移動版只進 upper 層（lower 層的 R6_LOWER_INPUTS 不含 atkNm → 腿留在 locomotion）
	var mres := [r7_light_01_move_resource, r7_light_02_move_resource, r7_light_03_move_resource]
	var usel := root.get_node("upper_sel") as AnimationNodeTransition
	for i in 3:
		if mres[i] == null:
			continue
		_add_animation_resource(R7_LIGHT_M[i], mres[i])
		var key := "atk%dm" % (i + 1)
		var ui := usel.input_count
		usel.input_count = ui + 1
		usel.set_input_name(ui, key)
		usel.set_input_reset(ui, true)
		root.add_node("upper_sel_" + key, _anim_node(R7_LIGHT_M[i]))
		root.connect_node("upper_sel", ui, "upper_sel_" + key)
	# R7 P2 日之呼吸：full 層（全身，腳步在 clip 裡）
	var fsel := root.get_node("full_sel") as AnimationNodeTransition
	var fres := {1: r7_sun_01_resource, 8: r7_sun_07_resource, 12: r7_sun_12_resource,
		3: r7_sun_03_resource, 6: r7_sun_08_resource, 9: r7_sun_11_resource, 2: r7_sun_02_resource, 11: r7_sun_04_resource,
		101: r7k_kesa_resource, 102: r7_sun01_rmb_resource}
	var vres := {8: r7_sun_07_run_resource}
	var nres := {8: r7_sun_07_near_resource, 9: r7_sun_11_near_resource, 11: r7_sun_04_near_resource}
	for id in R7_FORMS:
		var d: Dictionary = R7_FORMS[id]
		var pairs := [[d.anim, d.key, fres.get(id)]]
		if d.has("run_anim"):
			pairs.append([d.run_anim, d.run_key, vres.get(id)])
		if d.has("near_anim"):
			pairs.append([d.near_anim, d.near_key, nres.get(id)])
		for pr in pairs:
			var fa: Animation = pr[2]
			if fa == null:
				continue
			_add_animation_resource(pr[0], fa)
			var fi := fsel.input_count
			fsel.input_count = fi + 1
			fsel.set_input_name(fi, pr[1])
			fsel.set_input_reset(fi, true)
			root.add_node("full_sel_" + pr[1], _anim_node(pr[0]))
			root.connect_node("full_sel", fi, "full_sel_" + pr[1])
	if not r7_vfx_enabled:
		if _sword_trail != null:
			_sword_trail.visible = false
		if _charge_fx != null:
			# start() 會自己 visible=true 並給刀身換發光材質、滿蓄時點火 → 只能整個拿掉（父類所有呼叫都有 null 檢查）
			_charge_fx.queue_free()
			_charge_fx = null
	r7_install_air_forms()
	_r7c_install_seams()
	_r7k_install_draw_sheathe(root)


## 段落改為獨立 clip：時長 = clip 長 ÷ 倍率；命中窗只開在 clip metadata 的切削格。
func _start_light_section(stage: int) -> void:
	var a: Animation = [r7_light_01_resource, r7_light_02_resource, r7_light_03_resource][stage - 1]
	_action_real = a.length / r7_light_speed
	_action_elapsed = 0.0
	var is_moving := velocity.length_squared() > 0.5 or _read_input_dir().length_squared() > 0.0
	_upper_finish_fade = 0.08 if is_moving else (0.20 if stage >= 3 else 0.12)
	r7_last_light_key = ("atk%dm" if is_moving and r7_light_01_move_resource != null else "atk%d") % stage
	_fire_upper(r7_last_light_key, r7_light_speed)
	_character_audio.play_swing(stage)
	_hit_targets_this_swing.clear()
	_r7_begin_window(a.get_meta("r7_hit_window", PackedInt32Array([-1, -1])), r7_light_speed)


func _combo_stage_speed(_stage: int) -> float:
	return r7_light_speed


func _r7_begin_window(win, spd: float) -> void:
	_r7_trail_def = {}
	_r7_begin_windows([win], spd)


## 多段命中窗（clip 格數）：每進入下一個窗＝新的命中組，同一目標可再被命中一次；窗外判定關閉。
func _r7_begin_windows(wins: Array, spd: float) -> void:
	_r7_wins = []
	_r7_prev_in_win = false
	for w in wins:
		var pw := PackedInt32Array(w)
		if pw.size() >= 2 and pw[0] >= 0:
			_r7_wins.append(pw)
	_r7_hit = _r7_wins[0] if not _r7_wins.is_empty() else PackedInt32Array([-1, -1])
	_r7_win_idx = -1
	r7_hit_group = 0
	_r7_hit_speed = spd
	_r7_trail_on = false
	if _hitbox != null:
		_hitbox.monitoring = false
	if _sword_trail != null:
		_sword_trail.stop_trail()


func _r7_window_tick() -> void:
	if _r7_is_air() and r7_air_phase != R7AirPhase.AIR_ACTION:
		_r7_air_close_damage()
		return
	if _r7_wins.is_empty():
		return
	var fr := _action_elapsed * _r7_hit_speed * 30.0
	var idx := -1
	for i in _r7_wins.size():
		var w: PackedInt32Array = _r7_wins[i]
		if fr >= float(w[0]) and fr < float(w[1]) + 1.0:
			idx = i
			break
	if idx > _r7_win_idx:
		if idx > 0:
			_hit_targets_this_swing.clear()
			_hit_targets_this_swing["_rehit_done"] = true
		_r7_win_idx = idx
	var on := idx >= 0
	r7_hit_group = idx + 1
	var sweep := r7_blade_sweep and R7_FORMS.has(active_form) and _sword_hand != null and _blade_base != null and _blade_tip != null
	if _hitbox != null:
		_hitbox.monitoring = on and not sweep
	if R7_FORMS.has(active_form) and _sword_hand != null and _blade_base != null and _blade_tip != null:
		var hx := _sword_hand.global_transform
		var line := []
		for lp in R7_BLADE_LINE:
			line.append(hx * lp)
		# 診斷：頸（Neck→Head 骨）位置，給離線頸部淨空用
		if _r7_skel == null and _visual != null:
			var sks := _visual.find_children("*", "Skeleton3D", true, false)
			if not sks.is_empty():
				_r7_skel = sks[0] as Skeleton3D
		if _r7_skel != null:
			for bn in ["mixamorig_Neck", "mixamorig_Head"]:
				var bi := _r7_skel.find_bone(bn)
				line.append(_r7_skel.global_transform * _r7_skel.get_bone_global_pose(bi).origin if bi >= 0 else Vector3.ZERO)
		r7_blade_trace.append([snappedf(_action_elapsed, 0.0001), idx + 1, line])
	if sweep:
		# 窗內每個物理步都掃「上一步 → 這一步」（含進窗那一步），與 clip 的命中格 f（速度＝tip(f)−tip(f−1)）一一對應
		var cur := _sword_hand.global_transform
		if on and _r7_prev_in_win:
			_r7_sweep_blade(_r7_prev_hand, cur)
		_r7_prev_hand = cur
		_r7_prev_in_win = true
	if on and not _r7_trail_on and _sword_trail != null:
		_r7_trail_on = true
		if _r7_trail_def.is_empty():
			_sword_trail.reset_form()
		else:
			_sword_trail.apply_form(_r7_trail_def)
		_sword_trail.start_trail()
	elif not on and _r7_trail_on and fr > float((_r7_wins[maxi(_r7_win_idx, 0)] as PackedInt32Array)[1]) + 3.0 and _sword_trail != null:
		_sword_trail.stop_trail()
		_r7_trail_on = false


## 刀段從 a 掃到 b（兩個 _sword_hand 全域變換）：切 3 段，每段 8 點薄凸體，查 _hitbox 同一 collision_mask 的身體與區域。
## 刀身從 a 掃到 b（兩個 _sword_hand 全域變換）：時間切 3 段 × 刀身 4 節，每塊＝兩個時刻的兩個截面（寬×厚 4 角）共 16 點凸包，
## 查 _hitbox 同一 collision_mask 的身體與區域；命中交給父類 _on_hit_target（去重／傷害／受擊同一流程）。
func _r7_sweep_blade(a: Transform3D, b: Transform3D) -> void:
	_r7_sweep_body(a, b)
	r7_sweep_calls += 1


func _r7_sweep_body(a: Transform3D, b: Transform3D) -> void:
	var t0 := Time.get_ticks_usec()
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.collision_mask = _hitbox.collision_mask if _hitbox != null else 3
	q.collide_with_bodies = true
	q.collide_with_areas = true
	q.exclude = [get_rid()]
	q.transform = Transform3D.IDENTITY
	var corners := [Vector3(R7_BLADE_HALF_W, 0, R7_BLADE_HALF_T), Vector3(-R7_BLADE_HALF_W, 0, R7_BLADE_HALF_T),
		Vector3(R7_BLADE_HALF_W, 0, -R7_BLADE_HALF_T), Vector3(-R7_BLADE_HALF_W, 0, -R7_BLADE_HALF_T)]
	const NT := 3
	var hit := {}
	for k in NT:
		var xa := a.interpolate_with(b, float(k) / NT)
		var xb := a.interpolate_with(b, float(k + 1) / NT)
		for s in R7_BLADE_LINE.size() - 1:
			var pts := PackedVector3Array()
			for xf in [xa, xb]:
				for lp in [R7_BLADE_LINE[s], R7_BLADE_LINE[s + 1]]:
					for c in corners:
						pts.append(xf * (lp + c))
			var sh := ConvexPolygonShape3D.new()
			sh.points = pts
			q.shape = sh
			for r in space.intersect_shape(q, 16):
				var col: Object = r.get("collider")
				if col is Node:
					hit[col] = true
	r7_sweep_usec += Time.get_ticks_usec() - t0   # 只計幾何查詢；命中後的傷害／火花／音效另計
	if action_state != ActionState.ATTACKING:
		return
	for col in hit:
		r7_sweep_hits.append([snappedf(_action_elapsed, 0.0001), r7_hit_group, str((col as Node).name), (col as Node).get_class()])
		_on_hit_target(col as Node)


## 幻日虹的無敵窗：沿用父類 take_hit 的翻滾無敵入口（同一個「閃避成功」流程），只在 R7_FORMS 有 evade 的型、該進度區間成立
## clip metadata 優先（R7K 版幻日虹自帶 r7_evade／r7_face_win），否則用 R7_FORMS 的值
func _r7_clip_win(key: String, fallback: Array) -> Array:
	if _anim != null and _anim.has_animation(_active_attack_name):
		var a: Animation = _anim.get_animation(_active_attack_name)
		if a.has_meta(key):
			return Array(a.get_meta(key))
	return fallback


func in_dodge_invuln() -> bool:
	if action_state == ActionState.ATTACKING and R7_FORMS.has(active_form) and R7_FORMS[active_form].has("evade"):
		var w: Array = _r7_clip_win("r7_evade", R7_FORMS[active_form].evade)
		var pr := _attack_progress()
		return pr >= float(w[0]) and pr < float(w[1])
	return super.in_dodge_invuln()


## 幻日虹收尾轉向：在右腳收步（騰空）的 face_win 進度區間內，以左腳（支撐腳）為軸把角色轉向目標
## （鎖定目標優先，否則最近敵人），同時平移角色讓左腳世界位置不動 → 支撐腳不滑；右腳在空中，落地即在新方向。
func _r7_face_tick(delta: float) -> void:
	if not R7_FORMS.has(active_form) or not R7_FORMS[active_form].has("face_win") or action_state != ActionState.ATTACKING:
		return
	var t: Node3D = lock_target if lock_target != null and is_instance_valid(lock_target) else _nearest_enemy()
	if t == null or _visual == null:
		r7_face_err = -1.0
		return
	var to := t.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 1e-4:
		return
	var want := atan2(to.x, to.z)
	var w: Array = _r7_clip_win("r7_face_win", R7_FORMS[active_form].face_win)
	var pr := _attack_progress()
	if pr >= float(w[0]) and r7_evade_face_speed > 0.0:
		var cur := _visual.global_rotation.y
		var diff := wrapf(want - cur, -PI, PI)
		# 剩下的轉角平均分到 face_win 結束前的時間（最慢也要 r7_evade_face_speed）
		var left_t := maxf((float(w[1]) - pr) * _action_real, delta)
		var stp := maxf(absf(diff) * delta / left_t, 0.0) if pr < float(w[1]) else absf(diff)
		stp = minf(stp, deg_to_rad(r7_evade_face_speed) * delta) if pr < float(w[1]) else stp
		var d := clampf(diff, -stp, stp)
		if absf(d) > 1e-5:
			var piv := global_position
			if _r7_skel == null and _visual != null:
				var sks := _visual.find_children("*", "Skeleton3D", true, false)
				if not sks.is_empty():
					_r7_skel = sks[0] as Skeleton3D
			if _r7_skel != null and R7_FORMS[active_form].has("face_pivot"):
				var bi := _r7_skel.find_bone(String(R7_FORMS[active_form].face_pivot))
				if bi >= 0:
					piv = _r7_skel.global_transform * _r7_skel.get_bone_global_pose(bi).origin
			var rel := global_position - piv
			rel.y = 0.0
			# 經碰撞移動（牆邊不穿牆；被擋住時支撐腳會略滑，但不進牆）
			move_and_collide(Vector3(piv.x, global_position.y, piv.z) + rel.rotated(Vector3.UP, d) - global_position)
			_visual.global_rotation.y = cur + d
	r7_face_err = rad_to_deg(absf(wrapf(want - _visual.global_rotation.y, -PI, PI)))


func r7_set_blade_sweep(on: bool) -> void:
	r7_blade_sweep = on


func _physics_process(delta):
	_r7c_watch(delta)
	if is_on_floor() and not _r7_is_air():
		_r7_air_used = false
	if _r7_is_air() and not _r7_air_control_ok():
		r7_air_exit = "interrupted"
		_finish_attack()
	var saved_jump_v := jump_velocity
	if _r7_is_air():
		_r7_air_prepare(delta)
	# 型的實際位移：本格要走到 action clock（t + delta）對應的 root(f)。父類在 move_and_slide 之後才推進 clock，
	# 所以這裡先算速度，經 _form_dash 交給父類（k ≈ 1、移動倍率 0 → velocity = 位移速度）。
	var root_v := Vector3.ZERO
	var root_on := _r7_form_on and R7_FORMS.has(active_form) and action_state == ActionState.ATTACKING and _r7_root.size() > 1
	var hs := _hitstop_time > 0.0
	if root_on:
		# 實測：AnimationTree 的姿勢比 action clock 晚一個物理步（1/60 s）→ 以目前 clock 取 root，支撐腳才不會先前後滑
		var fr: float = _action_elapsed * r7_sun_speed * 30.0
		var i0 := clampi(int(floor(fr)), 0, _r7_root.size() - 1)
		var i1 := mini(i0 + 1, _r7_root.size() - 1)
		var u := clampf(fr - float(i0), 0.0, 1.0)
		var req := lerpf(_r7_root[i0], _r7_root[i1], u)
		var req_s := 0.0
		if _r7_root_side.size() > i1:
			req_s = lerpf(_r7_root_side[i0], _r7_root_side[i1], u)
		var plen := Vector2(req, req_s).length()
		if plen > _r7_root_cap and plen > 1e-6:
			req *= _r7_root_cap / plen
			req_s *= _r7_root_cap / plen
		req = maxf(req, _r7_root_req)
		root_v = (_r7_root_dir * (req - _r7_root_req) + _r7_root_right * (req_s - _r7_root_req_s)) / maxf(delta, 1e-5)
		_r7_root_req = req
		_r7_root_req_s = req_s
		if _r7_is_air():
			if r7_air_phase == R7AirPhase.AIR_HOLD or r7_air_phase == R7AirPhase.WAIT_CONTACT:
				root_v = Vector3.ZERO
			_r7_air_step_v = root_v
		_form_dash = root_v
		_form_dash_total = 1.0e6
		_form_dash_left = 1.0e6
	# 命中停頓（hitstop）期間父類整個 _physics_process 提早 return，action clock 不走、AnimationTree 照播 →
	# 命中窗（以 action clock 計）落後動畫（實測炎舞第一刀命中後第二刀窗晚 0.07 s，刀已掃過目標才開）。
	# R7：停頓期間 action clock 照走，命中窗／刀鞘表／取消點與畫面同步（停頓仍只凍結移動，與父類手感相同）。
	if _hitstop_time > 0.0 and action_state == ActionState.ATTACKING and not _r7_is_air() and not _heavy_charging and _iai_unfreeze_in < 0.0:
		_action_elapsed += delta
	_r7_rmb_watch(delta)
	# R7 型進行中的後續輸入改由 R7 取消窗口消費（父類會用舊型表的 cancel.x）
	if _r7_form_on and R7_FORMS.has(active_form) and _form_followup != "":
		_r7_followup = _form_followup
		_r7_followup_left = combo_input_buffer_time
		_form_followup = ""
	if _r7_is_air() and _r7_followup != "":
		_r7_followup_left = maxf(0.0, _r7_followup_left - delta)
		if _r7_followup_left <= 0.0:
			_r7_followup = ""
	super._physics_process(delta)
	jump_velocity = saved_jump_v
	if is_on_floor() and not _r7_is_air():
		_r7_air_used = false
	if _r7_is_air():
		_r7_air_disable_ik()
	if _r7k_ds_active and _r62_ik != null:
		_r62_w = _r7k_ds_rw
		_r62_ik.right_weight = _r7k_ds_rw
		_r62_ik.left_enabled = r62_left_grip_enabled and _r62_has_left and (_r7k_ds_lw > 0.001)
		_r62_ik._lw = _r7k_ds_lw
	if _r7k_ds_lower_on:
		if _r6_lower == null or not _r6_still():
			_r7k_ds_lower_on = false
			_r6_lower_fade()
		elif not _r7k_ds_active or not _tree.get("parameters/upper/internal_active"):
			_r7k_ds_lower_on = false
			_r6_lower_fade(r6_lower_endfade)
		else:
			_tree.set("parameters/ts_lower/scale", _tree.get("parameters/ts_upper/scale"))
	if _r7_is_air() and hs:
		# full 命中停頓仍跑同一重力／碰撞／空中時鐘，不能懸停。
		velocity.x = _r7_air_step_v.x
		velocity.z = _r7_air_step_v.z
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
		if _jump_charge >= 0.0:
			_jump_charge = -1.0
			velocity.y = _r7_air_takeoff_v
		move_and_slide()
		_r7_air_advance(delta)
	elif root_on and hs:
		# 父類在命中停頓時提早 return、不 move_and_slide；動畫照播 → 位移也要照走，否則腳會在世界中滑
		velocity.x = root_v.x
		velocity.z = root_v.z
		move_and_slide()
	if _r7_form_on and (action_state != ActionState.ATTACKING or not R7_FORMS.has(active_form)):
		_r7_form_end()
	if action_state != ActionState.ATTACKING:
		_r7_hit = PackedInt32Array([-1, -1])
		_r7_rel_on = false
		r7_hit_group = 0
		return
	if R7_FORMS.has(active_form):
		_r7_window_tick()
		_r7_face_tick(delta)
		# REF01 右鍵分支：同 tick 優先於自動續招（_r7c_tick 的交接）；待處理的合法閃避仍優先（_r7_rmb_tick 讓出）
		if _r7_rmb_tick():
			return
		if _r7_followup != "" and (_in_form_cancel_window() if _r7_is_air() else _attack_progress() >= float(R7_FORMS[active_form].cancel)):
			var act := _r7_followup
			_r7_followup = ""
			_finish_attack()
			if act == "light":
				_start_combo()
			else:
				request_heavy_cut()
		else:
			_r7c_tick(_read_input_dir())
	elif combo_stage > 0 and active_form == 0:
		_r7_window_tick()
	elif _active_attack_name == "Heavy_Cut" and _iai_charged and _attack_layer == "full" and not _heavy_frozen \
			and _iai_unfreeze_in < 0.0:
		# 蓄力釋放（切り上げ）：只在 clip 的切削格開判定（每次釋放重新開窗，不沿用上一刀的窗）
		if not _r7_rel_on:
			_r7_rel_on = true
			_r7_begin_window(iai_slash_resource.get_meta("r7_hit_window", PackedInt32Array([-1, -1])), heavy_charge_slash_speed)
		_r7_window_tick()
	else:
		_r7_rel_on = false


## 日之呼吸：R7_FORMS 的新製型走 R7 流程；舊型在 R7 候選停用（連段分支、重斬分支、疾跑重斬、彈刀反擊、十三型都經過這裡）。
func execute_form(id: int, free := false) -> bool:
	if R7_FORMS.has(id):
		return _r7_execute_form(id, free)
	if not r7_forms_enabled:
		return false
	return super.execute_form(id, free)


## R7 型：全身 clip（腳步、重心都在 clip 裡，移動倍率 0 → 不滑步）；命中窗＝clip metadata r7_hit_windows（多組）；
## 呼吸、冷卻、熟練度、傷害倍率沿用舊型表同一 legacy ID 的數值（存檔／HUD／分支鍵不變）。
func form_block_reason(id: int) -> String:
	if not R7_AIR_PATHS.has(id):
		return super.form_block_reason(id)
	var d: Dictionary = SunBreathing.FORMS[id]
	if int(d.required_mastery) > sun_mastery:
		return "mastery"
	if _anim == null or not _anim.has_animation(R7_FORMS[id].anim):
		return "no_anim"
	if form_cooldown_left(id) > 0.0:
		return "cooldown"
	if sun_breath_gauge < float(d.breath_cost):
		return "breath"
	if not _r7_air_control_ok() or action_state != ActionState.FREE:
		return "busy"
	if not is_on_floor() and _r7_air_used:
		return "airborne_used"
	return ""


func _r7_execute_form(id: int, free: bool) -> bool:
	var d: Dictionary = R7_FORMS[id]
	if sword_state != SwordState.DRAWN or _anim == null or not _anim.has_animation(d.anim):
		return false
	var aerial := bool(d.get("air", false))
	if aerial:
		if not _r7_air_control_ok() or (not is_on_floor() and _r7_air_used):
			return false
		if not _r7_air_clip_valid(_anim.get_animation(d.anim)):
			return false
	elif not is_on_floor():
		return false
	if form_cooldown_left(id) > 0.0:
		return false
	if not free and not can_use_form(id):
		return false
	if action_state != ActionState.FREE:
		return false
	var hspeed := Vector3(velocity.x, 0.0, velocity.z).length()
	var anim_name: String = d.anim
	var key: String = d.key
	r7_form_variant = "stand"
	if d.has("run_anim") and hspeed > speed + 0.5 and _anim.has_animation(d.run_anim):
		anim_name = d.run_anim
		key = d.run_key
		r7_form_variant = "run"
	var yaw: float = _visual.global_rotation.y if _visual != null else global_rotation.y
	_r7_root_dir = Vector3(sin(yaw), 0.0, cos(yaw))
	_r7_root_right = _r7_root_dir.cross(Vector3.UP)
	var a: Animation = _anim.get_animation(anim_name)
	# P3 的水平慣性明確由 authored root 取代，不疊加跑速；垂直慣性保留，只在不足時補起速。
	var carry := Vector3(velocity.x, 0.0, velocity.z) * r7_sun_carry
	_r7_root = PackedFloat32Array(a.get_meta("r7_root_fwd", []))
	_r7_root_side = PackedFloat32Array(a.get_meta("r7_root_side", []))
	_r7_root_req = 0.0
	_r7_root_req_s = 0.0
	_r7_root_cap = INF
	if _r7_root.size() > 1:
		var dl := _r7_root_disp(_r7_root, _r7_root_side)
		var tstop := INF if bool(d.get("no_target_stop", false)) else _r7_root_stop_for_target()
		_r7_root_cap = minf(tstop, _r7_free_distance(dl, dl.length() + 0.1))
		# 走不完整段 → 換位移較短的版本（疾跑版擠不下就退回站立／近距離版），避免截斷後支撐腳在原地滑
		if _r7_root_cap < _r7_path_len(a) - 0.02:
			var best := ["", "", PackedFloat32Array()]
			for cand in [[d.anim, d.key], [d.get("near_anim", ""), d.get("near_key", "")]]:
				if cand[0] == "" or cand[0] == anim_name or not _anim.has_animation(cand[0]):
					continue
				var ca: Animation = _anim.get_animation(cand[0])
				var ra := PackedFloat32Array(ca.get_meta("r7_root_fwd", []))
				if ra.size() < 2:
					continue
				best = [cand[0], cand[1], ra]
				if _r7_path_len(ca) <= _r7_root_cap + 0.02:
					break
			if best[0] != "":
				anim_name = best[0]
				key = best[1]
				_r7_root = best[2]
				a = _anim.get_animation(anim_name)
				_r7_root_side = PackedFloat32Array(a.get_meta("r7_root_side", []))
				r7_form_variant = "near" if anim_name == d.get("near_anim", "") else "stand"
	# R7 P4 循環接縫：只在 _r7c_exec 指定了上一型、且選定版本有派生 clip 時換用（metadata／root／時長與原 clip 相同）。
	if _r7c_seam_prev > 0 and R7C_SEAMS.has(_r7c_seam_prev):
		var sm: Dictionary = R7C_SEAMS[_r7c_seam_prev].map
		if sm.has(anim_name) and _anim.has_animation(String(sm[anim_name][0])):
			var ent: Array = sm[anim_name]
			r7c_seam_used = String(ent[0])
			anim_name = String(ent[0])
			key = String(ent[1])
			a = _anim.get_animation(anim_name)
		else:
			r7c_seam_used = "fallback:" + anim_name
	r7_root_cap_used = _r7_root_cap if _r7_root.size() > 1 else -1.0
	action_state = ActionState.ATTACKING
	active_form = id
	_active_attack_name = anim_name
	_spin_buffered_cancel = ""
	combo_stage = 0
	_combo_queued_inputs = 0
	combo_input_buffered = false
	_attack_layer = "full"
	_action_real = a.length / r7_sun_speed
	_action_elapsed = 0.0
	if not _r7_form_on:
		_r7_form_saved_move = attack_move_factor_heavy
	attack_move_factor_heavy = 0.0
	_r7_form_on = true
	_r7_followup = ""
	_form_dash_left = 0.0
	if _r7_root.size() <= 1 and hspeed > speed + 0.5 and carry.length() > 0.01:
		# 疾跑中起手：短暫煞停滑行（線性衰減），不是位移技
		_form_dash = carry
		_form_dash_total = maxf(r7_sun_carry_time, 0.001)
		_form_dash_left = _form_dash_total
	if _r7_root.size() > 1:
		velocity.x = 0.0
		velocity.z = 0.0
	if aerial:
		_r7_air_begin(a, key)
	_fire_full(key, r7_sun_speed)
	if _full_node:
		_full_node.fadeout_time = float(d.fade)
	var legacy: Dictionary = SunBreathing.FORMS.get(id, {})
	if not free:
		add_breath(-float(legacy.get("breath_cost", 0.0)))
	if float(legacy.get("cooldown", 0.0)) > 0.0:
		_form_cooldowns[id] = float(legacy.cooldown)
	if not bool(d.get("branch", false)):
		form_executed.emit(id)
		if _character_audio != null:
			_character_audio.play_form(id)
	_hit_targets_this_swing.clear()
	_hit_targets_this_swing["_rehit_done"] = true   # 父類舊型 rehit（拾貳 0.55）不用：命中組由 r7_hit_windows 決定
	_r7_trail_def = legacy
	_r7_begin_windows(a.get_meta("r7_hit_windows", [a.get_meta("r7_hit_window", [-1, -1])]), r7_sun_speed)
	return true


func _r7_form_end() -> void:
	_r7_air_end()
	_r7_prev_in_win = false
	_r7_form_on = false
	_r7_followup = ""
	attack_move_factor_heavy = _r7_form_saved_move
	_r7_root = PackedFloat32Array()
	_r7_root_side = PackedFloat32Array()
	_r7_root_req = 0.0
	_r7_root_req_s = 0.0
	_form_dash_left = 0.0


## clip 整段根位移的路徑長（前後＋側向）
func _r7_path_len(a: Animation) -> float:
	var f := PackedFloat32Array(a.get_meta("r7_root_fwd", []))
	var sd := PackedFloat32Array(a.get_meta("r7_root_side", []))
	return Vector2(f[f.size() - 1] if f.size() > 0 else 0.0, sd[sd.size() - 1] if sd.size() > 0 else 0.0).length()


## 整段位移向量（世界）
func _r7_root_disp(fwd: PackedFloat32Array, side: PackedFloat32Array) -> Vector3:
	var df := fwd[fwd.size() - 1] if fwd.size() > 0 else 0.0
	var ds := side[side.size() - 1] if side.size() > 0 else 0.0
	return _r7_root_dir * df + _r7_root_right * ds


## 沿位移方向還能走多遠（牆、台階、木樁等碰撞體；test_move 不移動角色）
func _r7_free_distance(disp: Vector3, want: float) -> float:
	if disp.length_squared() < 1e-8:
		return INF
	var col := KinematicCollision3D.new()
	if test_move(global_transform, disp.normalized() * want, col):
		return maxf(0.0, col.get_travel().length() - 0.02)
	return INF


## R7 型的後段取消（V1.0 §9.3 門檻）：進度 ≥ R7_FORMS.cancel、所有命中窗已結束（不切斷有效斬擊）、著地、刀在手、REF11 另需追進已停（剩餘位移 ≤ 3 cm）。
func r7_form_cancel_ok() -> bool:
	if not r7_form_late_cancel or not R7_FORMS.has(active_form) or action_state != ActionState.ATTACKING:
		return false
	if _r7_is_air() and (r7_air_phase != R7AirPhase.LAND_RECOVER or not _r7_air_control_ok()):
		return false
	if sword_state != SwordState.DRAWN or not is_on_floor():
		return false
	if _attack_progress() < float(R7_FORMS[active_form].cancel):
		return false
	var fr := _action_elapsed * _r7_hit_speed * 30.0
	for w in _r7_wins:
		if fr < float((w as PackedInt32Array)[1]) + 1.0:
			return false
	return _r7_root_settled()


## 停止追進／避線位移已結束（§9.3：REF11、REF04 有 stop_root）：剩餘路徑（前後＋側向；被目標／牆裁切的不算）≤ 3 cm
func _r7_root_settled() -> bool:
	if not bool(R7_FORMS[active_form].get("stop_root", false)) or _r7_root.size() < 2:
		return true
	var total := minf(_r7_path_len(_anim.get_animation(_active_attack_name)), _r7_root_cap)
	var done := Vector2(_r7_root_req, _r7_root_req_s).length()
	return total - done <= 0.03


func _can_dodge_cancel_attack() -> bool:
	if R7_FORMS.has(active_form) and action_state == ActionState.ATTACKING:
		return r7_form_cancel_ok()
	return super._can_dodge_cancel_attack()


func _r7_begin_guard() -> void:
	if R7_FORMS.has(active_form) and action_state == ActionState.ATTACKING:
		if not r7_form_cancel_ok():
			return
		_finish_attack()
	super.begin_guard()


## 前方錐角內的目標（鎖定優先，否則最近的敵人）：位移在接觸前停住，不擠進／穿過目標。沒有目標 → INF（只受碰撞限制）。
func _r7_root_stop_for_target() -> float:
	var t: Node3D = null
	if lock_target != null and is_instance_valid(lock_target) and lock_target.is_inside_tree():
		t = lock_target
	else:
		t = _nearest_enemy()
	if t == null:
		return INF
	var to := t.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 1e-6 or to.normalized().dot(_r7_root_dir) < r7_root_target_cone:
		return INF
	var tr: float = 0.35
	if t.get("target_radius") != null:
		tr = float(t.get("target_radius"))
	var me := 0.3
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null and cs.shape is CapsuleShape3D:
		me = (cs.shape as CapsuleShape3D).radius
	return maxf(0.0, to.length() - me - tr - r7_root_stop_margin)


## 接下一招（LMB／RMB 分支）：同 §9.3，進度 ≥ q 且所有命中窗已結束（不切斷有效斬擊）
func _in_form_cancel_window() -> bool:
	if R7_FORMS.has(active_form):
		if _r7_is_air():
			return r7_form_cancel_ok()
		if _attack_progress() < float(R7_FORMS[active_form].cancel):
			return false
		var fr := _action_elapsed * _r7_hit_speed * 30.0
		for w in _r7_wins:
			if fr < float((w as PackedInt32Array)[1]) + 1.0:
				return false
		return _r7_root_settled()
	return super._in_form_cancel_window()


func request_continuous_spin() -> void:
	if r7_forms_enabled:
		super.request_continuous_spin()


func _branch_form_for_stage(stage: int) -> int:
	var id := super._branch_form_for_stage(stage)
	return id if (r7_forms_enabled or R7_FORMS.has(id)) else 0


## R7K 拔刀／納刀安裝（僅當 r7k_draw_resource 與 r7k_sheathe_resource 皆指定時啟用；R7 場景維持原狀）
func _r7k_install_draw_sheathe(root: AnimationNodeBlendTree) -> void:
	if r7k_draw_resource == null or r7k_sheathe_resource == null or root == null:
		return
	_add_animation_resource("R7K_Draw", r7k_draw_resource)
	_add_animation_resource("R7K_Sheathe", r7k_sheathe_resource)
	if root.has_node("upper_sel_draw"):
		var nd := root.get_node("upper_sel_draw") as AnimationNodeAnimation
		nd.animation = "R7K_Draw"
		nd.play_mode = AnimationNodeAnimation.PLAY_MODE_FORWARD
		nd.use_custom_timeline = false
	if root.has_node("upper_sel_sheathe"):
		var ns := root.get_node("upper_sel_sheathe") as AnimationNodeAnimation
		ns.animation = "R7K_Sheathe"
		ns.play_mode = AnimationNodeAnimation.PLAY_MODE_FORWARD
		ns.use_custom_timeline = false
	if root.has_node("lower_sel"):
		var lsel := root.get_node("lower_sel") as AnimationNodeTransition
		for pr in [["draw", "R7K_Draw"], ["sheathe", "R7K_Sheathe"]]:
			var li := lsel.input_count
			lsel.input_count = li + 1
			lsel.set_input_name(li, pr[0])
			lsel.set_input_reset(li, true)
			root.add_node("lower_sel_" + pr[0], _anim_node(pr[1]))
			root.connect_node("lower_sel", li, "lower_sel_" + pr[0])
	_r7k_d_saya = r7k_draw_resource.get_meta("r5_saya_offset", PackedFloat32Array())
	_r7k_d_clip = r7k_draw_resource.get_meta("r5_clip_y", PackedFloat32Array())
	_r7k_d_vis = r7k_draw_resource.get_meta("r5_hand_visible", PackedByteArray())
	_r7k_d_lw = PackedFloat32Array(r7k_draw_resource.get_meta("r7_lhilt_w", []))
	_r7k_d_rw = _r7k_build_rw(_r7k_d_vis)
	_r7k_d_n = _r7k_d_clip.size()
	_r7k_s_saya = r7k_sheathe_resource.get_meta("r5_saya_offset", PackedFloat32Array())
	_r7k_s_clip = r7k_sheathe_resource.get_meta("r5_clip_y", PackedFloat32Array())
	_r7k_s_vis = r7k_sheathe_resource.get_meta("r5_hand_visible", PackedByteArray())
	_r7k_s_lw = PackedFloat32Array(r7k_sheathe_resource.get_meta("r7_lhilt_w", []))
	_r7k_s_rw = _r7k_build_rw(_r7k_s_vis)
	_r7k_s_n = _r7k_s_clip.size()
	_r7k_ds_ready = _r7k_d_n > 1 and _r7k_s_n > 1


func _r7k_build_rw(vis: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := vis.size()
	out.resize(n)
	var L := maxi(2, r62_lead_frames)
	for f in n:
		var w := 1.0 if vis[f] == 1 else 0.0
		if w < 1.0:
			for k in range(1, L + 3):
				if f + k < n and vis[f + k] == 1:
					w = maxf(w, clampf(1.0 - float(k - 2) / float(L), 0.0, 1.0))
					break
			for k in range(1, L + 2):
				if f - k >= 0 and vis[f - k] == 1:
					w = maxf(w, clampf(1.0 - float(k - 2) / float(L), 0.0, 1.0))
					break
		out[f] = w
	return out


func request_draw():
	if not _r7k_ds_ready:
		super.request_draw()
		return
	if sword_state != SwordState.SHEATHED or action_state == ActionState.DODGING or action_state == ActionState.ATTACKING:
		return
	sword_state = SwordState.DRAWING
	var spd := (r7k_draw_speed * 1.8) if _attack_after_draw else r7k_draw_speed
	_draw_real = r7k_draw_resource.length / spd
	_draw_elapsed = 0.0
	_draw_t = 0.0
	_r7k_ds_begin(true, spd)
	_upper_finish_fade = 0.16
	_fire_upper("draw", spd)


func _start_sheathe() -> void:
	if not _r7k_ds_ready:
		super._start_sheathe()
		return
	sword_state = SwordState.SHEATHING
	_draw_real = r7k_sheathe_resource.length / r7k_sheathe_speed
	_draw_elapsed = 0.0
	_draw_t = 1.0
	_r7k_ds_begin(false, r7k_sheathe_speed)
	_upper_finish_fade = 0.16
	_fire_upper("sheathe", r7k_sheathe_speed)


func _update_sword(delta: float) -> void:
	if not _r7k_ds_active:
		super._update_sword(delta)
		return
	if sword_state == SwordState.DRAWING:
		_draw_elapsed += delta
		var u := clampf(_draw_elapsed / _draw_real, 0.0, 1.0) if _draw_real > 0.0 else 1.0
		_draw_t = u
		var fr := u * float(_r7k_d_n - 1)
		_r7k_ds_apply(true, fr)
		if _attack_after_draw and fr >= 27.0:
			_r7k_ds_end(true)
			sword_state = SwordState.DRAWN
			_apply_sword_visibility()
			_execute_draw_followup()
			return
		if u >= 1.0:
			_r7k_ds_end(true)
			sword_state = SwordState.DRAWN
			_apply_sword_visibility()
			if _attack_after_draw:
				_execute_draw_followup()
	elif sword_state == SwordState.SHEATHING:
		_draw_elapsed += delta
		var u := clampf(_draw_elapsed / _draw_real, 0.0, 1.0) if _draw_real > 0.0 else 1.0
		_draw_t = 1.0 - u
		var fr := u * float(_r7k_s_n - 1)
		_r7k_ds_apply(false, fr)
		if u >= 1.0:
			_r7k_ds_end(false)
			sword_state = SwordState.SHEATHED
			_apply_sword_visibility()
	else:
		_r7k_ds_end(sword_state == SwordState.DRAWN)
		super._update_sword(delta)


func _apply_sword_visibility():
	if _r7k_ds_active and (sword_state == SwordState.DRAWING or sword_state == SwordState.SHEATHING):
		return
	if _r7k_ds_active:
		_r7k_ds_end(sword_state == SwordState.DRAWN)
	super._apply_sword_visibility()


func _r7k_ds_begin(is_draw: bool, spd: float) -> void:
	_r7k_ds_active = true
	_r7k_ds_is_draw = is_draw
	if _r5_sheath:
		_r5_sway_gain = float(_r5_sheath.get("sway_gain"))
		_r5_sheath.set("sway_gain", 0.0)
	for i in _r5_hand_mi.size():
		_r5_hand_mi[i].material_override = _r5_hand_sm[i]
	_r7k_ds_apply(is_draw, 0.0)
	if _r6_lower != null and _r6_still():
		_tree.set("parameters/lower_sel/transition_request", "draw" if is_draw else "sheathe")
		_tree.set("parameters/ts_lower/scale", spd)
		_r6_lower.fadeout_time = 0.16
		if not _tree.get("parameters/lower/internal_active"):
			_tree.set("parameters/lower/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_r7k_ds_lower_on = true


func _r7k_ds_apply(is_draw: bool, fr: float) -> void:
	var n := _r7k_d_n if is_draw else _r7k_s_n
	if n <= 0:
		return
	var saya := _r7k_d_saya if is_draw else _r7k_s_saya
	var clip_arr := _r7k_d_clip if is_draw else _r7k_s_clip
	var vis_arr := _r7k_d_vis if is_draw else _r7k_s_vis
	var lw_arr := _r7k_d_lw if is_draw else _r7k_s_lw
	var rw_arr := _r7k_d_rw if is_draw else _r7k_s_rw
	var f0 := clampi(int(floor(fr)), 0, n - 1)
	var f1 := mini(f0 + 1, n - 1)
	var u := clampf(fr - float(f0), 0.0, 1.0)
	var vis := vis_arr[f0] == 1
	if _sword_hand:
		_sword_hand.visible = vis
	if _sword_sheathed:
		_sword_sheathed.visible = not vis
	if _tree != null:
		_tree.set("parameters/grip/blend_amount", 0.0)
	var clip := lerpf(clip_arr[f0], clip_arr[f1], u) if vis else 99.0
	for sm in _r5_hand_sm:
		sm.set_shader_parameter("clip_y", clip)
	var T := _r7k_saya_xf(saya, f0).interpolate_with(_r7k_saya_xf(saya, f1), u)
	if _r5_sheath:
		_r5_sheath.set("_rest", T * _r5_sheath_rest)
		_r5_sheath.transform = T * _r5_sheath_rest
	if _sword_sheathed:
		_sword_sheathed.set_meta("sheath_rest", T * _r5_ss_rest)
		_sword_sheathed.transform = T * _r5_ss_rest
	_r7k_ds_rw = lerpf(rw_arr[f0], rw_arr[f1], u)
	_r7k_ds_lw = lerpf(lw_arr[f0], lw_arr[f1], u) if lw_arr.size() > f1 else 0.0
	if _r62_ik != null:
		_r62_w = _r7k_ds_rw
		_r62_ik.right_weight = _r7k_ds_rw
		_r62_ik.left_enabled = r62_left_grip_enabled and _r62_has_left and (_r7k_ds_lw > 0.001)
		_r62_ik._lw = _r7k_ds_lw


func _r7k_ds_end(drawn_now: bool) -> void:
	_r7k_ds_active = false
	if _r5_sheath:
		_r5_sheath.set("_rest", _r5_sheath_rest)
		_r5_sheath.set("sway_gain", _r5_sway_gain)
		_r5_sheath.transform = _r5_sheath_rest
	if _sword_sheathed:
		_sword_sheathed.set_meta("sheath_rest", _r5_ss_rest)
		_sword_sheathed.transform = _r5_ss_rest
	for mi in _r5_hand_mi:
		mi.material_override = null
	if _r62_ik != null:
		_r62_w = 1.0 if drawn_now else 0.0
		_r62_ik.right_weight = _r62_w
		_r62_ik.left_enabled = r62_left_grip_enabled and _r62_has_left and drawn_now
		_r62_ik._lw = 1.0 if drawn_now else 0.0


func _r7k_saya_xf(s: PackedFloat32Array, f: int) -> Transform3D:
	var o := f * 12
	if o + 11 >= s.size():
		return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3(s[o], s[o + 1], s[o + 2]), Vector3(s[o + 3], s[o + 4], s[o + 5]), Vector3(s[o + 6], s[o + 7], s[o + 8])),
		Vector3(s[o + 9], s[o + 10], s[o + 11]))


## 可在生成資源後明確重試；冪等安裝，不重建／重複註冊其餘八型。
func r7_install_air_forms() -> void:
	if _tree == null or _anim == null:
		return
	var root := _tree.tree_root as AnimationNodeBlendTree
	var sel := root.get_node("full_sel") as AnimationNodeTransition
	var resources := {10: r7_sun_05_resource, 4: r7_sun_06_resource, 5: r7_sun_09_resource, 7: r7_sun_10_resource}
	for id in R7_AIR_PATHS:
		var d: Dictionary = R7_FORMS[id]
		if root.has_node("full_sel_" + d.key):
			continue
		var a := resources[id] as Animation
		if a == null and FileAccess.file_exists(R7_AIR_PATHS[id]):
			a = load(R7_AIR_PATHS[id]) as Animation
		if not _r7_air_clip_valid(a):
			continue
		_add_animation_resource(d.anim, a)
		var i := sel.input_count
		sel.input_count = i + 1
		sel.set_input_name(i, d.key)
		sel.set_input_reset(i, true)
		root.add_node("full_sel_" + d.key, _anim_node(d.anim))
		root.connect_node("full_sel", i, "full_sel_" + d.key)


func _r7_air_clip_valid(a: Animation) -> bool:
	if a == null or not bool(a.get_meta("r7_air", false)) or r7_sun_speed <= 0.0:
		return false
	for key in ["r7_takeoff_frame", "r7_takeoff_v", "r7_contact_frame", "r7_air_start_frame", "r7_air_hold_frame", "r7_root_fwd", "r7_root_side", "r7_hit_windows"]:
		if not a.has_meta(key):
			return false
	var takeoff := float(a.get_meta("r7_takeoff_frame"))
	var contact := float(a.get_meta("r7_contact_frame"))
	var start := float(a.get_meta("r7_air_start_frame"))
	var hold := float(a.get_meta("r7_air_hold_frame"))
	if takeoff < 0.0 or contact <= takeoff or contact >= a.length * 30.0 or start < takeoff or hold < start or hold >= contact:
		return false
	if float(a.get_meta("r7_takeoff_v")) <= 0.0:
		return false
	for win in a.get_meta("r7_hit_windows"):
		if win.size() != 2 or float(win[0]) < hold or float(win[1]) < float(win[0]) or float(win[1]) + 1.0 > contact:
			return false
	return true


func _r7_is_air() -> bool:
	return _r7_form_on and r7_air_phase != R7AirPhase.NONE


## FREE 並不代表無硬直：父類的受擊／崩潰／死亡有獨立計時器。
func _r7_air_control_ok() -> bool:
	return not input_locked and not _guard_held and _hitstun_left <= 0.0 and _stagger_left <= 0.0 \
		and _deathblow_left <= 0.0 and _dead_left < 0.0 and _trick_left <= 0.0 and _climb_left <= 0.0 \
		and (posture == null or (not posture.is_dead() and not posture.is_broken()))


func _r7_air_begin(a: Animation, key: String) -> void:
	var fps := 30.0 * r7_sun_speed
	r7_air_phase = R7AirPhase.AIR_ACTION
	r7_air_exit = ""
	_r7_air_takeoff = float(a.get_meta("r7_takeoff_frame")) / fps
	_r7_air_takeoff_v = float(a.get_meta("r7_takeoff_v"))
	_r7_air_contact = float(a.get_meta("r7_contact_frame")) / fps
	_r7_air_hold = float(a.get_meta("r7_air_hold_frame")) / fps
	_r7_air_wait = 0.0
	_r7_air_hold_done = is_on_floor()
	_r7_air_launched = not is_on_floor()
	_r7_air_left_floor = not is_on_floor()
	_r7_air_step_v = Vector3.ZERO
	_jump_charge = -1.0
	_r7_air_node = (_tree.tree_root as AnimationNodeBlendTree).get_node("full_sel_" + key) as AnimationNodeAnimation
	_r7_air_node.use_custom_timeline = false
	if not is_on_floor():
		_r7_air_used = true
		_action_elapsed = float(a.get_meta("r7_air_start_frame")) / fps
		_r7_air_node.use_custom_timeline = true
		_r7_air_node.start_offset = _action_elapsed * r7_sun_speed
		_r7_air_node.timeline_length = a.length - _r7_air_node.start_offset
		_r7_air_node.stretch_time_scale = false
		_r7_air_node.loop_mode = Animation.LOOP_NONE
		# 只補一次足夠完成刀路的起速；此後每步仍是真重力，不寫角色高度。
		var remaining := _r7_air_contact - _action_elapsed
		var height := _r7_air_ground_height()
		if height >= 0.0 and _r7_air_fall_time(height) < remaining:
			velocity.y = maxf(velocity.y, (0.5 * gravity * remaining * remaining - height) / remaining)
		_r7_root_req = _r7_air_root_at(_r7_root, _action_elapsed)
		_r7_root_req_s = _r7_air_root_at(_r7_root_side, _action_elapsed)
	# 空中位移整段等比裁切，不在飛行中途突然停步（地面八型保留原截斷）。
	var total := _r7_path_len(a)
	if total > 1e-5 and _r7_root_cap < total:
		var ratio := _r7_root_cap / total
		for i in _r7_root.size():
			_r7_root[i] *= ratio
		for i in _r7_root_side.size():
			_r7_root_side[i] *= ratio
		_r7_root_req *= ratio
		_r7_root_req_s *= ratio
		_r7_root_cap = INF
	if _r62_ik != null:
		_r7_air_ik_saved = {"right": _r62_ik.right_weight, "left": _r62_ik.left_enabled, "lw": _r62_ik._lw,
			"sock": _sword_hand.transform if _sword_hand != null else Transform3D.IDENTITY}
		# authored clip 的刀路是舊插槽；關 IK 同時還原它，否則刀相對手仍偏一截。
		if _sword_hand != null:
			_sword_hand.transform = _r62_ik.sock_old
	_r7_air_disable_ik()


func _r7_air_root_at(values: PackedFloat32Array, t: float) -> float:
	if values.is_empty():
		return 0.0
	var f := clampf(t * r7_sun_speed * 30.0, 0.0, float(values.size() - 1))
	var i := int(floor(f))
	return lerpf(values[i], values[mini(i + 1, values.size() - 1)], f - float(i))


func _r7_air_disable_ik() -> void:
	if _r62_ik != null:
		_r62_w = 0.0
		_r62_ik.right_weight = 0.0
		_r62_ik.left_enabled = false
		_r62_ik._lw = 0.0


func _r7_air_ground_height() -> float:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.02, global_position + Vector3.DOWN * 4096.0, collision_mask)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return maxf(0.0, global_position.y - (hit.position as Vector3).y) if not hit.is_empty() else -1.0


func _r7_air_fall_time(height: float) -> float:
	return (velocity.y + sqrt(maxf(0.0, velocity.y * velocity.y + 2.0 * gravity * height))) / maxf(gravity, 0.001)


## 在父類清掉 grounded velocity.y 之前排純物理起跳，暫時的 jump_velocity 在同一步後還原。
func _r7_air_prepare(delta: float) -> void:
	_r7_air_step_v = Vector3.ZERO
	if not _r7_air_launched and not is_on_floor():
		_r7_air_abort("lost_floor_before_takeoff")
		return
	if not _r7_air_launched and _action_elapsed + delta >= _r7_air_takeoff:
		_r7_air_launched = true
		_r7_air_used = true
		_jump_charge = 0.0
		jump_velocity = _r7_air_takeoff_v
	var scale := r7_sun_speed
	if r7_air_phase == R7AirPhase.AIR_HOLD or r7_air_phase == R7AirPhase.WAIT_CONTACT:
		scale = 0.0
	elif r7_air_phase == R7AirPhase.AIR_ACTION:
		var stop := _r7_air_contact
		if not _r7_air_hold_done:
			stop = minf(stop, _r7_air_hold)
		# 最後一步精確停到 barrier，動畫不能先跨入落地段。
		scale *= clampf((stop - _action_elapsed) / maxf(delta, 1e-5), 0.0, 1.0)
	_tree.set("parameters/ts_full/scale", scale)


func _update_attack(delta: float, input_dir: Vector3) -> void:
	if _r7_is_air():
		# P3.1：落地恢復＝視覺；控制在取消點（已著地、命中窗結束、承重段過）後即可用移動切出，由 OneShot fade 混回移動。
		# 十三型循環中改由 _r7c_tick 依優先順序（閃避 → 移動 → 續招）處理，這裡只管單招。
		if not _r7c_running and r7_form_cancel_ok() and r7_air_phase == R7AirPhase.LAND_RECOVER and input_dir.length() > 0.3:
			r7_air_exit = "move_cancel"
			_finish_attack()
			return
		_r7_air_advance(delta)
		return
	super._update_attack(delta, input_dir)


func _apply_air_control(input_dir: Vector3, cur_speed: float, delta: float) -> void:
	if _r7_is_air():
		velocity.x = _r7_air_step_v.x
		velocity.z = _r7_air_step_v.z
		return
	super._apply_air_control(input_dir, cur_speed, delta)


func _r7_air_advance(delta: float) -> void:
	if not is_on_floor():
		_r7_air_left_floor = true
	if _r7_air_left_floor and is_on_ceiling():
		_r7_air_abort("ceiling")
		return
	if _r7_air_left_floor and is_on_floor() and r7_air_phase != R7AirPhase.LAND_RECOVER:
		if _action_elapsed + delta < _r7_air_contact - 0.025:
			_r7_air_abort("early_contact")
			return
		_action_elapsed = _r7_air_contact
		r7_air_phase = R7AirPhase.LAND_RECOVER
		_was_airborne = false
		_air_t = 0.0
		_air_peak_y = -INF
		_double_jump_used = false
		_r7_air_used = false
		_r7_air_wait = 0.0
		_tree.set("parameters/ts_full/scale", r7_sun_speed)
		_r7_air_close_damage()
		return
	if r7_air_phase == R7AirPhase.WAIT_CONTACT or r7_air_phase == R7AirPhase.AIR_HOLD:
		_r7_air_wait += delta
		_r7_air_close_damage()
		if _r7_air_wait >= 2.0:
			_r7_air_abort("timeout")
		elif r7_air_phase == R7AirPhase.AIR_HOLD:
			var height := _r7_air_ground_height()
			if height < 0.0 or _r7_air_fall_time(height) <= _r7_air_contact - _action_elapsed + delta:
				r7_air_phase = R7AirPhase.AIR_ACTION
				_r7_air_hold_done = true
				_r7_air_wait = 0.0
				_tree.set("parameters/ts_full/scale", r7_sun_speed)
		return
	var stop := _r7_air_contact if r7_air_phase != R7AirPhase.LAND_RECOVER else _action_real
	if not _r7_air_hold_done:
		stop = minf(stop, _r7_air_hold)
	_action_elapsed = minf(_action_elapsed + delta, stop)
	if not _r7_air_hold_done and _action_elapsed >= _r7_air_hold:
		var height := _r7_air_ground_height()
		if height >= 0.0 and _r7_air_fall_time(height) > _r7_air_contact - _action_elapsed + delta:
			r7_air_phase = R7AirPhase.AIR_HOLD
			_tree.set("parameters/ts_full/scale", 0.0)
			_r7_air_close_damage()
		else:
			_r7_air_hold_done = true
	elif r7_air_phase == R7AirPhase.AIR_ACTION and _action_elapsed >= _r7_air_contact:
		r7_air_phase = R7AirPhase.WAIT_CONTACT
		_tree.set("parameters/ts_full/scale", 0.0)
		_r7_air_close_damage()
	elif r7_air_phase == R7AirPhase.LAND_RECOVER and _action_elapsed >= _action_real:
		r7_air_exit = "complete"
		_finish_attack()


func _r7_air_close_damage() -> void:
	r7_hit_group = 0
	_r7_prev_in_win = false
	_r7_trail_on = false
	if _hitbox != null:
		_hitbox.monitoring = false
	if _sword_trail != null:
		_sword_trail.stop_trail()


func _r7_air_abort(reason: String) -> void:
	r7_air_exit = reason
	var landed := is_on_floor()
	_finish_attack()
	if landed:
		_r7_air_used = false
		_was_airborne = false
		_land_lock = land_lock_time
		_playback().travel("Land")
	else:
		_was_airborne = true
		_playback().travel("Fall")


## 同步清理，不能等下一個 physics tick（take_hit 會在同格播放 hit／stagger／dead）。
## R7 P4 十三型：只有 _r7c_try_handoff()／自然播完（且仍持續、狀態合法）才續下一型；其他任何呼叫（受擊、死亡、閃避、
## 架刀、移動取消、空中 abort、跟招）一律先清 R7 循環狀態再走父類清理。父類 _form13_queue 永遠保持空 → 父類不會自行續招。
func _finish_attack() -> void:
	if _r7_rmb_left > 0.0:
		_r7_rmb_log_ev({"ev": "rmb_cleared", "why": (_r7c_hint if _r7c_hint != "" else "finish")})
		_r7_rmb_left = 0.0
	var cont := false
	var reason := ""
	var prev_form := active_form
	var fire_dodge := false
	if _r7c_running and action_state == ActionState.ATTACKING:
		var natural := _r7c_handoff or ((_attack_progress() >= 1.0 or (_r7_is_air() and r7_air_exit == "complete")) and _r7c_hint == "")
		if _r7c_hint == "" and _r7_is_air() and r7_air_exit not in ["", "complete"]:
			_r7c_hint = r7_air_exit
		if posture != null and posture.is_dead():
			_r7c_hint = "death"
		if natural and _r7c_hint == "" and not _r7c_stop_req and _r7c_dodge_left > 0.0:
			_r7c_hint = "dodge"   # 自然交接同一格有待處理的合法閃避 → 閃避勝出，不啟動下一型
			fire_dodge = true
		elif natural and _r7c_hint == "" and not _r7c_stop_req and _read_input_dir().length() > 0.3:
			_r7c_hint = "move"
		if natural and _r7c_hint == "" and not _r7c_stop_req:
			cont = true
		else:
			reason = _r7c_hint if _r7c_hint != "" else ("stop" if natural and _r7c_stop_req else "interrupted")
	_r7c_handoff = false
	_r7c_hint = ""
	_form13_queue.clear()
	if _r7c_running and not cont and _full_node != null and R7_FORMS.has(prev_form):
		_full_node.fadeout_time = float(R7_FORMS[prev_form].fade)   # 收勢淡出恢復該型原值（循環中為 0）
	if _r7_is_air():
		_r7_form_end()
	super._finish_attack()
	if not _r7c_running:
		return
	if cont:
		_r7c_advance(prev_form)
	else:
		_r7c_end(reason, prev_form)
		if fire_dodge:
			_r7c_roll()


# ---------------------------------------------------------------------------
# R7 P4 日之呼吸十三型（REF13 十二圓環）：規格 V1.0 REF13 順序 REF01→…→REF12→REF01。
# sun_breathing.gd 的 FORM13_SEQUENCE [1..12] 在此解讀為「第 n 型 = REFnn」，經 R7_FORMS.ref 轉成 legacy ID
# （與 legacy ID 的 [1..12] 播放順序不同；共享檔不改）。實際 ID 序列：1,2,3,11,10,4,8,6,5,7,9,12。
# 接點（R7C_HANDOFF，authored 格）由 tools/yoriichi_r7/probe_form13_meta.gd 逐格量測選出：
#   ≥ 最後命中窗結束＋2 格；空中型 ≥ 觸地＋12 格（吸震）；無命中的 REF04 ≥ 原取消點且需位移走完；
#   取「與下一型首格姿態差 ≤ 0.15 m」或「已收到本型定姿 ≤ 0.05 m」的最早一格。
# 跨型以 full_sel transition xfade（R7C_XFADE 秒）交接，不重啟 OneShot（不回 locomotion）；循環中 OneShot fadeout = 0。
# ---------------------------------------------------------------------------
const R7C_HANDOFF := {1: 41, 2: 46, 3: 46, 11: 28, 10: 95, 4: 89, 8: 41, 6: 43, 5: 116, 7: 81, 9: 83, 12: 63}
## R7 P4 接縫修補（循環專用；單招不經過）：6 對「K1 低刀尖構 ↔ K2/K3 喉高刀尖構」的相鄰接縫。
## fa＝上一型在隨揮仍在走、尚未回中段構的接出格（≥ 最後命中窗結束＋2；空中型 ≥ 觸地＋12）；
## map＝下一型（主版／近距版）→ 派生 clip（tools/yoriichi_r7/build_r7_form13_seams.gd：上半身旋轉偏移，第 0 格＝上一型 fa 姿勢，
## N 格內 smoothstep 衰減到 0，N 一律早於下一型第一個命中窗／起跳蹲／無敵窗；時長、命中窗、root、空中 marker 與原 clip 相同）。
## 原十二型 .res 不動；派生資源缺件 → 該接縫退回 R7C_HANDOFF＋原 clip（舊行為）。
const R7C_SEAM_DIR := "res://characters/yoriichi/v24/anims_r7/form13/"
const R7C_SEAMS := {
	1: {"fa": 24, "next": 2, "map": {"R7_Sun02_Hekira": ["R7C_Sun02_Hekira_from_Sun01", "r7c_s0102", "r_7c_sun_02_hekira_from_sun_01.res"]}},
	2: {"fa": 37, "next": 3, "map": {"R7_Sun03_Retsujitsu": ["R7C_Sun03_Retsujitsu_from_Sun02", "r7c_s0203", "r_7c_sun_03_retsujitsu_from_sun_02.res"]}},
	# REF03→REF04 不修：REF03 隨揮停在 f24–32（刀尖距 REF04 首格 1.44 m），f33–40 本身就是回構動作；
	# 在 f39 接出實測於交接格出現刀尖折返（反轉 0→2），比原本更差；REF04 是無命中的避線步，沒有可接續的蓄勢段 → 維持原 f46＋原 clip。
	4: {"fa": 78, "next": 8, "map": {
		"R7_Sun07_Youkatotsu": ["R7C_Sun07_Youkatotsu_from_Sun06", "r7c_s0607", "r_7c_sun_07_youkatotsu_from_sun_06.res"],
		"R7_Sun07_YoukatotsuNear": ["R7C_Sun07_YoukatotsuNear_from_Sun06", "r7c_s0607n", "r_7c_sun_07_youkatotsu_near_from_sun_06.res"]}},
	6: {"fa": 35, "next": 5, "map": {"R7_Sun09_ShayouTenshinMX": ["R7C_Sun09_ShayouTenshinMX_from_Sun08", "r7c_s0809", "r_7c_sun_09_shayou_tenshin_mx_from_sun_08.res"]}},
	7: {"fa": 74, "next": 9, "map": {
		"R7_Sun11_NichirinDragon": ["R7C_Sun11_NichirinDragon_from_Sun10", "r7c_s1011", "r_7c_sun_11_nichirin_dragon_from_sun_10.res"],
		"R7_Sun11_NichirinDragonNear": ["R7C_Sun11_NichirinDragonNear_from_Sun10", "r7c_s1011n", "r_7c_sun_11_nichirin_dragon_near_from_sun_10.res"]}},
}
## R7 P5 D：局部回退到原接法的接縫（上一型 legacy ID）。10→11（id 7）派生接法 runtime 刀尖 vmax 28.9→33.0 m/s、折返 1→2，
## 同鏡頭原速比較也未見改善 → 回退原 R7C_HANDOFF＋原 clip；派生資源保留不刪。
const R7C_SEAM_ROLLBACK := [7]
## false = 關閉接縫修補（修前對照用；環境變數 R7C_SEAM_FIX=0 亦可）
@export var r7c_seam_fix := true
var _r7c_seam_prev := 0
var _r7c_seam_ok := {}
## 測試記錄用：本型實際用的派生 clip（"" = 原 clip；"fallback:<anim>" = 有接縫但此版本無派生）
var r7c_seam_used := ""


func _r7c_install_seams() -> void:
	if OS.get_environment("R7C_SEAM_FIX") == "0":
		r7c_seam_fix = false
	if _tree == null or _anim == null:
		return
	var root := _tree.tree_root as AnimationNodeBlendTree
	var sel := root.get_node("full_sel") as AnimationNodeTransition
	for pid in R7C_SEAMS:
		var ok := true
		var m: Dictionary = R7C_SEAMS[pid].map
		for src in m:
			var ent: Array = m[src]
			var path: String = R7C_SEAM_DIR + String(ent[2])
			if root.has_node("full_sel_" + String(ent[1])):
				continue
			var a: Animation = load(path) as Animation if ResourceLoader.exists(path) else null
			if a == null or not _anim.has_animation(src):
				ok = false
				continue
			_add_animation_resource(String(ent[0]), a)
			var i := sel.input_count
			sel.input_count = i + 1
			sel.set_input_name(i, String(ent[1]))
			sel.set_input_reset(i, true)
			root.add_node("full_sel_" + String(ent[1]), _anim_node(String(ent[0])))
			root.connect_node("full_sel", i, "full_sel_" + String(ent[1]))
		_r7c_seam_ok[pid] = ok and not R7C_SEAM_ROLLBACK.has(pid)


## 本型的循環接出格：接縫修補啟用、下一型確為表內的 next、資源齊 → 用 fa；否則原 R7C_HANDOFF
func _r7c_handoff_frame(id: int) -> float:
	if r7c_seam_fix and R7C_SEAMS.has(id) and bool(_r7c_seam_ok.get(id, false)) and r7c_seq.size() > 0:
		var nxt := r7c_seq[(r7c_idx + 1) % r7c_seq.size()]
		if nxt == int(R7C_SEAMS[id].next):
			return float(R7C_SEAMS[id].fa)
	return float(R7C_HANDOFF.get(id, 1 << 20))


const R7C_XFADE := {1: 0.16, 2: 0.16, 3: 0.16, 11: 0.10, 10: 0.10, 4: 0.16, 8: 0.10, 6: 0.16, 5: 0.10, 7: 0.16, 9: 0.10, 12: 0.10}
## true = 按住 form13 持續循環、鬆開 → 本型播完收勢；false = 不看按住狀態，只跑到停止要求（測試／展示用）
@export var r7c_hold_to_continue := true
## 每圈（含第一圈）的資源：未解鎖 → 需 sun_breath_gauge ≥ form13_gauge_cost，起手清零；
## 已解鎖 → 每圈扣固定成本 form13_gauge_cost（不足則清零）。
## 注意：這與父類 start_form13 不同（父類解鎖時清零）——屬 R7 候選差異，待決，非「相同政策」。
signal r7c_event(info: Dictionary)
var r7c_seq: Array[int] = []
var r7c_idx := -1
var r7c_lap := 0
var r7c_exit := ""
var r7c_log: Array = []
var _r7c_running := false
var _r7c_handoff := false
var _r7c_switch := false
var _r7c_hint := ""
var _r7c_stop_req := false
var _r7c_saved_xfade := -1.0
## 循環專用閃避緩衝（父類 request_dodge 不可取消時直接丟棄、沒有緩衝欄位可重用）：
## 不合法時記一次請求，最多保留 r7c_dodge_buffer_time 秒；到合法取消點即翻滾，逾期清除（之後不會自動翻滾）。
@export var r7c_dodge_buffer_time := 0.40
var _r7c_dodge_left := 0.0
var _r7c_dodge_dir := Vector3.ZERO
## 本型是否由循環接點進入（第一型除外）、及其「首個承諾格」（authored 格，見 _r7c_commit_frame）
var _r7c_entry_seam := false
var _r7c_commit_af := -1.0


func r7c_running() -> bool:
	return _r7c_running


## FORM13_SEQUENCE 的第 n 項 → REFnn → R7_FORMS 的 legacy ID；找不到 → 0（缺件）
func r7c_resolve_sequence() -> Array[int]:
	var out: Array[int] = []
	for n in SunBreathing.FORM13_SEQUENCE:
		var want := "REF%02d" % int(n)
		var hit := 0
		for id in R7_FORMS:
			if String(R7_FORMS[id].get("ref", "")) == want:
				hit = int(id)
				break
		out.append(hit)
	return out


func r7c_block_reason() -> String:
	if _r7c_running:
		return "running"
	if sword_state != SwordState.DRAWN:
		return "sword"
	if action_state != ActionState.FREE or not _r7_air_control_ok():
		return "busy"
	if not is_on_floor():
		return "airborne"
	var seq := r7c_resolve_sequence()
	for i in seq.size():
		var id := seq[i]
		if id == 0 or _anim == null or not _anim.has_animation(R7_FORMS[id].anim) or not R7C_HANDOFF.has(id):
			return "missing:REF%02d" % int(SunBreathing.FORM13_SEQUENCE[i])
		if bool(R7_FORMS[id].get("air", false)) and not _r7_air_clip_valid(_anim.get_animation(R7_FORMS[id].anim)):
			return "missing:REF%02d" % int(SunBreathing.FORM13_SEQUENCE[i])
	for id in seq:
		if form_cooldown_left(id) > 0.0:
			return "cooldown:%s" % R7_FORMS[id].ref
	if not form13_unlocked and sun_breath_gauge < form13_gauge_cost:
		return "breath"
	return ""


## 父類同名入口（form13 action → _unhandled_input → start_form13）。缺件／冷卻／資源不足 → 拒絕，不扣資源、不跳型。
func start_form13() -> bool:
	var why := r7c_block_reason()
	if why != "":
		_r7c_log({"ev": "refuse", "reason": why})
		return false
	r7c_seq = r7c_resolve_sequence()
	_form13_queue.clear()
	_form13_running = false
	r7c_lap = 1
	r7c_idx = 0
	r7c_exit = ""
	_r7c_stop_req = false
	_r7c_hint = ""
	_r7c_dodge_left = 0.0
	_r7c_entry_seam = false
	_r7c_pay_lap()
	if not _r7c_exec(r7c_seq[0], -1):
		_r7c_log({"ev": "refuse", "reason": "exec_fail:%s" % R7_FORMS[r7c_seq[0]].ref})
		return false
	_r7c_running = true
	form13_started.emit()
	return true


## 鬆開／停止：不中斷目前這一型，播完（含收勢）結束，不再接下一型。等待接地時同樣只記要求。
func r7c_request_stop() -> void:
	if _r7c_running and not _r7c_stop_req:
		_r7c_stop_req = true
		_r7c_log({"ev": "stop_request"})


func _r7c_pay_lap() -> void:
	if not form13_unlocked:
		sun_breath_gauge = 0.0
		breath_changed.emit(sun_breath_gauge, sun_breath_max)
	else:
		sun_breath_gauge = 0.0 if sun_breath_gauge < form13_gauge_cost else sun_breath_gauge - form13_gauge_cost
		breath_changed.emit(sun_breath_gauge, sun_breath_max)


func _r7c_exec(id: int, prev: int) -> bool:
	if _tree == null:
		return false
	var fsel := (_tree.tree_root as AnimationNodeBlendTree).get_node("full_sel") as AnimationNodeTransition
	if prev > 0:
		if _r7c_saved_xfade < 0.0:
			_r7c_saved_xfade = fsel.xfade_time
		fsel.xfade_time = float(R7C_XFADE.get(prev, 0.12))
		_r7c_switch = true
	r7c_seam_used = ""
	if prev > 0 and r7c_seam_fix and R7C_SEAMS.has(prev) and int(R7C_SEAMS[prev].next) == id and bool(_r7c_seam_ok.get(prev, false)):
		_r7c_seam_prev = prev
	var ok := execute_form(id, true)
	_r7c_seam_prev = 0
	_r7c_entry_seam = ok and prev > 0
	_r7c_commit_af = _r7c_commit_frame() if ok else -1.0
	_r7c_switch = false
	if ok and _full_node != null:
		_full_node.fadeout_time = 0.0   # 循環中不讓 OneShot 在 clip 尾自行淡回 locomotion；停止／中斷時 _finish_attack 還原
	if ok:
		_r7c_log({"ev": "start", "id": id, "ref": R7_FORMS[id].ref, "anim": _active_attack_name, "variant": r7_form_variant, "seam": r7c_seam_used,
			"xfade": (float(R7C_XFADE.get(prev, 0.0)) if prev > 0 else 0.0), "commit_af": _r7c_commit_af,
			"handoff_af": _r7c_handoff_frame(id)})
	return ok


func _r7c_advance(prev: int) -> void:
	r7c_idx += 1
	if r7c_idx >= r7c_seq.size():
		if not form13_unlocked and sun_breath_gauge < form13_gauge_cost:
			_r7c_end("breath", prev)
			return
		r7c_idx = 0
		r7c_lap += 1
		_r7c_pay_lap()
	var id := r7c_seq[r7c_idx]
	if not _r7c_exec(id, prev):
		_r7c_end("exec_fail:%s" % R7_FORMS[id].ref, prev)


func _r7c_end(reason: String, prev: int) -> void:
	if not _r7c_running:
		return
	_r7c_running = false
	_r7c_stop_req = false
	_r7c_switch = false
	_r7c_handoff = false
	r7c_exit = reason
	_r7c_dodge_left = 0.0
	_r7c_entry_seam = false
	_form13_queue.clear()
	_form13_running = false
	if _tree != null and _r7c_saved_xfade >= 0.0:
		((_tree.tree_root as AnimationNodeBlendTree).get_node("full_sel") as AnimationNodeTransition).xfade_time = _r7c_saved_xfade
	_r7c_saved_xfade = -1.0
	_r7c_log({"ev": "exit", "reason": reason, "last": (R7_FORMS[prev].ref if R7_FORMS.has(prev) else "")})
	form13_finished.emit()


func _r7c_log(info: Dictionary) -> void:
	info["lap"] = r7c_lap
	info["idx"] = r7c_idx
	info["t_ms"] = Time.get_ticks_msec()
	r7c_log.append(info)
	r7c_event.emit(info)


## 交接：跨型時只換 full_sel 段落（xfade），撤銷同格 _finish_attack 發出的 FADE_OUT，不重 FIRE OneShot。
func _fire_full(input_name: String, time_scale: float) -> void:
	if _r7c_switch and _tree != null and _tree.get("parameters/full/internal_active"):
		_tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_NONE)
		_tree.set("parameters/full_sel/transition_request", input_name)
		_tree.set("parameters/ts_full/scale", time_scale)
		return
	super._fire_full(input_name, time_scale)


## 每步開頭：持續鍵、狀態守門（死亡／非法狀態先清循環）、閃避緩衝倒數（逾期清除並記錄）。
func _r7c_watch(delta: float = 0.0) -> void:
	if not _r7c_running:
		_r7c_dodge_left = 0.0
		return
	if r7c_hold_to_continue and not Input.is_action_pressed("form13"):
		r7c_request_stop()
	if action_state != ActionState.ATTACKING or not R7_FORMS.has(active_form):
		_r7c_end("cleared", active_form)
		return
	if _r7c_dodge_left > 0.0:
		_r7c_dodge_left -= delta
		if _r7c_dodge_left <= 1e-6:
			_r7c_dodge_left = 0.0
			_r7c_log({"ev": "dodge_expired", "ref": R7_FORMS[active_form].ref, "af": snappedf(_r7c_af(), 0.1)})


func _r7c_af() -> float:
	return _action_elapsed * r7_sun_speed * 30.0


## 本型的首個承諾格（authored 格）：第一個命中窗開始、空中型起跳格、無敵窗開始，取最早；
## 都沒有（REF04 有無敵窗所以不會落到這裡）→ 根位移超過 3 cm 的格。循環接點進入後、此格之前＝合法取消區。
func _r7c_commit_frame() -> float:
	var c := INF
	var hk := _r7_hit_speed / maxf(r7_sun_speed, 1e-5)   # 命中窗格 → action clock 格
	for w in _r7_wins:
		c = minf(c, float((w as PackedInt32Array)[0]) / maxf(hk, 1e-5))
	var a: Animation = _anim.get_animation(_active_attack_name) if _anim != null and _anim.has_animation(_active_attack_name) else null
	if a != null and _r7_is_air() and a.has_meta("r7_takeoff_frame"):
		c = minf(c, float(a.get_meta("r7_takeoff_frame")))
	if a != null and R7_FORMS[active_form].has("evade"):
		var ev: Array = _r7_clip_win("r7_evade", R7_FORMS[active_form].evade)
		c = minf(c, float(ev[0]) * a.length * 30.0)
	if c == INF:
		for k in _r7_root.size():
			var sd := _r7_root_side[k] if _r7_root_side.size() > k else 0.0
			if Vector2(_r7_root[k], sd).length() > 0.03:
				c = float(k)
				break
	return c if c != INF else 0.0


## 循環專用合法取消點（只在 _r7c_running 時使用；單招規則 r7_form_cancel_ok 不變）：
##   a) 本型原本的後段取消（r7_form_cancel_ok）；
##   b) 本型接出格之後（＝自動交接的同一組條件：命中窗結束、空中型已觸地且吸震完、著地、刀在手、位移走完）；
##   c) 由接點進入的下一型、在其首個承諾格（命中窗／起跳／無敵）之前，且仍在地面、尚未起跳。
func _r7c_safe_point() -> bool:
	if not _r7c_running or action_state != ActionState.ATTACKING or not R7_FORMS.has(active_form):
		return false
	if not _r7_air_control_ok() or sword_state != SwordState.DRAWN or not is_on_floor():
		return false
	if r7_form_cancel_ok():
		return true
	var fr := _r7c_af()
	if _r7_is_air():
		if r7_air_phase == R7AirPhase.LAND_RECOVER:
			pass
		elif r7_air_phase == R7AirPhase.AIR_ACTION and not _r7_air_launched and _r7c_entry_seam and fr < _r7c_commit_af:
			return true
		else:
			return false
	elif _r7c_entry_seam and fr < _r7c_commit_af:
		return true
	if fr < _r7c_handoff_frame(active_form):
		return false
	var hf := _action_elapsed * _r7_hit_speed * 30.0
	for w in _r7_wins:
		if hf < float((w as PackedInt32Array)[1]) + 1.0:
			return false
	return _r7_root_settled()


## 在 R7 型的 tick 內，同一 tick 的優先順序：
##   非法狀態（受擊／死亡已在 take_hit 同步清理）→ 待處理的合法閃避 → 持續移動取消 → 停止要求 → 自動續招。
## 空中（不在合法點）收到閃避／移動 → 只記停止意圖，不強制著地、不地面翻滾；落地後到合法點再處理。
func _r7c_tick(input_dir: Vector3) -> void:
	if not _r7c_running or action_state != ActionState.ATTACKING or not R7_FORMS.has(active_form):
		return
	if not _r7_air_control_ok():
		return
	var moving := input_dir.length() > 0.3
	var safe := _r7c_safe_point()
	if safe and _r7c_dodge_left > 0.0:
		_r7c_fire_dodge()
		return
	if safe and moving:
		_r7c_hint = "move"
		_r7c_log({"ev": "move_exit", "ref": R7_FORMS[active_form].ref, "af": snappedf(_r7c_af(), 0.1)})
		_finish_attack()
		return
	if not safe and (moving or _r7c_dodge_left > 0.0) and (not is_on_floor() or (_r7_is_air() and r7_air_phase != R7AirPhase.LAND_RECOVER)):
		r7c_request_stop()   # 等待接地：停止意圖，重力／中斷照常
	if _r7c_stop_req:
		return   # 停止要求：本型照原樣播完（收勢），由自然結束收尾
	var fr := _r7c_af()
	if fr < _r7c_handoff_frame(active_form):
		return
	if sword_state != SwordState.DRAWN or not is_on_floor():
		return
	if _r7_is_air() and r7_air_phase != R7AirPhase.LAND_RECOVER:
		return
	for w in _r7_wins:
		if fr < float((w as PackedInt32Array)[1]) + 1.0:
			return
	if not _r7_root_settled():
		return
	_r7c_handoff = true
	_finish_attack()


func _r7c_fire_dodge() -> void:
	_r7c_log({"ev": "dodge_exit", "ref": R7_FORMS[active_form].ref, "af": snappedf(_r7c_af(), 0.1),
		"buffer_left": snappedf(_r7c_dodge_left, 0.001)})
	pending_sheathe = false
	_r7c_hint = "dodge"
	_finish_attack()   # 清循環（reason dodge）→ FREE
	_r7c_roll()


## 循環已清理（FREE）後執行翻滾：走父類同一個 request_dodge（翻滾、無敵、塵土都不變）。
func _r7c_roll() -> void:
	var d := _r7c_dodge_dir
	_r7c_dodge_left = 0.0
	_r7c_dodge_dir = Vector3.ZERO
	super.request_dodge(d)


func take_hit(hit_data: Dictionary) -> Dictionary:
	if _r7c_running:
		_r7c_hint = "hit"
	var r: Dictionary = super.take_hit(hit_data)
	if _r7c_running:
		_r7c_hint = ""   # 未打斷（閃避無敵／格擋等）→ 循環照常
	return r


## 十三型循環中：合法取消點 → 立即翻滾；否則緩衝一次（r7c_dodge_buffer_time，不因重按延長以外的方式續命），
## 由 _r7c_tick 在下一個合法點消費；逾期清除。循環外完全走父類（單招閃避取消規則不變）。
func request_dodge(direction_override: Vector3 = Vector3.ZERO) -> void:
	if _r7c_running and action_state == ActionState.ATTACKING and R7_FORMS.has(active_form):
		if not _r7_air_control_ok() or sword_state == SwordState.DRAWING or sword_state == SwordState.SHEATHING:
			return
		_r7c_dodge_dir = Vector3(direction_override.x, 0.0, direction_override.z)
		if _r7c_safe_point():
			_r7c_dodge_left = r7c_dodge_buffer_time
			_r7c_fire_dodge()
			return
		_r7c_dodge_left = r7c_dodge_buffer_time
		_r7c_log({"ev": "dodge_buffered", "ref": R7_FORMS[active_form].ref, "af": snappedf(_r7c_af(), 0.1),
			"expires_s": r7c_dodge_buffer_time, "air": not is_on_floor()})
		if not is_on_floor() or (_r7_is_air() and r7_air_phase != R7AirPhase.LAND_RECOVER):
			r7c_request_stop()
		return
	super.request_dodge(direction_override)


func begin_guard() -> void:
	if _r7c_running:
		_r7c_hint = "guard"
	_r7_begin_guard()
	if _r7c_running:
		_r7c_hint = ""


func _r7_air_end() -> void:
	if r7_air_phase == R7AirPhase.NONE:
		return
	_r7_air_close_damage()
	_r7_wins.clear()
	_r7_hit = PackedInt32Array([-1, -1])
	_r7_win_idx = -1
	_r7_followup_left = 0.0
	_jump_charge = -1.0
	_form_followup = ""
	if _tree != null:
		_tree.set("parameters/ts_full/scale", 1.0)
	# 退出當格仍有 OneShot fade：不可把空中起手的 custom timeline 改回整段，否則淡出時倒跳重播空中刀。
	# 下次 _r7_air_begin 在 FIRE 之前重設此節點；其他型不使用它。
	_r7_air_node = null
	if _r62_ik != null and not _r7_air_ik_saved.is_empty():
		_r62_w = float(_r7_air_ik_saved.right)
		_r62_ik.right_weight = _r62_w
		_r62_ik.left_enabled = bool(_r7_air_ik_saved.left)
		_r62_ik._lw = float(_r7_air_ik_saved.lw)
		if _sword_hand != null:
			_sword_hand.transform = _r7_air_ik_saved.sock
	_r7_air_ik_saved.clear()
	r7_air_phase = R7AirPhase.NONE
	_r7_air_launched = false
	_r7_air_left_floor = false
	_r7_air_wait = 0.0
	_r7_air_step_v = Vector3.ZERO


## 本批 REF06／10 和 REF05／09 一律等待真落地，不啟用 AIR_EXIT。
func request_jump() -> void:
	if _r7_is_air():
		return
	super.request_jump()


func _apply_hit_reaction(result: String, hit_dir: Vector3) -> void:
	if _r7_is_air() and result == "hit":
		r7_air_exit = "hit"
		_finish_attack()
	super._apply_hit_reaction(result, hit_dir)


func request_primary_attack() -> void:
	if _r7_is_air():
		_r7_air_buffer_followup("light")
		return
	super.request_primary_attack()


func request_heavy_cut() -> void:
	if _r7_is_air():
		_r7_air_buffer_followup("heavy")
		return
	if action_state == ActionState.ATTACKING and active_form == 1 and _r7_rmb_ready():
		_r7_rmb_request()
		return
	super.request_heavy_cut()


# ---------------------------------------------------------------------------
# R7 P5 REF01 圓舞 右鍵分支（單招與十三型中的 REF01 皆同）：只改 REF01 期間的右鍵，其他型右鍵與一般重斬不變。
# 合法窗：地面、刀在手、REF01 所有命中窗已結束，且（單招）R7 取消窗口 _in_form_cancel_window／（循環中）已到本型接出格
# 或後段取消。窗前按 → 緩衝 r7_rmb_buffer_time 秒（與循環閃避緩衝同值），到合法窗即發；逾期／受擊／死亡／閃避／
# 其他取消（任何 _finish_attack）都清掉，之後不會自己觸發。循環中：先以 exit reason rmb_branch 乾淨結束循環、
# 清掃掠／命中組，再開分支新招；循環已結束，分支後不會被拉回。
# ---------------------------------------------------------------------------
const R7_RMB_ID := 102
@export var r7_rmb_buffer_time := 0.40
var _r7_rmb_left := 0.0
var r7_rmb_log: Array = []


func _r7_rmb_ready() -> bool:
	return R7_FORMS.has(R7_RMB_ID) and _anim != null and _anim.has_animation(String(R7_FORMS[R7_RMB_ID].anim))


func _r7_rmb_log_ev(info: Dictionary) -> void:
	info["t_ms"] = Time.get_ticks_msec()
	info["af"] = snappedf(_action_elapsed * r7_sun_speed * 30.0, 0.1)
	info["cycle"] = _r7c_running
	r7_rmb_log.append(info)


func _r7_rmb_legal() -> bool:
	if action_state != ActionState.ATTACKING or active_form != 1 or not _r7_rmb_ready():
		return false
	if _r7_is_air() or not is_on_floor() or sword_state != SwordState.DRAWN:
		return false
	var hf := _action_elapsed * _r7_hit_speed * 30.0
	for w in _r7_wins:
		if hf < float((w as PackedInt32Array)[1]) + 1.0:
			return false
	if _r7c_running:
		return _r7c_af() >= _r7c_handoff_frame(1) or r7_form_cancel_ok()
	return _in_form_cancel_window()


func _r7_rmb_request() -> void:
	if _r7_rmb_legal():
		_r7_rmb_fire()
		return
	_r7_rmb_left = r7_rmb_buffer_time
	_r7_rmb_log_ev({"ev": "rmb_buffered", "expires_s": r7_rmb_buffer_time})


## 每步開頭：倒數；離開 REF01（交接／結束）時仍有待處理 → 清除
func _r7_rmb_watch(delta: float) -> void:
	if _r7_rmb_left <= 0.0:
		return
	if action_state != ActionState.ATTACKING or active_form != 1:
		_r7_rmb_log_ev({"ev": "rmb_cleared", "why": "left_ref01"})
		_r7_rmb_left = 0.0
		return
	_r7_rmb_left -= delta
	if _r7_rmb_left <= 1e-6:
		_r7_rmb_left = 0.0
		_r7_rmb_log_ev({"ev": "rmb_expired"})


## 物理步內（R7 型 tick）：有待處理且合法 → 發分支（回傳 true，本步不再做續招／交接）
func _r7_rmb_tick() -> bool:
	if _r7_rmb_left <= 0.0 or active_form != 1:
		return false
	if _r7c_running and _r7c_dodge_left > 0.0 and _r7c_safe_point():
		_r7_rmb_log_ev({"ev": "rmb_cleared", "why": "dodge_priority"})
		_r7_rmb_left = 0.0
		return false
	if not _r7_rmb_legal():
		return false
	_r7_rmb_fire()
	return true


func _r7_rmb_fire() -> void:
	var was_cycle := _r7c_running
	_r7_rmb_log_ev({"ev": "rmb_fire", "buffer_left": snappedf(_r7_rmb_left, 0.001)})
	_r7_rmb_left = 0.0
	if _r7c_running:
		_r7c_hint = "rmb_branch"
	_finish_attack()
	if _r7c_running:
		_r7c_end("rmb_branch", 1)
	_r7c_hint = ""
	_form13_queue.clear()
	_hit_targets_this_swing.clear()
	_r7_prev_in_win = false
	_r7_rel_on = false
	var ok := execute_form(R7_RMB_ID, true)
	_r7_rmb_log_ev({"ev": "rmb_start" if ok else "rmb_exec_fail", "from_cycle": was_cycle, "anim": _active_attack_name})


func _r7_air_buffer_followup(kind: String) -> void:
	if not _r7_air_control_ok():
		return
	if r7_form_cancel_ok():
		_finish_attack()
		if kind == "light":
			_start_combo()
		else:
			request_heavy_cut()
	else:
		_r7_followup = kind
		_r7_followup_left = combo_input_buffer_time


## 空中輸入不落入父類普通斬／蓄力；地上輸入完全沿用原路。
func _unhandled_input(event):
	if not is_on_floor() and not input_locked and _combat_anims_ready:
		var id := 0
		if event.is_action_pressed("attack_light"):
			id = 10
		elif event.is_action_pressed("attack_heavy"):
			id = 4
		elif event.is_action_pressed("attack_special"):
			id = 7
		if id != 0:
			if not event.is_echo():
				execute_form(id)
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


