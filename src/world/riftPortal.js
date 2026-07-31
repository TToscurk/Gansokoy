// 裂縫傳送點 —— 有條件才出現的 makePortalGlow。
//
// 白玉樓的入口是神社夜裡 22:00–02:00 的裂縫、天界要站上山頂、彼岸要在
// 渡口等小町的船 —— 這些傳送點跟一般的「走到就在」不同，有出現條件。
// 這裡包一層：activeCheck 不滿足時整組隱藏（光球、光柱、PointLight
// 全部消失），滿足的瞬間才浮現。
//
// 呼叫端每幀照樣呼叫 userData.update(t)；要不要能按 E 用
// userData.isActive() 問（隱藏中的傳送點不該吃互動鍵）。

import { makePortalGlow } from './portal.js';

/**
 * @param {THREE.Object3D} parent
 * @param {number} x @param {number} y @param {number} z
 * @param {object} [o]
 * @param {number}   [o.color=0xc8a8ff] 裂縫色（預設偏紫 —— 異界的顏色）
 * @param {()=>boolean} [o.activeCheck] 回 true 才出現；省略 = 常駐
 * @returns {THREE.Group} 加了 isActive() 的 portal group
 */
export function makeRiftPortal(parent, x, y, z, { color = 0xc8a8ff, activeCheck = null } = {}) {
  const g = makePortalGlow(parent, x, y, z, color);
  const baseUpdate = g.userData.update;

  g.userData.isActive = () => !activeCheck || !!activeCheck();
  g.userData.update = (t) => {
    const on = g.userData.isActive();
    if (g.visible !== on) g.visible = on;
    if (on) baseUpdate(t);
  };
  // 初始狀態就要對 —— 裂縫白天不該閃一幀
  g.visible = g.userData.isActive();
  return g;
}

/**
 * 時間窗檢查器（給夜間裂縫用）。
 * 支援跨午夜：inHourWindow(env, 22, 2) = 22:00–02:00。
 * @param {{hour:number}} env Environment（讀 env.hour）
 */
export function inHourWindow(env, from, to) {
  return () => {
    const h = env.hour;
    return from <= to ? (h >= from && h < to) : (h >= from || h < to);
  };
}
