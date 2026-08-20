# Yoriichi Gameplay Animations

`yoriichi_character_meshy_full.tscn` 會由 `yoriichi_character.gd` 載入本資料夾的衍生動畫。
角色仍使用同一套 Meshy 24-bone Skeleton；這些資源不會建立第二套角色或骨架。

## 操作

- `W/A/S/D`：移動
- `Shift + W/A/S/D`：疾跑（RunFast）
- `Space`：翻滾閃避
- `Q`：拔刀；拔刀完成後維持 DRAWN
- 滑鼠左鍵或 `J`：拔刀後連段攻擊
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

Walk/Run turn、死亡、360 jump、雙刀類動畫暫未接入：它們需要對應的鎖定轉向、生命、跳躍或雙武器 gameplay 狀態，直接播放會讓控制與碰撞不同步。
