# P10 R3c Mixamo Activity Pack — FINAL ART_REVIEW（等待使用者裁定）

Agent 只到 ART_REVIEW，**未授 ART_APPROVED、不進 R3d**。範圍不變：16 人、7 件指派／5 類（Talk×3、Carry、Sit、YouthShortStep、Drink），私有 overlay `godot/scripts/npc_activity_overlay.gd`；封存的 R3b actor／generator／Population scene、NPCLIB、P9、市場都沒改。

## 本輪：W3 Drink A/B 收尾（2026-10-07）
| 候選 | 結果 |
|---|---|
| A `drinking_a030`（原指派） | 淘汰：喝時低頭 48°、最寬時上臂離垂直 104°（肘高過肩 5 cm）、杯進臉 55 格最深 3.1 cm、手指陷杯 1.9 cm、杯到眼高 1.30 s／循環 |
| **B1 `drinking_im1_a030`**（Mixamo Drinking Intensity −1）＋新握持 | **採用**：臉／袖／軀幹進杯 0 格、握指接觸 ≤ 3.3 mm、不浮空、杯緣距唇最近 1.1 cm、低持杯傾 ≤ 15°、喝時低頭 2.7°、上臂最大 91°、肘外張 15 cm、無聳肩 |
| B2 `watercooler_a030` | 淘汰：沒有真正喝到（杯距嘴 4.6 cm）、臉＋袖／軀幹命中、hold 段前傾彎腰 |

- 共同病因是舊握持（杯軸固定在 −hand.x、杯底貼在指根內）：三支都把杯插進臉、手指陷杯、喝時杯轉過水平。新握持由 `tools/fit_p10_drink_cup.py` 在 CPU 蒙皮頂點上擬合：`cup_grip (0.04,−0.02,0.09)`／`cup_axis (−0.962,0.263,−0.066)`（LeftHand 軸）。這是道具擺放，**動畫 key 未改**。
- 杯模補上杯底與內底（原本是開口筒，從下方看像杯口）。
- **殘留（非阻塞，請判斷）**：每循環 4.20–4.43 s（0.27 s）有一段喝乾動作，杯傾到 123°、杯到眼高、肘抬到肩高。Mixamo Drinking 調到最低 Intensity 仍有這段，不手 key 就去不掉。TPS 6 m 時 7 cm 小杯形狀不易辨識（看得出動作，看不太出杯子）。

## 審圖檔
- `drink_ab_close_front34.jpg`／`drink_ab_close_profileL.jpg`：A／B1／B2 同鏡近景 1.7 m，hold／approach／sip／widest／return。
- `drink_ab_tps_4m.jpg`／`_6m`／`_8m`：TPS 距離，hold／sip。
- `W3_drink_in_village_sheet.jpg`／`W3_drink_isolated_sheet.jpg`：最終版 4 視角×8 相位。
- `1_…`–`6_…_R3b_vs_R3c.jpg`：R3b（activity off）vs R3c（on）同鏡六類；5 為正式 Player 實際走動 6 格，R3b／R3c 各一列。
- 原圖：`../final_population`、`../final_baseline_walk`、`../final_w3_selected`、`../final_w3_isolated`、`../drink_ab/render`（全部最新 build、Forward+、10:00、1920×1080）。

## Technical（同一版本）
- `verify_p10_activity.gd`：plan 8／scene 17／negatives 27 全 PASS exit 0（`../final_gate/`）。杯脫手檢查改為「杯體中心距中指根 ≤ 0.10 m」，原本是杯底 ≤ 0.09 m；新握持下杯底距 0.100 m、杯體中心 0.088 m。
- R3b `--seal` 0 失敗、NPCLIB `--seal` 0 失敗。
- 量測：`../drink_ab/drink_ab2_old.json`（舊握持）、`drink_ab2_final.json`（新握持＋逐格臉部 trace）、`cup_fit_B1.json`。
- Gate PASS ≠ 美術 PASS。

## 視覺界線（直說）
六類審圖鏡位是 8.5 m TPS 和 13 m 高視角。在這些距離下，R3b→R3c 的差異偏小：Talk／Carry／Sit／Drink 遠看大多只是姿勢不同，不容易認出是在做什麼。**不宣稱已達「同一 TPS 鏡位明顯變成有人生活、交易、工作的村落」**。W3 喝茶在 TPS 4–6 m 看得出手到嘴的動作；其他 6 件沒做同等距離檢查。
