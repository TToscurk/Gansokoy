# Yoriichi Gameplay Animations

`yoriichi_character_meshy_full.tscn` 會由 `yoriichi_character.gd` 載入本資料夾的衍生動畫。
角色仍使用同一套 Meshy 24-bone Skeleton；這些資源不會建立第二套角色或骨架。

## 操作

- `W/A/S/D`：移動
- `Shift + W/A/S/D`：疾跑（RunFast）
- `Space`：沿輸入方向翻滾；無輸入時沿目前面朝方向
- `Q`：拔刀；拔刀完成後維持 DRAWN
- 滑鼠左鍵：主攻擊；連點可依序接 Attack_1 → Attack_2 → Attack_3
- `J`：主攻擊 debug fallback
- `K`：拔刀後旋轉攻擊
- `L`：拔刀後 Judgment 攻擊

## 動畫來源

| 遊戲內名稱 | Meshy 動畫來源 | 處理 |
|---|---|---|
| RunFast | `Animation_RunFast_withSkin.fbx` | 原地循環 |
| Roll_Dodge | `Animation_Roll_Dodge_1_withSkin.fbx` | 移除 Hips 水平位移，位移由 CharacterBody3D 控制 |
| Attack_Combo | `Animation_Weapon_Combo_withSkin.fbx` | 移除 Hips 水平位移 |
| Attack_Spin | `Animation_Axe_Spin_Attack_withSkin.fbx` | 移除 Hips 水平位移 |
| Attack_Judgment | `Animation_Sword_Judgment_withSkin.fbx` | 移除 Hips 水平位移 |

移除的只有 Hips X/Z root motion；垂直姿勢、肢體動作與腳部 animation tracks 均保留。
這可避免視覺骨架離開 CharacterBody3D、碰撞體與地板。

## Gameplay 參數

- Roll：6.4 m／1.267 s（使用 Roll clip 實際長度）。CharacterBody3D 依
  `p(t) = 1 - (1 - t)^2` ease-out 曲線前進，碰撞體跟隨角色本體；Animation 不累積 X/Z root motion。
- 所有 Attack：`attack_speed_scale = 5.0`；Idle／Walk／Run／Roll／Draw Sword 維持 1.0x。
- 主攻擊使用同一份 Weapon Combo 的三段播放區間：0–34%、30–67%、63–100%。
- Combo cancel window：每段 35–65%；超過窗口的有效輸入會保留到該段尾端。
- Combo input buffer：0.30 s；最多預存到剩餘 combo 段數。
- Combo blend：0.035 s。攻擊期間停止平移，但保留 35% WASD 轉向控制。

Walk/Run turn、死亡、Regular Jump／360 jump、雙刀類動畫暫未接入：它們需要對應的鎖定轉向、生命、跳躍或雙武器 gameplay 狀態，直接播放會讓控制與碰撞不同步。
