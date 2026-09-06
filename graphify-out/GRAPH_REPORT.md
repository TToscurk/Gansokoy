# Graph Report - docs  (2026-09-01)

## Corpus Check
- Large corpus: 31 files · ~642,235 words. Semantic extraction will be expensive (many Claude tokens). Consider running on a subfolder.

## Summary
- 204 nodes · 225 edges · 15 communities (14 shown, 1 thin omitted)
- Extraction: 71% EXTRACTED · 28% INFERRED · 2% AMBIGUOUS · INFERRED: 62 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- 村落住商建築
- 町家製作與街區重建
- 河川水路整合
- Godot 遷移與執行架構
- 河童技術與商業街
- 河岸護岸與農業水利
- 村落俯視地景
- 村落交通與功能分區
- 遠景與世界呈現
- 世界生成領域模型
- 稗田宅邸系統
- 村落生活機能分區
- 江戶住宅建築類型
- 人間之里住商概念
- 日常取水生活

## God Nodes (most connected - your core abstractions)
1. `市集主要店舖群` - 11 edges
2. `住宅區` - 10 edges
3. `Human Village Art Direction Specification` - 7 edges
4. `Human Village Concept Art Authority` - 7 edges
5. `Godot 4.7 Live Build` - 6 edges
6. `Terrain Domain Vocabulary` - 6 edges
7. `Human Village Current Specification` - 6 edges
8. `分層塊石護岸` - 6 edges
9. `村落概念設計圖：功能分區規劃` - 6 edges
10. `市集核心區` - 6 edges

## Surprising Connections (you probably didn't know these)
- `Terrain Domain Vocabulary` --semantically_similar_to--> `Terrain and Height Sampling`  [INFERRED] [semantically similar]
  archive/domain-model-full-history-2026-08-11.md → domain-model.md
- `Land and Parcel Domain Vocabulary` --semantically_similar_to--> `Parcel and Transport Concepts`  [INFERRED] [semantically similar]
  archive/domain-model-full-history-2026-08-11.md → domain-model.md
- `WaterBody Domain Vocabulary` --semantically_similar_to--> `Water Building and Prop Concepts`  [INFERRED] [semantically similar]
  archive/domain-model-full-history-2026-08-11.md → domain-model.md
- `Hieda Estate Feature List` --semantically_similar_to--> `Hieda Estate Current Specification`  [INFERRED] [semantically similar]
  archive/hieda-estate-features-production-history-2026-08-11.md → hieda-estate-features.md
- `Four Branch Water System` --semantically_similar_to--> `Four Level Water Hierarchy`  [INFERRED] [semantically similar]
  plans/町中水路重做計畫.md → 新人里規劃提案.md

## Hyperedges (group relationships)
- **Human Village Rebuild Authority Chain** — docs_project_state_village_new_baseline, docs_ningen_no_sato_village_current_spec, docs_village_concept_reference_concept_reference, docs_village_art_direction_village_art_spec [EXTRACTED 1.00]
- **Village Water Reconstruction** — docs_plans_machi_canal_slice_integration_canal_slice_plan, docs_plans_canal_redesign_plan, docs_river_sync_2026_08_26_river_sync, docs_water_hierarchy [INFERRED 0.85]
- **Historical Generator Domain Knowledge** — docs_archive_domain_model_full_history_2026_08_11_generator_adr_strategy, docs_domain_model_generator_domain_model, docs_archive_ningen_no_sato_production_history_2026_08_10_map_validation_pipeline [INFERRED 0.85]
- **中央市集場景** — docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_shang_di_qu_market_street, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_shang_di_qu_central_square, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_shang_di_qu_market_stall_kits, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_shang_di_qu_red_market_parasol, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_shang_di_qu_villagers [EXTRACTED 1.00]
- **公共核心至田園外圈的空間梯度** — docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_shang_di_qu_central_square, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_shang_di_qu_market_street, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_shang_di_qu_residential_area, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_shang_di_qu_back_alleys, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_shang_di_qu_farming_area, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_shang_di_qu_lively_to_quiet_gradient [EXTRACTED 1.00]
- **模組化環境資產系統** — docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_shang_di_qu_building_variations, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_shang_di_qu_market_stall_kits, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_shang_di_qu_everyday_life_vignettes, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_shang_di_qu_edo_material_palette [INFERRED 0.85]
- **人間之里住宅類型系統** — docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_zhai_gai_nian_tu_poor_machiya, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_zhai_gai_nian_tu_standard_machiya, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_zhai_gai_nian_tu_merchant_machiya, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_zhai_gai_nian_tu_farmhouse, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_zhai_gai_nian_tu_wealthy_machiya, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_zhai_gai_nian_tu_nagaya, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_zhai_gai_nian_tu_storehouse, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_zhai_gai_nian_tu_special_machiya [EXTRACTED 1.00]
- **基底建築、材質與生活道具的模組化資產系統** — docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_zhai_gai_nian_tu_architecture_concept_sheet, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_zhai_gai_nian_tu_modular_detail_props, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_zhai_gai_nian_tu_material_palette, docs_reference_ren_jian_zhi_li_gai_nian_tu_zhu_zhai_gai_nian_tu_lived_in_human_warmth [INFERRED 0.85]
- **防洪灌溉生活景觀整合系統** — docs_reference_renjianzhili_xinbanshuihuan_flood_level_design, docs_reference_renjianzhili_xinbanshuihuan_irrigation_channel, docs_reference_renjianzhili_xinbanshuihuan_water_access_node, docs_reference_renjianzhili_xinbanshuihuan_water_coexistence [EXTRACTED 1.00]
- **聚落硬岸至農田軟岸過渡** — docs_reference_renjianzhili_xinbanshuihuan_village_life_bank, docs_reference_renjianzhili_xinbanshuihuan_layered_revetment, docs_reference_renjianzhili_xinbanshuihuan_agricultural_ecological_bank, docs_reference_renjianzhili_xinbanshuihuan_local_materials [INFERRED 0.85]
- **鳥居至丘頂神社的儀式軸線** — docs_reference_________________foreground_torii, docs_reference_________________main_street, docs_reference_________________torii_path, docs_reference_________________shrine_hill [INFERRED 0.55]
- **水力生產與農業灌溉系統** — docs_reference_________________western_ponds_and_falls, docs_reference_________________eastern_waterway, docs_reference_________________watermills, docs_reference_________________wooden_bridges, docs_reference_________________rice_fields [INFERRED 0.75]
- **聚落交易與生產生活系統** — docs_reference_________________main_street, docs_reference_________________machiya_core, docs_reference_________________market_square, docs_reference_________________rice_fields, docs_reference_________________watermills [INFERRED 0.85]
- **村落四大機能分區系統** — docs_reference_ren_jian_zhi_li_gai_nian_tu_cun_luo_nong_cun_gai_nian_fu_shi_qu_yu_fen_ge_market_zone, docs_reference_ren_jian_zhi_li_gai_nian_tu_cun_luo_nong_cun_gai_nian_fu_shi_qu_yu_fen_ge_mixed_use_zone, docs_reference_ren_jian_zhi_li_gai_nian_tu_cun_luo_nong_cun_gai_nian_fu_shi_qu_yu_fen_ge_residential_zones, docs_reference_ren_jian_zhi_li_gai_nian_tu_cun_luo_nong_cun_gai_nian_fu_shi_qu_yu_fen_ge_farmland_zone [EXTRACTED 1.00]
- **地形水系交通骨架** — docs_reference_ren_jian_zhi_li_gai_nian_tu_cun_luo_nong_cun_gai_nian_fu_shi_qu_yu_fen_ge_main_river, docs_reference_ren_jian_zhi_li_gai_nian_tu_cun_luo_nong_cun_gai_nian_fu_shi_qu_yu_fen_ge_irrigation_network, docs_reference_ren_jian_zhi_li_gai_nian_tu_cun_luo_nong_cun_gai_nian_fu_shi_qu_yu_fen_ge_bridge_network, docs_reference_ren_jian_zhi_li_gai_nian_tu_cun_luo_nong_cun_gai_nian_fu_shi_qu_yu_fen_ge_main_road [INFERRED 0.85]
- **農業商業居住互補循環** — docs_reference_ren_jian_zhi_li_gai_nian_tu_cun_luo_nong_cun_gai_nian_fu_shi_qu_yu_fen_ge_farmland_zone, docs_reference_ren_jian_zhi_li_gai_nian_tu_cun_luo_nong_cun_gai_nian_fu_shi_qu_yu_fen_ge_market_zone, docs_reference_ren_jian_zhi_li_gai_nian_tu_cun_luo_nong_cun_gai_nian_fu_shi_qu_yu_fen_ge_mixed_use_zone, docs_reference_ren_jian_zhi_li_gai_nian_tu_cun_luo_nong_cun_gai_nian_fu_shi_qu_yu_fen_ge_residential_zones [INFERRED 0.75]
- **山水至工房與照明的水力動力鏈** — docs_reference___________________youkai_mountain, docs_reference___________________river_and_hydraulics, docs_reference___________________street_drainage_channel, docs_reference___________________waterwheel_workshop, docs_reference___________________hydroelectric_street_lamp [INFERRED 0.85]
- **町家、妖怪與河童技術的三層視覺身份** — docs_reference___________________traditional_machiya_language, docs_reference___________________human_youkai_coexistence, docs_reference___________________kappa_heavy_industries_technology [EXTRACTED 1.00]

## Communities (15 total, 1 thin omitted)

### Community 0 - "村落住商建築"
Cohesion: 0.10
Nodes (25): 人間之里住宅區與市集建築設計概念圖, 農家（郊區型）, 魚屋, 花屋, 八百屋, 人間之里, 布料・吳服屋, 不同町家與生活煙火氣共同塑造人情味 (+17 more)

### Community 1 - "町家製作與街區重建"
Cohesion: 0.10
Nodes (21): Blender Machiya Asset Workflow, Machiya Production Kit, Modular Machiya Architecture, Machiya Facade Variation, Machiya Kit Production History, Machiya Roof Families, Village Map Validation Pipeline, Village Street Reconstruction (+13 more)

### Community 2 - "河川水路整合"
Cohesion: 0.10
Nodes (21): Village Landmark Scale, Organic Narrow Alley Settlement, Human Village Redesign, Asset Origin Placement Rule, Five Layer Canal Bank Section, Town Irrigation Canal Redesign Plan A, Four Branch Water System, Canal Node Migration (+13 more)

### Community 3 - "Godot 遷移與執行架構"
Cohesion: 0.12
Nodes (19): Active Documents Take Precedence, Archive Document Policy, Web to Godot Baking Pipeline, Blender Hero Asset Pipeline, Three.js to Godot Hybrid Migration, Native Godot Scene Priority, Current Project Priorities, Godot 4.7 Live Build (+11 more)

### Community 4 - "河童技術與商業街"
Cohesion: 0.14
Nodes (18): 白日人類生活與夜間妖怪氣息的雙面性, 河童製龍神像, 人間之里（鈴奈庵周邊）共同視覺概念圖, 人與妖怪共存但保持距離, 水力小型發電機與河童式路燈, 河童重工水力與機械技術, 商業街與石板主街, 市場與屋台 (+10 more)

### Community 5 - "河岸護岸與農業水利"
Cohesion: 0.14
Nodes (18): 農業生態岸, 小型分水閘門, 護岸排水系統, 水位與防洪設計, 灌溉引水渠, 分層塊石護岸, 在地材料與傳統工法, 水田農業區 (+10 more)

### Community 6 - "村落俯視地景"
Cohesion: 0.15
Nodes (16): 坡地針葉林帶, 河岸巨型黑色地標, 東側水路, 前景朱紅大鳥居, 町屋商業核心, 聚落主街, 中央開放市庭, 日式山谷聚落 (+8 more)

### Community 7 - "村落交通與功能分區"
Cohesion: 0.18
Nodes (15): 跨河橋梁網, 互補共生的村落結構, 農田生產區, 丘頂神社, 農田灌溉支渠網, 蜿蜒主河川, 村落主幹道, 市集核心區 (+7 more)

### Community 8 - "遠景與世界呈現"
Cohesion: 0.18
Nodes (11): Continuous Day and Weather Cycle, Two Stage Draw Call Optimization, Three.js Hakurei Shrine, World Map Connections, Border Vista Design, Shared Global Landmarks, Three Layer Vista Technique, Reversible Art Review Batches (+3 more)

### Community 9 - "世界生成領域模型"
Cohesion: 0.24
Nodes (10): Depth Over Breadth, Incremental Domain Model Extraction, Land and Parcel Domain Vocabulary, Geometry and Walkability Tests, Terrain Domain Vocabulary, WaterBody Domain Vocabulary, Generator Domain Model, Parcel and Transport Concepts (+2 more)

### Community 10 - "稗田宅邸系統"
Cohesion: 0.22
Nodes (10): Hieda Backyard Garden, Hieda Estate Feature List, Three Floor Interior Narrative Axis, Hieda MultiMesh Optimization, Restrained Surreal Estate Direction, Hieda Courtyard Contract, Hieda Estate Art Direction, Hieda Generation and Validation (+2 more)

### Community 11 - "村落生活機能分區"
Cohesion: 0.25
Nodes (8): 裏路地・生活路, 中央廣場（市）, 農作區・田畑, 市場陳設型錄, 市場通（商店・露店）, 朱紅市集大傘, 住居區（町屋・長屋）, 村民與市集活動

### Community 12 - "江戶住宅建築類型"
Cohesion: 0.40
Nodes (5): 建築變體型錄, 江戶風材質語彙, 町屋（商店兼住居）, 長屋, 茅葺農家住宅

### Community 13 - "人間之里住商概念"
Cohesion: 0.40
Nodes (5): 寺社・共同設施, 人間之里, 熱鬧至安靜的空間梯度, 人間之里・住商地區概念圖, 櫻花與紫陽花的季節歧義

## Ambiguous Edges - Review These
- `人間之里・住商地區概念圖` → `寺社・共同設施`  [AMBIGUOUS]
  reference/人間之里概念圖/住商地區.PNG · relation: conceptually_related_to
- `人間之里・住商地區概念圖` → `櫻花與紫陽花的季節歧義`  [AMBIGUOUS]
  reference/人間之里概念圖/住商地區.PNG · relation: conceptually_related_to
- `聚落主街` → `前景朱紅大鳥居`  [AMBIGUOUS]
  reference/人間之里概念圖/村落農村概念俯視.png · relation: conceptually_related_to
- `東側水路` → `西側池沼與跌水`  [AMBIGUOUS]
  reference/人間之里概念圖/村落農村概念俯視.png · relation: shares_data_with

## Knowledge Gaps
- **70 isolated node(s):** `Next Roadmap Work`, `Geometry and Walkability Tests`, `Restrained Surreal Estate Direction`, `Hieda Backyard Garden`, `Hieda MultiMesh Optimization` (+65 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 89 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `人間之里・住商地區概念圖` and `寺社・共同設施`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `人間之里・住商地區概念圖` and `櫻花與紫陽花的季節歧義`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `聚落主街` and `前景朱紅大鳥居`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `東側水路` and `西側池沼與跌水`?**
  _Edge tagged AMBIGUOUS (relation: shares_data_with) - confidence is low._
- **Why does `Human Village Current Specification` connect `町家製作與街區重建` to `稗田宅邸系統`, `河川水路整合`?**
  _High betweenness centrality (0.101) - this node is a cross-community bridge._
- **Why does `Human Village Concept Art Authority` connect `町家製作與街區重建` to `遠景與世界呈現`, `河川水路整合`?**
  _High betweenness centrality (0.086) - this node is a cross-community bridge._
- **Why does `Godot 4.7 Live Build` connect `Godot 遷移與執行架構` to `町家製作與街區重建`?**
  _High betweenness centrality (0.061) - this node is a cross-community bridge._