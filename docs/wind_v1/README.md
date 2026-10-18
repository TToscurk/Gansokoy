# Gensokyo World Wind System V1

> V1.1 追加（隨時間轉向的空間場＋五類物件＋pilot）：見 `README_V11.md`。本檔保留 V1 的基準與 V1 時期的數字。

狀態：**WIND_V1_REVIEW**（未經使用者 `ART_APPROVED`）。視覺由使用者裁定。

## 一句話

一個全域風場（autoload `Wind`）→ 5 個 global shader uniform → 既有植被／草／暖簾著色器讀取；
不新增材質、不新增 draw call、不逐棵 CPU 更新、不動場景與碰撞。

## 架構

```
scripts/wind.gd  (autoload Wind)
  風場狀態機：方向／強度／陣風包絡／平滑過渡／空間取樣／除錯 API
        │  每幀只上傳 5 個值（RenderingServer.global_shader_parameter_set）
        ▼
  gw_dir( vec3 )  gw_strength( float )  gw_gust( float )  gw_time( float )  gw_flutter( float )
        │
        ├─ assets/village_v2/veg_kit/veg_common.gdshaderinc   → veg_leaf / veg_bark
        ├─ assets/village_v2/meadow/meadow_grass.gdshader     → 草原／獸道地被
        ├─ maps/village_v2/shaders/p8_paddy_plant.gdshader    → 秧苗／田埂草／地被草叢
        ├─ assets/shaders/grass_wind.gdshader                 → trail／kourindou／slice 草
        └─ assets/shaders/wind_cloth.gdshader                 → 暖簾 nr_noren*（執行期換材質）
```

為什麼不是第二套植被 shader：專案原本就有 `veg_leaf`／`veg_bark`（UV2 已烤好階層風權重 0–1）
與三套草 shader，只是風參數全設 0。V1 把它們接到同一個風場，沒有改網格、沒有重烤資產。

## 公開 API（`Wind` autoload）

| 方法 | 說明 |
|---|---|
| `set_preset(int)` | `Wind.Preset.CALM / BREEZE / MODERATE / GUST`；只換強度與陣風節奏，方向不跳 |
| `set_wind(deg, strength)` | 直接指定吹向方位（0=+X、90=+Z）與強度 0–2；給劇情／技能用 |
| `set_override(deg, strength, seconds)` | 限時覆寫；結束自動回 preset |
| `clear_override()` | 取消覆寫 |
| `trigger_gust(strength=-1, duration=-1)` | 手動陣風（預設振幅取 preset 的 2.2 倍） |
| `set_enabled(bool)` / `toggle_enabled()` | 平滑關風／恢復（0.45 s 斜坡，不是 0 幀切斷） |
| `get_wind() -> Dictionary` | preset／方向／強度／陣風／有效值／風時鐘 |
| `wind_direction() -> Vector3` | 世界空間風向單位向量 |
| `sample_wind(world_pos) -> Vector3` | 近似 m/s；純函式（位置＋風時鐘），可重現。**角色頭髮／羽織用這個** |
| `set_frozen(bool)` / `debug_advance(sec)` | 凍結／手動推進風時鐘（截圖、測試、A/B） |
| `cloth_count()` | 已接線的暖簾數（診斷） |

訊號：`preset_changed(name)`、`gust_triggered(strength)`、`wind_toggled(enabled)`。

## Preset 表

| preset | base | gust 振幅 | 自動陣風週期／持續 | 說明 |
|---|---|---|---|---|
| Calm | 0.04 | 0 | — | 幾乎靜止 |
| Light Breeze（預設） | 0.55 | 0.18 | 11 s／3.4 s | 草原、樹冠、暖簾的日常微風 |
| Moderate | 0.88 | 0.26 | 8 s／3.0 s | 明顯擺動 |
| Strong Gust | 1.10 | 0.45 | 5.5 s／2.6 s | 陣風＋更快二次運動 |

過渡：強度 tau 1.35 s、方向 tau 1.9 s、自動陣風再平滑 tau 0.55 s。
所以 GUST→CALM 不會把當下陣風一幀抽掉（實測 30 fps 每幀最大變化 0.026）。

## 誰在動（village_v2 ＋ 獸道 S01）

| 資產 | 實例數（實測） | 回應 |
|---|---|---|
| 樹葉卡 `VK_Leaf_A`（veg_leaf） | 11,571 nodes ＋ 3,194 MultiMesh | 葉叢外緣最強（UV2 權重 →1），枝條中，樹幹 ≈0.01 |
| 樹皮 `VK_Bark_*`（veg_bark） | ~17,000 nodes ＋ ~19,000 MM | 大枝／小枝 1–5 cm，樹幹幾乎不動 |
| 竹稈 `BK_Culm_*`（veg_bark，wind_speed 1.35） | 3,120 ＋ 2,798 MM | 稈基穩定、梢部彈性擺動 |
| 竹葉 `BK_Leaf_A`（veg_leaf，flutter 0.1） | 93 ＋ 3,168 MM | 比樹葉更快、更碎 |
| 草原 `meadow_grass` | 153,772 MM | 草浪沿風向推進（既有 P9 振幅，BREEZE＝原外觀） |
| 秧苗／田埂草／地被草叢 `p8_paddy_plant` | 824,066 ＋ 21,640 MM | 葉尖擺動，根部釘死 |
| 暖簾 `nr_noren_*`（wind_cloth） | 50 片（其中 27 片在相機範圍內可見） | 上緣釘死、下襬 3–10 cm 擺動＋側擺 |

距離閘門：樹 45→60 m 漸弱、60 m 外跳過；草 34 m（草原）／45 m（p8、grass_wind）外跳過。
位移只改頂點，不改 AABB、不改碰撞。

## 未接線（與原因）

- **旗幟／幟／長條布**：目前是獨立 MeshInstance＋StandardMaterial，沒有共用材質可安全批次換；
  換材質需逐支重建 albedo/emission 參數，V1 不做（暖簾先證明布料路徑）。
- **SimpleGrass addon（只有 slice 用）**：它有自己的 `sgt_wind_*` 全域。V1 不改，避免兩套風互相打架；
  slice 的草目前仍由 addon 自己吹。
- **緣一頭髮／羽織**：`v24` rig 已有 `SpringBoneSimulator3D`（sleeve／hem／hair）。
  建議下一步把 `Wind.sample_wind(bone_world_pos)` 當額外加速度餵進那個 sim，不要改動畫權重。
- **完整天氣、風推動角色、布料模擬、樹木破壞**：明確不在 V1。

## 除錯面板

`F9` 開關（只有 debug build 會建立；release 完全不出現）。
`1–4` preset、`G` 陣風、`0` 開／關風、`[` `]` 方向 ±15°、`-` `=` 強度 ±0.1。
`--wind-debug` 啟動時自動打開。

啟動旗標（A/B 用）：`--wind=off|calm|breeze|moderate|gust`、環境變數 `WIND_NO_CLOTH=1`（跳過暖簾接線）。

## 工具

```bash
# 控制器＋接線驗證（headless，會 FAIL 就 exit 1）
Godot_v4.7.2-stable_win64_console.exe --headless --path godot --script res://tools/wind/wind_verify.gd

# 實機連拍（非 headless）：固定風時鐘步進，每 preset 8 幀
Godot_v4.7.2-stable_win64_console.exe --path godot --script res://tools/wind/wind_capture.gd -- \
  --scene=village_v2 --views=res://tools/wind/views_village.json \
  --out=C:/tmp/wind --presets=calm,breeze,moderate,gust,off --frames=8 --transition=1

# 效能 A/B/A（VSync 關；viewport GPU time）
Godot_v4.7.2-stable_win64_console.exe --path godot --disable-vsync \
  --script res://tools/wind/wind_perf.gd -- --scene=village_v2 \
  --views=res://tools/wind/views_village.json --out=C:/tmp/perf.json

# 分析（動量比、diff 圖、GIF）
python tools/wind/wind_analyze.py --dir <capture out> --out <analysis out> --gif-views forest_edge
python tools/wind/wind_sheet.py  --dir <capture out> --out <sheet.jpg> --views forest_edge,bamboo_grove
```

## 實測（GTX 1070、1280×720、Forward+、VSync 關、A/B/A 各 150 幀中位數）

village_v2：

| 機位 | draw | prim | 風關 GPU | 風開 GPU | Δ |
|---|---|---|---|---|---|
| meadow_a | 3,829 | 6.68 M | 10.85 ms | 12.25 ms | **+1.40 ms（+13%）** |
| forest_edge | 3,989 | 6.88 M | 13.75 ms | 14.29 ms | **+0.55 ms（+4%）** |
| bamboo_grove | 5,017 | 8.24 M | 12.91 ms | 13.34 ms | **+0.44 ms（+3.5%）** |

獸道 S01：

| 機位 | draw | prim | 風關 GPU | 風開 GPU | Δ |
|---|---|---|---|---|---|
| bp_torii | 507 | 5.80 M | 6.78 ms | 8.80 ms | +2.01 ms（+30%） |
| bp_meadow | 383 | 4.60 M | 5.98 ms | 7.70 ms | +1.72 ms（+29%） |
| bp_grass | 288 | 3.85 M | 4.88 ms | 6.67 ms | +1.79 ms（+37%） |
| bp_forest | 48 | 1.03 M | 1.46 ms | 2.05 ms | +0.59 ms（+40%） |

draw call 在所有機位、風開／關之間完全不變。獸道的百分比高是因為它的基準幀很輕（6 ms／160 fps）；
絕對成本仍 ≤ 2 ms。

載入：village_v2 `load_map` 約 4.1 s（三次 4.23／4.10／4.13 s）；跳過暖簾接線 4.10／4.15／4.03 s
（差 ≤ 0.06 s，在量測噪聲內）。沒有新增資源或 shader variant。

## 風不是同步正弦

- 相位＝世界座標低頻場＋每頂點 UV2 相位（每主枝一個，子枝帶微差）。
- 陣風＝沿風向傳遞的波（`dot(wp, dir)`），所以是一片掃過，不是全部同時點頭。
- 草：世界座標 value noise 扭曲波前（沿襲 P9），再加 `gw_gust` 放大與 `gw_flutter` 加快細顫。

## 已知限制

1. 樹冠位移 >0.3 m 時理論上可能超出原 AABB 邊緣被剔除；目前最大振幅（GUST、大樹）約 0.2 m，
   未觀測到 pop。不改 AABB 是為了避免與既有剔除／陰影預算互相影響。
2. 陰影跟著頂點一起動（同一支 vertex shader 跑 shadow pass），代價已含在上表 Δ 內。
3. `global_shader_parameter_get()` 在 runtime 是 editor-only，程式內無法回讀；驗證改由
   「像素動量比」與控制器狀態完成。
4. 風場只有一個方向；未來天氣系統要给區域性風（例如竹林渦流）需在 `Wind` 加第二層 override。
5. 既有 `veg_kit`／`bamboo_kit` manifest 的 shader sha256 已因本次修改失配，需使用者同意後重封存。
