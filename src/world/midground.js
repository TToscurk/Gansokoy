// 中景層（地圖品質升級書・升級 7 第 1 點）。
//
// 三層景深：玩法層（可走）＋**中景層（走不到但看得清）**＋遠景層（剪影）。
// 多數圖只有玩法層與遠景層 —— 走到邊界，眼前突然從「有細節的世界」跳成
// 「一排剪影」，那個斷層就是「像關卡不像地方」的來源。
//
// 中景要滿足三件事：
//   1. 在玩家走得到的範圍**之外**，但在霧完全吃掉之前
//   2. 有可辨識的形狀（屋頂、田埂），不是一團色塊 —— 遠景才是色塊
//   3. 便宜 —— 它只是背景，不值得花玩法層的預算
//
// 所以這裡的東西都沒有碰撞盒、不投影、能合併就合併。

import * as THREE from 'three';
import * as BGU from 'three/addons/utils/BufferGeometryUtils.js';

function rng(seed = 1) {
  let s = (seed >>> 0) || 1;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0), s / 4294967296);
}

/**
 * 坡地梯田。一階一階往上退的田，每階前緣一道土埂。
 *
 * 為什麼是梯田：它是**人的痕跡**，而且形狀在遠處仍然讀得出來（水平線一條
 * 一條）。同樣的距離擺一片樹林就只是一團綠。
 *
 * @param {THREE.Object3D} world
 * @param {object} o
 * @param {number} o.cx @param {number} o.cz 起點（最低、最靠近玩家的那一階的中心）
 * @param {number} [o.facing=0] 階梯往上退的方向（弧度，繞 Y）。**必須指向遠離
 *        可走範圍的那一側** —— 局部 +z 會被轉到這個方向，一階一階往那邊退。
 * @param {number} [o.steps=6] 幾階
 * @param {number} [o.w=34] 每階寬
 * @param {number} [o.depth=7] 每階進深
 * @param {number} [o.rise=1.8] 每階升高（只在沒給 groundAt 時使用）
 * @param {number} [o.y=0] 起始高度（只在沒給 groundAt 時使用）
 * @param {(x:number,z:number)=>number} [o.groundAt] 地面高度。**山坡上一定要給**：
 *        固定 rise 疊出來的階梯跟不上地形，坡陡一點就整座浮在半空。
 * @param {number|string} [o.field='#7d8a4e'] 田面顏色
 * @param {number|string} [o.bund='#5c6440'] 土埂顏色。**別用裸土色**：坡陡的時候
 *        從坡下往上望是掠射角，看到的幾乎全是埂面，裸土色會讓整片山變成褐色的牆。
 *        真的梯田埂上也是長草的。
 * @param {number} [o.seed=5]
 * @returns {THREE.Group} 田面與土埂各一個合併網格
 */
export function terraces(world, {
  cx, cz, facing = 0, steps = 6, w = 34, depth = 7, rise = 1.8, y = 0,
  groundAt = null, field = '#7d8a4e', bund = '#5c6440', seed = 5,
} = {}) {
  const rand = rng(seed);
  const fieldGeos = [], bundGeos = [];
  const m4 = new THREE.Matrix4();
  const sf = Math.sin(facing), cf = Math.cos(facing);
  // 局部座標 (lx, lz) → 世界座標。取地形高度得用世界座標，不然整組都取到同一點
  const wx = (lx, lz) => cx + lx * cf + lz * sf;
  const wz = (lx, lz) => cz - lx * sf + lz * cf;

  // 每階的進深由**地形坡度**決定，不是給死的。
  //
  // 田面是平的，所以一階的落差 = 進深 × 坡度。人間之里西坡的坡度大約 0.8，
  // 給死 depth = 7 就是每階落差 5.6 公尺 —— 那不是田埂，那是比房子還高的擋土牆
  // （實測畫面上就是一整面褐色的牆，梯田完全讀不出來）。
  // 改成反過來：先定落差（rise，1.8 公尺左右是人爬得上去的高度），再往外找到
  // 地形剛好升高這麼多的位置，那裡就是下一階的界線。坡陡階就窄、坡緩階就寬，
  // 跟真的梯田一樣。depth 於是變成「最寬不超過」的上限。
  const edges = [0];
  if (groundAt) {
    let z = 0;
    for (let i = 0; i < steps; i++) {
      const y0 = groundAt(wx(0, z), wz(0, z));
      let zn = z + 1.4;
      // 0.4 公尺一步往外掃；掃到 depth 還沒升夠就停在 depth（平地不能無限延伸）
      while (zn < z + depth && groundAt(wx(0, zn), wz(0, zn)) < y0 + rise) zn += 0.4;
      edges.push(zn);
      z = zn;
    }
  } else {
    for (let i = 1; i <= steps; i++) edges.push(i * depth);
  }

  let prev = null;
  for (let i = 0; i < steps; i++) {
    // 每階寬窄不一 —— 等寬的梯田是印出來的，不是種出來的
    const ww = w * (0.72 + rand() * 0.5);
    const off = (rand() - 0.5) * w * 0.25;
    const front = edges[i], back = edges[i + 1];
    const dd = back - front;
    // 高度取**後緣**。田面是平的、山坡不是，取哪裡決定田面被埋掉多少：
    //   取中心 → 前半截翹出坡面浮在空中，遠看是一疊飄浮的板子
    //   取前緣 → 除了最前面那條，整片田面全埋進山裡，只剩土埂露出來
    //   取後緣 → 後緣貼著坡，田面整片浮出，前緣與坡面的落差正好給土埂填
    // 只有第三種能同時看到「平的田」與「擋土的埂」，那才讀得出是梯田。
    const yy = groundAt ? groundAt(wx(off, back), wz(off, back)) + 0.15 : y + i * rise;

    const f = new THREE.BoxGeometry(ww, 0.3, dd * 0.96);
    f.applyMatrix4(m4.makeTranslation(off, yy, (front + back) / 2));
    fieldGeos.push(f);

    // 前緣的土埂：擋住這階與前一階的落差。埂頂要跟田面**齊平**，不能高過去 ——
    // 高過去的話從坡下往上望，每一階看到的都是埂的頂面，田面被完全蓋住。
    const drop = prev === null ? rise : Math.max(0.6, yy - prev);
    const bh = drop * 1.3;
    const b = new THREE.BoxGeometry(ww * 1.02, bh, 0.6);
    b.applyMatrix4(m4.makeTranslation(off, yy + 0.15 - bh / 2, front));
    bundGeos.push(b);
    prev = yy;
  }

  // 田面與土埂分兩個材質。同色的話那一條條水平線在遠處就糊成一片，
  // 而「水平線一條一條」正是選梯田當中景的唯一理由。
  const g = new THREE.Group();
  g.position.set(cx, 0, cz);
  g.rotation.y = facing;
  g.userData.midground = true;
  for (const [geos, color] of [[fieldGeos, field], [bundGeos, bund]]) {
    const geo = BGU.mergeGeometries(geos, false);
    geos.forEach(x => x.dispose());
    const mesh = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({
      color, roughness: 1, flatShading: true,
    }));
    mesh.castShadow = false;        // 中景不投影：它離得遠，陰影貼圖的解析度花在這裡是浪費
    mesh.receiveShadow = true;
    mesh.userData.midground = true; // 明確標記：驗證腳本要分得出中景與一般佈景
    g.add(mesh);
  }
  world.add(g);
  return g;
}

/**
 * 遠處的小聚落。幾間只有量體與屋頂的房子 —— 走不到，所以不需要門窗。
 *
 * @param {THREE.Object3D} world
 * @param {object} o
 * @param {number} o.cx @param {number} o.cz 聚落中心
 * @param {(x:number,z:number)=>number} [o.groundAt] 地面高度
 * @param {number} [o.count=5]
 * @param {number} [o.spread=26] 散佈半徑
 * @param {number} [o.scale=1] 整體大小
 * @param {number|string} [o.wall='#c8bda6'] @param {number|string} [o.roof='#4a5058']
 * @param {number} [o.seed=9]
 * @returns {THREE.Group}
 */
export function hamlet(world, {
  cx, cz, groundAt = null, count = 5, spread = 26, scale = 1,
  wall = '#c8bda6', roof = '#4a5058', seed = 9,
} = {}) {
  const rand = rng(seed);
  const g = new THREE.Group();
  g.userData.midground = true;
  world.add(g);

  const wallGeos = [], roofGeos = [];
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion();
  const v = new THREE.Vector3(), s = new THREE.Vector3();

  for (let i = 0; i < count; i++) {
    const a = rand() * Math.PI * 2, d = rand() * spread;
    const x = cx + Math.cos(a) * d, z = cz + Math.sin(a) * d;
    const yy = groundAt ? groundAt(x, z) : 0;
    const w = (5 + rand() * 4) * scale, dp = (4 + rand() * 3) * scale;
    const h = (3 + rand() * 1.6) * scale;
    const rot = rand() * Math.PI;

    q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), rot);

    const body = new THREE.BoxGeometry(w, h, dp);
    body.applyMatrix4(m4.compose(v.set(x, yy + h / 2, z), q, s.set(1, 1, 1)));
    wallGeos.push(body);

    // 屋頂：四角錐壓扁，遠看就是一個「屋頂」的形
    const rf = new THREE.ConeGeometry(Math.max(w, dp) * 0.72, h * 0.55, 4);
    rf.rotateY(Math.PI / 4);
    rf.applyMatrix4(m4.compose(v.set(x, yy + h + h * 0.27, z), q, s.set(1, 1, 1)));
    roofGeos.push(rf);
  }

  const mk = (geos, color) => {
    const geo = BGU.mergeGeometries(geos, false);
    geos.forEach(x => x.dispose());
    const m = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({
      color, roughness: 1, flatShading: true,
    }));
    m.castShadow = false;
    m.receiveShadow = true;
    m.userData.midground = true;
    g.add(m);
  };
  mk(wallGeos, wall);
  mk(roofGeos, roof);
  return g;
}
