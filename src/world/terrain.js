// 最小地形層 —— 給 NPC 系統放置角色用。
//
// shrine 本身有 heightAt()，但那是 main.js 裡的 scene-local 函式。
// NPC 模組不能直接依賴 main.js（循環參照），所以透過 setGroundHeightFn
// 讓 main.js 把自己的高度場接上來。
//
// 預設永遠回傳 0（= 沒有高度場時角色站在 y=0）。

let _fn = () => 0;

/** main.js 啟動時呼叫這個，把 shrine 自己的 heightAt 接上來 */
export function setGroundHeightFn(fn) {
  _fn = fn;
}

/** NPC 放置時會問「這點的地面多高」 */
export function groundHeight(x, z) {
  return _fn(x, z);
}

import * as THREE from 'three';
const _n = new THREE.Vector3();

/** 地形法線（PlayerController 的相機避碰用） */
export function terrainNormal(x, z, eps = 1.2) {
  const hL = groundHeight(x - eps, z), hR = groundHeight(x + eps, z);
  const hD = groundHeight(x, z - eps), hU = groundHeight(x, z + eps);
  return _n.set(hL - hR, 2 * eps, hD - hU).normalize();
}
