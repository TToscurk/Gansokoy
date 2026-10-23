class_name IsshinCombatLocomotion
extends Node
## 獨立候選：戰鬥警戒步行（鎖定敵人、始終面向敵人移動）。
## 與 yoriichi_character.gd（跑酷）完全分離：不引用、不覆蓋；之後要接進 Player 時，只需要在「戰鬥警戒」狀態下呼叫 step()。
##
## 動作來源（皆為《隻狼》c5400 a000，經 v24_isshin 管線重定向）：
##   待機 400000、前走 405000、後退 405001、左移 405002、右移 405003、快走 405010、
##   原地轉身 405400/405401（90°）405402/405403（180°）、閃避步 405012/405013（左／右）。
## 庫裡沒有專用的起步／停步動作（掃描 347 支 a000 的首尾姿勢，起步候選 0 支）：
##   起步＝把前進動作跳到「經過相位」（兩腳最靠近待機站姿）再從 0 加速；
##   停步＝從放開輸入起，在 0.28–0.70 s 內把速度與播放速度一起線性減到 0，並挑能落在經過相位附近的時長。
##
## 座標：actor 朝 +Z；角色的右手邊 = -X；偏航 + = 向左轉（繞 +Y）。

const HipTwist = preload("res://characters/yoriichi/v24_isshin/hip_twist_modifier.gd")
const FootLock = preload("res://characters/yoriichi/v24_isshin/foot_lock_modifier.gd")
const ClothTuning = preload("res://characters/yoriichi/v24_isshin/cloth_tuning.gd")
const TwoHandGrip = preload("res://characters/yoriichi/v24_isshin/two_hand_grip.gd")
const HITSTOP_FRAMES := 3          # 命中停格幀數（60 fps；3 幀 ≈ 50 ms，2026-10-20 與 5 幀／83 ms 比較後採用：83 ms 讓跨步中的身體懸停過久、打斷兩刀節奏）。攻擊方動畫、位移與受擊方一起凍結，布料／頭髮照常模擬
const ANIM_DIR := "res://characters/yoriichi/v24_isshin/anims/"
const SPEED := {"fwd": 0.490, "back": 0.443, "left": 0.419, "right": 0.447, "brisk": 0.976}   # m/s，站立腳接觸速度中位數（不是一心的根位移）
const CLIP_LEN := {"walk": 2.3333, "back": 2.3333, "strafe_l": 2.3333, "strafe_r": 2.3333, "run": 1.1667, "sprint": 0.5333}
const PASS := {"walk": [0.114, 0.686], "back": [0.386, 0.900], "strafe_l": [0.429, 0.871], "strafe_r": [0.171, 0.643], "run": [0.114, 0.686], "sprint": [0.188, 0.625]}
## R9（選用）：衝刺循環（弦一郎 c7100 a000_405010 跑步，0.533 s）。場景在 setup() 前設 sprint_anim 才會加進方向混合（輸入 y＝3）；
## 速度＝重定向後站立腳接觸速度 4.19 m/s；PASS／STANCE_AT["sprint"] 由 notes/r9 量得（兩腳交會相位 0.188 左腳撐地、0.625 右腳撐地）。
var sprint_anim := ""
var sprint_speed := 4.19
## R10（選用）：刀在鞘中的移動（c1400 居合型 a100 的居合構步行組，build：notes/r10/build_sheathed_loco.py）。
## 場景在 setup() 前設 sheathed 才會多建一組方向混合；iai_mode 時改用這組（可走、跑、衝刺、轉身、閃避）。
## 沒設＝舊行為（居合模式不能移動），既有候選完全不受影響。
## 格式：{"anims": {walk, back, strafe_l, strafe_r, run}, "speed": {fwd, back, left, right, run, sprint}, "len": {...}, "pass": {...}, "stance": {...},
##        "turn": {"l90": key, "r90": key}}
var sheathed := {}
var _sh_w := 0.0
## R11（選用，預設 false＝舊行為）：待機姿勢在居合構與持刀待機之間交叉淡入（0.2 s），不再於拔刀／納刀結束那一格直接換待機動畫
## （舊行為站著拔刀時髖部一格跳 0.25 m）。需要 sheathed 已設，場景在 setup() 前設。
var smooth_stance := false
var _ii_w := 0.0
## 各循環動作的兩個「經過相位」(PASS) 對應的支撐腳（由 scan_planted.gd 實測：該相位哪隻腳貼地、偏移≈9 cm、速度≈行進速度）
const STANCE_AT := {"walk": ["Left", "Right"], "back": ["Right", "Left"], "strafe_l": ["Right", "Left"], "strafe_r": ["Left", "Right"], "run": ["Left", "Right"], "sprint": ["Left", "Right"]}
const T_START := 0.45
const T_STOP_MIN := 0.45
const T_STOP_MAX := 0.85
const STRAFE_CHEST := deg_to_rad(33.0)   # 一心橫移動作的軀幹本身側轉約 52°（腿與骨盆約 60°）；脊椎補回 33° 讓肩線接近前走時的朝向
const BLEND_RATE := 3.5
const REVERSE_BRAKE := 0.22
const TURN_TRIGGER := deg_to_rad(50.0)
const AIM_MAX := deg_to_rad(38.0)
const DODGE_SCALE := 0.55       # 閃避位移＝一心根位移（約 3.6 m）× 0.55 ≈ 2.0 m。閃避是騰空滑步，腳無接地期可量，距離依可信的人體速度（峰值約 4.8 m/s）而非一心的原始位移
const SHOTS := {
	"turn_l90": {"anim": "isshin_turn_l90", "angle": 90.0, "fade_in": 0.05, "fade_out": 0.14},
	"turn_r90": {"anim": "isshin_turn_r90", "angle": -90.0, "fade_in": 0.05, "fade_out": 0.14},
	"turn_l180": {"anim": "isshin_turn_l180", "angle": 180.0, "fade_in": 0.05, "fade_out": 0.14},
	"turn_r180": {"anim": "isshin_turn_r180", "angle": -180.0, "fade_in": 0.05, "fade_out": 0.14},
	"dodge_l": {"anim": "isshin_dodge_l", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.18},
	"dodge_r": {"anim": "isshin_dodge_r", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.18},
	# ---- 攻擊（notes/build_combo.py 烘焙；30 fps 第 k 格；根位移已是公尺的動作 travel_scale＝1）
	# 取消窗（秒，shot_t）：next＝在 [open, close] 內按攻擊接下一刀（只記一次；seam 之前切換姿勢逐格相同，之後淡入 0.08 s）；
	# dodge_cancel／move_cancel＝之後按閃避／移動可提早結束（刀已過有效攻擊段）；lunges＝前衝段（開始時依離目標距離整段等比縮短位移）。
	# 一心 TAE 3038（hkx a000_003012）第一刀：中段 → 上段 → 直劈 → 殘心（f0–f19＋12 格定格殘心）；判定 f11–15。
	"slash_v": {"anim": "isshin_slash_v", "angle": 0.0, "fade_in": 0.08, "fade_out": 0.18, "travel_scale": 0.55, "two_hand": true, "attack": true,
		"strikes": [[11.0 / 30.0, 15.0 / 30.0]], "swings": [0.33], "lockout": 0.30, "lunges": [[0.0, 19.0 / 30.0]],
		"next": {"key": "slash_vh", "open": 0.10, "close": 0.70, "seam": 19.0 / 30.0}, "dodge_cancel": 19.0 / 30.0, "move_cancel": 0.70,
		"min_dist": 0.85, "lunge_min_dist": [0.95], "freeze_hit_frame": true},
	# 兩刀：k0–18＝縱斬（同 slash_v，無定格殘心）；k19–27 交接（左腳釘地、右腳後撤）；k28–121＝3071 橫斬 f9–102（3071 f → k＝f＋19）。
	# 橫斬判定 f14–19 → k33–38；刀掃完（刀尖 < 7 m/s）在 f17；放左手 f52 → k71。
	# 取消：接第三刀 f17–30（k36–49，交接起點 k40）；閃避 f21（k40）；移動 f26（k45＝TAE ComboAttack 旗標）。原本 2.9 s 才能動。
	# R9（共用刀身判定）：第二刀橫斬在原本的 0.95 m 停點只擦過木樁（舊的寬鬆判定半徑 0.30 才算中）→ 第二段前衝改停 0.85 m
	# （lunge_min_dist；第一刀仍 0.95 m），三刀都是刀身切進 7–18 cm、雙手離木樁軸 ≥ 0.42 m；並改成停在命中那一格（freeze_hit_frame）。
	"slash_vh": {"anim": "isshin_slash_vh", "angle": 0.0, "fade_in": 0.08, "fade_out": 0.25, "travel_scale": 1.0, "two_hand": true, "attack": true,
		"strikes": [[11.0 / 30.0, 15.0 / 30.0], [33.0 / 30.0, 38.0 / 30.0]], "swings": [0.33, 0.99], "grip_off": 71.0 / 30.0, "lockout": 0.20,
		"lunges": [[0.0, 19.0 / 30.0], [28.0 / 30.0, 38.0 / 30.0], [39.0 / 30.0, 45.0 / 30.0]],
		"next": {"key": "slash_vhx", "open": 36.0 / 30.0, "close": 49.0 / 30.0, "seam": 40.0 / 30.0}, "dodge_cancel": 40.0 / 30.0, "move_cancel": 45.0 / 30.0,
		"min_dist": 0.85, "lunge_min_dist": [0.95, 0.85, 0.95], "freeze_hit_frame": true},
	# 三刀：k0–39 同 slash_vh；k40–47 交接（3071 收刀前 × 3031 左上舉刀，右腳釘地）；k48–150＝一心 TAE 3031 雙手左上→右下袈裟斬 f13–115（3031 f → k＝f＋35），結尾回到待機姿。
	# 判定 f18–23 → k53–58；放左手 f22 → k57；閃避 f28（k63）；移動 f40（k75＝TAE ComboAttack 旗標）。
	"slash_vhx": {"anim": "isshin_slash_vhx", "angle": 0.0, "fade_in": 0.08, "fade_out": 0.25, "travel_scale": 1.0, "two_hand": true, "attack": true,
		"strikes": [[11.0 / 30.0, 15.0 / 30.0], [33.0 / 30.0, 38.0 / 30.0], [53.0 / 30.0, 58.0 / 30.0]], "swings": [0.33, 0.99, 1.70],
		"grip_off": 57.0 / 30.0, "lockout": 0.20, "lunges": [[0.0, 19.0 / 30.0], [28.0 / 30.0, 38.0 / 30.0], [39.0 / 30.0, 58.0 / 30.0]],
		"dodge_cancel": 63.0 / 30.0, "move_cancel": 75.0 / 30.0, "min_dist": 0.85, "lunge_min_dist": [0.95, 0.85, 0.95], "freeze_hit_frame": true},
	# 跨角色融合候選（第三刀換成葦名弦一郎 c7100 TAE 3001：雙手、左腳上步、振りかぶり → 唐竹斬，斬完即可接招，結尾停在弦一郎警戒姿）：
	# k0–39 同 slash_vh；k40–46 交接（3071 收刀前 × 3001 f0–6，右腳釘地）；k47–111＝3001 f7–71（3001 f → k＝f＋40）。根位移 × 0.6（弦一郎腿長比 0.85）。
	# 判定 f23–26 → k63–66；放左手 f26 → k66；TAE ComboAttack 旗標 f27 → k67：閃避／移動 k68。
	"slash_vhg": {"anim": "isshin_slash_vhg", "angle": 0.0, "fade_in": 0.08, "fade_out": 0.45, "travel_scale": 1.0, "two_hand": true, "attack": true,
		"strikes": [[11.0 / 30.0, 15.0 / 30.0], [33.0 / 30.0, 38.0 / 30.0], [63.0 / 30.0, 66.0 / 30.0]], "swings": [0.33, 0.99, 2.00],
		"grip_off": 66.0 / 30.0, "lockout": 0.20, "lunges": [[0.0, 19.0 / 30.0], [28.0 / 30.0, 38.0 / 30.0], [39.0 / 30.0, 66.0 / 30.0]],
		"dodge_cancel": 68.0 / 30.0, "move_cancel": 68.0 / 30.0, "min_dist": 0.85, "lunge_min_dist": [0.95, 0.85, 0.95], "freeze_hit_frame": true,
		"end_t": 84.0 / 30.0},     # 3001 f44：弦一郎斬後的低位持刀與一心待機（右側低持）接近；之後 f46–71 是弦一郎自己的中段構，不用，直接淡回
	# 葦名流居合（說明見 set_iai_mode 上方註解）
	"iai": {"anim": "isshin_iai", "angle": 0.0, "fade_in": 0.08, "fade_out": 0.20, "travel_scale": 0.65, "two_hand": false, "attack": true,
		"strikes": [[7.0 / 30.0, 24.0 / 60.0]], "swings": [0.06], "lockout": 0.10, "lunges": [[0.0, 0.42]], "move_cancel": 2.10, "dodge_cancel": 2.10,
		# 前衝收在離目標中心 0.55 m，且出招時身體轉到讓目標落在右前 30°（80°/s，約 0.37 s 轉完）：刀在 0.30–0.33 s 向右甩過右前方，
		# 刀身外段（物打，刀尖往內約 25 cm）切進木樁、0.42 s 時切到木樁中心；左手／右手離木樁軸 ≥ 0.39 m（木樁半徑 0.24）。
		# 原本正對＋0.50 m：刀尖最近只到木樁表面外 1–6 cm（判定半徑 0.30 比木樁大才算中），而前伸的左手停在離木樁軸 7–14 cm（插進木樁）。
		# 判定窗：TAE 7–10（0.233–0.333 s）延到 0.40 s——0.333 s 起刀身外段才真正在木樁裡（0.33–0.45 s 深 5–23 cm）；原窗只到 0.333 s 時，
		# 30／50 fps 或木樁移動 0.3 m/s 都會整招漏判。判定範圍（刀身、實際半徑、切入 5 cm）不變。
		"min_dist": 0.55, "aim_offset": -30.0},
	# 葦名流二連斬（候選）：c1400 居合型 a100_003010（TAE 100003010）。鞘中起手，0.23–0.37 s 拔刀，第一刀 TAE 12–14（0.40–0.467 s）由左下往右上
	# 逆袈裟上撩、第二刀 TAE 17–19（0.567–0.633 s）沿同一條斜線袈裟斬回左下（兩刀刀路平面夾角 166°，不是十字）；0.7–1.6 s 殘心、
	# 1.6–2.3 s 血振、2.47–3.03 s 納刀。notes/build_twocut.py；判定沿用居合候選的刀身判定（實際半徑、切入 5 cm、掃掠）。
	"twocut": {"anim": "isshin_twocut", "angle": 0.0, "fade_in": 0.08, "fade_out": 0.20, "travel_scale": 0.65, "two_hand": false, "attack": true,
		"strikes": [[24.0 / 60.0, 28.0 / 60.0], [34.0 / 60.0, 38.0 / 60.0]], "swings": [0.30, 0.52], "lockout": 0.10,
		"lunges": [[0.0, 28.0 / 60.0], [28.0 / 60.0, 40.0 / 60.0]], "move_cancel": 3.05, "dodge_cancel": 3.05,
		# 前衝停在離目標中心 1.20 m（掃參數：0.8–1.0 m 時單手揮出的右手會穿進木樁，離木樁軸只剩 0.07–0.17 m）
		"min_dist": 1.20, "aim_offset": 0.0, "freeze_hit_frame": true},
	# 前衝突刺（候選）：c1400 a000「剣客 守り／攻めタイプ」a000_003014（TAE 3014），雙手、刀已出鞘；命中窗內刀軸朝正前方（F≈1.0），
	# 刀尖在骨盆前 1.6 m（原尺寸）。判定 TAE 7–16（0.233–0.533 s）；原動作 0.20–0.35 s 前衝 2.5 m（峰值約 17 m/s），全長 1.68 s、總前進 3.16 m。
	# 取消：TAE 旗 0x49／0x7A／23 在 f40–41（1.33 s）→ 移動取消；閃避取消提前到 0.70 s（根位移已停、刀已收回中段）。
	"thrust": {"anim": "isshin_thrust", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 0.93, "two_hand": true, "attack": true,
		"strikes": [[7.0 / 30.0, 16.0 / 30.0]], "swings": [0.18], "lockout": 0.10, "lunges": [[0.0, 0.40]],
		"move_cancel": 40.0 / 30.0, "dodge_cancel": 0.70, "min_dist": 1.20, "freeze_hit_frame": true},     # min_dist：掃 0.9–1.4 m，1.2 m 時雙手離木樁軸 ≥ 0.52 m、刀尖外 25% 刺入
	# 退步縱斬（候選）：c1400 a000「剣客 守り／攻めタイプ」a000_003009（TAE 3009），雙手、刀已出鞘。舉刀過頂（刀尖朝後上），判定 TAE 12–16
	# （0.40–0.533 s）內刀由頭頂後方劈到身前下方（刀尖最遠在骨盆前 1.4 m）；後退從 0.4 s 開始、0.6 s 時退 1.0 m、全長 2.10 s 共退 2.48 m（原尺寸）。
	# 取消：TAE 旗 0x49／0x7A 在 f42（1.40 s）→ 移動取消；閃避取消 1.00 s（後退已停）。後退方向不受 min_dist 夾住（只夾朝目標的位移）。
	"backcut": {"anim": "isshin_backcut", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 0.93, "two_hand": true, "attack": true,
		"strikes": [[12.0 / 30.0, 16.0 / 30.0]], "swings": [0.38], "lockout": 0.10,
		"move_cancel": 42.0 / 30.0, "dodge_cancel": 1.00, "freeze_hit_frame": true},
	# 雙手交叉二連斬（候選）：c1400 a000「剣客」a000_003072 f0–49 → 10 格橋接（左腳踩定、右腳前踏 0.21 m）→ a000_003056 f26–130（60 fps，根位移已烘成公尺）。
	# 第一刀 3072 TAE 17–20（0.567–0.667 s）左上→右下；第二刀 3056 TAE 14–16 → 合成後 1.050–1.117 s 右上→左下（兩條刀路在正面成 X）。
	# 取消：3056 的 TAE 旗 23（f25）→ 合成後 1.42 s 可閃避；旗 0x49／0x7A（f38）→ 1.85 s 可移動。
	"pairx": {"anim": "isshin_pairx", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 1.0, "two_hand": true, "attack": true,
		"strikes": [[34.0 / 60.0, 40.0 / 60.0], [63.0 / 60.0, 69.0 / 60.0]], "swings": [0.52, 0.98], "lockout": 0.10,     # 第二刀窗延 2 格到 1.15 s：刀在 1.08–1.11 s 穿過木樁，30 fps 時那一格落在 1.133 s
		"lunges": [[0.0, 40.0 / 60.0], [50.0 / 60.0, 67.0 / 60.0]],
		"move_cancel": 111.0 / 60.0, "dodge_cancel": 85.0 / 60.0, "min_dist": 1.40, "freeze_hit_frame": true},     # min_dist：掃 1.0–1.4 m，1.4 m 時兩刀都是刀身外段命中、雙手離木樁軸 ≥ 0.61 m
	# ==== BATCH MOVES BEGIN（notes/gen_batch_moves.py 產生；手改會被覆蓋）
	# 側閃橫斬（永真 3015）：閃避後反擊：左跨步再單手橫斬（c7400 TAE 3015；判定 [[0.5333, 0.6]]；全長 3.5 s）
	"q_sidecut": {"anim": "isshin_q_sidecut", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 1.107, "two_hand": false, "attack": true, "strikes": [[0.5333, 0.6]], "lockout": 0.1, "lunges": [[0.0, 0.6]], "move_cancel": 0.767, "dodge_cancel": 0.8, "min_dist": 1.1, "freeze_hit_frame": true, "attack_cancel": 0.767},
	# 側跨縱斬（一心 3084）：大幅右跨 4.6 m 繞側後縱斬（c5400 TAE 3084；判定 [[0.8, 0.9333]]；全長 3.833 s）
	"q_sidevert": {"anim": "isshin_q_sidevert", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 0.78, "two_hand": false, "attack": true, "strikes": [[0.8, 0.9333]], "lockout": 0.1, "lunges": [[0.0, 0.9333]], "move_cancel": 1.833, "dodge_cancel": 1.0, "min_dist": 0.9, "freeze_hit_frame": true, "attack_cancel": 1.0},
	# 轉身退步橫斬（一心 3025）：向左轉 90° 退開同時雙手橫斬（c5400 TAE 3025；判定 [[0.6667, 0.8]]；全長 3.5 s）
	"q_pivotcut": {"anim": "isshin_q_pivotcut", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 0.78, "two_hand": true, "attack": true, "strikes": [[0.6667, 0.8]], "lockout": 0.1, "lunges": [[0.0, 0.8]], "move_cancel": 1.133, "dodge_cancel": 0.833, "min_dist": 0.9, "freeze_hit_frame": true, "attack_cancel": 0.833, "root_yaw": true},
	# 旋身穿身斬（永真 3021）：衝刺中旋身 180° 橫斬（c7400 TAE 3021；判定 [[1.0, 1.1333]]；全長 4.167 s）
	"q_spinpass": {"anim": "isshin_q_spinpass", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 1.107, "two_hand": true, "attack": true, "strikes": [[1.0, 1.1333]], "lockout": 0.1, "lunges": [[0.0, 1.1333]], "move_cancel": 1.267, "dodge_cancel": 1.5, "min_dist": 0.9, "freeze_hit_frame": true, "attack_cancel": 1.267, "root_yaw": true},
	# 躍斬（弦一郎 3022）：躍起 0.9 m 雙手縱斬（c7100 TAE 3022；判定 [[0.9, 1.0]]；全長 2.833 s）
	"q_jumpcut": {"anim": "isshin_q_jumpcut", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 0.852, "two_hand": true, "attack": true, "strikes": [[0.9, 1.0]], "lockout": 0.1, "lunges": [[0.0, 1.0]], "move_cancel": 1.1, "dodge_cancel": 2.167, "min_dist": 1.1, "freeze_hit_frame": true, "attack_cancel": 1.1},
	# 空中二連（弦一郎 3026）：躍起 1.5 m 空中兩記橫斬（原動作第一刀突刺搆不到木樁，判定只留空中兩刀）（c7100 TAE 3026；判定 [[0.9667, 1.0667], [1.3333, 1.4333], [2.2, 2.3]]；全長 5.067 s）
	"q_aerial3": {"anim": "isshin_q_aerial3", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 0.852, "two_hand": true, "attack": true, "strikes": [[1.3333, 1.4333], [2.2, 2.3]], "lockout": 0.1, "lunges": [[0.0, 2.3]], "move_cancel": 3.867, "dodge_cancel": 3.8, "min_dist": 0.9, "freeze_hit_frame": true, "attack_cancel": 3.8},
	# 三連斬（弦一郎 3041）：突→袈裟→逆袈裟的快速三連（c7100 TAE 3041；判定 [[0.1667, 0.2667], [0.4667, 0.5667], [1.2667, 1.4]]；全長 3.233 s）
	"q_gen3": {"anim": "isshin_q_gen3", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 0.852, "two_hand": false, "attack": true, "strikes": [[0.1667, 0.2667], [0.4667, 0.5667], [1.2667, 1.4]], "lockout": 0.1, "lunges": [[0.0, 1.4]], "move_cancel": 2.333, "dodge_cancel": 2.267, "min_dist": 1.1, "freeze_hit_frame": true, "attack_cancel": 2.267},
	# 快速二連（永真 3019）：0.13 s 間隔的逆袈裟＋袈裟（c7400 TAE 3019；判定 [[0.5333, 0.6333], [0.6667, 0.7667]]；全長 4.567 s）
	"q_emma2": {"anim": "isshin_q_emma2", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 1.107, "two_hand": false, "attack": true, "strikes": [[0.5333, 0.6333], [0.6667, 0.7667]], "lockout": 0.1, "lunges": [[0.0, 0.7667]], "move_cancel": 1.0, "dodge_cancel": 2.033, "min_dist": 0.9, "freeze_hit_frame": true, "attack_cancel": 1.0},
	# 極短快斬（弦一郎 3002）：1.4 s 全長的單手小斬（c7100 TAE 3002；判定 [[0.2667, 0.3667]]；全長 1.333 s）
	"q_flick": {"anim": "isshin_q_flick", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 0.852, "two_hand": false, "attack": true, "strikes": [[0.2667, 0.3667]], "lockout": 0.1, "lunges": [[0.0, 0.3667]], "move_cancel": 0.567, "dodge_cancel": 0.533, "min_dist": 0.9, "freeze_hit_frame": true, "attack_cancel": 0.533},
	# 單手袈裟快斬（永真 3067）：單手袈裟、0.67 s 可取消（c7400 TAE 3067；判定 [[0.5, 0.6]]；全長 2.833 s）
	"q_emmacut": {"anim": "isshin_q_emmacut", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 1.107, "two_hand": false, "attack": true, "strikes": [[0.5, 0.6]], "lockout": 0.1, "lunges": [[0.0, 0.6]], "move_cancel": 0.8, "dodge_cancel": 0.667, "min_dist": 1.2, "freeze_hit_frame": true, "attack_cancel": 0.667},
	# 突進逆袈裟（永真 3027）：前衝 5 m 單手由右下往左上斬（弦一郎 3038 突進橫斬因刀身穿過軀幹 15 cm 淘汰）（c7400 TAE 3027；判定 [[0.5, 0.6333]]；全長 2.867 s）
	"q_dashcut": {"anim": "isshin_q_dashcut", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 1.107, "two_hand": false, "attack": true, "strikes": [[0.5, 0.6333]], "lockout": 0.1, "lunges": [[0.0, 0.6333]], "move_cancel": 1.567, "dodge_cancel": 1.5, "min_dist": 1.2, "freeze_hit_frame": true, "attack_cancel": 1.5},
	# 居合上撩（葦名流 a100_3011，刀留手上）：拔刀由左腰往右上撩斬、不納刀直接轉一般架勢（c1400 TAE 100003011；判定 [[0.2667, 0.4333]]；全長 2.0 s）
	"q_iaiup": {"anim": "isshin_q_iaiup", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 0.93, "two_hand": false, "attack": true, "strikes": [[0.2667, 0.4333]], "lockout": 0.1, "lunges": [[0.0, 0.4333]], "move_cancel": 0.767, "dodge_cancel": 1.167, "min_dist": 1.2, "freeze_hit_frame": true, "attack_cancel": 0.767},
	# 邊退邊斬（主城劍客 3013）：先退再於後退中劈下（c1400 TAE 3013；判定 [[0.3333, 0.4667]]；全長 2.833 s）
	"q_retreat": {"anim": "isshin_q_retreat", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 0.929, "two_hand": true, "attack": true, "strikes": [[0.3333, 0.4667]], "lockout": 0.1, "lunges": [[0.0, 0.4667]], "move_cancel": 2.4, "dodge_cancel": 1.0, "min_dist": 0.9, "freeze_hit_frame": true, "attack_cancel": 1.0},
	# 進身二連：突進逆袈裟→袈裟（永真 3027→3067）：衝刺上撩後順勢袈裟斬回（銜接殘差：手 0.03 m、刀 76°、肩 5°）（c7400 TAE 3067；判定 [[0.5, 0.6], [1.1667, 1.2667]]；全長 3.5 s）
	"q_c_emma": {"anim": "isshin_q_c_emma", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 1.0, "two_hand": false, "attack": true, "strikes": [[0.5, 0.6], [1.1667, 1.2667]], "lockout": 0.1, "lunges": [[0.0, 0.6], [0.85, 1.2666666666666666]], "move_cancel": 1.467, "dodge_cancel": 1.334, "min_dist": 1.2, "freeze_hit_frame": true, "attack_cancel": 1.334},
	# 退斬反刺：邊退邊斬→前衝突刺（主城劍客 3013→3014）：先退開斬一刀、回到架勢立即前衝突刺（銜接殘差：手 0.05 m、刀 0°、腳 0.06 m）（c1400 TAE 3014；判定 [[0.3333, 0.4667], [1.35, 1.65]]；全長 2.783 s）
	"q_c_retthrust": {"anim": "isshin_q_c_retthrust", "angle": 0.0, "fade_in": 0.06, "fade_out": 0.25, "travel_scale": 1.0, "two_hand": true, "attack": true, "strikes": [[0.3333, 0.4667], [1.35, 1.65]], "lockout": 0.1, "lunges": [[0.0, 0.4667], [1.1166666666666667, 1.65]], "move_cancel": 2.45, "dodge_cancel": 1.817, "min_dist": 1.2, "freeze_hit_frame": true, "attack_cancel": 1.817},
	# 拔刀（試玩場景用）：居合斬動畫的前 0.13 s（刀經鞘口出鞘）再淡回一般架勢
	"draw": {"anim": "isshin_draw", "angle": 0.0, "fade_in": 0.05, "fade_out": 0.22, "travel_scale": 0.0, "two_hand": false, "attack": true, "strikes": [], "lockout": 0.0, "end_t": 0.13},
	# 收刀（試玩場景用）：二連斬動畫的納刀段（2.40 s 起：刀尖對鞘口 → 入鞘 → 居合構）
	"noto": {"anim": "isshin_noto", "angle": 0.0, "fade_in": 0.15, "fade_out": 0.20, "travel_scale": 0.0, "two_hand": false, "attack": true, "strikes": [], "lockout": 0.0, "start_t": 2.40},
	# ==== BATCH MOVES END
}
## 葦名流居合（候選）：c1400「剣客_居合」（佐瀬甚助 NpcParam 14000200／水生氏成 14004200，皆用 SpEffect 200031 → a100 動畫組）的
## 快速拔刀橫斬 a100_003021（TAE 100003021）。notes/build_iai.py 已把拔刀（f0–6，0.10 s 出鞘）與納刀（f66–124）改成刀身經過緣一自己的鞘口；
## 判定 TAE f7–10（0.233–0.333 s）；收刀完成 f124（2.07 s）後才可移動（中途取消會讓刀留在鞘外，居合模式不允許）。根位移 × 0.65（腿長比 0.93）。
## 居合模式：待機換成居合構（鞘中刀），攻擊鍵改成居合；此模式下不走路（走路動作是手上持刀的）
var iai_mode := false
## 居合模式下攻擊鍵出哪一招（預設居合斬；二連斬候選 demo 設成 "twocut"）
var iai_key := "iai"
## 一般（刀在手上）模式下攻擊鍵出哪一招（預設縱斬起手的連段；突刺候選 demo 設成 "thrust"）
var attack_key := "slash_v"

func set_iai_mode(on: bool) -> void:
	iai_mode = on
	if smooth_stance and (tree.tree_root as AnimationNodeBlendTree).has_node("imix"):
		return                                   # R11：由 imix 交叉淡入（step 裡）
	var idle := (tree.tree_root as AnimationNodeBlendTree).get_node("idle") as AnimationNodeAnimation
	idle.animation = "isshin_iai_stance" if on else "isshin_idle"

## 第三刀用哪一支（"slash_vhx"＝一心 3031；"slash_vhg"＝弦一郎 3001 融合候選）
var third_key := "slash_vhx"
## 攻擊位移不把角色推進到離鎖定目標中心小於這個距離（木樁半徑 0.26 m＋身體約 0.3 m＋餘裕）
const ATTACK_MIN_DIST := 0.95
var attack_min_dist := ATTACK_MIN_DIST
enum S { IDLE, MOVE, SHOT }
const HIP_RATE_MOVE := deg_to_rad(100.0)   # 行進中髖部轉向最大速率（過快會讓支撐腳滑）
const HIP_RATE_IDLE := deg_to_rad(35.0)    # 停下後腿部回正的速率

## 斜向移動方式："blend" = 兩個方向動作混合（無髖部扭轉）；"twist" = 單一方向動作 + 髖部扭轉朝移動方向、胸口仍朝敵人
var diag_mode := "twist"

var actor: Node3D
var rig: YoriichiV24Rig
var tree: AnimationTree
var twist: HipTwist
var foot_lock: FootLock
## 起步／停步／反向／待機時的局部腳掌鎖定 IK（轉身與騰空閃避不用）。
var foot_lock_on := true
var stance_start := "Left"
var stop_stance := "Left"
var target: Node3D = null
var roots := {}
var state := S.IDLE
var g := 0.0                    # 步行閘門 0..1（同時是播放速度）
var stopping := false
var stop_rate := 3.0
var loco_t := 0.0
var bp := Vector2(0, 1)
var hip_yaw := 0.0
var hip_yaw_target := 0.0
var chest_yaw := 0.0
var strafe_bias := 0.0
var shot_key := ""
var shot_t := 0.0
var shot_prev := Vector3.ZERO   # (yaw_rad_sekiro, left_m, fwd_m)
var shot_yaw_scale := 1.0
var cooldown := 0.0
var turn_pending := 0.0        # 誤差超過門檻後經過的秒數；等 0.10 s 讓目標方位穩定再選 90°/180°
var last_x := -1.0
var label := "idle"
var body_velocity := Vector3.ZERO     # actor 局部（Godot）速度，量測用
var grip: TwoHandGrip = null
var hit_test: Callable = Callable()   # 由場景設定：() -> Dictionary（空＝沒打到；{pos, dir}＝命中）
var hits_done: Array = []            # 每個判定窗各自只算一次命中（停格期間不檢查）
var swings_done: Array = []
var hitstop_frames := HITSTOP_FRAMES
var hitstop_left := 0
var hitstop_total := 0               # 量測用：本場累計停格幀數
var combo_queued := false
var lunge_idx := -1
var lunge_fit := 1.0
var fit_log: Array = []              # 量測用
var cancel_log: Array = []           # 量測用
var atk_w := 0.0                     # 攻擊分支權重（腳本控制淡入淡出）
var atk_target := 0.0
var atk_fade := 0.1
var combo_switch_t := -1.0           # 量測用：切到連段動作時的 shot_t
var clamp_total := 0.0               # 量測用：被最小距離擋下的前進量（m）
## root_yaw 招式（動作本身帶轉身，例：轉身斬）：出招當下的朝向；根位移以這個朝向套用，角色朝向跟著動作的偏航轉
var shot_basis0 := Basis.IDENTITY
## 單發結束（自然結束或被取消）時通知場景：key、結束時的 shot_t、是否中途取消（候選場景用來切換武器狀態）
signal shot_finished(key: String, t: float, cancelled: bool)
signal swing_started(idx: int)
signal hit_landed(info: Dictionary)

func setup(actor_: Node3D, rig_: YoriichiV24Rig, cloth_fix := true) -> void:
	actor = actor_
	rig = rig_
	if cloth_fix:
		ClothTuning.apply(rig)
	var ap := rig.anim_player
	var lib := ap.get_animation_library("")
	var names := ["isshin_idle", "isshin_walk", "isshin_back", "isshin_strafe_l", "isshin_strafe_r", "isshin_run", "isshin_iai_stance"]
	if sprint_anim != "":
		names.append(sprint_anim)
	for k in (sheathed.get("anims", {}) as Dictionary):
		if not names.has(sheathed["anims"][k]):
			names.append(sheathed["anims"][k])
	shots = SHOTS.duplicate()
	shots.merge(extra_shots, true)
	for k in shots:
		names.append(shots[k]["anim"])
	for n in names:
		if lib.has_animation(n):
			continue
		var a: Animation = load(ANIM_DIR + n + ".res")
		lib.add_animation(n, a)
	roots = JSON.parse_string(FileAccess.get_file_as_string(ANIM_DIR + "root_motion.json"))
	if FileAccess.file_exists(ANIM_DIR + "root_motion_r10.json"):          # R10：新增動作的根位移另存（不改原檔；只多出新 key）
		var r10: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ANIM_DIR + "root_motion_r10.json"))
		for k in r10:
			if not roots.has(k):
				roots[k] = r10[k]
	# 髖部扭轉修飾器：放在 Skeleton3D 第一個子節點（早於 SpringBone）
	twist = HipTwist.new()
	twist.name = "IsshinHipTwist"
	rig.skeleton.add_child(twist)
	rig.skeleton.move_child(twist, 0)
	foot_lock = FootLock.new()
	foot_lock.name = "IsshinFootLock"
	rig.skeleton.add_child(foot_lock)
	rig.skeleton.move_child(foot_lock, 1)
	var sh := rig.find_child("Sword_Hand", true, false) as Node3D
	if sh:
		grip = TwoHandGrip.new()
		grip.name = "TwoHandGrip"
		add_child(grip)
		grip.setup(rig.skeleton, sh, 2)
	_build_tree(ap)

func _build_tree(ap: AnimationPlayer) -> void:
	tree = AnimationTree.new()
	tree.name = "IsshinCombatTree"
	rig.add_child(tree)
	tree.anim_player = tree.get_path_to(ap)
	tree.root_node = tree.get_path_to(rig)
	var bt := AnimationNodeBlendTree.new()
	# 方向混合（不含待機；中心由 mix 與待機混）
	var bs := AnimationNodeBlendSpace2D.new()
	bs.min_space = Vector2(-1, -1)
	bs.max_space = Vector2(1, 3 if sprint_anim != "" else 2)
	bs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	bs.sync = true
	var pts := {"isshin_walk": Vector2(0, 1), "isshin_back": Vector2(0, -1), "isshin_strafe_l": Vector2(-1, 0),
		"isshin_strafe_r": Vector2(1, 0), "isshin_run": Vector2(0, 2)}
	if sprint_anim != "":
		pts[sprint_anim] = Vector2(0, 3)
	for n in pts:
		var an := AnimationNodeAnimation.new()
		an.animation = n
		bs.add_blend_point(an, pts[n])
	var idle := AnimationNodeAnimation.new()
	idle.animation = "isshin_idle"
	bt.add_node("idle", idle)
	bt.add_node("dirs", bs)
	bt.add_node("seek", AnimationNodeTimeSeek.new())
	bt.add_node("ts", AnimationNodeTimeScale.new())
	bt.add_node("mix", AnimationNodeBlend2.new())
	# 一般單發（轉身／閃避）：OneShot ← sts ← sel
	var shot_keys: Array = []
	var atk_keys: Array = []
	for k in shots:
		if shots[k].get("attack", false):
			atk_keys.append(k)
		else:
			shot_keys.append(k)
	var sel := AnimationNodeTransition.new()
	sel.input_count = shot_keys.size()
	for i in shot_keys.size():
		var k: String = shot_keys[i]
		sel.set_input_name(i, shots[k]["anim"])
		var an2 := AnimationNodeAnimation.new()
		an2.animation = shots[k]["anim"]
		bt.add_node("a_" + k, an2)
	bt.add_node("sel", sel)
	for i in shot_keys.size():
		bt.connect_node("sel", i, "a_" + shot_keys[i])
	bt.add_node("sts", AnimationNodeTimeScale.new())
	bt.connect_node("sts", 0, "sel")
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.05
	shot.fadeout_time = 0.14
	bt.add_node("shot", shot)
	bt.connect_node("seek", 0, "dirs")
	bt.connect_node("ts", 0, "seek")
	if smooth_stance and not sheathed.is_empty():
		var idle2 := AnimationNodeAnimation.new()
		idle2.animation = "isshin_iai_stance"
		bt.add_node("idle_iai", idle2)
		bt.add_node("imix", AnimationNodeBlend2.new())
		bt.connect_node("imix", 0, "idle")
		bt.connect_node("imix", 1, "idle_iai")
		bt.connect_node("mix", 0, "imix")
	else:
		bt.connect_node("mix", 0, "idle")
	if sheathed.is_empty():
		bt.connect_node("mix", 1, "ts")
	else:
		# R10：鞘中移動組 sdirs（自己的 seek／時間縮放），lmix 依 iai_mode 在兩組之間交叉淡入
		var sbs := AnimationNodeBlendSpace2D.new()
		sbs.min_space = Vector2(-1, -1)
		sbs.max_space = Vector2(1, 3)
		sbs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
		sbs.sync = true
		var A: Dictionary = sheathed["anims"]
		for pr in [["walk", Vector2(0, 1)], ["back", Vector2(0, -1)], ["strafe_l", Vector2(-1, 0)], ["strafe_r", Vector2(1, 0)], ["run", Vector2(0, 2)], ["run", Vector2(0, 3)]]:
			var an := AnimationNodeAnimation.new()
			an.animation = A[pr[0]]
			sbs.add_blend_point(an, pr[1])
		bt.add_node("sdirs", sbs)
		bt.add_node("sseek", AnimationNodeTimeSeek.new())
		bt.add_node("sts2", AnimationNodeTimeScale.new())
		bt.add_node("lmix", AnimationNodeBlend2.new())
		bt.connect_node("sseek", 0, "sdirs")
		bt.connect_node("sts2", 0, "sseek")
		bt.connect_node("lmix", 0, "ts")
		bt.connect_node("lmix", 1, "sts2")
		bt.connect_node("mix", 1, "lmix")
	bt.connect_node("shot", 0, "mix")
	bt.connect_node("shot", 1, "sts")
	# 攻擊（可中途換成連段動作）：不用 OneShot，改由腳本控制淡入淡出權重 atk_w。
	# atk(Blend2) ← [shot, asts ← asel ← (seek_<k> ← a_<k>)]；每支攻擊動作前面都有 TimeSeek，開始時跳到 0、換連段時跳到同一時間點。
	var asel := AnimationNodeTransition.new()
	asel.input_count = atk_keys.size()
	for i in atk_keys.size():
		var k: String = atk_keys[i]
		asel.set_input_name(i, shots[k]["anim"])
		var an3 := AnimationNodeAnimation.new()
		an3.animation = shots[k]["anim"]
		bt.add_node("a_" + k, an3)
		bt.add_node("seek_" + k, AnimationNodeTimeSeek.new())
		bt.connect_node("seek_" + k, 0, "a_" + k)
	bt.add_node("asel", asel)
	for i in atk_keys.size():
		bt.connect_node("asel", i, "seek_" + atk_keys[i])
	bt.add_node("asts", AnimationNodeTimeScale.new())
	bt.connect_node("asts", 0, "asel")
	bt.add_node("atk", AnimationNodeBlend2.new())
	bt.connect_node("atk", 0, "shot")
	bt.connect_node("atk", 1, "asts")
	bt.connect_node("output", 0, "atk")
	tree.tree_root = bt
	tree.active = true

# ------------------------------------------------------------------ 輸入整形
## 輸入 (x 右+, y 前+; y>1.5=快走) → 方向混合位置與髖部偏航（Godot：+ = 向左）
func _cmd(v: Vector2) -> Array:
	if v.y > 2.5 and sprint_anim != "":
		return [Vector2(0, 3), 0.0]
	if v.y > 1.5:
		return [Vector2(0, 2), 0.0]
	if v.x != 0.0 and v.y != 0.0:
		if diag_mode == "twist":
			var yaw := atan2(-v.x, v.y) if v.y > 0.0 else atan2(v.x, -v.y)
			return [Vector2(0, signf(v.y)), yaw]
		return [v / (absf(v.x) + absf(v.y)), 0.0]      # 菱形邊上：兩個方向動作各 50%
	return [v, 0.0]

func _dominant(b: Vector2) -> String:
	if b.y > 2.5:
		return "sprint"
	if b.y > 1.5:
		return "run"
	if absf(b.y) >= absf(b.x):
		return "walk" if b.y >= 0.0 else "back"
	return "strafe_r" if b.x > 0.0 else "strafe_l"

func _sh() -> bool:
	return iai_mode and not sheathed.is_empty()

func _local_velocity(b: Vector2) -> Vector3:
	if _sh():
		var S: Dictionary = sheathed["speed"]
		var z := 0.0
		if b.y >= 0.0:
			z = b.y * float(S["fwd"]) if b.y <= 1.0 else (lerpf(float(S["fwd"]), float(S["run"]), b.y - 1.0) if b.y <= 2.0 else lerpf(float(S["run"]), float(S["sprint"]), b.y - 2.0))
		else:
			z = b.y * float(S["back"])
		return Vector3(-b.x * float(S["right"] if b.x > 0.0 else S["left"]), 0.0, z)
	var vz := 0.0
	if b.y >= 0.0:
		vz = b.y * SPEED["fwd"] if b.y <= 1.0 else (lerpf(SPEED["fwd"], SPEED["brisk"], b.y - 1.0) if b.y <= 2.0 else lerpf(SPEED["brisk"], sprint_speed, b.y - 2.0))
	else:
		vz = b.y * SPEED["back"]
	var vs: float = b.x * (SPEED["right"] if b.x > 0.0 else SPEED["left"])
	return Vector3(-vs, 0.0, vz)

func _sample_root(key: String, t: float) -> Vector3:
	var r: Dictionary = roots[shots[key]["anim"]]
	var f: float = clampf(t, 0.0, float(r["length"])) * float(r["fps"])
	var i0 := int(floor(f))
	var i1 := mini(i0 + 1, int(r["frames"]) - 1)
	var w := f - i0
	var yaw: float = lerpf(r["yaw"][i0], r["yaw"][i1], w)
	var left: float = lerpf(r["left"][i0], r["left"][i1], w)
	var fwd: float = lerpf(r["fwd"][i0], r["fwd"][i1], w)
	return Vector3(yaw, left, fwd)

func shot_length(key: String) -> float:
	var full := float(roots[shots[key]["anim"]]["length"])
	return minf(full, float(shots[key].get("end_t", full)))    # end_t＝提早收尾（之後淡回本體待機姿）

# ------------------------------------------------------------------ 主迴圈
## move: x 右+, y 前+（y=2 快走）；dodge: 本幀按下閃避；target_pos: 敵人世界座標（null＝不鎖定）
func step(delta: float, move: Vector2, dodge: bool, target_pos: Variant, dodge_side := 0.0, attack := false) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	var err := 0.0
	var has_target: bool = target_pos != null
	if has_target:
		var to: Vector3 = (target_pos as Vector3) - actor.global_position
		err = wrapf(atan2(to.x, to.z) - actor.rotation.y, -PI, PI)
	body_velocity = Vector3.ZERO
	if state == S.SHOT:
		_step_shot(delta, err, has_target, move, attack, target_pos, dodge, dodge_side)
	else:
		_step_loco(delta, move, dodge, err, has_target, dodge_side, attack)
	# 腳掌鎖定：轉身／閃避階段關閉並清除；其餘階段只在「還沒走到穩定步行」時抓新的支撐腳
	foot_lock.dt = delta
	if state == S.SHOT:
		foot_lock.release_all(0.12)          # 轉身／閃避：不是硬切，緩 0.12 s 放掉（硬切會讓腳一幀跳 10 cm 以上）
		foot_lock.enabled = false
	else:
		foot_lock.enabled = foot_lock_on and (g < 0.999)
		if stopping or label == "reverse":
			foot_lock.allow = {"Left": true, "Right": true}      # 停步：誰貼地且慢（< 0.7 m/s）誰就鎖；邁步中的腳速度高，自然不會被鎖
		elif g > 0.001:
			foot_lock.allow = {stance_start: true, ("Right" if stance_start == "Left" else "Left"): false}     # 起步：只鎖該相位的支撐腳（兩腳都貼地、速度都≈0，只能靠相位表分辨）
		else:
			foot_lock.allow = {"Left": true, "Right": true}
	if grip:
		grip.step(delta)
	# 套用髖部／胸口偏航
	twist.hip_yaw = hip_yaw
	twist.chest_yaw = chest_yaw + strafe_bias
	var w := g * g * (3.0 - 2.0 * g)
	var sb_goal := STRAFE_CHEST * minf(absf(bp.x), 1.0) * w * (1.0 if state != S.SHOT else 0.0)
	strafe_bias = lerpf(strafe_bias, sb_goal, 1.0 - exp(-8.0 * delta))
	tree.set("parameters/mix/blend_amount", w)
	atk_w = move_toward(atk_w, atk_target, delta / maxf(atk_fade, 1e-3))
	tree.set("parameters/atk/blend_amount", atk_w * atk_w * (3.0 - 2.0 * atk_w))
	tree.set("parameters/dirs/blend_position", bp)
	tree.set("parameters/ts/scale", g)
	if not sheathed.is_empty():
		_sh_w = move_toward(_sh_w, 1.0 if iai_mode else 0.0, delta / 0.2)
		tree.set("parameters/lmix/blend_amount", _sh_w * _sh_w * (3.0 - 2.0 * _sh_w))
		if smooth_stance:
			_ii_w = move_toward(_ii_w, 1.0 if iai_mode else 0.0, delta / 0.2)
			tree.set("parameters/imix/blend_amount", _ii_w * _ii_w * (3.0 - 2.0 * _ii_w))
		tree.set("parameters/sdirs/blend_position", bp)
		var spd: Dictionary = sheathed["speed"]
		# 跑／衝刺用同一支居合突進跑（原速 run_nat）：放慢播放到目標速度，腳步與位移一起縮放
		var kr := float(spd["run"]) / float(spd["run_nat"])
		var ks := float(spd["sprint"]) / float(spd["run_nat"])
		var sk := 1.0 if bp.y <= 1.0 else (lerpf(1.0, kr, bp.y - 1.0) if bp.y <= 2.0 else lerpf(kr, ks, minf(bp.y - 2.0, 1.0)))
		tree.set("parameters/sts2/scale", g * sk)

## 實驗用：覆寫某招的部分參數（只給候選 demo 的命令列調參用；空字典＝完全照 SHOTS）
var shot_override := {}
## R9：場景在 setup() 前登記的額外招式（例：日之呼吸、跳躍）；setup() 時與 SHOTS 合併成 shots。既有招式不受影響。
var extra_shots := {}
var shots := {}
## R9：出招路由（選用）。設了就由它決定攻擊鍵出哪一招：attack_router.call(ctx) -> String（""＝不出招）；
## ctx＝"loco"（站立／移動中按攻擊）或 "cancel"（收招段 attack_cancel）。沒設＝舊行為（iai_key／attack_key）。
var attack_router: Callable = Callable()
## R9：下一次 _fire() 的一次性選項（start_t／fade_in），用完即清（例：衝刺派生從突進段開始播）
var fire_opts := {}

func _cfg(key: String) -> Dictionary:
	return (shots[key] as Dictionary).merged(shot_override[key], true) if shot_override.has(key) else shots[key]

func _attack_key_now(ctx: String) -> String:
	if attack_router.is_valid():
		return str(attack_router.call(ctx))
	return iai_key if iai_mode else attack_key

## R9：場景（技能系統）直接出招：出招中就先結束目前這招（記一筆 skill 取消），再出新招
func fire_now(key: String, err: float) -> void:
	if state == S.SHOT:
		cancel_log.append({"key": shot_key, "kind": "skill", "shot_t": shot_t, "to": key})
		_end_shot(true)
	_fire(key, err)

func _fire(key: String, err: float) -> void:
	state = S.SHOT
	shot_key = key
	var cfg: Dictionary = _cfg(key)
	# start_t（選用）：從動作中段開始播（例：收刀＝二連斬動畫的納刀段）；預設 0
	var st0 := float(fire_opts.get("start_t", cfg.get("start_t", 0.0)))
	var fin := float(fire_opts.get("fade_in", cfg["fade_in"]))
	fire_opts = {}
	shot_t = st0
	shot_prev = _sample_root(key, st0)
	shot_basis0 = actor.global_basis
	if cfg.get("attack", false):
		# 攻擊：腳本控制的淡入（atk_w），動作從 start_t（預設 0）開始
		# 攻擊分支已在畫面上（攻擊接攻擊、技能取消）：在攻擊分支內交叉淡入 fade_in 秒，不硬切（R9：硬切會一幀換姿勢＝瞬移）
		_asel_node().xfade_time = fin if atk_w > 0.05 else 0.0
		tree.set("parameters/seek_" + key + "/seek_request", st0)
		tree.set("parameters/asel/transition_request", cfg["anim"])
		atk_target = 1.0
		atk_fade = fin
	else:
		atk_target = 0.0          # 攻擊途中被閃避取消：攻擊分支淡出、閃避 OneShot 淡入
		atk_fade = 0.10
		var shot_node := (tree.tree_root as AnimationNodeBlendTree).get_node("shot") as AnimationNodeOneShot
		shot_node.fadein_time = fin
		shot_node.fadeout_time = cfg["fade_out"]
		tree.set("parameters/sel/transition_request", cfg["anim"])
		tree.set("parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	shot_yaw_scale = 1.0
	if absf(cfg["angle"]) > 1.0:
		shot_yaw_scale = clampf(err / deg_to_rad(cfg["angle"]), 0.6, float(cfg.get("yaw_scale_max", 1.5)))   # 轉到「實際需要的角度」，殘差由慢速追蹤收尾（R10：yaw_scale_max 選用）
	g = 0.0
	stopping = false
	hip_yaw = 0.0
	hip_yaw_target = 0.0
	label = key
	cooldown = 0.12 + float(cfg.get("lockout", 0.0))
	hits_done = []
	swings_done = []
	for _i in (cfg.get("strikes", []) as Array).size():
		hits_done.append(false)
	for _i in (cfg.get("swings", []) as Array).size():
		swings_done.append(false)
	combo_queued = false
	combo_switch_t = -1.0
	lunge_idx = -1
	lunge_fit = 1.0
	hitstop_left = 0
	tree.set("parameters/sts/scale", 1.0)
	tree.set("parameters/asts/scale", 1.0)
	if grip:
		grip.target = 1.0 if cfg.get("two_hand", false) else 0.0

func _asel_node() -> AnimationNodeTransition:
	return (tree.tree_root as AnimationNodeBlendTree).get_node("asel") as AnimationNodeTransition

## 連段途中接下一刀：換成更長的連段動作並從同一時間點接著播。交接起點（seam）前切換＝逐格相同的姿勢（xfade 0）；之後淡入 0.08 s。
func _switch_to(key: String, delta: float) -> void:
	var t := shot_t
	var cfg: Dictionary = _cfg(key)
	var seam := float((shots[shot_key]["next"] as Dictionary)["seam"])
	shot_key = key
	shot_prev = _sample_root(key, t)
	_asel_node().xfade_time = 0.0 if t <= seam else 0.08
	# 這一格原動作本來會播到 t＋delta（停格中則不前進）；seek 那一格不會再前進，所以直接跳到這一格該有的時間，避免慢一格
	tree.set("parameters/seek_" + key + "/seek_request", t + (delta if hitstop_left == 0 else 0.0))
	tree.set("parameters/asel/transition_request", cfg["anim"])
	while hits_done.size() < (cfg.get("strikes", []) as Array).size():
		hits_done.append(false)
	while swings_done.size() < (cfg.get("swings", []) as Array).size():
		swings_done.append(false)
	cooldown = 0.12 + float(cfg.get("lockout", 0.0))
	label = key
	combo_queued = false
	combo_switch_t = t
	if grip:
		grip.target = 1.0

func _end_shot(fade: bool) -> void:
	var cfg: Dictionary = _cfg(shot_key)
	shot_finished.emit(shot_key, shot_t, shot_t < shot_length(shot_key) - 0.02)
	if cfg.get("attack", false):
		atk_target = 0.0
		atk_fade = float(cfg["fade_out"])
	elif fade:
		tree.set("parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	tree.set("parameters/asts/scale", 1.0)
	state = S.IDLE
	label = "idle"
	if grip:
		grip.target = 0.0

func _step_shot(delta: float, err: float, has_target: bool, move := Vector2.ZERO, attack := false, target_pos: Variant = null, dodge := false, dodge_side := 0.0) -> void:
	var cfg: Dictionary = _cfg(shot_key)
	# 接下一刀（只記一次，不累積）：在 next 的 [open, close] 內按攻擊；太早／過期的按鍵忽略
	if attack and cfg.has("next"):
		var nx: Dictionary = cfg["next"]
		if shot_t >= float(nx["open"]) and shot_t <= float(nx["close"]):
			combo_queued = true
	if combo_queued and cfg.has("next"):
		var nk := str((cfg["next"] as Dictionary)["key"])
		_switch_to(third_key if nk == "slash_vhx" else nk, delta)
		cfg = _cfg(shot_key)
	# 命中停格：攻擊動畫（sts 時間縮放＝0）、位移、計時、判定一起凍結；布料／頭髮／IK 仍照常算
	var ts_param := "parameters/asts/scale" if cfg.get("attack", false) else "parameters/sts/scale"
	if hitstop_left > 0:
		hitstop_left -= 1
		hitstop_total += 1
		tree.set(ts_param, 0.0)
		body_velocity = Vector3.ZERO
		return
	tree.set(ts_param, 1.0)
	# 收招段取消（刀已過有效攻擊段）：閃避＝直接接閃避；移動＝淡回戰鬥步行
	var can_cancel := shot_t <= float(cfg.get("cancel_until", 1e9))   # cancel_until（選用）：之後（例：納刀進行中）不能取消
	if dodge and can_cancel and cfg.has("dodge_cancel") and shot_t >= float(cfg["dodge_cancel"]):
		var side := dodge_side if dodge_side != 0.0 else (move.x if move.x != 0.0 else last_x)
		_end_shot(true)
		cancel_log.append({"key": shot_key, "kind": "dodge", "shot_t": shot_t})
		_fire("dodge_l" if side < 0.0 else "dodge_r", err)
		return
	if can_cancel and cfg.has("move_cancel") and shot_t >= float(cfg["move_cancel"]) and move.length() > 0.1:
		cancel_log.append({"key": shot_key, "kind": "move", "shot_t": shot_t})
		_end_shot(true)
		return
	# attack_cancel（選用）：收招段按攻擊＝直接接下一招（iai_mode 時出 iai_key，否則 attack_key；場景可在 shot_finished 裡切換武器狀態）
	if attack and can_cancel and cfg.has("attack_cancel") and shot_t >= float(cfg["attack_cancel"]) and not (cfg.has("next") and shot_t <= float((cfg["next"] as Dictionary)["close"])):
		# 有路由：先問（要看目前這招）、""＝不取消；沒路由：舊行為＝先結束這招（場景可能在 shot_finished 裡切換武器狀態）再取 iai_key／attack_key
		var routed := attack_router.is_valid()
		var nk2 := str(attack_router.call("cancel")) if routed else ""
		if not routed or nk2 != "":
			_end_shot(true)
			if not routed:
				nk2 = iai_key if iai_mode else attack_key
			cancel_log.append({"key": shot_key, "kind": "attack", "shot_t": shot_t, "to": nk2})
			_fire(nk2, err)
			return
	shot_t += delta
	# root_pose_sync（R11，選用）：畫面上的姿勢是 AnimationTree 這一幀「之後」才算的，比 shot_t 慢一格；根位移也取慢一格的時間，
	# 快速踏步時腳才不會相對地面滑一格位移（R11 實測：5 m/s 踏步時差 8 cm）。沒設＝舊行為。
	var cur := _sample_root(shot_key, shot_t - (delta if cfg.get("root_pose_sync", false) else 0.0))
	var d := cur - shot_prev
	shot_prev = cur
	if absf(cfg["angle"]) > 1.0:
		# 每幀依「剩餘誤差 ÷ 剩餘的動作偏航」微調縮放（敵人還在移動時也能收在面向敵人上）
		var total: float = float(roots[cfg["anim"]]["yaw"][int(roots[cfg["anim"]]["frames"]) - 1])
		var rem_clip := -(total - cur.x)                   # Godot 符號（+ = 向左）
		if absf(rem_clip) > deg_to_rad(8.0) and signf(rem_clip) == signf(err):
			shot_yaw_scale = lerpf(shot_yaw_scale, clampf(err / rem_clip, 0.5, 1.7), 0.35)
		actor.rotate_y(-d.x * shot_yaw_scale)             # Sekiro 偏航 − = 向左；Godot + = 向左
	elif cfg.get("root_yaw", false):
		actor.rotate_y(-d.x)                               # 動作自帶的轉身（不追目標）
	else:
		if has_target:
			# aim_offset（度，+＝目標在左）：這招要讓目標落在身體的哪個方位（居合：刀路收在右前方，目標放右前 15°）
			var e2 := err - deg_to_rad(float(cfg.get("aim_offset", 0.0)))
			actor.rotate_y(clampf(e2, -deg_to_rad(80) * delta, deg_to_rad(80) * delta))   # 閃避／斬擊中仍慢慢轉向敵人
	var tscale: float = float(cfg.get("travel_scale", DODGE_SCALE))
	var loc := Vector3(d.y * tscale, 0.0, d.z * tscale) if absf(cfg["angle"]) <= 1.0 else Vector3.ZERO
	# 前衝段：進入時預估整段朝目標的前進量，超過「到最小距離」的部分就把整段位移等比縮小（取代撞到最小距離才急停造成的腳滑）
	var li := -1
	var lunges: Array = cfg.get("lunges", [])
	for i in lunges.size():
		if shot_t >= float(lunges[i][0]) and shot_t < float(lunges[i][1]):
			li = i
	if li != lunge_idx:
		lunge_idx = li
		lunge_fit = 1.0
		if li >= 0 and target_pos != null:
			var pred_l: Vector3 = _sample_root(shot_key, float(lunges[li][1])) - cur
			var pred := actor.global_basis * Vector3(pred_l.y * tscale, 0.0, pred_l.z * tscale)
			var to2: Vector3 = (target_pos as Vector3) - actor.global_position
			to2.y = 0.0
			var along2 := pred.dot(to2.normalized())
			var lmins: Array = cfg.get("lunge_min_dist", [])
			var lmin := float(lmins[li]) if li < lmins.size() else float(cfg.get("min_dist", attack_min_dist))
			var room := to2.length() - lmin - 0.05
			if along2 > 0.05 and room < along2:
				lunge_fit = clampf(room / along2, 0.2, 1.0)
			fit_log.append({"key": shot_key, "lunge": li, "shot_t": shot_t, "fit": lunge_fit, "pred": along2, "room": room})
	if li >= 0:
		loc *= lunge_fit
	var mv := (shot_basis0 if cfg.get("root_yaw", false) else actor.global_basis) * loc
	if cfg.get("attack", false) and target_pos != null:
		# 攻擊位移不把角色推過最小距離（只截掉朝目標方向的分量）
		var to: Vector3 = (target_pos as Vector3) - actor.global_position
		to.y = 0.0
		var dist := to.length()
		if dist > 1e-3:
			var dir := to / dist
			var along := mv.dot(dir)
			var allowed := maxf(0.0, dist - float(cfg.get("min_dist", attack_min_dist)))
			if along > allowed and along > 0.0:
				mv -= dir * (along - allowed)
				clamp_total += along - allowed
	actor.global_position += mv
	body_velocity = actor.global_basis.inverse() * mv / maxf(delta, 1e-4)
	chest_yaw = lerp_angle(chest_yaw, 0.0, 1.0 - exp(-12.0 * delta))
	var sw: Array = cfg.get("swings", [])
	for i in sw.size():
		if not swings_done[i] and shot_t >= float(sw[i]):
			swings_done[i] = true
			swing_started.emit(i)
	var st: Array = cfg.get("strikes", [])
	for i in st.size():
		if hits_done[i] or not hit_test.is_valid() or shot_t < float(st[i][0]) or shot_t > float(st[i][1]):
			continue
		var info: Dictionary = hit_test.call()
		if not info.is_empty():
			hits_done[i] = true
			var hsf := int(cfg.get("hitstop_frames", hitstop_frames))     # R9：每招可設自己的停格幀數（重斬／技能）；沒設＝全域值
			hitstop_left = hsf
			if cfg.get("freeze_hit_frame", false) and hsf > 0:
				# 停格停在「判到命中的那一格」：預設流程裡動畫這一幀還會再前進一格才停，快刀（二連斬）那一格刀已穿出木樁。
				# 這一幀就把動畫停住、shot_t 退回動畫目前的時間（根位移這一格已套用、shot_prev 不動，所以下一幀不會重複位移），
				# 停格總長不變（這一幀算第 1 格）。只有設了 freeze_hit_frame 的招式才這樣做。
				tree.set(ts_param, 0.0)
				shot_t -= delta
				hitstop_left = hsf - 1
				hitstop_total += 1
				body_velocity = Vector3.ZERO
			info["shot_t"] = shot_t
			info["strike"] = i
			info["key"] = shot_key
			hit_landed.emit(info)
			lunge_idx = -2          # 命中後（目標可能被擊退）重新估算這段前衝剩下的位移
		break
	if cfg.has("grip_off") and grip and shot_t >= float(cfg["grip_off"]):
		grip.target = 0.0
	if cfg.get("attack", false) and atk_target > 0.0 and shot_t >= shot_length(shot_key) - float(cfg["fade_out"]):
		atk_target = 0.0          # 自然收招：最後 fade_out 秒淡回戰鬥步行（連段動作最後一格＝待機姿勢）
		atk_fade = float(cfg["fade_out"])
	if shot_t >= shot_length(shot_key):
		_end_shot(false)

func _step_loco(delta: float, move: Vector2, dodge: bool, err: float, has_target: bool, dodge_side := 0.0, attack := false) -> void:
	var has_in := move.length() > 0.1
	if move.x != 0.0:
		last_x = move.x
	# 斬擊
	if attack and cooldown <= 0.0:
		var ak := _attack_key_now("loco")
		if ak != "":
			_fire(ak, err)
			return
	if iai_mode and sheathed.is_empty():
		move = Vector2.ZERO
		dodge = false
	# 閃避
	if dodge and cooldown <= 0.0:
		var side := dodge_side if dodge_side != 0.0 else (move.x if move.x != 0.0 else last_x)
		_fire("dodge_l" if side < 0.0 else "dodge_r", err)
		return
	# 原地轉身（只在完全停下時）
	if not has_in and g < 0.02 and has_target and absf(err) > TURN_TRIGGER and cooldown <= 0.0:
		turn_pending += delta
		if turn_pending >= 0.10 or absf(err) > deg_to_rad(150.0):
			var key := ("turn_l" if err > 0.0 else "turn_r") + ("180" if absf(err) > deg_to_rad(135.0) else "90")
			if _sh():                               # R10：鞘中轉身（居合構的 90° 轉身；超過 135° 由偏航縮放補到）
				key = str(sheathed["turn"]["l90" if err > 0.0 else "r90"])
			turn_pending = 0.0
			_fire(key, err)
			return
	else:
		turn_pending = 0.0
	# 步行閘門
	var cmd := _cmd(move)
	if has_in:
		var nb: Vector2 = cmd[0]
		if g > 0.05 and bp.length() > 0.1 and nb.length() > 0.1 and bp.normalized().dot(nb.normalized()) < -0.3:
			# 反向（前↔後、左↔右）：先在原方向煞停（0.22 s），停住後再以起步流程往新方向走，避免混合到中心點把腿糊成一團
			stopping = false
			g = move_toward(g, 0.0, delta / REVERSE_BRAKE)
			label = "reverse"
		else:
			if g <= 0.001:
				bp = nb
				_start_seek(nb)
			stopping = false
			g = move_toward(g, 1.0, delta / T_START)
			bp = bp.move_toward(nb, BLEND_RATE * delta)
			label = "move"
		hip_yaw_target = cmd[1]
		state = S.MOVE
	else:
		if g > 0.001 and not stopping:
			_begin_stop()
		if stopping:
			g = move_toward(g, 0.0, stop_rate * delta)
			if g <= 0.001:
				g = 0.0
				stopping = false
				hip_yaw_target = 0.0
				state = S.IDLE
				label = "idle"
			else:
				label = "stopping"
	var s := g
	loco_t += delta * s
	var hip_goal := hip_yaw_target if g > 0.001 else 0.0
	var hip_rate := HIP_RATE_MOVE if has_in else HIP_RATE_IDLE
	hip_yaw = move_toward(hip_yaw, hip_goal, hip_rate * delta)
	if g > 0.001:
		var w := g * g * (3.0 - 2.0 * g)
		var v := Basis(Vector3.UP, hip_yaw) * (_local_velocity(bp) * s * w)
		actor.global_position += actor.global_basis * v * delta
		body_velocity = v
	# 面向敵人
	if has_target:
		if g > 0.05:
			actor.rotate_y(clampf(err, -deg_to_rad(260) * delta, deg_to_rad(260) * delta))
			chest_yaw = lerp_angle(chest_yaw, 0.0, 1.0 - exp(-10.0 * delta))
		else:
			var stp := clampf(err, -deg_to_rad(22) * delta, deg_to_rad(22) * delta)
			actor.rotate_y(stp)
			var rem := err - stp
			chest_yaw = lerp_angle(chest_yaw, clampf(rem, -AIM_MAX, AIM_MAX), 1.0 - exp(-8.0 * delta))

func _tab(name_: String) -> Dictionary:
	if _sh():
		return sheathed[{"CLIP_LEN": "len", "PASS": "pass", "STANCE_AT": "stance"}[name_]]
	return {"CLIP_LEN": CLIP_LEN, "PASS": PASS, "STANCE_AT": STANCE_AT}[name_]

func _start_seek(b: Vector2) -> void:
	var c := _dominant(b)
	stance_start = _tab("STANCE_AT")[c][0]
	var len_: float = _tab("CLIP_LEN")[c]
	var p: float = _tab("PASS")[c][0]
	loco_t = p * len_
	tree.set("parameters/seek/seek_request", loco_t)
	if not sheathed.is_empty():
		tree.set("parameters/sseek/seek_request", loco_t)

func _begin_stop() -> void:
	stopping = true
	var c := _dominant(bp)
	var len_: float = _tab("CLIP_LEN")[c]
	var phase := fposmod(loco_t, len_) / len_
	var best := -1.0
	var best_i := -1
	var near_i := 0
	var near_d := 9.0
	for i in 2:
		var p: float = _tab("PASS")[c][i]
		var d := fposmod(p - phase, 1.0)
		if d < near_d:
			near_d = d
			near_i = i
		var t := 2.0 * d * len_ / maxf(g, 0.2)
		if t >= T_STOP_MIN and t <= T_STOP_MAX and (best < 0.0 or t < best):
			best = t
			best_i = i
	if best < 0.0:
		best = 0.38
		best_i = near_i
	stop_stance = _tab("STANCE_AT")[c][best_i]
	stop_rate = maxf(g, 0.01) / best
