#!/usr/bin/env bash
# 人間之里 V2 回歸總表（P1 Terrain ART_APPROVED 2026-09-24 起，任何 gen_village_v2.gd／terrain lib／water lib／layout 修改後都要全跑）。
# P2 起加：P1 Approved Terrain Protection（水線以上 |Δh| ≤ 0.03 m、岸線縫 ≤ 0.30 m）與 P2 water gate。
# P3 起加：roads / parcels gate（巷道層、單棟地塊 §11 紀錄、覆蓋率）。
# P5 Asset Reset 起加：asset reset gate（V2 只能引用白名單／已過 Asset Gate 的新資產；Protected 資產雜湊不變；封存不等於刪除）。
# P5 R1 起加：Hero Asset Gate 回歸（v2_assets 已登記的 Hero／地標在場景裡重驗尺寸～效能 9 項；截圖與 F5/F6 另跑 --render，見規劃 §15）。
# P5 R5 後加：場景擺放／碰撞稽核 audit_village_v2_placement.gd（skill godot-asset-placement-validation；AABB 只當 broad phase；--selftest 含 5 個永久反向／對照案例）。
# P8 ART_APPROVED（2026-10-01）起加：P8 封存雜湊（--seal，含反向）、local gate＋--negative（預期恰 1 項 FAIL）、田埂／水面擺放稽核、取水淨空、
#   全區 25 段 1.7 m 實走＋TPS 相機淨空（--no-shots，不覆寫封存圖）、runtime budget（五鏡位 A/B；GPU 增量一般 ≤ 4 ms、T1 ≤ 6 ms、render CPU ≤ 4 ms）。
#   P8 實走／A/B 需要實際渲染（非 headless）；A/B 量測前 GPU 須閒置（其他遊戲／影片會讓數字整體偏高）。
# P9 R1 ART_APPROVED（2026-10-01）起加：植被庫封存（--seal，含反向）、veg_kit Asset Gate 1–9 回歸＋gate.json 11 項（--regress，唯讀）、
#   6 個永久反向案例（--negatives：每個都必須讓它瞄準的那一項 FAIL）。
# 永久 build rule（2026-10-03 起）：MultiMesh 烘焙必須非 headless，存檔後回讀 instance transform 非零（tools/village_v2_mm_bake_guard.gd）；
#   本表 MMBAKE 以非 headless 掃描整個 village_v2 場景的全部 MultiMesh（headless 跑會直接 FAIL，不當 PASS）。
# 用法（repo 根目錄，git-bash）：  bash godot/tools/run_village_v2_regression.sh [--full] [--seals] [--gen]
#   （預設）FAST：只跑 FAST_TAGS（凍結／地形保護／Hero 回歸／場景擺放稽核；約 1.5 分鐘）——日常改動用這個（2026-10-18 使用者裁定：驗證預算）
#   --full  全部非封存項目（里程碑、批次提交前、使用者要求時才跑）
#   --seals 另外加跑封存（--seal）項目。封存制度 2026-10-18 起退役（凍結改由 git 提交保證）；
#           場景本體可直接手改，封存雜湊不符是預期的，只在要對照歷史基準時才跑
#   --gen   先重新產生場景再驗證（生成器已退役，需另設 VILLAGE_V2_ALLOW_REGEN=1，會丟掉全部 overlay）
# 任一項非 0 退出 → 整體退出碼 = 失敗項目數。固定鏡位擷取另見 docs/plans/2026-09-23-人間之里V2重製規劃.md §9.5。
set -u
cd "$(dirname "$0")/.." || exit 99
G="${GODOT:-D:/Godot/Godot_v4.7.2-stable_win64_console.exe}"
fail=0
skipped=0
MODE=fast
SEALS=0
GEN=0
for a in "$@"; do
	case "$a" in
		--full)  MODE=full ;;
		--seals) SEALS=1 ;;
		--gen)   GEN=1 ;;
	esac
done
FAST_TAGS=" FREEZE PROTECT HERO PLACE "   # 19 點實走（WALK）單項約 9.5 分鐘 → 只在 --full
skip() {  # $1 標籤, $2 tag, 其餘為 Godot 參數 → 0＝要跳過
	local label="$1" tag="$2"; shift 2
	local is_seal=0
	case " $* " in *" --seal "*) is_seal=1 ;; esac
	case "$label" in *封存*) is_seal=1 ;; esac
	if [ $is_seal -eq 1 ] && [ $SEALS -eq 0 ]; then return 0; fi
	if [ $is_seal -eq 1 ] && [ $SEALS -eq 1 ]; then return 1; fi
	if [ "$MODE" = fast ] && [[ "$FAST_TAGS" != *" $tag "* ]]; then return 0; fi
	return 1
}
run() {  # $1 標籤, $2 grep 前綴, 其餘為 Godot 參數
	local label="$1" tag="$2"; shift 2
	if skip "$label" "$tag" "$@"; then skipped=$((skipped + 1)); return; fi
	local out; out="$("$G" "$@" 2>&1)"; local rc=$?
	printf '%s\n' "$out" | grep -E "^\[$tag\] (FAIL|結果)|SCRIPT ERROR|Parse Error"
	if [ $rc -ne 0 ]; then echo "✗ $label（exit $rc）"; fail=$((fail + 1)); else echo "✓ $label"; fi
}
runneg() {  # 反向：$1 標籤, $2 期待する FAIL 行（grep -F）, 其餘為 Godot 參數；exit≠0 かつ期待行あり → PASS（P10 R6a：P6 Kit Gate 合法変体の反向）
	local label="$1" want="$2"; shift 2
	if [ "$MODE" = fast ]; then skipped=$((skipped + 1)); return; fi
	local out; out="$("$G" "$@" 2>&1)"; local rc=$?
	if [ $rc -ne 0 ] && printf '%s\n' "$out" | grep -qF "$want"; then echo "✓ $label"; else echo "✗ $label（反向が FAIL しない：exit $rc）"; fail=$((fail + 1)); fi
}
echo "模式：$MODE$([ $SEALS -eq 1 ] && echo '＋封存')"
if [ $GEN -eq 1 ]; then
	"$G" --headless --path . --script res://tools/gen_village_v2.gd > /dev/null 2>&1 || { echo "✗ 產生器失敗"; exit 98; }
	echo "✓ 產生器"
fi
run "freeze check"                         FREEZE  --headless --path . --script res://tools/verify_village_v2_freeze.gd
run "P1 Approved Terrain Protection"       PROTECT --headless --path . --script res://tools/verify_village_v2_p1_protect.gd
run "P2 water gate"                        WATER   --headless --path . --script res://tools/verify_village_v2_water.gd
run "terrain gate（含鋸齒坡、東岸、橋端、農田）" TERRAIN --headless --path . --script res://tools/verify_village_v2_terrain.gd
run "5 bridge checks"                      BRIDGE  --headless --path . --script res://tools/verify_village_v2_bridges.gd
run "sightline checks"                     SL      --headless --path . --script res://tools/verify_village_v2_sightlines.gd
run "P3 roads / parcels gate"               PARCEL  --headless --path . --script res://tools/verify_village_v2_parcels.gd
run "P4 greybox gate"                       GB      --headless --path . --script res://tools/verify_village_v2_greybox.gd
run "P5 asset reset gate（白名單／Protected／封存）" ASSET --headless --path . --script res://tools/verify_village_v2_asset_reset.gd
run "P5 Hero Asset Gate 回歸（已登記資產 1–9 項重驗＋gate.json 雜湊）" HERO --headless --path . --script res://tools/verify_village_v2_hero_gate.gd -- --all
run "P6 町家 Kit Asset Gate 回歸（1–9 項重驗＋gate.json 雜湊）" KIT --headless --path . --script res://tools/verify_village_v2_machiya_kit_gate.gd -- --regress
runneg "P6 町家 Kit Gate 反向：任意の override → 4 材質 FAIL" "FAIL machiya_kit materials" --headless --path . --script res://tools/verify_village_v2_machiya_kit_gate.gd -- --regress --neg=material
runneg "P6 町家 Kit Gate 反向（P10 R6a）：登記変体を Pilot 外の建物へ → FAIL" "FAIL machiya_kit materials" --headless --path . --script res://tools/verify_village_v2_machiya_kit_gate.gd -- --regress --neg=material_offpilot
runneg "P6 町家 Kit Gate 反向（P10 R6a）：登記変体を基底違いの面へ → FAIL" "FAIL machiya_kit materials" --headless --path . --script res://tools/verify_village_v2_machiya_kit_gate.gd -- --regress --neg=material_wrongbase
runneg "P6 町家 Kit Gate 反向（P10 R6a）：変体の sha が登記／封存と不一致 → FAIL" "FAIL machiya_kit materials" --headless --path . --script res://tools/verify_village_v2_machiya_kit_gate.gd -- --regress --neg=material_badsha
run "P7 R2 河岸 Kit Asset Gate 回歸（1–9 項重驗＋gate.json 雜湊＋烘焙＝重排）" RBG --headless --path . --script res://tools/verify_village_v2_riverbank_gate.gd -- --regress
run "P7 R3 河岸石砌 Cleanup Gate（4 條規則：覆蓋空窗／可見 40–70%／浮空與過度外露／2–4 層）" RBSW --headless --path . --script res://tools/verify_village_v2_riverbank_stonework.gd
run "場景擺放／碰撞稽核＋永久反向案例（clean 全 PASS；float／sink／clash→FAIL、aabbfp→PASS、noproxy→REVIEW）" PLACE --headless --path . --script res://tools/audit_village_v2_placement.gd -- --selftest
# --no-review：dev review start（2026-10-03）が F5 を審圖站位へ直入させるため、實走は正式流程（獸道→人間之里）で走らせる
run "19-point walk"                        WALK    --rendering-method gl_compatibility --path . --script res://tools/walk_village_v2.gd -- --no-review
run "P8 封存（凍結來源／overlay／ART_REVIEW 圖／證據 sha256＋反向）" FARM --headless --path . --script res://tools/verify_village_v2_farmland.gd -- --seal
run "P8 local gate（田數、田埂碰撞、水位、灌排、農路淨距）" FARM --headless --path . --script res://tools/verify_village_v2_farmland.gd
run "P8 永久反向（田面水抬 0.5 m → 恰 1 項 FAIL）"  FARM    --headless --path . --script res://tools/verify_village_v2_farmland.gd -- --negative
run "P8 P11 R2D 竜骨車支線 永久反向（支線の水面を逆勾配にする → branch gate が検出）" FARM --headless --path . --script res://tools/verify_village_v2_farmland.gd -- --negative-branch
runneg "P8 P11 R2D-Fix 送り樋 T0 開口 永久反向（開口判定を反転 → FAIL）" "FAIL P11 R2D-Fix T0 tap" --headless --path . --script res://tools/verify_village_v2_farmland.gd -- --negative-feedcut
run "P8 田埂／水面擺放稽核"                    FARM_PLACE --headless --path . --script res://tools/audit_village_v2_farmland_placement.gd
run "P8 取水水路淨空（FarmPath_1／稗田邸前）＋R5b.1 竜骨車：系統狀態〔非表示・無効碰撞・高架樋残骸 0〕・水源連通〔水位鎖単調〕・他層干渉 0" FEEDER  --path . --resolution 1600x900 --script res://tools/walk_village_v2_farmland.gd -- --feeder --no-shots --hour=10
run "P8 R5b.1 FEEDER 永久反向（取水構件の runtime 非表示・碰撞停止・高架樋残骸 → supply_system_state 各案 FAIL）" FEEDER-NEG --path . --resolution 1600x900 --script res://tools/walk_village_v2_farmland.gd -- --feeder-negative --hour=10
run "P13 W3B 土渠美術 gate（N0／T0 支線：地面重み非一様〔旧＝全幅同一の濡れ泥〕・外縁は草・泥水材質・木槽の台〔槽底の隙間 4–20 mm・槽内に土なし・側板の下に隙間なし〕・口の水幅）" CANAL --headless --path . --script res://tools/verify_village_v2_canal_art.gd
run "P13 W3B 土渠美術 永久反向 5 案（uniform／gap／poke／wide／mat が各自の狙った項だけ FAIL）" CANAL --headless --path . --script res://tools/verify_village_v2_canal_art.gd -- --negatives
run "P8 全區 1.7 m 實走 25 段＋TPS 相機淨空"      ZONE    --path . --resolution 1600x900 --script res://tools/walk_village_v2_farmland.gd -- --zone --no-shots --hour=10
run "P8 runtime budget（五鏡位 A/B）"           COST    --path . --resolution 1920x1080 --script res://tools/walk_village_v2_farmland.gd -- --cost --hour=10
run "P9 R1 植被庫封存（樹庫／生成器／LOD 指標／7 張核准總表／證據 sha256＋反向）" VEG --headless --path . --script res://tools/verify_village_v2_veg_gate.gd -- --seal
run "P9 R1 veg_kit Asset Gate 回歸（1–9 項重驗＋gate.json 11 項＋雜湊）" VEG --headless --path . --script res://tools/verify_village_v2_veg_gate.gd -- --regress
run "P9 R1 veg_kit 永久反向 6 案（slab／lod／collision／material／perf／scale 各自 FAIL）" VEG --headless --path . --script res://tools/verify_village_v2_veg_gate.gd -- --negatives
run "P9 R2 林帶封存（規劃器／gate／overlay／4 張 ART_REVIEW 總表／證據 sha256＋反向）" FOREST --headless --path . --script res://tools/verify_village_v2_forest.gd -- --seal
run "P9 R2 林帶 local gate（禁區、接地、檜 secondary、非均勻、杉牆、視線、天際線層級、instance uniform）" FOREST --headless --path . --script res://tools/verify_village_v2_forest.gd
run "P9 R2 林帶永久反向 5 案（hinoki／uniform／float／road／sightline 各自瞄準項 FAIL）" FOREST --headless --path . --script res://tools/verify_village_v2_forest.gd -- --negatives
run "P9 R3 bamboo_kit Asset Gate 回歸（1–9 項重驗＋gate.json 11 項＋雜湊；ART_REVIEW 中）" BAMBOO --headless --path . --script res://tools/verify_village_v2_bamboo_gate.gd -- --regress
run "P9 R3 bamboo_kit 反向 7 案（slab／lod／collision／material／perf／scale／culm_d 各自 FAIL）" BAMBOO --headless --path . --script res://tools/verify_village_v2_bamboo_gate.gd -- --negatives
run "P9 R3 封存（竹 Kit＋竹林擺放 生成器／gate／overlay／8 張 ART_REVIEW 總表／證據 sha256＋掛載＋反向）" BPLACE --headless --path . --script res://tools/verify_village_v2_bamboo_place.gd -- --seal
run "P9 R3 竹林擺放 gate（禁區、接地、R2 共存、踏跡小徑、空間結構、頂線起伏、稈距、instance uniform）" BPLACE --headless --path . --script res://tools/verify_village_v2_bamboo_place.gd
run "P9 R3 竹林擺放永久反向 5 案（road／float／r2／path／dome 各自瞄準項 FAIL）" BPLACE --headless --path . --script res://tools/verify_village_v2_bamboo_place.gd -- --negatives
run "P9 R3 竹林場景級驗證（稈基射線接地、稈碰撞 shape 查詢、小徑實走、節點總數）" BPLACE --headless --path . --script res://tools/verify_village_v2_bamboo_place.gd -- --scene
run "P9 R4 封存（稗田邸庭園 garden_kit＋HiedaGardenP9 生成器／gate／shader／overlay／9 張 ART_REVIEW 總表／證據 sha256＋掛載順序＋反向）" GARDEN --headless --path . --script res://tools/verify_village_v2_hieda_garden.gd -- --seal
run "P9 R4 稗田邸庭園 plan gate（邊界／主軸淨空／前庭留白／池泉／飛石間距／接地／元素齊備）" GARDEN --headless --path . --script res://tools/verify_village_v2_hieda_garden.gd
run "P9 R4 稗田邸庭園永久反向 5 案（float／clutter／axis／pond／wall 各自瞄準項 FAIL）" GARDEN --headless --path . --script res://tools/verify_village_v2_hieda_garden.gd -- --negatives
run "P9 R4 稗田邸庭園場景級驗證（ForestP9／BambooP9／HiedaGardenP9 掛載、射線接地、碰撞 vs 本屋／門／牆、主軸＋飛石實走、池擋人）" GARDEN --headless --path . --script res://tools/verify_village_v2_hieda_garden.gd -- --scene
run "P9 R4-2 封存（神社周邊 生成器／gate／地面 shader／overlay／4 張 ART_REVIEW 總表／證據 sha256＋掛載順序＋反向）" SHRINE --headless --path . --script res://tools/verify_village_v2_shrine_grove.gd -- --seal
run "P9 R4-2 神社周邊 plan gate（參道淨空／接地／村側視線＋R2 社殿天窗／前庭留白／鎮守林連續／非均勻／R2 共存／注連繩貼幹／元素）" SHRINE --headless --path . --script res://tools/verify_village_v2_shrine_grove.gd
run "P9 R4-2 神社周邊永久反向 6 案（road／sight／void／uniform／float／rope 各自瞄準項 FAIL）" SHRINE --headless --path . --script res://tools/verify_village_v2_shrine_grove.gd -- --negatives
run "P9 R4-2 神社周邊場景級驗證（掛載順序 ForestP9→BambooP9→HiedaGardenP9→ShrineGroveP9、射線接地、碰撞、參道＋前庭實走〔P11 R1：歩行面基準＋段差 ≤ 0.45〕）" SHRINE --headless --path . --script res://tools/verify_village_v2_shrine_grove.gd -- --scene
run "P9 R4-2 神社周邊 場景級反向 3 案（P11 R1：參道の箱／斜坡の継ぎ目段差／未登記の台 → 實走 FAIL）" SHRINE --headless --path . --script res://tools/verify_village_v2_shrine_grove.gd -- --scene-negatives
run "P9 R4-3 封存（寺子屋周邊 school_kit＋SchoolYardP9 生成器／gate／地面 shader／overlay／7 張 ART_REVIEW 總表／證據 sha256＋掛載順序＋反向）" SCHOOL --headless --path . --script res://tools/verify_village_v2_school_yard.gd -- --seal
run "P9 R4-3 寺子屋周邊 plan gate（接地／不穿建築／主入口淨空／正面視線／前庭留白≤8 %＋生活小物≤20／植被語彙無杉檜／元素齊備）" SCHOOL --headless --path . --script res://tools/verify_village_v2_school_yard.gd
run "P9 R4-3 寺子屋周邊永久反向 6 案（float／door／facade／conifer／clip／clutter 各自瞄準項 FAIL）" SCHOOL --headless --path . --script res://tools/verify_village_v2_school_yard.gd -- --negatives
run "P9 R4-3 寺子屋周邊場景級驗證（掛載順序 …→ShrineGroveP9→SchoolYardP9、射線接地、碰撞 vs Hero 本體、入口／前庭／側院膠囊實走〔P11 R1：靜的障害＋NPC 動的規則〕）" SCHOOL --headless --path . --script res://tools/verify_village_v2_school_yard.gd -- --scene
run "P9 R4-3 寺子屋周邊 場景級反向 4 案（P11 R1：靜的箱／NPC 待機点／巡回端／ルートに沿う巡回 → FAIL）" SCHOOL --headless --path . --script res://tools/verify_village_v2_school_yard.gd -- --scene-negatives
run "P9 R4-4 封存（水車／龍神像周邊 waterside_kit＋WatersideP9 生成器／gate／overlay／3 張 ART_REVIEW 總表／證據 sha256＋掛載順序＋反向）" WATER --headless --path . --script res://tools/verify_village_v2_waterside.gd -- --seal
run "P9 R4-4 水車／龍神像周邊 plan gate（接地／不穿／動線淨空／Hero 淨空／視線／河岸植生／植被語彙／元素／注連繩 Ø≥0.30 貼幹／作業場原寸留白）" WATER --headless --path . --script res://tools/verify_village_v2_waterside.gd
run "P9 R4-4 水車／龍神像周邊永久反向 8 案（float／road／hero／sight／uniform／conifer／rope／mill 各自瞄準項 FAIL）" WATER --headless --path . --script res://tools/verify_village_v2_waterside.gd -- --negatives
run "P9 R4-4 水車／龍神像周邊場景級驗證（掛載順序 …→SchoolYardP9→WatersideP9、射線接地、碰撞、參拜道＋水車入口實走）" WATER --headless --path . --script res://tools/verify_village_v2_waterside.gd -- --scene
run "P9 R4-5 封存（火見櫓周邊 tower_kit＋TowerYardP9 生成器／gate／overlay／3 張 ART_REVIEW 總表／證據 sha256＋掛載順序＋反向）" TOWER --headless --path . --script res://tools/verify_village_v2_tower_yard.gd -- --seal
run "P9 R4-5 火見櫓周邊 plan gate（接地／不穿／動線淨空／開闊＋塔頂視線／地塊／構圖／元素）" TOWER --headless --path . --script res://tools/verify_village_v2_tower_yard.gd
run "P9 R4-5 火見櫓周邊永久反向 6 案（float／path／tree／parcel／clutter／hero 各自瞄準項 FAIL）" TOWER --headless --path . --script res://tools/verify_village_v2_tower_yard.gd -- --negatives
run "P9 R4-5 火見櫓周邊場景級驗證（掛載順序 …→WatersideP9→TowerYardP9、射線接地、碰撞、進出路＋巡回路＋置き場踏み跡實走）" TOWER --headless --path . --script res://tools/verify_village_v2_tower_yard.gd -- --scene
run "P9 R4-6 封存（鈴奈庵周邊 suzu_kit＋SuzunaanP9 生成器／gate／overlay／4 張 ART_REVIEW 總表／證據 sha256＋掛載順序＋反向）" SUZU --headless --path . --script res://tools/verify_village_v2_suzunaan_yard.gd -- --seal
run "P9 R4-6 鈴奈庵周邊 plan gate（Hero 座標系／接地／不穿／動線淨空／門面視線／地塊・道路／構圖留白／元素）" SUZU --headless --path . --script res://tools/verify_village_v2_suzunaan_yard.gd
run "P9 R4-6 鈴奈庵周邊永久反向 6 案（float／path／facade／parcel／clutter／hero 各自瞄準項 FAIL）" SUZU --headless --path . --script res://tools/verify_village_v2_suzunaan_yard.gd -- --negatives
run "P9 R4-6 鈴奈庵周邊場景級驗證（掛載順序 …→TowerYardP9→SuzunaanP9、射線接地、碰撞、入口軸＋庇下＋北・横丁踏み跡實走）" SUZU --headless --path . --script res://tools/verify_village_v2_suzunaan_yard.gd -- --scene
run "P9 R4-7 封存（鯢吞亭周邊 geidon_kit＋GeidonteiP9 生成器／gate／overlay／4 張 ART_REVIEW 總表／證據 sha256＋掛載順序＋反向）" GEID --headless --path . --script res://tools/verify_village_v2_geidontei_yard.gd -- --seal
run "P9 R4-7 鯢吞亭周邊 plan gate（Hero 座標系／接地／不穿／動線淨空／門面視線／地塊・道路／構圖留白／元素）" GEID --headless --path . --script res://tools/verify_village_v2_geidontei_yard.gd
run "P9 R4-7 鯢吞亭周邊永久反向 6 案（float／path／facade／parcel／clutter／hero 各自瞄準項 FAIL）" GEID --headless --path . --script res://tools/verify_village_v2_geidontei_yard.gd -- --negatives
run "P9 R4-7 鯢吞亭周邊場景級驗證（掛載順序 …→SuzunaanP9→GeidonteiP9、射線接地、碰撞、入口軸＋庇下＋南の踏み跡實走）" GEID --headless --path . --script res://tools/verify_village_v2_geidontei_yard.gd -- --scene
run "P9 R4-8 封存（霧雨店周邊 kiri_kit＋KirisameP9 生成器／gate／overlay／4 張 ART_REVIEW 總表／證據 sha256＋掛載順序＋反向）" KIRI --headless --path . --script res://tools/verify_village_v2_kirisame_yard.gd -- --seal
run "P9 R4-8 霧雨店周邊 plan gate（Hero 座標系／接地／不穿／動線淨空・搬運路／門面視線／地塊・道路／構圖〔大件靠牆・側院外側留白〕／元素）" KIRI --headless --path . --script res://tools/verify_village_v2_kirisame_yard.gd
run "P9 R4-8 霧雨店周邊永久反向 6 案（float／path／facade／parcel／clutter／hero 各自瞄準項 FAIL）" KIRI --headless --path . --script res://tools/verify_village_v2_kirisame_yard.gd -- --negatives
run "P9 R4-8 霧雨店周邊場景級驗證（掛載順序 …→GeidonteiP9→KirisameP9、射線接地、碰撞、入口軸＋庇下＋北の踏み跡＋搬運路實走）" KIRI --headless --path . --script res://tools/verify_village_v2_kirisame_yard.gd -- --scene
run "P9 R5 封存（Groundcover：Pilot r10f＋Macro Pilot m9＋全村 Macro 生成器／shader／overlay／35 張 ART_REVIEW 圖／證據 sha256＋掛載順序＋反向）" GC --headless --path . --script res://tools/verify_village_v2_groundcover.gd -- --seal
run "P9 R5 Groundcover plan gate 37 項（Pilot r10f digest／全村 r5 林緣・溪岸／Macro Pilot＋m9 digest／全村 Macro 禁區・尺度・語意・留白・農田交界・後院・路肩／可見最上面）" GC --headless --path . --script res://tools/verify_village_v2_groundcover.gd
run "P9 R5 Groundcover 永久反向 42 案（Pilot 14／全村 8／Macro 8／MV・Surface・m9 12 各自瞄準項 FAIL）" GC --headless --path . --script res://tools/verify_village_v2_groundcover.gd -- --negatives
run "P9 R5 Groundcover 場景級驗證（掛載順序 …→KirisameP9→GroundcoverP9、地面 overlay・shader・MultiMesh 矩陣；需 rendering display）" GC --path . --script res://tools/verify_village_v2_groundcover.gd -- --scene
run "P10 R1 市集廣場封存（market_kit＋MarketP10 生成器／gate／Kit 網格／overlay／5 張 ART_REVIEW 圖／證據 sha256＋掛載＋反向）" MKT --headless --path . --script res://tools/verify_village_v2_market.gd -- --seal
run "P10 R1 市集廣場 plan gate 9 項（Kit／接地／建物／路面／封存／互不重疊／歩く通り／構圖／NPC anchors）" MKT --headless --path . --script res://tools/verify_village_v2_market.gd
run "P10 R1 市集廣場永久反向 8 案（各自瞄準項 FAIL）" MKT --headless --path . --script res://tools/verify_village_v2_market.gd -- --negatives
run "P10 R1 市集廣場場景級驗證（掛載・接地射線・LOD・碰撞・anchors・MultiMesh 0）" MKT --path . --script res://tools/verify_village_v2_market.gd -- --scene
run "P10 R2 主街 Street Life plan gate 16 項（Kit／接地／建物／店先帯／封存／戸口／水際／互不重疊／通行〔主街中央 ≥ 4.5 m〕／構圖／巷口／市の入口〔主街 4 視點・口の前 3 視點〕／作業場／農田交界／暮らし／NPC anchors）" STR --headless --path . --script res://tools/verify_village_v2_street.gd
run "P10 R2 主街 Street Life 永久反向 13 案（各自瞄準項 FAIL）" STR --headless --path . --script res://tools/verify_village_v2_street.gd -- --negatives
run "P10 R2 主街 Street Life 場景級驗證（掛載 MarketP10→StreetP10・MarketP10 封存雜湊・接地射線・LOD・碰撞・anchors・MultiMesh 0）" STR --path . --script res://tools/verify_village_v2_street.gd -- --scene
run "P10 R2 主街 r5 封存（ART_APPROVED 2026-10-07：street_kit＋StreetP10 生成器／gate／網格／overlay／ART_REVIEW 圖 4／證據 sha256＋掛載＋字の向き 0＋竄改反向；封存中 --build 拒否）" STR --headless --path . --script res://tools/verify_village_v2_street.gd -- --seal
run "字の向き監査（street_kit／market_kit／mise_kit／寺子屋：幟・暖簾・提灯・看板の字の面が表裏とも鏡像・逆さま 0；例外は測定理由つき）" TXT --headless --path . --script res://tools/audit_village_v2_text_facing.gd -- --strict --only=street_kit,market_kit,mise_kit,terakoya
run "P10 R1b Market West r3 封存（ART_APPROVED：雜湊 124 檔＋依存〔P10 R1・P9 R5 限定解封〕＋掛載＋裁定 10 項・店の灯 18＋竄改反向 2）" MW --headless --path . --script res://tools/verify_village_v2_market_west.gd -- --seal
run "P10 R1b Market West（裏通り）r3 営業中 plan gate 21 項（Kit／建物／地塊／接地／掛け物／路面・店先帯／封存／水際／互不重疊／歩く通り／戸口／到達／視線〔主の口→茶屋・路地 1→呉服〕／構圖／NPC anchors／床／市集の北西角の視野／店内〔店台・奥の棚・店の灯〕／営業中〔北 ≥ 4・南 ≥ 2、店先の連続 ≥ 0.6〕／主次〔focal 2–3〕／入口の誘い）" MW --headless --path . --script res://tools/verify_village_v2_market_west.gd
run "P10 R1b Market West r3 永久反向 19 案（各自瞄準項 FAIL）" MW --headless --path . --script res://tools/verify_village_v2_market_west.gd -- --negatives
run "P10 R1b Market West r3 場景級驗證（掛載順・MarketP10 封存雜湊・接地射線・LOD・建物 Kit・床・掀げた暖簾と店の灯・碰撞・anchors・MultiMesh 0）" MW --path . --script res://tools/verify_village_v2_market_west.gd -- --scene
run "P9 R5-3 封存（MeadowP9 立ち草：生成器／gate／shader〔wind 0.7〕／overlay／ART_REVIEW 圖・wind GIF／證據 sha256＋掛載順序＋反向）" MDW --headless --path . --script res://tools/verify_village_v2_meadow.gd -- --seal
run "P9 R5-3 MeadowP9 場景級驗證（掛載順序 …→GroundcoverP9→MeadowP9、近中級・shader・碰撞 0・MultiMesh 矩陣；需 rendering display）" MDW --path . --script res://tools/verify_village_v2_meadow.gd -- --scene
run "P9 R5-4 EnvironmentP9 全村 plan gate 13 項（既存資產のみ／分工語彙／MeadowP9 株位〔同 seed〕／接地／禁區〔P10 +1.5 m・anchors +1.2 m〕／戸口／階層／非展示／間隔／邊界邏輯／大留白／P10 優先／村邊／中尺度／R5 Macro Ground）" ENV --headless --path . --script res://tools/verify_village_v2_environment.gd
run "P9 R5-4 EnvironmentP9 場景級驗證（Props 掛載 MarketP10→StreetP10→MarketWestP10→EnvironmentP9・個別ノード・MultiMesh 0）" ENV --path . --script res://tools/verify_village_v2_environment.gd -- --scene
run "P9 R5-4 封存（EnvironmentP9 生成器／gate／機位／overlay／audit／ART_REVIEW 圖／證據 sha256＋Props 掛載順＋反向；封存中 --build 拒否）" ENV --headless --path . --script res://tools/verify_village_v2_environment.gd -- --seal
run "P9 FINAL SEAL（P9_CLOSED：R1–R5 子封存檔 14 件の sha256＋Vegetation／Props 掛載順＋R5 final 狀態＋反向）" P9F --headless --path . --script res://tools/verify_village_v2_p9_final.gd
run "永久 build rule：全場景 MultiMesh instance transform 非零（各 overlay 分組＋零矩陣反向＋非空；需 rendering display）" MMBAKE --path . --script res://tools/verify_village_v2_multimesh_bake.gd
run "P10 R3a NPC Prototype（普通町人・男 chonin_m01、使用者 Tripo）技術 gate：部位 5・humanoid 骨格・共通 idle／walk ループ・三角・外部材質 3・身長 1.65–1.70・全フレーム接地・首胴不伸＋wrapper（美術判定ではない）" NPC --headless --path . --script res://tools/verify_npc_prototype.gd
run "P10 R3a NPC Prototype 反向 4 案（部位欠落・1.1 倍・首伸び・10 cm 浮き）" NPC --headless --path . --script res://tools/verify_npc_prototype.gd -- --negatives
run "P10 NPC Asset Library（9 体・npc_roster.json）技術 gate 11 項/体：部位 skin・skeleton mapping〔family BoneMap 全割当・profile 親子〕・選定 clip（idle／walk ループ）・三角・外部材質・指定身長 ±5 mm・全フレーム接地・首胴不伸・root motion なし・wrapper（美術判定ではない）" NPCLIB --headless --path . --script res://tools/verify_npc_library.gd
run "P10 NPC Asset Library 反向 7 案（部位欠落・1.05 倍・首伸び・10 cm 浮き・root drift・別 clip・骨の割当外れ）" NPCLIB --headless --path . --script res://tools/verify_npc_library.gd -- --negatives
run "P10 NPC Asset Library 封存（ART_APPROVED 2026-10-06）：凍結 410・原素材 24・ART_REVIEW 35・證據 77 の雜湊＋封存外ファイルなし＋正式パラメータ（arm-space・布料老闆娘 UV 復元／2048・主婦 apron +4.0 cm）＋竄改反向" NPCLIB --headless --path . --script res://tools/verify_npc_library.gd -- --seal
run "P10 R3b ART_APPROVED baseline seal（來源／snapshot／原圖／證據／子封存雜湊＋mount scope＋永久竄改反向）" POP --headless --path . --script res://tools/verify_village_v2_population.gd -- --seal
run "P10 R3b Population Pilot plan（16 人、三區、職業／重複／婆婆／小群／接地／render geometry／patrol／步速／sealed overlays）" POP --headless --path . --script res://tools/verify_village_v2_population.gd
run "P10 R3b Population Pilot 永久反向 9 案（各自瞄準項 FAIL）" POP --headless --path . --script res://tools/verify_village_v2_population.gd -- --negatives
run "P10 R3b Population Pilot scene（掛載／NPC instance／TPS 同模型 ≤ 2／runtime／SpringArm）" POP --headless --path . --script res://tools/verify_village_v2_population.gd -- --scene
run "P10 R3c／R3c.1 Activity baseline seal（ART_APPROVED 2026-10-07）：凍結・證據・審圖圖・子封存（R3b／NPCLIB）雜湊＋7 指派〔2026-10-16 茶屋少女 Drink 削除〕／道具參數＝overlay＋掛載 1 つ＋永久竄改反向" ACT --headless --path . --script res://tools/verify_p10_activity.gd -- --seal
run "P10 R3d 核心人口 封存（ART_APPROVED 2026-10-07：39 人 roster・五區・R3b 不變・新增 23 の位置／朝向／activity／patrol・南側入口 3 人・EntranceCueP10 小幟 2・證據・審圖・子封存 R3b／R3c／NPCLIB の雜湊＋掛載順＋場景＝snapshot＋竄改反向；封存中 --build／--attach 拒否）" CORE --headless --path . --script res://tools/verify_village_v2_population_core.gd -- --seal
run "P10 R3d 核心區人口 plan（R3b＋R3d 30–40 人・密度順・核心區・anchor・職業・歩く人・同モデル ≥ 8 m・構圖・接地・體・往復路・步速・承認 vocabulary・封存只讀）" CORE --headless --path . --script res://tools/verify_village_v2_population_core.gd
run "P10 R3d 核心區人口 反向 12 案（各自瞄準項 FAIL）" CORE --headless --path . --script res://tools/verify_village_v2_population_core.gd -- --negatives
run "P10 R3d 核心區人口 scene（人數＝scope 別の身元 39〔R3b＋R3d〕・多一人／少一人／重複の反向・R3d 単獨〔R3e を外す〕でも 39；掛載順・人數・Activity 再生・道具・審圖鏡位同モデル ≤ 2・歩く人 30 秒；非 headless）" CORE --rendering-method forward_plus --path . --script res://tools/verify_village_v2_population_core.gd -- --scene
run "P10 R3e 外圍人口 封存（ART_APPROVED 2026-10-07：外圍 12 人＝最終基準・各區・位置／朝向・activity・patrol 端點・密度環単調下降・森林／山腳 0 人・依存 R3d／R3c／R3b／NPCLIB 雜湊＋掛載順＋場景＝snapshot＋竄改反向 3；封存中 --build／--attach 拒否）" OUTER --headless --path . --script res://tools/verify_village_v2_population_outer.gd -- --seal
run "P10 R3e 外圍人口 Pilot plan（人數・區域・密度勾配単調下降・外圍不成群・anchor・職業・歩く人・同モデル・接地・體・往復路・步速・封存 vocabulary・R3d 雜湊）" OUTER --headless --path . --script res://tools/verify_village_v2_population_outer.gd
run "P10 R3e 外圍人口 反向 13 案（各自瞄準項 FAIL）" OUTER --headless --path . --script res://tools/verify_village_v2_population_outer.gd -- --negatives
run "P10 R3e 外圍人口 scene（人數＝外圍の身元 12＋村人口 51〔scope 外・重複なし〕・反向；掛載順・人數・Activity 逐フレーム・審圖鏡位・歩く人；非 headless）" OUTER --rendering-method forward_plus --path . --script res://tools/verify_village_v2_population_outer.gd -- --scene
run "P10 R3c Activity plan（16 人・7 指派・4 類）" ACT --headless --path . --script res://tools/verify_p10_activity.gd -- --plan
run "P10 R3c Activity 反向（停止／root／空 clip／長さ 0／道具脫離／隱藏／17 人）" ACT --headless --path . --script res://tools/verify_p10_activity.gd -- --negatives
run "P10 R4 Human-Use Pilot plan gate（3 Pilot・既存資產優先＋缺件 6・中型の輪郭・who/why/anchor・依附・禁區〔P8・水・NPC・Env +1.6・MeadowP9 株 0〕・接地・成組・非均一）＋反向 16" HUSE --headless --path . --script res://tools/verify_village_v2_human_use.gd -- --negatives
run "P10 R4 Human-Use Pilot 場景級驗證（root 直下 Props の次に HumanUseP10・Props の子は封存どおり・個別ノード・MultiMesh／Marker3D 0・Population 不変・擺放〔3×3 ray 接地・collide_shape 貫通〕＋float／clash 反向）" HUSE --headless --path . --script res://tools/verify_village_v2_human_use.gd -- --scene
run "P10 R4 Human-Use Pilot 封存（ART_APPROVED 2026-10-08：A／B／C・10 cluster 50 件 snapshot＝場景〔位置・朝向・who／why／anchor〕・root 掛載 Props の次・Props の子は封存どおり・凍結／證據／審圖／子封存 R3d・R3e・P9F 等の雜湊＋竄改反向 3；封存中 --build／--attach 拒否）" HUSE --headless --path . --script res://tools/verify_village_v2_human_use.gd -- --seal
run "P10 R4b Human-Use Expansion Batch 1 A/B FINAL plan gate（正式 10 群＝A 農田 5・B 住宅 5・C 水岸擴張 0〔ART_REJECTED〕・計画＝封存 snapshot・重用＋缺件・中型の輪郭・who/why/anchor・依附・禁區〔R4 全禁區＋核心商業區＋R4 の 50 件／Pilot 区〕・見えている最上面に接地・成組・非均一・自然の岸）＋反向 19〔rejected_c() を戻す・hx_doroage を置く を含む〕" HUX --headless --path . --script res://tools/verify_village_v2_human_use_exp.gd -- --negatives
run "P10 R4b Human-Use Expansion Batch 1 A/B FINAL 場景級驗證（root 直下 HumanUseP10 の次に HumanUseExpansionP10・Props の子は封存どおり・正式 10 群／C 0／ZoneC なし・個別ノード・MultiMesh／Marker3D 0・R4 の 50 件 snapshot 不変・Population 51 不変・擺放〔3×3 ray 接地・collide_shape 貫通〕＋float／clash 反向）" HUX --headless --path . --script res://tools/verify_village_v2_human_use_exp.gd -- --scene
run "P10 R4b Human-Use Expansion Batch 1 A/B FINAL 封存（使用者 2026-10-08：A・B ART_APPROVED／C 水岸 ART_REJECTED＝除去・理由を記録・40 件 snapshot＝場景＝承認時 r3 の A/B・C 群／hx_doroage なし・R4 の 50 件不変・NPC 51・凍結／證據／審圖／rejected candidates／子封存雜湊＋竄改・移動・who・C 戻し反向；封存中 --build／--attach 拒否）" HUX --headless --path . --script res://tools/verify_village_v2_human_use_exp.gd -- --seal
run "P10 R5c World Edge Closure plan gate＋反向 4（frame 外 Vista：P1 邊緣頂點接縫 ≤ 0.01 m・vista 頂點全在 frame 外・TPS 視點 294／射線 25852 看見世界盡頭 0・水系延續〔水位單調・接口＝P2・匯入／會合〕・樹〔水中／陡坡／frame 內 0〕・地形 ≤ 140k 三角；反向 rim／seam／tree／water）" EDGE --headless --path . --script res://tools/verify_village_v2_edge_closure.gd
run "P10 R5c World Edge Closure 場景級（root 直下 HumanUseExpansionP10 の次に EdgeClosureP10 1 個・CollisionObject3D 0・Collision/Boundary 4 牆不變・VistaTerrain frame 內頂點 0・MultiMesh 零矩陣 0；非 headless）" EDGE --path . --script res://tools/verify_village_v2_edge_closure.gd -- --scene
run "P10 R5c World Edge Closure 封存（使用者 2026-10-09 ART_APPROVED：雜湊・掛載・林帯／遠景の描画・竄改反向；封存中 --build 拒否）" EDGE --headless --path . --script res://tools/verify_village_v2_edge_closure.gd -- --seal
run "P10 R6a 材質亮度基準＋街區調色盤 Pilot plan gate＋反向 9（來源材質＝0.42 灰／校正只改 albedo（Kit atlas＝等價 shader：木 0.75／屋根灰 0.42 不變／漆喰 0.70）／色卡 luma 在目標帶／Pilot 24 棟兩區・≤ 25 %／調色盤飽和 ≤ 0.22・鄰棟不同組；反向：帶色・等幅提亮・區外・全村・改粗糙度・Hero・Kit 屋根提亮・過飽和・全同組）" ALB --headless --path . --script res://tools/verify_village_v2_albedo_pilot.gd
run "P10 R6a 材質亮度基準 Pilot 場景級（root EdgeClosureP10 の次に AlbedoPilotP10・Pilot 建物の來源材質表面全覆寫・Pilot 外 0・enabled 開關還原・_matlib／kit 來源雜湊＝build 時；非 headless）" ALB --path . --script res://tools/verify_village_v2_albedo_pilot.gd -- --scene
run "P10 R6a ROUND 3 Kit 專用校正材質 合法変体 gate＋反向 6（登記表 18 変体 ↔ 檔案 sha256・基底との差＝albedo_color／Kit atlas＝k だけ・飽和 ≤ 0.22・明度帯・承認済み 24 棟と同値・場景の Kit override＝登記変体だけ／Pilot 24 棟だけ／他 163 棟 0・_matlib／P6 Kit 原檔 git 未変更；Kit Gate は不変）" KITM --headless --path . --script res://tools/verify_village_v2_kit_material.gd
run "P10 R6a Kit Material 24 Buildings Pilot 封存（使用者 2026-10-09 ART_APPROVED：雜湊〔登記表・変体 18・shader・overlay〕・掛載・材質＝登記変体だけ・Pilot 24 棟・竄改反向）" ALB --headless --path . --script res://tools/verify_village_v2_albedo_pilot.gd -- --seal
run "P10 R5a Ground Pilot plan gate＋反向 7（封存 ground.gdshader 雜湊＝matlib.json・補丁 7 段逐字（ROUND 2：再生道 UV2.y の区間別の使われ方）・pilot shader 可重現・田格移除・discard 只在外緣侵蝕／參道挖洞・新參數預設＝舊行為・道路參數在核准範圍・外緣實測 sd 0.08–0.45 m）" GRD --headless --path . --script res://tools/verify_village_v2_ground_pilot.gd
run "P10 R5a Ground Pilot 場景級（AlbedoPilotP10 の次に GroundPilotP10・地形 4＋道路 4 換 pilot shader・原參數逐一保留・非 Pilot 道路不變・enabled 開關・雜湊；非 headless）" GRD --path . --script res://tools/verify_village_v2_ground_pilot.gd -- --scene
run "P10 R5b Water Pilot plan gate＋反向 9（ROUND 3 純動力水車：揚水部材 0・下端の動き·水渠下流 ≥ 0.9・葉板浸水 0.15–0.80・主泡は出水側・P8 取水に触れない〔R5b.1：高架落とし樋は P8 で撤去・竜骨車へ置換、overlay が隠す／止める P8 ノード 0、P8 高架部材は竜骨車だけ〕・表裏・小舟・繫船杭・荷）" WLF --headless --path . --script res://tools/verify_village_v2_water_life.gd
run "P10 R5b Water Pilot 場景級（GroundPilotP10 の次に WaterLifeP10・ROUND 3：揚水部材 0・輪が回り下端は下流へ・水車 1／3 不動・P8 取水構件は overlay の有無で不変〔全部表示・碰撞有効〕・碰撞 2；非 headless）" WLF --path . --script res://tools/verify_village_v2_water_life.gd -- --scene
run "P10 R6b Shrine Approach plan gate＋反向 8（ROUND 2：石段 ≥ 80・蹴上 0.12–0.20・踏面 0.25–0.45／長い段 0.45–1.2／踊り場 1.2–2.0・地形不蓋踏面・斜坡碰撞與踏面差 ≤ 半蹴上＋0.03・≤ 38°・寬度／二の鳥居淨空・一の鳥居・燈籠・NPC 不在石段・リズム〔踊り場 3・盛土 ≤ 1.2 m・休みなし ≤ 60 段・丘の肩の長い段 ≥ 3〕）" SAN --headless --path . --script res://tools/verify_village_v2_shrine_approach.gd
run "P10 R6b Shrine Approach 場景級（WaterLifeP10 の次に ShrineApproachP10・參道 ribbon 挖洞・中心線射線＝斜坡碰撞／地形・enabled 開關；非 headless）" SAN --path . --script res://tools/verify_village_v2_shrine_approach.gd -- --scene
run "P10 R6b ROUND 3 參道 walkable-surface gate＋反向 5（足場＝最上面の歩ける面〔P1 地形／斜坡碰撞〕：斜坡と見える踏面 ≤ 半蹴上＋0.03・玩家膠囊淨空〔中心＋左右〕・0.25 m ごとの高さ連続 ≤ tan(floor_max_angle)・踊り場の縁／両脇・NPC 巡回不横切り・正式 TPS 相機が石／地形に入らない〔腕の縮み回数は INFO〕・P9 R4-2 同經路を最上面基準で被擋 0；P9 R4-2 封存 gate は不変）" SWALK --headless --path . --script res://tools/verify_village_v2_sando_walkable.gd
run "P10 R4c Prop Fix plan gate＋反向 5（st_hasa_v2 規格：竿×半束 ≥ 0.010・束頭坐竿上・束×束 ≥ 0.005・脚×束 ≥ 0.010・網格＝manifest・與 st_hasa 同尺度；A2 籠 移位後も接地〔地面＝TerrainCollision〕・視線・碰撞；N4 籠不動・N5 籠沈む）" R4C --headless --path . --script res://tools/verify_village_v2_prop_fix.gd
run "P10 R4c Prop Fix 場景級（ShrineApproachP10 の次に PropFixP10・st_hasa 全換 v2・enabled 還原；非 headless）" R4C --path . --script res://tools/verify_village_v2_prop_fix.gd -- --scene
run "P10 R4c Straw Geometry Pilot 封存（使用者 2026-10-09 ART_APPROVED：雜湊・掛載・st_hasa_v2 差し替え 18・A2 移位 1 件＝R4 snapshot・竄改反向）" R4C --headless --path . --script res://tools/verify_village_v2_prop_fix.gd -- --seal
run "P10 R5a ROUND 3 Road Base Pilot plan gate＋反向 7（ROUND 3：P7 地形 FarmlandTerrain の踩み固め重みを再生道に合わせて局部修正〔COLOR.r だけ・対象 3 本の旧い帯が支配する頂点だけ・旧い帯 ≤ 0.6 倍〕；小範囲 3 本 ≤ 450 m・元の路幅の中・地形なり〔芯＋0.02–0.07／縁 −0.03–0〕・定規の直線でない・水の上の切れ目を保つ・南橫街の町の区間は元の三角形・交差点の上下 ≥ 0.012・NPC 地形の上）" RDB --headless --path . --script res://tools/verify_village_v2_road_base.gd
run "P10 R5a ROUND 3 Road Base Pilot 場景級（PropFixP10 の次に RoadBaseP10・3 本の mesh＋FarmlandTerrain 差し替え・材質＝pilot shader のまま・道に碰撞なし・P9 地被／立ち草の浮き 0・enabled 開關で元の mesh；非 headless）" RDB --path . --script res://tools/verify_village_v2_road_base.gd -- --scene
run "P10 R5a Road Base 416 m Pilot 封存（使用者 2026-10-09 ART_APPROVED：雜湊〔元の road_*.res／terrain_farmlandterrain.res 含む〕・掛載・再現性＝生成器で記憶體内再生成→封存 overlay と配列一致・地形 COLOR.r 577 頂点・竄改反向）" RDB --headless --path . --script res://tools/verify_village_v2_road_base.gd -- --seal
echo "回歸失敗項目：$fail（跳過 $skipped 項；模式 $MODE）"
exit $fail
