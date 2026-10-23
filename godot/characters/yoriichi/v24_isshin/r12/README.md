# R12 日之呼吸・火車（かしゃ）— 蓄勢 → 刀身點燃 → 起跳空中縮身前空翻 → 火焰爆發 → 向下斬擊 → 落地（ART_REVIEW）

2026-10-22：R12 原本暫定為碧羅天的空翻招，改歸「日之呼吸・火車」。動作、時序、Root Motion、碰撞全部沿用，不重做。
碧羅天回到 R11 原版（`r11/`，技能 ID `sun_hekiraten`，未改）；碧羅天的新動作來源由使用者自行研究，暫停開發。
沒改 R11、正式 Player、跑酷、普通劍術、共用骨架、戰鬥控制器。

## 對應表（火車 vs 碧羅天，兩者不共用 ID）
| 項目 | 火車（R12） | 碧羅天（R11，原樣） |
|---|---|---|
| 技能 ID | `sun_kasha`（試玩執行時加進技能表；輸入／傷害 3／冷卻／派生沿用碧羅天的值另建一份） | `sun_hekiraten`（`r11/sun_breathing_r11.json`） |
| 技能資料 | `r12/kasha_r12.json` | `r11/sun_breathing_r11.json` |
| 動畫 | `anims/isshin_sun_kasha_r12.res`（jobs `r12/r12_anim_jobs.json`） | `anims/isshin_sun_hekira_r11.res` |
| Blender 火焰 | `r9c/enbu_vfx_KS12.glb`，變體 `KS12_R10` | `r9c/enbu_vfx_HK11.glb`，變體 `HK11_R10`／`HK11_L1`／`HK11_L2` |
| 統一火焰 profile | `sun_kasha`（`fire_research_v2/sun_fire_profiles.json`，火環路徑 `kasha_r12_ring_path.json`） | `sun_hekiraten` |
| 試玩 | `r12/r12_kasha_demo.tscn` | `r11/r11_combat_demo.tscn`、`fire_research_v2/sun_fire_hekira_demo.tscn` |
| 研究腳本 | `notes/r12/build_kasha_r12.py`、`make_blade240_r12.py`、`build_kasha_vfx.py`、`gen_kasha_vfx.py` | `notes/r11/build_hekira_r11.py`、`gen_r11_data.py` |

改名時舊的 R12 產物（`isshin_sun_hekira_r12.res`、`enbu_vfx_HK12.glb`／`.blend`）由同一腳本以新名重建，比對與舊檔相同（動畫軌道、root motion、刀路、火環點）後移到 `%LOCALAPPDATA%/hermes/cache/scratch/r12_pre_kasha/`。
`r12_hekira_motion_preview.tscn` 是當時的候選預覽，保留原名。

## 試玩
`res://characters/yoriichi/v24_isshin/r12/r12_kasha_demo.tscn`（開場選火車；繼承碧羅天火焰試玩 → R11 → R10，碧羅天本身不覆寫）。
L／右鍵 火車｜Space 閃避（蓄勢段可取消）｜R 回木樁前（木樁 3.2 m）｜B 火焰：Blender KS12 ↔ 統一系統火環｜Z／X 換型（可選回 R11 碧羅天）｜Q／E、←／→ 轉鏡頭｜O 繞轉。
鏡頭：第三人稱自由鏡頭（`third_person_cam.gd`，身後偏右肩），技能不接管。
功能檢查：`-- --kasha-check=DIR`（命中、位移、牆、蓄勢取消，4 張圖）；報告 `D:/research/sekiro_r8_p0/notes/r12/report_r12_check.py DIR`。

## 動作（梟 c5060 a000_003003 改造，`notes/r12/build_kasha_r12.py`；沿用 R10/R11 的「重定向軌道 → build_r10_anims.gd」流程）
| 時間 | 階段 | 做法 |
|---|---|---|
| 0–0.22 s | 入架 | 左腳 IK 弧線退 0.42 m，雙手把刀舉到臉前、刀身沿背上方；0.08 s 刀身開始點燃 |
| 0.22–0.46 s | 壓抑 | 原動作下蹲段放慢成 0.27 倍：髖 0.79→0.63 m，刀尖仍以 1.2 m/s 緩動（不是停格），兩腳 IK 釘地 |
| 0.46–0.54 s | 爆發 | 原動作蹬地段 1.75 倍速，腳在腿伸直前不離地 |
| 0.54–1.32 s | 空中縮身前空翻 | 髖高改成拋物線（g＝9.8、滯空 0.78 s、髖最高 1.58 m、腳最高 1.85 m、倒立時頭 0.87 m；原動作髖升 1.7 m、腳 3.1 m） |
| 1.15–1.32 s | 向下斬擊 | 原動作原速，刀尖 50 m/s，1.30 s 命中 |
| 1.32–1.65 s | 落地吸收 | 原速，兩腳落點 IK 釘地（髖低到 0.49 m） |
| 1.65–2.45 s | 收勢起身 | 2.2 倍速；腳伸不到時改成真的跨一步；手臂、上身淡回待機 |

- 雙手：蓄勢到翻轉頂點用原動作 0.40 s 的手臂姿勢，左手由既有雙手握刀 IK 收合 0.21 m；下劈前 1.12–1.18 s 換回原動作手臂。不用 IK 硬拉整條手臂。
- 位移：起跳 0.30 m＋空中 1.68 m（原 4.0 m ×0.42，只在空中縮，腳不滑）＋落地 0.18 m＝約 2.2 m；離木樁較近時空中段等比縮（`lunge_min_dist` 1.2 m）。原動作整段降 8.5 cm（原站高比緣一高）。
- 判定：命中窗 1.19–1.36 s、停格 5 幀、閃避取消 ≥1.62 s、移動／攻擊取消 ≥1.85 s；蓄勢段（<0.44 s）閃避可取消。其他型接在火車後的時間＝1.85 s。
- 碰撞：位移經 R11 的 0.3 m 膠囊對牆掃掠（牆在 1.3 m：根停在 1.0 m，不穿）。膠囊留在地面高度；刀身不和牆碰撞（所有招式相同）。

## 火焰
- 預設＝Blender 火焰 KS12：R11 原版同一套 Blender 建造（`notes/r9c/build_enbu_vfx.py`＋`notes/r9c2/build_hero.py`；分層 Sheet／Layer0／Layer1／Fin／Flames／Burst／Embers／BladeFlame／命中三層）跑在火車的真實刀路上（`make_blade240_r12.py`，240 Hz、施放時的世界座標）。`build_kasha_vfx.py` 另加：沿行進方向繞刀尖線扭轉 ±38°、層距 0.09→0.16 m、Fin 0.16→0.30 m、火舌 7→9 叢。Blender 原檔 `D:/research/sekiro_r8_p0/combat/r12/enbu_vfx_KS12.blend`。
- 時間（`gen_kasha_vfx.py`）：材質／顏色／光照取 R11 HK11_R10，映到火車時間（點燃 0.10、起跳 0.54、命中 1.30、主弧結束 1.36）；主體／火舌壽命 0.85／0.9 s，1.38–2.1 s 撕裂飄散。網格施放時固定在世界（火焰留在刀經過的地方）；`sun_vfx_mesh.gd` 只多一個選用欄位 `light_freeze_t`（R11 不設＝照舊）。
- B＝統一系統 `sun_fire.gd` profile `sun_kasha`：刀身熱邊＋依技能時間沿翻轉展開的縱向風格化火環（中心離地 1.38 m、半徑 1.23 m），不強求完整圓；`sun_fire.gd` 只多兩個選用欄位（`stroke.follow_until`、路徑第 5 欄寬度倍率）。
- 命中爆燃照實際命中事件（`mvfx.hit`）。
- A/B 錄影工具：`notes/r12/record_compare.sh`＋`compare_vfx.py` → `D:/research/r12_vfx_compare/`（R11 碧羅天原版作為畫質基準）。

## 以下為碧羅天時期的研究紀錄（動作來源篩選；碧羅天現暫停，保留作紀錄）

### 預覽
`res://characters/yoriichi/v24_isshin/r12/r12_hekira_motion_preview.tscn`（繼承 R10 試玩，動作都是 R10 刀法庫裡已重定向的隻狼原動作，未改造）
1–5 播放候選（第二輪清單）｜T 慢動作 0.3×｜R 回原點｜Q／E 轉鏡頭｜O 繞轉｜白帶＝刀尖軌跡。功能檢查：`-- --preview-check=DIR`。

### 第二輪：依參考影片重篩
參考：YouTube 3cCYBKi6o0k「碧羅の天」（17 s，無限列車篇）。用 2 fps 總覽＋10 fps 細格逐段看（`D:/research/r12_ref_video/`）。

| 時間 | 內容 |
|---|---|
| 0–2.5 s | 蓄勢：雙手舉刀過頭、身體前壓、咬牙；呼吸從白霧變成火焰 |
| 3–6.5 s | 刀身點燃特寫：刀刃先一條橘光，再長出火舌、火星，最後整把刀包在流動火焰裡 |
| 7–8.4 s | 已經在空中，雙手持刀高舉，從高處飛向目標 |
| 8.6–10.6 s | 空中縮身前空翻：背拱起、膝收到胸、頭朝下，雙手刀貼在身體旁 |
| 10.7 s | 一格縱向拖影（爆發） |
| 10.8–11.8 s | 正面看的完整火環（內白黃、外橘紅、深色描邊）＋中央十字閃光，完整停留約 1 s |
| 11.9–14 s | 縮身翻轉的炭治郎在火環中間；火環邊緣開始撕裂、甩出火舌，但仍連著 |
| 14.5–16 s | 從上方斬中車頭：白閃、兩道重疊火弧、碎塊飛起 |

篩選（`notes/r12/survey_flip_r12.py`，量軀幹側面轉角、離地、刀尖繞身掃角與半徑、雙手比例）：

| # | 來源 | 實測 | 評價 |
|---|---|---|---|
| ① | 梟 c5060 a000_003003 | 沉身→起跳，雙腳最高 2.9 m → 空中前翻 350° → 1.0 s 下劈 54 m/s → 深蹲落地；刀繞身 453°、半徑 0.96 m；單手；前進 5.8 m | 最完整（現為火車的基底） |
| ② | 狼 c0000 a050_309000 | 0.27–0.67 s 前翻 367°，刀繞身 600°、兩刀 47／56 m/s；雙手 57% | 只有空中段 |
| ③ | 狼 c0000 a101_316200 | 站立前手翻、腳離地 0.96 m → 0.67 s 縱劈 59 m/s；刀繞身 494° | 低空翻 |
| ✗ | 弦一郎 c7110 a000_003015 | 低空前滾翻，刀繞身 236° | 不採用 |

### 第一輪（地面縱劈）
腳本：`survey_hekira_r12.py`（550 支、721 段 strike）、`timeline_r12.py`、`arc_pair_r12.py`、`plot_windows_r12.py`。結論：地面上沒有「先蓄勢、再高速畫 ≥300° 垂直圓」的動作；縱劈系側面 220–300°。
