# NPC AI 語音（r1 評估 2026-10-20 → r2 收尾 2026-10-21）

規格：使用者 2026-10-20 指示（三套本機免費 TTS：AivisSpeech／Kokoro-FastAPI／VOICEVOX）。只用本機引擎，不用付費／雲端語音。

## 現況（r2，使用者裁定後）

- **正式只用日文語音：AivisSpeech**（魔理沙＝まお／からかい、慧音＝みちのくあいり／標準、靈夢＝コハク／ねむたい）。
- **英文語音已移除**（使用者 2026-10-21：「CUDA 測試做完後，整個英文語音都不要」）：Kokoro 引擎（CPU／GPU 兩套環境、模型、uv 快取、啟動檔）已從 `D:\Tools\TTS` 刪除；英文語音快取 15 句與 `voices.json` 的英文設定已刪。
- **英文字幕保留**（使用者更正：「可以留下英文字幕設定」）：`social.json` 每個主題的 `voice.en` 原文台詞保留；`lang=en` 時不送引擎、只提供英文字幕（交談紀錄 `SAY` 的 `sub` 欄位）。
- VOICEVOX 引擎仍裝在 D 槽當備選，但沒有任何 HERO 用它，平常不必開。

## 安裝（全部在 D 槽）

| 引擎 | 位置 | 啟動 | API | 狀態 |
|---|---|---|---|---|
| AivisSpeech Engine 1.2.0（DirectML GPU） | `D:\Tools\TTS\AivisSpeech-Engine` | `D:\Tools\TTS\start_aivis.cmd` | `http://127.0.0.1:10101` | **使用中** |
| VOICEVOX ENGINE 0.25.2（DirectML） | `D:\Tools\TTS\VOICEVOX-Engine` | `D:\Tools\TTS\start_voicevox.cmd` | `http://127.0.0.1:50021` | 備選、未使用 |
| Kokoro-FastAPI 0.9.0 | （已刪除） | — | — | 已移除 |

- AivisSpeech 的模型資料夾 `%APPDATA%\AivisSpeech-Engine` 是 junction，實體 1.4 GB 在 `D:\Tools\TTS\data\AivisSpeech-Engine`。
- 硬體：i7-9700（8 核）、32 GB RAM、GTX 1070 8 GB（驅動 582.66）。

## 什麼時候要開引擎

- **玩遊戲：不用開任何引擎。** 已烘焙的 15 句日文語音隨專案出貨（`res://assets/voice`），沒有快取的台詞只顯示字幕。遊戲本身不會啟動或重啟引擎。
- **開發時要新增台詞：只開 AivisSpeech。** `bake_voice_cache.py` 會先檢查需要的引擎有沒有開，沒開就直接說要開哪個。
- **冷啟動**：AivisSpeech 每個模型第一次載入約 6–8 s。現在有兩層處理：
  1. 烘焙工具在烘焙前先預熱用到的 3 個聲線。
  2. 遊戲在引擎有開時，啟動後在背景預熱（`/initialize_speaker`），引擎剛啟動還沒回應時每 5 s 重試、最多 6 次。
  - 實測（引擎重啟後）：預熱每聲線 6.0–6.1 s（背景，不擋遊戲）；之後第一次生成 0.80–1.65 s（未預熱時 7.2–8.1 s）。

## r1 三套引擎實測（`D:\神社\proto\npc_voice\tts_bench.py`；暖機後單句；樣本 `D:\神社\proto\npc_voice\samples`）

| 引擎 | 語言 | 聲線（魔理沙／靈夢／慧音） | 每句生成 | RTF（生成÷音長） | 引擎記憶體 | 顯示記憶體 |
|---|---|---|---|---|---|---|
| AivisSpeech | 日 | まお／からかい、コハク／ねむたい、みちのくあいり／標準 | 0.51–0.70 s | 0.11–0.20 | 925 MB | 1,904 MB |
| VOICEVOX | 日 | 春日部つむぎ、冥鳴ひまり、No.7 | 0.13–0.23 s | 0.04–0.06 | 411 MB | 845 MB |
| Kokoro（CPU） | 日／英 | jf_*／af_bella、af_heart、bf_emma | 0.65–2.0 s | 0.38–0.54 | 1,432 MB | 0 |

可懂度參考（faster-whisper 轉寫的 CER）、授權條文原文見 `D:\神社\proto\npc_voice\`。

## r2 Kokoro CUDA 測試（做完後依裁定移除）

- 環境：另建 `.venv-gpu`（原 CPU 環境不動），PyTorch **2.8.0+cu126** 官方預編譯包（Kokoro-FastAPI 官方 gpu 選項同版本），沒有裝 CUDA Toolkit。
  - `torch.cuda.is_available()=True`，GTX 1070 compute 6.1。
  - 這個版本的編譯清單含 sm_61（sm_61／70／75／80／86／90）。
  - GPU 矩陣乘法有實際跑過。
- **確認真的在 GPU 推論**：
  - 伺服器紀錄寫「Loading Kokoro model on cuda」。
  - 合成時 GPU 使用率平均 75 %、最高 91 %。
  - 伺服器顯示記憶體 1,293 MB。
  - 10 句只用 2.0 CPU 秒（CPU 版要 92.1 CPU 秒）。
- **CPU vs GPU**（同模型 Kokoro-82M v1.0、同聲線 af_bella、同 10 句英文；`D:\神社\proto\npc_voice\kokoro_cpu_gpu_bench.py`，結果 `kokoro_cpu_gpu.json`）：

| | CPU | GPU（GTX 1070） | GPU 快幾倍 |
|---|---|---|---|
| 啟動到可用 | 43.7 s | 32.6 s | 1.3× |
| 第一句（冷） | 7.03 s | 0.52 s | 13.5× |
| 暖機後每句 | 0.93–7.36 s | 0.16–0.30 s | — |
| 連續 10 句 | 23.79 s | 2.38 s | **10.0×** |
| 伺服器 CPU 時間（10 句） | 92.1 s（吃滿 8 核約 12 s） | 2.0 s | — |
| 記憶體／顯示記憶體 | 1.2 GB／0 | 1.9 GB／1.3 GB | — |

- **同時跑 Godot（village_v2 視窗 1280×720）**：
  - Godot 單獨：平均 47.3 fps、最慢 1 % 區間 36.9 fps。
  - Godot 加上 Kokoro-GPU 連續合成 50 s：159 句、0 失敗、最慢一句 0.46 s；Godot 平均 41.2 fps（約 −13 %）、最低 32.8 fps。
  - 顯示記憶體總用量最高 5.4 GB／8 GB，沒有不足，也沒有當機。
- 結論：GTX 1070 跑 Kokoro 有明顯優勢（10×）、與遊戲並存穩定。但英文語音不採用，已整個移除。

## Godot 整合（沿用 NPC Living World，不重做）

- `data/npc_life/voices.json`：每名 HERO、每種語言指定引擎與聲線，另記嘴的資料。語言用 `lang` 切換，也可用環境變數 `NPC_VOICE_LANG` 或啟動參數 `--voice_lang=`。
- `data/npc_life/social.json`：交談主題的 `voice.ja`（語音）／`voice.en`（英文字幕），與繁中台詞逐句對應。目前 4 個主題、各 3–4 句：mk_greet、mk_mushroom、keine_anomaly_marisa、mr_banter。
- `systems/npc_life/npc_voice.gd`：
  - 查快取的順序：記憶體 → `res://assets/voice/voice_index.json`（離線烘焙）→ `user://voice_cache`（執行期生成過的）。
  - 都沒有、而且引擎有開 → 當場生成並自動存進快取。
  - 引擎沒開 → 1.5 s 內判定，只顯示字幕。
  - 引擎有開時在背景預熱。
- 交談時：
  - 語音由頭部的 AudioStreamPlayer3D（Voice 匯流排）播放，每句長度＝語音長度＋0.45 s，字幕泡泡同步。
  - 說完照原流程回到生活事件。
  - 玩家插話、被敵人打斷時語音一起停。
- 烘焙：開 AivisSpeech → `python godot/tools/npc_voice/bake_voice_cache.py`（只用 Python 標準函式庫）→ `godot --headless --path godot --import`。
- 驗證：`godot --headless --path godot -s res://tools/npc_voice/verify_npc_voice.gd`（要開 AivisSpeech）。

## 嘴型（r2 改版）

- **模型盤點**（魔理沙、慧音、靈夢、小鈴、阿求）：
  - 5 人都沒有 blend shape，也沒有下顎／嘴部骨，臉部只有 Head 骨。
  - 嘴是畫在「身體」網格貼圖上的；慧音的模型在嘴的位置有一道約 2 mm 的開縫。
  - 沒有其他表情系統。
- **r1 做法（已棄用）**：在 Head 骨上掛一片平面橢圓，正面準，側面會往鼻尖那側偏約半個嘴寬。
- **r2 做法**：直接用模型原有的臉部網格與貼圖。
  - 在「身體」網格的 `material_overlay` 上，以**貼圖 UV 空間**畫口腔橢圓，依語音音量開合；不說話時拿掉 overlay（零成本）。
  - 因為畫在臉的表面本身，跟著曲面與骨架走，正面、3/4、側面都貼在嘴上。
  - 嘴的 UV 由 `tools/npc_voice/bake_mouth_uv.gd` 從 `voices.json` 的嘴位置自動算：嘴附近每 2 mm 往臉打射線、只取朝外的面、依 UV 分群。
  - 個別情況：
    - 魔理沙的嘴剛好跨在貼圖接縫上，分成 2 塊。
    - 慧音是開縫的嘴：另外處理縫裡露出的頭殼內側與唇內壁，說話時塗暗。
  - 角色資產（GLB、貼圖、骨架）都沒有修改。
  - 審圖：正面／3/4／側面九格，三人都在嘴上、無偏移、無雜點（`D:\神社\proto\npc_voice\mouth_probe\mouth_uv_sheet5.png`）。
- **限制（美術改善，可延後）**：仍是「一個會開闔的深色橢圓」，沒有母音口型、沒有牙齒舌頭。要更好，需要在模型上做嘴部 blend shape（a／i／u／e／o＋閉）或下顎骨——要改角色資產，先評估再做，不在本輪。

## 授權（原文存 `D:\神社\proto\npc_voice\licenses\`）

- **AivisSpeech Engine**：LGPL-3.0。三個模型（まお、コハク、みちのくあいり）都是 ACML 1.0：個人、法人、營利都可以，署名可選。禁止讓人誤以為是本人／官方、貶損話者形象等。
- **VOICEVOX**（備選）：引擎 LGPL-3.0；No.7 只限非商用，商用要事先詢問。
- 東方 Project 二次創作另受 ZUN／上海アリス幻樂団的同人指引約束；遊戲裡應註明「非官方」。

## NPC Living World 回歸

- r1 語音整合後：A–F 50/50、G 30/30、語音 6/6 PASS（同時修了轉身逾時起點、被約的人原地罰站、玩家攔不下趕赴約談的人，見 git 紀錄）。
- r2（嘴型改版、預熱、移除英文語音後）：見下方「r2 驗證」。

## r2 驗證（2026-10-21）

- NPC Living World：A–F **50/50 PASS**、G（10 倍生活時鐘 420 s）**30/30 PASS**。
- 語音 `verify_npc_voice.gd` **9/9 PASS**（引擎重啟後冷跑），涵蓋：
  - 烘焙快取命中。
  - 預熱 3 聲線。
  - 三人預熱後第一次生成 < 3 s。
  - 重開後 user:// 快取命中。
  - `lang=en` 只有字幕、不送引擎。
  - 英文字幕 4 主題保留。
  - 引擎離線 1.5 s 退回字幕。
- 遊戲內錄影（`D:\神社\proto\npc_voice\video_r2\`）：
  - `voice_ja.mp4`：魔理沙↔慧音 mk_greet 4 句，有聲（對話段平均 −19 dB）；繁中＋日文字幕；嘴型畫在臉上開合（每 10 格取樣 27 次開口）；講完 t=40.7 交談完成，t=46.4 魔理沙接著去市集。
  - `subs_en.mp4`：`lang=en`，mk_mushroom 3 句，繁中＋英文字幕、無聲（−91 dB）；講完回到生活事件。
- 審圖總表：`docs/npc_life/npc_voice_r2_sheet.jpg`（嘴型九格＋日文語音畫面＋英文字幕畫面）。
