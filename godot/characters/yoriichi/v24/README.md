# 緣一 V2.4 衣髮骨架（Godot 整合，試作，未接正式 Player）
- `yoriichi_v24.glb`：V2.4 角色（已烘成 1.7 m，場景縮放保持 1.0）。173 骨 = 65 身體 + 84 衣髮（下擺 8 鏈/頭髮 5 鏈）+ 24 袖口（Cuff_*）。動畫 `idle`(Neutral Idle) / `walk`(Walking)，皆 Mixamo Arm-Space 0.78、in-place、30fps。
- `yoriichi_v24_rig.gd`（class YoriichiV24Rig）：掛在含 glb 的節點上，自動建 3 組 SpringBoneSimulator3D + 身體碰撞膠囊並循環播動作。
- `yoriichi_v24_walk_test.tscn`：F6 測試（WASD / Q E / R 彈簧骨 / H 羽織）；`-- --auto --auto-shots [--front]` 自動截圖。
- `verify_v24_springs.tscn`：headless 取樣 A(彈簧關)/B(開)，輸出 user://v24_springs_samples.json；環境變數 RIG_TX/RIG_SR/RIG_K/RIG_G 覆寫參數。
- 資產由 `袖口彈簧骨_r5/` 的 build_hybrid.py（暫存工作區）自 `衣髮碰撞試作_r1` 產生：袖子頂點還原 V2.4 原權重，僅袖口外段（t>-0.7 前臂長）改綁 Cuff 骨。
- 狀態：ART_REVIEW 前的技術試作；穿身未歸零；未接 `player_yoriichi.tscn`。

## 2026-10-14 修正：手臂穿出袖管
先前預設（軀幹碰撞 +14 cm、袖口鏈與手臂碰撞、剛性 1.5）會把貼身側袖管壓扁，右臂 9% 頂點在袖管外（最深 46 mm）。
改為：袖口鏈不碰手臂膠囊、軀幹 +5 cm、關節半徑 0.03、剛性 30、重力 0.05 → 左 1%／右 0%。代價：袖子擺動變小。
