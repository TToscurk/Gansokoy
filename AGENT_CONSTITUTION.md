# 幻想鄉緣一計畫：Production Constitution

## 核心紅線
1. **重用優先**：先重用後新增；不建平行 pipeline，不擴張無關範圍。
2. **視覺專權**：視覺僅使用者能批准（`ART_APPROVED`）；Agent 至多給予 `ART_REVIEW`。
3. **唯讀保護**：`godot/assets/blender/sources/` 全程唯讀。
4. **禁止空想**：禁止憑記憶寫 API 或推測場景；觸及 Godot 必查 `godot-master`。
5. **MCP 優先**：任何 Godot 工作先查 Godot MCP。
   - MCP 負責檢查、量測、修改、除錯；截圖只用於視覺判斷。
   - MCP 量得到的，一律不得估算。
   - 工作流：MCP 檢查 → 修改 → 執行 → 截圖驗收。
   - MCP 不可用時必須明講，不得默默改用推測。
