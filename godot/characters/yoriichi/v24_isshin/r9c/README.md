# R9-C／R9-C2：日之呼吸・圓舞 Blender 特效候選（ART_REVIEW）

只改圓舞的特效。圓舞骨骼動畫、命中判定、19 招、派生規則、正式 Player、跑酷與正式場景都沒動。
R9 的程式刀光（`r9/sun_vfx.gd`）保留，可隨時切回。備份：
- R9-C 動工前：`D:/research/sekiro_r8_p0/backups/r9_vfx_pre_r9c_20261021_0221/`
- R9-C2 動工前：`D:/research/sekiro_r8_p0/backups/r9c_pre_r9c2_20261021_1228/`

## 切換
- 試玩場景 `r9/r9_combat_demo.tscn`：按 **C** 依序切換「R9 程式刀光 → A → B → C1 → C2 → C3」，**V** 開關特效。
- 命令列：`--vfx=r9|A|B|C1|C2|C3`；預設值在 `r9/sun_breathing.json` 的 `vfx_variant`。

## R9-C2 新候選（C1 爆發／C2 流焰／C3 神火）
- 資產：`enbu_vfx_C1／C2／C3.glb`，貼圖 `r9c2_body.png`（主體火焰帶）、`r9c2_ring.png`（日輪）。
- 物件：
  - Core：點燃的刀路。C1／C3 在命中前細，命中後變粗。
  - Sheet／Layer0／Layer1：主體火焰帶與上下錯層，增加側面厚度。
  - Fin：垂直於斬擊面的交叉火焰面。
  - Flames：大幅捲出斬擊平面的火舌。
  - Burst（C1）：斬線爆燃。
  - Ring（C3）：日輪，290° 開口、寬度不均、兩端收尖。
  - Embers、BladeFlame（刀身火，越近刀尖越大）。
  - HitFlame／HitRing／HitStar：命中三層，分別是定向火柱、上側開口衝擊弧、白金點燃團塊。
- 命中點燃（C1／C3）：著色器 `ignite_from／ignite_t`。刀在 0.60 s 之前掃過的部分先不燒，只留金色刀線；第一次命中時用實際命中時間一口氣點燃，停格那一格就是點燃格。沒命中則照設計時間 0.60 s 點燃。A／B 沒設這些參數，行為不變。
- 參數：`r9/sun_breathing.json` → `skills.sun_enbu.vfx_variants.C1／C2／C3`。

## R9-C3 動態光照（L1 自然火光／L2 動畫爆發；預設 L1）
- 火焰 mesh：L1、L2 共用同一套，主體是 C2 流焰，再加 C1 的命中爆燃（Burst＋命中三層），沒有新增幾何。設定在 `sun_breathing.json` 的 `mesh: "C2"`、`extra: {"C1": [...]}`。
- 光源：setup 時就建好 5 盞無陰影的 OmniLight3D，全部版本共用，出招時不新建燈光或材質。
  - 刀身火光：跟著刀身。
  - 火焰體光 ×2：落在刀後 0.05／0.13 s 的位置，離地至少 0.9 m；主斬結束後固定在原地。
  - 命中光：Hit Stop 期間白金色，放開後轉橘紅再衰減。
  - 餘燼光：只有 L2。
- 熱浪：L2 實驗，`enbu_haze.gdshader`。依深度判斷，只扭曲背景，人物、刀和木樁不扭曲。
- 同步：場景每幀把 `combat.hitstop_left > 0` 傳給 `mvfx.hitstop`；停格期間刀光、命中白光與火焰脈衝固定在峰值。
- 環境：`--env=dusk` 或在試玩中按 **N**，切換白天／黃昏森林。樹用 `assets/landscape` 的杉樹與針葉樹，只讀取，開場時預先載入。
- 自動檢查：`D:/research/sekiro_r8_p0/combat/r9c3/test/`
  - `check_lights.py`：光源數、節奏、跟刀、停格同步、轉色、熄滅、命中與扣血。
  - `probe_lum.py`：錄影抽格，量地面、木樁、背的亮度變化。

## R9-C（A／B）
- `enbu_vfx_A.glb`／`enbu_vfx_B.glb`：
  - 物件：Core（金黃刀光核心）、Flames（火舌）、Embers（殘焰碎片）、BladeFlame（刀身火）、HitFlame（命中火）。
  - Flames 和 Embers 帶 shape key `drift`，控制消散時的上捲與飛散。
- 貼圖：`r9c_tongue.png`／`r9c_core.png`／`r9c_ember.png`，在 Blender 內繪製，通道分別是熱度、外緣、撕裂紋、輪廓。

## 共用
- `enbu_flame.gdshader`／`enbu_core.gdshader`：依「技能時間 − 刀經過的時間」計算出現、長出、撕裂、熄滅；Hit Stop 時技能時間不前進。R9-C2 另加 `tear_heat`、`ignite_flash`、`ignite_*`，預設值不影響 A／B。
- `sun_vfx_mesh.gd`：播放模組。負責掛載、主斬結束後凍結到世界座標、drift 權重、刀身火、命中組（3 份輪流用）、命中閃光（OmniLight3D，只有 C 系列有設）與火星。

## 來源
- R9-C2 Blender 原檔（可編輯，含 A／B／C1／C2／C3 與青色刀尖路徑 BladePath）：`D:/research/sekiro_r8_p0/combat/r9c2/enbu_vfx_hero.blend`
- R9-C2 產生腳本（經 Blender MCP 在開著的 Blender 內執行）：`D:/research/sekiro_r8_p0/notes/r9c2/build_hero.py`，沿用 `notes/r9c/build_enbu_vfx.py` 的實際刀路（`combat/r9c/blade_240.json`，角色本地座標，240 Hz）。
- R9-C 原檔：`D:/research/sekiro_r8_p0/combat/r9c/enbu_vfx_candidates.blend`
- 預覽算圖：`notes/r9c2/render_preview.py`（Eevee）。審圖總表：`notes/r9c2/sheet.sh`。
