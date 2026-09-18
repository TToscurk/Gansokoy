# PROJECT STATE

Last updated: 2026-09-16.

This file is intentionally short. It contains only facts that should affect the next task. Load subsystem details only when that subsystem is being edited.

## Save / load (2026-09-15)

- `systems/save/save_manager.gd` (autoload `SaveManager`): `user://save_<slot>.json`,
  3 slots + rolling `.bak`. Stores **plain data only** — story flags, quest progress
  (id + objective index + state), current map / position / yaw. It deliberately does
  NOT store `QuestData`: definitions live in `res://` and travel with the build, so
  serialising them would break every old save whenever a quest is edited.
  `Vector3` is split into x/y/z (JSON does not round-trip Vector3).
- `version` field + `_migrate()` hook. A file with no `version` is treated as corrupt;
  a *newer* version is read anyway (fields are read with defaults). Overwrite copies
  the old file to `.bak` first; a corrupt primary falls back to the backup.
- `deserialize` validates every entry (saves are user-editable text): missing quest →
  dropped; objective index past the end (definition got shorter) → marked completed so
  no un-advanceable quest is left; negative progress clamped to 0; orphan pending dropped.
- ⚠ `StoryFlags.deserialize` / `QuestManager.deserialize` emit **no signals**. Measured
  reason: setting `spared_wounded_yokai` makes `WoundedYokaiEvent` believe the player just
  chose 靠近 — it replays the kedama flee and re-reports the quest event with the player
  20 m away. `main._on_load_requested` pokes the UI once after the data is in place.
- UI: `ui/save/save_menu.tscn` — Esc opens, ↑↓ select, Enter act, Tab save/load, Del delete.
  Overwriting an existing save needs a second Enter (slot turns red-brown). F5/F9 = quick
  save/load on slot 1. `main.save_to_slot()` / `load_from_slot()` are the single path.
- ⚠ The Esc contest with the map UI is solved by the group `modal_ui`, **not** by mount
  order. `_unhandled_input` reaches the LAST-added node first, so ordering gave the wrong
  result in practice (map would not close, menu opened on top of it).
- Gates: `tools/verify_save_load.gd` (30, API/corruption/tamper/migration/signal isolation),
  `tools/verify_save_menu.gd` (44, incl. an InputMap-action existence check — a typo'd
  action name silently does nothing), `tools/verify_save_live.gd` (11, two-phase: real save,
  then a separate process with `--continue`; drift 0.000 m, yaw error 0.000 rad).
- Not built: no save UI beyond this menu; combat state (health/posture/breath) is not saved.

## Prologue quest bugs fixed (2026-09-15)

Found by simulating real player movement, not scripted happy paths. All six have regression
tests in `tools/verify_quest_flow.gd` (now 31 checks):

- **Core dialogue was skippable.** The 拜殿 interaction had no prerequisite, so a player
  could reach the shrine during MQ00 and burn Reimu's whole `first_*` branch; `met_reimu`
  then let early-arriving events instantly complete MQ05/MQ06, and a revisit only showed the
  2-line `repeat` branch — the prologue's thematic pivot («妖怪，不代表它該死» plus the
  wounded-kedama callback) was lost silently. `WorldInteraction` gained `require_flag` /
  `require_quest`; 拜殿 is gated on MQ05. The guard sits inside `interact()` itself, not
  just `_unhandled_input` — that method is public and story scripts call it directly.
- **`_pending` never expired or de-duplicated** (walking back retained 3 entries, repeat
  dialogue accumulated to amount=3). Now only events that `_event_index` says a future quest
  still needs are stored, capped at that objective's `required_amount`.
- **`_tracked` could stick on a completed quest** when `next_quest_id` pointed at something
  already done. Broken chains now fall back to `_first_active()`.
- **Input hygiene**: `amount=-3` used to subtract from progress, `amount=0` counted as
  handled, `report_event(99, …)` left permanent debris in `_pending`, and `MQ00`/`mq00` built
  two separate active entries. All rejected at the entry point.
- **Wounded-yokai deadlock**: with `wounded_yokai_played` already set, `_on_enter` returned
  early while that area is the only source of `trail_wounded_yokai` — MQ03 stuck forever.
  Re-entry now re-reports (QuestManager de-duplicates).

## Test-suite notes (2026-09-15)

Two long-standing gate failures turned out to be **test bugs, not product bugs**. Recorded so
they are not "fixed" in the engine again:

- `verify_story_slice` P2d was intermittent (~1/7). It drove dialogue with
  `_press("ui_accept")`, but `DialogueUI` treats `ui_accept` as *confirm this choice* when
  choices are visible, so it selected 靠近/離開 before the assertion could count them.
  Use `dm.advance()` to step dialogue in tests. Now 6/6 clean.
- `verify_hud_autohide` reported "交手後 HUD 浮出 alpha=0.859". The headless frame delta
  is not 1/60, so waiting a fixed 40 frames never reaches alpha 1.0 (the fade is
  `delta/hud_fade_time`). Test now waits until the alpha saturates or times out.
  A/B verified: the failure predates the 2026-09-16 combat work (baseline = 0.859).
- `verify_yoriichi_player` reported "緣一不會走路" (0.00 m). The player is locked twice at
  cold start: OpeningFade's black hold/fade, then the `yoriichi_wake` monologue it triggers.
  The fade is a Tween on `process_frame`, so a pure `physics_frame` loop never advances it —
  call `OpeningFade.skip()` then drain the dialogue. In an isolated scene the same input
  moves 4.00 m (= walk speed).

## Current Build

- Live game: **Godot 4.7** under `godot/` (`project.godot` features = 4.7; older docs saying 4.4 are historical).
- `src/` is the frozen three.js line.
- Human Village scene: `godot/maps/village/village.tscn` plus committed artifacts in `godot/maps/village/gen/`.
- **Active work happens in `godot/maps/slice/slice.tscn`**, not `village.tscn`. The slice
  is where B1/B2/B3 rounds, the canal, the east river and the collision work live; it is
  hand-tuned by the user between rounds and is now ~27 MB of scene text.
- **Published on GitHub**: `origin` = `https://github.com/TToscurk/Gansokoy.git`. Active branch
  is `yoriichi-combat-and-village-routing` (in sync with its remote as of 2026-09-09).
  Multiple sessions push this same branch: local is authoritative, push with
  `--force-with-lease`; fallback `origin/backup/remote-before-force-push-20260907`.
  Git LFS is in use — binaries must be pulled/checked out before Godot opens the project.

## Slice status (2026-09-04)

- Content is at capacity: 13,001 nodes / 6,483 visible meshes / ~44 M triangles.
  70 machiya, 14 landmarks, 2 torii, 415 water pieces, 208 trees, 3,118 ground-cover,
  2,609 rocks, 14 street lamps. `tools/survey_slice_content.gd` regenerates this census.
- Performance after the decimation pass (2026-09-09): visible triangles down to **18.77 M**
  and main street to **58 fps** (was 44 M / 43-44 fps on 09-04). Remaining hot spots are
  `B1_Street` and `MachiCanal` at ~27 % each. Tools: `tools/decimate_meshes.gd`,
  `tools/gen_manual_collision.gd`, `tools/bench_slice.gd`, `tools/probe_glb.gd`, and
  `data/slice_manual_collision.json`. Further cuts are a visual trade-off and need a
  user ruling, not an agent decision.
- Collision is complete and verified: 23/23 probe audit, 17/17 real-controller walk,
  675-sample ground-gap probe at zero deviation. Bodies: 71 convex hulls (avg 83 verts),
  15 cylinders (14 lamps), 10 trimeshes.
- Collision scenes are **binary `.scn`** (`gen/ground_collision.scn`,
  `building_collision.scn`, `lamp_collision.scn`). Text `.tscn` has no import cache, so
  it is re-parsed from decimal on every launch; the switch took F5 from 30.1 s to 19.3 s.
- Generators bake from **disk**, so `slice.tscn` must be saved in the editor before any
  `gen_*_collision.gd` run — otherwise hand-tuned positions bake at their old coordinates
  (this happened: 鯢吞亭 was 90 m out).
- Unused assets remaining: `assets/riverbank/` 9 (the paddy-field set: 稻作株, 水田一格,
  畦道, 洗物石段, 水車小屋, 木樋支撐棚架, 水車(窄), 收頭件大/小) and `assets/bridges/` 3
  (the live bridge is `imported_models/Stonebound Wooden Bri_1`). Using the paddy set
  means opening a whole new field area, not dressing the existing one.
- `check_map.gd -- slice` reports 12 issues; `tools/triage_check_map.gd` shows 10 of the
  11 "water buried underground" hits are false — the canal is a *dug* channel, so its
  water sits below village grade by design. The 2 empty MultiMesh layers
  (`GrassFlower`/`GrassTall`, 0 instances) are real leftovers superseded by `草筆刷_*`.

## Human Village — new baseline (user ruling 2026-08-26)

- The 170-house era is **fully retired and deleted (2026-08-25)** — generator pipeline (`gen_town.gd`, `tools/town/`, `make_town.py`, `make_machiya.py`, `town_modules.json`) **and the machiya assets, market, village gates, and portals**. None of these exist in the repo. Do not look for them, restore them, or treat docs describing them as current.
- **The current `village.tscn` IS the new baseline** (user ruling): landmarks 鎮守之杜, 稗田邸(+後院), 鈴奈庵, 寺子屋, 霧雨店, 鯢吞亭, 龍神像; 14 路燈; vegetation; vista; terrain; boundary. ~221 nodes. Future village content builds on top of this.
- The village is a **frozen, committed scene**: edit `village.tscn` / its `gen/` artifacts directly, following normal art-review gates.
- Remaining live generators: `gen_hieda*.gd`, `gen_kourindou.gd`, `gen_trail_v2.gd`, `gen_textures.gd`, `gen_charpreview.gd` + Blender `make_hieda/shourou/trees/props/hedge/chars.py`.
- Known naming wart: scene nodes and `gen/` folder use 「裨田邸」 (typo) for 稗田邸. Renaming touches scene references — leave as-is unless a task explicitly fixes it.
- Visual changes still require prototype → render → Human Art Review → rollout.
- Next major art direction is lighting / cel-shading.

## Beast Trail (獸道) v2 重構完成 (2026-09-04)

- **定位與規格**：南端（人里入口）至北端（神社傳送點）全線蛇行漸窄（路寬 2.8m → 1.3m），劃分 10 個張弛段落（農田/柵欄 → 界碑森林 → 密林1 → 疏段地藏 → 密林2 → 小溪木橋 → 獸道大空地 → 密林3妖怪痕跡 → 夜雀屋台 → 深處妖怪領域）。
- **產生器**：`godot/tools/gen_trail_v2.gd` 產出 `maps/trail/trail.tscn`（節點約 30,700 個、樹幹碰撞 1,080+ 根）。
- **自然與美術校正**：
  1. 樹種分配：闊葉 42%、松 33%、杉 20%、老歪樹 3%、枯樹 2%。前半段老樹全面覆寫綠葉，僅深處極稀疏紅葉。
  2. 密林感：樹木重兵配置在路沿 3.2m ~ 55m 帶狀區（路沿樹達 3,840+ 棵），營造林蔭穹頂。
  3. 空地與視線保護：空地半徑擴至 17m，古樹偏心置放並採自然綠葉闊葉巨木（CommonTree_1）；路心、屋台周圍與大空地完全禁入高草/大灌木，路面結實清晰。
  4. 螢火蟲粒子：白晝 `emitting = false`，光色柔綠微縮，消除黃色發光方塊。
- **測試驗收**：`walk_test.gd -- trail` 通過（0 條路線不通，BFS 全線暢通）；`check_map.gd -- trail` 水面正常開挖；截圖集存於 `docs/art_review/trail_v2/`。
- **傳送點**：`data/trail.meta.json` 的 portals 已改成新主脊兩端 —— 北 (8.64, 9.06, −313.6) → `shrine`、南 (9.56, 0.29, 320.0) → `village`，各帶 `arrival_ground_y`（玩家落在傳送點往圖心退 4 m 處，該處地面較高）。`connections` 與 `mapRegistry.json` 同步線性化；舊的 1,635 筆樹幹碰撞已清空（場景帶 `own_colliders`）。
- **實機自檢**：`main.gd --playtest`（走完整開機流程後驗傳送區生成與貼地、玩家出生落地、主脊 7 點可站立性）。獸道結果 0 項失敗。⚠ 不能用獨立 `--script` 工具做這件事：那模式下 autoload 不建立，`main.gd._ready` 中途即斷。
- **狀態：可接受、未定版**（使用者 2026-09-04 裁決，**非** `ART_APPROVED`）。之後可能回頭改。
- **Meshy 待補件**：界碑×2、警告牌、夜雀小木牌、地藏×7、石燈籠、路標×3、倒木×7、古樹 Hero、屋台 Hero、木橋。全部有 `Marker3D` + `meshy` meta 寫好尺寸與風化要求，資產到位可直接替換。

## check_map 誤報修正 (2026-09-04)

`check_map.gd` 兩個誤報來源已修，slice 從 11 個問題降到 1 個真問題：

- **地面高度場只讀 `Terrain`**。slice 同時有 `Terrain`（舊地形，河床沒挖，水路一帶 +0.3 m）與 `UnifiedGround`（`gen_terrain_river.gd` 產出，含河床 −3.4 m）。只讀前者導致 11 個水面全被報「100% 埋在地下」，而實拍水路正常。改成 `GROUND_MESHES` 列出的網格全部併入同一高度場。
- **刻意清空的 MultiMesh 被當成漏做**。`GrassTall`／`GrassFlower` 是使用者 2026-08-29 判定「彩度過高、尺寸過大」後由 `tools/clear_bright_grass.gd` 清成 0 實例的，節點保留以便還原。加 `INTENTIONALLY_EMPTY` 白名單。

**slice 剩下的 1 個真問題（使用者裁決本輪不修）**：幹渠上游 z≈104 附近渠道沒挖到底 —— `UpstreamWater` 水面 −2.29 m、該處地面僅 −0.47 m，實拍確認畫面上水渠斷掉、草地蓋過。`Reach_Lower` 在 (287, −20) 同樣是平地上的水面。屬水路整合當時的既有缺口。診斷工具：`probe_slice_ground_pair.gd`、`probe_slice_water_gap.gd`。

## Prologue / story systems (2026-09-06 - 09-09)

- Main-quest data lives in `godot/data/quests/mq00.tres` - `mq04.tres`, `mq07.tres`,
  chained by `next_quest_id`: MQ00 陌生之地 -> MQ02 攔路的野獸 -> MQ03 害怕我的東西 ->
  MQ04 山上的巫女 -> MQ07 人間之里. 純走路的 MQ01，以及同一場靈夢對話拆出的
  MQ05／MQ06 已刪除；MQ04 現在以兩個目標完成「抵達神社 → 與靈夢初見」。
  MQ02 **is a fight again** (user ruling 2026-09-16: real-time combat stays). It uses one
  objective, `DEFEAT trail_wolf` (the 山犬遭遇 `CombatEncounter` at the clearing's north rim).
  戰後獸骨只作非任務環境觀察，不再要求玩家再踩一次痕跡區。
- Systems: `systems/quest/{quest_manager,quest_data,quest_objective}.gd`,
  `systems/dialogue/dialogue_manager.gd`, `systems/story/story_flags.gd` (autoload, bool only),
  `systems/save/save_manager.gd`. Dependency direction is one-way:
  WorldInteraction -> DialogueManager -> QuestManager -> StoryFlags; SaveManager sits above
  QuestManager/StoryFlags and calls their serialize/deserialize. Persistence exists as of
  2026-09-15 (see the Save / load section) — older notes saying "no save-file" are historical.
- UI: `ui/quest/quest_tracker.gd`, `ui/dialogue/dialogue_ui.gd`, `ui/opening/opening_fade.gd`
  (black hold 1.4 s, fade 2.2 s, monologue starts only after the fade completes).
- Story props: `components/story/{fleeing_yokai_group,wounded_yokai_event,dropped_fruit}.gd`;
  `characters/yokai/kedama.gd` FLEE state serves MQ03.
- Verification helpers: `tools/verify_story_slice.gd`, `tools/shot_opening.gd`, `tools/_shot_story.gd`.
- Design docs: `docs/plans/2026-09-07-角色NPC任務UI規劃.md`, `docs/plans/sekiro_combat_spec.md`.

## Combat (2026-09-06 - 09-16)

- **2026-09-16 user ruling: the combat system stays REAL-TIME (Sekiro-style) and is
  deepened. The 2026-09-15 "moving to turn-based (FF-style)" note is VOID** — it had
  been written into `mq02.tres`, `trail_interactions.tscn`, `PROJECT_STATE`,
  `verify_quest_flow.gd` and `verify_story_slice.gd`; all five are updated. Nothing
  turn-based was ever designed or built.
- Sekiro-style posture system `characters/combat/posture.gd`; enemies
  `enemy_samurai`, `enemy_wolf`, `training_dummy` under `characters/combat/`.
- 山犬 is now `assets/enemies/wolf/wolf_pounce.glb` (single tail, 46 bones, 6 clips).
  Live enemy in the world as of 2026-09-16: `CombatEncounter`
  (`components/combat/combat_encounter.gd`, runtime spawner with quest/dialogue hooks)
  is instanced in `maps/trail/trail_interactions.tscn` as 山犬遭遇 at
  **(-14.08, -40.03)** — the clearing's north rim. `main.gd` now calls
  `combat.rescan_enemies()` after every `load_map`, so runtime-spawned enemies reach
  the HUD. MQ02 is again `DEFEAT trail_wolf` → then `REACH trail_predator_sign`.
- ⚠ **遭遇區的邊界要用「膠囊半徑」算，不是用中心點算。** 第一版 `arena`
  盒深 26 m（南緣 z=-27.03）與序章醒來點 z=-26.82 只差 0.21 m —— 玩家膠囊
  r=0.3 一伸就重疊，`body_entered` 在**開機那一**觸發：狼在醒來獨白之前撲上來，
  HUD 一亮、序章 P0 四項（淡入期間不得有對話框、第一／二句台詞、woke_in_trail）
  全部失敗。盒深改 18 m（南緣 z=-31.03，離醒來點 4.2 m）後 12/12 全過。
  診斷手法：開機 60 幀後印 `get_nodes_in_group("enemies").size()` 與 HUD alpha。
- **Where a fight can actually happen is a measured quantity.** Tool:
  `tools/probe_combat_space.gd` (真碰撞體、玩家膠囊、二分搜尋最大淨空圓), output
  `data/combat_spaces.json`. Measured after the 2026-09-16 venue pass:
  | 場地 | 淨空半徑（改前 → 改後） |
  |---|---|
  | 獸道大空地中心 | **0.00 m → 12.00 m** ✓ |
  | 獸道空地北緣 | 7.00 → **12.50 m** ✓ |
  | 獵食者痕跡 (z-62) | 5.50 → 9.75 m（戰鬥袋中心 3.75 m，見下） |
  | 神社前庭南帶 / 東翼 / 參道 | 3.75 / 1.75 / 4.75 m ✗ |
  | 人里 寺子屋南外（村內最大） | 9.75 m ✗ |
  | 人里 村門內 / 火見櫓南 / 東岸農地 / 龍石像橋西岸 | 4.75 / 1.75 / 4.75 / 0.00 m ✗ |
  **人里目前沒有任何一處符合規格（R12）** — 這是「遇到敵人的位置很尷尬」的根因。
  Spec: see `.hermes/plans/2026-09-16_031308-緣一戰鬥落地.md` §2.
- 空地為什麼改得動：古樹 Hero 的碰撞（CylinderShape r1.6 h8.0）原本距空地中心
  **1.80 m** → 淨空半徑 0.20 m；`gen_trail_v2.gd` 新增 `COMBAT_CORE_R = 15.0`
  與 `_push_out_of_core()`，把古樹／地藏／燈籠／陶罐／苔石／倒木沿方位角推到核心外
  （古樹不刪，只搬家）。CLEARING_R 17 → 22、角度擾動 0.25/0.15 → 0.12/0.08。
- 獵食者戰鬥袋（`T_FIGHT = 0.7719`, `FIGHT_R = 13.0`）**未完成**：已壓平（起伏 0.00 m）
  但袋內仍有一尊地藏（4.46 m）與一段走廊碰撞牆（12.9 m），袋中心淨空只有 3.75 m。
  待下一輪：`_jizo_base()` 的擺放點要一起過 `_push_out_of_core()`（`_plan_jizo_sites`
  已改，`_build_human_traces` 的實際擺放尚未），走廊牆的 `play_half` 在該段與實測不符。
- Dissolve death (`wolf_dissolve.gdshader`) is accepted. The 牙通牙 spin VFX
  (`wolf_gatsuga.gdshader`) **failed agent self-review** — the semi-transparent cone does not
  hide the body underneath. Superseded by the new model's own Pounce (per project notes).

## Yoriichi

- The old procedural Y02 rebuild track is obsolete and must not be treated as the active character workflow.
- Active character prefab: `角色/緣一動作/yoriichi_character_meshy_full.tscn`.
- Body and Haori use the same 24-bone Meshy skeleton.
- Runtime locomotion, draw/sheathe, attacks, dodge/roll, jump/fall/land, sword sockets, and the current AnimationTree controller have been implemented and validated at the character-project level.
- Yoriichi **is** the formal Player in `godot/` (since 2026-09-03 — the line above was
  stale). Read `docs/yoriichi-runtime.md` only when working on Yoriichi.
- **2026-09-16 gap fixes (both verified)**: (1) the project had **zero invincibility
  frames** (`grep invuln|i_frame|無敵` = 0 hits) — rolling gave no protection even though
  the dodge-counter (伍ノ型) depends on it. `yoriichi_character.gd` gained
  `dodge_invuln_start/end` (roll progress, half-open `[start, end)`, so `end = 0` really
  disables it) and `in_dodge_invuln()`; gate `tools/verify_dodge_iframes.gd` (17 checks,
  including both endpoints). (2) getting hit had no feedback beyond numbers —
  `_apply_hit_reaction()` + `vfx/hit_feedback.gd` now do knockback (1.6 / 0.6 / 0.15 m for
  hit / block / deflect), hitstun (0.25 s, its own timer — `input_locked` is left alone as
  the dialogue/transition control), and camera shake via `Camera3D.h_offset/v_offset`
  (never the transform, which the user hand-tunes). Gate: `tools/verify_hit_feedback.gd`
  (22 checks incl. endpoints). `character_audio.gd` also gained `play_deflect` /
  `play_block` / `play_hurt` — `take_hit()` had been calling `has_method("play_deflect")`
  for months, so **deflects had never made a sound**.
- Deathblow now spawns `CombatVFX.spawn_deathblow_burst()` (white-gold, 48 particles) on
  both enemies and shakes the player camera; `enemy_samurai.take_hit()` interrupts
  `STRIKE` as well as `WINDUP` (previously a struck samurai mid-swing simply ignored it).
- **2026-09-18 RMB 長按 = 蓄力拔刀斬（居合）**（`yoriichi_character.gd` export group
  `Heavy Charge (RMB 長按)`, `heavy_charge_*`; VFX `vfx/heavy_charge_fx.gd`）。短按仍是
  原聚力單斬（同一支 clip、零延遲）；按住 → atk1 舉刀到進度 0.27 → 切 **full 層居合架勢**
  （`Iai_Stance`：Blender MCP 手調 `tools/blender/iai_lib.py`，沉腰 12 cm、雙手疊握低橫身前
  的刀、頭平視；upper 層 filter 不含腿/Hips 所以蹲姿必須全身 clip）→ 蓄 **2 s**（刀身
  emission override 升溫、內聚火星、中段暖光）→ 滿蓄閃光＋拔刀音 → **放開才衝**
  （`heavy_charge_auto_release` 預設 false；自動衝是可選端點）→ 對鎖定／最近敵人衝刺
  （≤ 8 m、煞停 1.3 m、衝不到的不當目標；無敵人朝面向衝 4 m）→ 抵達前 0.06 s 切
  full 層 `Iai_Slash`（拔刀斬）以 2.6× 落刀，傷害 2.5× / 軀幹 2.0×、加長火焰刀光。
  未滿放開 = 淡掉架勢、重放一段普通聚力單斬（atk1 在蓄力中早已播完，無「續播」可言）。
  蓄力進姿段可慢走瞄準、架勢後腳步紮穩；翻滾取消、受擊／死亡／對話鎖／跳躍／格擋／
  忍殺一律擋掉或收乾淨。動畫管線：`iai_clips.glb` → `build_react_clips.gd`（同反應 clip
  管線；Stance 用 `anchor_first` 錨 Idle 端髖高）→ `yoriichi_iai_{stance,slash}.res`。
  Gate `tools/verify_heavy_charge.gd`（93 checks，含端點、auto/manual、所有取消路徑）；實機連拍
  `tools/capture_heavy_charge_ingame.gd`（要視窗，加 `--audio-driver Dummy`）。
  **同輪兩個範圍較廣的修正**：(1) `_on_hit_target` 先解析 receiver 再去重 —— 敵人本體
  body_entered ＋ Hurtbox area_entered 以前各算一次，**一刀打兩次**（實測 35 → 70），修掉後
  所有帶 Hurtbox 的敵人（武士、山犬）受傷減半，平衡待使用者裁定；(2) `_fire_upper` 改看
  `internal_active` 而非 `active`：上一招淡出期間 `active` 仍 true，只換段落不 FIRE 會讓新招跟著
  淡掉（實拍：上一刀剛收就 RMB 蓄力，舉刀 0.24 s 後整層回 Idle）。

## Village Rebuild — active work (2026-08-26)

- 視覺基準：`docs/reference/人間之里概念圖/村落農村概念俯視.png`（使用者裁決 2026-08-30，
  **圖本身是權威**）。圖上實況：市集主街貫穿村心、北面林丘社寺為視覺終點、
  西半住宅、東半農田＋大宅、東北河中平台立龍神像、細渠與水車穿行村內。
  `docs/village-concept-reference.md` 已於 2026-08-30 依圖校正（舊版有多處錯誤轉錄，
  含虛構的中央龍神廣場、北緣墓地、南緣 U 形河，已作廢）。
  ⚠️ slice 現行沿南緣的 U 形河**在概念圖上沒有依據**，出自使用者 2026-08-26 的
  獨立裁決，屬刻意偏離。
- River rework in progress on `maps/slice/slice.tscn`: ring/narrow versions v1–v5 were **rejected by the user (too narrow, not U-shaped)**; current candidate is `river_open_u` v6b (`shots2/river_open_u_v6b_*_20260826`), awaiting Human Art Review.
- River art card (user, 2026-08-26): **deep moat-like channel, stone-textured revetment, vegetation + trees along the banks**. The procedurally generated bridge is **placeholder only — do not treat it as final**; the user will replace it with a Meshy-made bridge.
- v7 pass applied on slice (2026-08-26 afternoon): 22 bank trees (round/pine/sakura mix at the three bridge areas, node `RiverV3_Candidate/RiverBankTrees`), stone revetment materials assigned (`river_ishigaki_dry.tres` on Dry banks, `river_ishigaki_wet.tres` on Wet banks; shared `2F岸石.tres` untouched). Shots: `shots2/river_open_u_v7*_20260826`.
- Bank trees were removed again on user order (2026-08-26 evening): trees/vegetation will come from Meshy; do not plant the existing tree_* GLBs along the river.
- A GPT repair attempt (2026-08-26, `repair_river_outer_transition.gd`, mesh swaps on Vista/OuterTerrainTransition, hidden vista trees) was **rejected by the user and fully reverted**; it is archived in `work_backups/gpt_river_attempt_20260826/` and is NOT part of the current scene.
- Second defect found the same way: `VillageLandExtension`, `EastTail/WestTailLandConnection`, `OuterTerrainTransition` shipped with **no material at all** (rendered white). Patched: earth on the extensions/tails, grass on the transition.
- Water is CLEAN — probe audit confirms `RiverWater` covers only the channel; earlier oversized-water suspicion was wrong.
- Materials ready: `river_ishigaki_dry.tres` / `river_ishigaki_wet.tres` (stone revetment, triplanar) and `river_transition_grass.tres` (double-sided matte grass) in `assets/materials/`. Audit tool kept at `godot/tools/audit_river_slice.gd`. The large arch visible at the east edge belongs to the pre-existing root `Vista` mesh, not the river banks; an A/B hide test exposed world void, so `Vista` remains unchanged pending a dedicated landscape-vista replacement.
- **v9 landscape pass (2026-08-26 night)**: continuous ground achieved — `GroundUnderlay` node (generated by `tools/gen_ground_underlay.gd`, 5m grid sampled 0.22m under every ground mesh, dips below the river bed inside the channel) fills all sky-holes between Terrain / VillageLandExtension / OuterTerrainTransition / hills. Fog fixed: `fog_density` 0.0016→0.0006, `volumetric_fog_density` 0.012→0.004, `volumetric_fog_sky_affect` 0.18→0 (this was the blocky-sky cause — froxel grid compositing onto the sky, not the cumulus shader). Evidence: `shots2/slice_v9c_fine_20260826`. GPT's rejected repair attempt archived in `work_backups/gpt_river_attempt_20260826/`.
- Next: user will apply zone material transitions on the ground for lived-in feel; vegetation/bridges via Meshy.
- **v10 pass (user round, 2026-08-26 night)**: (1) all three placeholder bridge assemblies removed (bridge, piers, abutments, foundations, collisions; land roads kept) — bridges will come from Meshy. (2) Remaining sky holes plugged: `tools/gen_hole_patches.gd` detects open-edge loops on Vista/OuterTerrainTransition and drops double-sided curtains from the rim to ground (`VistaHolePatches` node) — the east arch and west gap are now hill-coloured walls. (3) Bulges inside the revetment fixed for good: the ground underlay now **cuts out the whole channel band** (any cell touched by bank/water/bed emits no geometry) — verified by A/B hide test that the bulges were underlay poke-through. A cylindrical "VistaBackstop" attempt was ugly and was removed same-day. Evidence: `shots2/slice_v10e_cutout_20260826` + `slice_v10e_wide_20260826` (zero sky holes in all 8 cameras).
- **Vista redo step 1 done (2026-08-26 night, awaiting ART_REVIEW)**: old Vista + OuterTerrainTransition + curtain patches retired (the river-through-mountain hole is gone with them). New `BasinHills` ring generated by `tools/gen_basin_hills.gd` (deterministic seed 20260826): annulus r430-1250, 48 staggered mounds in 3 rows, north valley gap for the river exit, south highest, aerial-perspective vertex colours, **no trees (user supplies via Meshy 7)**. River clearance verified numerically: hills forced to 0 within 45m of water (12.7m of would-be hill suppressed). Mountains (150-300m) come from the user via Meshy per docs/vista-basin-plan.md; fog-band rework is plan step 4, still pending.
- **East river R3 continuation (2026-08-27, awaiting ART_REVIEW)**: `tools/gen_terrain_river.gd` now builds the stone revetment as a cross-segmented skin sampled from the exact ground-triangle interpolation, replacing R2's single chord that intersected the curved bank. By user ruling, the river generator no longer reserves or flattens an island for the current dragon statue and no longer interrupts either revetment beside it; ground, water, and banks pass continuously through that location. The statue node is intentionally untouched and may intersect the river until the user replaces it. Evidence: `shots2/east_river_r2_before_20260827`, `shots2/dragon_pool_r2_before_20260827`, `shots2/east_river_r3_through_20260827`, and `shots2/dragon_pool_r3_through_20260827`.
- **Unified terrain + B-scale river candidate (2026-08-27, awaiting ART_REVIEW)**: the slice village floor and basin hills now use one continuous `slice_unified_ground.res`; the old embedded `Terrain` visual is hidden. `unified_terrain.gdshader` blends ochre village soil, grass hills, and stone revetment from vertex masks on that one mesh, so the bank is no longer a raised/overlapping skin. User-selected river dimensions are about 44m water, 68m valley top, and 6m drop; water and valley continue through both map boundaries. The dragon statue was not moved. Geometry audit: 0 non-finite vertices, 0 downward normals, sampled water width 39.84-44.98m; `check_map.gd -- slice` and `walk_test.gd -- slice` passed. Evidence: `shots2/terrain_river_B_before_20260827`, `shots2/terrain_river_B_after2_20260827`, `shots2/terrain_basin_B_before_20260827`, and `shots2/terrain_basin_B_after2_20260827`.
- **Reference revetment pass (2026-08-27, ART_APPROVED by user)**: the user confirmed the result matches the reference. The B-scale river uses a river-aligned 5.5m-run engineered wall (nominal face angle about 48 degrees), a packed ochre crest path, and dry/wet stone vertex masks. A continuous conservative ground slope remains sealed beneath the 4m-sampled revetment cap, avoiding both terrain holes and the jagged silhouette produced by forcing the steep face into the 6m world grid. The dragon statue, water scale, and 68m valley-top envelope are unchanged. Final audit: ground/water/revetment each have 0 non-finite vertices and 0 downward normals; sampled water rows are 37.98-50.66m under organic width variation; `check_map.gd -- slice` reports 0 issues and `walk_test.gd -- slice` reports 0 blocked routes. Evidence: `shots2/revetment_ref_before_20260827` and `shots2/revetment_ref_after3_20260827`.
- The thin bright waterline band remains optional lighting/material polish, not a blocker for the approved revetment geometry.
- **River crest vegetation belt (2026-08-28, awaiting ART_REVIEW)**: `tools/gen_river_vegetation.gd` builds `maps/slice/gen/river_vegetation.tscn`, a ProtonScatter rig instanced once from `slice.tscn`, to break the razor-straight ochre-path/grass seam down both banks. Ten scatter rows (five offsets per bank, from 2.6 m inside the seam to 7.2 m out into the grass) run along Curve3D paths whose points are computed from the same centreline, width and height maths as `gen_terrain_river.gd`, so nothing is raycast or floated; the offsets themselves wander on noise so the belt does not read as a drawn line. Assets are reused, not authored: `bamboo_a/b` meshes down-scaled to about 2 m stand in as reeds with `river_transition_grass.tres` as override material, plus `hieda_bush_a/b/c` on the grass side. The bridge approach at z=-144 is skipped for 32 m either side. No approved ground, water, or revetment artifact was regenerated. `check_map.gd -- slice` reports 0 issues and `walk_test.gd -- slice` reports 0 blocked routes with 85074/85075 standable cells. Evidence: `shots2/vegbelt_before_20260828` and `shots2/vegbelt_after_20260828`.
- **Photoscan upgrade of the belt (2026-08-28 later, awaiting ART_REVIEW)**: the user rejected the low-poly `hieda_bush` look and asked for UE5-grade quality. PolyHaven CC0 photoscans (1k) now live under `imported_models/polyhaven/` (shrub_01, nettle_plant, periwinkle_plant, fern_02, grass_medium_02, rock_moss_set_01; LICENSE.txt in the directory). `gen_river_vegetation.gd` bakes each scan to a single ArrayMesh in `maps/slice/gen/ph_*.res` with re-tuned foliage materials (alpha scissor 0.22, specular 0.05, double-sided) and scatters those: bush rows use the four green plants with shadows on, plus a sparse half-buried mossy-rock row (60 m spacing, 0.3 m sink). **Measured limit**: photoscan grass tufts and any leaf card below roughly pixel scale erode to white dust under gl_compatibility (no TAA / alpha-to-coverage) — grass tufts were removed again and plants run at 2.4-3.0x real scale to compensate; do not re-add thin photoscan foliage while the renderer is gl_compatibility. The Karoo-biome PolyHaven shrubs (shrub_02/03/04) look dead and were deleted. Evidence: `shots2/vegbelt_ph_final_20260828`.
- **Revetment de-flattening (2026-08-28 night, awaiting ART_REVIEW)**: per the user's 護岸強化 reference, the wall no longer reads as a texture on a ramp. (1) Geometry: the revetment cross-section now ends in a coping course — the face stops 0.45 m short of the crest and a stone lip rises 0.22 m proud of the path before dropping back (silhouette break at the top edge). (2) Shading: `unified_terrain.gdshader` gained triplanar whiteout normal mapping plus AO for the stone branch only (mesh has no UVs, so tangent-space NORMAL_MAP is unavailable); masonry set is PolyHaven CC0 `old_stone_wall` 2k saved as `assets/textures/ishigaki_old_stone_*_2k.jpg`. Stone tint 0.47 dry / 0.22-0.28 wet, texture scale 0.32 (~3.1 m tile). First attempt at 0.82 tint washed the wall limestone-white — recorded so it is not retried. Gates re-ran clean after the profile change. Evidence: `shots2/revetment2_after_20260828` vs `shots2/vegbelt_ph_final_20260828`.
- **Water flow + bridge steps (2026-08-28 late night, awaiting ART_REVIEW)**: user ruled the landmark scales stay untouched for now. (1) `gen_terrain_river.gd` bakes the local downstream direction into the water mesh's COLOR.gb; `water.gdshader` gained a gated flow-map path (`use_flow_vc`, enabled only in `east_river_water.tres`) with classic two-phase scrolling, so ripples travel along the meander instead of world +z; pond materials keep the legacy path. (2) The bright waterline band's root cause was the semi-transparent shallow zone glowing with the ochre dirt bed underneath — submerged ground cells now carry wet-stone vertex colour; shore foam is additionally torn into lapping segments by a flow-scrolled noise mask and dimmed. (3) New `east_river_steps.res` (+`EastRiverSteps` node): a 3 m stone landing stair, 19 steps from the west crest path through the wall face to below waterline at z=-115 — placed clear of the Meshy bridge deck, whose approach ramp reaches ~z=-128 (first placement at z=-130 collided with it; recorded). Gates clean. Evidence: `shots2/water_steps_before_20260828` vs `shots2/water_steps_after_20260828` (`steps_axis`/`steps_top` are new-object framing shots).
- **Vegetation debt + bridge-approach clearing (2026-08-28, awaiting ART_REVIEW)**: three fixes in `gen_river_vegetation.gd`. (1) PolyHaven scan SETS are now split — each MeshInstance3D child bakes to its own re-centred single-plant mesh (`gen/ph_<species>_<i>.res`, 19 singles) and the bush/rock rows mix the singles; the 6 m hedge-sliver footprints from the scale audit are gone, periwinkle held to 1.55x so its flowers stop reading fist-sized. (2) **Curve gaps never worked**: removing Curve3D control points just lets the curve interpolate across the hole and Create Along Edge fills it — the bridge clearing had been decorative since round one. Rows are now built as ARRAYS of curve segments, one ScatterShape per contiguous segment; a skip genuinely ends the segment. (3) The bridge 龍石像橋 sits rotated 17.3 deg, so an oriented approach corridor (axis (0.9548,-0.2977), half-length 150 m, half-width 12 m) clears both walkway directions on top of the ±32 m river-crossing band. Evidence: `shots2/bridge_approach_before/after_20260828` (west approach: reeds+giant ferns against the deck -> clean walkway line), regression `shots2/vegbelt_singles_20260828`. Gates clean.
- Do not integrate any river into `village.tscn` until the slice prototype is approved.

## Asset diet — 2026-08-28 (user-ordered)

- All Meshy GLBs under `maps/village/gen/` were re-exported via Blender: textures capped at 4096 (8K sources downscaled), all embedded images re-encoded WEBP q85, and three pathological meshes decimated (寺子屋 2.97M tris @0.35, 遠景山 2.97M @0.12, 稗田底新版 0.92M @0.5). Totals: 739MB -> 212MB across 21 files; visual A/B in `shots2/asset_diet_before/after_20260828` shows no perceptible change at review distances.
- Meshy sidecar textures (`*_base_color/_metallic_roughness/_normal` etc.) were dead weight — zero scene/material references (the GLBs embed their own copies) — and were deleted (~460MB).
- The three unreferenced manor generations (Serene Edo Estate / Mountain Garden Manor / Misty Mountain Sanctuary) were deleted on user order after preview renders.
- slice.tscn no longer embeds the four vegetation MultiMesh buffers (the "binary data" save warning): they live in `maps/slice/gen/veg_mm_*.res` (compressed). Scene text 6.0MB -> 3.9MB, node structure verified identical (90 nodes), gates clean.
- Generated river meshes save with `ResourceSaver.FLAG_COMPRESS`.
- **GitHub blocker note**: history still contains >100MB blobs (Misty 174MB, 遠景山 112MB) from before the diet; first push requires either `git lfs migrate import --include="*.glb" --everything` or a one-off history rewrite. Working tree itself is now free of >100MB files outside `.godot` cache.

## Asset Pipeline — user ruling 2026-08-26

- **LLM-written procedural 3D asset generation (bpy code producing props/buildings) is REJECTED for new visible assets** — quality verdict: too ugly. New visible 3D assets come from the **image-AI → Meshy 7** workflow (image concept → Meshy image-to-3D → Godot import), same lineage as the Yoriichi character and `godot/imported_models/`.
- Procedural generation remains acceptable only for non-asset scene work: terrain shaping, water surfaces, scattering/placement, and utility geometry.
- Existing baked assets in the current baseline stay as-is until individually replaced.

## Current Priorities

1. Keep the working copy clean and avoid reviving obsolete prototype/review workflows or the retired village generator.
2. Continue Human Village lighting / cel-shading and remaining visible art-quality work.
3. Integrate the finished Yoriichi runtime into the formal game Player only when that task is explicitly started.

## Open decisions (waiting on the user)

- **圍牆 scale.** `imported_models/Japanese Castle Wall` is placed at scale 20 =
  8.18 m tall / 5.10 m thick / 37.98 m per segment. Real 築地塀 is 2.2-3.0 m; the user
  picked 2.41 m (scale 5.9) but the scene still holds scale 20. Four segments sit at
  (210.5, 93.8), (263.1, 93.8), (209.1, -76.2), (261.7, -76.2) — two rows flanking the
  north and south torii. **These are deliberate placements, not duplicates** (an agent
  misread them as a 4× stack and nearly deleted them).
- **Shadow budget.** 24.3 M casting triangles is what holds the frame at 31-44 fps.
  Turning off casting for `TakeFence` / `VillageTrees` would buy the most, but that is a
  look decision. Street lamps were already switched off and bought nothing (0.7 % of the
  total, 44→43 fps, inside noise) — recorded so it is not retried as a fix.
- **Play boundary.** `tools/probe_play_bounds.gd`: 15 of 16 compass headings run 420 m+
  with no terrain stopping the player. A plan exists at
  `docs/plans/2026-09-04-圍牆佈局規劃.md` (invisible `StaticBody3D` bounds for movement,
  wall segments only as gate dressing) but has not been approved or built.

## Do Not Reopen Without Evidence

- Current `village.tscn` landmark placement (the new baseline).
- The 2026-08-25 retirement of the 170-house era (generator AND assets) and the 2026-08-26 new-baseline ruling.
- Godot front-face winding convention.

## Context Rule

Do not load `docs/archive/` by default. Historical documents are for archaeology only, not current instructions.
