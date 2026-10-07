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
# 用法（repo 根目錄，git-bash）：  bash godot/tools/run_village_v2_regression.sh [--gen]
#   --gen   先重新產生場景再驗證
# 任一項非 0 退出 → 整體退出碼 = 失敗項目數。固定鏡位擷取另見 docs/plans/2026-09-23-人間之里V2重製規劃.md §9.5。
set -u
cd "$(dirname "$0")/.." || exit 99
G="${GODOT:-D:/Godot/Godot_v4.7.2-stable_win64_console.exe}"
fail=0
run() {  # $1 標籤, $2 grep 前綴, 其餘為 Godot 參數
	local label="$1" tag="$2"; shift 2
	local out; out="$("$G" "$@" 2>&1)"; local rc=$?
	printf '%s\n' "$out" | grep -E "^\[$tag\] (FAIL|結果)|SCRIPT ERROR|Parse Error"
	if [ $rc -ne 0 ]; then echo "✗ $label（exit $rc）"; fail=$((fail + 1)); else echo "✓ $label"; fi
}
if [ "${1:-}" = "--gen" ]; then
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
run "P7 R2 河岸 Kit Asset Gate 回歸（1–9 項重驗＋gate.json 雜湊＋烘焙＝重排）" RBG --headless --path . --script res://tools/verify_village_v2_riverbank_gate.gd -- --regress
run "P7 R3 河岸石砌 Cleanup Gate（4 條規則：覆蓋空窗／可見 40–70%／浮空與過度外露／2–4 層）" RBSW --headless --path . --script res://tools/verify_village_v2_riverbank_stonework.gd
run "場景擺放／碰撞稽核＋永久反向案例（clean 全 PASS；float／sink／clash→FAIL、aabbfp→PASS、noproxy→REVIEW）" PLACE --headless --path . --script res://tools/audit_village_v2_placement.gd -- --selftest
# --no-review：dev review start（2026-10-03）が F5 を審圖站位へ直入させるため、實走は正式流程（獸道→人間之里）で走らせる
run "19-point walk"                        WALK    --rendering-method gl_compatibility --path . --script res://tools/walk_village_v2.gd -- --no-review
run "P8 封存（凍結來源／overlay／ART_REVIEW 圖／證據 sha256＋反向）" FARM --headless --path . --script res://tools/verify_village_v2_farmland.gd -- --seal
run "P8 local gate（田數、田埂碰撞、水位、灌排、農路淨距）" FARM --headless --path . --script res://tools/verify_village_v2_farmland.gd
run "P8 永久反向（田面水抬 0.5 m → 恰 1 項 FAIL）"  FARM    --headless --path . --script res://tools/verify_village_v2_farmland.gd -- --negative
run "P8 田埂／水面擺放稽核"                    FARM_PLACE --headless --path . --script res://tools/audit_village_v2_farmland_placement.gd
run "P8 取水水路淨空（FarmPath_1／稗田邸前）"     FEEDER  --path . --resolution 1600x900 --script res://tools/walk_village_v2_farmland.gd -- --feeder --no-shots --hour=10
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
run "P9 R4-2 神社周邊場景級驗證（掛載順序 ForestP9→BambooP9→HiedaGardenP9→ShrineGroveP9、射線接地、碰撞、參道＋前庭實走）" SHRINE --headless --path . --script res://tools/verify_village_v2_shrine_grove.gd -- --scene
run "P9 R4-3 封存（寺子屋周邊 school_kit＋SchoolYardP9 生成器／gate／地面 shader／overlay／7 張 ART_REVIEW 總表／證據 sha256＋掛載順序＋反向）" SCHOOL --headless --path . --script res://tools/verify_village_v2_school_yard.gd -- --seal
run "P9 R4-3 寺子屋周邊 plan gate（接地／不穿建築／主入口淨空／正面視線／前庭留白≤8 %＋生活小物≤20／植被語彙無杉檜／元素齊備）" SCHOOL --headless --path . --script res://tools/verify_village_v2_school_yard.gd
run "P9 R4-3 寺子屋周邊永久反向 6 案（float／door／facade／conifer／clip／clutter 各自瞄準項 FAIL）" SCHOOL --headless --path . --script res://tools/verify_village_v2_school_yard.gd -- --negatives
run "P9 R4-3 寺子屋周邊場景級驗證（掛載順序 …→ShrineGroveP9→SchoolYardP9、射線接地、碰撞 vs Hero 本體、入口／前庭／側院膠囊實走）" SCHOOL --headless --path . --script res://tools/verify_village_v2_school_yard.gd -- --scene
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
run "P10 R2 主街 Street Life 永久反向 14 案（各自瞄準項 FAIL）" STR --headless --path . --script res://tools/verify_village_v2_street.gd -- --negatives
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
run "P10 R3c／R3c.1 Activity baseline seal（ART_APPROVED 2026-10-07）：凍結・證據・審圖圖・子封存（R3b／NPCLIB）雜湊＋8 指派／道具參數＝overlay＋掛載 1 つ＋永久竄改反向" ACT --headless --path . --script res://tools/verify_p10_activity.gd -- --seal
run "P10 R3c Activity plan（16 人・8 指派・5 類）" ACT --headless --path . --script res://tools/verify_p10_activity.gd -- --plan
run "P10 R3c Activity 反向（停止／root／空 clip／長さ 0／道具脫離／隱藏／17 人）" ACT --headless --path . --script res://tools/verify_p10_activity.gd -- --negatives
echo "回歸失敗項目：$fail"
exit $fail
