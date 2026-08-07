# 町家 Production Kit —— Repo Audit + PHASE 1

**狀態**：PHASE 1（`machiya_f_a` prototype）完成，等人工審核。
Phase 2 **未動工**。

---

## 1. Repo current-state audit

掃過 `godot/assets/blender/`、`godot/assets/models/`、`godot/tools/`、
`godot/maps/village/`、`godot/data/`。以下是分類，**不是**看 README 猜的，
是逐檔讀出來的。

### Legacy — 保留運作，Phase 1 不動

| 項目 | 為什麼是 Legacy |
|---|---|
| `machiya_f_b` / `b_a` / `b_b` / `e_a` 四個 blockout 模組 | 白盒子 + 外貼木條，單一頂點色。技術上正常運作，但不符合新的 production art standard |
| 169 棟町家的**佈局**（`_block()` 的 frontage 明表） | 佈局本身是好的，Phase 3 才處理 spacing / rotation / alley |
| 六座地標（足洗邸／鈴奈庵／寺子屋／鎮守之杜／市場／稗田邸） | 稗田邸完整版庭院已搬遷完成；本體是否照新標準重建留到 Phase 1-2 驗證後另議 |
| 三座地標塔（火見櫓／鐘楼／水車櫓） | 同上 |
| `make_town.py` 的 `machiya()` / `gable_roof()` blockout builder | 還在供上面四個模組使用，不刪 |
| 前一輪的 cel-shading / outline 方案 | **superseded 但不刪**。`assets/shaders/` 下的東西一個都沒動 |

### Reusable — 直接延用進新系統

| 項目 | 為什麼可以留 |
|---|---|
| `Blender → GLB → town_modules.json → gen_town.gd → MultiMesh → village.tscn` | 這條線本身是對的。Phase 1 只換了「Blender 那一端產出什麼」，管線一個環節都沒重寫 |
| `make_town.py` 的 `B` 累加器與 `box()/quad()` **繞序慣例** | 169 棟町家驗證過。新的 `MB` 逐字沿用，只把「逐面頂點色」換成「逐面材質索引」 |
| `_bbox()` / `_gbox()` / manifest 寫出 | 模組包絡從**實際頂點**量、不是從參數推 —— 這是 OBB 自檢的基礎，照留 |
| `gen_town.gd` 的街區／保留區／OBB 重疊自檢／密度層錨點（`facade`） | Phase 1 的新模組照樣餵得進去（`facade` 欄位照舊輸出） |
| `gen_lib.gd` 的 `pbr()` 材質庫與貼圖組 | 語意材質直接接上它，不用另建一套 |
| 四道靜態閘門 + 稗田邸兩支專用檢查 | 換模組之後照跑，全過 |

### Must Replace — 屬於舊建築模組本體，未來由新 Kit 取代

| 項目 | 問題 |
|---|---|
| `machiya()` 的「白盒子 + 外貼木條」立面 | 柱與牆沒有結構關係。規格 §2.1 明列要換掉的就是這個 |
| `gable_roof()` 的屋頂 | 只有斜面 + 厚度 + 簷底 + 一根棟條。沒有垂木、鼻隠し、破風板、懸魚、瓦 |
| 腰簷（`bld.box(0, -0.28, ko_z, W+0.7, 0.95, 0.10, ...)`） | 這正是規格 §7 禁止的 `horizontal cube sticking from wall` |
| **`gen_lib.prop_mesh()` 用在建築上** | 它把 mesh 的每一個 surface 覆蓋成同一份材質 —— 材質身分在管線中間就死了。對頂點色資產（岩石／樹／鴨）是對的，對 production 建築是災難 |
| 整棟一個 `COLOR_0` | 沒有語意材質就沒有 PBR、沒有 per-material polish |

---

## 2. PHASE 1 做了什麼

新檔 `godot/assets/blender/make_machiya.py`，產 `machiya_f_a`。
`make_town.py` 的模組迴圈對 `PROTO = {"machiya_f_a"}` 改呼叫它 ——
**manifest 仍由 `make_town.py` 統一寫出**（一份 manifest 一個寫入者，
兩邊各寫一份遲早對不上）。

### 真壁造：軸組先立，漆喰填進去

```
土台 150×150 → 柱 150×150（四角通し柱 + 正背面管柱 + 側面管柱）
            → 貫 105×30（兩道，兩面各凸 30mm）
            → 内法長押 130×30
            → 桁 180×180（頂面齊屋面起點）
```

漆喰是**逐格嵌板**、比柱面**內縮 25mm**。那 25mm 的落差就是真壁造在遠景
唯一讀得出來的東西 —— 牆不再是一個連續量體，柱是真的比牆凸出來，
陰影線是**幾何**不是貼圖。

### 立面（四開間，刻意不對稱）

```
bay0 出格子（凸 0.34m 的盒子：底板＋持ち送り＋兩側板＋障子背板＋直櫺＋上枠）
bay1 連子格子（腰板＋障子＋直櫺＋上下框）
bay2 大戶口（兩片板戶＋橫桟＋敷居）＋ 庇
bay3 連子格子
```

### 庇：完整構件

腕木 → 前桁 → 垂木（看得到的椽）→ 野地（含厚度）→ 鼻隠し → 軒裏（仰視面，
木色不是瓦色）→ 丸瓦。出簷 0.95m、坡度 17°。

### 屋頂：一組構件

野地（厚 0.16）→ 鼻隠し → 軒裏 → 垂木（出簷段，18 根）→ 丸瓦（本瓦葺きの
縱向半圓，每側 26 條）→ 軒瓦（簷端巴瓦）→ 妻壁（**漆喰**）→ 破風板 →
懸魚 → 棟（熨斗瓦 + 冠瓦）。

---

## 3. 三個在製作中實際炸出來、修掉的問題

1. **總高 4.78 ≠ 規格 4.50。**
   舊版的棟只有一根 0.14 的方條，新版是熨斗＋冠瓦兩層 0.26。屋身反推公式
   扣的還是 0.14，差的 0.28 全部往上長。天際線的階梯是使用者定案過的，
   prototype 不許順手改掉 → **屋身讓棟**，內法高同時收到 1.72。

2. **桁戳穿屋面。**
   第一版把桁擺成「坐在 z_wall 上往上長」，而屋面在牆線的高度就是 z_wall
   —— 桁往上凸 0.18 直接穿出屋頂，正是規格明列的禁項
   `roof intersecting wall`。改成**桁頂面齊 z_wall**。
   同一個理由拿掉了小屋梁：它架在兩道桁之間、擺在那個高度一定穿出屋面，
   而平入切妻的妻側看到的是妻壁與破風板，梁端本來就被遮住。

3. **Godot 的 glTF 匯入快取不會自己更新。**
   換成六材質的 glb 之後，`semantic_mesh()` 讀回來仍然是 **1 個 surface**
   —— 讀到的是 `.godot/imported/` 裡舊的 `.scn`。要先
   `rm .godot/imported/machiya_f_a.glb-*` 再 `godot --headless --import`。
   **這條要寫進流程**：模組的材質結構改變時，光重跑 Blender 不夠。

---

## 4. 材質身分怎麼活著走完管線

```
Blender 六個材質（WOOD / WOOD_LT / PLASTER / STONE / KAWARA / SHOJI）
  → glTF 匯出：一材質一 primitive（實測 Primitives created: 6）
  → Godot 匯入：Mesh 6 surfaces，材質名帶著
  → gen_lib.semantic_mesh()：逐 surface 依**名字前綴**換成專案的 pbr() 材質
  → MultiMesh
```

`gen_town._emit_batches()` 的判斷依據是 **surface 數 > 1**，不是寫死模組名
—— Phase 2 加新模組時不用再改那裡。legacy 的四個單 surface 模組自動走舊路徑。

⚠ 名字比對要**長名優先**（`WOOD_LT` 不能被 `WOOD` 吃掉）。對不上的名字
保留 glb 自己的材質、不亂猜。

---

## 5. Phase 1 驗證結果

| 項目 | 結果 |
|---|---|
| Blender 幾何自檢 | 面 2,478／頂點 7,434／**退化面 0**／鬆散頂點 0 |
| 材質覆蓋 | WOOD 1170・KAWARA 998・PLASTER 142・WOOD_LT 118・SHOJI 30・STONE 20（六種全有面） |
| bbox | 9.56 × 9.60 × **4.50**（總高規格 4.50，準確命中） |
| gbox / manifest | `[-4.78, 4.78, -8.65, 0.95]`，fw 9.56 / fd 9.60 / h 4.50 |
| glTF 匯出 | Primitives created: **6** |
| Godot 匯入 | 6 surfaces，六個語意名全部對上專案材質 |
| village 產生 | 169 棟、OBB 重疊自檢 **0 穿插**、saved err=0 |
| lm_ghost | 通過 |
| check_map | 六張圖 0 問題 |
| walk_test | 22 條全通 |
| hieda_boundary_check | 0 項不符 |

> ⚠ **非流形邊 7,434 不是錯誤**：這個 builder 是三角形湯（每個面自己一組
> 頂點、不共用），flat shading 的必要條件，legacy 的 `B` 也是一樣。
> 拿它當紅燈會誤導，所以驗證報告裡它是**資訊**不是判定。

---

## 6. Known visual risks（人工審核時請特別看這幾點）

1. **屋身只有 2.29m。** 4.50 的總高扣掉 23° 屋頂（1.655）與棟（0.26）之後就
   剩這麼多。真壁造的立面節奏（腰→貫→內法→小壁）被壓得很扁，小壁只有
   0.32m。要更好的比例只有兩條路：放寬總高規格，或收屋頂坡度 —— 兩者都會
   動到使用者定案過的天際線，所以 Phase 1 沒動。
2. **丸瓦（本瓦葺き）是強烈的選擇。** 它比桟瓦貴氣、也更「寺社」。如果人間
   之里的一般町家應該是**桟瓦**（民家的常見形），這一輪要改的是屋面那 52 條
   半圓 —— 改起來很快，但要先定案。
3. **出格子只做在 bay0。** 四開間裡只有一格凸出去，正面因此不對稱。這是刻意
   的（町家的店・住・通り庭各佔各的開間），但如果要更整齊的商業立面，
   應該是 bay0+bay1 都出格子。
4. **貼圖比例還沒調。** 語意材質直接接上專案既有的貼圖組（plaster / planks /
   dark_wood / roof_kawara / stone_wall / shoji），uv1_scale 沿用材質庫的預設值
   —— 那組數字是配 blockout 的大面積調的，貼到 0.15m 寬的柱子上會太密或太疏。
   Phase 7（Materials/Polish）的事，但近景審圖看得到。
5. **169 棟裡有多少變成新版**：`machiya_f_a` 這個 kind 的每一棟都換了。
   其餘四種仍是 legacy blockout，所以街上現在是**新舊混排**。這是驗證
   「新模組進得了現有管線」的必要條件，不是最終狀態。

---

## 7. 流程備忘

```bash
# 只重建 prototype（含五張審圖）
blender -b -P godot/assets/blender/make_machiya.py -- \
  godot/assets/models --render godot/art_review/phase1_machiya_f_a

# 全模組庫 + manifest（machiya_f_a 會自動走 prototype builder）
blender -b -P godot/assets/blender/make_town.py -- godot/assets/models

# ⚠ 模組的**材質結構**改變時，Godot 的匯入快取要清掉重來
rm godot/.godot/imported/machiya_f_a.glb-*
godot --headless --path godot --import

godot --headless --path godot --script tools/gen_town.gd
```
