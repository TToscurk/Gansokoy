# Yoriichi Gameplay Animations

`yoriichi_character_meshy_full.tscn` 會由 `yoriichi_character.gd` 載入本資料夾的衍生動畫。
角色仍使用同一套 Meshy 24-bone Skeleton；這些資源不會建立第二套角色或骨架。

## AnimationTree 架構（`yoriichi_character.gd` 於 _ready 程式化建立）

```
loco  (AnimationNodeStateMachine)         下半身 / 一般 locomotion
	  Idle / Walk / Run / RunFL / RunFR / BackPedal /
	  JumpStart / Fall / Land
  ↓
upper (AnimationNodeOneShot, bone filter = Spine02 以上 15 根上半身骨)
	  draw / sheathe(Draw_Sword 反播) / atk1 / atk2 / atk3（輕連段三段）
	  → 腿繼續 locomotion：邊跑邊拔刀、邊跑邊斬、空中斬
  ↓
full  (AnimationNodeOneShot, 無 filter)   全身 override
	  roll / spin / judgment / combo1 / spinjump
  ↓
output
```

- **Jump/Fall 不是 ActionState，是純 physics**：`_jump_charge` 蓄力倒數
  （(0.533−skip 0.30)/1.9 ≈ 0.12 s，Run→Jump 立即）→ `velocity.y = 5.33`；
  之後不論播什麼攻擊，gravity / 慣性照常 —— 攻擊永遠取消不了跳躍，
  蓄力期間按 LMB 攻擊照打、照樣離地。Jump 拆三段（custom timeline）：
  JumpStart 0.30–0.62 s × 1.9、Fall 0.75–1.05 s 循環（vy≤0 切入）、
  Land 1.067–1.9 s × 1.5（落地無輸入才播；有輸入直接接 Run/Walk）。
- 每段/技的時間全部由腳本計時器管理（同一個時鐘），AnimationTree 只負責混合。
- CharacterBody3D 永遠是真實位置；動畫零水平 root motion，位移全程式驅動。
- **Run_Turn / Walk_Turn 已停用**：實測源 clip 整段懸空（腳底 0.12~0.25 m，
  且舊衍生版把 Hips 凍在 −1.15 m 的水平偏移上），無法補成落地轉身。
  急轉由 8 向扇區（RunFL/FR、BackPedal）＋**限速**視覺轉向接管；
  .res 檔案保留不刪，不再被狀態機引用。
- **收勢（zanshin）**：攻擊結束不硬切回 locomotion —— upper 層結束時依招式
  設定 OneShot fadeout（輕斬段 0.10 s、第三斬 0.20 s、聚力單斬 0.24 s、
  拔/收刀 0.16 s）；保留給日之呼吸框架的全身技淡出更長
  （Judgment 0.32 s、Combo_1 0.30 s、Spin 0.20 s、SpinJump 0.16 s、Roll 0.12 s）。
- **第二輪風格減法**：Judgment（大縱劈）、SpinJump（空中迴旋）、Spin（全身
  迴旋）、Combo_1 自動收尾已從預設輸入下線——動作幅度過大、有「展示招式」
  感，不符合沉穩精準的方向。資源與 `execute_form()` 通道全部保留。

## 操作

- `W/A/S/D`：移動
- `Shift` 按住：疾跑；快按（≤ 0.25 s 內放開）：翻滾（跑步中可直接發動）
- `Space`：跳躍（起跳段 1.9x，約 0.28 s 離地；空中為慣性移動）
- `Q`：拔刀 / 收刀 toggle —— **跑步中不停下**（上半身分層）；攻擊中按 Q 排隊收刀
- 滑鼠左鍵：輕連段 Attack_1→2→3（速度 2.2 / 2.0 / 1.8 —— 第一刀突然、
  第三刀略收；第三段後**不再自動接大招**，乾淨收勢回架勢）；
  收刀狀態按左鍵 = quick-draw（自動拔刀接第一段）
- 滑鼠右鍵：**聚力單斬** —— 輕連段第一斬素材的慎重版（1.5x、upper 層、
  收勢 0.24 s）。地面、空中皆可用。沒有全身技的跳動與旋轉
- Judgment / SpinJump / Spin / Combo_1 已無預設鍵（風格減法），
  僅保留日之呼吸 `execute_form()` 通道
- 鍵盤攻擊鍵（J/K/L）已全部移除，無 debug fallback

## 動畫來源

| 遊戲內名稱 | Meshy 動畫來源 | 處理 |
|---|---|---|
| RunFast | `animations/yoriichi_run_fast.res` | 衍生版：Hips 水平對齊骨架 rest（保留步態擺動）＋垂直 −0.036（邊界腳底對齊 Walk） |
| RunFL / RunFR | `animations/yoriichi_run_fl/fr.res` | 衍生版：同上（z_shift −0.034 / −0.037，最深幀趾尖容許 ≤1.3 cm 微陷）；側身追擊跑姿 |
| BackPedal | `Animation_Walking_withSkin.fbx` **反播** | Walking 是零位移完美循環，反播即後退步，無需新動畫 |
| ~~TurnL / TurnR~~ | `animations/yoriichi_turn_left/right.res` | **已停用**：源 clip 整段懸空（腳底 0.12~0.25 m）、舊衍生版 Hips 凍在 −1.15 m 偏移；檔案保留 |
| ~~WalkTurnL / WalkTurnR~~ | `animations/yoriichi_walk_turn_left/right.res` | **已停用**（同上）；檔案保留 |
| Idle_Grounded | `animations/yoriichi_idle_grounded.res` | 原 Idle 腳趾懸空 0.123 m（實測 vs Walk 接觸幀 0.027）；Hips 垂直軸下移補正，修正後 0.031 |
| Roll_Dodge | `animations/yoriichi_roll_dodge.res` | Hips XY 凍結在骨架 rest；**time-dependent 垂直補正**（`ground_window`）：起滾蹲伏段與收勢站立段依逐 key 腳底高度釘回地面（0.038），中段翻騰保留原样。實測：起滾腳底 0.031~0.039、中段騰空最高 1.12、收勢站立 0.031~0.038 |
| Attack_Combo | `animations/yoriichi_attack_combo.res` | 移除 Hips 水平位移（1.56 u）；三段輕連段；**只走 upper 層，腿部由 locomotion 提供** |
| Attack_Combo_1 | `animations/yoriichi_attack_combo_1.res` | Hips XY 凍結在 rest＋垂直 −0.090；**已從連段自動收尾下線**，僅日之呼吸肆型通道 |
| Attack_Spin | `animations/yoriichi_attack_spin.res` | Hips XY 凍結在 rest＋垂直 −0.108（原整段懸空 0.13~0.14）；貳型保留技，無預設鍵 |
| Attack_Judgment | `animations/yoriichi_attack_judgment.res` | Hips XY 凍結在 rest＋垂直 −0.090；**已從預設 RMB 下線**（風格減法），僅柒型通道 |
| Attack_Spin_Jump | `animations/yoriichi_attack_spin_jump.res` | Hips XY 凍結在 rest＋垂直 −0.048＋垂直 clamp；**已從預設空中 RMB 下線**，僅拾型通道 |
| Jump | `animations/yoriichi_jump.res` | Hips XY 凍結在 rest（源首幀帶 −0.07 側偏）；垂直 −0.028；垂直弧線 clamp，上升由物理提供；**手臂 keys 向 Running 首幀 slerp（保留 35%），最大偏差 148.8°→52.1°，起跳不再雙手高舉** |
| Draw_Sword | `Animation_拔刀_withSkin.fbx`（裁切 0–1.0 s） | 正播拔刀 1.15x；**反播收刀 0.95x（納刀較慢，儀式感）** |

**骨架空間軸向（Meshy 24-bone rig）**：Hips position track 的 **Z 是垂直軸**
（rest ≈ 0.986 = 髖高），X/Y 是水平軸。清 root motion 必須凍結 X/Y、保留 Z。
`animations/build_jump.gd` 是唯一的重建腳本。

## Gameplay 參數

- Roll：**3.2 m／0.422 s**（原 6.4 m 縮短 50%；clip 1.267 s × 3.0x）。
  ease-out `p(t)=1-(1-t)²`，位移與動畫共用 `_roll_duration`；跑步中可直接翻滾，
  結束依當前輸入回 Run / Walk / Idle。
- Attack：**速度分級**——輕連段三段 2.2 / 2.0 / 1.8（`attack_speed_scale` /
  `combo_stage2_speed` / `combo_stage3_speed`：第一刀突然、第三刀略收）、
  聚力單斬 1.5（`heavy_cut_speed`）。日之呼吸框架保留技：
  Judgment 2.4、Combo_1 2.2、Spin 1.7、SpinJump 2.0。
  Draw `draw_speed_scale = 1.15`、**Sheathe 獨立 `sheathe_speed_scale = 0.95`**
  （納刀較慢；socket 切換依 `_draw_real` 自動同步）。
- 輕連段：Weapon Combo 三段 0–34% / 30–67% / 63–100%，cancel window 35–65%，
  input buffer 0.30 s，段間 blend 0.035 s。**第三段後不再延伸**：
  buffer 只到第三段，結束走 0.20 s 收勢淡出回架勢（Combo_1 保留給肆型通道）。
- **聚力單斬（RMB）**：Weapon_Combo 第一斬區段，1.5x，upper 層 ——
  腳步不受限、無全身技跳動；收勢 0.24 s。強大感來自節奏差（比連段慢），
  不是來自動作幅度。
- 移動中攻擊動量（MGR 式，攻擊不是 movement lock）：Run × 1.0（全速跑斬）、
  Walk × 0.7、全身技 × 0.5 —— 即使 full-body override 也不停；
  攻擊期間保留 35% WASD 轉向。拔刀中按 LMB 會 buffer 成拔刀斬。
- 空中慣性：有輸入 move_toward(目標, `4.0 × 0.35 = 1.4 m/s²`)；無輸入僅
  `air_drag 0.2 m/s²` 衰減。跳躍物理：`jump_velocity = 5.33`，離地時刻
  `0.533 / 1.9 ≈ 0.28 s`；FREE 離地 > `coyote_time 0.12 s` 也會進 Fall。
- 收刀：Draw_Sword 反播（`play_mode = BACKWARD` 的 tree 節點）；
  socket 切換依進度對 `t_unsheathe = 0.65`，正反向共用同一門檻。

## 8 向 locomotion

- 判定用**角色 local 速度方向**（`_locomotion_target()`：世界水平速度投影到
  面朝 forward/left 軸取夾角），不是世界座標、不是輸入鍵。
- Forward |a|<22.5° → Run/Walk；22.5°~112.5° → RunFL（純側向 67.5°~112.5°
  暫無專用 strafe clip，代用 FL 側身跑，右側鏡像）；|a|>112.5° → BackPedal。
- **急轉不再有獨立轉身狀態**：舊 Turn/WalkTurn clip 整段懸空無法用，
  60°~112.5° 直接由 RunFL/FR 扇區接、>112.5° 由 BackPedal 接。
- **視覺轉向限速**（第二輪）：`turn_speed` 改為速率上限（8.0 rad/s ≈
  458°/s），疾跑 ×`run_turn_multiplier`（1.9 ≈ 870°/s），攻擊中再 ×
  `attack_turn_control`（0.35）。180° 急轉需要時間走完，不瞬間 snap；
  配合扇區步法（側身跑／後退步）避免「轉盤式」原地旋轉與滑步。
- 換 sector 最短持續 `sector_min_hold = 0.15 s` 防抖；FL/FR 只在疾跑時啟用。
- 8 向輸入 normalized，實測 8 方向速度全部 = 4.00（無 √2 加速）。
- **所有 locomotion 衍生動畫的 Hips 水平首幀已對齊骨架 rest**（recenter_rest），
  扇區切換時視覺原點一致；全身技的 Hips 凍結在 rest（freeze_rest）。

## 組合動作（全部由既有動畫組成，未新增 FBX）

| 動作 | 來源 / 區段 | 倍率 | 層 | 程式位移 |
|---|---|---|---|---|
| Running Slash | Weapon_Combo 三段 | 2.2/2.0/1.8 | upper | run×0.85 動量 |
| Quick Draw / 居合斬 | Draw_Sword 0~0.65（離鞘瞬間 cancel 接 Combo 段1） | 1.15→2.2 | upper | — |
| Dodge Counter | Roll 全段 → Combo 段1 | 2.2 | full→upper | roll 3.2 m + 前衝 2 m/s |
| Aerial Slash | Combo 段1~3（Fall 腿姿上） | 2.2~1.8 | upper | 慣性 + gravity |
| **聚力單斬（RMB）** | Weapon_Combo 第一斬區段（慎重版） | 1.5 | upper | — |
| Sheathe | Draw_Sword 反播 | 0.95 | upper | — |
| BackPedal | Walking 反播 | 1.0 | loco | — |
| ~~Heavy Overhead~~ | Sword_Judgment（已下線預設鍵，保留柒型通道） | 2.4 | full | — |
| ~~Aerial Spin~~ | 360_Power_Spin_Jump（已下線，保留拾型通道） | 2.0 | full | — |
| ~~Spin Slash~~ | Axe_Spin（已下線，保留貳型通道） | 1.7 | full | — |

## 日之呼吸（`sun_breathing.gd`，data-driven）

- Form01–13 定義：animation / section / layer / speed / damage / breath_cost /
  cooldown / impulse / allowed_airborne / required_mastery / vfx / cancel / next。
- **READY**（動畫可直接/裁切完成）：壹（Combo 段1）、貳（Spin）、參（Combo 段2）、
  肆（Combo_1）、柒（Judgment）、拾（Spin_Jump）。
  **目前玩法中的型**：壹/參＝LMB 連段段落。
  **第二輪風格減法後僅留框架通道**（`execute_form` 可呼叫、未綁鍵）：
  貳、肆（原連段自動收尾）、柒（原 RMB 地面）、拾（原 RMB 空中）。
- **PARTIAL**（現有動畫＋程式位移已可操作，專用動畫仍可補）：
  伍（dodge counter 已實裝）、陸（居合 quick-draw 已實裝，缺 dash 版）、
  拾貳（quick-draw→段1→段2 鏈已可操作）。
- **MISSING**（真缺專用動畫）：捌（直線突刺）、玖（dash 連斬鏈）、拾壹（殘影反擊）。
- 未接入素材（全專案僅剩這兩支未使用）：`Dead`（完整倒地，留給死亡狀態）、
  `Double_Blade_Spin`（5.7 s 雙刀大迴旋，留給雙刀系統）。
- 刀 socket：`Sword_Hand` 第一輪以幾何計算初值（刀長軸 = local +Y、
  刃軸 = local X、厚度軸 = local Z，AABB 實測；刀刃在刀本地 −X 側），
  再經肉眼驗收**手動微調**成目前 tscn 中的值（未動 Skeleton3D rest pose、
  未動刀鞘掛點）。第二輪實測刀向（骨架空間，−Y 前、+Z 上）：
  持刀待機 (0.24, −0.94, −0.24)、持刀走 (0.11, −0.93, −0.36) —— 前下方、
  刃向下分量 0.90；拔刀收尾 (−0.48, −0.75, −0.46)、連段中段
  (−0.82, −0.07, −0.56) 屬揮動過程的合理過渡。

## 動畫 layer 適性（依 Stage 1 實測腿/臂活動量分類）

| 動畫 | 腿°/s | 臂°/s | 分類 |
|---|---|---|---|
| Weapon_Combo | 636 | 1112 | UPPER_BODY_SAFE（腿低活動 → 三段輕連段走 upper filter） |
| Draw_Sword | 437 | 388 | UPPER_BODY_SAFE（拔/收刀走 upper） |
| Weapon_Combo_1 | 860 | 1123 | FULL_BODY（含跳劈、垂直 0.52–1.50） |
| Axe_Spin_Attack | 640 | 825 | FULL_BODY（整身旋轉，hips 轉向不可 filter） |
| Sword_Judgment | 599 | 672 | FULL_BODY（大縱劈、垂直 0.59–1.79） |
| 360_Power_Spin_Jump | 992 | 893 | FULL_BODY + AIRBORNE |
| FL/FR_Run_Fight | ~2500 | ~870 | LOCOMOTION（完美循環側身跑） |
| Run/Walk_Turn | 650–1030 | 440–620 | TRANSITION（剝離位移版） |
| Roll_Dodge | 1551 | 1994 | FULL_BODY |
| Regular_Jump | 1085 | 831(修) | LOCOMOTION（三段拆分＋手臂抑制） |
- 拾參ノ型 = `start_form13()`：把可用的型按序高速循環（框架已驗證，
  解鎖條件 `form13_unlocked` / `form13_gauge_cost` 為 export data，尚未綁輸入）。
- 型的選型輸入（方向派生 / mastery 映射）尚未實裝；目前僅左右鍵 + quick-draw。

死亡、雙刀類動畫暫未接入。
