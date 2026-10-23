# 日之呼吸火焰系統（統一版）＋ FIRE_RESEARCH_V2 研究來源（ART_REVIEW）

只做 VFX。圓舞動畫、R10／R11、普通劍術、居合、命中判定、Hit Stop、正式 Player、跑酷、共用骨架都沒動。
原始 R9（`r9/`）、Blender A/B/C 系列（`r9c/`）、V2 研究模組（本資料夾 `fire_v2.gd` 與 `fire_v2_*.gdshader`）原檔都保留，作為來源與回退依據。

## 試玩
`res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_demo.tscn`（預設＝統一版，木樁在正前方 1.4 m）

| 按鍵 | 功能 |
|---|---|
| L／滑鼠右鍵 | 圓舞 |
| B | 統一版 ↔ 原始 R9 程式刀光 |
| R | 回到木樁前 |
| V | 特效開關 |
| N | 白天／黃昏 |

功能檢查：`-- --fire-check=OUT_DIR`。

## 架構：單一入口 `sun_fire.gd`
`setup(actor, sword, cam)` → `begin(skill_key)` → 每幀 `frame(刀的變換, 技能時間, dt, 停格, 刀尖速度)` → `hit(pos, dir, normal, strike)` → `end()`；切換特效用 `clear()`。
每型資料在 `sun_fire_profiles.json`（刀光時間窗與寬度、Blender GLB 與部件、時序、規模、點燃、命中）。新增一型＝加一筆資料，不另寫系統。

| 層 | 來源 | 做法 |
|---|---|---|
| 1 高溫刀光核心 | 原始 R9 `sun_trail_r9.gd`（取樣、幾何、Hit Stop 時鐘原封不動） | 核心 strip 換 `sun_fire_core.gdshader`：刀尖側斷續、粗細會變的象牙白線＋金黃伴線 |
| 2 火焰主體 | Blender R9-C2 `enbu_vfx_C2.glb` 的 Flames／Sheet／Fin／Embers／BladeFlame | `sun_fire_mesh.gdshader`；不取 Core（R9 負責）、Layer0/1（同形重疊）、Ring（霓虹圓環）、Hit*（命中層負責） |
| 3 動態燃燒 | V2 噪聲侵蝕、溫度色、預乘 alpha | R9 火焰 strip 掛 `sun_fire_trail.gdshader`；第二層用同一套噪聲流動／撕裂／冷卻；刀刃熱邊（`fire_v2_blade.gdshader`）＋蓄勢小火舌（每招上限 14） |
| 4 命中爆燃 | V2 | 高溫裂口（偏到接觸點前方與外側）＋5 道定向爆燃＋12 火星；每段判定只觸發一次 |

- 發光：`unshaded` 時 Godot 只輸出 ALBEDO（EMISSION 被忽略），所以 HDR 亮度一律寫進 ALBEDO。舊 R9-C 材質把熱度資料貼圖當 sRGB 解碼，這裡改成線性讀取。沒有新增任何燈光。
- 顏色只由熱度決定（`fire_v2_common.gdshaderinc`），外緣變冷時先變透明；全部 `blend_premul_alpha`，重疊只會更亮，不會疊成棕色。
- 時鐘：技能時間（Blender 層、刀光）、`fx_time`（噪聲）、粒子 `time_scale` 都在 Hit Stop 時停。
- 中斷：`end()` 後，之後才會被刀經過的部分不再點燃（`cut_t`）；已點燃的照壽命燒完，0.25 s 內收掉。
- 首次出招前預熱全部材質（避免編譯卡頓讓判定漏掉命中）。

## 碧羅天：風格化火環（stroke 層，同一個 sun_fire.gd）
試玩：`res://characters/yoriichi/v24_isshin/fire_research_v2/sun_fire_hekira_demo.tscn`（繼承 R11 碧羅天試玩，R11 檔案沒改；開場選碧羅天，木樁 1.6 m）
B＝統一版（風格化火環）↔ R11 原特效；其他鍵同 R11（Z／X 換型；圓舞、烈日紅鏡照 R11 原特效）。功能檢查：`-- --fire-check=OUT_DIR`。

- 美術語言（參考《鬼滅之刃》碧羅天）：先有明確的火環主形，再加細節。手繪造型貼圖 `stylized_flame_band.png`（`make_stylized_assets.py` 生成；R＝火體距離場、G＝黃核心位移、B＝白熱亮線、A＝深色摺痕；匯入關掉 fix_alpha_border）。
  著色用門檻切硬邊色塊：大面積金黃核心、橘中層、紅外焰、外側深色輪廓線；形狀抖動 12 fps 跳格。
- 路徑：`hekira_ring_path.json`＝R11 實測刀尖 0.53–0.95 s（角色根本地座標），σ＝8 ms 平滑、半徑往平均收 35%，0.95–1.00 s 用短弧閉合（345° → 360°）。
  執行時照「畫面上的刀」逐段點燃（骨架晚 shot_t 一幀），用當下的角色變換放進世界，之後留在原地；刀尖到火環實測最大 8.8 cm。
- 火帶每幀朝相機展開（自由視角都看得到整圈），方向一律朝環外；擋在角色與鏡頭之間的段變窄、變透明。起點與刀尖前緣收尖。
- 節奏：刀經過即點燃（0.07 s 由內緣長到全高）→ 1.00 s 閉合 → 1.10 s 起由外往內撕開（先點燃的先散）→ 約 1.8 s 燒完。命中時黃核心瞬間擴大（flare）。
- 只是視覺：判定、Hit Stop、命中範圍完全沒動。R9 只留白金刀線（標出刀刃位置），不用 Blender 火焰層與 R9 噪聲火帶。
- **動作限制**：R11 碧羅天刀路是半徑 1.14 m、繞胸口一圈的「斜環」，環面與地面夾 31°，不是參考圖的垂直火環。火環照實際刀路做，沒有用特效硬做成垂直；要垂直火環必須改動作。
