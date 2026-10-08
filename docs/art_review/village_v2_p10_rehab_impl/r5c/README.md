# P10 R5c — World Edge Closure（ART_REVIEW・未核准）

使用者 2026-10-09 D2：**Boundary APPROVED**——frame 外 Vista＋內側林帶做自然視覺收邊；P1 主地形與既有碰撞不動；實際掉落與視覺裁切分開驗證。

## 根因
- 村 frame＝x 0–560、z −340–220。P1 地形在 frame 邊直接結束，外面是天空：東緣（田區）、北／南水系出口、西稜線看得到「世界被切掉」。
- 掉落：MASTER AUDIT 實測 0（碰撞 1 m 格全覆蓋、15 點實機跑跳、BFS 出口 0）；問題是**視覺裁切**，不是物理掉落。

## 做法（overlay，不改封存、不改 P1）
- `tools/village_v2_edge_closure_lib.gd` → `maps/village_v2/gen/edge_closure_p10.scn` → root `EdgeClosureP10`（HumanUseExpansionP10 之後）。
- **VistaTerrain**：frame 外 0–700 m 放射狀格（近 2 m、遠 ≤ 37 m）；frame 邊頂點逐點取 P1 邊緣頂點高度（接縫 ≤ 0.01 m），向外延續坡度後交給四側地形語彙（北／西＝山、東＝丘陵、南＝低丘），300–660 m 起稜線閉合視線。地面權重從 P1 邊緣權重 14 m 內漸變到遠景權重。
- **VistaWater**：主河（東出口、北出口）、南水渠、西溪往外延續，水位單調（流出方向不升）、接口＝P2 水位、在 frame 外匯入「南の川」再接 RiverEast（不留斷頭）。岸線寬度加雜訊（不規則岸）。
- **近帶實樹**（4.5–176 m，2312 棵，沿用 P9 veg_kit LOD 鏈／MultiMesh；110 m 外逐漸變疏，避開水面與陡坡）＋**遠山林冠面**（108 m 起升起、8 m 均勻格、叢塊暗色雜訊、貼實際地形網格）。
- 不加任何碰撞（CollisionObject3D 0）；Collision/Boundary 4 道牆原樣。

## 驗證
| 項目 | 結果 |
|---|---|
| plan gate（headless） | 0 失敗：接縫、vista 頂點 frame 內 0、**視線閉合射線 25852 條看見世界盡頭 0**、水系不合理 0、樹違規 0、地形 122,952 三角 ≤ 140k |
| 反向 | 4/4（山脊壓低→視線 FAIL、接縫 +0.3 m→FAIL、河心種樹→FAIL、RiverEast 往外升高→FAIL） |
| scene gate（非 headless） | 掛載 1 個／順序／碰撞 0／Boundary 4 牆不變／frame 內頂點 0／MultiMesh 1646 節點 9248 instance 零矩陣 0 |
| 實機邊界（掛 overlay 後重跑） | `after_runtime_boundary_portals.json`：15 測點跑＋連跳全 PASS（不越 frame、無 y < −10） |
| BFS 出口掃描 | `after_mapedge_village_v2.json`：可達格 74,691、**VOID_EXIT 0** |
| 封存 | HUX／HUSE／OUTER／CORE／POP／ACT／STR／MW／MKT／FARM／P9F／NPCLIB／ENV／MDW／GC `--seal` 15 項 0 失敗（掛載後） |
| 效能（`../perf/perf_r5c_edge_toggle.json`，同機位 ON/OFF ABAB 中位數） | 村內 +0.3～+1.0 ms GPU；東緣 +2.4～+3.2 ms；朝外稜線 +4.5～+5.6 ms（原本外面是空的所以便宜；ON 後絕對值 9.8～11.0 ms 仍低於村中心 12～13 ms 機位） |

## 審圖（`*_b.png`＝overlay OFF＝BEFORE、`*_a.png`＝AFTER，同機位、10:00、Forward+）
- TPS：`r5c_e_edge_farm_tps`、`r5c_e_farmpath4_tps`、`r5c_e_river_exit_tps`、`r5c_n_river_exit_tps`、`r5c_n_ridge_out_tps`、`r5c_w_ridge_out_tps`、`r5c_s_canal_exit_tps`、`r5c_s_entry_road_south`、`r5c_hill_shrine_out`、`r5c_arrival_n`、`r5c_e_crosssouth_axis`
- 高視角：`r5c_e_edge_high`、`r5c_s_canal_exit_high`、`r5c_village_high_e`、`r5c_village_high_s`
- Agent 自評（vision，**不是 ART 判定**）：東緣 TPS 4/5、北稜 TPS 4/5、南水渠出口 TPS 4/5。

## 已知殘留（non-blocking 候選，待使用者判斷）
- 遠山林冠在部分角度偏平滑、林相變化少；中景樹的間距略規則。
- 南水渠出口：P7 岸石稜角重複、近景水面紋理偏密（P7 封存內容，不在本 Pilot 範圍）。
- **傳送落點 fallback (0,40,0)**：仍在 `main.gd`（D1 HOLD，其他 session 未提交 +376 行），本輪不動。
