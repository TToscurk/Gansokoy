# R9：普通劍術派生＋日之呼吸・圓舞（候選，ART_REVIEW）

不改正式 Player、跑酷、正式場景與共用骨架。19 招動作庫、Dojo 與各招獨立 demo 都保留。
回退點：`D:/research/sekiro_r8_p0/backups/v24_isshin_pre_r9_20261020_2357/`（整個 v24_isshin，附 MANIFEST.sha256）。

## 試玩
`res://characters/yoriichi/v24_isshin/r9/r9_combat_demo.tscn`

| 按鍵 | 功能 |
|---|---|
| WASD | 移動 |
| Shift＋W | 衝刺 |
| Space | 閃避 |
| F | 跳躍 |
| J／K／滑鼠左鍵 | 攻擊（依派生表出招） |
| L／滑鼠右鍵 | 日之呼吸・圓舞 |
| G | 拔刀／收刀 |
| 1–9、0（Tab 換頁） | 選一般攻擊的起手招 |
| V | 特效開／關 |

## 資料
- `r9_moveset.json`：派生表（branches 由上往下比對）、衝刺設定、輸入緩衝、跳躍招、R9 用的取消時間覆寫、19 招的狀態／啟用。
- `sun_breathing.json`：日之呼吸技能（招式、傷害、冷卻、可從哪些普通招式接、VFX 參數、音效事件）。新增其他型＝在 skills 加一筆＋一支動畫。

## 程式
- `r9_combat_demo.gd`：派生路由、輸入緩衝、跳躍、技能系統、錄影相機（`--cam=third|side|front`）、量測（`--perf=PATH`）。
- `sun_vfx.gd`：日之呼吸 VFX 模組（刀刃火焰、斬擊殘影、火星、命中火焰）；`sun_trail_r9.gd`＝正式 SwordTrail3D 的子類（換取樣與時鐘，正式檔不改）。
- `skill_audio.gd`：技能音效事件（揮刀／點燃／火焰循環／命中分開設定）。
- `../blade_hit_judge.gd`：所有候選場景共用的刀身命中判定。

## 動畫來源
- 圓舞：永真 c7400 a000_003008，重新配時（`notes/r9/build_enbu.py`）。
- 跳躍：弦一郎 c7100 TAE 3022 起跳＋不攻擊的落地（`notes/r9/build_jump.py`）。
- 衝刺：弦一郎 c7100 a000_405010 跑步循環。
