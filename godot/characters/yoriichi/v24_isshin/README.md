# 緣一 × 一心「拿刀走路」移動展示（ART_REVIEW，未接正式 Player）

動作來源：《隻狼》c5400 a000 動畫 400000（待機）、405000（前走）、405001（後退）、405002（左移）、405003（右移）、405010（快走）。
重定向：Blender 內以世界旋轉差＋A/T 姿勢補償轉到緣一 v24 骨架（`D:/research/sekiro_r8_p0/notes/bl_retarget_walk.py`），
再烘成 Godot Animation（`build_isshin_anims.gd`）。握刀＝R6.2 解好的握形＋刀柄沿掌心滑 7 cm（貼近刀鐔）＋大拇指另解（繞過刀柄前側、尖端壓在食指／中指上；六支動作共用同一組手指局部旋轉，切換時手不會變形）。

## 執行
```
godot --path godot res://characters/yoriichi/v24_isshin/isshin_move_demo.tscn
```
W 前進　S 後退　A/D 左右橫移　Shift+W 快走　Q/E 轉身　右鍵拖曳／滾輪 相機　F 彈簧骨　H 隱藏說明　R 重設　Esc 離開
同時按前後＋左右（斜向）＝用前走／後退動作，身體轉向移動方向（前走和橫移是不同的腿部動作，混在一起站立腳會漂）。

## 檔案
| 檔案 | 說明 |
|---|---|
| `isshin_move_demo.tscn/.gd` | 展示場景（緣一 v24_r62 身體＋刀＋空鞘＋彈簧骨；AnimationTree + BlendSpace2D） |
| `anims/isshin_*.res` | idle 5.0 s、walk／back／strafe_l／strafe_r 2.333 s、run（快走）1.167 s，全部循環 |
| `build_isshin_anims.gd` | 由 Blender 輸出的 JSON 烘 .res；含循環相位平移（把各動作左右腳站立時機對齊走路） |
| `measure_isshin_clips.gd` | headless：Blender↔Godot 骨位誤差、站立腳接觸速度向量、站立相位、離地、接縫 |

`--auto --out=DIR` 自動拍照＋導覽 GIF；`--hand` 握刀近景；`--dbg` 指骨小球；`--slip` 真實移動下量腳滑（以上皆用 Godot 視窗模式，不是 headless）。

## 實測（Godot 4.7.2）
| 動作 | 不滑步速度（站立腳接觸速度中位數） | 備註 |
|---|---|---|
| walk 405000 | 前 0.490 m/s | 70 格循環 |
| back 405001 | 後 0.443 m/s | |
| strafe_l 405002 | 左 0.419 m/s | |
| strafe_r 405003 | 右 0.447 m/s | |
| run 405010（快走） | 前 0.976 m/s | 原動作是 2 倍步頻的快走，站立相佔 50%，不是騰空跑；一心原動畫位移 2.97 m/s 與腳不符，不採用 |

- Blender↔Godot 骨位誤差 0.00001 m（未平移的原始版本，6 支）；循環接縫 0.0 m；最低腳趾高度 0.074–0.080 m。
- 拇指（皮膚網格實測）：貼在刀柄前半圈的頂點 0 → 31；角度 −97…63° → 28…163°（0° = 掌心側、180° = 刀柄正前方）。
- 真實移動下（`--slip`）身體速度 0.42–0.97 m/s，站立腳世界速度中位數 0.09–0.18 m/s（斜向 0.10–0.11，與正向同量級；此偵測含落地／離地瞬間，非零偏高）。
- 若不做相位平移、斜向直接混合：fwd+L 站立腳世界速度 0.76 m/s（明顯滑步）；平移後 0.34；改成「前走動作＋身體轉向」後 0.10。
- 右手在髖外側約 0.31 m、刀尖朝下偏外；手腕彎 38°；刀對粗略軀幹膠囊最近 −15 mm（羽織會蓋住，未驗證布料穿插）。

## 注意
- 這是《隻狼》原始動畫的衍生物（使用者 2026-10-20 表示不在意著作權），**未 git 提交**；正式 Player／控制器／場景一行未改。
- 身體用 `v24_r62/yoriichi_v24_r62.glb`（R6.2 握形在這個身體上解的；骨架與 `v24/yoriichi_v24.glb` 逐骨相同）。
- 視覺成果僅 ART_REVIEW，需使用者驗收。


---
## 戰鬥警戒步行候選（2026-10-20，獨立候選；與跑酷／正式 Player 無任何引用）

| 檔案 | 用途 |
|---|---|
| `combat_locomotion.gd` | 戰鬥警戒步行：鎖定敵人、起步／停步／反向煞停／原地轉身（90／180）／閃避；`step(delta, move, dodge, target_pos, dodge_side)` 為唯一入口 |
| `hip_twist_modifier.gd` | SkeletonModifier3D：斜向時腿朝移動方向、胸口仍朝敵人（需排在 SpringBone 之前） |
| `isshin_combat_demo.tscn/.gd` | 第三人稱示範場景。W/S/A/D、Shift+W 快走、Space 閃避、←/→ 轉動敵人方位、O 敵人繞圈；`-- --tour [--log=PATH] [--diag=twist\|blend]` 自動導覽＋逐幀記錄 |
| `anims/isshin_turn_{l,r}{90,180}.res`、`isshin_dodge_{l,r}.res`、`root_motion.json` | 405400–405403、405012／405013 重定向結果（單發）與一心根位移（偏航／左／前） |

要點（實測，詳見研究目錄 `D:
esearch\sekiro_r8_p0\combatnalysis_v5.json`）：
- 動作庫（已解碼 a000 共 172 支，非攻擊 115 支）沒有專用起步／停步／方向變換動作；起步＝把前進循環跳到「經過相位」再加速（0.45 s），停步＝在 0.45–0.85 s 內讓播放速度與身體速度一起降到 0 並落在經過相位，反向＝先煞停 0.22 s 再起步。
- 斜向：不混合兩個方向動作，用前／後動作＋髖部扭轉朝移動方向、脊椎補償讓胸口朝敵人（混合版站立腳速度 0.14–0.26 m/s，扭轉版 0.07–0.10 m/s）。橫移動作本身軀幹側轉 52°，另加 33° 胸口補償。
- 閃避是騰空滑步（腳踝離地 0.35 m），沒有接地期可量；距離＝一心原位移 3.6 m × 0.55 ≈ 2.0 m（峰值 4.8 m/s），`DODGE_SCALE` 可調。
- 不影響跑酷：本資料夾只新增檔案，`yoriichi_character.gd`／Player／場景一行未改，未 git 提交。


---
## 衣物／腳步視覺檢查（2026-10-20，仍為候選；未改正式 Player、跑酷、共用骨架）

| 檔案 | 用途 |
|---|---|
| `isshin_visual_check.tscn/.gd` | 三面板（正面／左側刀鞘側／背後）原速檢查；起步／停步／反向／轉身時在腳踝正下方放標記並顯示公分數（「滑」＝支撐腳位移，「步」＝邁步腳）。旗標：`--tour --no-iklock --diag= --poselog=P --log=P --slipjson=P --shots="T,x,y,z,名;…" --shotdir=D --cam-off=x,y,z --cam-dist=m`，以及僅作診斷用的 `--springs=off --sleeve-springs=off --sleeve-col=off --hem-col=off --torso-extra=m --hem-leg=大腿,小腿` |
| `foot_lock_modifier.gd` | 局部腳掌鎖定 IK（SkeletonModifier3D，解析式二骨 IK）。只在待機／起步／停步／反向啟用；轉身與騰空閃避關閉。`combat.foot_lock_on=false` 或 `--no-iklock` 可關 |

腳掌鎖定規則：腳踝離待機高度 < 3 cm 且水平速度 < 0.7 m/s 才抓；起步只鎖「該相位的支撐腳」（`STANCE_AT` 表，由 `scan_planted.gd` 實測），停步誰貼地且慢誰鎖；抬腳（> 5 cm）或速度 > 0.7 m/s 就放（0.12 s 斜坡）；轉身／閃避起手時鎖定點與動畫腳差 < 4 cm 直接放、否則 0.12 s 放。

已量到、尚未處理的缺陷（數據與圖在 `D:
esearch\sekiro_r8_p0\combatc\`）：
1. 後退停步時左袖口（`Cuff_L_Dn`）彈跳 18.6 cm／幀：彈簧骨 × 軀幹碰撞膠囊卡死後釋放；關掉袖鏈碰撞降到 4.3 cm，關掉彈簧為 0。
2. 羽織前襬在前進／斜向／橫移／閃避時穿進袴：原因＝下襬碰撞膠囊大腿 8 cm／小腿 6 cm，袴實際表面半徑 11.7／15.1 cm，且每片下襬只有 3 節、只有節點做碰撞。
3. 待機姿勢本來就有後下襬 15% 長度在袴內（資產本身的穿插）。

### 衣物微調（`cloth_tuning.gd`，候選預設開；`--no-clothfix` 關閉；只改此實例的彈簧骨碰撞設定）
- 袖口：`Cuff_*_Dn` 兩條袖鏈不與軀幹膠囊碰撞 → 最大單幀跳動 18.6 → 5.8 cm，離靜止最大偏移 37.4 → 8.5 cm。
- 下襬：腿膠囊放大（大腿 12／小腿 14 cm）→ 羽織進袴 > 2 cm 的最大頂點數：前進 2096→1537、停步 2094→1018、閃避 1765→1246；下襬抖動不變（HF rms 0.80→0.81 cm）。**仍有穿插，記為後續美術問題**（每片下襬只有 3 節、只有節點做碰撞）。
- 腳掌 IK 不再動。快測影片：`D:
esearch\sekiro_r8_p0\combatc\yoriichi_cloth_ik_quicktest.mp4`（21 s，`--short`）。


---
## 第一支雙手斬擊 `slash_v`（2026-10-20，候選；不改 Player／跑酷／共用資產）
- 來源：一心 TAE 3038（hkx `a000_003012`）的第一刀＝中段 → 上段 → 直劈 → 殘心。挑選依據：已解碼的 a000 攻擊中，打擊窗（f11–15）內雙手距離 < 0.30 m 的比例 100%（單手斬擊佔大宗，例如 3000 為 0%）、斬線 elev −30°（由上往下）、出手點在中線（right≈0）。原動作 f0–f19 取出（0.63 s），後面補 12 格定格殘心（讓 OneShot 淡出在隨揮之後）；之後原動作會抬回上段接第二刀，不用。
- 檔案：`anims/isshin_slash_v.res`（`build_isshin_anims.gd` 的 TRIM／PAD）、`two_hand_grip.gd`（重用 `characters/yoriichi/r62_grip_ik.gd` 的右手＋左手握刀 IK，只實例化不修改）、`combat_locomotion.gd`（`slash_v`：位移＝一心根位移 × `travel_scale` 0.55、判定窗 f11–15、命中停格 `HITSTOP_FRAMES`=5）、`isshin_slash_demo.tscn/.gd`（J／滑鼠左鍵＝斬擊；`--tour --slashlog=P --dist=2.0 --no-audio --no-grip`）。`isshin_visual_check` 加 `--slash-tour` 可看三面板。
- 實測：舉刀 0.32 s 刀尖到最高 2.20 m；命中在 0.467 s（打擊窗 0.367–0.500）、刀尖速度峰值 70 m/s；命中停格 5 幀（83 ms）時攻擊動畫、位移、計時全凍結（刀尖速度 0），布料照常；右手握位誤差 0 mm（權重 1）；突進 1.63 m。
- 已知缺陷：舉過頭到下劈起手那 8 幀（shot_t 0.30–0.43）緣一左臂伸直（reach 1.000，臂長 0.414 m），左手離刀柄最多 56–61 mm（平均 11 mm）；原因＝一心動作的刀位離左肩太遠，滑動握位無法解決（測過）。


---
## 兩刀連段 `slash_vh`：縱斬 → 橫斬（2026-10-20，候選；ART_REVIEW；不改 Player／跑酷／共用資產）
- 左手離柄修正（研究目錄 `notes/fix_twohand_reach.py`）：在重定向結果上逐格只轉兩根骨——左鎖骨（`LeftShoulder`，最多 33°，左肩往前 2–4 cm、往中線 1–3 cm）與右上臂（`RightArm`，最多 13°，刀往中線收 2–7 cm），時間上高斯平滑；刀尖位移 ≤ 7 cm。左握位到左肩距離 ÷ 臂長：1.146 → 0.981。實測（同一套量法）：單發第一刀左手離柄最大 60.6 mm／8 格 → 0 mm，左臂完全伸直 9 格 → 0 格（最大伸直比 0.98）。`anims/isshin_slash_v.res` 已換成修正版。
- 第二刀：一心 TAE 3071（hkx `a000_003071`，雙手橫斬，起手是上段，結尾回到待機 400000 同一姿勢）同一管線重定向＋同一修正。
- 交接（`notes/build_combo.py` 烘成單支 `anims/isshin_slash_vh.res`，4.0 s）：k0–18＝縱斬原樣（與 slash_v 逐格相同，不含 12 格定格殘心）；k19–26＝8 格交接：縱斬後續（刀回彈上舉）與 3071 f1–8（上段落到右腰）逐骨 slerp，左腳釘地（根位移由左腳反推）、右腳以雙骨 IK 抬 14 cm 後撤一步；k27–120＝3071 f9–102。刀與身體膠囊最小間距 6.7 cm（不穿身）。
- 控制（`combat_locomotion.gd`）：攻擊不再走 OneShot（中途換動作會讓 OneShot 直接結束），改成 `atk` Blend2＋每支攻擊動作各自 TimeSeek，權重由腳本淡入淡出。第一刀開始後 0.10–0.70 s 內再按攻擊＝接第二刀（只記一次）；交接起點 0.633 s 之前切換姿勢逐格相同，之後晚按淡入 0.08 s。判定窗：第一刀 f11–15、第二刀 k32–37（TAE 3071 f14–19）；每個窗只算一次命中。3071 f52 放開左手；TAE「可移動」f69（k87＝2.9 s）之後有移動輸入就提早淡出交回步行。攻擊位移不把角色推到離目標中心 0.95 m 以內。
- 命中停格：比較 3 幀（50 ms）與 5 幀（83 ms）後採 3 幀（`HITSTOP_FRAMES`；`--hitstop=N` 可覆寫）。停格期間攻擊動畫、位移、計時、判定一起停，實測刀尖速度 0、shot_t 不前進、每刀只扣一次血。
- 示範：`isshin_slash_demo.tscn -- --tour --dist=2.7`（18 s：單發第一刀 → 兩刀連段自然收回 → 兩刀連段後直接移動）。


---
## 操作手感＋第三刀 `slash_vhx`（2026-10-20，候選；ART_REVIEW）
- 回退基準（兩刀 v1）：研究目錄 `combat/rollback_twocut_v1/`（舊 combat_locomotion.gd／isshin_slash_demo.gd、godot_tracks_combo_vh_v1.json、舊影片）；烘焙腳本 `notes/build_combo_v1_twocut.py`。
- 取消窗（`SHOTS[*]` 的 next／dodge_cancel／move_cancel，皆在刀過有效攻擊段之後）：橫斬判定 k33–38、刀尖 < 7 m/s 在 3071 f17（k36）。兩刀：接第三刀 1.20–1.63 s、閃避 1.33 s、移動 1.50 s（原本 2.90 s）。三刀：閃避 2.10 s、移動 2.50 s（3031 f40＝TAE ComboAttack 旗標），完整收回 5.0 s。
- 交接一：9 格（原 8），右腳後撤峰值 12.6→10.9 m/s（離線）／實跑約 10 m/s。前衝段 lunges：進入時依離目標距離整段等比縮短（取代撞到 0.95 m 才急停）。
- 第三刀：一心 TAE 3031（hkx a000_003031）雙手左上→右下袈裟斬。選法：`notes/third_cut_search.py` 以 3071 收刀姿（刀在左腰、右腳在前）比對所有 a000 攻擊的蓄勢姿（手位、刀向、雙腳、髖肩朝向），再以「刀在左 → 由左往右斬、站姿同為右腳在前」判讀；3031 結尾回到待機 400000 同姿。交接二：3071 f21–28 × 3031 f5–12（左側舉刀），右腳釘地；判定 f18–23 → k53–58；3031 f22 放左手。


---
## 跨角色融合原型 `slash_vhg`（2026-10-20，候選；ART_REVIEW）
- 候選表：研究目錄 `analysis/motion_study/XCHR_CANDIDATES_R1.md`（c7100 弦一郎、c7110 巴流、c7400 永真已解碼；梟的 Boss 版本角色 ID 未找到）。
- 第三刀換成弦一郎 TAE 3001（雙手、左腳上步、舉刀過頭 → 唐竹斬）：`notes/build_combo.py C=c7100_a000_003001_reach FC=6 N2=6 TSC=0.6 PLANT2=R LIFT2=0.04 OUT2=combo_vhg`；重定向前用 `SEKIRO_CHR=c7100`（walk_probe／bl_retarget_walk 已參數化）。
- 控制：`combat.third_key`＝"slash_vhx"（一心 3031，保留）或 "slash_vhg"（融合）。融合版斬後 2.27 s 可閃避／移動，2.8 s 淡回一心待機（`end_t`，不用弦一郎自己的中段構）。一心三刀版：2.10／2.50 s，5.0 s 收完。
- 示範木樁加擊退：橫斬 0.6 m、第三刀 0.45 m（`KNOCK_M`），前衝段在命中後依新距離重新估算位移。
