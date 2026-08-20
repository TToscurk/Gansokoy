# Yoriichi Gameplay Animations

`yoriichi_character_meshy_full.tscn` 會由 `yoriichi_character.gd` 載入本資料夾的衍生動畫。
角色仍使用同一套 Meshy 24-bone Skeleton；這些資源不會建立第二套角色或骨架。

## 操作

- `W/A/S/D`：移動
- `Shift` 按住：疾跑（RunFast）；快按（≤ 0.25 s 內放開）：沿輸入方向翻滾，
  無輸入時沿目前面朝方向
- `Space`：跳躍（前 0.533 s 蹲伏預備，之後物理起跳；空中為慣性移動）
- `Q`：拔刀 / 收刀 toggle；攻擊中按 Q 會排隊（pending_sheathe），攻擊播完自動收刀
- 滑鼠左鍵：主攻擊；連點依序接 Attack_1 → Attack_2 → Attack_3（Walk/Run/空中都可攻擊）
- 滑鼠右鍵：Spin 重攻擊（Judgment 暫未綁鍵，保留資源）
- 鍵盤攻擊鍵（J/K/L）已全部移除，無 debug fallback

## 動畫來源

| 遊戲內名稱 | Meshy 動畫來源 | 處理 |
|---|---|---|
| RunFast | `Animation_RunFast_withSkin.fbx` | 原地循環 |
| Roll_Dodge | `Animation_Roll_Dodge_1_withSkin.fbx` | 移除 Hips 水平位移（6.48 u），位移由 CharacterBody3D 控制 |
| Attack_Combo | `Animation_Weapon_Combo_withSkin.fbx` | 移除 Hips 水平位移（1.56 u） |
| Attack_Spin | `Animation_Axe_Spin_Attack_withSkin.fbx` | 移除 Hips 水平位移（原始即為 0） |
| Attack_Judgment | `Animation_Sword_Judgment_withSkin.fbx` | 移除 Hips 水平位移（1.33 u） |
| Jump | `Animation_Regular_Jump_withSkin.fbx` | 移除水平位移；垂直弧線 clamp 到 rest 高度，上升由物理提供 |

**骨架空間軸向（Meshy 24-bone rig）**：Hips position track 的 **Z 是垂直軸**
（rest ≈ 0.986 = 髖高），X/Y 是水平軸。第一版衍生資源誤凍結 X/Z、留下 Y，
造成 roll 殘留 6.48 u 水平漂移（視覺前飛 + 結束瞬移回原點）。
`animations/build_jump.gd` 是唯一的重建腳本：凍結 X/Y、保留 Z 垂直起伏。
垂直姿勢、肢體動作與腳部 animation tracks 均保留，
視覺骨架不會離開 CharacterBody3D、碰撞體與地板。

## Gameplay 參數

- Roll：6.4 m／0.422 s（clip 1.267 s × `roll_animation_speed = 3.0`）。
  CharacterBody3D 依 `p(t) = 1 - (1 - t)^2` ease-out 曲線前進，位移 duration 與
  動畫同一個 `_roll_duration`，碰撞體跟隨角色本體；Animation 不含水平 root motion。
- 所有 Attack：`attack_speed_scale = 3.0`；Idle／Walk／Run／Jump／Draw／Sheathe 維持 1.0x。
- 主攻擊使用同一份 Weapon Combo 的三段播放區間：0–34%、30–67%、63–100%。
- Combo cancel window：每段 35–65%；超過窗口的有效輸入會保留到該段尾端。
- Combo input buffer：0.30 s；最多預存到剩餘 combo 段數。
- Combo blend：0.035 s；攻擊結束回 locomotion 用 `attack_recovery_blend = 0.12 s`。
- 地面攻擊保留移動：水平速度 = locomotion × `attack_move_factor = 0.65`，
  並保留 35% WASD 轉向控制；不再原地定住。
- 空中慣性：離地後不直接覆寫水平速度。有輸入 → move_toward(目標,
  `air_acceleration(4.0) × air_control(0.35)` = 1.4 m/s²)；無輸入 → 只以
  `air_drag = 0.2 m/s²` 衰減（跑跳放開 W 仍保持前進慣性）。落地恢復直接控制。
- 空中攻擊：gravity 與慣性照常（攻擊不改寫 velocity），結束後 blend 0.08 s 回
  Jump clip 的下落姿勢（`jump_air_pose_time = 0.9`），落地才回 FREE。
- 收刀：`Draw_Sword` 以 `play_backwards` 反向播放，不新增動畫資源。刀的
  socket 切換依實際播放位置對 `t_unsheathe = 0.65` 判斷，反向跨過即回鞘。

- Jump：物理起跳 `jump_velocity = 5.33 m/s`（gravity 20 → 空中 0.533 s，
  與 clip 空中段 0.533~1.067 s 一致；物理跳高 0.71 m ≈ 動畫弧線 0.63 m）。
  clip 全長 1.9 s，起終幀 Hips 回到同位（對 Idle 最大骨骼差 32.5°，
  由 0.12 s action blend 吸收）。落地判定在 physics，跳下平台也能正確結束。

Walk/Run turn、死亡、360 jump、雙刀類動畫暫未接入：它們需要對應的鎖定轉向、生命、跳躍或雙武器 gameplay 狀態，直接播放會讓控制與碰撞不同步。
