# godot_motion.v1 — Godot 逐格真值記錄格式

由 `godot/tools/motion_capture/motion_recorder.gd` 產生、`tools/video_intel/validate_animation.py` 驗證。
一次錄製＝一個資料夾：

| 檔案 | 內容 |
|---|---|
| `meta.json` | 版本、場景、Godot 版本、命令列、視窗／viewport 大小、同步標記版面、刀的網格幾何、座標系說明、`unavailable`（取不到的資料與原因） |
| `frames.jsonl` | 一行＝一個渲染格（`frame_pre_draw` 時取樣） |
| `events.jsonl` | 事件（命中、出招結束、揮刀開始、停格計數開始／結束、姿勢凍結開始／結束、動畫速度變更、Engine.time_scale 變更） |
| `video.avi` | Movie Maker 輸出（`--write-movie … --fixed-fps 60`） |
| `video_frame_map.json` | 驗證器解出的「影片第 k 格 → recorder id」 |
| `legacy_slog.json`／`legacy_log.*` | 被測 demo 自己的舊記錄（相容對照用） |
| `record_cmd.json` | 實際執行的命令、exit code、耗時 |
| `report.json`／`report.md`／`review_sheet.png` | 驗證結果 |

## 取樣時機
- `id`：MotionRecorder 的格號，在 recorder `_process`（`process_priority` 最大＝本格最後執行）設定，同一格的 `frame_pre_draw` 寫入。**同步標記顯示的就是這個 id**。
- `frame_pre_draw` 在本格所有 `_process`、AnimationTree、Skeleton3D 修改器（IK、彈簧骨）之後、繪製之前 → 記錄值＝這一格畫面上的姿勢。
- `order`：本格內各回呼的時間戳（µs）：`harness_process_first`（外殼，比被測場景先跑）、`mixer_updated`（AnimationTree 算完）、`skeleton_updated`、`recorder_process_last`、`pre_draw`。

## 欄位（frames.jsonl）
座標系後綴：`_w`＝Godot 世界座標（公尺，+Y 上）；`_local`＝角色根節點本地座標；`_px_godot`＝`Camera3D.unproject_position`（像素，左上原點，viewport 大小）。

| 欄位 | 說明 |
|---|---|
| `id`, `frame_drawn`, `process_frame`, `physics_frame`, `physics_steps_since_prev` | 格號：recorder／`Engine.get_frames_drawn()`／`get_process_frames()`／`get_physics_frames()`／上一列以來跑了幾次 `_physics_process` |
| `t_usec`, `delta`, `physics_delta`, `time_scale` | 單調時間（自 recorder 啟動，µs）、本格 process delta、physics delta、`Engine.time_scale` |
| `viewport.size` | 實際渲染大小（像素） |
| `camera` | `path`、`pos_w`、`basis_w`（三個欄向量）、`quat_w`、`fov_deg`、`keep_aspect`、`near`、`far`、`projection_type`、`projection_cols`（`get_camera_projection()` 四個欄向量）、`view_xform`（相機逆變換：三欄＋原點）、`viewport_px` |
| `actor` | 根節點 `pos_w`、`quat_w`、`yaw_rad` |
| `skeleton_xform_w`, `bones_p_w`, `bones_q_w` | 骨架全域變換；主骨（`meta.main_bones` 順序）世界位置／旋轉（xyzw） |
| `main_delta_max_m`, `secondary_delta_max_m` | 與上一列相比，主骨／彈簧骨（Haori_、Hair_、Cuff_、Sleeve*）在角色本地座標的最大位移 |
| `sword.node_origin_w` | `Sword_Hand` 節點原點（刀網格 y=0：柄上、鍔中心下方約 7 cm）——**舊 demo 記錄的 `tip_x/y/z` 就是這個點** |
| `sword.hilt_w` | 握柄中心＝柄（鍔與柄頭之間）頂點質心 |
| `sword.guard_w` | 鍔＝截面最寬 2 cm 段的頂點質心（兩端 6 cm 除外） |
| `sword.blade_tip_w` | **真刀尖**＝沿刀身長軸最遠的網格頂點（彎刀，不在軸線上） |
| `sword.blade_tip_vel_w`, `blade_tip_speed` | 由真刀尖相鄰兩列差分 ÷ delta（第一列 null） |
| `sword.blade_dir_w`, `blade_len_m` | 鍔→刀尖單位向量（彎刀弦向）、長度 |
| `sword.blade_tip_px_godot`, `hilt_px_godot` | Godot 自己算的投影像素（驗證器拿來核對自己的矩陣運算） |
| `feet.Left/Right` | 腳趾／腳踝世界位置、腳趾高出校正值（前 10 格最低）多少、水平速度、`contact`；`rule` 說明判定依據（**運動學推定，不是物理接觸**） |
| `controller` | 被測場景的 `combat` 控制器（若有）：`state`/`state_name`、`shot_key`、`shot_t`、`hitstop_left`、`hitstop_total`、`hitstop_frames_cfg`、`atk_w`、`label`、`is_attack`、`body_velocity_local` |
| `anim` | AnimationTree：`attack_time_scale`（`parameters/asts/scale`）、`shot_time_scale`（`parameters/sts/scale`）、`tree_active`、`callback_mode_process` |
| `freeze` | 三件事分開：`hitstop_counter_active`（`hitstop_left>0`）、`anim_time_scale_zero`（攻擊動畫時間縮放＝0）、`shot_t_unchanged`、`main_pose_frozen`（主骨位移 < 0.5 mm） |
| `events` | 本格事件（同 events.jsonl） |

取不到的值一律 `null`，原因寫在 `meta.unavailable`，不填假值。

## 停格的三種計數（實測定義）
- `controller.hitstop_total`：控制器累計凍結格數；每次命中 `hitstop_frames` 格（目前 3）。
- `anim_time_scale_zero`／`shot_t_unchanged`：動畫真的被停住的格數＝每次命中 3 格。
- `hitstop_left>0` 的列：每次命中只有 2 格——這些招式設了 `freeze_hit_frame`，命中那一格就停並先計 1，`hitstop_left` 從 2 倒數；取樣在 `combat.step()` 之後，計數已遞減，第 3 個凍結格取樣時已是 0。
- 停格期間布料／頭髮彈簧骨照常動（`secondary_delta_max_m` > 0），所以只看影格差抓不到停格。

## 同步標記
左下角 16×2 格、每格 12 px（`meta.marker.rect_px` 為 viewport 像素）：`bits[0:4]=1011`、`bits[4:28]`＝24 位 id（高位在前）、`bits[28:32]`＝六個 4 位元組的 XOR；白＝1。驗證器逐格解碼 → 得到影片格→id 對照，抓重複格、掉格、無法辨識格。

## 舊記錄的相容處理
- `isshin_combat_demo.gd --log`：`tip_x/y/z` 欄位**名稱保留、值不變**（＝Sword_Hand 原點）；`meta.col_notes` 標示棄用。真刀尖等新欄位附加在骨骼之後（`extra_cols`、`extra_offset`；`width` 已含附加欄位，骨骼起點仍是 `len(cols)`）。
- `isshin_slash_demo.gd --slashlog`：`tip_speed`、`tip_l`、命中的 `tip_speed` 仍是固定偏移點 `TIP_LOCAL(0,1.085,0)`（距真刀尖約 6.2 cm），值不變；`field_notes` 說明。
- `blade_hit_judge.gd` 的命中判定刀段同樣用 `TIP_LOCAL`／`GUARD_LOCAL`；這是遊戲判定，**本階段沒動**。
