import * as THREE from 'three';
import * as BGU from 'three/addons/utils/BufferGeometryUtils.js';

// ---------------------------------------------------------------------------
// Draw call 是這類場景真正的瓶頸 —— 不是三角形數量。
// 建築全部靜態，可以把世界矩陣烘進頂點後依材質合併成幾個大網格。
// ---------------------------------------------------------------------------

const KEEP_ATTRS = ['position', 'normal', 'uv'];

/**
 * 統一屬性後的幾何複本。合併的前提是每個來源的屬性組完全一致 ——
 * 少一個 uv、多一個 tangent，mergeGeometries 就回 null。
 * @param {THREE.BufferGeometry} geo
 * @param {boolean} [keepColor] 保留既有的頂點色（遠景 LOD 要靠它帶配色）
 */
function normalize(geo, keepColor = false) {
  let g = geo.index ? geo.toNonIndexed() : geo.clone();
  const keep = keepColor ? [...KEEP_ATTRS, 'color'] : KEEP_ATTRS;
  for (const k of Object.keys(g.attributes)) {
    if (!keep.includes(k)) g.deleteAttribute(k);
  }
  if (!g.attributes.normal) g.computeVertexNormals();
  if (!g.attributes.uv) {
    const n = g.attributes.position.count;
    g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(n * 2), 2));
  }
  return g;
}

/** 會動、或不能被合併走的東西 —— 掛上這個就整棵子樹跳過 */
export function keepDynamic(obj) {
  obj.userData.noMerge = true;
  return obj;
}

/** 這個網格能不能被合併走 */
function mergeable(o) {
  if (!o.isMesh) return false;
  if (o.isInstancedMesh || o.isSkinnedMesh || o.isBatchedMesh) return false;
  if (Array.isArray(o.material)) return false;          // 多材質網格
  if (o.geometry?.morphAttributes &&
      Object.keys(o.geometry.morphAttributes).length) return false;
  const m = o.material;
  if (!m) return false;
  // 半透明／不寫深度的東西靠「逐物件由遠到近排序」才畫得對，
  // 合成一顆大網格之後排序單位就沒了 —— 光柱、光環、水面留著各自畫。
  if (m.transparent || m.depthWrite === false) return false;
  return true;
}

/**
 * 把 root 底下的靜態網格依「材質 × 空間格子 × 陰影旗標」合併。
 *
 * 為什麼要分格子：全圖同材質合成一顆網格的話，draw call 會降到最低，
 * 但那顆網格的包圍盒涵蓋整張地圖 —— 視錐裁剪永遠命中，玩家站在神社
 * 也得把山腳的樹一起送進 GPU。切成 cell 公尺見方的格子，鏡頭後面的
 * 格子就整塊被裁掉，兩邊的好處都拿得到。cell = 0 代表不分格。
 *
 * 為什麼要分陰影旗標：castShadow 是逐物件的。地面、遠山本來就設成
 * 不投影，跟會投影的建築合在一起就會被迫一起進 shadow pass。
 *
 * @param {THREE.Object3D} root
 * @param {object} [opts]
 * @param {string[]} [opts.skipNames]  這些名字（含其子樹）保持獨立
 * @param {number}   [opts.cell=60]    空間格子邊長（公尺），0 = 不分格
 * @returns {{before:number, after:number, merged:number, kept:number}}
 */
export function mergeStaticByMaterial(root, opts = {}) {
  // 舊呼叫法 mergeStaticByMaterial(root, ['name']) 仍然可用
  const { skipNames = [], cell = 60 } = Array.isArray(opts) ? { skipNames: opts } : opts;

  root.updateMatrixWorld(true);

  const groups = new Map();     // key → { mat, cast, receive, geos: [] }
  const victims = [];
  let before = 0;
  const box = new THREE.Box3();
  const mid = new THREE.Vector3();
  const matIds = new Map();
  const matId = (m) => {
    if (!matIds.has(m)) matIds.set(m, matIds.size);
    return matIds.get(m);
  };

  root.traverse(o => {
    if (!o.isMesh) return;
    before++;

    // 位於保留子樹內就跳過（名字或 userData.noMerge，含自己）
    for (let p = o; p && p !== root.parent; p = p.parent) {
      if (p.userData?.noMerge || skipNames.includes(p.name)) return;
    }
    if (!mergeable(o)) return;

    const g = normalize(o.geometry);
    g.applyMatrix4(o.matrixWorld);

    // 用世界座標的包圍盒中心決定落在哪個格子
    let cx = 0, cz = 0;
    if (cell > 0) {
      g.computeBoundingBox();
      box.copy(g.boundingBox).getCenter(mid);
      cx = Math.floor(mid.x / cell);
      cz = Math.floor(mid.z / cell);
    }

    const cast = o.castShadow, receive = o.receiveShadow;
    const key = `${matId(o.material)}|${cx}|${cz}|${cast ? 1 : 0}${receive ? 1 : 0}`;
    if (!groups.has(key)) groups.set(key, { mat: o.material, cast, receive, geos: [] });
    groups.get(key).geos.push(g);
    victims.push(o);
  });

  // 從場景圖摘除原件
  for (const o of victims) {
    o.parent?.remove(o);
    o.geometry.dispose();
  }

  let merged = 0;
  for (const { mat, cast, receive, geos } of groups.values()) {
    if (!geos.length) continue;
    const geo = geos.length === 1 ? geos[0] : BGU.mergeGeometries(geos, false);
    if (!geo) {                         // 屬性不相容時 mergeGeometries 回傳 null
      geos.forEach(g => g.dispose());
      continue;
    }
    geos.forEach(g => { if (g !== geo) g.dispose(); });

    const mesh = new THREE.Mesh(geo, mat);
    mesh.castShadow = cast;
    mesh.receiveShadow = receive;
    mesh.matrixAutoUpdate = false;      // 靜態，省掉每幀的矩陣合成
    mesh.updateMatrix();
    mesh.name = 'merged';
    root.add(mesh);
    merged++;
  }

  // 沒被合併、仍各自存在的網格
  let kept = 0;
  root.traverse(o => { if (o.isMesh && o.name !== 'merged') kept++; });

  return { before, after: merged + kept, merged, kept };
}

/**
 * 把幾何瘦身：丟掉用不到的 uv、法線壓成 Int8。
 *
 * 遠景網格是「額外多出來的一份幾何」，一位路人就是 5 千多個三角形，
 * 一條街五十位就是三十幾 MB —— 內顯的顯存是跟系統記憶體共用的，這種
 * 純複製品該壓就壓。共用材質是 MeshToonMaterial + vertexColors，
 * 沒有任何貼圖，uv 完全用不到；法線只拿來算 NdotL 再去查三階漸層圖，
 * Int8（1/127 的精度）綽綽有餘。位置與頂點色維持原精度。
 */
function shrinkAttributes(geo) {
  geo.deleteAttribute('uv');
  const n = geo.attributes.normal;
  if (n && n.array instanceof Float32Array) {
    const q = new Int8Array(n.count * 3);
    for (let i = 0; i < q.length; i++) {
      q[i] = Math.max(-127, Math.min(127, Math.round(n.array[i] * 127)));
    }
    geo.setAttribute('normal', new THREE.BufferAttribute(q, 3, true));
  }
}

/**
 * 把整隻角色（現在的姿勢）壓成單一網格 —— 遠景 LOD 用。
 *
 * optimizeRig 已經把角色壓到「每個動畫節點一個網格」，約 10 個 draw call。
 * 但一條街上五十位路人就是五百個 draw call，而三十公尺外的人只有十幾個
 * 像素高，關節在不在動根本看不出來。這個函式把整隻角色連同姿勢烘成一個
 * 網格，遠景時整組動畫節點關掉、只畫這一個 —— 10 個 draw call 變 1 個，
 * 而且完全不用每幀算動畫。
 *
 * 顏色靠頂點色攜帶（跟 mergeAnimNode 同一招），所以遠景網格也共用
 * 同一份材質，不會多佔 GPU 狀態。
 *
 * @param {THREE.Object3D} root      角色根節點
 * @param {THREE.Material} sharedMat 共用材質（需 vertexColors:true）
 * @param {string[]} [skipNames]     這些名字的子樹不烘（預設跳過描邊外殼）
 * @returns {THREE.Mesh|null}
 */
export function mergeRigSnapshot(root, sharedMat, skipNames = ['outline', 'farLod']) {
  const geos = [];
  const tmp = new THREE.Color();

  const walk = (obj, matrix) => {
    for (const child of obj.children) {
      if (skipNames.includes(child.name)) continue;
      child.updateMatrix();
      const m = matrix.clone().multiply(child.matrix);

      if (child.isMesh && !child.isInstancedMesh) {
        const mat = child.material;
        // 半透明的部件（妖夢的半靈之類）在遠景省掉，混合排序不值得為它留
        if (!Array.isArray(mat) && !mat.transparent) {
          const g = normalize(child.geometry, true);
          g.applyMatrix4(m);
          const cnt = g.attributes.position.count;
          // 已經帶頂點色的（optimizeRig 合併過的部位）沿用原色，
          // 其餘用材質色烘一份 —— 兩種來源合併後才不會有一半變白。
          if (!g.attributes.color) {
            const col = new Float32Array(cnt * 3);
            if (mat.color) tmp.copy(mat.color); else tmp.setHex(0xffffff);
            for (let i = 0; i < cnt; i++) {
              col[i * 3] = tmp.r; col[i * 3 + 1] = tmp.g; col[i * 3 + 2] = tmp.b;
            }
            g.setAttribute('color', new THREE.BufferAttribute(col, 3));
          }
          geos.push(g);
        }
      }
      walk(child, m);
    }
  };

  root.updateMatrix();
  walk(root, new THREE.Matrix4());
  if (!geos.length) return null;

  const merged = geos.length === 1 ? geos[0] : BGU.mergeGeometries(geos, false);
  geos.forEach(g => { if (g !== merged) g.dispose(); });
  if (merged) shrinkAttributes(merged);
  if (!merged) return null;

  const mesh = new THREE.Mesh(merged, sharedMat);
  mesh.castShadow = true;
  mesh.receiveShadow = false;
  mesh.name = 'farLod';
  return mesh;
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
