// 怪物群的共用核心 —— 命中判定、傷害結算、存活統計。
//
// combat.js 只認識四個方法（inSector / damage / aliveNear / update），
// 每種怪物的差別其實只在 update：妖精在窩附近飄，妖怪兔會追著玩家跳。
// 前三個是完全一樣的邏輯，抽到這裡讓每種怪物只需要寫自己的行為。
//
// 這裡刻意寫成純函式而不是基底類別：怪物的渲染方式差很多
// （妖精是發光的 BasicMaterial、兔子是吃光的 StandardMaterial，
// InstancedMesh 的組成也不同），共用建構流程只會綁手綁腳。

/**
 * 扇形命中判定。
 * @param {object[]} mobs      怪物清單（需有 pos 與 state）
 * @param {{x:number,z:number}} origin 攻擊者位置
 * @param {number} yaw         攻擊朝向
 * @param {number} range       判定半徑
 * @param {number} arc         扇形角（>= 2π 視為全周）
 * @param {number} mobR        怪物的命中半徑
 * @param {number} deadState   代表「已消散」的 state 值（跳過不判定）
 * @returns {object[]} 被打中的怪物
 */
export function sectorHits(mobs, origin, yaw, range, arc, mobR, deadState) {
  const hit = [];
  const fx = Math.sin(yaw), fz = Math.cos(yaw);
  const cosHalf = Math.cos(arc / 2);
  const full = arc >= Math.PI * 1.99;

  for (const m of mobs) {
    if (m.state === deadState) continue;
    const dx = m.pos.x - origin.x, dz = m.pos.z - origin.z;
    const d = Math.hypot(dx, dz);
    if (d > range + mobR) continue;
    if (!full && d > 1e-4 && (dx * fx + dz * fz) / d < cosHalf) continue;
    hit.push(m);
  }
  return hit;
}

/** 半徑內還活著的數量（連段判定、BGM 之類會想知道） */
export function countAlive(mobs, pos, r, deadState) {
  let n = 0;
  for (const m of mobs) {
    if (m.state === deadState) continue;
    if (Math.hypot(m.pos.x - pos.x, m.pos.z - pos.z) < r) n++;
  }
  return n;
}
