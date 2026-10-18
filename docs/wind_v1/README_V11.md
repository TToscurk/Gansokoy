# Gensokyo World Wind System V1.1（WIND_V1_REVIEW）

狀態：**WIND_V1_REVIEW**。視覺與手感由使用者裁定；agent 只給 `ART_REVIEW`。
本版在 V1（植被風場）之上加了：**隨時間緩慢轉向的空間隨機場**、**五類質量分級物件**、
**陣風前緣傳播**、**遮蔽體積**、**混合物件 pilot**。

## 1. 架構

```
scripts/wind.gd（autoload Wind）
  ├─ 全域狀態：preset／緩慢轉向／lull／自動＋手動陣風
  ├─ 空間場：sample_field(pos)
  │     n1 = sin(pos·k1 + t·0.11)   k1=(0.045,0.031)  λ≈27 m
  │     n2 = sin(pos·k2 + t·0.07)   k2=(-0.021,0.038) λ≈35 m
  │     front = sin(t·1.25 − pos·dir·0.10)  → 12.5 m/s 沿風向推進
  │     strength = (base+gust) · (1+0.28(n1−.5)) · (1+0.14(n2−.5)) · (0.85+0.30·front) · shelter
  │     angle    = base + 0.38(n1−.5) + 0.12(n2−.5)
  ├─ 每幀上傳 gw_dir／gw_strength／gw_gust／gw_time／gw_flutter
  ├─ 暖簾：50 片各自 5 Hz 取樣 obj_wind（instance uniform）
  └─ 除錯：F9 面板、`--wind=`、`debug_reset()`（同 seed 可重現）
        │
        ├─ veg_common／veg_leaf／veg_bark（樹、竹）——同一個場公式（GPU）
        ├─ meadow_grass／p8_paddy_plant／grass_wind（草）——同一個場公式（GPU）
        └─ wind_cloth（暖簾）
scripts/wind/wind_suspended.gd  → 類別 B 吊掛物（擺錘＋慣性＋阻尼）
scripts/wind/wind_loose.gd      → 類別 C／D 地面鬆動物（靜摩擦門檻＋積分＋接地＋邊界）
```

**關鍵設計**：CPU 與 shader 用同一組波向量與同一個 front 項。所以同一陣風會**同時**掃過
草、樹、暖簾、燈籠、落葉；它們的差異來自質量／面積／阻尼／慣性，不是各自獨立的隨機源。

## 2. 公開 API

| 方法 | 說明 |
|---|---|
| `sample_field(pos) -> {angle, strength, speed}` | 空間場取樣（角度/強度/近似 m/s）。道具與角色用這個 |
| `sample_wind(pos) -> Vector3` | 同上，回傳速度向量（m/s） |
| `add_shelter(pos, radius, factor)` / `clear_shelters()` | 避風體積（只影響 CPU 取樣物件） |
| `set_preset()` / `set_wind(deg, strength)` / `set_override()` | 與 V1 相同 |
| `trigger_gust()` / `set_enabled()` | 與 V1 相同 |
| `debug_reset()` | 重設時間／方向／陣風／RNG 到 seed 初始（可重現測試） |
| `set_frozen()` / `debug_advance(sec)` | 凍結／手動推進風時鐘 |
| `seed_value` | 可重現的隨機種子（預設 20261018） |

## 3. 五類物件

| 類別 | 實作 | 物件 | 行為 |
|---|---|---|---|
| A 柔性固定 | `wind_cloth.gdshader` | 暖簾 50 片 | 上緣釘死、下襬擺動；每片自己取樣（含遮蔽） |
| B 吊掛剛體 | `wind_suspended.gd` | 燈籠 ×3（pilot，真實 mesh） | 擺錘動力學：風壓力矩→角加速度、g/L 回復、阻尼、最大 32°；0.4 s 時 15°、5 s 32.4°（慣性延遲） |
| C 輕量地面物 | `wind_loose.gd`（LEAF） | 落葉 ×14（pilot proxy） | 靜摩擦未突破前只抖動；陣風才滑行／翻滾／短暫離地；邊界 1.0 m |
| D 中重量地面物 | `wind_loose.gd`（BASKET） | 竹籃 ×1（真實 mesh） | 微風 0.000 m、陣風慢慢滑到 0.7 m 上限 |
| E 重／結構 | 無元件 | 石燈籠 ×1（真實 mesh） | 整個測試座標不變（P6 PASS） |

分類是**逐節點 export 參數**（mass／area／μs／μk／damping／max_radius…），
沒掛元件的資產預設完全靜止——不會「看起來像道具就自己動」。

## 4. Pilot（`scenes/wind_pilot.tscn`）

程式生成的灰盒地面＋石牆（避風口袋），加上村裡真實的 mesh：3 棵樹、暖簾、
3 個吊燈籠、竹籃、石燈籠；落葉是明示的 proxy（`PILOT_leaf_*` 菱形薄片，專案沒有單片落葉資產）。

```
Godot_v4.7.2-stable_win64_console.exe --path godot res://scenes/wind_pilot.tscn
# 或 -- --wind=gust / --pilot-vectors（風向量視覺化）
```

HUD：preset／base 方向／本地取樣方向・強度・m/s。
`1–4` preset、`G` 陣風、`0` 開關、`V` 風向量、`F9` 風面板。

## 5. 實測

### 5.1 風場與控制器（headless）

`tools/wind/wind_verify.gd`：**37 項 PASS／0 FAIL**（W1–W15）。節錄：

| 項目 | 實測 |
|---|---|
| 180 s 內最大單步轉向 | 0.3°（無 180° 掉頭） |
| 180 s 累積轉向 | 367°（會緩慢繞） |
| 同 seed、同 dt 重跑 | 180 筆取樣逐項相同 |
| 近處（3 m 內）／遠處（100 m）差異 | 0.009 vs 0.019（遠處 2.1×） |
| 陣風前緣 25 m 傳播 | delay 1.6–2.6 s（12.5 m/s 波） |
| 遮蔽體積 | 0.23 vs 開闊 0.93（factor 0.25） |
| GUST→CALM 每幀最大變化 | 0.026（30 fps） |

### 5.2 五類物件（pilot，headless 物理 60 Hz）

`tools/wind/wind_pilot_verify.gd`：**22 項 PASS／0 FAIL**（P1–P7）。

| 類別 | 實測 |
|---|---|
| A 暖簾 | 換 preset 不 snap；BREEZE 起擺、GUST 振幅 3× |
| B 燈籠 | 0.4 s 時 15.0° < 5 s 的 32.4°（慣性延遲）；CALM 衰減到 0° |
| C 落葉 | CALM 0.000 m → GUST 1.0 m（邊界）；最大單幀 0.048 m（無瞬移） |
| D 竹籃 | BREEZE 0.000 m（靜摩擦）→ GUST 0.7 m（慢慢滑、不超過上限） |
| E 石燈籠 | 整個測試座標與 basis 完全不變 |

### 5.3 視覺動量（平均值，相鄰幀像素差 0–255；TAA 關、固定風時鐘）

| 場景／機位 | 風關 | Calm | Breeze | Moderate | Gust |
|---|---|---|---|---|---|
| pilot 全景 | 0.006 | 0.045 | 1.99 | — | 4.83 |
| pilot 燈籠特寫 | 0.012 | 0.045 | 1.81 | — | 5.22 |
| pilot 落葉特寫 | 0.009 | 0.077 | 1.76 | — | 3.90 |
| pilot 暖簾特寫 | 0.004 | 0.021 | 1.05 | — | 2.92 |
| 村莊竹林 | 0.013 | 0.096 | 2.83 | 4.36 | 5.89 |
| 村莊林緣 | 0.018 | 0.54 | 3.75 | 4.56 | 5.41 |
| 獸道草原 | 0.000 | 0.007 | 0.27 | 0.68 | 0.86 |

（村莊草原機位在 GUST 擷取時風向偏離視線，螢幕動量反而比 MODERATE 低；這是空間轉向，
不是強度下降。需要看單一物件的話看 pilot 的數字。）

### 5.4 效能（GTX 1070、1280×720、VSync 關、A/B/A 中位數）

| 場景／機位 | 風關 GPU | 風開 GPU | Δ |
|---|---|---|---|
| village meadow（6.68 M prim） | 10.42 ms | 11.91 ms | **+1.49 ms（+14.3%）** |
| village forest_edge（6.88 M） | 13.47 ms | 14.12 ms | **+0.65 ms（+4.8%）** |
| village bamboo（8.24 M） | 12.56 ms | 13.10 ms | **+0.54 ms（+4.3%）** |
| BP torii | 6.04 ms | 7.76 ms | +1.72 ms |
| BP meadow | 5.31 ms | 7.11 ms | +1.82 ms |
| BP grass | 4.44 ms | 6.28 ms | +1.85 ms |
| pilot 全景（81 k prim） | 1.54 ms | 1.46 ms | −0.08 ms（噪聲內） |

pilot 的 18 個動態元件：physics 約 0.2–0.5 ms／幀（`Performance.TIME_PHYSICS_PROCESS`）。
pilot 的 draw call 124–128，差異來自落葉移動造成的剔除變化，不是新材質。

## 6. 限制

1. 植被 shader **不做逐物件遮蔽**（只有 CPU 道具／角色吃 shelter）；理由：逐頂點遮蔽要多一張
   世界遮罩貼圖，V1 沒有。巷內草仍會和空地一樣晃。
2. 幟／旗（nobori、rb_flag）**尚未接**：它們是「竿＋布」同一個 mesh，旋轉或彎曲整支會連竿一起歪；
   需要拆 mesh 或加骨骼，屬於資產工作，不在本次。
3. 村裡 62 個吊燈籠**尚未全域啟用**，只在 pilot 示範（避免改動已封存場景）。
4. 落葉是 proxy；真正的落葉資產不存在。
5. 鬆動物的位移是 visual-only：不寫存檔、不影響碰撞與導航；場景重載回到作者擺位。
6. `veg_kit`／`bamboo_kit` manifest 的 shader sha256 仍與修改後的 shader 不符（等使用者裁定重封存）。
