# PROJECT STATE

這是每個新任務在 `CLAUDE.md` 之後必讀的目前狀態。只保留會影響下一個決策的
事實；逐輪紀錄在子系統文件或 `docs/archive/`。

Last updated: 2026-08-11.

## Execution Mode

| 子系統 | 模式 |
|---|---|
| Human Village production work | PRODUCTION MODE |
| 其他子系統 | DESIGN MODE，除非使用者另有指示 |

完整規則：`.claude/rules/execution-modes.md`。

## Current Build

- 現行遊戲是 `godot/` 下的 Godot 4.4 專案。
- 頂層 `src/` 是凍結的 three.js 舊線，但仍供尚未原生化的地圖匯出 blockout。
- 人間之里場景：`godot/maps/village/village.tscn`。
- 正式生成入口：`godot/tools/gen_town.gd`，約 1,154 行。
- `gen_town.gd` 只保留 orchestration、shared state 與 deterministic RNG ownership；
  實作責任已拆到 `godot/tools/town/*.gd`。
- 已淘汰的 `godot/tools/gen_village.gd` 已於 2026-08-11 刪除；需要考古時查 Git。
- 人間之里生成結果目前是 1,680 個節點。最後一次結構重構前後，instance 與
  MultiMesh stable hashes 均保持一致，五項靜態驗證通過。

## Human Village Baseline

- 道路、河道、地標、傳送點、建物配置及 deterministic output 已鎖定。
- 住宅已全面使用 production architecture；legacy residential blockout 為 0。
- 市場、主要街道、街燈、河岸生態、草層及密度層均已模組化。
- 六座正式地標均有真內容；名稱一律使用「鯢吞亭／鲵吞亭」，不得沿用歷史誤字
  「鵜吞亭」。
- 視覺變更仍須 prototype/slice → render → Human Art Review → rollout。

## Generator Contract

- 不改 RNG 呼叫次序、不在責任模組內建立新的獨立 RNG ownership。
- 不改程序生成順序、座標、建物數、資產選擇或保留區，除非使用者明確核准。
- 驗證以輸出的 `.tscn`、instances JSON、MultiMesh buffer 及引擎畫面為準。
- `gen_town.gd` 是正式入口，不能刪除，也不再以行數為理由強拆。

## Current Risks

- RNG 雖已分層，個別層內仍可能是循序 stream；插入隨機呼叫會造成後續漂移。
- 稗田邸 blockout、鐘塔／火見櫓、近景小物和水生植物仍有美術品質債。
- 手工 LOD 尚未完成；住宅 production geometry 的三角面成本高於早期 blockout。
- `bamboo`、`eientei`、`namelessHill`、`shrine`、`sunflower` 尚依賴
  `godot/blockout/*.glb`。
- `shots2/` 有尚未納入 Git 的驗收圖；清除前需由使用者決定是否保留。

## Current Gate / Next

- 先完成現有市場、資產尺寸與村落視覺證據的 Human Art Review／保存決策。
- 下一個主要美術階段是 lighting / cel-shading；不得順手改道路或地標結構。
- 若工作只涉及程式結構，硬條件是生成結果 stable hash 不漂移，所有靜態檢查通過。

## Do Not Reopen Without Regression Evidence

- 人間之里道路與河道結構、主要地標位置及 portal 連接。
- 已核准的町家結構比例、材質語言與 production asset pipeline。
- 稗田邸完整版放在人間之里，舊縮小程序版不復活。
- Godot front-face winding 為 clockwise。
- `make_town.py` 是 `town_modules.json` 的單一 writer。
- `gen_town.gd` 持有 shared state 與 RNG；責任模組不另起一套生成流程。

## Canonical Documents

| 主題 | 文件 |
|---|---|
| 路線圖 | `docs/ROADMAP.md` |
| 人間之里生成規則 | `docs/ningen-no-sato.md` |
| 人間之里美術方向 | `docs/village-art-direction.md` |
| 町家 production kit | `docs/machiya-production-kit.md` |
| Generator domain / ADR | `docs/domain-model.md` |
| Godot 遷移狀態 | `docs/godot-migration.md` |
