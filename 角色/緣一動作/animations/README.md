# Yoriichi Gameplay Animations

`yoriichi_character_meshy_full.tscn` 會由 `yoriichi_character.gd` 載入本資料夾的衍生動畫。
角色仍使用同一套 Meshy 24-bone Skeleton；這些資源不會建立第二套角色或骨架。

## AnimationTree 架構（`yoriichi_character.gd` 於 _ready 程式化建立）

```
loco  (AnimationNodeStateMachine)         下半身 / 一般 locomotion
      Idle / Walk / Run / TurnL / TurnR / JumpStart / Fall / Land
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
| TurnL / TurnR | `Animation_Run_Turn_Left/Right_withSkin.fbx` | 跑步中輸入夾角 > 25° 觸發，0.35 s 後回 Run |
| Roll_Dodge | `Animation_Roll_Dodge_1_withSkin.fbx` | 移除 Hips 水平位移（6.48 u） |
| Attack_Combo | `Animation_Weapon_Combo_withSkin.fbx` | 移除 Hips 水平位移（1.56 u）；三段輕連段 |
| Attack_Combo_1 | `Animation_Weapon_Combo_1_withSkin.fbx` | 移除 Hips 水平位移（2.64 u）；日之呼吸肆型 |
| Attack_Spin | `Animation_Axe_Spin_Attack_withSkin.fbx` | 原始即為 0；右鍵重攻擊／貳型 |
| Attack_Judgment | `Animation_Sword_Judgment_withSkin.fbx` | 移除 Hips 水平位移（1.33 u）；柒型 |
| Attack_Spin_Jump | `Animation_360_Power_Spin_Jump_withSkin.fbx` | 移除水平位移（2.85 u）＋垂直 clamp；拾型 |
| Jump | `Animation_Regular_Jump_withSkin.fbx` | 移除水平位移；垂直弧線 clamp，上升由物理提供 |
| Draw_Sword | `Animation_拔刀_withSkin.fbx`（裁切 0–1.0 s） | 正播拔刀 2.2x；反播收刀 |

**骨架空間軸向（Meshy 24-bone rig）**：Hips position track 的 **Z 是垂直軸**
（rest ≈ 0.986 = 髖高），X/Y 是水平軸。清 root motion 必須凍結 X/Y、保留 Z。
`animations/build_jump.gd` 是唯一的重建腳本。

## Gameplay 參數

- Roll：**3.2 m／0.422 s**（原 6.4 m 縮短 50%；clip 1.267 s × 3.0x）。
  ease-out `p(t)=1-(1-t)²`，位移與動畫共用 `_roll_duration`；跑步中可直接翻滾，
  結束依當前輸入回 Run / Walk / Idle。
- Attack：`attack_speed_scale = 3.0`（輕連段與全身技同）；Draw/Sheathe 獨立
  `draw_speed_scale = 2.2`；Idle/Walk/Run/Roll 以外的 Jump 三段見上。
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

## 日之呼吸（`sun_breathing.gd`，data-driven）

- Form01–13 定義：animation / section / layer / speed / damage / breath_cost /
  cooldown / impulse / allowed_airborne / required_mastery / vfx / cancel / next。
- 已有動畫的型：壹（Combo 第一段）、貳（Spin）、參（Combo 第二段）、
  肆（Combo_1）、柒（Judgment）、拾（Spin_Jump）。
- **仍缺專用動畫的型（slot 保留，執行時誠實跳過）**：伍（dodge counter）、
  陸（拔刀 dash 斬）、捌（突刺）、玖（dash 連斬）、拾壹（殘影反擊）、拾貳（拔刀二段斬）。
- 拾參ノ型 = `start_form13()`：把可用的型按序高速循環（框架已驗證，
  解鎖條件 `form13_unlocked` / `form13_gauge_cost` 為 export data，尚未綁輸入）。
- 型的選型輸入（方向派生 / mastery 映射）尚未實裝；目前僅左右鍵 + quick-draw。

死亡、雙刀類動畫暫未接入。
