# 河道同步簡報 → GPT 沙盒（2026-08-26）

給下一輪河道幾何重建的完整交接。現行候選：`maps/slice/slice.tscn` 的
`RiverV3_Candidate`（open-U v6 幾何＋Claude 的 v7/v8 材質修補）。

## 一、已確診的 v6 幾何缺陷（重建必修）

1. **面片繞向系統性反轉**。`OuterTerrainTransition`、Inner/Outer Dry/WetBank
   均含背面朝上的面片。Godot 剔除背面 → 單面材質下整片隱形、露出霧色天空
   （使用者看到的「兩側白」「蒼白大場」全是這個）。目前靠把材質設
   `cull_mode = disabled`（雙面）治標。**重建時繞向必須正時針**（front face
   = clockwise，見 `.claude/rules/godot.md`），之後材質改回單面。
2. **多張面片出廠沒掛任何材質**（渲染純白）：`VillageLandExtension`、
   `EastTailLandConnection`、`WestTailLandConnection`、`OuterTerrainTransition`。
   已補掛（見下），但重建輸出時每張面片必須自帶材質。
3. **U 形兩端沒有收尾**：河道到尾端直接截斷，端面裸露。需自然收束
   （漸窄入地形或接遠景水面）。
4. 地形過渡皮要收在護岸頂緣，不得垂進河道側。

## 二、已驗證無罪

- `RiverWater` 水面**只覆蓋河道內**（探針實測），沒有超出。
- 剖面深度合格：地面 0 → 水面 −4.15 → 河床 −8.85，護城河落差已有 4m+。

## 三、已備好的材質（重建的 mesh 直接掛）

| 檔案 | 用途 | 備註 |
|---|---|---|
| `assets/materials/river_ishigaki_dry.tres` | 乾壁石垣（護岸主牆） | stone_wall 三向貼圖、深灰、uv 0.4 |
| `assets/materials/river_ishigaki_wet.tres` | 水線濕壁帶 | 同貼圖更深色 |
| `assets/materials/river_transition_grass.tres` | 外側草坡 | terrain_grass、霧面 |
| （現有）`RiverV5_UnifiedVillageEarth` | 村台側泥土 | 場景內嵌 |

目前三個新材質都是 `cull_mode = disabled`——**繞向修正後請改回單面**。

## 四、使用者 Art Card（不變的驗收標準）

- 深河道、護城河感（落差與份量）。
- 石頭紋理護岸（石垣，不是素面斜坡）。
- 護岸旁植被與樹——**樹由使用者用 Meshy 生成**，不要用專案現有 tree_* 資產。
- 橋只是佔位，不引用；正式橋使用者用 Meshy 做。
- 河道要寬、開放 U 形（環形與窄河已否決）。

## 五、驗證入口（照用，勿另建）

- 幾何探針審計：`godot --headless --path godot --script tools/audit_river_slice.gd`
- 固定鏡位：`tools\capture-godot.cmd -Map slice -Shotlist godot\tools\shots\village_ring_river_prototype.json -OutputDirectory shots2\<批次名>`
  （detail 鏡組：`village_ring_river_detail.json`）
- 對照基準（BEFORE）：`shots2/river_open_u_v8b_banks_20260826`、
  `shots2/river_open_u_v8b_banks_detail_20260826`
- 完成後停在 ART_REVIEW，等使用者看圖批准才進 village.tscn。

## 六、遺留小項（可與重建一併處理）

- 水線頂緣一條細白邊（石材色在濃霧下偏亮）。
- 50m 距離整體霧白——屬 lighting/cel-shading 階段，不在河道範圍。
