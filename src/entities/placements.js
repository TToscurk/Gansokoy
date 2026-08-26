// 角色場景編輯器用的擺放狀態表。
//
// 純記憶體、不落地存檔（沒有 localStorage）—— 模組載入時 placements 永遠是
// 空物件，重新整理頁面等於重新載入這個模組，狀態自然歸零。這正好符合
// 「編輯器的擺放只在本次遊玩期間有效」的需求，不需要額外的清除邏輯。

let placements = {};

/** 目前所有擺放記錄：{ [charId]: { x, z, face } } */
export function getPlacements() {
  return placements;
}

/** 建立或更新一筆擺放 */
export function setPlacement(id, x, z, face = 0) {
  placements[id] = { x, z, face };
}

/** 移除一筆擺放（角色收回編輯器面板） */
export function removePlacement(id) {
  delete placements[id];
}
