extends CharacterBody3D
## Yoriichi 高速武士控制器 — AnimationTree 三層架構。
##
##   loco  (AnimationNodeStateMachine)：Idle / Walk / Run / RunFL / RunFR /
##          BackPedal / JumpStart / Fall / Land —— 下半身與一般 locomotion。
##          8 向由角色 local 速度方向分 sector；急轉靠扇區＋限速視覺轉向
##          （舊 Run_Turn 素材整段懸空且帶 1.15 m 水平偏移，已停用）。
##   upper (AnimationNodeOneShot，上半身 bone filter)：Draw / Sheathe(反播) /
##          輕攻擊三段 / 聚力單斬 —— 腿繼續 locomotion，邊跑邊做。
##   full  (AnimationNodeOneShot，無 filter)：Roll —— 以及保留給日之呼吸
##          框架（execute_form）的 Spin / Judgment / Combo_1 / SpinJump，
##          這些大動作已從預設輸入下線（風格減法：沉穩、精準、不炫技）。
##
## 輸入：WASD 移動；Shift 按住疾跑、快按翻滾；Space 跳；Q 拔/收刀；
##       LMB 輕連段三段（快、準、有收勢，第三段後不接續大招）；
##       RMB 聚力單斬（同一刀素材的慎重版：較慢、收勢較長；空中亦可用）；
##       RMB 按住 = 蓄力拔刀斬：舉刀凍住蓄 3 s → 衝向鎖定／最近敵人 → 落刀（heavy_charge_* 群組）。
##
## CharacterBody3D 永遠是真實世界位置；所有衍生動畫資源水平 root motion 已清除
## 並錨定到骨架 rest 的 Hips 位置（locomotion 保留步態擺動但對齊原點），
## 位移（roll / lunge / jump）一律程式驅動。動畫時間全部由本腳本的計時器管理
## （AnimationTree 不提供 per-clip position），一個時鐘避免視覺與位移脫鉤。

# ---------------------------------------------------------------------------
# Locomotion
# ---------------------------------------------------------------------------
@export var speed := 4.0
@export var run_speed := 7.0
@export var gravity := 20.0
## 視覺轉向「速率上限」(rad/s)，不是 lerp 權重：走路沉穩、不瞬間 snap。
@export var turn_speed := 8.0
## 疾跑時轉向速率倍率（跑步可比走路轉得快）。
@export var run_turn_multiplier := 1.9
@export var blend_time := 0.2         # locomotion 狀態間預設 xfade

## 2026-10-17 換裝 v2.4（yoriichi_v24.glb，Mixamo 骨架）：舊 Meshy 24 骨動畫全部刪除，
## 動作改由 tools/v24_anim/build_v24_anims.gd 從 Mixamo（V2.4 角色、Arm-Space 0.78 防袖子穿身）重定向，
## 輸出在 res://characters/yoriichi/v24/anims/。欄位留空（null）時 _ready 以 idle 片段佔位。
## 移動三段：按住 walk（Alt）= 走路 walk_speed；預設 = 跑步 speed；按住 Shift = 疾跑 run_speed。
@export var idle_anim := "idle"
@export var walk_anim := "walk_user"
@export var idle_grounded_resource: Animation = null
@export var walk_speed := 1.6
## 動畫播放倍率 = 遊戲速度 ÷ 素材原生步速（Running 4.87 m/s、Fast Run 5.90 m/s、Walking 約 1.45 m/s）。
@export var walk_anim_speed := 1.1
@export var run_fast_anim := "Run_Jog"
@export var run_anim_speed := 0.82
@export var run_fast_resource: Animation = preload("res://characters/yoriichi/v24/anims/run.res")
@export var sprint_anim := "Sprint"
@export var sprint_anim_speed := 1.09
@export var sprint_resource: Animation = preload("res://characters/yoriichi/v24/anims/sprint_std.res")
## 待機小動作：站著不動 idle_break_after 秒後隨機播一支（呼吸、張望），一動就淡出。
@export var idle_break_enabled := true
@export var idle_break_after := Vector2(9.0, 15.0)
@export var idle_break_resources: Array[Animation] = [preload("res://characters/yoriichi/v24/anims/idle_breath.res"), preload("res://characters/yoriichi/v24/anims/idle_look.res")]
## 跑步中反向（>150°）輸入時播 180° 急轉（Running Turn 180）。
@export var run_turn_enabled := true
@export var run_turn_resource: Animation = preload("res://characters/yoriichi/v24/anims/run_turn180.res")
@export var run_turn_speed := 1.3
## 左前 / 右前「武士側身追擊」跑姿（剝離水平偏移、保留步態擺動的衍生版）。
@export var fl_run_resource: Animation = null
@export var fr_run_resource: Animation = null

@export_group("8-Direction")
## 8 向 sector 判定以角色 local 速度方向為準；換 sector 後最短持續時間（防抖）。
@export var sector_min_hold := 0.15

@export_group("Jump")
@export var jump_anim := "Jump"
## Mixamo「Jumping Up」（0.83 s）：0.33 s 蹲到最低、0.567 s 腳離地。
@export var jump_anim_resource: Animation = preload("res://characters/yoriichi/v24/anims/jump_up.res")
@export var jump_takeoff_t := 0.567
@export var fall_anim := "Fall"
@export var fall_resource: Animation = preload("res://characters/yoriichi/v24/anims/fall.res")
@export var land_anim := "Land"
## 「Falling To Landing」從觸地格起裁（0.25 s 後）。
@export var land_resource: Animation = preload("res://characters/yoriichi/v24/anims/land.res")
## 起跳段播放倍率。
@export var jump_start_speed := 1.6
## 落地段播放倍率。
@export var jump_land_speed := 1.5
## 起跳速度（物理）。空中時間 2v/g = 0.82 s，跳高 v²/2g ≈ 1.68 m。
@export var jump_velocity := 8.2
## JumpStart 跳過 clip 前面這段蹲伏（Run→Jump 立即起跳的關鍵）：
## 實際蓄力 = (jump_takeoff_t - skip) / jump_start_speed ≈ 0.15 s。
@export var jump_start_skip := 0.33
## 落地後無輸入時 Land 動畫佔用 locomotion 的時間；有輸入直接接 Run/Walk。
@export var land_lock_time := 0.25
## FREE 狀態離地超過此秒數視為 Fall（走出平台邊緣）。
@export var coyote_time := 0.12

@export_group("Traversal (特技)")
## 二段跳：空中再按跳 → 前空翻（疾跑中是轉體空翻）。落地或踩牆後重置。
@export var double_jump_enabled := true
@export var double_jump_velocity := 7.6
@export var flip_resource: Animation = preload("res://characters/yoriichi/v24/anims/flip.res")
@export var twist_flip_resource: Animation = preload("res://characters/yoriichi/v24/anims/twist_flip.res")
@export var flip_speed := 1.35
## 踩牆跳：空中貼牆時按跳 → 朝牆外反彈＋前空翻。可連續踩（每次需離開原牆面）。
@export var wall_jump_enabled := true
@export var wall_jump_push := 6.5
@export var wall_jump_up := 8.6
## 攀上屋簷／牆頭：空中朝牆前進、前方牆頂在腳上 ledge_min_height~ledge_max_height 內 → 自動攀上；
## 地面朝牆按跳、牆頂在 wallrun_min_height~wallrun_max_height → 蹬牆跑上去（Wall Run 上平台）。
@export var ledge_climb_enabled := true
@export var ledge_min_height := 0.7
@export var ledge_max_height := 2.0
@export var wallrun_min_height := 1.6
@export var wallrun_max_height := 3.4
@export var ledge_probe_distance := 0.9
@export var mantle_resource: Animation = preload("res://characters/yoriichi/v24/anims/mantle.res")
@export var mantle_speed := 1.25
@export var wallrun_resource: Animation = preload("res://characters/yoriichi/v24/anims/wall_run_up.res")
@export var wallrun_speed := 1.35
## 高處落地：落差 > land_roll_height 且有移動輸入 → 落地翻滾；靜止且落差 > hard_land_height → 重落地。
@export var land_roll_height := 3.5
@export var hard_land_height := 5.0
@export var land_roll_resource: Animation = preload("res://characters/yoriichi/v24/anims/land_roll.res")
@export var hard_land_resource: Animation = preload("res://characters/yoriichi/v24/anims/hard_land.res")

@export_group("Air Inertia")
## 空中不直接覆寫水平速度：有輸入時以 air_acceleration * air_control (m/s²)
## move_toward 目標速度；無輸入時只以 air_drag (m/s²) 衰減 → 保留起跳慣性。
@export var air_acceleration := 5.0
@export var air_control := 0.45
@export var air_drag := 0.15

@export_group("Roll")
@export var roll_anim := "Roll_Dodge"
## Mixamo「Sprinting Forward Roll」裁 0.25~1.17 s（0.93 s）。
@export var roll_anim_resource: Animation = preload("res://characters/yoriichi/v24/anims/roll.res")
## 3.2 m = 原 6.4 m 縮短 50%。位移仍由 CharacterBody3D ease-out 曲線驅動。
@export var roll_distance := 3.2
@export var roll_animation_speed := 2.0
@export var action_blend_time := 0.12
## Shift 按住 = 疾跑；按下後在此秒數內放開 = 翻滾。
@export var shift_tap_time := 0.25

## 玖ノ型 日暈龍・頭舞的火焰龍特效；關掉即回到原本純刀光的旋轉斬。
@export var sun_dragon_enabled := true
## 龍身直徑倍率：1.0 約 6 公尺寬，配合角色體型可自行調整。
@export_range(0.2, 3.0, 0.05) var sun_dragon_scale := 1.0
## 龍頭是否追著刀尖轉。使用者裁定不追的版本較好，預設關閉。
@export var sun_dragon_head_tracking := false
## 普通輕／重斬的閃避派生；不改日之呼吸或旋轉斬原有規則。
@export var attack_dodge_cancel_enabled := true
## 0 = 出招即可閃避；1 = 完整播完才可閃避。
@export_range(0.0, 1.0) var attack_dodge_cancel_start := 0.45

@export_group("Guard / Deflect")
## 隻狼式格擋：按住即格擋，按下瞬間的短窗口內被打中 = 彈刀。
@export var guard_enabled := true
## 彈刀窗口（秒）。0.15 為隻狼原作水準；調大變簡單。
@export_range(0.05, 0.5, 0.01) var deflect_window := 0.15
## 彈刀：傷害全免，自己軀幹只漲一點，對方軀幹重挫。
@export var deflect_self_posture := 5.0
@export var deflect_attacker_posture := 22.0
## 格擋：漏傷比例與軀幹代價。
@export_range(0.0, 1.0, 0.01) var block_damage_ratio := 0.15
## 32 不是拍的：试玩機實測 18 時每循環淨 +9.2，敵人 1.4 s/刀，
## 6 秒爆不了 —— 「一直龜會自己爆」的支柱被再生吃掉。32 → 淨 +15/循環，
## 約 7 刀（10 秒）爆，龟得住前 5 秒、撐不過 15 秒。
@export var block_self_posture := 32.0
@export var block_attacker_posture := 6.0
## 未防禦時的軀幹累積倍率。
@export var unguarded_posture_mult := 1.0
## 危攻擊（不可格擋）硬架的代價：漏傷比例與軀幹爆量。
@export_range(0.0, 1.0, 0.01) var perilous_block_damage_ratio := 0.6
@export var perilous_block_posture := 40.0

@export_group("Hit Reaction")
## 翻滾無敵幀窗口（以翻滾進度比例表示）。0 = 一起翻就有；1 = 全程。
## 窗口是半開區間 [start, end)：end = 0 或 start > end 都是合法的「無敵幀全關」。
@export_range(0.0, 1.0, 0.01) var dodge_invuln_start := 0.05
@export_range(0.0, 1.0, 0.01) var dodge_invuln_end := 0.75
## 受擊硬直（秒）。0 = 不中斷操作，只保留位移與鏡頭回饋。
## ⚠ 硬直走自己的計時器，不動 input_locked —— 那是對話／過場的介面，
##   硬直期間 HUD 與對話必須照常運作。
@export_range(0.0, 1.0, 0.01) var hit_stun_time := 0.25
## 受擊後退距離（公尺，程式位移，非 root motion）。
@export var hit_knockback := 1.6
@export var block_knockback := 0.6
@export var deflect_knockback := 0.15
## 鏡頭震動：振幅（公尺）與時間（秒）。振幅 0 = 關掉。
@export_range(0.0, 0.4, 0.01) var hit_shake_strength := 0.16
@export var hit_shake_time := 0.35
@export_range(0.0, 0.4, 0.01) var deflect_shake_strength := 0.05
@export var deflect_shake_time := 0.18

@export_group("Lock-on")
@export var lock_on_enabled := true
## 鎖定搜尋半徑。
@export var lock_on_range := 22.0
## 超過此距離自動解鎖。
@export var lock_break_range := 30.0
## 鎖定時角色轉向敵人的速率（rad/s）。
@export var lock_turn_speed := 9.0
## 忍殺可及距離：必須貼上去才能處決，不能隔空秒殺。
@export_range(1.0, 6.0, 0.1) var deathblow_range := 3.5
## 忍殺（處決）玩家端動作（2026-09-23）：Mixamo「Stealth Assassination」重定向版，
## 已用 tools/align_clip_to_idle.gd 的切片模式切成「落地→起身」36 格 / 1.1667 s，並首尾
## 對齊 Idle（Hips f0 54.6°→0.0°，腳底夾制回 +0.0230）。
## 為什麼要切片＋對齊：來源第一格是深蹲（髖 0.79 vs Idle 0.95），直接當 full 層 OneShot 播時，
## 入場淡化的關節角插值會讓腳底沉 50.7 mm（遊戲自己的普攻只沉 3.9 mm）；對齊後入場兩端
## 都是 Idle 姿，同一量測降到與普攻同級（見 tools/verify_deathblow.gd 的對照組）。
## 來源 7.0 s 的分段：0.00~1.30 貼地（接近／壓制）｜1.40~3.30 騰空（跳躍，髖 1.29 m）｜
## 3.40~3.62 落地（髖最低 0.79 = 落刀）｜3.70~7.00 貼地（收勢起身）。
## 要換範圍就重跑（from/to 會吸附 1/30 格）：
##   align_clip_to_idle.gd -- --slice=res://characters/yoriichi/animations/_mixamo_gap_staging/Stealth_Assassination.res \
##     --from=3.6 --to=4.7667 --name=yoriichi_deathblow --out=res://characters/yoriichi/animations
@export var deathblow_anim := "Deathblow"
@export var deathblow_resource: Animation = preload("res://characters/yoriichi/v24/anims/assassin.res")
@export var deathblow_speed := 1.0

@export_group("Drawn Locomotion（持刀移動）")
## 拔刀後的移動改播雙手持刀版（Great Sword Idle／Walk／Strafe…）；跑／疾跑用單手提刀跑（Run With Sword）。
## 播放倍率依 clip meta "root_speed" 對到實際速度，避免滑步。關掉 = 回到收刀的移動動作。
@export var drawn_locomotion_enabled := true
@export var grip_pose_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_idle.res")
@export var drawn_idle_resource: Animation = preload("res://characters/yoriichi/v24/anims/ua_idle_b.res")
@export var drawn_walk_resource: Animation = preload("res://characters/yoriichi/v24/anims/d_walk.res")
@export var drawn_back_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_walk_back.res")
@export var drawn_strafe_l_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_strafe_l.res")
@export var drawn_strafe_r_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_strafe_r.res")
@export var drawn_strafe_l_run_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_strafe_l_run.res")
@export var drawn_strafe_r_run_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_strafe_r_run.res")
@export var drawn_run_resource: Animation = preload("res://characters/yoriichi/v24/anims/sword_run.res")
@export var drawn_run_back_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_run_back.res")
## 持刀時右手指固定成握拳（非持刀 clip 如跳躍／翻滾／特技時手是張開的，刀會像浮在掌邊）。
@export var grip_overlay_enabled := true

@export_group("Attack")
## RMB 聚力單斬專用 clip（Great Sword Downward Slash：舉刀過頂→直劈）。null = 退回輕連段第一刀。
@export var heavy_cut_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_down.res")
@export var attack_combo_anim := "Attack_Combo"
@export var attack_combo_resource: Animation = preload("res://characters/yoriichi/v24/anims/attack_combo.res")
@export var attack_spin_anim := "Attack_Spin"
@export var attack_spin_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_spin_run.res")
@export var attack_continuous_spin_anim := "Attack_Continuous_Spin"
@export var attack_continuous_spin_resource: Animation = preload("res://characters/yoriichi/v24/anims/atk_onehand.res")
@export var attack_judgment_anim := "Attack_Judgment"
@export var attack_judgment_resource: Animation = preload("res://characters/yoriichi/v24/anims/atk_high.res")
@export var attack_combo_1_anim := "Attack_Combo_1"
@export var attack_combo_1_resource: Animation = preload("res://characters/yoriichi/v24/anims/atk_low.res")
@export var attack_spin_jump_anim := "Attack_Spin_Jump"
@export var attack_spin_jump_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_jump_atk.res")
## 捌ノ型 陽華突：自製直線突刺（tools/blender/make_form08_thrust.py）。
@export var attack_thrust_anim := "Attack_Thrust"
@export var attack_thrust_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_slide.res")
## 日之呼吸缺件四型：自製姿勢表動畫（tools/blender/make_form_clips.py → build_react_clips.gd）。
@export var attack_form05_anim := "Attack_Form05_Turn"
@export var attack_form05_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_power.res")
@export var attack_form06_anim := "Attack_Form06_Wheel"
@export var attack_form06_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_crouch_slash.res")
@export var attack_form11_anim := "Attack_Form11_Halo"
@export var attack_form11_resource: Animation = preload("res://characters/yoriichi/v24/anims/atk_outward.res")
@export var attack_form12_anim := "Attack_Form12_Dance"
@export var attack_form12_resource: Animation = preload("res://characters/yoriichi/v24/anims/th_combo.res")
## 居合（RMB 蓄力）兩支：Blender MCP 手調（tools/blender/iai_lib.py → build_react_clips.gd）。
## Stance f0=Idle 姿 → t≈0.33 進到 kamae（沉腰架勢）→ 末段呼吸循環；引擎拆兩節點：
##   iai_in（0→KAMAE_T 進姿）＋ iai_hold（KAMAE_T→尾，loop）。Slash = 拔刀斬一整刀。
@export var iai_stance_anim := "Iai_Stance"
@export var iai_stance_resource: Animation = preload("res://characters/yoriichi/v24/anims/iai_stance.res")
@export var iai_slash_anim := "Iai_Slash"
@export var iai_slash_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_crouch_slash.res")

@export_group("Combo Branches")
## 滑鼠左右鍵互搭：輕連段（LMB）某一段的取消窗口內按 RMB → 接對應的型；
## 聚力單斬（RMB）取消窗口內按 LMB → 接 heavy_branch_form；疾跑中 RMB → sprint_heavy_form。
## 0 = 該分支關閉。分支型不扣呼吸、不看熟練度（它們是累積呼吸的手段），冷卻照算。
@export var branch_after_stage1 := 6
@export var branch_after_stage2 := 5
@export var branch_after_stage3 := 12
@export var heavy_branch_form := 11
@export var sprint_heavy_form := 8
## 型結束前可接下一招的窗口（進度比例）：型表 cancel.x 之後，LMB 回連段段1、RMB 接聚力單斬。
@export var form_followup_enabled := true
## 日之呼吸起手：型發動瞬間刀身點燃。型的刀光側寫（尾巴長度／火扇寬度／亮度）
## 已移到 sun_breathing.gd FORMS[id].trail，不在這裡調。
@export var form_ignite_vfx := true
## 型的起手位移（impulse）持續時間（秒）：起手瞬間全速、線性衰減到 0。
## ⚠ 之前 execute_form 只做 velocity += impulse，下一個 physics 幀就被輸入速度蓋掉，
##   捌型 6 m/s 從來沒真的衝出去；改成有時長的 dash 才會有位移。
@export var form_impulse_time := 0.22

@export_group("Counter & Reward")
## 見切反擊：彈刀成功後 counter_window 秒內按 LMB → 直接接 counter_form（不扣呼吸、無視冷卻與熟練度）。
## 0 = 關閉。
@export var counter_form := 11
@export_range(0.0, 2.0, 0.05) var counter_window := 0.5
## 翻滾無敵幀真的閃過攻擊：呼吸回報 ＋ 短暫時間減速（隻狼式「見切」的爽感）。
@export var dodge_success_breath := 10.0
@export_range(0.0, 1.0, 0.05) var dodge_slowmo_scale := 0.4
@export_range(0.0, 1.0, 0.01) var dodge_slowmo_time := 0.25
## 拾參ノ型（form13 action，預設 C）：呼吸滿 form13_gauge_cost 時按下，把所有可用型連放。
## 連放期間不看熟練度（十三型本身就是「把十二型全部打出來」）。
@export var form13_key_enabled := true

@export_group("Reaction Animations")
## 反應動畫組（tools/blender/make_react_clips.py → build_react_clips.gd）。
## 架勢／格擋受衝／彈刀走 upper 層（腿由 locomotion 提供，可邊走邊架）；
## 受擊／軀幹爆／死亡走 full 層。首尾幀 = Idle 姿，與 loco Idle 髖高一致（0.9475）。
@export var guard_anim := "Guard_Hold"
@export var guard_anim_resource: Animation = preload("res://characters/yoriichi/v24/anims/guard.res")
@export var block_anim := "Block_Impact"
@export var block_anim_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_block_hit.res")
@export var deflect_anim := "Deflect"
@export var deflect_anim_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_block_hit.res")
@export var hit_react_anim := "Hit_React"
@export var hit_react_anim_resource: Animation = preload("res://characters/yoriichi/v24/anims/gs_hit.res")
@export var stagger_anim := "Stagger"
@export var stagger_anim_resource: Animation = preload("res://characters/yoriichi/v24/anims/react_front.res")
## 死亡倒地：Meshy Dead clip 衍生版（角色/緣一動作/animations/build_jump.gd，floor_clamp）。
@export var dead_anim := "Dead"
## 打坐（冥想）定格用的 clip。尚未製作時 start_meditation_pose() 退回站姿 Idle。
## 2026-09-22：由使用者提供的「盤腿坐」FBX 重定向而來（CC_Base 101 骨 → 本骨架 24 骨），
## 產生腳本 tools/build_meditate_clip.gd；內容是**定姿**（來源 clip 173 格骨頭全不動），
## 所以只有兩個相同關鍵格，play 完 seek 到結尾定格。
@export var meditate_anim := "Meditate"
@export var meditate_anim_resource: Animation = preload("res://characters/yoriichi/v24/anims/sit_floor.res")
@export var dead_anim_resource: Animation = preload("res://characters/yoriichi/v24/anims/death.res")
## 開場仰躺後的起身（Getting Up From Back）；沒有就退回 Dead 反播。
@export var get_up_resource: Animation = preload("res://characters/yoriichi/v24/anims/get_up.res")
## 方向性軀幹爆反應（2026-09-23）：Mixamo「Standing React Large」四方向，經
## tools/align_clip_to_idle.gd 對齊 Idle 首尾（Hips f0 偏 0.0°）＋逐格地面夾制，
## 再以 tools/verify_mixamo_clips.gd 驗收通過（腳底 ±1 mm、23 軌、23 key/格）。
## 播法沿用既有 Stagger：整段縮放到 posture.break_time，所以 1.0~1.7 s 的來源沒有時長衝突。
@export var stagger_directional := true
@export var stagger_front_anim := "Stagger_Front"
@export var stagger_front_resource: Animation = preload("res://characters/yoriichi/v24/anims/react_front.res")
@export var stagger_back_anim := "Stagger_Back"
@export var stagger_back_resource: Animation = preload("res://characters/yoriichi/v24/anims/react_back.res")
@export var stagger_left_anim := "Stagger_Left"
@export var stagger_left_resource: Animation = preload("res://characters/yoriichi/v24/anims/react_left.res")
@export var stagger_right_anim := "Stagger_Right"
@export var stagger_right_resource: Animation = preload("res://characters/yoriichi/v24/anims/react_right.res")
## Guard_Hold clip 從這個比例起全是架勢幀（f7/f12），持續架勢循環由此切入。
## guard.res = Great Sword Standing To Block（0.5 s）＋ Blocking Idle 循環（雙手架刀）；由 build_v24_anims 的 CONCAT meta "sections" 而來。
const GUARD_HOLD_FROM := 0.3636
## 架勢進場 0.5 s clip；1.6x ≈ 0.31 s 到位（比 deflect_window 稍長，刀先舉起來才算彈）。
@export var guard_anim_speed := 1.2
## 格擋受衝 0.33 s clip；1.2x ≈ 0.28 s，對上 block 位移 0.18 s＋回架。
@export var block_anim_speed := 1.3
## 彈刀 0.42 s clip；1.8x ≈ 0.23 s —— 彈刀要比格擋更快、更脆。
@export var deflect_anim_speed := 1.8
## 受擊 0.42 s clip；1.5x ≈ 0.28 s ≈ hit_stun_time 0.25。
@export var hit_react_speed := 1.6
## 死亡倒地播放倍率（clip 2.97 s）。播完停在最後一幀，不淡回 locomotion。
@export var dead_anim_speed := 1.0
## 速度分級（緣一風格：出刀突然且快、收勢清楚，不是一致的機械倍率）。
## 輕連段第一斬：突然、快。
@export var attack_speed_scale := 1.25
## 第二斬：維持節奏。
@export var combo_stage2_speed := 1.15
## 第三斬：略收（為明確收勢做準備）。
@export var combo_stage3_speed := 1.05
## RMB 聚力單斬：同一刀素材的慎重版 —— 預備小、落刀清楚、收勢長。
@export var heavy_cut_speed := 0.95
## 以下為日之呼吸框架（execute_form）保留技的倍率，不綁預設輸入：
## Judgment 大縱劈（柒型）。
@export var judgment_speed_scale := 2.4
## Weapon_Combo_1 全身斬（肆型）。
@export var combo_1_speed_scale := 2.2
## Axe_Spin 全身迴旋（貳型）。
@export var spin_speed_scale := 1.7
## 連續旋轉砍擊（Continuous Spin）。
@export var continuous_spin_speed_scale := 1.8
## 360_Power_Spin_Jump（拾型）。
@export var spin_jump_speed_scale := 2.0
## 捌型 陽華突。動畫本身 1.25 s；1.6 倍 → 約 0.78 s，
## 蓄力看得見、突刺仍然突然（動畫內部的爆發比已經是 4.6x）。
@export var thrust_speed_scale := 1.6
@export_range(0.0, 1.0) var combo_cancel_start := 0.35
@export_range(0.0, 1.0) var combo_cancel_end := 0.65
@export var combo_input_buffer_time := 0.30
@export var combo_section_blend := 0.035
@export_range(0.0, 1.0) var attack_turn_control := 0.35
## MGR 式：攻擊不是 movement lock。Run 攻擊保留 100% 前進動量、Walk 70%；
## 全身技（heavy）50% —— 即使 full-body override，CharacterBody3D 也不停。
@export var attack_move_factor_run := 1.0
@export var attack_move_factor_walk := 1.0
@export var attack_move_factor_heavy := 0.5

@export_group("Heavy Charge (RMB 長按)")
## RMB 按住 = 蓄力拔刀斬；未滿放開 = 原本的聚力單斬（短按行為不變）。關掉即回到純聚力單斬。
@export var heavy_charge_enabled := true
## 滿蓄所需秒數（從按下算起）。
@export_range(0.2, 6.0, 0.05) var heavy_charge_time := 2.0
## 聚力單斬 clip 播到這個進度時切入居合架勢（gs_down 刀尖最高在 f17/38 ≈ 0.45，取 0.42 = 刀剛舉到頂）。
@export_range(0.05, 0.6, 0.01) var heavy_charge_freeze_progress := 0.42
## Iai_Stance 進姿段結束點（秒）：iai_stance.res = Great Sword Stand To Crouch（0.67 s）＋蹲姿持刀循環，
## CONCAT sections[1] = 0.28 × 2.5 s = 0.70。
@export_range(0.05, 1.0, 0.01) var iai_kamae_t := 0.70
## 滿蓄後停在架勢，放開才衝；打開 = 滿蓄立即發動（舊行為）。
@export var heavy_charge_auto_release := false
## 衝刺距離上限（公尺）。0 = 不衝，原地落刀。
@export_range(0.0, 12.0, 0.1) var heavy_charge_dash_max := 8.0
## 沒有敵人時朝面向衝的距離（公尺）。
@export_range(0.0, 8.0, 0.1) var heavy_charge_dash_no_target := 4.0
## 衝刺速度（m/s）。8 m ÷ 24 ≈ 0.33 s。
@export_range(4.0, 40.0, 0.5) var heavy_charge_dash_speed := 24.0
## 煞停在敵人前多遠（公尺）。玩家碰撞不跟敵人層互撞，不設就會穿過去揮空。
@export_range(0.5, 3.0, 0.05) var heavy_charge_stop_distance := 1.3
## 到位前多少秒開始落刀（刀在抵達瞬間切到）。
@export_range(0.0, 0.3, 0.01) var heavy_charge_slash_lead := 0.06
## 落刀播放倍率（比聚力單斬 1.5 快得多：蓄得越久、出刀越突然）。
@export_range(1.0, 5.0, 0.1) var heavy_charge_slash_speed := 2.6
@export_range(1.0, 6.0, 0.1) var heavy_charge_damage_mult := 2.5
@export_range(1.0, 6.0, 0.1) var heavy_charge_posture_mult := 2.0
## 落刀的火焰刀光側寫（同 sun_breathing FORMS.trail 欄位）。emission 1.0 = 與普通刀光同亮：
## 實拍 1.2 時刀根又疊出白球（336f769 才拿掉的），份量靠尾巴長度與火扇寬度給，不靠加亮。
@export_range(0.1, 1.5, 0.01) var heavy_charge_trail_lifetime := 0.55
@export_range(0.0, 2.0, 0.01) var heavy_charge_trail_extend := 0.85
@export_range(0.5, 2.0, 0.05) var heavy_charge_trail_emission := 1.0

const SunBreathing = preload("res://characters/yoriichi/sun_breathing.gd")
const CombatVFX = preload("res://characters/yoriichi/vfx/combat_vfx.gd")
const SunDragonVFX = preload("res://characters/yoriichi/vfx/sun_dragon.gd")
const SwordTrail3D = preload("res://characters/yoriichi/vfx/sword_trail.gd")
const HitFeedback = preload("res://characters/yoriichi/vfx/hit_feedback.gd")
const HeavyChargeFX = preload("res://characters/yoriichi/vfx/heavy_charge_fx.gd")
const PostureComponent = preload("res://characters/combat/posture.gd")

## Relayed from the camera/interaction adapter child so main.gd can keep
## connecting to the Player root exactly as it did with scenes/player.gd.
## 格擋舉起／放下；HUD 用來顯示防禦姿態。
signal guard_state_changed(guarding: bool)
## 玩家受擊結果（含彈刀／格擋／未防禦），HUD 與音效用。
signal player_was_hit(info: Dictionary)
## 呼吸量變動；型選單與 HUD 用。
signal breath_changed(current: float, maximum: float)
## 成功發動某一型（已扣呼吸、已起算冷卻）。
signal form_executed(id: int)
## RMB 蓄力進度 0~1（HUD 用）；-1 = 蓄力結束／取消。
signal heavy_charge_changed(progress: float)
## 蓄力拔刀斬發動（target 可為 null）。
signal heavy_charge_released(target: Node3D)
## 玩家軀幹被打爆（硬直開始）／恢復。
signal player_posture_broken
signal player_posture_recovered
## 玩家死亡。
signal player_died
## 見切反擊成功發動（彈刀 → LMB）。
signal counter_triggered(form_id: int)
## 拾參ノ型開始／結束。
signal form13_started
signal form13_finished
signal interaction_prompt_changed(text: String)
signal interaction_message(text: String)
## attack_combo.res（第三輪「超人類武士」）= 單手三刀 Cross Slash／Inward Slash／Downward Slash 串接：
## 挺胸、伸臂、左手握鞘口，揮砍段時間加速（snap）。段落 = 三支 clip 的接縫（builder meta sections）。
## sun_breathing 壹／參 型用同一組值。
const COMBO_SECTION_RANGES: Array[Vector2] = [
	Vector2(0.0, 0.3178),
	Vector2(0.3178, 0.7442),
	Vector2(0.7442, 1.00),
]
## OneShot filter：上半身骨骼（Spine02 以上）。下半身（Hips＋腿）留給 loco。
const UPPER_BONES := ["Spine02", "Spine01", "Spine",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"neck", "Head", "head_end", "headfront"]

# ---------------------------------------------------------------------------
# 刀（socket 結構不變）：SheathSocket(Hips)=Sword_Sheathed、HandSocket(RightHand)=Sword_Hand
# ---------------------------------------------------------------------------
enum SwordState { SHEATHED, DRAWING, DRAWN, SHEATHING }
## Jump/Fall 不是 ActionState：跳躍是純 physics（_jump_charge 倒數 → velocity.y），
## 攻擊只是疊在上面的 animation layer，永遠取消不了跳躍。
enum ActionState { FREE, ATTACKING, DODGING }

@export_group("Sword Draw")
@export var draw_anim := "Draw_Sword"
@export var draw_anim_resource: Animation = preload("res://characters/yoriichi/v24/anims/draw.res")
## 拔刀播放倍率（1.0s clip → 0.87s：看得清楚但不拖沓）。
## socket 切換時間依 _draw_real 自動同步。
@export var draw_speed_scale := 1.1
## 納刀比拔刀更慢一點 —— 儀式感在收勢。
@export var sheathe_speed_scale := 0.9
## 拔刀動畫進度（0~1）中「刀離開刀鞘」的時間點。反播跨過同一點刀即回鞘。
@export_range(0.0, 1.0) var t_unsheathe := 0.41

@export_group("Attack Damage")
## 輕連段單段傷害。型的 FORMS.damage 倍率會乘在這上面。
@export var light_attack_damage := 15.0
@export var light_posture_damage := 12.0
## 聚力單斬／全身技傷害。
@export var heavy_attack_damage := 35.0
@export var heavy_posture_damage := 28.0

@export_group("Sun Breathing")
## 呼吸量。命中與彈刀累積，發型時消耗。
@export var sun_breath_gauge := 0.0
@export var sun_breath_max := 100.0
## 每次刀刃命中累積的呼吸量。
@export var breath_gain_on_hit := 6.0
## 彈刀成功累積的呼吸量 —— 彈刀比硬砍更「順呼吸」，給得比命中多。
@export var breath_gain_on_deflect := 14.0
## 格擋（非彈刀）累積的呼吸量。
@export var breath_gain_on_block := 3.0
## 型的解鎖熟練度（0=初期）。required_mastery 高於此值的型不可用。
@export var sun_mastery := 0
## 拾參ノ型解鎖開關與啟動所需呼吸量（data parameter，先不綁輸入）。
@export var form13_unlocked := false
@export var form13_gauge_cost := 100.0

var sword_state: SwordState = SwordState.SHEATHED
var action_state: ActionState = ActionState.FREE
var combo_stage := 0
var combo_input_buffered := false
var pending_sheathe := false
var active_form := 0                  # 執行中的日之呼吸型 id（0 = 一般攻擊）

var _anim: AnimationPlayer
var _tree: AnimationTree
var _visual: Node3D
var _sword_hand: Node3D
var _sword_sheathed: Node3D
var _upper_node: AnimationNodeOneShot = null
var _full_node: AnimationNodeOneShot = null
var _fl_anim := ""
var _fr_anim := ""
var _sector_state := "Run"
var _sector_hold := 0.0
var _attack_after_roll := false

var _attack_layer := "upper"          # "upper" | "full"
var _active_attack_name := ""
var _spin_buffered_cancel := ""
## 收勢（zanshin）：upper 層結束時的淡出時間，發招時依招式設定——
## 輕斬段短、第三斬與聚力單斬長（刀停了 → 身體穩下來 → 回架勢）。
var _upper_finish_fade := 0.10
var _action_elapsed := 0.0
var _action_real := 0.0               # 目前段/技的真實時長（已除以播放倍率）
var _roll_duration := 0.0
var _dodge_dir := Vector3.ZERO
var _combo_queued_inputs := 0
var _combo_buffer_remaining := 0.0
var _jump_charge := -1.0     # >= 0 = 起跳蓄力倒數中（獨立於 ActionState，攻擊打不斷）
var _was_airborne := false
var _air_t := 0.0
var _land_lock := 0.0
var _draw_elapsed := 0.0
var _draw_real := 0.0
var _draw_t := 0.0
var _attack_after_draw := false
var _draw_followup := "light"
var _shift_pressed_msec := -1
var _form13_queue: Array[int] = []
## 左右鍵互搭的排隊：連段中按 RMB 排的型 id（0 = 無）；型中按 LMB/RMB 排的後續（"light"/"heavy"/""）。
var _branch_queued := 0
var _form_followup := ""
var _trail_default_lifetime := 0.20
var _form_dash := Vector3.ZERO
var _form_dash_total := 0.0
var _form_dash_left := 0.0
var _counter_until_msec := -1
var _slowmo_left := 0.0
var _form13_running := false
var _blade_base: Marker3D = null
var _blade_tip: Marker3D = null
var _sword_trail: SwordTrail3D = null
var _hitbox: Area3D = null
var _hitstop_time := 0.0
var _hit_targets_this_swing: Dictionary = {}
## RMB 蓄力拔刀斬。蓄力期間 action_state 仍是 ATTACKING、_active_attack_name 仍是 "Heavy_Cut"
## （不加 ActionState：tools/_fake_player.gd 與多處 == 1 判斷依賴既有數值）。
var _heavy_charging := false
var _heavy_frozen := false          # 已切入居合架勢（full 層 iai_in／iai_hold 播放中）
var _iai_hold_in := 0.0             # >0 = iai_in 進姿段剩餘秒數，到點切 iai_hold 循環
var _iai_full_active := false       # full 層目前是 iai 內容（架勢／落刀）；_finish_attack 據此淡出
var _heavy_charge_elapsed := 0.0
var _heavy_charge_ready := false
var _iai_dash_dir := Vector3.ZERO
var _iai_dash_remaining := 0.0      # >0 = 衝刺中（公尺）
var _iai_unfreeze_in := -1.0        # >=0 = 幾秒後解凍落刀
var _iai_charged := false           # 本刀是蓄力版（傷害倍率）
var _iai_target: Node3D = null
var _heavy_charge_arming := false   # begin_heavy_charge 呼叫 request_heavy_cut 期間為真
var _charge_fx: HeavyChargeFX = null
## 型 id → 冷卻剩餘秒數。空 = 全部就緒。
var _form_cooldowns: Dictionary = {}
## 軀幹被打爆後的硬直剩餘秒數（>0 = 不能動）。
var _stagger_left := 0.0
## 最近一次受擊的推力方向（take_hit 一收到就存）。軀幹爆是在 apply_damage 內觸發的，
## 那時已經拿不到 hit_data，所以方向要在這裡先留下來。
var _last_hit_dir := Vector3.ZERO
## 忍殺演出剩餘秒數（>0 = 走「軀幹爆」那條只跑重力、不讀輸入的提早返回分支）。
var _deathblow_left := 0.0
## 忍殺的 input_locked 是不是我們自己鎖的 —— 是我們鎖的才由我們解，
## 不覆蓋對話／過場已經持有的鎖。
var _deathblow_lock_owned := false
## 受擊硬直剩餘秒數（>0 = 讀不到輸入，但 input_locked 保持 false）。
var _hitstun_left := 0.0
## 受擊／格擋的後退速度（m/s，線性衰減）與它的總時長。
var _knockback := Vector3.ZERO
var _knockback_total := 0.0
var _knockback_left := 0.0
var _hit_feedback: Node = null
## 格擋／彈刀 one-shot 剩餘秒數：歸零且仍按著格擋 → 切回 Guard_Hold 循環。
var _guard_react_left := -1.0
## 死亡倒地剩餘秒數：歸零 → 關 AnimationTree、AnimationPlayer 停在最後一幀。
var _dead_left := -1.0

## Step-up for ledges and stone edges up to this height (metres). The east
## river revetment top (coping lip 0.22 m proud, walk_slice 2026-09-03) and
## the west bridge abutment present ~46° faces that move_and_slide treats as
## walls; a real person steps over them. Set 0 to disable.
## P11 R2：0.6 → 0.35（0.51 m の店前の長凳・0.45–0.49 m の縁台を歩くだけで乗り越えない；
## 參道・踏石・門・橋・田埂・跨渠板・河岸石段は 0.35 で通れる。docs/art_review/village_v2_p11/r2/）
@export var step_height := 0.35

## Node whose world yaw defines "forward" for move_forward/back/left/right.
## main.tscn points this at the camera pivot so input is camera-relative; the
## standalone test level leaves it empty and reads world axes.
@export var input_yaw_node: Node3D

## 對話／過場鎖定：為真時不讀移動與動作輸入，只跑重力與動畫落地。
## 這是 DialogueManager 等上層鎖玩家的正式接口（player_camera_adapter 同步看它）。
var input_locked := false:
	set(v):
		input_locked = v
		if v:
			velocity.x = 0.0
			velocity.z = 0.0
			# 對話／過場鎖住時蓄力不能懸著（放開事件已收不到）：整招收掉。
			if _heavy_charging or _iai_unfreeze_in >= 0.0:
				_finish_attack()

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
func _ready():
	var aps := find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		push_warning("yoriichi_character: no AnimationPlayer found in FBX")
		return
	_anim = aps[0]
	_visual = _anim.get_parent()
	if _visual != null and is_zero_approx(_visual.rotation.y):
		_visual.rotation.y = PI
	_fl_anim = "Run_FL" if fl_run_resource != null else ""
	_fr_anim = "Run_FR" if fr_run_resource != null else ""
	_combat_anims_ready = attack_combo_resource != null and draw_anim_resource != null
	_fill_missing_animations()
	_add_animation_resource(idle_anim, idle_grounded_resource)
	_add_animation_resource(run_fast_anim, run_fast_resource)
	_add_animation_resource(_fl_anim, fl_run_resource)
	_add_animation_resource(_fr_anim, fr_run_resource)
	_add_animation_resource(roll_anim, roll_anim_resource)
	_add_animation_resource(jump_anim, jump_anim_resource)
	_add_animation_resource(attack_combo_anim, attack_combo_resource)
	_add_animation_resource(attack_spin_anim, attack_spin_resource)
	_add_animation_resource(attack_continuous_spin_anim, attack_continuous_spin_resource)
	_add_animation_resource(attack_judgment_anim, attack_judgment_resource)
	_add_animation_resource(attack_combo_1_anim, attack_combo_1_resource)
	_add_animation_resource(attack_spin_jump_anim, attack_spin_jump_resource)
	_add_animation_resource(attack_thrust_anim, attack_thrust_resource)
	_add_animation_resource(attack_form05_anim, attack_form05_resource)
	_add_animation_resource(attack_form06_anim, attack_form06_resource)
	_add_animation_resource(attack_form11_anim, attack_form11_resource)
	_add_animation_resource(attack_form12_anim, attack_form12_resource)
	_add_animation_resource(iai_stance_anim, iai_stance_resource)
	_add_animation_resource(iai_slash_anim, iai_slash_resource)
	_add_animation_resource(draw_anim, draw_anim_resource)
	_add_animation_resource(guard_anim, guard_anim_resource)
	_add_animation_resource(block_anim, block_anim_resource)
	_add_animation_resource(deflect_anim, deflect_anim_resource)
	_add_animation_resource(hit_react_anim, hit_react_anim_resource)
	_add_animation_resource(stagger_anim, stagger_anim_resource)
	_add_animation_resource(stagger_front_anim, stagger_front_resource)
	_add_animation_resource(stagger_back_anim, stagger_back_resource)
	_add_animation_resource(stagger_left_anim, stagger_left_resource)
	_add_animation_resource(stagger_right_anim, stagger_right_resource)
	_add_animation_resource(deathblow_anim, deathblow_resource)
	_add_animation_resource(dead_anim, dead_anim_resource)
	_add_animation_resource(meditate_anim, meditate_anim_resource)
	_add_animation_resource(sprint_anim, sprint_resource)
	_add_animation_resource(fall_anim, fall_resource)
	_add_animation_resource(land_anim, land_resource)
	_add_animation_resource("Get_Up", get_up_resource)
	_add_animation_resource("Run_Turn", run_turn_resource)
	_add_animation_resource("Heavy_Cut", heavy_cut_resource)
	for dk in DRAWN_CLIPS:
		_add_animation_resource(dk, get(DRAWN_CLIPS[dk]))
	for tk in TRAVERSAL_CLIPS:
		_add_animation_resource(tk, get(TRAVERSAL_CLIPS[tk]))
	for i in idle_break_resources.size():
		_add_animation_resource("Idle_Break_%d" % i, idle_break_resources[i])
	_ensure_walk_action()
	_check_section_meta()
	for n in [walk_anim, run_fast_anim, sprint_anim, fall_anim, _fl_anim, _fr_anim, idle_anim, guard_anim] + DRAWN_CLIPS.keys():
		if n != "" and _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for n in [draw_anim, roll_anim, jump_anim, attack_combo_anim, attack_spin_anim,
			attack_continuous_spin_anim, attack_judgment_anim, attack_combo_1_anim,
			attack_spin_jump_anim, attack_thrust_anim,
			attack_form05_anim, attack_form06_anim, attack_form11_anim, attack_form12_anim,
			iai_stance_anim, iai_slash_anim,
			block_anim, deflect_anim, hit_react_anim, stagger_anim,
			stagger_front_anim, stagger_back_anim, stagger_left_anim, stagger_right_anim,
			deathblow_anim, land_anim, "Get_Up", "Run_Turn", "Heavy_Cut",
			dead_anim] + TRAVERSAL_CLIPS.keys():
		if n != "" and _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_NONE
	_sword_hand = _find_first("Sword_Hand")
	_sword_sheathed = _find_first("Sword_Sheathed")
	_apply_sword_visibility()
	_build_tree()
	_setup_combat_extensions()

## 持刀 locomotion：loco 狀態名 = 動畫名 = 此表 key；值 = export 欄位。
const DRAWN_CLIPS := {
	"D_Idle": "drawn_idle_resource", "D_Walk": "drawn_walk_resource", "D_Back": "drawn_back_resource",
	"D_StrafeL": "drawn_strafe_l_resource", "D_StrafeR": "drawn_strafe_r_resource",
	"D_StrafeLRun": "drawn_strafe_l_run_resource", "D_StrafeRRun": "drawn_strafe_r_run_resource",
	"D_Run": "drawn_run_resource", "D_RunBack": "drawn_run_back_resource",
}
## 收刀狀態名 → 持刀狀態名（Sprint 也走單手提刀跑，倍率另算）。
const DRAWN_OF := {"Idle": "D_Idle", "Walk": "D_Walk", "Run": "D_Run", "Sprint": "D_Sprint", "BackPedal": "D_Back"}

## 特技用全身 clip：AnimationTree full 層的 input 名 = 動畫名 = 此表 key；值 = export 欄位。
const TRAVERSAL_CLIPS := {
	"Trick_Flip": "flip_resource", "Trick_TwistFlip": "twist_flip_resource",
	"Trick_Mantle": "mantle_resource", "Trick_WallRun": "wallrun_resource",
	"Trick_LandRoll": "land_roll_resource", "Trick_HardLand": "hard_land_resource",
}

## 走路鍵：專案 InputMap 沒有 walk 時，執行期補一個（Left Alt），不改 project.godot。
func _ensure_walk_action() -> void:
	if InputMap.has_action("walk"):
		return
	InputMap.add_action("walk")
	var ev := InputEventKey.new()
	ev.keycode = KEY_ALT
	InputMap.action_add_event("walk", ev)

## 動畫串接段落（meta "sections"）與程式常數不符時警告：重建 attack_combo／guard 後要同步常數。
func _check_section_meta() -> void:
	if attack_combo_resource != null and attack_combo_resource.has_meta("sections"):
		var sec: PackedFloat32Array = attack_combo_resource.get_meta("sections")
		for i in mini(sec.size(), COMBO_SECTION_RANGES.size()):
			if absf(sec[i] - COMBO_SECTION_RANGES[i].x) > 0.003:
				push_warning("attack_combo sections %s 與 COMBO_SECTION_RANGES 不符" % [sec])
				break
	if guard_anim_resource != null and guard_anim_resource.has_meta("sections"):
		var gs: PackedFloat32Array = guard_anim_resource.get_meta("sections")
		if gs.size() > 1 and absf(gs[1] - GUARD_HOLD_FROM) > 0.003:
			push_warning("guard sections %s 與 GUARD_HOLD_FROM 不符" % [gs])

func _find_first(n: String) -> Node3D:
	var r := find_children(n, "", true, false)
	return r[0] if r.size() > 0 else null

## 戰鬥動畫（輕連段＋拔刀）是否已指定。v2.4 換裝後尚未製作 → false：
## 停用拔刀／攻擊／格擋／翻滾／型等輸入，只保留移動、疾跑、跳躍、鎖定。
var _combat_anims_ready := false

## 把留空（null）的動作欄位補成 idle 片段佔位，讓 AnimationTree 節點與各處 .length
## 計時都有合法對象（不會 null 崩潰）。佔位不代表動作完成：戰鬥輸入由 _combat_anims_ready 擋住；
## 被動觸發（受擊／死亡／開場倒地／打坐）時角色只會維持站姿。
func _fill_missing_animations() -> void:
	if not _anim.has_animation(idle_anim):
		push_warning("yoriichi_character: 找不到 idle 動畫 '%s'，無法建立佔位" % idle_anim)
		return
	var idle_src := _anim.get_animation(idle_anim)
	var short_ph: Animation = idle_src.duplicate(true)
	short_ph.length = minf(0.4, idle_src.length)
	short_ph.loop_mode = Animation.LOOP_NONE
	# Jump 的三段 custom timeline 讀到 1.9 s，佔位要夠長。
	var jump_ph: Animation = idle_src.duplicate(true)
	jump_ph.length = minf(1.9, idle_src.length)
	jump_ph.loop_mode = Animation.LOOP_NONE
	if jump_anim_resource == null:
		jump_anim_resource = jump_ph
	for prop in ["roll_anim_resource", "deathblow_resource",
			"attack_combo_resource", "attack_spin_resource", "attack_continuous_spin_resource",
			"attack_judgment_resource", "attack_combo_1_resource", "attack_spin_jump_resource",
			"attack_thrust_resource", "attack_form05_resource", "attack_form06_resource",
			"attack_form11_resource", "attack_form12_resource",
			"iai_stance_resource", "iai_slash_resource", "draw_anim_resource",
			"guard_anim_resource", "block_anim_resource", "deflect_anim_resource",
			"hit_react_anim_resource", "stagger_anim_resource",
			"stagger_front_resource", "stagger_back_resource",
			"stagger_left_resource", "stagger_right_resource",
			"dead_anim_resource", "meditate_anim_resource"]:
		if get(prop) == null:
			set(prop, short_ph)

var _character_audio: CharacterAudio
## 腳步音效（依地表切音庫）。見 footstep_audio.gd。
var _footstep_audio: FootstepAudio
## 隻狼式血量／軀幹；敵人共用同一份 posture.gd。
var posture: Node = null
var _guard_held := false
var _guard_started_msec := -1
## 目前鎖定的敵人；null = 未鎖定。
var lock_target: Node3D = null

func _setup_combat_extensions() -> void:
	_character_audio = CharacterAudio.new()
	_character_audio.name = "CharacterAudio"
	add_child(_character_audio)

	# 腳步：以前完全不存在（全專案 grep 不到任何 footstep 實作）。
	# 地表由腳下射線打到的 collider 名稱判定，見 footstep_audio.gd。
	_footstep_audio = FootstepAudio.new()
	_footstep_audio.name = "FootstepAudio"
	add_child(_footstep_audio)

	_hit_feedback = HitFeedback.new()
	_hit_feedback.name = "HitFeedback"
	add_child(_hit_feedback)

	posture = PostureComponent.new()
	posture.name = "Posture"
	add_child(posture)
	# ⚠ 玩家自己的軀幹爆掉／死亡以前沒有任何接收端：血歸零只是靜靜地
	#   把 _dead 設 true，玩家照樣能跑能砍。這裡把它接起來。
	posture.posture_broken.connect(_on_self_posture_broken)
	posture.posture_recovered.connect(_on_self_posture_recovered)
	posture.died.connect(_on_self_died)
	if _sword_hand:
		_blade_base = Marker3D.new()
		_blade_base.name = "BladeBase"
		_blade_base.position = Vector3(0, 0.1, 0)
		_sword_hand.add_child(_blade_base)

		_blade_tip = Marker3D.new()
		_blade_tip.name = "BladeTip"
		_blade_tip.position = Vector3(0, 1.05, 0)
		_sword_hand.add_child(_blade_tip)

		_sword_trail = SwordTrail3D.new()
		_sword_trail.name = "SwordTrail"
		_sword_trail.base_node = _blade_base
		_sword_trail.tip_node = _blade_tip
		add_child(_sword_trail)
		_trail_default_lifetime = _sword_trail.lifetime

		_hitbox = Area3D.new()
		_hitbox.name = "BladeHitbox"
		_hitbox.collision_layer = 0
		_hitbox.collision_mask = 3
		_hitbox.monitoring = false
		var col := CollisionShape3D.new()
		# ⚠ 刀手骨繼承非等比縮放（實測約 1.08×0.63×1.0）。Jolt 的膠囊不支援非等比縮放
		#   （會強制改成等比 0.90，判定體積走樣），凸包可以——所以用同尺寸膠囊網格
		#   生成凸包，判定體積與舊 GodotPhysics 下的縮放膠囊一致。
		var cap_mesh := CapsuleMesh.new()
		cap_mesh.radius = 0.40
		cap_mesh.height = 1.10
		col.shape = cap_mesh.create_convex_shape(true, false)
		col.position = Vector3(0, 0.55, 0)
		_hitbox.add_child(col)
		_sword_hand.add_child(_hitbox)
		_hitbox.body_entered.connect(_on_hit_target)
		_hitbox.area_entered.connect(_on_hit_target)

		# RMB 蓄力特效：掛在刀上（跟手走）。blade_mid 與 sword_mesh 要在 add_child 前設好（_ready 讀）。
		_charge_fx = HeavyChargeFX.new()
		_charge_fx.name = "HeavyChargeFX"
		_charge_fx.blade_mid = (_blade_base.position + _blade_tip.position) * 0.5
		var sword_meshes := _sword_hand.find_children("*", "MeshInstance3D", true, false)
		if sword_meshes.size() > 0:
			_charge_fx.sword_mesh = sword_meshes[0]
		_sword_hand.add_child(_charge_fx)

# ---------------------------------------------------------------------------
# Lock-on（沒有鎖定，隻狼式讀招不成立）
# ---------------------------------------------------------------------------

signal lock_target_changed(target: Node3D)

## 切換鎖定：已鎖定則解除，否則鎖最近的活敵人。
func toggle_lock_on() -> void:
	if not lock_on_enabled:
		return
	if lock_target != null:
		set_lock_target(null)
		return
	set_lock_target(_nearest_enemy())


func set_lock_target(t: Node3D) -> void:
	if lock_target == t:
		return
	lock_target = t
	lock_target_changed.emit(t)


func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_d := lock_on_range
	for n in get_tree().get_nodes_in_group("enemies"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var e := n as Node3D
		var p = e.get("posture")
		if p != null and p.is_dead():
			continue
		var d := global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## 每個物理步維護鎖定：死亡或跑太遠自動解除，否則轉身面對。
func _update_lock_on(delta: float) -> void:
	if lock_target == null:
		return
	if not is_instance_valid(lock_target) or not lock_target.is_inside_tree():
		set_lock_target(null)
		return
	var p = lock_target.get("posture")
	if p != null and p.is_dead():
		set_lock_target(null)
		return
	if global_position.distance_to(lock_target.global_position) > lock_break_range:
		set_lock_target(null)
		return

	# 翻滾中不強制轉向，否則閃避方向會被鎖死。
	if action_state == ActionState.DODGING:
		return
	var to := lock_target.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.0004:
		return
	var want := atan2(to.x, to.z)
	if _visual != null:
		_visual.global_rotation.y = rotate_toward(_visual.global_rotation.y, want, lock_turn_speed * delta)
	global_rotation.y = rotate_toward(global_rotation.y, want, lock_turn_speed * delta)


## 忍殺：對鎖定中（或最近）的破綻敵人發動處決。
func try_deathblow() -> bool:
	if _heavy_charging or _iai_unfreeze_in >= 0.0:
		return false   # 蓄力／衝刺中不忍殺：上半身凍著，處決會疊在舉刀姿勢上
	var t: Node3D = lock_target if lock_target != null else _nearest_enemy()
	if t == null or not t.has_method("execute_deathblow"):
		return false
	if global_position.distance_to(t.global_position) > deathblow_range:
		return false
	if not t.execute_deathblow():
		return false
	if _character_audio != null:
		_character_audio.play_deathblow()
	# 忍殺的份量：鏡頭震動比任何一刀都大（走既有 HitFeedback，不新增系統）。
	if _hit_feedback != null:
		_hit_feedback.shake(hit_shake_strength * 0.9, 0.3)
	# 玩家端動作（2026-09-23）：原本這裡完全沒有動畫，敵人在爆散的同時玩家站著不動。
	_play_deathblow()
	return true


## 忍殺演出：面向目標 → 播落刀段 → 鎖住操作直到放完。
## 只走既有機制：full 層 OneShot（子區段，同 iai_in/iai_hold）＋ input_locked（對話／過場
## 用的那個鎖）＋ 軀幹爆那條「只跑重力、不讀輸入」的提早返回分支。沒有新增系統。
func _play_deathblow() -> void:
	# 面向目標：處決是對著敵人做的，背對很突兀。朝向慣例同 _update_lock_facing（atan2(x, z)）。
	var t: Node3D = lock_target if lock_target != null else _nearest_enemy()
	if t != null and is_instance_valid(t):
		var to := t.global_position - global_position
		to.y = 0.0
		if to.length_squared() > 0.0004:
			var want := atan2(to.x, to.z)
			if _visual != null:
				_visual.global_rotation.y = want
			global_rotation.y = want
	var spd := maxf(deathblow_speed, 0.01)
	var dur := 1.1667
	if _anim.has_animation(deathblow_anim):
		dur = _anim.get_animation(deathblow_anim).length
	_deathblow_left = maxf(dur, 0.05) / spd
	velocity.x = 0.0
	velocity.z = 0.0
	# 演出期間不讀操作；是我們鎖的才由我們解，不覆蓋對話／過場已持有的鎖。
	if not input_locked:
		input_locked = true
		_deathblow_lock_owned = true
	if _tree != null:
		# 忍殺是全身技：上半身的架勢／居合同時淡掉，否則會疊在舉刀姿勢上。
		_fade_upper()
		if _anim.has_animation(deathblow_anim):
			# fadein 縮到 0.04：素材開頭 3 格已經壓成 Idle 姿（見 align 工具的 --head-hold），
			# 進場幾乎無姿差，淡得短就不會有「半彎膝＋半高髖」的混合過渡把腳往下推
			# （實測 fadein 0.10 時入場沉 25 mm，遊戲自己的普攻只沉 4 mm）。
			if _full_node:
				_full_node.fadein_time = 0.04
			_fire_full("deathblow", spd)


# ---------------------------------------------------------------------------
# Guard / Deflect（隻狼式防禦）
# ---------------------------------------------------------------------------

## 舉刀格擋。按下的瞬間開啟彈刀窗口。
func begin_guard() -> void:
	if not guard_enabled or posture == null:
		return
	# 出招、翻滾、收刀狀態下架不起來 —— 攻防不能同時。
	# 蓄力／衝刺也擋：begin_guard 會寫 upper_sel=guard，凍住（ts_upper 0）的舉刀會被換成凍住的架勢。
	if action_state != ActionState.FREE or _heavy_charging or _iai_unfreeze_in >= 0.0:
		return
	if sword_state != SwordState.DRAWN:
		return
	if posture.is_dead() or posture.is_broken():
		return
	if _guard_held:
		return
	_guard_held = true
	_guard_started_msec = Time.get_ticks_msec()
	_guard_react_left = -1.0
	_play_guard_pose()
	guard_state_changed.emit(true)


## 架勢：upper 層 one-shot 播 Guard_Hold（idle→架勢 0.5 s），播完停在最後一幀
## 直到放開。格擋／彈刀 one-shot 結束後也由此切回。
func _play_guard_pose() -> void:
	if _tree == null or not _anim.has_animation(guard_anim):
		return
	# fadeout 0：OneShot 在「剩餘時間 < fadeout」就開始淡出並結束，會在切到
	# guard_hold 之前把整層收掉（實測 block 切換後 5 幀 active=false）。
	# 放開格擋時 end_guard 再把 fadeout 設回 0.16 才請求 FADE_OUT。
	if _upper_node:
		_upper_node.fadeout_time = 0.0
	_tree.set("parameters/upper_sel/transition_request", "guard")
	_tree.set("parameters/ts_upper/scale", guard_anim_speed)
	_tree.set("parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	# 進場段播完 → 切到 guard_hold 循環（同一個 OneShot，不重新 FIRE，不跳姿勢）。
	_guard_react_left = guard_anim_resource.length * GUARD_HOLD_FROM / maxf(guard_anim_speed, 0.01)


## 持續架勢循環（進場或格擋／彈刀之後）。
func _hold_guard_pose() -> void:
	if _tree == null:
		return
	_tree.set("parameters/upper_sel/transition_request", "guard_hold")
	_tree.set("parameters/ts_upper/scale", 1.0)
	if not _tree.get("parameters/upper/active"):
		_tree.set("parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## 格擋受衝／彈刀：upper 層短 one-shot，結束後回 Guard_Hold（若仍按著）。
func _play_guard_react(input_name: String, speed: float, clip_len: float) -> void:
	if _tree == null:
		return
	if _upper_node:
		_upper_node.fadeout_time = 0.0
	_tree.set("parameters/upper_sel/transition_request", input_name)
	_tree.set("parameters/ts_upper/scale", speed)
	if not _tree.get("parameters/upper/active"):
		_tree.set("parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	# 稍早於 clip 結束切回 guard_hold（xfade 0.035 s），避免 OneShot 先結束淡回 loco。
	_guard_react_left = clip_len / maxf(speed, 0.01) - 0.05


func end_guard() -> void:
	if not _guard_held:
		return
	_guard_held = false
	_guard_started_msec = -1
	_guard_react_left = -1.0
	if _tree != null and _tree.get("parameters/upper/active") and action_state == ActionState.FREE:
		if _upper_node:
			_upper_node.fadeout_time = 0.16
		_fade_upper()
	guard_state_changed.emit(false)


func is_guarding() -> bool:
	return _guard_held


## 彈刀窗口是否還開著（按下格擋後的極短時間）。
func in_deflect_window() -> bool:
	if not _guard_held or _guard_started_msec < 0:
		return false
	return (Time.get_ticks_msec() - _guard_started_msec) <= int(deflect_window * 1000.0)


## 翻滾無敵幀：隻狼式戰鬥裡翻滾是「解法」而不是「位移」。
## 窗口以翻滾進度比例表示（0 = 起翻、1 = 收招），改 roll_animation_speed
## 不會讓無敵幀跟著跑掉。半開區間 [start, end)，故 end = 0 就是全關。
func in_dodge_invuln() -> bool:
	if action_state != ActionState.DODGING or _roll_duration <= 0.0:
		return false
	var t := clampf(_action_elapsed / _roll_duration, 0.0, 1.0)
	return t >= dodge_invuln_start and t < dodge_invuln_end


## 受擊入口。回傳 {result, damage, posture, attacker_posture}。
## result: "deflect" | "block" | "hit"
func take_hit(hit_data: Dictionary) -> Dictionary:
	if posture == null or posture.is_dead():
		return {"result": "hit", "damage": 0.0, "posture": 0.0, "attacker_posture": 0.0}

	# 翻滾無敵幀先於一切防禦判定 —— 這是隻狼式戰鬥的第三種解法。
	if in_dodge_invuln():
		if _character_audio != null:
			_character_audio.play_roll()
		add_breath(dodge_success_breath)
		if dodge_slowmo_time > 0.0 and dodge_slowmo_scale < 1.0:
			_slowmo_left = dodge_slowmo_time
			Engine.time_scale = dodge_slowmo_scale
		var dodged := {"result": "dodge", "damage": 0.0, "posture": 0.0, "attacker_posture": 0.0}
		player_was_hit.emit(dodged)
		return dodged

	var damage: float = float(hit_data.get("damage", 10.0))
	var posture_damage: float = float(hit_data.get("posture_damage", damage * 0.6))
	var perilous: bool = bool(hit_data.get("perilous", false))
	var hit_pos: Vector3 = hit_data.get("hit_pos", global_position + Vector3(0, 1.1, 0))
	var hit_dir: Vector3 = hit_data.get("hit_dir", -global_transform.basis.z)
	_last_hit_dir = hit_dir

	var result := "hit"
	var dealt := damage
	var self_posture := posture_damage * unguarded_posture_mult
	var attacker_posture := 0.0

	if _guard_held:
		if perilous:
			# 危攻擊架得住，但代價極高 —— 逼玩家改用見切／跳躍／閃避。
			result = "block"
			dealt = damage * perilous_block_damage_ratio
			self_posture = perilous_block_posture
		elif in_deflect_window():
			result = "deflect"
			dealt = 0.0
			self_posture = deflect_self_posture
			attacker_posture = deflect_attacker_posture
			if counter_form != 0:
				_counter_until_msec = Time.get_ticks_msec() + int(counter_window * 1000.0)
		else:
			result = "block"
			dealt = damage * block_damage_ratio
			self_posture = block_self_posture
			attacker_posture = block_attacker_posture

	posture.apply_damage(dealt, self_posture)

	# 彈刀／格擋累積呼吸 —— 防禦不是純挨打，是攢下一型的資源。
	if result == "deflect":
		add_breath(breath_gain_on_deflect)
	elif result == "block":
		add_breath(breath_gain_on_block)

	# 回饋：彈刀是金屬火花與清脆撞擊，格擋是悶響，未防禦是受擊。
	if _character_audio != null:
		if result == "deflect" and _character_audio.has_method("play_deflect"):
			_character_audio.play_deflect()
		elif result == "block" and _character_audio.has_method("play_block"):
			_character_audio.play_block()
	if result == "deflect":
		CombatVFX.spawn_hit_spark(self, hit_pos, hit_dir, true)
	elif result == "block":
		CombatVFX.spawn_hit_spark(self, hit_pos, hit_dir, false)

	var out := {
		"result": result,
		"damage": dealt,
		"posture": self_posture,
		"attacker_posture": attacker_posture,
	}
	_apply_hit_reaction(result, hit_dir)
	player_was_hit.emit(out)
	return out


## 受擊／格擋／彈刀的反應。三種結果的代價差很多，回饋也要差很多 ——
## 玩家必須在 0.2 秒內分辨自己彈到了、擋住了、還是被打到。
## 素材未到位（緣一沒有受擊動作），全部是程式演出：位移＋硬直＋鏡頭震動。
func _apply_hit_reaction(result: String, hit_dir: Vector3) -> void:
	var dir := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if dir.length_squared() < 0.0001:
		var f := -global_transform.basis.z
		dir = Vector3(f.x, 0.0, f.z)
	dir = dir.normalized()
	var distance := hit_knockback
	var stun := hit_stun_time
	var shake := hit_shake_strength
	var shake_time := hit_shake_time
	match result:
		"deflect":
			distance = deflect_knockback
			stun = 0.0
			shake = deflect_shake_strength
			shake_time = deflect_shake_time
		"block":
			distance = block_knockback
			stun = 0.0
	# 動畫：彈刀／格擋走 upper 層（腿照常），受擊走 full 層。
	match result:
		"deflect":
			if _anim.has_animation(deflect_anim):
				_play_guard_react("deflect", deflect_anim_speed, _anim.get_animation(deflect_anim).length)
		"block":
			if _anim.has_animation(block_anim):
				_play_guard_react("block", block_anim_speed, _anim.get_animation(block_anim).length)
		"hit":
			# apply_damage 已先跑：若這一下打爆軀幹或致死，stagger/dead 已在 full 層，不要蓋掉。
			if _anim.has_animation(hit_react_anim) and not posture.is_broken() and not posture.is_dead():
				_fire_full("hit", hit_react_speed)
	# 硬直：中斷攻擊與翻滾。不碰 input_locked（那是對話／過場的介面）。
	# 蓄力／衝刺被打到一律收招（即使 hit_stun_time 調成 0）：凍住的舉刀不能帶著傷繼續蓄。
	if result == "hit" and (_heavy_charging or _iai_unfreeze_in >= 0.0 or _iai_dash_remaining > 0.0):
		_finish_attack()
	if stun > 0.0:
		if action_state == ActionState.ATTACKING:
			_finish_attack()
		elif action_state == ActionState.DODGING:
			_finish_roll()
		_hitstun_left = maxf(_hitstun_left, stun)
	# 位移：線性衰減下總位移 = ½·v·t，故 v = 2·d / t。
	# 格擋／彈刀沒有硬直，但一樣要有位移，否則防禦看起來像「穿過去」。
	if distance > 0.0:
		var dur := maxf(stun, 0.18)
		_knockback = dir * (2.0 * distance / dur)
		_knockback_total = dur
		_knockback_left = dur
	if _hit_feedback != null:
		_hit_feedback.shake(shake, shake_time)
	if _character_audio != null and result == "hit":
		_character_audio.play_hurt()


## 受擊位移。回傳本幀是否有受擊位移（呼叫端據此決定誰覆寫速度）。
func _apply_knockback(delta: float) -> bool:
	if _knockback_left <= 0.0:
		return false
	_knockback_left = maxf(_knockback_left - delta, 0.0)
	var k: float = _knockback_left / maxf(_knockback_total, 0.001)
	velocity.x = _knockback.x * k
	velocity.z = _knockback.z * k
	if _knockback_left <= 0.0:
		_knockback = Vector3.ZERO
	return true


func _on_hit_target(node: Node) -> void:
	if action_state != ActionState.ATTACKING:
		return
	if node == self or is_ancestor_of(node) or node.is_ancestor_of(self):
		return
	# 先解析真正的受擊者再去重：敵人本體（CharacterBody3D）與它的 Hurtbox（Area3D）會在同一揮
	# 各觸發一次 body_entered / area_entered，以原始 node 當 key 會讓一刀打兩次（實測 35 → 70）。
	var receiver: Node = node
	if not receiver.has_method("take_hit") and receiver.get_parent() != null \
			and receiver.get_parent().has_method("take_hit"):
		receiver = receiver.get_parent()
	if _hit_targets_this_swing.has(receiver):
		return
	_hit_targets_this_swing[receiver] = true

	var is_heavy: bool = (_attack_layer == "full" or combo_stage == 0)
	var is_spin: bool = (_active_attack_name == attack_continuous_spin_anim or _active_attack_name == attack_spin_anim)
	_hitstop_time = 0.07 if is_heavy else 0.05

	# 傷害 = 基礎（輕／重）× 型倍率 × 破綻加成。
	# 型倍率讀 FORMS.damage —— 柒型 1.8 要真的比壹型 1.0 痛，
	# 否則選單挑招只是換動畫，沒有取捨。
	var damage: float = heavy_attack_damage if is_heavy else light_attack_damage
	var pdmg: float = heavy_posture_damage if is_heavy else light_posture_damage
	if active_form != 0 and SunBreathing.FORMS.has(active_form):
		var mult: float = float(SunBreathing.FORMS[active_form].damage)
		damage *= mult
		pdmg *= mult
	if _iai_charged:
		# 蓄力拔刀斬：三秒的代價換一刀重擊。hitstop 與鏡頭震動也比普通重斬大。
		damage *= heavy_charge_damage_mult
		pdmg *= heavy_charge_posture_mult
		_hitstop_time = 0.12
		if _hit_feedback != null:
			_hit_feedback.shake(hit_shake_strength * 0.8, 0.25)

	var hit_pos: Vector3 = _blade_tip.global_position if _blade_tip != null else global_position + Vector3(0, 1, 0)
	var fwd := _visual.global_transform.basis.z if _visual != null else -global_transform.basis.z
	var hit_data := {
		"damage": damage,
		"posture_damage": pdmg,
		"hit_pos": hit_pos,
		"hit_dir": fwd,
		"heavy": is_heavy,
		"charged": _iai_charged,
	}
	if receiver.has_method("take_hit"):
		receiver.take_hit(hit_data)
		_character_audio.play_fire_hit(is_heavy, is_spin, combo_stage)
		add_breath(breath_gain_on_hit)
	else:
		CombatVFX.spawn_hit_spark(self, hit_pos, -fwd, is_heavy)

func _library() -> AnimationLibrary:
	var lib_name: StringName = _anim.get_animation_library_list()[0] if _anim.get_animation_library_list().size() > 0 else &""
	if not _anim.has_animation_library(lib_name):
		_anim.add_animation_library(lib_name, AnimationLibrary.new())
	return _anim.get_animation_library(lib_name)

func _add_animation_resource(animation_name: String, animation: Animation) -> void:
	if animation_name == "" or animation == null or _anim.has_animation(animation_name):
		return
	_library().add_animation(animation_name, animation)

# --- AnimationTree ---------------------------------------------------------
func _anim_node(name: String, backward := false) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = name
	if backward:
		n.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
	return n

func _clip_node(name: String, from: float, to: float, loop := false) -> AnimationNodeAnimation:
	var n := _anim_node(name)
	n.use_custom_timeline = true
	n.start_offset = from
	n.timeline_length = to - from
	n.stretch_time_scale = false
	n.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return n

## 內含 TimeScale 的單動畫子樹（給需要獨立倍率的 SM 狀態）。
## scale 是 AnimationTree 的 runtime 參數，樹啟用後由 parameters/loco/<state>/ts/scale 設定。
func _scaled_state(clip: AnimationNodeAnimation) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("anim", clip)
	bt.add_node("ts", AnimationNodeTimeScale.new())
	bt.connect_node("ts", 0, "anim")
	bt.connect_node("output", 0, "ts")
	return bt

func _build_tree() -> void:
	var root := AnimationNodeBlendTree.new()

	# --- loco state machine ---
	var sm := AnimationNodeStateMachine.new()
	var states := {
		"Idle": _anim_node(idle_anim),
		"Walk": _scaled_state(_anim_node(walk_anim)),
		"Run": _scaled_state(_anim_node(run_fast_anim)),
		"Sprint": _scaled_state(_anim_node(sprint_anim)),
		"JumpStart": _scaled_state(_clip_node(jump_anim, jump_start_skip, jump_anim_resource.length)),
		"Fall": _anim_node(fall_anim),
		"Land": _scaled_state(_anim_node(land_anim)),
	}
	if _fl_anim != "" and _anim.has_animation(_fl_anim):
		states["RunFL"] = _anim_node(_fl_anim)
	if _fr_anim != "" and _anim.has_animation(_fr_anim):
		states["RunFR"] = _anim_node(_fr_anim)
	# 後退步：Walking 是零位移的完美循環，反播即為合法 backpedal，不需新動畫。
	states["BackPedal"] = _anim_node(walk_anim, true)
	if drawn_locomotion_enabled:
		for dk in DRAWN_CLIPS:
			if _anim.has_animation(dk):
				states[dk] = _scaled_state(_anim_node(dk))
		if _anim.has_animation("D_Run"):
			states["D_Sprint"] = _scaled_state(_anim_node("D_Run"))
	for s in states:
		sm.add_node(s, states[s])
	for a in states:
		for b in states:
			if a == b:
				continue
			var tr := AnimationNodeStateMachineTransition.new()
			tr.xfade_time = blend_time
			if b == "JumpStart" or b == "Land":
				tr.xfade_time = 0.08
			elif b == "Fall":
				tr.xfade_time = 0.15
			sm.add_transition(a, b, tr)
	root.add_node("loco", sm)

	# --- upper one-shot（bone filter：上半身） ---
	var upper_sel := AnimationNodeTransition.new()
	var combo_len := attack_combo_resource.length
	var upper_inputs := {
		"draw": _anim_node(draw_anim),
		"sheathe": _anim_node(draw_anim, true),
		"atk1": _clip_node(attack_combo_anim, combo_len * COMBO_SECTION_RANGES[0].x, combo_len * COMBO_SECTION_RANGES[0].y),
		"atk2": _clip_node(attack_combo_anim, combo_len * COMBO_SECTION_RANGES[1].x, combo_len * COMBO_SECTION_RANGES[1].y),
		"atk3": _clip_node(attack_combo_anim, combo_len * COMBO_SECTION_RANGES[2].x, combo_len * COMBO_SECTION_RANGES[2].y),
		"heavy": _anim_node("Heavy_Cut") if _anim.has_animation("Heavy_Cut") else _clip_node(attack_combo_anim, 0.0, combo_len * COMBO_SECTION_RANGES[0].y),
		"guard": _anim_node(guard_anim),
		# 持續架勢：Guard_Hold 末段（f7~f12 全是架勢幀）循環 —— OneShot 有循環子節點就不會自己結束。
		"guard_hold": _clip_node(guard_anim, guard_anim_resource.length * GUARD_HOLD_FROM, guard_anim_resource.length, true),
		"block": _anim_node(block_anim),
		"deflect": _anim_node(deflect_anim),
	}
	_setup_transition(root, upper_sel, "upper_sel", upper_inputs)
	var ts_upper := AnimationNodeTimeScale.new()
	root.add_node("ts_upper", ts_upper)
	root.connect_node("ts_upper", 0, "upper_sel")
	var upper := AnimationNodeOneShot.new()
	upper.fadein_time = 0.06
	upper.fadeout_time = 0.1
	upper.filter_enabled = true
	for path in _upper_filter_paths():
		upper.set_filter_path(path, true)
	root.add_node("upper", upper)
	root.connect_node("upper", 0, "loco")
	root.connect_node("upper", 1, "ts_upper")
	_upper_node = upper

	# --- full-body one-shot ---
	var full_sel := AnimationNodeTransition.new()
	var full_inputs := {
		"roll": _anim_node(roll_anim),
		"spin": _anim_node(attack_spin_anim),
		"continuous_spin": _anim_node(attack_continuous_spin_anim),
		"judgment": _anim_node(attack_judgment_anim),
		"combo1": _anim_node(attack_combo_1_anim),
		"spinjump": _anim_node(attack_spin_jump_anim),
		"thrust": _anim_node(attack_thrust_anim),
		"form05": _anim_node(attack_form05_anim),
		"form06": _anim_node(attack_form06_anim),
		"form11": _anim_node(attack_form11_anim),
		"form12": _anim_node(attack_form12_anim),
		# 居合蓄力（RMB 長按）：iai_in = Stance 進姿段（0→kamae_t），iai_hold = kamae 呼吸循環
		# （OneShot 有循環子節點就不會自己結束，同 guard_hold 的寫法），iai_slash = 拔刀斬。
		"iai_in": _clip_node(iai_stance_anim, 0.0, iai_kamae_t),
		"iai_hold": _clip_node(iai_stance_anim, iai_kamae_t, iai_stance_resource.length, true),
		"iai_slash": _anim_node(iai_slash_anim),
		"hit": _anim_node(hit_react_anim),
		"stagger": _anim_node(stagger_anim),
		"stagger_front": _anim_node(stagger_front_anim),
		"stagger_back": _anim_node(stagger_back_anim),
		"stagger_left": _anim_node(stagger_left_anim),
		"stagger_right": _anim_node(stagger_right_anim),
		# 忍殺：素材本身已經是切好並對齊 Idle 的 1.17 s，不必再用子區段。
		"deathblow": _anim_node(deathblow_anim),
		"dead": _anim_node(dead_anim),
		"run_turn": _anim_node("Run_Turn"),
	}
	for tk in TRAVERSAL_CLIPS:
		full_inputs[tk] = _anim_node(tk)
	for i in idle_break_resources.size():
		full_inputs["idle_break_%d" % i] = _anim_node("Idle_Break_%d" % i)
	_setup_transition(root, full_sel, "full_sel", full_inputs)
	var ts_full := AnimationNodeTimeScale.new()
	root.add_node("ts_full", ts_full)
	root.connect_node("ts_full", 0, "full_sel")
	var full := AnimationNodeOneShot.new()
	# fadein 稍長：全身技進場時垂直姿態漸變，避免「啪」一聲切換。
	full.fadein_time = 0.10
	full.fadeout_time = 0.12
	root.add_node("full", full)
	root.connect_node("full", 0, "upper")
	root.connect_node("full", 1, "ts_full")
	# --- 握拳覆蓋：持刀時右手五指固定成 Great Sword Idle 的握拳（Blend2 + 右手指 filter）。
	var grip := AnimationNodeBlend2.new()
	grip.filter_enabled = true
	for path in _grip_filter_paths():
		grip.set_filter_path(path, true)
	root.add_node("grip", grip)
	# 握拳來源固定用 Great Sword Idle（持刀待機已改單手垂刀 ua_idle_b，其手指是空手鬆開的）。
	_add_animation_resource("D_Grip", grip_pose_resource)
	root.add_node("grip_pose", _anim_node("D_Grip" if _anim.has_animation("D_Grip") else idle_anim))
	root.connect_node("grip", 0, "full")
	root.connect_node("grip", 1, "grip_pose")
	root.connect_node("output", 0, "grip")
	_full_node = full

	_tree = AnimationTree.new()
	_tree.name = "Tree"
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_anim)
	_tree.root_node = _tree.get_path_to(_visual)
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_tree.tree_root = root
	_tree.active = true
	_tree.set("parameters/loco/JumpStart/ts/scale", jump_start_speed)
	_tree.set("parameters/loco/Land/ts/scale", jump_land_speed)
	_tree.set("parameters/loco/Run/ts/scale", run_anim_speed)
	_tree.set("parameters/loco/Walk/ts/scale", walk_anim_speed)
	_tree.set("parameters/loco/Sprint/ts/scale", sprint_anim_speed)
	_tree.set("parameters/grip/blend_amount", 0.0)
	_apply_drawn_speeds()
	_playback().start("Idle")

## 持刀 locomotion 倍率：clip 步速（meta root_speed）對到角色實際速度；原地 clip 維持 1.0。
func _apply_drawn_speeds() -> void:
	if _tree == null or not drawn_locomotion_enabled:
		return
	var want := {"D_Walk": walk_speed, "D_Back": walk_speed, "D_StrafeL": walk_speed, "D_StrafeR": walk_speed,
		"D_StrafeLRun": speed, "D_StrafeRRun": speed, "D_Run": speed, "D_RunBack": speed, "D_Sprint": run_speed}
	for st in want:
		var clip: String = "D_Run" if st == "D_Sprint" else st
		if not _anim.has_animation(clip):
			continue
		var a := _anim.get_animation(clip)
		var rs: float = a.get_meta("root_speed", 0.0)
		var sc := clampf(want[st] / rs, 0.6, 1.8) if rs > 0.3 else 1.0
		_tree.set("parameters/loco/%s/ts/scale" % st, sc)

## 右手五指骨（握拳覆蓋用），路徑相對 AnimationTree root_node = _visual。
func _grip_filter_paths() -> Array[String]:
	var out: Array[String] = []
	var sk := _visual.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return out
	var skel := sk[0] as Skeleton3D
	var base := str(_visual.get_path_to(skel)) + ":"
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i)
		if bn.begins_with("mixamorig_RightHand") and bn != "mixamorig_RightHand":
			out.append(base + bn)
	return out

## upper OneShot 的骨骼 filter 路徑（相對 AnimationTree root_node = _visual）。
## 舊 Meshy 骨架用 UPPER_BONES；v2.4 Mixamo 骨架取 mixamorig_Spine 以下所有骨，
## 排除彈簧骨鏈（Haori／Hair／Cuff／Sleeve，由 SpringBoneSimulator3D 驅動）。
func _upper_filter_paths() -> Array[String]:
	var out: Array[String] = []
	var sks := _visual.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return out
	var sk: Skeleton3D = sks[0]
	var prefix := str(_visual.get_path_to(sk)) + ":"
	var spine := sk.find_bone("mixamorig_Spine")
	if spine < 0:
		for b in UPPER_BONES:
			out.append(prefix + b)
		return out
	for i in sk.get_bone_count():
		var bn := sk.get_bone_name(i)
		if bn.begins_with("Haori") or bn.begins_with("Hair") or bn.begins_with("Cuff") or bn.begins_with("Sleeve"):
			continue
		var p := i
		while p >= 0 and p != spine:
			p = sk.get_bone_parent(p)
		if p == spine:
			out.append(prefix + bn)
	return out

func _setup_transition(root: AnimationNodeBlendTree, sel: AnimationNodeTransition, sel_name: String, inputs: Dictionary) -> void:
	sel.xfade_time = combo_section_blend
	sel.input_count = inputs.size()
	root.add_node(sel_name, sel)
	var i := 0
	for key: String in inputs:
		sel.set_input_name(i, key)
		sel.set_input_reset(i, true)
		var node_name: String = sel_name + "_" + key
		root.add_node(node_name, inputs[key])
		root.connect_node(sel_name, i, node_name)
		i += 1

func _playback() -> AnimationNodeStateMachinePlayback:
	return _tree.get("parameters/loco/playback")

func _fire_upper(input_name: String, time_scale: float) -> void:
	if _upper_node:
		_upper_node.fadeout_time = _upper_finish_fade
	_tree.set("parameters/upper_sel/transition_request", input_name)
	_tree.set("parameters/ts_upper/scale", time_scale)
	# 看 internal_active 而不是 active：OneShot 淡出期間 active 仍為 true、internal_active 已 false，
	# 這時只換 transition 不 FIRE，新招會跟著上一招的淡出一起消失（實測：上一刀剛收、立刻 RMB 蓄力，
	# 舉刀 0.24 s 後整層淡掉回 Idle）。播放中（internal_active true）維持只換段落，連段切段不受影響。
	if not _tree.get("parameters/upper/internal_active"):
		_tree.set("parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

## 全身技的 fadeout 就是「收勢」：結束後姿勢停留在收尾幀、按此時間淡回
## locomotion —— Judgment / Combo_1 收勢長，Roll 要能立刻接行動。
func _fire_full(input_name: String, time_scale: float) -> void:
	if not input_name.begins_with("idle_break"):
		_idle_break_on = false   # 別的全身動作接手：待機小動作的淡出不能再去關它
		_run_turn_left = 0.0
	if _full_node:
		match input_name:
			"judgment":
				_full_node.fadeout_time = 0.32
			"combo1":
				_full_node.fadeout_time = 0.30
			"spin":
				_full_node.fadeout_time = 0.20
			"continuous_spin":
				_full_node.fadeout_time = 0.22
			"spinjump":
				_full_node.fadeout_time = 0.16
			"thrust":
				# 突刺的收勢：刀尖停住 → 慢慢收回架勢，不能急切
				_full_node.fadeout_time = 0.28
			"form05", "form06", "form11":
				_full_node.fadeout_time = 0.22
			"form12":
				_full_node.fadeout_time = 0.26
			"iai_in":
				# 進姿段結束即切 iai_hold（transition xfade 0.035 接手），OneShot 淡出用不到。
				_full_node.fadeout_time = 0.06
			"iai_hold":
				# 蓄力取消／未滿放開：架勢淡回 locomotion，不能瞬切。
				_full_node.fadeout_time = 0.18
			"iai_slash":
				# 殘心 → Idle：比聚力單斬收勢更長（拔刀斬的份量）。
				_full_node.fadeout_time = 0.30
			"hit":
				_full_node.fadeout_time = 0.14
			"stagger", "stagger_front", "stagger_back", "stagger_left", "stagger_right":
				_full_node.fadeout_time = 0.30
			"deathblow":
				# 忍殺收勢用短淡出：素材最後 8 格已對齊 Idle（見 align 工具的 --tail），所以短淡
				# 就夠。淡出視窗越長越糟 —— 「clip 姿 ↔ Idle」在關節角上混合會把腳往下推，
				# 實測 0.22 s 沉 25 mm、0.06 s 沉 5.6 mm、硬切 6.3 mm（硬切沒比較好，且換素材會跳）。
				_full_node.fadeout_time = 0.06
			"dead":
				_full_node.fadeout_time = 0.0
			_:
				_full_node.fadeout_time = 0.12
		# 忍殺會把 fadein 調短；這裡還原成標準值，避免後面的招式沿用（只還原，不覆寫特殊值）。
		if input_name != "deathblow":
			_full_node.fadein_time = 0.10
	_tree.set("parameters/full_sel/transition_request", input_name)
	_tree.set("parameters/ts_full/scale", time_scale)
	_tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _fade_upper() -> void:
	_tree.set("parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)

func _fade_full() -> void:
	_tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)

## 同 _fire_full，但 OneShot 播放中只換段落、不重啟（transition xfade 接手）。
## iai_in → iai_hold 用：FIRE 會重播 fadein，架勢會被彈回 Idle 一下。
## fadeout_time 也要跟著換：_fire_full 的表不會重跑，iai_in 的 0.06 殘值會讓
## 取消／落刀結束的淡出變成瞬切。
func _switch_full(input_name: String, time_scale: float) -> void:
	if _full_node:
		match input_name:
			"iai_hold":
				_full_node.fadeout_time = 0.18
			"iai_slash":
				_full_node.fadeout_time = 0.30
	_tree.set("parameters/full_sel/transition_request", input_name)
	_tree.set("parameters/ts_full/scale", time_scale)
	if not _tree.get("parameters/full/internal_active"):
		_tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

## 軀幹被打爆時要播哪一支方向性反應。dir = 受擊推力方向（玩家被推走的方向），
## 所以攻擊來自 -dir；以角色的前／右為軸切四個 45° 楔形。
## 回傳的是 AnimationTree 的**段落鍵**（full_sel_<鍵>），不是 clip 名稱 ——
## _fire_full() 吃的是段落鍵；給錯會噴 "No such input" 且整個反應不會播。
## 關掉 stagger_directional、或沒有方向資料（例如非戰鬥來源直接打爆軀幹）時，
## 退回原本單一的 stagger 段落。
func stagger_key_for_dir(dir: Vector3) -> String:
	if not stagger_directional:
		return "stagger"
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return "stagger"
	var from := -flat.normalized()
	var bf := -global_transform.basis.z
	var br := global_transform.basis.x
	var f := Vector3(bf.x, 0.0, bf.z)
	var r := Vector3(br.x, 0.0, br.z)
	if f.length_squared() < 0.0001 or r.length_squared() < 0.0001:
		return "stagger"
	f = f.normalized()
	r = r.normalized()
	var fd := f.dot(from)
	var rd := r.dot(from)
	if absf(fd) >= absf(rd):
		return "stagger_front" if fd > 0.0 else "stagger_back"
	return "stagger_right" if rd > 0.0 else "stagger_left"


## 段落鍵 → clip 名稱（量長度、檢查是否註冊時用）。
func stagger_anim_for_key(key: String) -> String:
	match key:
		"stagger_front":
			return stagger_front_anim
		"stagger_back":
			return stagger_back_anim
		"stagger_left":
			return stagger_left_anim
		"stagger_right":
			return stagger_right_anim
	return stagger_anim


## 玩家軀幹被打爆：硬直，攻防全斷。隻狼的規則是此時可被忍殺 ——
## 敵人的處決動畫還沒有，先做成「動不了的懲罰窗口」，破綻結束自動恢復。
func _on_self_posture_broken() -> void:
	_stagger_left = posture.break_time
	end_guard()
	if action_state == ActionState.ATTACKING:
		_finish_attack()
	elif action_state == ActionState.DODGING:
		_finish_roll()
	velocity.x = 0.0
	velocity.z = 0.0
	# 軀幹爆動畫 2.0 s 對上 break_time；break_time 被改時等比縮放，破綻結束正好站回。
	var key := stagger_key_for_dir(_last_hit_dir)
	var clip_name := stagger_anim_for_key(key)
	if _tree != null and _anim.has_animation(clip_name):
		var clip_len := _anim.get_animation(clip_name).length
		_fire_full(key, clip_len / maxf(posture.break_time, 0.05))
	player_posture_broken.emit()


## 重生：還原死亡定格（Tree 重開、播放倍率還原、回 Idle）、血量全滿、解除鎖輸入。
## 位置由呼叫端（main.gd）決定。
func revive() -> void:
	_dead_left = -1.0
	_slowmo_left = 0.0
	Engine.time_scale = 1.0
	_counter_until_msec = -1
	_form13_queue.clear()
	_form13_running = false
	_hitstun_left = 0.0
	_stagger_left = 0.0
	_knockback = Vector3.ZERO
	_knockback_left = 0.0
	velocity = Vector3.ZERO
	end_guard()
	if action_state == ActionState.ATTACKING:
		_finish_attack()
	elif action_state == ActionState.DODGING:
		_finish_roll()
	if _anim != null:
		_anim.speed_scale = 1.0
		_anim.stop()
	if _tree != null:
		_tree.active = true
		_tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		_tree.set("parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		_playback().start("Idle")
	if posture != null:
		posture.heal_full()
	set_lock_target(null)
	input_locked = false


## 倒地定格：關掉 AnimationTree，AnimationPlayer 直接 seek 到 Dead 最後一幀。
func _freeze_dead_pose() -> void:
	if _tree != null:
		_tree.active = false
	if _anim != null and _anim.has_animation(dead_anim):
		_anim.play(dead_anim)
		_anim.seek(_anim.get_animation(dead_anim).length, true)
		# 不用 pause()（會清掉 current_animation，存讀檔／除錯看不出停在哪）：
		# 以 speed_scale 0 定格在末幀；復活流程要記得還原 speed_scale 與 Tree.active。
		_anim.speed_scale = 0.0


## 開場仰躺定格：關閉 Tree，定格在 Dead 末幀（平躺面朝天），鎖定輸入與速度。
func start_opening_lie_down() -> void:
	input_locked = true
	velocity = Vector3.ZERO
	_freeze_dead_pose()


## 爬起動作：從仰躺反向播放 Dead clip，撐地挺身站立，隨後平滑切回 Idle 與 AnimationTree。
func play_get_up(speed: float = 1.15) -> float:
	# v2.4：有專用起身（Getting Up From Back）就正播它；首格＝仰躺，接得上 Dead 末格。
	if _anim != null and _anim.has_animation("Get_Up"):
		_anim.speed_scale = speed * get_up_speed
		_anim.play("Get_Up")
		var gdur: float = _anim.get_animation("Get_Up").length / maxf(speed * get_up_speed, 0.1)
		get_tree().create_timer(gdur).timeout.connect(finish_get_up)
		return gdur
	if _anim != null and _anim.has_animation(dead_anim):
		_anim.speed_scale = speed
		_anim.play_backwards(dead_anim)
		var dur: float = _anim.get_animation(dead_anim).length / maxf(speed, 0.1)
		get_tree().create_timer(dur).timeout.connect(finish_get_up)
		return dur
	finish_get_up()
	return 0.0


func finish_get_up() -> void:
	if _anim != null:
		_anim.speed_scale = 1.0
		_anim.stop()
	if _tree != null:
		_tree.active = true
		_tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		_tree.set("parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		_playback().start("Idle")
	input_locked = false


## ── 冥想擺姿 ────────────────────────────────────────────────────────────
## 坐下調息：關掉 AnimationTree、AnimationPlayer 直接播打坐 clip 並定格
## （跟倒地定格同一招）。有循環的 clip（呼吸）就讓它繼續跑。
## ⚠ 打坐 clip 還沒生出來時**退回站姿**：冥想系統（時間快轉、運鏡）不該被
##   一個動畫卡住，姿勢是可以獨立補的。
func start_meditation_pose() -> void:
	input_locked = true
	velocity = Vector3.ZERO
	if _anim == null or not _anim.has_animation(meditate_anim):
		return
	if _tree != null:
		_tree.active = false
	var clip := _anim.get_animation(meditate_anim)
	_anim.play(meditate_anim)
	if clip.loop_mode == Animation.LOOP_NONE:
		_anim.seek(clip.length, true)
		_anim.speed_scale = 0.0     # speed_scale 0 定格（不用 pause，除錯看得到停在哪）
	else:
		_anim.speed_scale = 1.0


## 出定：跟爬起共用同一條收尾（還原 speed_scale、開回 Tree、回 Idle、解鎖）。
func end_meditation_pose() -> void:
	finish_get_up()


func _on_self_posture_recovered() -> void:
	_stagger_left = 0.0
	player_posture_recovered.emit()


func _on_self_died() -> void:
	_stagger_left = 0.0
	end_guard()
	if action_state == ActionState.ATTACKING:
		_finish_attack()
	elif action_state == ActionState.DODGING:
		_finish_roll()
	input_locked = true
	velocity.x = 0.0
	velocity.z = 0.0
	if _character_audio != null:
		_character_audio.play_death_collapse()
	# 死亡倒地：full 層播 Dead，播完由 _physics_process 關掉 AnimationTree，
	# 讓 AnimationPlayer 停在倒地最後一幀（OneShot 結束會淡回 locomotion，不能靠它）。
	if _tree != null and _anim.has_animation(dead_anim):
		_fire_full("dead", dead_anim_speed)
		_dead_left = _anim.get_animation(dead_anim).length / maxf(dead_anim_speed, 0.01)
	player_died.emit()


# ---------------------------------------------------------------------------
# Physics
# ---------------------------------------------------------------------------
func _physics_process(delta):
	# 死亡：倒地動畫播到底就凍住，之後什麼都不做。
	if _dead_left >= 0.0:
		_dead_left -= delta
		if _dead_left <= 0.0:
			_dead_left = -1.0
			_freeze_dead_pose()
		if not is_on_floor():
			velocity.y -= gravity * delta
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	if posture != null and posture.is_dead():
		return
	# 格擋／彈刀 one-shot 播完 → 仍按著就回架勢。
	if _guard_react_left >= 0.0:
		_guard_react_left -= delta
		if _guard_react_left <= 0.0:
			_guard_react_left = -1.0
			if _guard_held:
				_hold_guard_pose()
	# 閃避成功的時間減速：用真實時間倒數（delta 已被 time_scale 縮過）。
	if _slowmo_left > 0.0:
		_slowmo_left -= delta / maxf(Engine.time_scale, 0.01)
		if _slowmo_left <= 0.0:
			_slowmo_left = 0.0
			Engine.time_scale = 1.0
	# 型冷卻：與 ActionState 無關，永遠在跑。
	if not _form_cooldowns.is_empty():
		for id in _form_cooldowns.keys():
			var left: float = float(_form_cooldowns[id]) - delta
			if left <= 0.0:
				_form_cooldowns.erase(id)
			else:
				_form_cooldowns[id] = left
	# 軀幹爆掉的硬直／忍殺演出：只跑重力，不讀輸入、不動作。
	if _stagger_left > 0.0 or _deathblow_left > 0.0:
		_stagger_left = maxf(_stagger_left - delta, 0.0)
		# 忍殺演出走同一條（不新增系統）；放完才把操作權還回去。
		if _deathblow_left > 0.0:
			_deathblow_left = maxf(_deathblow_left - delta, 0.0)
			if _deathblow_left <= 0.0 and _deathblow_lock_owned:
				input_locked = false
				_deathblow_lock_owned = false
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
		move_and_slide()
		return
	# 受擊硬直：只跑重力與受擊位移，不讀輸入、不動作 —— 但 HUD 與對話照常。
	if _hitstun_left > 0.0:
		_hitstun_left = maxf(_hitstun_left - delta, 0.0)
		if not _apply_knockback(delta):
			velocity.x = 0.0
			velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
		move_and_slide()
		_update_sword(delta)
		if _tree:
			_update_locomotion(delta, Vector3.ZERO, is_on_floor(), false, false)
		return
	_update_lock_on(delta)
	var input_dir := _read_input_dir()
	if _hitstop_time > 0.0:
		_hitstop_time = maxf(_hitstop_time - delta, 0.0)
		if input_dir.length_squared() > 0.0 and _attack_layer == "upper":
			move_and_slide()
		return
	var grounded := is_on_floor()
	var running := Input.is_action_pressed("sprint") and not input_locked
	_walking = not running and InputMap.has_action("walk") and Input.is_action_pressed("walk") and not input_locked
	var cur_speed := run_speed if running else (walk_speed if _walking else speed)
	var moving := input_dir.length_squared() > 0.0
	# 特技（攀牆／翻越）期間位置由 root_path 驅動，不跑一般物理。
	if _update_traversal(delta, input_dir, grounded, moving, running):
		return

	# --- 水平速度 ---
	if action_state == ActionState.DODGING:
		_update_roll_movement(delta)
	elif not grounded:
		_apply_air_control(input_dir, cur_speed, delta)
	elif action_state == ActionState.ATTACKING:
		var f := attack_move_factor_heavy if _attack_layer == "full" else 1.0
		if _apply_iai_dash(delta):
			pass
		elif _heavy_charging:
			# 蓄力進姿段（atk1 舉刀）還能慢走瞄準；切入居合架勢後腳要紮穩
			# （full 層全身 override，腿是 clip 的弓步——再給移動速度會變成滑行）。
			if _heavy_frozen:
				velocity.x = 0.0
				velocity.z = 0.0
			else:
				velocity.x = input_dir.x * speed * 0.35
				velocity.z = input_dir.z * speed * 0.35
		elif _form_dash_left > 0.0 and _form_dash_total > 0.0:
			# 型的起手衝刺：dash 佔比線性衰減，輸入慢慢接手。
			_form_dash_left = maxf(_form_dash_left - delta, 0.0)
			var k := _form_dash_left / _form_dash_total
			velocity.x = _form_dash.x * k + input_dir.x * cur_speed * f * (1.0 - k)
			velocity.z = _form_dash.z * k + input_dir.z * cur_speed * f * (1.0 - k)
		else:
			velocity.x = input_dir.x * cur_speed * f
			velocity.z = input_dir.z * cur_speed * f
	elif _land_lock_move > 0.0:
		# 落地翻滾：沿落地前的面向往前滾；重落地：原地蹲穩。
		var roll_v := _land_roll_dir * speed
		velocity.x = roll_v.x
		velocity.z = roll_v.z
	else:
		var tf := _run_turn_speed_factor()
		velocity.x = input_dir.x * cur_speed * tf
		velocity.z = input_dir.z * cur_speed * tf

	# 受擊位移優先於一切水平控制：被打退時不能靠輸入走回來。
	_apply_knockback(delta)

	if not grounded:
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	# 跳躍蓄力是純 physics 倒數：與 ActionState 無關，攻擊/拔刀都打不斷。
	if _jump_charge >= 0.0:
		_jump_charge -= delta
		if _jump_charge <= 0.0:
			_jump_charge = -1.0
			velocity.y = jump_velocity
			CombatVFX.spawn_jump_dust(self, global_position)

	# Gate on "not in a jump" rather than is_on_floor(): pressed against a
	# 46° lip the body reports on_wall / off-floor while its feet are on the
	# ground (probe_step_up 2026-09-03).
	if _jump_charge < 0.0 and velocity.y <= 0.0:
		_try_step_up(delta)
	move_and_slide()

	if action_state == ActionState.DODGING:
		if _action_elapsed >= _roll_duration:
			_finish_roll()
	elif action_state == ActionState.ATTACKING:
		_update_attack(delta, input_dir)

	_update_sword(delta)
	if _run_turn_left <= 0.0 and _trick_lock_yaw <= 0.0:
		_update_visual_yaw(delta, input_dir, moving, running)
	if _tree:
		_update_locomotion(delta, input_dir, is_on_floor(), moving, running)
		_update_idle_break(delta, moving)
	# 腳步：用實際水平速度而不是輸入 —— 撞牆、被擊退、踩斜坡時速度才是真的。
	if _footstep_audio != null:
		var flat := Vector2(velocity.x, velocity.z).length()
		var can_step := action_state != ActionState.DODGING and _jump_charge < 0.0
		_footstep_audio.tick(delta, is_on_floor() and can_step, flat, running)

## Stair / ledge step: if moving horizontally into something at foot level
## that we could stand on top of within step_height, lift the body onto it.
## Uses test_move (no side effects) so a false positive costs nothing.
## Pattern: godot-master physics-3d "kinematic_3d_stairs_logic".
## P11 R2：②③④ を追加。g＝足元中心の真下の地面。② g が無ければ跨がない／③ 障害物の上面が g＋step_height を超えたら跨がない／
## ④ 跨いだ後の足の高さ ≤ g＋step_height（膠囊の丸い底が縁に乗った状態からの連続抬升を禁止）。持ち上げ・前進・着地の掃引は原版のまま。
func _try_step_up(delta: float) -> void:
	if step_height <= 0.0:
		return
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if h.length_squared() < 0.01:
		return
	var space := get_world_3d().direct_space_state
	# ② 足元中心の真下の地面 g（step_height＋0.5 m 以内に無ければ跨がない）
	var o := global_transform.origin
	var gq := PhysicsRayQueryParameters3D.create(o + Vector3(0, 0.05, 0), o - Vector3(0, step_height + 0.5, 0), collision_mask)
	gq.exclude = [get_rid()]
	var gh := space.intersect_ray(gq)
	if gh.is_empty():
		return
	var g := float((gh["position"] as Vector3).y)
	var motion := h * delta
	var par := PhysicsTestMotionParameters3D.new()
	var res := PhysicsTestMotionResult3D.new()
	par.from = global_transform
	par.motion = motion
	# Not blocked → nothing to step over.
	if not PhysicsServer3D.body_test_motion(get_rid(), par, res):
		return
	# ③ 障害物の上面（当たった点の 5 cm 奥を真上から）が g＋step_height を超えるなら跨がない
	var cp := res.get_collision_point()
	var probe := Vector3(cp.x, 0.0, cp.z) + h.normalized() * 0.05
	var tq := PhysicsRayQueryParameters3D.create(Vector3(probe.x, g + step_height + 0.3, probe.z), Vector3(probe.x, g - 0.1, probe.z), collision_mask)
	tq.exclude = [get_rid()]
	var th := space.intersect_ray(tq)
	if not th.is_empty() and float((th["position"] as Vector3).y) > g + step_height + 0.01:
		return
	# Lift, try the motion up there, then settle back down.
	#
	# The lift is NOT tested as an upward sweep from the contact pose: resting
	# against a 47° coping lip, the capsule's bottom sphere is already inside
	# the slope's lateral reach, so any straight-up motion re-hits the same
	# face after 1 cm (probe_step_up 2026-09-03) and vetoes every real step.
	# Instead: check the raised pose is simply free of overlap, then sweep.
	var up := Vector3(0.0, step_height, 0.0)
	var raised := global_transform.translated(up)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _capsule_shape()
	if q.shape == null:
		return
	q.transform = raised * _capsule_local()
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
		return  # ceiling / overhang: cannot stand step_height higher here
	par.from = raised
	par.motion = motion
	PhysicsServer3D.body_test_motion(get_rid(), par, res)
	var fwd: Vector3 = res.get_travel()
	if fwd.length() < motion.length() * 0.5:
		return  # still walled at the lifted height: a real wall, not a step
	var lifted_by: float = step_height
	par.from = raised.translated(fwd)
	par.motion = Vector3(0.0, -lifted_by, 0.0)
	if not PhysicsServer3D.body_test_motion(get_rid(), par, res):
		return  # nothing to land on within step_height
	# Only accept walkable landings — no climbing 46° faces sideways. Judge
	# by the surface under the FOOT CENTRE, not the capsule's first contact:
	# on a 0.25 m-wide coping stone the r=0.3 capsule's sphere touches the
	# stone's 47° edge first (probe_bridge_profile 2026-09-03) though the
	# foot lands on the flat top.
	var landed := raised.translated(fwd).translated(res.get_travel())
	var foot := landed.origin
	var rq := PhysicsRayQueryParameters3D.create(foot + Vector3(0, 0.3, 0), foot + Vector3(0, -0.3, 0), collision_mask)
	rq.exclude = [get_rid()]
	var rh := get_world_3d().direct_space_state.intersect_ray(rq)
	var land_n: Vector3 = rh["normal"] if not rh.is_empty() else res.get_collision_normal()
	if land_n.angle_to(Vector3.UP) > floor_max_angle:
		return
	var rise: float = lifted_by - res.get_travel().length()
	if rise <= 0.02:
		return
	# ④ 累積の上限：跨いだ後の足の高さ ≤ g＋step_height
	if o.y + rise - g > step_height + 0.01:
		return
	global_position.y += rise


func _capsule_shape() -> Shape3D:
	for c in get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			return (c as CollisionShape3D).shape
	return null


func _capsule_local() -> Transform3D:
	for c in get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			return (c as Node3D).transform
	return Transform3D.IDENTITY


func _read_input_dir() -> Vector3:
	# InputMap actions (project.godot [input]), not raw keycodes, so the main
	# game's bindings / gamepad apply. Rotated into the camera's yaw when
	# input_yaw_node is set.
	if input_locked:
		return Vector3.ZERO
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var input_dir := Vector3(v.x, 0.0, v.y)
	if input_yaw_node != null:
		input_dir = input_dir.rotated(Vector3.UP, input_yaw_node.global_rotation.y)
	return input_dir

func _apply_air_control(input_dir: Vector3, cur_speed: float, delta: float) -> void:
	var h := Vector2(velocity.x, velocity.z)
	if input_dir.is_zero_approx():
		h = h.move_toward(Vector2.ZERO, air_drag * delta)
	else:
		var desired := Vector2(input_dir.x, input_dir.z) * cur_speed
		h = h.move_toward(desired, air_acceleration * air_control * delta)
	velocity.x = h.x
	velocity.z = h.y

## 出生或傳送時對齊面向：保持 CharacterBody3D 根節點 rotation.y 乾淨（為 0），
## 將模型視覺朝向對齊 yaw，並通知相機適配器同步對齊。
func snap_yaw(yaw: float) -> void:
	rotation.y = 0.0
	if _visual != null:
		_visual.global_rotation.y = wrapf(yaw + PI, -PI, PI)
	var adapter := get_node_or_null("CameraAdapter")
	if adapter != null and adapter.has_method("snap_yaw"):
		adapter.snap_yaw(yaw)


## snap_yaw 的反函式 —— 目前的面向，與 snap_yaw 吃的座標系一致。
##
## ⚠ 存檔一定要用這個，不要讀 rotation.y。本節點刻意把根節點的 rotation.y
##   固定在 0（面向只存在 _visual 上），所以 player.rotation.y 永遠是 0 ——
##   直接存它等於根本沒存朝向，讀檔後緣一一律面向同一邊。
func current_yaw() -> float:
	if _visual == null:
		return rotation.y
	return wrapf(_visual.global_rotation.y - PI, -PI, PI)

## 視覺轉向：速率上限（不是指數 lerp）——180° 急轉需要時間走完，不會瞬間
## snap；走路慢（沉穩）、疾跑快（×run_turn_multiplier）、攻擊中再降
## （×attack_turn_control）。腳下的扇區動畫（FL/FR/BackPedal）同步提供
## 對應步法，避免「轉盤式」原地旋轉。
## ⚠ 一律使用世界旋轉 global_rotation.y，避免地圖或父節點帶旋轉時內外疊加導致 180° 反轉。
func _update_visual_yaw(delta: float, input_dir: Vector3, moving: bool, running: bool) -> void:
	if not moving or _visual == null or action_state == ActionState.DODGING:
		return
	if _iai_dash_remaining > 0.0 or _iai_unfreeze_in >= 0.0:
		return   # 衝刺鎖定方向：輸入不能把刀轉離目標
	# input_dir 前進為 -Z、後退為 +Z（Godot 慣例）。
	# BodyVisual 模型正面朝向本體 +Z，因此以 atan2(input_dir.x, input_dir.z) 使前進 (-Z) 為 180°(PI)，後退 (+Z) 為 0°。
	var target_yaw := atan2(input_dir.x, input_dir.z)
	var diff := wrapf(target_yaw - _visual.global_rotation.y, -PI, PI)
	var max_rate := turn_speed * (run_turn_multiplier if running else 1.0)
	if action_state == ActionState.ATTACKING and _attack_layer == "full":
		max_rate *= attack_turn_control
	var step := minf(absf(diff), max_rate * delta) * signf(diff)
	_visual.global_rotation.y = wrapf(_visual.global_rotation.y + step, -PI, PI)

# --- locomotion 狀態選擇 ----------------------------------------------------
func _update_locomotion(delta: float, input_dir: Vector3, grounded: bool, moving: bool, running: bool) -> void:
	if action_state == ActionState.DODGING or (action_state == ActionState.ATTACKING and _attack_layer == "full"):
		return   # 全身 override 顯示中
	var pb := _playback()
	if _iai_dash_remaining > 0.0 and grounded:
		pb.travel(_drawn_state("Run"))   # 拔刀斬衝刺：腿要跑，不能滑著走（moving 是看輸入的，沒按方向會變 Idle 滑行）
		return
	if not grounded:
		if not _was_airborne:
			_air_peak_y = global_position.y
		_was_airborne = true
		_air_peak_y = maxf(_air_peak_y, global_position.y)
		_air_t += delta
		# 上升期維持 JumpStart 姿勢；velocity.y <= 0（或走出邊緣過 coyote）→ Fall。
		if velocity.y <= 0.0 and _air_t > coyote_time and pb.get_current_node() != &"Fall":
			pb.travel("Fall")
		return
	_air_t = 0.0
	if _jump_charge >= 0.0:
		return   # 蓄力蹲伏：JumpStart 播放中，locomotion 不搶
	if _was_airborne:
		_was_airborne = false
		_double_jump_used = false
		_last_wall_normal = Vector3.ZERO
		CombatVFX.spawn_land_dust(self, global_position)
		if _trick_left > 0.0 and _climb_left <= 0.0:
			_trick_left = 0.0   # 空翻還沒播完就著地：直接收掉，交給落地
			_fade_full()
		var drop := _air_peak_y - global_position.y
		_air_peak_y = -INF
		if _try_heavy_landing(drop, moving):
			return
		if not moving:
			_land_lock = land_lock_time
			pb.travel("Land")
			return
		_land_lock = 0.0   # 有輸入：落地直接接 Run/Walk
	if _land_lock > 0.0:
		if moving:
			_land_lock = 0.0   # 有輸入直接接 locomotion
		else:
			_land_lock -= delta
			return
	_sector_hold = maxf(_sector_hold - delta, 0.0)
	if not moving:
		pb.travel(_drawn_state("Idle"))
		return
	# 急轉不再播獨立 turn clip（素材整段懸空、Hips 帶 1.15 m 偏移）：
	# 60°~112.5° 由 RunFL/FR 側身扇區接，>112.5° 交給 BackPedal，
	# 視覺朝向仍由 _update_visual_yaw 的 turn_speed lerp 跟上。
	pb.travel(_drawn_state(_locomotion_target(running)))

## 刀在手上（拔刀完成、或拔刀途中已出鞘）就換持刀版 locomotion。
func _sword_in_hand() -> bool:
	return sword_state == SwordState.DRAWN or ((sword_state == SwordState.DRAWING or sword_state == SwordState.SHEATHING) and _draw_t >= t_unsheathe)

func _drawn_state(st: String) -> String:
	if not drawn_locomotion_enabled or not _sword_in_hand():
		return st
	if st == "RunFL" or st == "RunFR":
		var run := Vector2(velocity.x, velocity.z).length() > walk_speed + 0.8
		var sname := ("D_StrafeL" if st == "RunFL" else "D_StrafeR") + ("Run" if run else "")
		return sname if _anim.has_animation(sname) else st
	if st == "BackPedal" and Vector2(velocity.x, velocity.z).length() > walk_speed + 0.8 and _anim.has_animation("D_RunBack"):
		return "D_RunBack"
	var d: String = DRAWN_OF.get(st, "")
	if d == "D_Sprint":
		return d if _anim.has_animation("D_Run") else st
	return d if d != "" and _anim.has_animation(d) else st

## 8 向 locomotion：以角色 local 速度方向分 sector（不是世界座標、不是輸入鍵）。
## 0°=前、+90°=左、180°=後。Forward |a|<22.5 → Run/Walk；22.5~112.5 → RunFL
## （側向 67.5~112.5 目前無專用 strafe clip，代用 FL 側身跑，鏡像同理）；
## |a|>112.5 → BackPedal（Walking 反播）。sector_min_hold 防抖。
func _locomotion_target(running: bool) -> String:
	var lv := Vector2(velocity.x, velocity.z)
	var forward_state := "Sprint" if running else ("Walk" if _walking else "Run")
	if lv.length() < 0.5 or _visual == null:
		return forward_state
	var yaw: float = _visual.global_rotation.y
	# BodyVisual 模型本體正面為 +Z、左側為 -X。
	# 旋轉世界 yaw 後世界座標：fwd = (sin(yaw), cos(yaw))，left = (-cos(yaw), sin(yaw))。
	var fwd := Vector2(sin(yaw), cos(yaw))
	var left := Vector2(-cos(yaw), sin(yaw))
	var nd := lv.normalized()
	var ang := rad_to_deg(atan2(nd.dot(left), nd.dot(fwd)))
	var target := forward_state
	var drawn := drawn_locomotion_enabled and _sword_in_hand()
	if absf(ang) > 112.5:
		target = "BackPedal"
	elif drawn and ang > 60.0:
		target = "RunFL"
	elif drawn and ang < -60.0:
		target = "RunFR"
	elif running and _fl_anim != "" and ang > 22.5:
		target = "RunFL"
	elif running and _fr_anim != "" and ang < -22.5:
		target = "RunFR"
	if target != _sector_state:
		if _sector_hold > 0.0:
			return _sector_state   # 換 sector 後最短持續 0.15 s，防高速抖動
		_sector_state = target
		_sector_hold = sector_min_hold
	return _sector_state

# ---------------------------------------------------------------------------
# Input（正式戰鬥輸入只有滑鼠；J/K/L 已移除，無 debug fallback）
# Space = 跳躍；Shift 按住 = 疾跑、快按 = 翻滾；Q = 拔/收刀 toggle。
# ---------------------------------------------------------------------------
func _unhandled_input(event):
	# Actions from project.godot [input]; the camera / interaction adapter
	# (player_yoriichi.gd) handles mouse-look and "interact" on top of this.
	if input_locked:
		return
	if not _combat_anims_ready:
		_unhandled_input_locomotion_only(event)
		return
	if event.is_action_pressed("draw_sword"):
		if _active_attack_name == attack_continuous_spin_anim:
			if can_cancel_continuous_spin():
				cancel_continuous_spin()
				request_sword_toggle()
		else:
			request_sword_toggle()
	elif event.is_action_pressed("jump"):
		if _active_attack_name == attack_continuous_spin_anim:
			if can_cancel_continuous_spin():
				cancel_continuous_spin()
				request_jump()
			else:
				_spin_buffered_cancel = "jump"
		else:
			request_jump()
	elif event.is_action_pressed("sprint"):
		_shift_pressed_msec = Time.get_ticks_msec()
	elif event.is_action_released("sprint") and _shift_pressed_msec >= 0:
		if (Time.get_ticks_msec() - _shift_pressed_msec) / 1000.0 <= shift_tap_time:
			if _active_attack_name == attack_continuous_spin_anim:
				if can_cancel_continuous_spin():
					cancel_continuous_spin()
					request_dodge()
				else:
					_spin_buffered_cancel = "dodge"
			else:
				request_dodge()
		_shift_pressed_msec = -1
	elif event.is_action_pressed("attack_light"):
		if _active_attack_name == attack_continuous_spin_anim:
			if can_cancel_continuous_spin():
				cancel_continuous_spin()
				_start_combo()
			else:
				_spin_buffered_cancel = "light"
		else:
			request_primary_attack()
	elif event.is_action_pressed("attack_heavy") and not event.is_echo():
		if _active_attack_name == attack_continuous_spin_anim:
			if can_cancel_continuous_spin():
				cancel_continuous_spin()
				request_heavy_cut()
			else:
				_spin_buffered_cancel = "heavy"
		elif not begin_heavy_charge():
			request_heavy_cut()
	elif event.is_action_released("attack_heavy"):
		# 主要靠 _update_attack 每步輪詢 Input（選單／對話會吃掉 release 事件），這裡只是提早一幀。
		if _heavy_charging:
			release_heavy_charge()
	elif event.is_action_pressed("guard"):
		begin_guard()
	elif event.is_action_released("guard"):
		end_guard()
	elif event.is_action_pressed("lock_on"):
		toggle_lock_on()
	elif event.is_action_pressed("deathblow"):
		try_deathblow()
	elif event.is_action_pressed("form13"):
		if form13_key_enabled:
			start_form13()
	elif event.is_action_pressed("attack_special"):
		if _active_attack_name == attack_continuous_spin_anim:
			if can_cancel_continuous_spin():
				cancel_continuous_spin()
				request_continuous_spin()
			else:
				_spin_buffered_cancel = "special"
		else:
			request_continuous_spin()

## 戰鬥動畫未就緒（v2.4 換裝過渡期）：只處理跳躍與鎖定；疾跑由 _physics_process 讀按住狀態。
## 拔刀、攻擊、格擋、翻滾（快按 Shift）、忍殺、型全部不觸發，避免播佔位動畫卻判定命中。
func _unhandled_input_locomotion_only(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		request_jump()
	elif event.is_action_pressed("lock_on"):
		toggle_lock_on()

# ---------------------------------------------------------------------------
# Traversal（v2.4 特技）：二段空翻、踩牆跳、攀牆頂、蹬牆跑上平台、高處落地翻滾、跑步急轉、待機小動作
# ---------------------------------------------------------------------------
var _walking := false
var _double_jump_used := false
var _last_wall_normal := Vector3.ZERO
var _air_peak_y := -INF
## 特技 clip 剩餘秒數（>0 = full 層特技播放中；到點淡出）。
var _trick_left := 0.0
## 特技期間鎖住視覺朝向（踩牆跳要面向離牆方向，不被輸入拉回）。
var _trick_lock_yaw := 0.0
## 攀爬：root_path 驅動。
var _climb_left := 0.0
var _climb_total := 0.0
var _climb_path := PackedVector3Array()
var _climb_scale := Vector3.ONE
var _climb_end := Vector3.ZERO
var _climb_basis := Basis()
## 重落地鎖移動剩餘秒數；落地翻滾的前衝方向。
var _land_lock_move := 0.0
var _land_roll_dir := Vector3.ZERO
var _run_turn_left := 0.0
var _run_turn_yaw := 0.0
var _idle_time := 0.0
var _idle_break_at := -1.0
var _idle_break_on := false
## 起身速度倍率（Getting Up From Back 原片 8.3 s 偏長）。
@export var get_up_speed := 1.6

func _facing() -> Vector3:
	var yaw: float = _visual.global_rotation.y if _visual else 0.0
	return Vector3(sin(yaw), 0.0, cos(yaw))

func _face_dir(d: Vector3) -> void:
	if _visual != null and Vector2(d.x, d.z).length() > 0.01:
		_visual.global_rotation.y = atan2(d.x, d.z)

func _play_trick(key: String, spd: float, lock_yaw := 0.0) -> void:
	if not _anim.has_animation(key):
		return
	_fade_idle_break()
	_fire_full(key, spd)
	_trick_left = _anim.get_animation(key).length / maxf(spd, 0.01)
	_trick_lock_yaw = lock_yaw

## 回傳 true = 本幀被特技接管（攀爬中）。
func _update_traversal(delta: float, input_dir: Vector3, grounded: bool, moving: bool, running: bool) -> bool:
	if _trick_left > 0.0:
		_trick_left -= delta
		if _trick_left <= 0.0 and _climb_left <= 0.0:
			_fade_full()
	_trick_lock_yaw = maxf(_trick_lock_yaw - delta, 0.0)
	if _climb_left > 0.0:
		_climb_left = maxf(_climb_left - delta, 0.0)
		var u := 1.0 - _climb_left / maxf(_climb_total, 0.001)
		var f := u * float(_climb_path.size() - 1)
		var i0 := clampi(int(f), 0, _climb_path.size() - 1)
		var i1 := mini(i0 + 1, _climb_path.size() - 1)
		var p := _climb_path[i0].lerp(_climb_path[i1], f - float(i0)) * _climb_scale
		# 還在牆頂以下時，身體中心不得比「牆面 + 膠囊半徑」更靠牆（牆面在終點後方 LEDGE_INSET）；
		# 越接近牆頂越放開，上到頂面後就照 clip 往前走。避免 root_path 縮放後提早前移、身體埋進牆。
		var below := clampf(-p.y / 0.12, 0.0, 1.0)
		var zmax := lerpf(1.0, -(LEDGE_INSET + climb_wall_clearance), below)
		p.z = minf(p.z, zmax)
		global_position = _climb_end + _climb_basis * p
		velocity = Vector3.ZERO
		if _climb_left <= 0.0:
			global_position = _climb_end
			_fade_full()
			_trick_left = 0.0
		_update_sword(delta)
		return true
	if _land_lock_move > 0.0:
		_land_lock_move -= delta
	if _run_turn_left > 0.0:
		_run_turn_left -= delta
		if _run_turn_left <= 0.0:
			_visual.global_rotation.y = _run_turn_yaw
			_tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	# 跑步急轉：地面、自由狀態、速度夠快、輸入與面向夾角 > 150°。
	elif run_turn_enabled and grounded and moving and action_state == ActionState.FREE and _anim.has_animation("Run_Turn") \
			and Vector2(velocity.x, velocity.z).length() > speed * 0.8 and _trick_left <= 0.0:
		var fwd := _facing()
		if fwd.dot(input_dir.normalized()) < -0.86:
			_run_turn_yaw = atan2(input_dir.x, input_dir.z)
			_fire_full("run_turn", run_turn_speed)
			_full_node.fadeout_time = 0.0
			_run_turn_left = _anim.get_animation("Run_Turn").length / run_turn_speed
	# 空中朝牆前進時自動攀上牆頂（屋簷、石垣、木箱）。
	if ledge_climb_enabled and not grounded and moving and action_state == ActionState.FREE and _jump_charge < 0.0:
		var ledge := _find_ledge(input_dir.normalized(), ledge_min_height, ledge_max_height)
		if not ledge.is_empty():
			_start_climb(ledge, "Trick_Mantle", mantle_speed)
			return true
	return false

## 跑步急轉期間不讓輸入改面向；水平速度先煞再出。
func _run_turn_speed_factor() -> float:
	return 0.35 if _run_turn_left > 0.0 else 1.0

## 牆頂站立點離牆面的深度（m）。
const LEDGE_INSET := 0.3
## 攀爬時身體中心離牆面的最小距離（m）＝膠囊半徑。
@export var climb_wall_clearance := 0.3

## 前方牆頂偵測。dir＝水平前進方向。回傳 {top, normal, h} 或 {}。
## 1) 胸口／膝蓋兩條水平射線找牆（法線接近水平）；2) 從牆內 0.3 m、上方往下打找頂面（法線朝上）；
## 3) 頂面站得下膠囊（上方淨空）。h＝頂面相對腳底的高度。
func _find_ledge(dir: Vector3, min_h: float, max_h: float) -> Dictionary:
	if dir.length_squared() < 0.01:
		return {}
	var space := get_world_3d().direct_space_state
	var o := global_position
	var wall := {}
	for hh in [1.2, 0.6, 1.8]:
		var q := PhysicsRayQueryParameters3D.create(o + Vector3(0, hh, 0), o + Vector3(0, hh, 0) + dir * ledge_probe_distance, collision_mask)
		q.exclude = [get_rid()]
		var r := space.intersect_ray(q)
		if not r.is_empty() and absf((r.normal as Vector3).y) < 0.35:
			wall = r
			break
	if wall.is_empty():
		return {}
	var n: Vector3 = wall.normal
	n.y = 0.0
	n = n.normalized()
	var inside: Vector3 = (wall.position as Vector3) - n * LEDGE_INSET
	var dq := PhysicsRayQueryParameters3D.create(Vector3(inside.x, o.y + max_h + 0.4, inside.z), Vector3(inside.x, o.y + min_h - 0.05, inside.z), collision_mask)
	dq.exclude = [get_rid()]
	var top := space.intersect_ray(dq)
	if top.is_empty() or (top.normal as Vector3).y < 0.75:
		return {}
	var h: float = (top.position as Vector3).y - o.y
	if h < min_h or h > max_h:
		return {}
	var stand: Vector3 = top.position
	var shp := PhysicsShapeQueryParameters3D.new()
	shp.shape = _capsule_shape()
	if shp.shape == null:
		return {}
	shp.transform = Transform3D(Basis(), stand + Vector3(0, 0.05, 0)) * _capsule_local()
	shp.collision_mask = collision_mask
	shp.exclude = [get_rid()]
	if not space.intersect_shape(shp, 1).is_empty():
		return {}
	return {"top": stand, "normal": n, "h": h}

## 攀上：位置沿 clip 的 root_path 走（y 依實際牆高、前進依實際距離縮放），終點＝牆頂站立點。
func _start_climb(ledge: Dictionary, key: String, spd: float) -> void:
	var a: Animation = _anim.get_animation(key)
	if a == null or not a.has_meta("root_path"):
		return
	_climb_path = a.get_meta("root_path")
	var n: Vector3 = ledge.normal
	var fwd := -n
	_face_dir(fwd)
	_climb_basis = Basis(Vector3.UP, atan2(fwd.x, fwd.z))
	var start := _climb_path[0]
	_climb_end = ledge.top as Vector3
	var rel := _climb_basis.inverse() * (global_position - _climb_end)
	_climb_scale = Vector3(0.0,
		rel.y / start.y if absf(start.y) > 0.05 else 1.0,
		rel.z / start.z if absf(start.z) > 0.05 else 1.0)
	# 橫向維持目前位置（不往側邊瞬移），終點跟著平移。
	_climb_end += _climb_basis * Vector3(rel.x, 0.0, 0.0)
	_climb_scale.y = clampf(_climb_scale.y, 0.2, 2.5)
	_climb_scale.z = clampf(_climb_scale.z, 0.0, 3.0)
	_climb_total = a.length / maxf(spd, 0.01)
	_climb_left = _climb_total
	velocity = Vector3.ZERO
	_jump_charge = -1.0
	_double_jump_used = false
	_play_trick(key, spd)
	_full_node.fadeout_time = 0.18

## 地面朝牆按跳：牆頂在 wallrun 高度範圍 → 蹬牆跑上去；更低的牆頂交給一般跳＋空中攀爬。
func _try_start_wallrun() -> bool:
	if not ledge_climb_enabled:
		return false
	var dir := _read_input_dir()
	if dir.length_squared() < 0.01:
		return false
	var ledge := _find_ledge(dir.normalized(), wallrun_min_height, wallrun_max_height)
	if ledge.is_empty():
		return false
	_start_climb(ledge, "Trick_WallRun", wallrun_speed)
	return true

## 空中再按跳：貼牆 → 踩牆跳；否則 → 二段空翻。
func _request_air_jump() -> void:
	if _heavy_charging or _iai_unfreeze_in >= 0.0 or _iai_dash_remaining > 0.0:
		return
	if wall_jump_enabled and is_on_wall():
		var n := get_wall_normal()
		n.y = 0.0
		if n.length() > 0.5 and (n.normalized().dot(_last_wall_normal) < 0.7):
			n = n.normalized()
			_last_wall_normal = n
			velocity.x = n.x * wall_jump_push
			velocity.z = n.z * wall_jump_push
			velocity.y = wall_jump_up
			_double_jump_used = false
			_face_dir(n)
			_play_trick("Trick_Flip", flip_speed, 0.45)
			CombatVFX.spawn_jump_dust(self, global_position + Vector3(0, 0.9, 0) - n * 0.3)
			return
	if double_jump_enabled and not _double_jump_used and _air_t > 0.05:
		_double_jump_used = true
		velocity.y = double_jump_velocity
		var dir := _read_input_dir()
		if dir.length_squared() > 0.01:
			_face_dir(dir)
		var twist := Input.is_action_pressed("sprint")
		_play_trick("Trick_TwistFlip" if twist else "Trick_Flip", flip_speed)
		CombatVFX.spawn_jump_dust(self, global_position)

## 高處落地：移動中 → 落地翻滾（往前滾、不吃硬直）；靜止 → 重落地（短暫鎖移動）。
func _try_heavy_landing(drop: float, moving: bool) -> bool:
	if action_state != ActionState.FREE:
		return false
	if moving and drop > land_roll_height and _anim.has_animation("Trick_LandRoll"):
		_land_roll_dir = _facing()
		_play_trick("Trick_LandRoll", 1.35)
		_land_lock_move = _trick_left * 0.55
		return true
	if not moving and drop > hard_land_height and _anim.has_animation("Trick_HardLand"):
		_land_roll_dir = Vector3.ZERO
		_play_trick("Trick_HardLand", 1.0)
		_land_lock_move = _trick_left * 0.6
		return true
	return false

## 待機小動作：只在地面、自由、收刀、站著不動時累積；一動或有任何動作就淡出。
func _update_idle_break(delta: float, moving: bool) -> void:
	if not idle_break_enabled or idle_break_resources.is_empty():
		return
	var calm := not moving and is_on_floor() and _jump_charge < 0.0 and action_state == ActionState.FREE and sword_state == SwordState.SHEATHED \
		and _trick_left <= 0.0 and not input_locked and _guard_held == false
	if not calm:
		_idle_time = 0.0
		_idle_break_at = -1.0
		_fade_idle_break()
		return
	_idle_time += delta
	if _idle_break_at < 0.0:
		_idle_break_at = randf_range(idle_break_after.x, idle_break_after.y)
	if not _idle_break_on and _idle_time >= _idle_break_at:
		var i := randi() % idle_break_resources.size()
		_fire_full("idle_break_%d" % i, 1.0)
		_full_node.fadeout_time = 0.45
		_idle_break_on = true
		var dur := _anim.get_animation("Idle_Break_%d" % i).length
		_idle_time = -dur   # 播完後重新計時
		_idle_break_at = -1.0
	elif _idle_break_on and _idle_time >= 0.0:
		_idle_break_on = false
		_fade_full()

func _fade_idle_break() -> void:
	if _idle_break_on:
		_idle_break_on = false
		_idle_time = 0.0
		_full_node.fadeout_time = 0.25
		_fade_full()

# ---------------------------------------------------------------------------
# Jump
# ---------------------------------------------------------------------------
## 跳躍 = 純 physics。蓄力 ~0.12 s（JumpStart 跳過大半蹲伏）後給 velocity.y；
## 之後不論播什麼 attack，gravity / 慣性照常，Jump/Fall 只是 loco 層的視覺。
## 攻擊中也可以起跳（upper 攻擊照打、腿進 JumpStart）——攻擊永遠取消不了跳躍。
func request_jump() -> void:
	if sword_state == SwordState.DRAWING or sword_state == SwordState.SHEATHING:
		return
	if _climb_left > 0.0:
		return
	if action_state == ActionState.FREE and not is_on_floor() and _jump_charge < 0.0:
		_request_air_jump()
		return
	if action_state == ActionState.FREE and is_on_floor() and _try_start_wallrun():
		return
	if action_state == ActionState.DODGING or not is_on_floor() or _jump_charge >= 0.0:
		return
	# 蓄力／衝刺中不能起跳：離地後 dash 段不會執行，姿勢會凍在半空。
	if _heavy_charging or _iai_unfreeze_in >= 0.0 or _iai_dash_remaining > 0.0:
		return
	if action_state == ActionState.ATTACKING and can_cancel_continuous_spin():
		cancel_continuous_spin()
	_jump_charge = maxf(jump_takeoff_t - jump_start_skip, 0.0) / jump_start_speed
	_fade_idle_break()
	_air_t = 0.0
	if action_state != ActionState.ATTACKING or _attack_layer != "full":
		_playback().travel("JumpStart")

# ---------------------------------------------------------------------------
# Roll
# ---------------------------------------------------------------------------
func request_dodge(direction_override: Vector3 = Vector3.ZERO) -> void:
	if sword_state == SwordState.DRAWING or sword_state == SwordState.SHEATHING:
		return
	# 先判斷能否翻滾，避免空中輸入吃掉原本的攻擊。
	if not is_on_floor():
		return
	if action_state != ActionState.FREE:
		if can_cancel_continuous_spin():
			cancel_continuous_spin()
		elif _can_dodge_cancel_attack():
			# 明確閃避優先於先前排隊的收刀，不留下延遲觸發。
			pending_sheathe = false
			_finish_attack()
		else:
			return
	var horizontal_override := Vector3(direction_override.x, 0.0, direction_override.z)
	_dodge_dir = horizontal_override.normalized() if not horizontal_override.is_zero_approx() else _read_input_dir()
	if _dodge_dir.is_zero_approx():
		var yaw := _visual.global_rotation.y if _visual else global_rotation.y
		_dodge_dir = Vector3(sin(yaw), 0.0, cos(yaw)).normalized()
	elif _visual:
		_visual.global_rotation.y = atan2(_dodge_dir.x, _dodge_dir.z)
	action_state = ActionState.DODGING
	_action_elapsed = 0.0
	_attack_after_roll = false
	_jump_charge = -1.0   # 翻滾取消尚未離地的跳躍蓄力
	_roll_duration = roll_anim_resource.length / roll_animation_speed
	_fire_full("roll", roll_animation_speed)
	CombatVFX.spawn_roll_dust(self, global_position, _dodge_dir)

func _can_dodge_cancel_attack() -> bool:
	if not attack_dodge_cancel_enabled or action_state != ActionState.ATTACKING:
		return false
	# 蓄力中隨時可翻滾放棄（蓄力不是硬直，是玩家自己選的等待）。衝刺／落刀中不行。
	if _heavy_charging:
		return true
	if _iai_dash_remaining > 0.0 or _iai_unfreeze_in >= 0.0:
		return false
	if sword_state != SwordState.DRAWN or _attack_layer != "upper" or active_form != 0:
		return false
	if combo_stage <= 0 and _active_attack_name != "Heavy_Cut":
		return false
	return _action_real <= 0.0 or _action_elapsed >= _action_real * attack_dodge_cancel_start

func _update_roll_movement(delta: float) -> void:
	var previous_t := clampf(_action_elapsed / _roll_duration, 0.0, 1.0) if _roll_duration > 0.0 else 1.0
	_action_elapsed = minf(_action_elapsed + delta, _roll_duration)
	var current_t := clampf(_action_elapsed / _roll_duration, 0.0, 1.0) if _roll_duration > 0.0 else 1.0
	# ease-out p(t) = 1 - (1-t)^2；位移驅動 CharacterBody3D 本體，碰撞體永遠跟隨。
	var previous_curve := 1.0 - pow(1.0 - previous_t, 2.0)
	var current_curve := 1.0 - pow(1.0 - current_t, 2.0)
	var frame_distance := roll_distance * (current_curve - previous_curve)
	var roll_velocity := _dodge_dir * (frame_distance / delta) if delta > 0.0 else Vector3.ZERO
	velocity.x = roll_velocity.x
	velocity.z = roll_velocity.z

func _finish_roll() -> void:
	action_state = ActionState.FREE
	_action_elapsed = 0.0
	_roll_duration = 0.0
	_fade_full()
	if _attack_after_roll:
		_attack_after_roll = false
		if sword_state == SwordState.DRAWN:
			# dodge counter（斜陽轉身雛形）：沿翻滾方向小前衝＋立即反擊斬。
			velocity.x += _dodge_dir.x * 2.0
			velocity.z += _dodge_dir.z * 2.0
			_start_combo()
	# 否則不強制回 Idle：locomotion 分支依當前輸入接回 Run / Walk / Idle。

# ---------------------------------------------------------------------------
# Attack（LMB 輕連段 = upper layer 邊跑邊斬；RMB/型 heavy = full-body override）
# ---------------------------------------------------------------------------
func request_primary_attack() -> void:
	if _queue_draw_attack("light"):
		return
	if action_state == ActionState.DODGING and sword_state == SwordState.DRAWN:
		_attack_after_roll = true   # dodge counter：roll 結束自動接反擊斬
		return
	if sword_state != SwordState.DRAWN:
		return
	# 見切反擊：彈刀後 counter_window 內按 LMB → 直接接 counter_form。
	if counter_form != 0 and _counter_until_msec >= 0 and Time.get_ticks_msec() <= _counter_until_msec \
			and action_state == ActionState.FREE:
		_counter_until_msec = -1
		end_guard()
		if execute_form(counter_form, true):
			counter_triggered.emit(counter_form)
			return
	# 型進行中按 LMB：取消窗口內直接回連段段1，窗口前先排隊。
	if action_state == ActionState.ATTACKING and active_form != 0 and form_followup_enabled:
		if _in_form_cancel_window():
			_finish_attack()
			_start_combo()
		else:
			_form_followup = "light"
		return
	# 聚力單斬中按 LMB：接 heavy_branch_form（拾壹型 幻日虹）。蓄力／衝刺中不接（等落刀後）。
	if action_state == ActionState.ATTACKING and _active_attack_name == "Heavy_Cut" and heavy_branch_form != 0:
		if _heavy_charging or _iai_unfreeze_in >= 0.0:
			return
		if _attack_progress() >= combo_cancel_start:
			_branch_to_form(heavy_branch_form)
		else:
			_branch_queued = heavy_branch_form
		return
	if action_state == ActionState.ATTACKING and combo_stage > 0:
		_combo_queued_inputs = 1
		combo_input_buffered = true
		_combo_buffer_remaining = combo_input_buffer_time
		return
	if action_state != ActionState.FREE:
		if action_state == ActionState.ATTACKING and can_cancel_continuous_spin():
			cancel_continuous_spin()
		else:
			return
	_start_combo()

func _start_combo() -> void:
	action_state = ActionState.ATTACKING
	_attack_layer = "upper"
	_active_attack_name = attack_combo_anim
	_spin_buffered_cancel = ""
	active_form = 0
	combo_stage = 1
	_combo_queued_inputs = 0
	combo_input_buffered = false
	_combo_buffer_remaining = 0.0
	_start_light_section(combo_stage)

func _start_light_section(stage: int) -> void:
	var range := COMBO_SECTION_RANGES[stage - 1]
	var spd := _combo_stage_speed(stage)
	var section_len := attack_combo_resource.length * (range.y - range.x)
	_action_real = section_len / spd
	_action_elapsed = 0.0
	var is_moving := velocity.length_squared() > 0.5
	_upper_finish_fade = 0.08 if is_moving else (0.20 if stage >= COMBO_SECTION_RANGES.size() else 0.10)
	_fire_upper("atk%d" % stage, spd)
	_character_audio.play_swing(stage)
	if _sword_trail != null:
		# 普通斬一律用預設側寫；型被硬直打斷時沒走 _finish_attack，不補這行會拖著型的長尾巴。
		_sword_trail.reset_form()
		_sword_trail.start_trail()
	_hit_targets_this_swing.clear()
	if _hitbox != null:
		_hitbox.monitoring = true

## 三連斬不取同一速度：第一刀突然、第二刀維持、第三刀略收。
func _combo_stage_speed(stage: int) -> float:
	match stage:
		1:
			return attack_speed_scale
		2:
			return combo_stage2_speed
		3:
			return combo_stage3_speed
	return attack_speed_scale

func request_special_attack(animation_name: String) -> void:
	if sword_state != SwordState.DRAWN:
		return
	if action_state != ActionState.FREE:
		if action_state == ActionState.ATTACKING and can_cancel_continuous_spin():
			cancel_continuous_spin()
		else:
			return
	var key := _full_input_for(animation_name)
	if key == "":
		push_warning("yoriichi_character: attack animation is unavailable: " + animation_name)
		return
	action_state = ActionState.ATTACKING
	_attack_layer = "full"
	_active_attack_name = animation_name
	_spin_buffered_cancel = ""
	active_form = 0
	combo_stage = 0
	_combo_queued_inputs = 0
	combo_input_buffered = false
	var spd := _special_speed_for(animation_name)
	_action_real = _full_anim_length(animation_name) / spd
	_action_elapsed = 0.0
	_fire_full(key, spd)
	_character_audio.play_heavy_swing()
	if _sword_trail != null:
		# 普通斬一律用預設側寫；型被硬直打斷時沒走 _finish_attack，不補這行會拖著型的長尾巴。
		_sword_trail.reset_form()
		_sword_trail.start_trail()
	_hit_targets_this_swing.clear()
	if _hitbox != null:
		_hitbox.monitoring = true

## 各全身技的播放倍率（不再共用單一 attack_speed_scale）。
func _special_speed_for(animation_name: String) -> float:
	match animation_name:
		attack_judgment_anim:
			return judgment_speed_scale
		attack_combo_1_anim:
			return combo_1_speed_scale
		attack_spin_anim:
			return spin_speed_scale
		attack_continuous_spin_anim:
			return continuous_spin_speed_scale
		attack_spin_jump_anim:
			return spin_jump_speed_scale
		attack_thrust_anim:
			return thrust_speed_scale
	return attack_speed_scale

func _full_input_for(animation_name: String) -> String:
	match animation_name:
		attack_thrust_anim: return "thrust"
		attack_form05_anim: return "form05"
		attack_form06_anim: return "form06"
		attack_form11_anim: return "form11"
		attack_form12_anim: return "form12"
		attack_spin_anim: return "spin"
		attack_continuous_spin_anim: return "continuous_spin"
		attack_judgment_anim: return "judgment"
		attack_combo_1_anim: return "combo1"
		attack_spin_jump_anim: return "spinjump"
	return ""

func _full_anim_length(animation_name: String) -> float:
	return _anim.get_animation(animation_name).length if _anim.has_animation(animation_name) else 0.0

func _update_attack(delta: float, _input_dir: Vector3) -> void:
	if _heavy_charging:
		_update_heavy_charge(delta)
		return
	if _iai_unfreeze_in >= 0.0:
		_iai_unfreeze_in -= delta
		_update_iai_stance(delta)   # 衝刺中架勢照樣走完進姿段切循環
		if _iai_unfreeze_in > 0.0:
			return   # 衝刺中、仍是居合架勢
		_iai_unfreeze_in = -1.0
		_unfreeze_iai_slash()
	_action_elapsed += delta
	if _combo_queued_inputs > 0:
		_combo_buffer_remaining = maxf(_combo_buffer_remaining - delta, 0.0)
		if _combo_buffer_remaining <= 0.0:
			_combo_queued_inputs = 0
			combo_input_buffered = false
	var progress := clampf(_action_elapsed / _action_real, 0.0, 1.0) if _action_real > 0.0 else 1.0
	# 型：二段技的第二刀重新判定命中；取消窗口內執行排隊的後續。
	if active_form != 0 and SunBreathing.FORMS.has(active_form):
		var def: Dictionary = SunBreathing.FORMS[active_form]
		var rehit: float = float(def.get("rehit", 0.0))
		if rehit > 0.0 and progress >= rehit and _hit_targets_this_swing.get("_rehit_done", false) == false:
			_hit_targets_this_swing.clear()
			_hit_targets_this_swing["_rehit_done"] = true
		if _form_followup != "" and progress >= float(def.cancel.x):
			var act := _form_followup
			_form_followup = ""
			_finish_attack()
			if act == "light":
				_start_combo()
			else:
				request_heavy_cut()
			return
	# 連段／聚力單斬中排隊的型：進取消窗口就切。
	if _branch_queued != 0 and active_form == 0 and progress >= combo_cancel_start:
		var id := _branch_queued
		if _branch_to_form(id):
			return
		_branch_queued = 0
	if _active_attack_name == attack_continuous_spin_anim and _spin_buffered_cancel != "":
		if progress >= SPIN_CANCEL_WINDOW_START:
			var act := _spin_buffered_cancel
			_spin_buffered_cancel = ""
			cancel_continuous_spin()
			match act:
				"light":
					_start_combo()
				"heavy":
					request_heavy_cut()
				"dodge":
					request_dodge()
				"jump":
					request_jump()
				"special":
					request_continuous_spin()
			return
	if combo_stage > 0:
		var running_or_moving: bool = Input.is_action_pressed("sprint") or _input_dir.length_squared() > 0.0
		var holding_lmb: bool = Input.is_action_pressed("attack_light")
		var auto_loop: bool = running_or_moving and holding_lmb
		var should_advance: bool = (_combo_queued_inputs > 0 or auto_loop)
		if should_advance and progress >= combo_cancel_start:
			_advance_combo()
		elif progress >= 1.0:
			if should_advance:
				_advance_combo()
			else:
				_finish_attack()
	elif progress >= 1.0:
		_finish_attack()

func _advance_combo() -> void:
	_combo_queued_inputs = maxi(_combo_queued_inputs - 1, 0)
	combo_input_buffered = _combo_queued_inputs > 0
	_combo_buffer_remaining = combo_input_buffer_time if combo_input_buffered else 0.0
	combo_stage += 1
	if combo_stage > COMBO_SECTION_RANGES.size():
		combo_stage = 1
	_start_light_section(combo_stage)

## RMB 聚力單斬：同一刀素材（Weapon_Combo 第一斬）的慎重版——
## 倍率較低（1.5）、收勢較長（0.24 s）。走 upper 層：腳步不受限、
## 沒有全身技的跳動與旋轉，強大感來自「精準與從容」。空中亦可用。
func request_heavy_cut() -> void:
	if _queue_draw_attack("heavy"):
		return
	if sword_state != SwordState.DRAWN:
		return
	# 輕連段中按 RMB：依段數接型（壹段→陸 飛輪陽炎、貳段→伍 斜陽轉身、參段→拾貳 炎舞）。
	if action_state == ActionState.ATTACKING and combo_stage > 0 and active_form == 0:
		var id := _branch_form_for_stage(combo_stage)
		if id != 0:
			if _attack_progress() >= combo_cancel_start:
				_branch_to_form(id)
			else:
				_branch_queued = id
				_combo_queued_inputs = 0   # RMB 蓋掉先前排隊的 LMB
				combo_input_buffered = false
			return
	# 型進行中按 RMB：取消窗口內接聚力單斬。
	if action_state == ActionState.ATTACKING and active_form != 0 and form_followup_enabled:
		if _in_form_cancel_window():
			_finish_attack()
			request_heavy_cut()
		else:
			_form_followup = "heavy"
		return
	# 疾跑中 RMB：捌型 陽華突（衝刺突刺）。
	if action_state == ActionState.FREE and sprint_heavy_form != 0 and is_on_floor() \
			and Input.is_action_pressed("sprint") and Vector2(velocity.x, velocity.z).length() > speed + 0.5:
		if _branch_to_form(sprint_heavy_form):
			return
	if action_state != ActionState.FREE:
		if action_state == ActionState.ATTACKING and can_cancel_continuous_spin():
			cancel_continuous_spin()
		else:
			return
	action_state = ActionState.ATTACKING
	_attack_layer = "upper"
	_active_attack_name = "Heavy_Cut"
	_spin_buffered_cancel = ""
	active_form = 0
	combo_stage = 0
	_combo_queued_inputs = 0
	combo_input_buffered = false
	_action_real = _heavy_len() / heavy_cut_speed
	_action_elapsed = 0.0
	_upper_finish_fade = 0.24
	_fire_upper("heavy", heavy_cut_speed)
	_hit_targets_this_swing.clear()
	if _heavy_charge_arming:
		# 蓄力入口：舉刀段不是砍 —— 不出聲、不拖刀光、不判定；放開／落刀時再開。
		if _hitbox != null:
			_hitbox.monitoring = false
		return
	_character_audio.play_heavy_swing()
	if _sword_trail != null:
		# 普通斬一律用預設側寫；型被硬直打斷時沒走 _finish_attack，不補這行會拖著型的長尾巴。
		_sword_trail.reset_form()
		_sword_trail.start_trail()
	if _hitbox != null:
		_hitbox.monitoring = true

func _heavy_len() -> float:
	if _anim != null and _anim.has_animation("Heavy_Cut"):
		return _anim.get_animation("Heavy_Cut").length
	return attack_combo_resource.length * (COMBO_SECTION_RANGES[0].y - COMBO_SECTION_RANGES[0].x)

func _attack_progress() -> float:
	return clampf(_action_elapsed / _action_real, 0.0, 1.0) if _action_real > 0.0 else 1.0

# ---------------------------------------------------------------------------
# RMB 長按：蓄力拔刀斬（居合）
#
# 短按 = 原本的聚力單斬，一幀都不延遲：起手就是 request_heavy_cut()，同一支 clip。
# 按住 → atk1 播到 heavy_charge_freeze_progress（實測 0.27）就切 **full 層**居合架勢：
# iai_in（進姿 0.33 s：沉腰、雙手疊握低橫身前的刀）→ iai_hold（kamae 呼吸循環）。
# 蓄力姿勢是全身 clip（upper 層 filter 不含腿/Hips，蹲姿會被 locomotion 吃掉——
# 這就是舊版「凍 atk1 舉刀」讀不出蹲的原因）。
#   * 未滿放開 → 淡掉架勢、重放一段普通聚力單斬（atk1 在蓄力中早已播完，無法「續播」）。
#   * 滿 heavy_charge_time → 閃光＋拔刀音 → 放開（或 auto_release）→ 對鎖定／最近敵人
#     衝刺（架勢循環中衝，程式位移，煞停在 stop_distance）→ 抵達前 slash_lead 秒
#     切 full 層 iai_slash（拔刀斬，slash_speed 倍率）、加強版火焰刀光、傷害倍率。
# 蓄力／衝刺期間 action_state 仍是 ATTACKING、_active_attack_name 仍是 "Heavy_Cut"、
# _attack_layer 切入架勢後是 "full"。
# 放開是每個物理步輪詢 Input（選單／對話會吃掉 release 事件，只靠事件會卡住）。
# ---------------------------------------------------------------------------

## RMB 按下入口。回 true = 已處理（進蓄力、或已交給 request_heavy_cut 分支）；
## false = 條件不符（連段／型中／空中／拔刀中／事件沒對應按住狀態），呼叫端走原路。
func begin_heavy_charge() -> bool:
	if not heavy_charge_enabled or not Input.is_action_pressed("attack_heavy"):
		return false
	if sword_state != SwordState.DRAWN or action_state != ActionState.FREE or not is_on_floor():
		return false
	if _hitstun_left > 0.0 or _stagger_left > 0.0:
		return false
	# 疾跑中 RMB 仍是捌型（request_heavy_cut 內部分支）；只有真的起了 Heavy_Cut 才進蓄力。
	_heavy_charge_arming = true
	request_heavy_cut()
	_heavy_charge_arming = false
	if action_state != ActionState.ATTACKING or _active_attack_name != "Heavy_Cut":
		return true
	_heavy_charging = true
	_heavy_frozen = false
	_heavy_charge_elapsed = 0.0
	_heavy_charge_ready = false
	_iai_charged = false
	_iai_target = null
	heavy_charge_changed.emit(0.0)
	return true


func is_heavy_charging() -> bool:
	return _heavy_charging


## 蓄力比例 0~1；未蓄力 = 0。
func heavy_charge_progress() -> float:
	if not _heavy_charging:
		return 0.0
	return clampf(_heavy_charge_elapsed / maxf(heavy_charge_time, 0.001), 0.0, 1.0)


## iai_in（進姿）→ iai_hold（kamae 循環）的計時切換。蓄力中與衝刺中都要跑
## （放開後 _heavy_charging 已是 false，架勢得自己走完進姿段）。
func _update_iai_stance(delta: float) -> void:
	if _iai_hold_in <= 0.0:
		return
	_iai_hold_in -= delta
	if _iai_hold_in <= 0.0:
		_iai_hold_in = 0.0
		if _iai_full_active and _tree != null:
			_switch_full("iai_hold", 1.0)


func _update_heavy_charge(delta: float) -> void:
	_heavy_charge_elapsed += delta
	_update_iai_stance(delta)
	if not _heavy_frozen:
		_action_elapsed += delta
		if _attack_progress() >= heavy_charge_freeze_progress:
			# 舉刀到位：切 full 層居合架勢。特效此刻才開 —— 短按（<0.2 s 放開）不該閃一下火星。
			_heavy_frozen = true
			_attack_layer = "full"
			_iai_full_active = true
			_iai_hold_in = iai_kamae_t
			_fire_full("iai_in", 1.0)
			if _charge_fx != null:
				_charge_fx.start()
	var t := heavy_charge_progress()
	if _charge_fx != null:
		_charge_fx.set_progress(t)
	heavy_charge_changed.emit(t)
	if not _heavy_charge_ready and t >= 1.0:
		_heavy_charge_ready = true
		if _charge_fx != null and _blade_base != null and _blade_tip != null:
			var origin: Vector3 = _blade_base.global_position
			var dir: Vector3 = (_blade_tip.global_position - origin).normalized()
			_charge_fx.flash_ready(origin, dir, self)
		if _character_audio != null:
			_character_audio.play_draw()   # 「拔刀」音：滿蓄的訊號
		if heavy_charge_auto_release:
			release_heavy_charge()
			return
	if not Input.is_action_pressed("attack_heavy"):
		release_heavy_charge()


## 放開 RMB（或滿蓄自動）。未滿 → 普通聚力單斬續播；滿 → 拔刀斬衝刺。
func release_heavy_charge() -> void:
	if not _heavy_charging:
		return
	_heavy_charging = false
	var was_ready := _heavy_charge_ready
	_heavy_charge_ready = false
	if _charge_fx != null:
		_charge_fx.stop(false)
	heavy_charge_changed.emit(-1.0)
	if not was_ready:
		_resume_heavy_cut()
		return
	_launch_iai()


## 取消（受擊硬直／死亡／翻滾／對話鎖）：同幀清乾淨，不留材質 override、燈、粒子。
## full 層架勢的淡出由呼叫端 _finish_attack 依 _attack_layer 處理（was_layer=="full" → _fade_full）。
func cancel_heavy_charge() -> void:
	if not _heavy_charging:
		return
	_heavy_charging = false
	_heavy_charge_ready = false
	if _heavy_frozen:
		_heavy_frozen = false
	_iai_hold_in = 0.0
	_iai_full_active = false
	if _charge_fx != null:
		_charge_fx.stop(true)
	heavy_charge_changed.emit(-1.0)


## 未滿蓄放開：淡掉居合架勢、重放一段普通聚力單斬。
## （atk1 在蓄力中早已於 upper 層播完淡出，沒有「續播」可言——重放才是同一刀。）
## 短按（還沒進架勢就放開）也走這裡：atk1 還在播，把 begin 時關掉的判定／刀光／音效補開。
func _resume_heavy_cut() -> void:
	if _heavy_frozen:
		_heavy_frozen = false
		_iai_hold_in = 0.0
		if _iai_full_active:
			_iai_full_active = false
			_fade_full()
		_attack_layer = "upper"
		_action_real = _heavy_len() / heavy_cut_speed
		_action_elapsed = 0.0
		_upper_finish_fade = 0.24
		_fire_upper("heavy", heavy_cut_speed)
	_hit_targets_this_swing.clear()
	if _hitbox != null:
		_hitbox.monitoring = true
	if _sword_trail != null:
		_sword_trail.reset_form()
		_sword_trail.start_trail()
	if _character_audio != null:
		_character_audio.play_heavy_swing()


## 滿蓄發動：選目標、算衝刺距離、排定落刀時點。架勢循環中衝刺，抵達前才切拔刀斬。
func _launch_iai() -> void:
	_iai_charged = true
	_hit_targets_this_swing.clear()
	if not _heavy_frozen:
		# heavy_charge_time 調得比舉刀段還短：滿蓄先到，這裡直接進架勢，衝刺時姿勢才不會自己播完。
		_heavy_frozen = true
		_attack_layer = "full"
		_iai_full_active = true
		_iai_hold_in = iai_kamae_t
		_fire_full("iai_in", 1.0)
	var target: Node3D = null
	if lock_target != null and is_instance_valid(lock_target) and lock_target.is_inside_tree():
		target = lock_target
	else:
		target = _nearest_enemy()
	# 衝不到的敵人不當目標：_nearest_enemy 看 22 m，dash 上限 8 m，鎖 20 m 外的人會在半路對空氣落刀。
	if target != null and _flat_distance_to(target) > heavy_charge_dash_max + heavy_charge_stop_distance + 0.5:
		target = null
	_iai_target = target
	var dist := minf(heavy_charge_dash_no_target, heavy_charge_dash_max)
	var yaw: float = _visual.global_rotation.y if _visual != null else global_rotation.y
	_iai_dash_dir = Vector3(sin(yaw), 0.0, cos(yaw))
	if target != null:
		var to := target.global_position - global_position
		to.y = 0.0
		if to.length_squared() > 0.0001:
			_iai_dash_dir = to.normalized()
			dist = clampf(to.length() - heavy_charge_stop_distance, 0.0, heavy_charge_dash_max)
			if _visual != null:
				_visual.global_rotation.y = atan2(to.x, to.z)
	_iai_dash_remaining = dist
	var dash_time := dist / maxf(heavy_charge_dash_speed, 0.01)
	_iai_unfreeze_in = maxf(dash_time - heavy_charge_slash_lead, 0.0)
	if _character_audio != null:
		_character_audio.play_form(8)   # 突刺音色：短、高
	CombatVFX.spawn_roll_dust(self, global_position, _iai_dash_dir)
	if dist > 0.05:
		HeavyChargeFX.spawn_dash_streaks(self, _iai_dash_dir, dash_time)
	heavy_charge_released.emit(target)


## 抵達（或到時）：切 full 層 iai_slash（拔刀斬）、slash_speed 倍率、加強版刀光、開判定。
func _unfreeze_iai_slash() -> void:
	_heavy_frozen = false
	_iai_hold_in = 0.0
	_switch_full("iai_slash", heavy_charge_slash_speed)
	# 落刀段真實時長 = clip 全長 ÷ 倍率（.res 0.958 s ÷ 2.6 ≈ 0.37 s）。
	_action_elapsed = 0.0
	_action_real = iai_slash_resource.length / maxf(heavy_charge_slash_speed, 0.01)
	if _hitbox != null:
		_hitbox.monitoring = true
	if _sword_trail != null:
		_sword_trail.apply_form({"trail": {
			"lifetime": heavy_charge_trail_lifetime,
			"extend": heavy_charge_trail_extend,
			"emission": heavy_charge_trail_emission,
		}})
		_sword_trail.start_trail()
	if _character_audio != null:
		_character_audio.play_heavy_swing()


func _flat_distance_to(n: Node3D) -> float:
	var d := n.global_position - global_position
	d.y = 0.0
	return d.length()


## 衝刺位移（_physics_process 的速度段呼叫）。回傳是否本幀由衝刺接管水平速度。
func _apply_iai_dash(delta: float) -> bool:
	if _iai_dash_remaining <= 0.0:
		return false
	var step := minf(heavy_charge_dash_speed * delta, _iai_dash_remaining)
	if _iai_target != null and is_instance_valid(_iai_target) and _iai_target.is_inside_tree():
		# 目標動了也煞停在它前面：玩家碰撞不跟敵人層互撞，不擋會穿過去揮空。
		var to := _iai_target.global_position - global_position
		to.y = 0.0
		step = minf(step, maxf(to.length() - heavy_charge_stop_distance, 0.0))
	if step <= 0.0005:
		_iai_dash_remaining = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		_iai_dash_remaining -= step
		velocity.x = _iai_dash_dir.x * step / delta
		velocity.z = _iai_dash_dir.z * step / delta
	if _iai_dash_remaining <= 0.0:
		# 煞停：重塵土（跟重落地同一層級的中性灰，不染火色）。只在到位這一幀生一次。
		CombatVFX.spawn_land_dust(self, global_position, true)
		if _iai_unfreeze_in > 0.0:
			_iai_unfreeze_in = 0.0   # 提前到位 → 本幀 _update_attack 立即落刀
	return true

func _branch_form_for_stage(stage: int) -> int:
	match stage:
		1: return branch_after_stage1
		2: return branch_after_stage2
		3: return branch_after_stage3
	return 0

## 型的取消窗口：型表 cancel.x 之後。
func _in_form_cancel_window() -> bool:
	if active_form == 0 or not SunBreathing.FORMS.has(active_form):
		return false
	var c: Vector2 = SunBreathing.FORMS[active_form].cancel
	return _attack_progress() >= c.x

## 從目前招式切到某一型（左右鍵互搭）。分支不扣呼吸、不看熟練度；冷卻與著地限制照算。
func _branch_to_form(id: int) -> bool:
	_branch_queued = 0
	if not SunBreathing.FORMS.has(id) or String(SunBreathing.FORMS[id].anim) == "":
		return false
	if form_cooldown_left(id) > 0.0:
		return false
	if not bool(SunBreathing.FORMS[id].allowed_airborne) and not is_on_floor():
		return false
	if action_state == ActionState.ATTACKING:
		_finish_attack()
	return execute_form(id, true)

## 特殊技：連續旋轉砍擊（Continuous Spinning Slash）——
## Meshy AI 衍生全身體技，高速迴旋連擊並展開刀光。
func request_continuous_spin() -> void:
	if _queue_draw_attack("special"):
		return
	var before := action_state
	request_special_attack(attack_continuous_spin_anim)
	# 招式真的發動才生龍：被擋下的輸入不得留下特效。
	if action_state == ActionState.ATTACKING and before != ActionState.ATTACKING:
		_spawn_sun_dragon()

## 玖ノ型 日暈龍・頭舞：龍身以角色為圓心掃出，頭部朝面向方向。
func _spawn_sun_dragon() -> void:
	if not sun_dragon_enabled:
		return
	var basis_node: Node3D = _visual if _visual != null else self
	var facing := basis_node.global_transform.basis.z if basis_node == _visual else -basis_node.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		facing = Vector3.FORWARD
	facing = facing.normalized()
	var xform := Transform3D(Basis.looking_at(facing, Vector3.UP), global_position)
	xform = xform.scaled_local(Vector3.ONE * sun_dragon_scale)
	var dragon := SunDragonVFX.spawn(self, xform)
	if dragon != null and sun_dragon_head_tracking:
		# 龍頭追刀尖。使用者裁定：不追比較好看，預設關閉。
		dragon.track_node = _blade_tip

## 旋轉攻擊中途換招窗口：在第一刀斬出接觸判定後（10% 進度，約 0.22 秒），隨時可切換其他招式。
const SPIN_CANCEL_WINDOW_START := 0.10

func can_cancel_continuous_spin() -> bool:
	if action_state != ActionState.ATTACKING or sword_state != SwordState.DRAWN:
		return false
	if _active_attack_name != attack_continuous_spin_anim:
		return false
	var progress := (_action_elapsed / _action_real) if _action_real > 0.0 else 1.0
	return progress >= SPIN_CANCEL_WINDOW_START

func cancel_continuous_spin() -> void:
	if _sword_trail != null:
		_sword_trail.stop_trail()
		_sword_trail.reset_form()
	if _hitbox != null:
		_hitbox.monitoring = false
	_hit_targets_this_swing.clear()
	_fade_full()
	action_state = ActionState.FREE
	_active_attack_name = ""
	_spin_buffered_cancel = ""
	_action_elapsed = 0.0
	_action_real = 0.0

func _finish_attack() -> void:
	var was_layer := _attack_layer
	# ⚠ 先擷取再 cancel：cancel_heavy_charge() 會把 _heavy_frozen 清成 false，
	#   之後才判斷就永遠落空，ts_full 的 slash_speed 殘值會帶進下一招。
	var was_iai := _heavy_frozen or _iai_charged
	if _heavy_charging:
		cancel_heavy_charge()
	if was_iai:
		# 居合架勢（full 層）與蓄力落刀（ts_full=slash_speed）都要把倍率還原，
		# 下一招才不會吃到殘值（ts_upper 已不再被蓄力寫 0，還原是保險）。
		_heavy_frozen = false
		if _tree != null:
			_tree.set("parameters/ts_upper/scale", heavy_cut_speed)
			_tree.set("parameters/ts_full/scale", 1.0)
	_iai_hold_in = 0.0
	_iai_full_active = false
	_iai_dash_remaining = 0.0
	_iai_unfreeze_in = -1.0
	_iai_charged = false
	_iai_target = null
	action_state = ActionState.FREE
	combo_stage = 0
	active_form = 0
	_active_attack_name = ""
	_spin_buffered_cancel = ""
	_branch_queued = 0
	_form_followup = ""
	_form_dash_left = 0.0
	_combo_queued_inputs = 0
	combo_input_buffered = false
	_action_elapsed = 0.0
	_action_real = 0.0
	if _sword_trail != null:
		_sword_trail.stop_trail()
		# 只還原「下一刀」的參數；已拖出來的尾巴帶著自己的 life/extend 燒完。
		_sword_trail.reset_form()
	if _hitbox != null:
		_hitbox.monitoring = false
	_hit_targets_this_swing.clear()
	if was_layer == "upper":
		_fade_upper()
	else:
		_fade_full()
	if not _form13_queue.is_empty():
		var next_id: int = _form13_queue.pop_front()
		if execute_form(next_id, true):
			return
		_form13_queue.clear()
	if _form13_running:
		_form13_running = false
		form13_finished.emit()
	if pending_sheathe and sword_state == SwordState.DRAWN:
		pending_sheathe = false
		_start_sheathe()

# ---------------------------------------------------------------------------
# Draw / Sheathe（upper layer：腿繼續 locomotion，跑步中拔/收刀不停下）
# ---------------------------------------------------------------------------
func request_sword_toggle():
	match sword_state:
		SwordState.SHEATHED:
			request_draw()
		SwordState.DRAWN:
			if action_state == ActionState.ATTACKING:
				pending_sheathe = true
			elif action_state == ActionState.FREE:
				_start_sheathe()

## 拔刀期間只保留最後一個攻擊意圖；沿用既有快速拔刀時序。
func _queue_draw_attack(kind: String) -> bool:
	if sword_state != SwordState.DRAWING and not (
		sword_state == SwordState.SHEATHED and action_state == ActionState.FREE
	):
		return false
	_attack_after_draw = true
	_draw_followup = kind
	if sword_state == SwordState.SHEATHED:
		request_draw()
	return true

func _execute_draw_followup() -> void:
	var kind := _draw_followup
	_attack_after_draw = false
	_draw_followup = "light"
	match kind:
		"heavy":
			# 拔刀後 RMB 仍按著 → 直接進蓄力（真正的「拔刀→蓄→斬」）；已放開 → 原聚力單斬。
			if not begin_heavy_charge():
				request_heavy_cut()
		"special": request_continuous_spin()
		_: _start_combo()

func request_draw():
	if sword_state != SwordState.SHEATHED:
		return
	if action_state == ActionState.DODGING or action_state == ActionState.ATTACKING:
		return
	sword_state = SwordState.DRAWING
	var spd := (draw_speed_scale * 2.2) if _attack_after_draw else draw_speed_scale
	_draw_real = draw_anim_resource.length / spd
	_draw_elapsed = 0.0
	_draw_t = 0.0
	_apply_sword_visibility()
	_upper_finish_fade = 0.16
	_fire_upper("draw", spd)

func _start_sheathe() -> void:
	sword_state = SwordState.SHEATHING
	_draw_real = draw_anim_resource.length / sheathe_speed_scale
	_draw_elapsed = 0.0
	_draw_t = 1.0
	_apply_sword_visibility()
	_upper_finish_fade = 0.16
	_fire_upper("sheathe", sheathe_speed_scale)

func _update_sword(delta: float) -> void:
	if sword_state == SwordState.DRAWING:
		var prev_t := _draw_t
		_draw_elapsed += delta
		_draw_t = clampf(_draw_elapsed / _draw_real, 0.0, 1.0) if _draw_real > 0.0 else 1.0
		_apply_sword_visibility()
		var threshold := 0.35 if _attack_after_draw else t_unsheathe
		if _attack_after_draw and _draw_t >= threshold:
			# 拔刀斬（居合）：刀一離鞘立即取消剩餘 draw、接第一段斬擊。
			sword_state = SwordState.DRAWN
			_apply_sword_visibility()
			_execute_draw_followup()
			return
		if _draw_t >= 1.0:
			sword_state = SwordState.DRAWN
			_apply_sword_visibility()
			if _attack_after_draw:
				_execute_draw_followup()
	elif sword_state == SwordState.SHEATHING:
		_draw_elapsed += delta
		_draw_t = 1.0 - (clampf(_draw_elapsed / _draw_real, 0.0, 1.0) if _draw_real > 0.0 else 1.0)
		_apply_sword_visibility()
		if _draw_t <= 0.0:
			sword_state = SwordState.SHEATHED
			_apply_sword_visibility()

## 依狀態與拔刀進度決定哪一把刀可見；反向共用同一個 t_unsheathe 門檻。
func _apply_sword_visibility():
	var in_hand := false
	match sword_state:
		SwordState.SHEATHED:
			in_hand = false
		SwordState.DRAWING, SwordState.SHEATHING:
			in_hand = _draw_t >= t_unsheathe
		SwordState.DRAWN:
			in_hand = true
	if _sword_sheathed:
		_sword_sheathed.visible = not in_hand
	if _sword_hand:
		_sword_hand.visible = in_hand
	if _tree != null:
		_tree.set("parameters/grip/blend_amount", 1.0 if in_hand and grip_overlay_enabled else 0.0)

# ---------------------------------------------------------------------------
# Sun Breathing（data-driven；定義見 sun_breathing.gd）
# ---------------------------------------------------------------------------
func add_breath(amount: float) -> void:
	var before := sun_breath_gauge
	sun_breath_gauge = clampf(sun_breath_gauge + amount, 0.0, sun_breath_max)
	if not is_equal_approx(before, sun_breath_gauge):
		breath_changed.emit(sun_breath_gauge, sun_breath_max)

## 型的冷卻剩餘秒數；0 = 就緒。由 _physics_process 每步遞減。
func form_cooldown_left(id: int) -> float:
	return float(_form_cooldowns.get(id, 0.0))

## 型目前不可用的原因（給選單顯示用）。"" = 可用。
## 順序即嚴重度：未修得 > 缺動畫 > 冷卻 > 呼吸不足 > 空中限制。
func form_block_reason(id: int) -> String:
	if not SunBreathing.FORMS.has(id):
		return "unknown"
	var def: Dictionary = SunBreathing.FORMS[id]
	if int(def.required_mastery) > sun_mastery:
		return "mastery"
	if String(def.anim) == "":
		return "no_anim"
	if form_cooldown_left(id) > 0.0:
		return "cooldown"
	if sun_breath_gauge < float(def.breath_cost):
		return "breath"
	if not bool(def.allowed_airborne) and not is_on_floor():
		return "airborne"
	return ""


func can_use_form(id: int) -> bool:
	return form_block_reason(id) == ""

## 執行單一型。缺動畫的型誠實回傳 false，不播假內容。
## 成功發動才扣呼吸與起算冷卻 —— 被擋下的輸入不得付出代價。
## free = 左右鍵互搭的連段分支：不扣呼吸、不看熟練度（呼吸夠不夠也不看），冷卻照算。
func execute_form(id: int, free := false) -> bool:
	if sword_state != SwordState.DRAWN:
		return false
	if not free and not can_use_form(id):
		return false
	if free and (not SunBreathing.FORMS.has(id) or String(SunBreathing.FORMS[id].anim) == "" \
			or form_cooldown_left(id) > 0.0):
		return false
	if action_state != ActionState.FREE:
		if _active_attack_name == attack_continuous_spin_anim and can_cancel_continuous_spin():
			cancel_continuous_spin()
		else:
			return false
	var def: Dictionary = SunBreathing.FORMS[id]
	action_state = ActionState.ATTACKING
	active_form = id
	_active_attack_name = def.anim
	_spin_buffered_cancel = ""
	combo_stage = 0
	_combo_queued_inputs = 0
	combo_input_buffered = false
	if not is_zero_approx(float(def.impulse)) and _visual:
		var yaw: float = _visual.global_rotation.y
		_form_dash = Vector3(sin(yaw), 0.0, cos(yaw)) * float(def.impulse)
		_form_dash_total = maxf(form_impulse_time, 0.001)
		_form_dash_left = _form_dash_total
		velocity.x = _form_dash.x
		velocity.z = _form_dash.z
	if def.layer == "upper":
		_attack_layer = "upper"
		var clip_len: float = _full_anim_length(def.anim) * (def.section.y - def.section.x)
		_action_real = clip_len / def.speed
		_action_elapsed = 0.0
		# 型 1/3 的 section 與 atk1/atk2 相同，直接重用 upper 段落節點。
		var section_input := "atk1" if def.section.is_equal_approx(COMBO_SECTION_RANGES[0]) else "atk2"
		_fire_upper(section_input, def.speed)
	else:
		_attack_layer = "full"
		var key := _full_input_for(def.anim)
		if key == "":
			action_state = ActionState.FREE
			active_form = 0
			return false
		_action_real = _full_anim_length(def.anim) / def.speed
		_action_elapsed = 0.0
		_fire_full(key, def.speed)
	# 真的發動了才付代價。
	if not free:
		add_breath(-float(def.breath_cost))
	if float(def.cooldown) > 0.0:
		_form_cooldowns[id] = float(def.cooldown)
	form_executed.emit(id)
	# 日之呼吸演出：起手火光＋型專用音效＋加長火焰刀光。
	if String(def.get("vfx", "")) == "ignite" and form_ignite_vfx:
		var origin: Vector3 = _blade_base.global_position if _blade_base != null else global_position + Vector3(0, 1.0, 0)
		# 火星沿刀身（刀根→刀尖）噴，不是沿角色面朝：這是「刀被點燃」不是「腳下起火」。
		var fwd: Vector3
		if _blade_base != null and _blade_tip != null:
			fwd = (_blade_tip.global_position - _blade_base.global_position).normalized()
		else:
			fwd = _visual.global_transform.basis.z if _visual != null else -global_transform.basis.z
		CombatVFX.spawn_form_ignite(self, origin, fwd)
	if _character_audio != null:
		_character_audio.play_form(id)
	if _sword_trail != null:
		# 型的刀光側寫（FORMS.trail）必須在 start_trail() 之前套，
		# 否則第一個取樣點會拿到普通刀光的壽命與寬度。
		_sword_trail.apply_form(def)
		_sword_trail.start_trail()
	_hit_targets_this_swing.clear()
	if _hitbox != null:
		_hitbox.monitoring = true
	return true

## 拾參ノ型：把可用的前十二型按 FORM13_SEQUENCE 高速循環（框架；
## 解鎖條件 = form13_unlocked 或 gauge 滿）。缺動畫的型跳過。
func start_form13() -> bool:
	if sword_state != SwordState.DRAWN or action_state != ActionState.FREE:
		return false
	if not form13_unlocked and sun_breath_gauge < form13_gauge_cost:
		return false
	_form13_queue.clear()
	for id in SunBreathing.FORM13_SEQUENCE:
		# 十三型 = 十二型連放：只要有動畫、不在冷卻就排進去（不看熟練度／呼吸）。
		if SunBreathing.FORMS.has(id) and String(SunBreathing.FORMS[id].anim) != "" and form_cooldown_left(id) <= 0.0 \
				and (bool(SunBreathing.FORMS[id].allowed_airborne) or is_on_floor()):
			_form13_queue.append(id)
	if _form13_queue.is_empty():
		return false
	sun_breath_gauge = 0.0
	breath_changed.emit(sun_breath_gauge, sun_breath_max)
	var first: int = _form13_queue.pop_front()
	if not execute_form(first, true):
		_form13_queue.clear()
		return false
	_form13_running = true
	form13_started.emit()
	return true
