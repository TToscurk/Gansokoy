# phase3_r1/evidence 說明

- `gate_r2_main.log`／`gate_r2_posts.log`／`gate_w9_reach.log`：W9 R2 gate（既有）在 Phase 3 內容上的結果（374／0、反向 36/36；柱 19／0；到達性 NG 0）。
- `gate_p3_environment.log`：環境 gate（新）。**提交後更正版**：屋敷林判準還原為 16 m，40 通過／0 失敗。
- `walk_on.json`／`walk_on.log`：最終判準下的 ON 行走（21 脚 FAIL 0；`baseline_compare` 是與 OFF 基準的逐脚比較）。
- `walk_off.json`／`walk_off.log`：OFF 基準（`EnrichW9P3`、`ArchW9R2P13` 皆停用）。**這份是用第一版判準（reach 脚要求 lost==0）錄的，所以自己顯示「FAIL 4」**，就是 B_lane_east／C_road_west／C_plank_to_door／C_yard_to_garden 四條原地形脚（lost 37／1／9／24）。原始量測值（frames／blocked／lost／max_dy／終點）不依判準，ON 的 `baseline_compare` 用的就是這些值；未用最終判準重錄。
- `perf.json`／`perf.log`：代表鏡位 ALL／OFF／P3ENV 的 GPU／draw／prim。
- `camera_before_after_compare.json`：43 對 BEFORE/AFTER 鏡位逐筆比對（42 對相同；bT3 不同＝SpringArm 變短，腳下到相機 3.48→2.48 m、arm 長 2.75→1.54 m）。
- `springarm_bT3_before.log`／`springarm_bT3_after.log`：`tools/p13/w9/diag_arm.gd` 的輸出（命中的 collider 與 arm 長）。
- `p3_environment_plan.json`：環境 overlay 的 plan 傾印（87 件；更正版，cluster desc／who 的南北已改）。
- `repro/`：鏡位檔與腳本的寫し。
