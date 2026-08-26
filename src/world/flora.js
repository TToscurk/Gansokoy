// 草叢與雜草 —— 全地圖共用的地被散佈。
//
// 一叢草 = 五片交叉的窄面片合成一個幾何；一張圖幾千叢全部走 InstancedMesh，
// 並依空間格子切開 —— 單一個 InstancedMesh 的包圍盒會涵蓋整張圖，
// 視錐裁剪永遠命中（竹林的竹子踩過同一個坑）。
//
// 草不投影也不接受陰影：幾千叢草進 shadow pass 的成本遠大於觀感收益，
// 而薄面片接受陰影會跟地面的陰影邊界打架。

import * as THREE from 'three';
import * as BGU from 'three/addons/utils/BufferGeometryUtils.js';

/**
 * @param {THREE.Object3D} parent
 * @param {object} o
 * @param {number} o.count 目標叢數（place 回 null 算失敗，最多嘗試 count*3 次）
 * @param {() => [number,number]|null} o.place 給一個 [x,z] 或 null（不合格）
 * @param {(x:number,z:number)=>number} o.heightAt 地面高度
 * @param {number} [o.cell=48] 空間格子邊長
 * @param {number} [o.baseColor=0x557a36] 基色（每叢在色相/明度上抖動）
 * @param {[number,number]} [o.scale=[0.7,1.45]] 叢的縮放範圍
 * @returns {number} 實際種下的叢數
 */
export function scatterGrass(parent, {
  count, place, heightAt,
  cell = 48, baseColor = 0x557a36, scale = [0.7, 1.45],
}) {
  // --- 一叢草的幾何：七片窄葉，繞中心展開、往外翻 ---
  // 葉片要細長。0.14 寬的版本在畫面上是一塊深綠色的楔形，不像草像楔子；
  // 收到 0.075 並加高、加片數之後才讀得出「一叢細草」。
  const blades = [];
  for (let i = 0; i < 7; i++) {
    const g = new THREE.PlaneGeometry(0.075, 0.62);
    g.translate(0, 0.3, 0);                        // 根部在原點
    g.rotateX(0.2 + (i % 3) * 0.13);               // 往外翻，不是筆直一排
    g.rotateY((i / 7) * Math.PI * 2 + i * 0.31);
    blades.push(g);
  }
  const tuftGeo = BGU.mergeGeometries(blades, false);
  blades.forEach(g => { if (g !== tuftGeo) g.dispose(); });

  // 薄面片背面朝光時會全黑（一叢草總有一半的葉子背對太陽）。
  // 給一點自發光把背面拉回草色 —— 不加的話整片草地看起來像撒了一地炭。
  const mat = new THREE.MeshStandardMaterial({
    color: 0xffffff, roughness: 1, side: THREE.DoubleSide, flatShading: true,
    emissive: 0x2a3a1a, emissiveIntensity: 0.55,
  });

  // --- 撒點，按格子分桶 ---
  const cells = new Map();
  const key = (x, z) => `${Math.floor(x / cell)},${Math.floor(z / cell)}`;
  let placed = 0;
  for (let t = 0; t < count * 3 && placed < count; t++) {
    const p = place();
    if (!p) continue;
    const k = key(p[0], p[1]);
    if (!cells.has(k)) cells.set(k, []);
    cells.get(k).push(p);
    placed++;
  }

  // --- 每格一個 InstancedMesh ---
  const m4 = new THREE.Matrix4();
  const q = new THREE.Quaternion();
  const e = new THREE.Euler();
  const v = new THREE.Vector3();
  const s = new THREE.Vector3();
  const col = new THREE.Color();
  const base = new THREE.Color(baseColor);

  for (const list of cells.values()) {
    const im = new THREE.InstancedMesh(tuftGeo, mat, list.length);
    im.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(list.length * 3), 3);
    im.castShadow = false;
    im.receiveShadow = false;
    list.forEach(([x, z], i) => {
      const sc = scale[0] + Math.random() * (scale[1] - scale[0]);
      e.set(0, Math.random() * Math.PI * 2, (Math.random() - 0.5) * 0.12);
      q.setFromEuler(e);
      s.set(sc, sc * (0.85 + Math.random() * 0.4), sc);
      // 根部往下埋 3cm，起伏地上才不會有懸空的叢
      m4.compose(v.set(x, heightAt(x, z) - 0.03, z), q, s);
      im.setMatrixAt(i, m4);
      // 色相與明度都抖：一片草地不該是同一個綠
      col.copy(base).offsetHSL((Math.random() - 0.5) * 0.045, 0, (Math.random() - 0.5) * 0.12);
      im.setColorAt(i, col);
    });
    im.instanceColor.needsUpdate = true;
    parent.add(im);
  }
  return placed;
}
