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
