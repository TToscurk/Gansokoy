# NPC Living World — 實作說明（r1，2026-10-20）

規格：`docs/NPC自主生活系統.md`（動工前必讀）。本檔只記「現在怎麼運作、怎麼擴充、怎麼驗」。

## 架構

| 檔案 | 角色 |
|---|---|
| `godot/systems/npc_life/npc_life_director.gd` | 地圖上的 `NpcLife` 節點。讀資料、挑事件（權重＋條件＋性格）、物件預約、雙人交談同步、世界事實／傳聞、世界觸發、AStarGrid2D 尋路 |
| `godot/systems/npc_life/npc_life_actor.gd` | HERO 本體（繼承 `scripts/npc_population_actor.gd`）。執行步驟（走路、轉身、動作、泡泡台詞）、被玩家／劇情／戰鬥打斷、遠距降頻 |
| `godot/data/npc_life/heroes.json` | 每名 HERO：身分、性格、關係、動作對照、事件、對玩家台詞、`plan_change`（聽到傳聞時改計畫的機率） |
| `godot/data/npc_life/social.json` | 雙人交談主題（台詞、條件、結果＝傳聞擴散／世界事實） |
| `godot/data/npc_life/<map>.json` | 地點、Smart Object（站位／面向／場景節點）、據點、世界觸發 |
| `godot/data/npc_life/<map>_walk.bin` | 烘焙可走格（0.5 m，zstd）。`tools/npc_life/bake_npc_life_walkgrid.gd` 產生並逐點驗證 |

事件狀態：Reserved → Traveling → Interacting → Completed／Interrupted／Failed → Cooldown（director 的 `event_state` 訊號＋`[LIFE]` 紀錄）。

打斷優先序：劇情對話（25 m 內凍結）＞ 敵人 20 m 內（中止、面向威脅）＞ 玩家 3.2 m 內（暫停、轉身、依當下事件回話；離開 5.5 m 後續做）＞ 被找去聊天（發起者 12 m 內才暫停手上的事，聊完續做；對方還遠又沒事做時，只挑 30 m 內的一般事件做，不原地罰站）＞ 生活事件。

## 決策提供者（可切換）

預設全部 HERO 用原本的權重決策。`NpcLife` 節點的 `jev_heroes` 填入 HERO id（例：`marisa`）才改用 JEV（`systems/npc_life/npc_life_jev_provider.gd`，外掛 `addons/godot_jev`）；反應事件、優先權、冷卻、預約、打斷都不變，失敗／逾時／沒有金鑰自動退回原本決策。金鑰只讀環境變數 `TYPESAFE_API_KEY`。評估結果見 `docs/npc_life/JEV評估.md`。

## 語音（r1，可切換）

交談台詞可配本機 TTS 語音（`systems/npc_life/npc_voice.gd`＋`npc_mouth.gd`，設定 `data/npc_life/voices.json`、台詞 `social.json` 的 `voice`）。快取優先，引擎沒開只顯示字幕。評估、授權與指令見 `docs/npc_life/NPC語音評估.md`。

## 事件鏈（目前資料）

- **森林異狀**：世界觸發在村口林邊生出毛玉 → 巡視中的慧音看見（知覺 20 m）→ 放下巡視去通報（依關係挑魔理沙／靈夢／阿求）→ 交談把傳聞傳給對方 → 魔理沙改道調查（毛玉逃走、異狀解除）／靈夢憑直覺前往並在林邊找魔理沙／阿求在緣側記進緣起。
- **妖魔本**：世界觸發「新書到貨」→ 小鈴拆書得知 → 靈夢直覺去鈴奈庵沒收；阿求來訪時小鈴拿給她看。

## 擴充

- **新 HERO**：`heroes.json` 加一段（`skeleton: general` 自動共用說話／跪地／祈禱動作；其他骨架在 `actions` 指定自己的動作名）；場景裡 HERO 本體用 `npc_life_actor.gd` 並設 `hero_id`。
- **新互動物件**：`<map>.json` 的 `objects` 加一筆（`stand` 站位、`face` 面向、`node` 場景節點、`tags`），重跑烘焙確認 `[PLACE] PASS`。
- **新地圖**：建 `<map>.json`（grid 範圍＋places/objects/homes），烘焙，在地圖場景加 `NpcLife` 節點（`map_id`）。
- **新事件／主題**：純資料，不必改程式。

## 驗證

```
# 可走格烘焙＋地點擺放驗證
godot --headless --path godot -s res://tools/npc_life/bake_npc_life_walkgrid.gd
# 測試 A–F（約 15 分鐘）；G＝長時間加速
godot --headless --path godot -s res://tools/npc_life/verify_npc_life.gd -- --map=village_v2 --cases=ACBDEF --ts=4
godot --headless --path godot -s res://tools/npc_life/verify_npc_life.gd -- --map=village_v2 --cases=G --long=300
# JEV 對照（小型測試場景；--jev 才會連雲端）、正式村莊試跑
godot --headless --path godot -s res://tools/npc_life/jev_decision_bench.gd -- --failures [--jev --reps=3]
godot --headless --path godot -s res://tools/npc_life/jev_live_run.gd -- --map=village_v2 --mode=jev --secs=360 --ts=2
# 語音快取（要先開本機引擎）與驗證
python godot/tools/npc_voice/bake_voice_cache.py
godot --headless --path godot -s res://tools/npc_voice/verify_npc_voice.gd
# 錄影（視窗；scene=voice 為雙人語音對話，加 --topic=<主題> --voice_lang=ja|en）
godot --path godot --resolution 1280x720 --write-movie out.avi --fixed-fps 30 -s res://tools/npc_life/capture_npc_life.gd -- --map=village_v2 --scene=social --secs=60 --lifeshots=<資料夾>
```
