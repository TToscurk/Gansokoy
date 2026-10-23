# S04 畫面不連動：為什麼不用逐像素比對

目標是證明 S01 R1 沒有改到 S04 的最終畫面。先嘗試逐像素比對：用 V1.3 final（2026-10-15 21:31）重拍的 35 張 PNG（`diag_shots.gd --hour=10 --exps=base`）對 R1 狀態重拍的同一組鏡位。

結果：35 張全部有大面積差異（每張 2.8 萬–106 萬像素，最大通道差 40–176）。**這不能解讀成 S04 變了**——先量測了渲染本身的底噪（同一狀態、同一組鏡位，連拍兩次互比，4 個代表鏡位）：

| 模式 | 鏡位 | 兩次互比的差異像素 | 最大通道差 |
|---|---|---|---|
| 一般（即時） | f05_ground_macro | 913,527 / 1,440,000 | 147 |
| 一般（即時） | t01_entrance_south | 176,344 | 89 |
| 一般（即時） | t04_center_to_waterfall | 906,366 | 120 |
| 一般（即時） | t07_outer_forest_east | 748,416 | 86 |
| `--fixed-fps 60` | f05_ground_macro | 3,282 | 147 |
| `--fixed-fps 60` | t01_entrance_south | 39,495 | 22 |
| `--fixed-fps 60` | t04_center_to_waterfall | 101,390 | 121 |
| `--fixed-fps 60` | t07_outer_forest_east | 98,852 | 24 |

結論：獸道的渲染對時間敏感（風擺、水流、粒子），連同一狀態都不可逐像素重現；固定 60 fps 後仍有殘差（粒子亂數／時間性效果）。**逐像素比對在這條管線上不是有效證據**，沒有拿來宣稱「S04 畫面不變」，也沒有拿來宣稱「S04 畫面變了」。

S04 不連動改用檔案層級證據（見 `tree_diff_v13_vs_r1.md`、`verify_r1c.json` 的 `isolation.*`、`verify_s01_negatives.json`）：
- S04 的場景、地形、碰撞、材質（含共用的 `bp_ground.gdshader`／`.tres`、`bp_rock.*`）與 V1.3 備份**逐位元相同**；
- 主場景只差 Godot 每次重抽的 `unique_id`，語意比對 0 行差異；
- `forest_plan.json` 的 S02／S03／S04 共 3222 筆與 V1.3 逐筆相同。
