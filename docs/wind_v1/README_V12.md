# Wind V1.2 附錄：高度加權植被動態（WIND_V1_REVIEW）

狀態：**WIND_V1_REVIEW**。視覺與手感由使用者裁定；agent 不宣告完成。
沿用 V1.1 同一個 `Wind` autoload 與同一個空間風場——沒有新增風控制器。

## 1. 改了什麼

| 規格項 | 實作 | 位置 |
|---|---|---|
| 1 高度加權彎曲 | `bw = pow(hn, tip_response)`（預設 2.2）；`hn`＝mesh **局部** Y ÷（頂高−樞軸），頂高／樞軸由 mesh AABB 在接線時寫進 `wind_sp`；不用世界 Y。草用作者烘的 `UV.y`（葉根 0→葉尖 1）。位移以實例縮放換算（轉置 3×3 ÷ scale²），長度保持（樹梢隨彎曲略降） | `veg_common.gdshaderinc` `veg_wind()` |
| 2 分層二次運動 | ①主幹：驅動力延遲 0.25·lag；②樹冠：欠阻尼彈簧（damping、固有頻率 1.6·sway_hz、lag），只作用在 hn 上段 × 作者遮罩 UV2.x；③葉片顫動 flutter_hz × 樹冠高度亂流。彈簧＝6 點脈衝響應（含負權重＝過衝），穩定風 DC 增益 1；front 波用解析增益／相位，行進陣風用 CPU 預算的響應表 `gw_resp` | `wind_field.gdshaderinc` `wf_drive()`、`wind_species.gd` |
| 3 垂直風變化 | 強度 × `clamp((z/0.6)^0.16, 0.55, 1.9)`（z＝離地高；12 m 樹冠 ×1.61）× 海拔 `1 + 0.02·(根部 y − ref)`；與水平空間場**相乘**。遮蔽體積（牆／建築／山丘）植被 shader 也吃（離焦點最近 8 個），遮蔽頂高以上 2 m 漸回開闊 | `wf_height_factor`／`wf_elev_factor`／`wf_shelter`、`Wind.add_shelter(pos, r, factor, top_y)` |
| 4 物種參數 | 9 種：broad_tall／broad_small／conifer／weeping／bamboo／bush／grass／paddy／rigid；每種 stiffness、bend_mult、tip_response、response_lag、damping、flutter_hz、max_deform_m、crown_gain、sway_hz。mesh 名稱前綴→物種；**沒對到的一律 rigid**（庭園竹垣／蹲踞／手桶也用 veg_bark，不能彎） | `res://data/wind/wind_species.tres`、`WindSpeciesProfile.MESH_PREFIX` |
| 5 行進陣風 | 陣風＝事件：焦點上風 20 m 生成、9 m/s 推進、半寬 30–46 m、前緣沿橫向微彎、強度沿橫向起伏；自動陣風依 preset 節奏（間隔／振幅／長度隨機、可重現）。不是每幀亂數方向 | `Wind._spawn_event`、`wf_drive` |
| 6 剔除邊界 | 接線時 `extra_cull_margin ≥ max_deform × 1.3 + 0.1 m`（主畫面與陰影共用） | `Wind._wire_veg` |

不動：mesh、.tscn、`godot/assets/blender/sources/`、角色動畫、村莊建築。接線全在執行期（`node_added`）。

## 2. 調參

- 物種：`res://data/wind/wind_species.tres`（每種一組 `@export_range` 滑桿），執行中 `Wind.set_species_param("bamboo", "stiffness", 0.3)` 即時生效。缺的物種由 `tools/wind/wind_species_init.gd` 補（不覆寫已調值）。
- 垂直剖面：`Wind.set_vertical_profile(alpha, z0, elev_ref, elev_gain)`。
- 除錯：F9 面板 → `H` 位移熱圖（灰階 emission，0.6 m＝白）。

## 3. 實測（GPU 熱圖＝實際頂點位移，非 CPU 推算）

Pilot（`scenes/wind_pilot.tscn`；高木 keyaki 18.4 m、小樹 momiji 6.4 m、草叢含 5 m 土丘頂與牆後）：

| 項目 | 結果 |
|---|---|
| 根部（樹高 0–10 %）位移 | 高木 0.0005 m、小樹 0.000 m（不脫根） |
| Strong Gust 中段→樹梢 | 高木 0.155 → 0.294 m；小樹 0.099 → 0.174 m（高木絕對位移較大） |
| calm／breeze／gust 高木樹梢 | 0.016／0.187／0.294 m |
| 行進陣風抵達（草叢 x=−11…+11 m） | 1.3／1.9／2.5／3.1／3.7 s（22 m／2.4 s ≈ 9.2 m/s） |
| 小樹（x=−6）→ 高木（x=+7.5）樹冠峰值 | 3.3 s → 5.6 s |
| 高木主幹 vs 樹冠 | 峰值 4.4 s vs 5.6 s；降到一半 5.6 s vs 6.2 s（樹冠延遲回正） |
| 同像素 A/B：土丘頂（+5 m）海拔增益 | ×1.061（模型 ×1.10，草尖軟夾使像素平均略小） |
| 同像素 A/B：牆後遮蔽 | ×0.40；地面／開闊處 ×1.000（未受影響） |
| 最大位移 | 0.31 m（樹冠半徑 ~7 m；物種上限 0.8 m 未觸及） |

controller／接線（`tools/wind/wind_verify.gd`，headless）：**60 PASS／0 FAIL**，含 W16–W21：
陣風每 15 m 晚 1.70 s、橫向 60 m 外 0、樹冠彈簧權重和 1.0000 且含過衝、主幹回落一半時樹冠仍高、10 s 後收斂、
village_v2 29 439 個樹／竹節點全部有 `wind_sp`、剔除邊界不足 0、庭園構件全歸 rigid。
props（`wind_pilot_verify.gd`）：22 PASS／0 FAIL。

## 4. 效能（GTX 1070、1280×720、同一 session A/B/A，風開 − 風關 GPU）

| 機位 | V1.1 shader | V1.2 |
|---|---|---|
| village meadow_a | +1.36 ms | +2.65～+2.88 ms |
| village forest_edge | +0.61～+0.69 ms | +1.70～+2.54 ms |
| village bamboo_grove | +0.64～+0.67 ms | +1.90～+2.72 ms |

V1.2 比 V1.1 多 **約 +1.0～1.6 ms**；數字隨當下有幾道陣風前緣掃過畫面而變（陣風中段最貴）。
已做：樹冠彈簧改解析／查表（原本每頂點重算 7 次驅動力，+3.5～8.5 ms → 現值）、事件早退、關風時清空事件。
village_v2 載入多 ~0.38 s（13.8 萬植被節點接線，已做 per-mesh 快取）。

## 5. 限制

1. 陰影：陰影 pass 跑同一個 vertex shader（同一距離量測主相機）→ 與主畫面同步；只做了單張目視確認，沒有逐像素比對。
2. 樹冠互穿：只以位移上限控制（實測最大 0.31 m），沒有做樹與樹的碰撞。
3. 草不吃垂直剖面（草叢高度＝剖面正規化高度 z0，×1）；草也沒有樹冠層（單點驅動＋lag）。
4. Beast path／landscape 的 Tripo 樹（r7）沒有風 shader，不在本次範圍。
5. 效能比 V1.1 貴；若要壓回 V1.1 水準，下一步是把風場（含陣風／樹冠響應）每幀烘成相機周圍的世界座標貼圖，頂點只讀一次。
