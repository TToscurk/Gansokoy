# Visual QA（P2）— 建築／場景統一驗證

一個入口串起既有的四套工具，不重寫幾何：

| 步驟 | 誰做 | 工具 |
|---|---|---|
| 1 讀資料 | vqa.py | 連接表 `*.arch.json`、GLB、場景 |
| 2 幾何 | Geometry Inspector | `tools/blender/arch_check.py`（P0/P1：接觸／穿插／支撐／約束） |
| 3 構件連接 | Geometry Inspector | 同上 `--graph`（Scene Graph）、`--targets`（非 PASS → 特寫目標） |
| 4 放置與地形 | Scene Inspector | 快速通道 `result.json`（`--placement=`）；地圖模式用 `arch_spatial_lib.road_intrusion` |
| 5 多視角截圖 | — | `godot/tools/visual_qa/vqa_capture.gd`（非 headless） |
| 6 視覺審查 | Visual Reviewer | `review_request.json` → 審查者寫 `review.json` → `--review=` 合併 |
| 7–8 彙整報告 | vqa.py | `report.json`＋`report.md`＋總表圖 |

```bash
# 單棟（審查舞台：GLB 執行期載入，不匯入專案）
python tools/visual_qa/vqa.py --mode=full --name=torii \
    --glb=godot/assets/beast_path/s01_kit/glb/s01_torii_a.glb,godot/assets/beast_path/s01_kit/glb/s01_torii_a_base.glb \
    --blend=godot/assets/beast_path/s01_kit/src/s01_shrine.blend --map=docs/arch_spatial/examples/s01_torii.arch.json \
    --profile=japanese_shrine [--corners] [--yaw=37 --scale=1.3,1,0.8] [--ref=ref.json] [--review=review.json]
# Tripo 單網格（沒有連接表）
python tools/visual_qa/vqa.py --mode=full --glb=godot/assets/shrine/手水舍.glb --scan --scale=3.2 --profile=japanese_shrine
# 正式場景中的建築（記憶體內載入，不存檔）
python tools/visual_qa/vqa.py --mode=visual-only --scene=res://maps/village_v2/village_v2.tscn --node=FastLane/<id>
# 地圖區域
python tools/visual_qa/vqa.py --mode=map --scene=res://maps/village_v2/village_v2.tscn --region=200,-120,320,40 \
    [--landmarks=Landmarks/X/Hero,…] [--max-views=4]
# 回歸（約 4 分鐘，需要顯示）
python tools/visual_qa/test_vqa.py
```

輸出預設 `docs/visual_qa/<name>/`（`--out=` 改到別處）。exit：FAIL → 1；只有 UNKNOWN／REVIEW → 3；其他 0。

## 模式
| mode | 幾何 | 拍攝 | 用途 |
|---|---|---|---|
| `geometry-only` | ✓ | — | 只要數字 |
| `visual-only` | — | 六視圖（＋`--corners` 四角） | 沒有連接表、只看外觀與可靠性 |
| `full` | ✓ | 六視圖＋每個非 PASS 的特寫＋修正預覽前後 | 預設 |
| `review-failures` | ✓ | 只拍非 PASS 的特寫＋一張正視；沒有異常就不拍 | 大批量時省時間 |
| `map` | — | 區域俯視＋路口玩家視角＋地標可見率 | 地圖 |

## 固定拍攝條件（B2）
- 解析度預設 1280×720（`--res=WxH`），每張影像都記錄相機原點、基底、投影、size/fov、near/far。
- 相機由**建築座標**算：front＝目標節點 basis·`front_local`（預設 +Z），right＝front×up；不是世界軸。
- 正交五視圖（front/back/left/right/top）用建築緊貼盒投影後加 12% 邊距；top 的影像下方＝正面。
- 斜視 perspective 35°、方位 35°、仰角 30°；四角 45°+90°k、仰角 25°。透視圖只給人看，不拿來算公尺。
- 審查舞台：固定背景色、固定方向光（−52°, −38°）、灰地面 y=0、filmic；正式場景模式固定 10:00（天象系統／DayNight 停止流動）。
- ID 遮罩：unshaded 純色、無霧、無 AA、無 TAA、線性色調 → 顏色與指定值完全一致（實測零誤差）。
- 每輪重拍正視一次量重現性（審查舞台實測 0.11–0.16% 像素因陰影取樣雜訊改變，門檻 0.5%）。

## 截圖可靠性（B4）→ 不可靠就是 UNKNOWN
| 判定 | 方法 | 結果 |
|---|---|---|
| BLACK_FRAME | 平均亮度 < 4 或標準差 < 1.5 | UNKNOWN |
| NOT_IN_FRAME | ID 遮罩覆蓋 < 0.2% | UNKNOWN |
| CLIPPED | 建築遮罩碰到影像邊緣 | UNKNOWN |
| OCCLUDED | （一般 − 目標隱藏）差分 ∩ ID 遮罩 ÷ ID 遮罩 < 50% | UNKNOWN；50–90% → WARN |
| 解析度 | 影像尺寸 ≠ 指定 | UNKNOWN |
| VIS_SCALE | 正交剪影寬高 × m/px vs 幾何緊貼盒（±2 px＋1%） | 不符 → FAIL（這張圖的量測不可信） |

## 幾何 × 視覺交叉驗證（C1/C2）
| 項目 | 幾何 | 視覺量測 | 一致 | 不一致 |
|---|---|---|---|---|
| VIS_GAP（SUPPORT） | 中位間隙 | 特寫正交 ID 遮罩逐欄量「上件底 → 下件頂」 | 兩邊都 FAIL → FAIL（附兩視角） | 小於 1.5 px → UNKNOWN（幾何結論不變） |
| VIS_OFFSET（COAXIAL） | 中心線偏移＋建築座標方向 | 俯視**逐構件單獨**遮罩重心差（不被屋頂遮住） | 大小＋方向一致 → FAIL | REVIEW |
| VIS_SYMMETRY | SYMMETRIC 約束（若有） | 正視剪影對建築原點中軸鏡射 IoU、左右立面互鏡 IoU | 一致 | REVIEW（說明可能原因） |
| 審查意見 | 定位物件的所有規則 | 審查者給的像素 → ID 遮罩 → 物件 | 有 FAIL → FAIL | 全 PASS → REVIEW；無規則 → REVIEW；定位不到 → REVIEW |

視覺永遠不單獨產生 FAIL；FAIL 必須有可量測的幾何證據。單張圖不推算世界座標。

## 風格 Profile（D）
`tools/visual_qa/profiles.json`：japanese_shrine／japanese_house／rural_building／fantasy_building／generic_modular。
只產生 WARN（STYLE_DEVIATION／STRUCTURAL_ERROR）、REVIEW、UNKNOWN，**不產生 FAIL**。`project_canon` 命中（博麗、人間之里）時：
不提示新增未確認建築、允許古舊不規則。連接表 `intentional_asymmetry: [構件]` → 不對稱記 INTENTIONAL。

## 參考圖（E）
`--ref=ref.json`：`{"image": "...png", "view": "front", "projection": "ortho", "approved": true, "approved_by": "...", "mask": {"mode": "alpha"|"bg", "bg": [r,g,b], "tol": 24}}`。
沒有 `approved: true` 或視角／投影不同 → UNKNOWN（不算分數）。校正＝裁到剪影外框、等高縮放、底中對齊；量 IoU、寬高比、20 段寬度分布，
報告指出差最多的高度段。差異 → REVIEW，不重建。

## 審查意見格式（C3）
`review_request.json`（自動產生）給審查者：影像清單、幾何事實、Scene Graph 限制、profile 檢查清單——**不含建模階段的自我描述**。
審查者回填 `review.json`：`{"items": [{"image": "front.png", "px": [x, y], "object": "(可省)", "concern": "gap", "observation": "..."}]}`。

## 報告
`report.json`：`summary`（區段 × 狀態）、`totals`、`results`（欄位同 arch_spatial：`rule_id, type, status, object_ids, expected, actual,
deviation, tolerance, method, suggestion, evidence` ＋ `section, error_class, images, camera`）、`meta.version`（git HEAD、輸入檔與工具檔
sha256＋是否未提交、Godot／GPU）。`report.md` 分開列 FAIL／REVIEW／UNKNOWN／WARN，PASS 另列；UNKNOWN 與 REVIEW 不計入 PASS。

## 修正（I）
沿用 P1 `--fix-preview`。只有幾何預覽判 OK 的修正才拍「修正後」（記憶體內平移、拍完還原、不寫檔），並重量縫隙；
BREAKS／NOT_FIXED 只回報，不拍、不套用。純美術問題（沒有幾何證據）不提修正。
