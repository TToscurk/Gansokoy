# Wind V2：水面、浮物與生物二次運動（WIND_V2_REVIEW）

依 `docs/風力系統.md`。所有系統吃同一個 `Wind` autoload 的風場（沒有第二個控制器）。
技術驗證通過 ≠ 視覺通過；視覺由使用者裁定。

## Phase E：河面＋浮物

| 項目 | 實作 |
|---|---|
| 盤點 | 主河 `Water/MainRiver`（village_v2）＝P2 灰模 StandardMaterial：透明、頂點色（水深烘色）、雙面、roughness 0.15、無 UV、無動畫（生成器註記「正式水體 shader 在 P13」，一直沒做）。其他 6 支水 shader（獸道、田、庭園池、落水）不動 |
| 重用 | 不新開河水 shader：在既有 `assets/shaders/water.gdshader` 加「人里主河模式」（`vc_albedo`／`wind_coupled`，預設 0 → 獸道／slice 材質外觀不變） |
| 水面場 | `assets/shaders/water_field.gdshaderinc` ＝ CPU `scripts/water/water_field.gd`（逐項同式）：①流場（河道中心線 layout_v2.json，上游→下游、中央 0.55 m/s、近岸慢，1 m 世界貼圖 gw_flow）②長波 2 cm（λ 11／7 m、相位世界雜訊、風大 ×1.6）③風漣漪（λ 0.9／1.8／3.1 m 扇開、強度＝當地風力含行進陣風、風斑、被水流帶走；遠處轉粗糙度） |
| 接線 | Wind 在節點進場時換材質（原材質存 meta `wind_orig_material`），不改 mesh／不改場景；流場快取 user://wind_flow_cache；`WIND_NO_RIVER=1` 可關 |
| API | `Wind.sample_water_height／sample_water_normal／sample_water_flow／sample_water_mask(pos)` |
| 浮物 | `scripts/water/floatable.gd`（Floatable）：浮力（隱式積分）、水流／風拖曳（面積、Cd）、俯仰橫搖貼水面法線、偏航慣性（剪切＋風力矩）、繫留、離水減速推回、臨時物淡出回收（重生點不在畫面內才重生）、`visual_node` 只動視覺子節點 |
| 實地 | `maps/village_v2/water/wind_river_demo.tscn`（掛在 village_v2 根）：落葉 proxy ×8、酒樽 gd_taru（真實資產）×2、小舟 BoatLanding/Boat/Hull 繫留 0.35 m |

`tools/wind/water_verify.gd`（headless）：**19 PASS／0 FAIL**——流向下游 0.54 m/s、岸邊 0.19、岸上 0；逆流強風流速不變；
calm 水面 std 7.3 mm、強陣風 18.4 mm；漣漪斜率 calm→gust ×18.6；浮物貼水面最大誤差 44 mm（重物慣性）、不落水 0；
可見時最大單步 0.03 m；偏航 std 落葉 0.064 vs 酒樽 0.004 rad/s；加速響應 落葉 0.02 s vs 酒樽 1.05 s；小舟離錨點 ≤ 0.39 m（繩 0.35）；回收淡出每幀 ≤ 0.022。

已知視覺問題（REVIEW）：近景水面仍讀得出方塊感／平行條紋（專案沒有水用法線貼圖；目前用程序雜訊＋三道漣漪）；落葉 proxy 18 cm 在 7 m 外只有幾個像素。

## Phase F：生物二次運動

| 項目 | 實作 |
|---|---|
| 元件 | `scripts/wind/secondary_motion.gd`（WindSecondaryMotion，SkeletonModifier3D 子類）——動畫之後、非破壞式（Godot 4.7 修改器結果每幀還原，不累積） |
| 設定 | `SecondaryMotionProfile`＋`SecondaryChain`（root／tip、stiffness、damping、wind_influence、inertia、max_angle、gravity、min_tier）；狼 = `data/wind/secondary/wolf.tres`（尾 5 節＋鬃毛 6 條＋頸毛） |
| 模型 | 每骨小角度彈簧；驅動＝相對空氣（Wind.sample_wind − 身體速度）＋身體加速度（含轉向向心）＋下垂；根→梢權重遞增、末端角度上限 |
| 等級 | -1 自動（主相機 < 12 m 增強、< 35 m 輕量、其餘關）／0 關／1 輕量 30 Hz／2 增強每幀＋子步 |
| 安全 | 骨名只是線索：root→tip 必須是父子鏈、骨長 > 0，否則該鏈停用並警告一次；不改匯入、權重、AnimationTree |
| 試驗 | `scenes/secondary_motion_pilot.tscn`：狼 glb 實例（不動 enemy_wolf／戰鬥檔，緣一骨架由其他 session 持有，未動） |

`tools/wind/secondary_verify.gd`（雙胞胎比對，headless）：**13 PASS／0 FAIL**——8 條鏈驗證通過；無風 5 s 漂移 0.0000 m；
+X 側風尾尖 +0.063 m、鬃毛 0.022 m；非鏈骨與純動畫差 0；風停 3 s 回到 0.0087 m；+Z 加速尾尖 −0.108 m；轉彎往外 0.064 m；
Tier 0 差 0；缺骨／非父子鏈 → 安全失效。

## 實地圖整合狀態

- 主河：已整合（材質切換＋流場＋漂流物）。
- 植被：V1.2 已在人里與獸道材質上運作；效能閘門見 Phase C。
- 暖簾：V1.1 已接 50 片；吊燈籠只在 pilot。
- 生物：只有試驗場；正式角色整合需角色 session 交接（見下）。

## 角色整合交接（給角色／戰鬥 session）

1. 在角色 Skeleton3D 下新增 `WindSecondaryMotion` 子節點，`profile` 指向該角色的 `SecondaryMotionProfile`（髮束、袖、羽織下襬鏈）。
2. `body_path` 指向角色根（CharacterBody3D）；`tier` 用 -1。
3. 已有 SpringBoneSimulator3D 的骨鏈不要重複掛（同一根骨不要兩個模擬器）。

## Phase G／H：正式地圖整合（2026-10-19）

| 類別 | 正式整合 | 只有試驗場 | 不接（原因） |
|---|---|---|---|
| 人里植被 | ✓ 樹／竹／草／田（V1.2 執行期接線） | | 庭園竹垣、蹲踞、手桶 → rigid |
| 人里布料 | ✓ 暖簾 50＋竹簾 34（竹簾擺幅 30 %）；release 也接 | | 幟（nobori）、旗：竿與布同一 mesh |
| 人里吊燈籠 | ✓ 單顆簷下／竿燈籠 14 顆（LOD0／1 共 28 個鉸鏈，吊點＝mesh 頂、靜止＝原擺位、無碰撞） | | 繩串燈籠（ms_tsuna_chochin、mk_chochin_line）：一個 mesh 多顆 |
| 招牌 kanban | | | 固定在建築上（STATIC） |
| 地面鬆動物 | | ✓ pilot 落葉／竹籃 | 沒有正式落葉／輕物資產 |
| 主河 | ✓ 水面場＋碼頭小舟繫留 | ✓ 落葉 proxy／酒樽（`spawn_debris()`、`--wind-river-debris`） | |
| 獸道植被 | ✓ 樹 11122＋葉 1191＋草 3385 節點 | | 溪流維持原材質 |
| 生物 | ✓ 正式 enemy_wolf（骨架簽名自動接，身體＝CharacterBody3D） | ✓ 狼試驗場 | 緣一：骨架由角色 session 持有（簽名不符、不會被接） |

行為規則：暫停＝風時鐘停（植被、水、布一起停）；換圖與讀檔不重置風（決定性風場，不寫存檔）；
浮物／燈籠擺動不寫存檔，重載回作者擺位；測試漂流物正式遊玩不生成。

`tools/wind/wind_world_verify.gd`（main.tscn 真換圖）：**22 PASS／0 FAIL**——人里／回人里接線、燈籠靜止誤差 0.00000、
強陣風擺角 4.6°–11.9°（不同步）、獸道物種分佈、離開主河水面場清空、Wind 只有 1 個、風時鐘換圖連續、無重複鉸鏈、
存讀檔、暫停停表、enemy_wolf 自動接 8 鏈、緣一不接。

效能（GTX 1070、1280×720、同機位風開／關 A/B，**本輪兩次 off 差 < 0.1 ms ＝可信**）：

| 機位 | 風造成的 GPU | CPU |
|---|---|---|
| 人里市街（燈籠／暖簾） | +0.03～0.29 ms | 不變 |
| 主河 | +0.02～0.22 ms | 不變 |
| 生物試驗場 | ±0.1 ms | 不變 |
| 人里草原 meadow_a | **+2.7～3.1 ms**（V1.1：+1.36） | 不變 |
| 獸道 bp_torii | **+4.2～4.9 ms**（V1.1：+1.72） | 不變 |

獸道拆解：樹冠彈簧 ~0.3 ms、行進陣風 ~1.0 ms、其餘基本變形（高度加權＋自然擺動＋剖面）~3.2 ms。
**效能閘門：植被密集機位 FAIL**（其他機位 PASS）。進一步壓低需要縮短風作用距離（犧牲遠景）或改架構（每幀把風場烘成相機周圍世界貼圖）。

## 效能最終優化：共用 GPU 風場貼圖（WIND_V2_PERF_REVIEW，2026-10-19）

**架構**：逐根部的場量（風向偏移 aoff、強度倍率 m、各物種主幹／樹冠驅動力含行進陣風與樹冠彈簧、草浪 warp／gmod）
每幀由 Wind 的 SubViewport（`wind_field_gen.gdshader`，RGBA16F、10 方塊×128²、相機中心 ±128 m、貼齊格點）在 GPU 上算一次，
寫進 `gw_field`；植被頂點每頂點只取樣 1 次。生成器與 CPU 用同一套公式 → `tools/wind/wind_field_verify.gd`（非 headless）：
風向誤差 0.024°、m 0.0013、陣風中驅動力 p95 誤差 0.008（最大 1.9）、y 方向正確、範圍外夾邊、關風停止重算 —— 7/7 PASS。
草／秧苗物種參數改走 global uniform（`gw_spg／gw_spp／gw_spm`）。

**距離品質分級**：樹 近 <35 m 全部；35–50 m 葉片顫動漸弱；50–65 m 混合到遠景路徑（主幹高度加權＋樹冠彈性＋枝叢傾倒，
無逐頂點 sin）；100→130 m 漸弱（V2 之前 45→60 m 就整段靜止）；陰影 pass 50 m 外不加風。
草 <10 m 全部；14–34 m 主草浪＋陣風（省第 2 短波與細顫）；10–14 m 混合；陰影用中級式。

**順手修掉的既有 bug**：① 竹子材質 wind_speed 1.35 被乘進陣風時間軸 → 幾秒後就吃不到行進陣風（現在場時間一律 gw_time）。
② meadow_grass 隱藏的叢（f＝0）被風位移拉開成細條。③ `wind_perf` 關風基準被未淡出的陣風汙染（Δ 被低估）。

**瓶頸（`--gpu-profile` 逐 pass，獸道 bp_torii）**：風成本 ~90 % 在 Opaque Pass 頂點階段（Depth Pre-Pass 只 +0.3–0.6 ms）；
草約 2 ms、樹約 1.4 ms。場公式搬進貼圖後，剩下的主要是龐大草／樹頂點數 × 留存的逐頂點運算與暫存器壓力
（風關閉時光是代碼存在就付 ~0.7 ms）。

**效能（GTX 1070、1280×720；`--gpu-profile` 固定機位、各狀態取 min；第 2 輪被使用者收尾中止，只有第 1 輪完整）**：

| 機位 | V2 8f997cd 風造成 GPU | 本版 | 開風總幀 GPU（舊→新） |
|---|---|---|---|
| 獸道 bp_torii | +4.72 ms | +3.34 ms | 13.12 → 11.93 |
| 獸道 bp_forest | +4.26 | +3.36 | 11.63 → 10.90 |
| 人里草原 meadow_a | +2.87 | +1.83 | 13.87 → 12.85 |
| 人里林緣 forest_edge | +2.79 | +3.13 | 17.31 → 17.45（60–130 m 樹改成會動） |
| 竹林 bamboo_grove | +3.03 | +2.80 | 16.85 → 16.76 |

交錯 A/B（wind_perf，min）同向：bp_torii 4.25→3.45、meadow_a 2.63→1.83、forest_edge 1.78→2.26。CPU 不變。
**目標 1.5–2.0 ms：人里草原達成；獸道未達成（最佳 ~3.3 ms）**。再降的代價：拿掉近景草細顫／第 2 波 −0.5 ms（近景變單調，未採用）。

**視覺 A/B**（同風時鐘、同鏡位 6 個：近草、密林、長鏡、林緣、竹林、遠景；`perf/perf_ab_sheet.jpg`、`perf/*_ab.mp4`）：
一般渲染無缺幾何／脫根／陰影破綻；近景位移熱圖差 3–5 mm（獸道）、相關 0.88–0.98；中距離陣風動量 −5～−11 %（設計中的細節降級）；
遠景樹由靜止改為會動；竹林恢復段 +19 %（竹子終於吃到陣風）。

驗證：wind_verify 72／0、wind_pilot_verify 22／0、water_verify 19／0、secondary_verify 13／0、wind_world_verify 22／0、wind_field_verify 7／0。
