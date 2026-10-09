# 交接：參道下行時 TPS 相機被拉近（ARM_PULL）——給 Yoriichi 相機工作的負責 session

依使用者 2026-10-09 ROUND 3 FINAL ART DIRECTION §C：「相機 pitch 修正交由 Yoriichi 相機工作的負責 session 處理。提供 −0.18 與 −0.35 的實測數據及重現步驟，不直接修改其他 session 正在編輯的玩家程式。」
本 session **沒有**修改 `characters/yoriichi/player_camera_adapter.gd`、`player_yoriichi.tscn`、`yoriichi_character.gd`，也沒有關閉相機碰撞。

## 1. 現象
參道（`ShrineApproachP10`，一の鳥居〜山頂社殿，約 30° 一定坡＋踊り場 3）往下走時，SpringArm 撞到身後的上坡，相機從 8.5 m 被拉到 3–4 m，在踊り場附近又伸回去 → 一路下行時鏡頭距離在 3.5 ↔ 5.5 m 間脈動。

## 2. 根因（量測）
- 正式 TPS 相機：Pivot 高 1.65 m、`_target_pitch` 初值 −0.18（約 −10°）、`spring_length` 8.5、`margin` 0.2（`player_camera_adapter.gd` 第 36／46–47 行）。
- 坡 30°、腕只往後上方抬約 10° → 下行時腕打到身後的坡。**只有地形（沒有任何參道碰撞）時也有 73 % 的點被拉近**。
- 相機從未進入石頭或地形（`相機入石 0`）→ 不是階梯 Mesh、不是斜坡碰撞特有的問題。
- 踊り場讓坡在 3 處變平，腕在那裡伸回 → 一段長的拉近被切成 4–5 段（次數 1→5，但拉近總比例 73 % → 55 %）。

## 3. 數據（拉近＝腕長 < 0.55×8.5＝4.68 m）
模擬（`tools/diag_village_v2_sando_camera.gd`，中心線每 0.25 m、下行方向，正式相機幾何）：

| 碰撞構成 | pitch −0.18（現行） | pitch −0.35 | pitch −0.50 |
|---|---|---|---|
| A 只有地形 | 73 %・2 次・最短 2.99 m | 2 %・1 次・3.14 m | 2 %・1 次・3.37 m |
| B 一本斜坡（ROUND 1） | 73 %・2 次・1.31 m | 5 %・1 次・1.38 m | 5 %・1 次・1.49 m |
| C 踊り場 3（現行 ROUND 2/3） | **55 %・5 次・1.46 m** | **5 %・1 次・1.54 m** | 4 %・1 次・1.67 m |
（每格的「1 次／最短 1.4–1.7 m」都在頂端起步點 s≈101.5，身後是社殿前的 `Collision`。）

正式 F5 路徑實走（`walk_p10_final.gd`，`--pitch=-0.18` 固定）：下行 ARM_PULL 事件 ROUND 2＝5、ROUND 3＝4；上行 0。

## 4. 重現步驟（godot 目錄）
```bash
G="D:/Godot/Godot_v4.7.2-stable_win64_console.exe"
# 模擬（headless，約 1 分）：預設 pitch −0.18；--pitch= 可比較
"$G" --headless --path . --script res://tools/diag_village_v2_sando_camera.gd -- --out=cam_m018.json
"$G" --headless --path . --script res://tools/diag_village_v2_sando_camera.gd -- --out=cam_m035.json --pitch=-0.35
# 正式 F5 路徑實走（非 headless，約 3 分）：輸出 walk_log.json（events: ARM_PULL）＋seg*_2x 影片用的 frames
"$G" --path . --script res://tools/walk_p10_final.gd -- --review=kirisame --route=res://tools/walk_p10_rehab_sando_route.json --pitch=-0.18 --out=<dir>/
```
`--pitch=` 是本次在 `walk_p10_final.gd` 新增的：起動時滑鼠事件會改動 `_target_pitch`（實測一次變成 +0.338），比較時要固定。

## 5. 建議方向（由相機 session 判斷，不關碰撞）
1. 陡坡下行時的 pitch 偏置：玩家在可行走面坡度 > ~20° 且移動方向朝下坡時，把目標 pitch 平滑地拉到約 −0.35（模擬：拉近 55 % → 5 %，次數 5 → 1；相機入石仍 0）。離開坡或轉向上坡時回到使用者設定的 pitch。
2. 單獨加「拉近即時、伸回平滑」的長度遲滯在本段無效（伸回區間長，次數不減）——只能作為 1 的補充。
3. 頂端起步點（s≈101.5）身後社殿前的拉近（1.5 m）與坡度無關，所有構成都有；需另看社殿前的碰撞形狀。

證據：`docs/art_review/village_v2_p10_rehab_impl/round3/r6b_shrine/camera_diag*.json/log`、`round3/r6b_shrine/walk/walk_log.json`、`round2/r6b_shrine/walk/walk_log.json`。
