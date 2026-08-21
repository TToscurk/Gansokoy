# Yoriichi Gameplay Animations

`yoriichi_character_meshy_full.tscn` 會由 `yoriichi_character.gd` 載入本資料夾的衍生動畫。
角色仍使用同一套 Meshy 24-bone Skeleton；這些資源不會建立第二套角色或骨架。

## AnimationTree 架構（`yoriichi_character.gd` 於 _ready 程式化建立）

```
loco  (AnimationNodeStateMachine)         下半身 / 一般 locomotion
      Idle / Walk / Run / RunFL / RunFR / BackPedal /
      TurnL / TurnR / JumpStart / Fall / Land
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

- Jump 拆三段（同一支 Regular_Jump clip 的 custom timeline）：
  JumpStart 0–0.62 s × `jump_start_speed = 1.9`（起跳不再飄）、
  Fall 0.75–1.05 s 循環（apex 後切入）、Land 1.067–1.9 s × `jump_land_speed = 1.5`
  （落地無輸入才播；有輸入直接接 Run/Walk）。
- 每段/技的時間全部由腳本計時器管理（同一個時鐘），AnimationTree 只負責混合。
- CharacterBody3D 永遠是真實位置；動畫零水平 root motion，位移全程式驅動。

## 操作

- `W/A/S/D`：移動
- `Shift` 按住：疾跑；快按（≤ 0.25 s 內放開）：翻滾（跑步中可直接發動）
- `Space`：跳躍（起跳段 1.9x，約 0.28 s 離地；空中為慣性移動）
- `Q`：拔刀 / 收刀 toggle —— **跑步中不停下**（上半身分層）；攻擊中按 Q 排隊收刀
- 滑鼠左鍵：輕連段 Attack_1→2→3（Idle/Walk/Run/Jump/Fall 全部可攻擊）；
  收刀狀態按左鍵 = quick-draw（自動拔刀接第一段）
- 滑鼠右鍵：Spin 重攻擊（全身）
- 鍵盤攻擊鍵（J/K/L）已全部移除，無 debug fallback

## 動畫來源

| 遊戲內名稱 | Meshy 動畫來源 | 處理 |
|---|---|---|
| RunFast | `Animation_RunFast_withSkin.fbx` | 原地循環 |
| RunFL / RunFR | `Animation_ForwardLeft/Right_Run_Fight_withSkin.fbx` | 原地完美循環；local 速度方向 22.5°~112.5° 的側身追擊跑姿 |
| BackPedal | `Animation_Walking_withSkin.fbx` **反播** | Walking 是零位移完美循環，反播即後退步，無需新動畫 |
| TurnL / TurnR | `animations/yoriichi_turn_left/right.res` | **剝離 2.0~3.1 u 水平 root motion 的衍生版**（原始 clip 直接播會拖離碰撞體）；夾角 60°~112.5° 急轉觸發（>112.5° 交給 BackPedal） |
| WalkTurnL / WalkTurnR | `animations/yoriichi_walk_turn_left/right.res` | Walk 速度的轉身（剝離 1.1~2.1 u 水平位移） |
| Idle_Grounded | `animations/yoriichi_idle_grounded.res` | 原 Idle 腳趾懸空 0.123 m（實測 vs Walk 接觸幀 0.027）；Hips 垂直軸下移補正，修正後 0.031 |
| Roll_Dodge | `Animation_Roll_Dodge_1_withSkin.fbx` | 移除 Hips 水平位移（6.48 u） |
| Attack_Combo | `Animation_Weapon_Combo_withSkin.fbx` | 移除 Hips 水平位移（1.56 u）；三段輕連段 |
| Attack_Combo_1 | `Animation_Weapon_Combo_1_withSkin.fbx` | 移除 Hips 水平位移（2.64 u）；日之呼吸肆型 |
| Attack_Spin | `Animation_Axe_Spin_Attack_withSkin.fbx` | 原始即為 0；右鍵重攻擊／貳型 |
| Attack_Judgment | `Animation_Sword_Judgment_withSkin.fbx` | 移除 Hips 水平位移（1.33 u）；柒型 |
| Attack_Spin_Jump | `Animation_360_Power_Spin_Jump_withSkin.fbx` | 移除水平位移（2.85 u）＋垂直 clamp；拾型 |
| Jump | `Animation_Regular_Jump_withSkin.fbx` | 移除水平位移；垂直弧線 clamp，上升由物理提供；**手臂 keys 向 Running 首幀 slerp（保留 35%），最大偏差 148.8°→52.1°，起跳不再雙手高舉** |
| Draw_Sword | `Animation_拔刀_withSkin.fbx`（裁切 0–1.0 s） | 正播拔刀 2.2x；反播收刀 |

**骨架空間軸向（Meshy 24-bone rig）**：Hips position track 的 **Z 是垂直軸**
（rest ≈ 0.986 = 髖高），X/Y 是水平軸。清 root motion 必須凍結 X/Y、保留 Z。
`animations/build_jump.gd` 是唯一的重建腳本。

## Gameplay 參數

- Roll：**3.2 m／0.422 s**（原 6.4 m 縮短 50%；clip 1.267 s × 3.0x）。
  ease-out `p(t)=1-(1-t)²`，位移與動畫共用 `_roll_duration`；跑步中可直接翻滾，
  結束依當前輸入回 Run / Walk / Idle。
- Attack：`attack_speed_scale = 2.0`（輕連段、全身技與所有日之呼吸型統一）；
  Draw/Sheathe 獨立 `draw_speed_scale = 1.4`（正反向同速，socket 切換依
  `_draw_real` 自動同步）；Idle/Walk/Run/Roll 以外的 Jump 三段見上。
- 輕連段：Weapon Combo 三段 0–34% / 30–67% / 63–100%，cancel window 35–65%，
  input buffer 0.30 s，段間 blend 0.035 s。
- 移動中攻擊動量：Run × `attack_move_factor_run = 0.85`、
  Walk × `attack_move_factor_walk = 0.60`、全身技 × `attack_move_factor_heavy = 0.30`；
  攻擊期間保留 35% WASD 轉向。
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
- 換 sector 最短持續 `sector_min_hold = 0.15 s` 防抖；FL/FR 只在疾跑時啟用。
- 8 向輸入 normalized，實測 8 方向速度全部 = 4.00（無 √2 加速）。
- 面朝仍以 `turn_speed` lerp 向移動方向，因此純側/後 sector 主要出現在
  轉向過渡與攻擊期間（attack_turn_control 0.35 使攻擊中側移可持續）。

## 組合動作（全部由既有動畫組成，未新增 FBX）

| 動作 | 來源 / 區段 | 倍率 | 層 | 程式位移 |
|---|---|---|---|---|
| Running Slash | Weapon_Combo 三段 | 3.0 | upper | run×0.85 動量 |
| Quick Draw / 居合斬 | Draw_Sword 0~0.65（離鞘瞬間 cancel 接 Combo 段1） | 2.2→3.0 | upper | — |
| Dodge Counter | Roll 全段 → Combo 段1 | 3.0 | full→upper | roll 3.2 m + 前衝 2 m/s |
| Aerial Slash | Combo 段1~3（Fall 腿姿上） | 3.0 | upper | 慣性 + gravity |
| Spin Slash | Axe_Spin 全段（完美循環，0 位移） | 3.0 | full | — |
| Heavy Finisher | Sword_Judgment 全段 | 3.0 | full | impulse 0.5 |
| Sheathe | Draw_Sword 反播 | 2.2 | upper | — |
| BackPedal | Walking 反播 | 1.0 | loco | — |

## 日之呼吸（`sun_breathing.gd`，data-driven）

- Form01–13 定義：animation / section / layer / speed / damage / breath_cost /
  cooldown / impulse / allowed_airborne / required_mastery / vfx / cancel / next。
- **READY**（動畫可直接/裁切完成）：壹（Combo 段1）、貳（Spin）、參（Combo 段2）、
  肆（Combo_1）、柒（Judgment）、拾（Spin_Jump）。
- **PARTIAL**（現有動畫＋程式位移已可操作，專用動畫仍可補）：
  伍（dodge counter 已實裝）、陸（居合 quick-draw 已實裝，缺 dash 版）、
  拾貳（quick-draw→段1→段2 鏈已可操作）。
- **MISSING**（真缺專用動畫）：捌（直線突刺）、玖（dash 連斬鏈）、拾壹（殘影反擊）。
- 未接入素材（全專案僅剩這兩支未使用）：`Dead`（完整倒地，留給死亡狀態）、
  `Double_Blade_Spin`（5.7 s 雙刀大迴旋，留給雙刀系統）。
- 刀 socket：`Sword_Hand` local transform = identity basis + origin (0, 0.17, 0)
  （刀 mesh 長軸 = local +Y，柄佔 −0.38~−0.1）。舊值 Z 轉 90° 使柄掉在手外、
  刀身平舉；新值掌心落在柄卷中段、刀身斜下，三視角驗證於 grip_tuning/。
- 拾參ノ型 = `start_form13()`：把可用的型按序高速循環（框架已驗證，
  解鎖條件 `form13_unlocked` / `form13_gauge_cost` 為 export data，尚未綁輸入）。
- 型的選型輸入（方向派生 / mastery 映射）尚未實裝；目前僅左右鍵 + quick-draw。

死亡、雙刀類動畫暫未接入。
