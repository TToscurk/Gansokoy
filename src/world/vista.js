// 遠景稜線環 —— 把「邊坡頂著天空」的地平線補起來，全地圖共用。
//
// 每張圖的邊界靠圍坡＋座標夾制把玩家收在圖裡，這沒問題；問題是視覺：
// 站在圖中央環顧一圈，只要有一個方向是「土牆上緣直接切斷天空」，
// 玩家就知道「世界到這裡就沒了」—— 過場感的最大來源。
//
// 解法不是拆邊坡（獸道是山谷，谷壁天經地義），而是在邊坡上緣**之外**
// 再鋪一層更遠的東西：遠山稜線、更高處的樹冠剪影，罩在霧色裡。
// 剪影只做「一眼認得出是山/是樹」的程度，細節靠霧遮。
//
// 工法：
// - MeshBasicMaterial（不受光、吃霧色）—— 剪影的顏色會被每張圖的霧
//   自動調成當下時刻的遠景色，晨昏雨霧全部免費跟著變。
// - castShadow/receiveShadow 全關：邊界外一百公尺的東西進 shadow pass
//   純粹是浪費。
// - **建構時就自行按「材質 × 象限」烘成最多 12 顆網格**並掛
//   userData.noMerge —— 交給 mergeStaticByMaterial 的話，格子是為
//   場內物件挑的（40~60m），一圈半徑四百公尺的環會被切成幾十顆、
//   幾十個 draw call。環永遠在遠處，象限級的視錐裁剪就夠了。
// - 兩層深度（近層稜線＋遠層更高的稜線），走近邊界時有視差，
//   不會像一張貼在天上的畫。
// - 決定性亂數（LCG）：每次重整長一樣。
// - 傳送點方向留缺口（gap）—— 那些方向已經有各圖手工做的目的地剪影
//   （里的屋頂、竹梢、花田……），稜線疊上去會把它們吃掉。

import * as THREE from 'three';
import * as BGU from 'three/addons/utils/BufferGeometryUtils.js';

/**
 * 在地圖外圍一圈鋪遠山稜線（含可選的樹冠層）。
 *
 * @param {THREE.Object3D} world
 * @param {object} o
 * @param {number} o.radius      環的半徑（放地圖邊界外 60–150m）
 * @param {(x:number,z:number)=>number} [o.heightAt] 地面高度（山腳貼地用；不給就取 0）
 * @param {number[]} [o.height=[36,64]]  山高範圍 [min,max]
 * @param {number|string} [o.color=0x46584e]  稜線基色（會被霧染）
 * @param {{angle:number, span:number}[]} [o.gaps]  留缺口的方向
 *        angle 用 atan2(x, z) 的口徑（+z 為 0、+x 為 π/2），span 是整個缺口的弧度
 * @param {number} [o.count=26]  近層山的數量
 * @param {boolean} [o.treeTops=false]  稜線上緣再撒一排樹冠剪影（林地圖用）
 * @param {number} [o.seed=7]
 * @returns {THREE.Group}
 */
export function ridgeRing(world, {
  radius, heightAt = () => 0,
  height = [36, 64], color = 0x46584e, gaps = [],
  count = 26, treeTops = false, seed = 7,
} = {}) {
  let s = (seed * 2654435761) >>> 0;
  const rand = () => ((s = (s * 1664525 + 1013904223) >>> 0), s / 4294967296);
  const rr = (a, b) => a + rand() * (b - a);

  const g = new THREE.Group();
  world.add(g);

  const inGap = (a) => gaps.some(({ angle, span }) => {
    let d = a - angle;
    while (d > Math.PI) d -= Math.PI * 2;
    while (d < -Math.PI) d += Math.PI * 2;
    return Math.abs(d) < span / 2;
  });

  const c = new THREE.Color(color);
  // 遠層比近層更「退」：更暗一點點就夠了，剩下交給霧
  const MATS = [
    new THREE.MeshBasicMaterial({ color: c }),                            // 0 近層
    new THREE.MeshBasicMaterial({ color: c.clone().multiplyScalar(0.82) }), // 1 遠層
    new THREE.MeshBasicMaterial({ color: c.clone().multiplyScalar(0.9) }),  // 2 樹冠
  ];

  // 幾何桶：材質 × 象限。最後每桶烘成一顆網格 —— 環的 draw call
  // 上限 12，實際入鏡多半只有 3~6。
  const buckets = Array.from({ length: 12 }, () => []);
  const quadOf = (a) => {
    const q = Math.floor(((a % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2) / (Math.PI / 2));
    return Math.min(3, q);
  };
  const m4 = new THREE.Matrix4();
  const pos = new THREE.Vector3(), quat = new THREE.Quaternion(), scl = new THREE.Vector3();
  const eul = new THREE.Euler();

  function bake(geo, x, y, z, yaw, sx, sy, sz, mi, a) {
    eul.set(0, yaw, 0);
    quat.setFromEuler(eul);
    m4.compose(pos.set(x, y, z), quat, scl.set(sx, sy, sz));
    geo.applyMatrix4(m4);
    buckets[mi * 4 + quadOf(a)].push(geo);
  }

  /** 一座剪影山：低模圓錐，壓扁一點才像稜線不像金字塔 */
  function peak(a, r, h, mi) {
    const w = h * rr(1.3, 2.2);
    const x = Math.sin(a) * r, z = Math.cos(a) * r;
    bake(new THREE.ConeGeometry(w, h, 5), x, heightAt(x, z) + h * 0.42, z,
      rand() * Math.PI, 1, 1, rr(0.5, 0.8), mi, a);
  }

  // 近層：沿環擺，角度加擾動，缺口跳過
  for (let i = 0; i < count; i++) {
    const a = (i / count) * Math.PI * 2 + rr(-0.06, 0.06);
    if (inGap(a)) continue;
    peak(a, radius * rr(0.97, 1.08), rr(height[0], height[1]), 0);
  }
  // 遠層：更遠、更高、更疏 —— 兩層錯開才有視差
  for (let i = 0; i < Math.ceil(count * 0.6); i++) {
    const a = (i / (count * 0.6)) * Math.PI * 2 + rr(-0.1, 0.1) + 0.12;
    if (inGap(a)) continue;
    peak(a, radius * rr(1.25, 1.45), rr(height[1] * 0.9, height[1] * 1.5), 1);
  }
  // 樹冠層：貼著近層稜線的腳，撒一排球剪影 —— 林地圖的「更高處的樹冠」
  if (treeTops) {
    for (let i = 0; i < count * 2; i++) {
      const a = (i / (count * 2)) * Math.PI * 2 + rr(-0.05, 0.05);
      if (inGap(a)) continue;
      const r = radius * rr(0.88, 0.98);
      const size = rr(6, 12);
      const x = Math.sin(a) * r, z = Math.cos(a) * r;
      bake(new THREE.IcosahedronGeometry(size, 0), x, heightAt(x, z) + size * rr(0.8, 1.6), z,
        0, 1, 0.7, 1, 2, a);
    }
  }

  buckets.forEach((list, bi) => {
    if (!list.length) return;
    const merged = BGU.mergeGeometries(list, false);
    list.forEach(x => { if (x !== merged) x.dispose(); });
    const m = new THREE.Mesh(merged, MATS[Math.floor(bi / 4)]);
    m.castShadow = m.receiveShadow = false;
    m.userData.noMerge = true;      // 已經自己烘好了，通用合併別再碰
    g.add(m);
  });
  return g;
}

/** 出入口座標 → gaps 條目的小工具（角度口徑跟 ridgeRing 一致） */
export function gapToward(x, z, span = 0.6) {
  return { angle: Math.atan2(x, z), span };
}

// 霧牆貼圖全地圖共用一份 —— 每個傳送點各畫一張 256×256 的 canvas 太浪費
let _mistTex = null;
function mistTexture() {
  if (_mistTex) return _mistTex;
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(64, 64, 8, 64, 64, 64);
  grad.addColorStop(0, 'rgba(255,255,255,0.85)');
  grad.addColorStop(0.55, 'rgba(255,255,255,0.4)');
  grad.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 128, 128);
  _mistTex = new THREE.CanvasTexture(c);
  return _mistTex;
}

/**
 * 傳送點的「門後景深」—— 光點後方一面半透明霧牆，顏色取目的地的霧色。
 * 目的地剪影（各圖已有）在牆後面，隔著這層霧看 = 「透過門隱約看得到
 * 那邊的世界」。牆是廣告板（永遠面向鏡頭），走近時剪影與霧牆的相對
 * 位移就是視差，不用 shader。
 *
 * @param {THREE.Object3D} world
 * @param {number} x @param {number} y 地面高度 @param {number} z 傳送點位置
 * @param {object} o
 * @param {number} o.away  牆放在傳送點「外側」多遠（沿圖心 → 傳送點的方向）
 * @param {number|string} o.color  目的地的霧色（config REGIONS 的 fog）
 * @param {number} [o.w=26] @param {number} [o.h=13]
 */
export function portalMist(world, x, y, z, { away = 12, color = 0xcccccc, w = 26, h = 13 } = {}) {
  const len = Math.hypot(x, z) || 1;
  const mx = x + (x / len) * away, mz = z + (z / len) * away;
  const m = new THREE.Sprite(new THREE.SpriteMaterial({
    map: mistTexture(), color,
    transparent: true, opacity: 0.55,
    depthWrite: false,               // 不寫深度：後面的剪影照樣畫，只是被染霧
  }));
  m.position.set(mx, y + h * 0.34, mz);
  m.scale.set(w, h, 1);
  m.userData.noMerge = true;
  m.castShadow = m.receiveShadow = false;
  world.add(m);
  return m;
}
