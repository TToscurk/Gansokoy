# 音效素材來源與授權

本專案 `godot/assets/audio/sfx/` 下的音效，2026-09-17 起全面改用
**CC0 / Public Domain 的真實錄音**，取代原本 `tools/synth_sfx.py` 的程式合成音。

建構腳本：`work/build_combat.py`、`work/build_ambient.py`（共用 `work/sfx_lib.py`）。
原始下載包放在 `work/sfx_sourcing/`（約 160 MB，**不進版控**）；
版控只保留最終遊戲音檔、建構腳本與本文件。

---

## 授權原則

| 授權 | 處置 |
|------|------|
| CC0 / Public Domain | ✅ 採用 |
| CC BY | ⚠ 未使用（需保留署名，本輪不需要） |
| **CC BY-SA** | ❌ **排除** —— 傳染性條款（ShareAlike）對遊戲資產有授權風險 |

CC0 法律上不要求署名，本文件仍完整記錄出處，供日後查核與追溯。

---

## OpenGameArt（全部 CC0）

| 素材包 | 頁面 | 用途 |
|--------|------|------|
| Medieval Sound Effects: Weapon Impacts | `opengameart.org/content/medieval-sound-effects-weapon-impacts` | 刀刃互擊 → 揮砍命中、彈刀、格擋、重擊、受傷 |
| Swishes Sound Pack | `opengameart.org/content/swishes-sound-pack` | 揮空聲 → 揮刀、炎刃揮擊 |
| 3 Melee Sounds | `opengameart.org/content/3-melee-sounds` | 金屬摩擦 → 拔刀／納刀 |
| 4 Metal Dings/Rings | `opengameart.org/content/4-metal-dingsrings` | 金屬泛音 → 彈刀尾韻、拔刀 |
| Fire Crackling | `opengameart.org/content/fire-crackling` | 火焰層 → 炎刃揮擊／命中 |
| Different Steps on Wood/Stone/Leaves/Gravel/Mud | `opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud` | 落葉／礫石／泥土 → 草地腳步、土路、石板 |
| Fantozzi's Footsteps (Grass/Sand/Stone) | `opengameart.org/content/fantozzis-footsteps-grasssand-stone` | 沙地／石板 → 草地腳步的體感層、石板腳步 |
| Dog Snarl/Grunt/Grumble | `opengameart.org/content/dog-snarl-grunt-grumble` | 96 kHz 犬科錄音 → 山犬全套 |
| Bird/Cricket/Frog and Mosquito Sounds | `opengameart.org/content/birdcricketfrog-and-mosquito-sounds` | 鳥鳴、夜鳥、蛙鳴 |
| Forest Bird Sounds | `opengameart.org/content/forest-bird-sounds` | 遠景森林鳥層（8 kHz，僅堪當底噪） |
| 6 Short Water Splashes | `opengameart.org/content/6-short-water-splashes` | 水花 → 鴨子划水、鯉魚擺尾 |

## Wikimedia Commons

| 檔案 | 授權 | 用途 |
|------|------|------|
| `File:Wolf howls.ogg` | **Public domain** | ✅ `wolf_howl_distant.wav`（遠景嚎叫） |
| `File:Mallard (Anas platyrhynchos) (W1CDR0001518 BD17).ogg` | CC BY-SA 4.0 | ❌ 排除 |
| `File:Anas platyrhynchos - Mallard - XC62258.ogg` | CC BY-SA 3.0 | ❌ 排除 |
| `File:Strix aluco male.oga`（灰林鴞） | CC BY-SA 4.0 | ❌ 排除 |

---

## 處理管線

原始錄音不能直接用（單檔 6–13 秒、含多次撞擊、最高 192 kHz），`work/sfx_lib.py` 負責：

1. **瞬態偵測切段** —— 10 ms 滑動最大值找起音點，從 5 個刀劍檔切出 **46 段獨立撞擊**
2. **降頻至 44.1 kHz 單聲道**（來源有 192 kHz / 96 kHz / 8 kHz）
3. **修剪靜音、淡入淡出、峰值正規化到 −1 dBFS**
4. **變調**（`resample_pitch`：ratio > 1 = 變長變低 = 體型變大）
5. **分層混音**（揮空 + 火焰層、撞擊 + 泛音、落葉層 + 沙地層）

---

## ⚠ 兩個缺口（代用品，非真素材）

### 1. 草地腳步是合成的代用品

**CC0 世界裡沒有真正的草地腳步錄音。** OpenGameArt 那包標題寫 `Grass/Sand/Stone`，
實際解壓只有 **Sand 和 Stone 兩種**；Wikimedia 搜「footsteps grass」回傳的是 PDF 文件。

現行做法：**落葉的高頻沙沙層（`leaves01/02`）+ 沙地的中低頻踏實層（`Fantozzi-Sand`）**
疊合，跑步版另加一層土壤悶擊。這是聽感近似，不是真草地錄音。

### 2. 鴨叫沒有做

CC0 素材庫沒有鴨叫；Wikimedia 上的鴨聲全是 CC BY-SA，依上述原則排除。
**鴨子目前只有入水／拍水聲，沒有叫聲** —— 寧可沒有，不用假的。

若要補，兩條路：(a) 使用者提供授權乾淨的音檔；(b) 用 `tools/synth_sfx.py`
合成帶共振峰的短促「嘎」聲（授權乾淨但非真實錄音）。
