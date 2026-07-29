import * as THREE from 'three';
import * as BGU from 'three/addons/utils/BufferGeometryUtils.js';

// ---------------------------------------------------------------------------
// Draw call 是這類場景真正的瓶頸 —— 不是三角形數量。
// 建築全部靜態，可以把世界矩陣烘進頂點後依材質合併成幾個大網格。
// ---------------------------------------------------------------------------

const KEEP_ATTRS = ['position', 'normal', 'uv'];

function normalize(geo) {
  let g = geo.index ? geo.toNonIndexed() : geo.clone();
  for (const k of Object.keys(g.attributes)) {
    if (!KEEP_ATTRS.includes(k)) g.deleteAttribute(k);
  }
  if (!g.attributes.normal) g.computeVertexNormals();
  if (!g.attributes.uv) {
    const n = g.attributes.position.count;
    g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(n * 2), 2));
  }
  return g;
}

/**
 * 把 root 底下的靜態網格依材質合併。
 * @param {THREE.Object3D} root
 * @param {string[]} skipNames  這些名字（含其子樹）保持獨立，通常是會動的東西
 * @returns {{before:number, after:number}}
 */
export function mergeStaticByMaterial(root, skipNames = []) {
  root.updateMatrixWorld(true);

  const byMat = new Map();
  const victims = [];
  let before = 0;

  root.traverse(o => {
    if (!o.isMesh || o.isInstancedMesh) return;
    before++;

    // 若位於保留子樹內，跳過
    for (let p = o; p && p !== root.parent; p = p.parent) {
      if (skipNames.includes(p.name)) return;
    }
    // 多材質網格不處理
    if (Array.isArray(o.material)) return;

    const g = normalize(o.geometry);
    g.applyMatrix4(o.matrixWorld);

    if (!byMat.has(o.material)) byMat.set(o.material, []);
    byMat.get(o.material).push(g);
    victims.push(o);
  });

  // 從場景圖摘除原件
  for (const o of victims) {
    o.parent?.remove(o);
    o.geometry.dispose();
  }

  let after = 0;
  for (const [mat, geos] of byMat) {
    if (!geos.length) continue;
    const merged = geos.length === 1 ? geos[0] : BGU.mergeGeometries(geos, false);
    if (!merged) continue;               // 屬性不相容時 mergeGeometries 回傳 null
    geos.forEach(g => { if (g !== merged) g.dispose(); });

    const mesh = new THREE.Mesh(merged, mat);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    mesh.matrixAutoUpdate = false;
    mesh.name = 'merged';
    root.add(mesh);
    after++;
  }

  // 保留下來、仍需獨立存在的網格
  root.traverse(o => { if (o.isMesh && o.name !== 'merged') after++; });

  return { before, after };
}

/**
 * 沿頂點法線外推出描邊外殼。
 * 這才是正確的反向外殼做法 —— 等比放大會讓細長物件（手腳、劍）的描邊厚度失真。
 */
export function shellGeometry(geo, thickness) {
  const g = geo.clone();
  if (!g.attributes.normal) g.computeVertexNormals();
  const p = g.attributes.position;
  const n = g.attributes.normal;
  for (let i = 0; i < p.count; i++) {
    p.setXYZ(
      i,
      p.getX(i) + n.getX(i) * thickness,
      p.getY(i) + n.getY(i) * thickness,
      p.getZ(i) + n.getZ(i) * thickness
    );
  }
  p.needsUpdate = true;
  // 外殼只需要位置，把其他屬性丟掉省記憶體
  g.deleteAttribute('uv');
  return g;
}

/**
 * 把一個動畫節點底下的葉網格合併成單一網格。
 * 每個原網格的材質顏色會烘成頂點色，因此合併後仍保有配色。
 *
 * @param {THREE.Object3D} node       動畫節點（其 transform 會被動畫驅動）
 * @param {string[]} stopNames        遇到這些名字的子節點就停止（它們是別的動畫節點）
 * @param {THREE.Material} sharedMat  合併後使用的共用材質（需 vertexColors:true）
 */
export function mergeAnimNode(node, stopNames, sharedMat) {
  const geos = [];
  const victims = [];

  const walk = (obj, matrix) => {
    for (const child of [...obj.children]) {
      if (stopNames.includes(child.name)) continue;

      // part() 只設了 position/rotation，matrix 尚未合成
      child.updateMatrix();
      const m = matrix.clone().multiply(child.matrix);

      if (child.isMesh && !child.isInstancedMesh) {
        const mat = child.material;
        // 只合併「單純的」卡通材質：有貼圖、透明或自發光的留著各自畫
        const simple = mat.isMeshToonMaterial && !mat.map && !mat.transparent
          && (!mat.emissive || mat.emissive.getHex() === 0);
        if (simple && !child.userData.noMerge) {
          const g = normalize(child.geometry);
          g.applyMatrix4(m);
          const cnt = g.attributes.position.count;
          const col = new Float32Array(cnt * 3);
          const c = mat.color;
          for (let i = 0; i < cnt; i++) {
            col[i * 3] = c.r; col[i * 3 + 1] = c.g; col[i * 3 + 2] = c.b;
          }
          g.setAttribute('color', new THREE.BufferAttribute(col, 3));
          geos.push(g);
          victims.push(child);
        }
      }
      walk(child, m);
    }
  };

  node.updateMatrix();
  walk(node, new THREE.Matrix4());

  for (const o of victims) {
    o.parent?.remove(o);
    o.geometry.dispose();
  }

  if (!geos.length) return null;

  const merged = geos.length === 1 ? geos[0] : BGU.mergeGeometries(geos, false);
  geos.forEach(g => { if (g !== merged) g.dispose(); });
  if (!merged) return null;

  const mesh = new THREE.Mesh(merged, sharedMat);
  mesh.castShadow = true;
  mesh.name = 'merged';
  node.add(mesh);
  return mesh;
}
