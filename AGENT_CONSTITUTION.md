# 幻想鄉緣一計畫：Production Constitution

## 核心紅線

## 1. 重用優先
先重用，後新增。
不得建立平行 pipeline，不得擴張無關範圍。

## 2. 視覺專權
只有使用者能給予 `ART_APPROVED`。
Agent 最多只能給予 `ART_REVIEW`，不得自行宣告視覺完成。

## 3. 唯讀保護
`godot/assets/blender/sources/` 全程唯讀。
不得修改、覆寫或重新生成其中內容。

## 4. 禁止空想
不得憑記憶編寫 API、推測場景狀態或虛構驗證結果。

Godot API / engine behavior → 查 `godot-master`。
Project scene / node / transform / resource state → 查 MCP。

## 5. Godot Visual Workflow
- MCP = inspect, measure, debug, verify project state.
- Screenshot = visual evidence, never measurement truth.
- Never guess what MCP can measure.
- Never self-approve subjective visual quality.
- Convert approved visual decisions into measurable constraints when practical.
- Workflow: Inspect → Measure → Modify → Run → Verify → `ART_REVIEW`.
- `ART_APPROVED` requires user approval.
- If MCP is unavailable, state it explicitly.
