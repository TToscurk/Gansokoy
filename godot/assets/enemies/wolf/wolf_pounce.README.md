# wolf_pounce.glb — 山犬（單尾幻想狼）

來源 blend：`work/wolf_rig/wolf_fantasy_rig_v004_death.blend`
骨架 WolfRig / 46 骨、75,003 頂點、4096² Color+Normal+ORM 三張貼圖。
全部動作 **原地（in-place）**，位移由 `enemy_wolf.gd` 驅動 —— Wolf_Death 例外（見下）。

## 動作表（24 fps）

| 動作 | 幀 | 秒 | 循環 | 內容 |
|---|---|---|---|---|
| Wolf_Idle | 0–96 | 4.00 | 是 | 低頭警戒呼吸，兩組不同頻的呼吸/掃視疊加 |
| Wolf_Walk | 0–32 | 1.33 | 是 | 四拍步行，stride 0.23 m |
| Wolf_Run | 0–16 | 0.67 | 是 | 奔馳，前腳 stride 0.41 m |
| Wolf_Attack_Lunge | 0–48 | 2.00 | 否 | 蓄力 1.2 s → 直線突進咬擊，前伸 0.46 m |
| Wolf_Attack_Claw | 0–36 | 1.50 | 否 | 立起前身 → 右爪下劈 |
| Wolf_Attack_Pounce | 0–84 | 3.50 | 否 | 旋風撲擊 + 滑行煞車（旋轉已烘進動畫） |
| **Wolf_Death** | **0–96** | **4.00** | **否** | **化光死亡：中招 → 挺直抬頭 → 四腳離地 → 浮空** |

## Wolf_Death 細節（實測值）

分段：
- f0–6 中招退縮（Root −7 cm、頸縮 −30°、耳 62° 貼平、尾夾 −26°）
- f6–20 挺直、抬頭（頸 +24°、脊背 −8° 抬胸），**絕不倒地**
- f20–34 四腳離地：爪高 f20 = 0.058 m → f30 = 0.13 m
- f34–96 緩緩浮空，四肢垂掛、鬃毛與尾向上飄（mane 由 +6° 走到 −10°）

量測（模型局部，1 m 級狼身；引擎內 Visual 縮放約 2.06×）：

| 幀 | 骨盆 z | 身體 zmin | 前爪 z |
|---|---|---|---|
| 0 | 0.409 | −0.008 | 0.005 |
| 30 | 0.485 | −0.008 | 0.128 |
| 60 | 0.796 | 0.238 | 0.446 |
| 96 | 1.120 | 0.569 | 0.771 |

總上浮：骨盆 0.409 → 1.120 m（**+0.71 m**）。
接地：f0–34 min z 介於 −0.013 ~ 0 m（Root ground-clamp 後殘留 1.3 cm，為腳側毛髮掃地的殼厚噪音，在 2 cm 容許內）；f34 之後刻意離地，不再 clamp。

## companion FX：`dissolve_fx.json`

由本動畫**逐幀量測**重新產生（97 筆），欄位：

- `dissolve` 0→1：溶解門檻。f44 起、f94 全消，smoothstep。
  ⚠ 初版是 f26 起，實機拍出來身體 2.1 s 就沒了，浮空還沒讀出來就化光 —— 延後到 f44。
- `emit_rate` 0→1：光點粒子量，f44 起、中段最強、f96 收 0。
- `zmin`/`zmax`：該幀身體上下界，供 shader 由下往上掃描。
- `cx/cy/cz`：體心，粒子發射器跟隨。
- ⚠ 是 Blender z-up 座標；`wolf_dissolve_fx.gd` 的 `sample()` 已負責換到 Godot y-up。

## 引擎接線

`enemy_wolf.gd`：
- `_on_died()` → `_play("Wolf_Death")`，換上 `wolf_dissolve.gdshader` 材質、生 `DissolveMotes` 粒子，`_dissolve_t = 0`。
- `_physics_process()` DEAD 分支每幀 `_tick_dissolve()` 餵 `dissolve / sweep_min / sweep_max` 與粒子 `amount_ratio`。
- 掃描底線 `_sweep_floor` 在死亡當下鎖定 —— zmin 會隨浮空抬高，拿它當底會讓溶解看起來比曲線快。
- 存活時間 = `DissolveFX.duration()` (4.0 s) + 1.7 s 粒子殘留，然後 `queue_free()`。

## 已知事項

- glTF 匯出兩個正常警告：頂點骨影響 >4（取權重最高 4 個並正規化）、多個貼圖節點共用一個 sampler。
- 死亡上浮是動畫 Root 曲線推的，不是腳本 velocity；若之後想改高度，改 Blender 端 `clip_death()` 的 `K_dz` 再重烘、重出 JSON，兩者必須同步。
- 循環旗標沒隨 glTF 帶進來，Idle/Walk/Run 由 `enemy_wolf.gd` 在 `_ready()` 手動設 LOOP_LINEAR。

驗收：`Godot --headless --path godot --script tools/verify_enemy_wolf.gd` → failures=0，
其中「死亡浮空」實測 Root y 0.051 → 1.059（3 秒，含 2.06× 縮放）。

實機化光拍照（**必須開視窗，headless 拍不到 shader/粒子**）：
`Godot.exe --path godot --script tools/capture_wolf_death.gd --resolution 1280x800`
→ `_review/wolf_death/`。取樣依 `_dissolve_t` 而非牆鐘時間（存檔耗時會讓標籤對不上）。

shader 調校紀錄：`edge_energy` 原 5.0 過曝——溶解末段身體只剩頭時被 bloom 糊成一團白，
誤判為「身體提早消失」。改 2.6、`edge_width` 0.09 → 0.055。
