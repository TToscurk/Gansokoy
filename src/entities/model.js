import * as THREE from 'three';
import * as BGU from 'three/addons/utils/BufferGeometryUtils.js';
import { mergeAnimNode, shellGeometry, mergeRigSnapshot } from '../core/optimize.js';

// ---------------------------------------------------------------------------
// 角色建模：全部用基本體組出來，卡通著色 + 反向外殼描邊。
// 不是寫實建模，但剪影與配色足以一眼認出是誰 —— 這正是東方角色的辨識邏輯。
// ---------------------------------------------------------------------------

let GRADIENT = null;
function gradientMap(steps = 4) {
  if (GRADIENT) return GRADIENT;
  const d = new Uint8Array(steps);
  for (let i = 0; i < steps; i++) d[i] = Math.round((i / (steps - 1)) * 255);
  const t = new THREE.DataTexture(d, steps, 1, THREE.RedFormat);
  t.minFilter = t.magFilter = THREE.NearestFilter;
  t.needsUpdate = true;
  GRADIENT = t;
  return t;
}

const matCache = new Map();
function toon(color, emissive = 0x000000, ei = 0) {
  const key = `${color}-${emissive}-${ei}`;
  if (matCache.has(key)) return matCache.get(key);
  const m = new THREE.MeshToonMaterial({
    color, gradientMap: gradientMap(3),
    emissive, emissiveIntensity: ei,
  });
  matCache.set(key, m);
  return m;
}

// 裙子是開口圓柱，必須雙面 —— 併進單面的共用材質會從下方看穿。
const dsCache = new Map();
function toonDS(color) {
  if (dsCache.has(color)) return dsCache.get(color);
  const m = new THREE.MeshToonMaterial({
    color, gradientMap: gradientMap(3), side: THREE.DoubleSide,
  });
  dsCache.set(color, m);
  return m;
}


/* ─────────────────────────────────────────────── 眼睛（貼圖式） ── */

// 眼睛改用貼圖而不是疊小球（角色書 4.3）。
// 這一項對「像不像人」的影響遠大於幾何精細度，而且**更便宜** ——
// 原本一隻眼是「眼白球 + 高光球」兩顆 14×10 的球（約 500 個三角形），
// 現在是一片 6×4 的微凸面片（48 個），虹膜、瞳孔、高光全在貼圖裡。
//
// 貼圖做成上下兩格（上＝睜眼、下＝閉眼），眨眼只要把 map.offset.y
// 從 0.5 切到 0，不用動幾何 —— 之後要加眨眼動畫時直接用。
const eyeTexCache = new Map();
function eyeTexture(irisHex) {
  if (eyeTexCache.has(irisHex)) return eyeTexCache.get(irisHex);
  const W = 128, H = 256;                    // 兩格，每格 128×128
  const c = document.createElement('canvas');
  c.width = W; c.height = H;
  const g = c.getContext('2d', { willReadFrequently: true });
  const iris = new THREE.Color(irisHex);
  const hex = (col) => '#' + col.getHexString();

  g.clearRect(0, 0, W, H);

  // --- 上格：睜眼 ---
  // 眼型：杏仁形。上緣弧度大、下緣平 —— 這是「眼睛」而不是「圓孔」的關鍵
  const eye = (yOff) => {
    g.save();
    g.beginPath();
    g.moveTo(6, 64 + yOff);
    g.quadraticCurveTo(64, 4 + yOff, 122, 64 + yOff);
    g.quadraticCurveTo(64, 116 + yOff, 6, 64 + yOff);
    g.closePath();
    return g;
  };
  eye(0).clip();
  g.fillStyle = '#f6f2ee'; g.fillRect(0, 0, W, 128);          // 眼白（不是純白，純白會太跳）
  // 上眼瞼投影：眼球是球，上半本來就該暗
  const lid = g.createLinearGradient(0, 0, 0, 128);
  lid.addColorStop(0, 'rgba(90,70,80,.42)');
  lid.addColorStop(0.42, 'rgba(90,70,80,0)');
  g.fillStyle = lid; g.fillRect(0, 0, W, 128);
  // 虹膜
  const IX = 64, IY = 66, IR = 30;
  g.fillStyle = hex(iris.clone().multiplyScalar(0.82));
  g.beginPath(); g.arc(IX, IY, IR, 0, 7); g.fill();
  // 虹膜的放射狀纖維：一圈深淺交錯的細線，沒有這個虹膜會像一塊色紙
  for (let i = 0; i < 46; i++) {
    const a = (i / 46) * Math.PI * 2;
    const k = 0.6 + ((i * 7919) % 100) / 250;
    g.strokeStyle = hex(iris.clone().multiplyScalar(k));
    g.lineWidth = 1.6;
    g.beginPath();
    g.moveTo(IX + Math.cos(a) * IR * 0.32, IY + Math.sin(a) * IR * 0.32);
    g.lineTo(IX + Math.cos(a) * IR * 0.96, IY + Math.sin(a) * IR * 0.96);
    g.stroke();
  }
  // 虹膜外緣的深色環（limbal ring）—— 少了它眼睛會顯得沒有精神
  g.strokeStyle = hex(iris.clone().multiplyScalar(0.38));
  g.lineWidth = 4;
  g.beginPath(); g.arc(IX, IY, IR - 1.5, 0, 7); g.stroke();
  // 瞳孔
  g.fillStyle = '#171015';
  g.beginPath(); g.arc(IX, IY, IR * 0.42, 0, 7); g.fill();
  // 高光：主高光在左上、補光在右下，兩個才有濕潤感
  g.fillStyle = 'rgba(255,255,255,.92)';
  g.beginPath(); g.arc(IX - 11, IY - 12, 8, 0, 7); g.fill();
  g.fillStyle = 'rgba(255,255,255,.45)';
  g.beginPath(); g.arc(IX + 13, IY + 12, 4.2, 0, 7); g.fill();
  g.restore();

  // 眼線：沿上緣描一道，卡通臉的眼睛全靠這條撐起來
  g.strokeStyle = 'rgba(32,22,30,.92)';
  g.lineWidth = 7; g.lineCap = 'round';
  g.beginPath();
  g.moveTo(8, 62); g.quadraticCurveTo(64, 8, 120, 62);
  g.stroke();

  // --- 下格：閉眼（只有一道弧線）---
  g.strokeStyle = 'rgba(32,22,30,.92)';
  g.lineWidth = 6;
  g.beginPath();
  g.moveTo(10, 128 + 62); g.quadraticCurveTo(64, 128 + 84, 118, 128 + 62);
  g.stroke();

  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
  t.repeat.set(1, 0.5);
  t.offset.set(0, 0.5);            // 預設睜眼（上格）；眨眼把 y 改成 0
  t.anisotropy = 4;
  eyeTexCache.set(irisHex, t);
  return t;
}

/** 微凸的眼睛面片。平面片貼在球面臉上會露出邊緣，鼓一點才貼得住。 */
function eyePatch(w, h, bulge) {
  const g = new THREE.PlaneGeometry(w, h, 6, 4);
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i) / (w / 2), y = p.getY(i) / (h / 2);
    p.setZ(i, Math.max(0, 1 - x * x * 0.9 - y * y * 0.9) * bulge);
  }
  g.computeVertexNormals();
  return g;
}

const eyeMatCache = new Map();
function eyeMaterial(irisHex) {
  if (eyeMatCache.has(irisHex)) return eyeMatCache.get(irisHex);
  const m = new THREE.MeshToonMaterial({
    map: eyeTexture(irisHex), gradientMap: gradientMap(3),
    transparent: true, alphaTest: 0.35,   // alphaTest 而不是純 transparent：省掉排序，也不會被描邊蓋
    depthWrite: true,
  });
  eyeMatCache.set(irisHex, m);
  return m;
}

const OUTLINE = new THREE.MeshBasicMaterial({
  color: 0x1a1420, side: THREE.BackSide, fog: true,
});

// 所有角色的可合併部位共用這一份材質 —— 顏色改由頂點色攜帶，
// 於是 16 個角色的幾十個部位可以共享同一個 GPU 狀態。
const TOON_VC = new THREE.MeshToonMaterial({
  vertexColors: true, gradientMap: gradientMap(3),
});

// 輪廓光（rim light）：逆光時角色邊緣泛起一層光，是動畫感的關鍵。
// uniform 由主迴圈依日光色溫更新（見 main.js 的 updateRim）。
export const RIM = {
  uRimColor: { value: new THREE.Color(0xfff0dd) },
  uRimStrength: { value: 0.6 },
};
TOON_VC.onBeforeCompile = (sh) => {
  sh.uniforms.uRimColor = RIM.uRimColor;
  sh.uniforms.uRimStrength = RIM.uRimStrength;
  sh.fragmentShader = sh.fragmentShader
    .replace('#include <common>', `#include <common>
      uniform vec3 uRimColor;
      uniform float uRimStrength;`)
    .replace('#include <opaque_fragment>', `
      {
        vec3 rimViewDir = normalize(vViewPosition);
        float rimF = 1.0 - saturate(dot(rimViewDir, normal));
        outgoingLight += uRimColor * pow(rimF, 3.0) * uRimStrength;
      }
      #include <opaque_fragment>`);
};

// ---- 尺寸常數 ----
const LEG_H = 0.72;
const TORSO_H = 0.50;
const HEAD_R = 0.235;
const SHOULDER_Y = LEG_H + TORSO_H - 0.06;   // 1.16
const HEAD_Y = LEG_H + TORSO_H + HEAD_R * 0.92;

// ---------------------------------------------------------------------------
function part(geo, mat, x = 0, y = 0, z = 0) {
  const m = new THREE.Mesh(geo, mat);
  m.position.set(x, y, z);
  m.castShadow = true;
  m.receiveShadow = false;
  return m;
}

// seg 預設 18（升級書第 1 章）。CylinderGeometry 的側面法線本來就是沿
// 圓周平滑的，頂底面則是硬邊 —— 這正是書上要的「側面平滑、頂底硬邊」，
// 所以不必再呼叫 computeVertexNormals()，段數才是稜線的唯一來源。
// 手指、骨架那種一公分級的零件維持低段數，加了也看不到。
function tapered(rTop, rBot, h, seg = 18) {
  const g = new THREE.CylinderGeometry(rTop, rBot, h, seg, 1);
  return g;
}


/**
 * 紡錘形肢體（角色書第 3 章）。
 *
 * tapered() 是線性收縮的圓錐台，真實肢體是**中段粗、兩端細**（肌肉）。
 * 這裡吃一組沿長度的半徑控制點，用 Catmull-Rom 風格的線性插值長出剖面
 * ——一行參數就能捏出肌肉起伏。
 *
 * flat < 1 時橫截面壓成橢圓（x : z = 1 : flat）。前臂偏扁、小腿偏後鼓，
 * 正圓的四肢是「這是圓柱不是手」的第二個來源。
 *
 * 用 LatheGeometry 而不是自己疊 BufferGeometry：它會沿輪廓線自動生出
 * 正確的側面法線（跟 CylinderGeometry 同一套），不必再處理接縫。
 *
 * @param {number[]} profile 由頂到底的半徑控制點，至少兩個
 * @param {number} h 全長
 * @param {number} [seg=20] 圓周段數
 * @param {number} [flat=1] 橫截面的 z/x 比
 */
function limb(profile, h, seg = 20, flat = 1) {
  // 沿長度取樣幾圈。剖面只有 4 個控制點，12 圈是浪費 —— 實測 12 圈會讓
  // 角色面數比原本 +90%（超出升級書預估的 +60~80%），6 圈的起伏一樣順。
  const RINGS = 6;
  const pts = [];
  for (let i = 0; i <= RINGS; i++) {
    const t = i / RINGS;                  // 0 = 頂, 1 = 底
    const f = t * (profile.length - 1);
    const i0 = Math.min(profile.length - 1, Math.floor(f));
    const i1 = Math.min(profile.length - 1, i0 + 1);
    const r = profile[i0] + (profile[i1] - profile[i0]) * (f - i0);
    pts.push(new THREE.Vector2(Math.max(1e-4, r), h / 2 - t * h));
  }
  const g = new THREE.LatheGeometry(pts, seg);
  if (flat !== 1) {
    const p = g.attributes.position;
    for (let i = 0; i < p.count; i++) p.setZ(i, p.getZ(i) * flat);
    g.computeVertexNormals();
  }
  return g;
}

// 每個「動畫節點」的 transform 會被 animateCharacter 驅動，
// 因此合併只能在節點內部進行，不能跨節點。
// blade/sheath 也在列 —— 刀身要能離開腰間握到手上，就不能被合併進軀幹。
const ANIM_NODES = ['head', 'hairBack', 'armL', 'armR', 'legL', 'legR', 'wingL', 'wingR',
  'blade', 'sheath'];

/**
 * 把角色壓成少數幾個 draw call，並補上沿法線外推的描邊。
 * 一個角色原本約 48 個網格，處理後降到 20 個左右，而且全部共用兩份材質。
 */
/* thickness 0.02 → 0.014（角色書第 6 章）。段數提高、眼睛改貼圖之後，
 * 原本的 0.02 會顯得過粗，臉部尤其糊 —— 所以 head 節點再細一階。
 * 刀身的 ×0.45 特例保留。 */
function optimizeRig(root, thickness = 0.014) {
  const nodes = [];
  root.traverse(o => {
    if (o.name === 'body' || ANIM_NODES.includes(o.name)) nodes.push(o);
  });

  for (const node of nodes) {
    // body 底下還掛著其他動畫節點，合併時必須避開
    const stops = ANIM_NODES.concat(node.name === 'body' ? ['wings', 'ghost'] : []);
    const merged = mergeAnimNode(node, stops.filter(n => n !== node.name), TOON_VC);
    if (!merged) continue;

    // 刀身厚度只有 1.2cm，用全厚描邊會把它撐成一根棍子
    const th = (node.name === 'blade' || node.name === 'sheath') ? thickness * 0.45
      : node.name === 'head' ? thickness * 0.62      // 臉的描邊太粗會把五官糊掉
      : thickness;
    const shell = new THREE.Mesh(shellGeometry(merged.geometry, th), OUTLINE);
    shell.castShadow = false;
    shell.receiveShadow = false;
    shell.renderOrder = -1;
    shell.name = 'outline';
    node.add(shell);
  }
}

// ---------------------------------------------------------------------------
// 髮型
// ---------------------------------------------------------------------------
function buildHair(style, mat, group, head, pal = {}) {
  const back = new THREE.Group();
  back.name = 'hairBack';

  // 頭髮基底。
  // 只能蓋到眼睛以上 —— 球面片如果一路延伸到 110°，從正面看會把整張臉包住。
  const cap = new THREE.Mesh(
    new THREE.SphereGeometry(HEAD_R * 1.07, 24, 16, 0, Math.PI * 2, 0, Math.PI * 0.40), mat);
  cap.position.y = HEAD_R * 0.02;
  cap.castShadow = true;
  head.add(cap);

  // 後腦與兩側可以蓋得低。theta 的 0 在 -X、π/2 在 +Z，
  // 所以讓開 40°～140° 這段就等於讓開正面。
  const rear = new THREE.Mesh(
    new THREE.SphereGeometry(HEAD_R * 1.06, 24, 16,
      Math.PI * 0.78, Math.PI * 1.44, 0, Math.PI * 0.74), mat);
  rear.castShadow = true;
  head.add(rear);

  // 瀏海：只遮額頭。球面片 theta 0→π 本來就朝著 +Z，不需要再旋轉。
  const bang = new THREE.Mesh(
    new THREE.SphereGeometry(HEAD_R * 1.05, 20, 14,
      Math.PI * 0.16, Math.PI * 0.68, Math.PI * 0.10, Math.PI * 0.30), mat);
  bang.position.set(0, HEAD_R * 0.03, 0.012);
  bang.castShadow = true;
  head.add(bang);

  // 瀏海分片：整片瀏海殼是打底，上面再疊 5 束髮片、長短錯落 ——
  // 沒有這層的話瀏海是一整片光滑曲面，看起來像安全帽。
  // [x 位置, 髮片長, 外偏角(z), 前傾角(x)]
  const FRINGE = [
    [-0.168, 0.128, 0.30, 0.06],
    [-0.088, 0.100, 0.12, 0.03],
    [0.000, 0.088, 0.00, 0.02],
    [0.088, 0.107, -0.12, 0.03],
    [0.168, 0.121, -0.30, 0.06],
  ];
  for (const [fx, flen, rz, rx] of FRINGE) {
    const g = tapered(0.012, 0.052, flen, 7);
    g.translate(0, -flen / 2, 0);
    const f = part(g, mat, fx, HEAD_R * 0.74, HEAD_R * 0.84);
    f.scale.z = 0.55;                    // 壓扁貼臉，才是「髮片」不是「犄角」
    f.rotation.z = rz;
    f.rotation.x = rx;
    head.add(f);
  }

  /* 髮束（角色書第 5 章）。原本是 tapered 圓柱 —— 末端是一個平的圓形切面，
   * 這在剪影上非常明顯（頭髮不會有平的斷面）。改成：
   *   1. 末端收尖：剖面最後一個控制點收到 12%，不收到 0 是因為完全歸零
   *      會在尖端擠出一圈退化三角形，法線會亂掉
   *   2. 橫截面壓扁（flat 0.82）：一束頭髮是扁的，不是圓棍
   *   3. 沿長度輕微內彎：用平方曲線讓髮尾往內收，直棍最假 */
  const strand = (len, r, x, y, z, rx = 0, rz = 0) => {
    const g = limb([r * 0.55, r, r * 0.92, r * 0.12], len, 12, 0.82);
    const pos = g.attributes.position;
    for (let i = 0; i < pos.count; i++) {
      const t = (len / 2 - pos.getY(i)) / len;      // 0 = 髮根, 1 = 髮尾
      pos.setZ(i, pos.getZ(i) + t * t * len * 0.11);
    }
    g.computeVertexNormals();
    g.translate(0, -len / 2, 0);
    const m = part(g, mat, x, y, z);
    m.rotation.x = rx; m.rotation.z = rz;
    return m;
  };

  switch (style) {
    case 'long':            // 靈夢：後方長髮 + 側束
      back.add(strand(0.9, 0.15, 0, HEAD_R * 0.7, -0.11));
      back.add(strand(0.55, 0.075, -0.19, HEAD_R * 0.4, 0.02));
      back.add(strand(0.55, 0.075, 0.19, HEAD_R * 0.4, 0.02));
      break;
    case 'longStraight': {  // 咲夜 / 帕秋莉；給 hairTip 時髮尾變色（白蓮的漸層）
      back.add(strand(1.05, 0.17, 0, HEAD_R * 0.7, -0.10));
      back.add(strand(0.72, 0.085, -0.20, HEAD_R * 0.45, 0.0));
      back.add(strand(0.72, 0.085, 0.20, HEAD_R * 0.45, 0.0));
      if (pal.hairTip) {
        const tip = tapered(0.07, 0.15, 0.42, 14);
        tip.translate(0, -0.21, 0);
        back.add(part(tip, toon(pal.hairTip), 0, HEAD_R * 0.7 - 1.05, -0.10));
      }
      break;
    }
    case 'hime': {          // 輝夜：姬髮式 —— 長直髮 + 垂在臉側的齊切髮束
      back.add(strand(1.1, 0.17, 0, HEAD_R * 0.7, -0.10));
      back.add(strand(0.5, 0.07, -0.175, HEAD_R * 0.52, 0.10));
      back.add(strand(0.5, 0.07, 0.175, HEAD_R * 0.52, 0.10));
      break;
    }
    case 'twin':            // 芙蘭 / 帝：雙側束
      back.add(strand(0.62, 0.11, -0.24, HEAD_R * 0.6, -0.02, 0, 0.22));
      back.add(strand(0.62, 0.11, 0.24, HEAD_R * 0.6, -0.02, 0, -0.22));
      back.add(strand(0.42, 0.12, 0, HEAD_R * 0.6, -0.11));
      break;
    case 'short':           // 魔理沙 / 慧音
      back.add(strand(0.52, 0.16, 0, HEAD_R * 0.6, -0.09));
      break;
    case 'bob':             // 琪露諾 / 幽幽子
      back.add(strand(0.34, 0.18, 0, HEAD_R * 0.55, -0.07));
      break;
    case 'braid':           // 美鈴：長辮
      for (let i = 0; i < 5; i++) {
        const s = new THREE.Mesh(new THREE.SphereGeometry(0.088 - i * 0.007, 14, 10), mat);
        s.position.set(0, HEAD_R * 0.5 - i * 0.21, -0.13);
        s.castShadow = true;
        back.add(s);
      }
      break;
    case 'bunny':           // 鈴仙：長直髮
      back.add(strand(1.15, 0.16, 0, HEAD_R * 0.7, -0.10));
      break;
    case 'longTied': {      // 低馬尾，髮梢另一個顏色
      const tipMat = toon(pal.hairTip || pal.hair);
      back.add(strand(0.34, 0.17, 0, HEAD_R * 0.62, -0.12));   // 束起的根部
      const tail = strand(0.86, 0.125, 0, HEAD_R * 0.28, -0.155);
      back.add(tail);
      const tip = tapered(0.055, 0.115, 0.34, 14);
      tip.translate(0, -0.17, 0);
      const tipMesh = part(tip, tipMat, 0, HEAD_R * 0.28 - 0.86, -0.155);
      back.add(tipMesh);
      break;
    }
  }

  back.position.y = HEAD_Y;
  group.add(back);
  return back;
}

// ---------------------------------------------------------------------------
// 頭飾
// ---------------------------------------------------------------------------
function buildHat(kind, pal, head, group) {
  const acc = toon(pal.accent);
  const rib = toon(pal.ribbon || pal.accent);

  switch (kind) {
    case 'ribbon': {        // 靈夢的大蝴蝶結
      const knot = part(new THREE.SphereGeometry(0.075, 14, 10), rib, 0, HEAD_R * 0.85, -0.13);
      head.add(knot);
      for (const sx of [-1, 1]) {
        const w = new THREE.Mesh(new THREE.SphereGeometry(0.135, 16, 12), rib);
        w.scale.set(1.15, 0.62, 0.42);
        w.position.set(sx * 0.16, HEAD_R * 0.88, -0.16);
        w.rotation.z = sx * 0.42;
        w.castShadow = true;
        head.add(w);
      }
      break;
    }
    case 'witch': {         // 魔理沙的尖帽
      const brim = part(new THREE.CylinderGeometry(0.46, 0.46, 0.035, 20), acc, 0, HEAD_R * 0.92, 0);
      head.add(brim);
      const cone = part(new THREE.ConeGeometry(0.26, 0.46, 16), acc, 0, HEAD_R * 0.92 + 0.24, 0);
      head.add(cone);
      const band = part(new THREE.CylinderGeometry(0.265, 0.275, 0.07, 18), toon(pal.outfit2 || 0xffffff),
        0, HEAD_R * 0.92 + 0.05, 0);
      head.add(band);
      break;
    }
    case 'maid': {          // 咲夜的女僕頭飾
      const b = new THREE.Mesh(new THREE.TorusGeometry(0.17, 0.035, 8, 18, Math.PI), toon(0xffffff));
      b.rotation.set(Math.PI / 2, 0, 0);
      b.position.set(0, HEAD_R * 0.92, 0);
      b.castShadow = true;
      head.add(b);
      for (let i = 0; i < 3; i++) {
        const f = part(new THREE.SphereGeometry(0.045, 8, 6), toon(0xffffff),
          -0.09 + i * 0.09, HEAD_R * 0.96, -0.09);
        head.add(f);
      }
      break;
    }
    case 'mob': {           // 帕秋莉的睡帽
      const c = part(new THREE.CylinderGeometry(0.27, 0.3, 0.16, 16), acc, 0, HEAD_R * 0.95, 0);
      head.add(c);
      const t = part(new THREE.SphereGeometry(0.075, 14, 10), toon(0xffffff), 0, HEAD_R * 0.95 + 0.14, 0);
      head.add(t);
      break;
    }
    case 'star': {          // 蕾米莉亞的頭飾
      const c = part(new THREE.TorusGeometry(0.2, 0.03, 8, 20), acc, 0, HEAD_R * 0.9, 0);
      c.rotation.x = Math.PI / 2;
      head.add(c);
      break;
    }
    case 'beret': {         // 慧音的帽
      const c = part(new THREE.CylinderGeometry(0.3, 0.26, 0.11, 16), acc, 0, HEAD_R * 0.94, 0);
      head.add(c);
      break;
    }
    case 'bunnyEars': {     // 鈴仙的兔耳
      for (const sx of [-1, 1]) {
        const g = tapered(0.05, 0.085, 0.46, 14);
        const e = part(g, toon(pal.hair), sx * 0.12, HEAD_R * 1.35, -0.02);
        e.rotation.z = sx * 0.2;
        e.rotation.x = -0.12;
        head.add(e);
      }
      break;
    }
    case 'hanafuda': {      // 花札耳飾 —— 繼國緣一最好認的標記
      const card = toon(0xf2ece0);
      const ink = toon(0xc2302a);
      for (const sx of [-1, 1]) {
        const c = part(new THREE.BoxGeometry(0.075, 0.14, 0.014), card,
          sx * (HEAD_R * 0.94), -0.055, 0.02);
        c.rotation.z = sx * 0.06;
        head.add(c);
        const mark = part(new THREE.BoxGeometry(0.05, 0.05, 0.018), ink,
          sx * (HEAD_R * 0.94), -0.09, 0.022);
        head.add(mark);
      }
      break;
    }
    case 'gap': {           // 紫的帽子
      const brim = part(new THREE.CylinderGeometry(0.4, 0.4, 0.03, 20), acc, 0, HEAD_R * 0.92, 0);
      head.add(brim);
      const cyl = part(new THREE.CylinderGeometry(0.24, 0.26, 0.2, 16), acc, 0, HEAD_R * 0.92 + 0.11, 0);
      head.add(cyl);
      const rb = part(new THREE.SphereGeometry(0.1, 14, 10), toon(0xd4405a), 0.19, HEAD_R * 0.92 + 0.11, 0.16);
      rb.scale.set(1.2, 0.6, 0.5);
      head.add(rb);
      break;
    }
    case 'nurseCap': {      // 永琳的帽子 —— 平頂小帽 + 正面十字徽
      const c = part(new THREE.CylinderGeometry(0.20, 0.23, 0.13, 14), acc, 0, HEAD_R * 0.95, -0.02);
      head.add(c);
      head.add(part(new THREE.BoxGeometry(0.11, 0.035, 0.02), toon(0xd84048), 0, HEAD_R * 0.97, 0.20));
      head.add(part(new THREE.BoxGeometry(0.035, 0.11, 0.02), toon(0xd84048), 0, HEAD_R * 0.97, 0.20));
      break;
    }
    case 'frogHat': {       // 諏訪子的寬簷帽 —— 帽頂兩顆大眼是靈魂
      const khaki = toon(0xc8b46a);
      const brim = part(new THREE.CylinderGeometry(0.44, 0.46, 0.03, 20), khaki, 0, HEAD_R * 0.9, 0);
      head.add(brim);
      const dome = new THREE.Mesh(new THREE.SphereGeometry(0.24, 20, 14, 0, Math.PI * 2, 0, Math.PI * 0.5), khaki);
      dome.position.set(0, HEAD_R * 0.9, 0);
      dome.castShadow = true;
      head.add(dome);
      for (const sx of [-1, 1]) {
        const eye = part(new THREE.SphereGeometry(0.055, 14, 10), toon(0xf4f0e0), sx * 0.13, HEAD_R * 0.9 + 0.21, 0.12);
        head.add(eye);
        const pupil = part(new THREE.SphereGeometry(0.026, 8, 6), toon(0x2a2028), sx * 0.13, HEAD_R * 0.9 + 0.22, 0.165);
        head.add(pupil);
      }
      break;
    }
    case 'tokin': {         // 文的六角小紅帽，斜戴
      const c = part(new THREE.CylinderGeometry(0.085, 0.13, 0.075, 6), toon(0xd8383a), 0.09, HEAD_R * 0.98, 0.02);
      c.rotation.z = -0.22;
      head.add(c);
      const pom = part(new THREE.SphereGeometry(0.035, 8, 6), toon(0xf4f4f8), 0.145, HEAD_R * 0.98 + 0.06, 0.02);
      head.add(pom);
      break;
    }
    case 'hairpin': {       // 早苗的青蛙髮飾（右側）+ 白蛇髮飾（左側）
      const frog = toon(0x58b060);
      head.add(part(new THREE.SphereGeometry(0.042, 14, 10), frog, 0.155, HEAD_R * 0.55, 0.14));
      for (const sx of [-1, 1]) {
        head.add(part(new THREE.SphereGeometry(0.016, 8, 6), toon(0xf4f4f8), 0.155 + sx * 0.024, HEAD_R * 0.55 + 0.034, 0.168));
      }
      const snake = toon(0xe8e4da);
      head.add(part(new THREE.TorusGeometry(0.05, 0.014, 10, 12), snake, -0.16, HEAD_R * 0.6, 0.12));
      break;
    }
    case 'kasa': {          // 斗笠 —— 里民、旅人的稻草寬簷帽
      const straw = toon(0xc8b070);
      const brim = part(new THREE.ConeGeometry(0.42, 0.16, 12), straw, 0, HEAD_R * 1.02, 0);
      brim.castShadow = true;
      head.add(brim);
      head.add(part(new THREE.ConeGeometry(0.16, 0.12, 10), toon(0xb09858), 0, HEAD_R * 1.02 + 0.1, 0));
      break;
    }
    case 'horns': {         // 萃香的鬼角 —— 額前斜上兩根長角，各綁一圈緞帶
      const horn = toon(0xe8d8c0);
      for (const sx of [-1, 1]) {
        const g = tapered(0.022, 0.062, 0.52, 14);
        const h = part(g, horn, sx * 0.14, HEAD_R * 1.05, 0.1);
        h.rotation.z = sx * 0.5;
        h.rotation.x = -0.55;
        head.add(h);
        // 角上的緞帶結（左紅右紫）
        const rb = part(new THREE.TorusGeometry(0.045, 0.018, 10, 12),
          toon(sx < 0 ? 0xd84048 : 0x7a5abf), sx * 0.205, HEAD_R * 1.05 + 0.17, 0.21);
        rb.rotation.z = sx * 0.5;
        rb.rotation.x = Math.PI / 2 - 0.55;
        head.add(rb);
      }
      break;
    }
  }
}

// ---------------------------------------------------------------------------
// 翅膀
// ---------------------------------------------------------------------------
function buildWings(kind, pal, group) {
  if (kind === 'none') return null;
  const w = new THREE.Group();
  w.name = 'wings';
  w.position.set(0, LEG_H + TORSO_H * 0.62, -0.16);

  if (kind === 'ice') {          // 琪露諾的冰翼
    const mat = new THREE.MeshPhysicalMaterial({
      color: 0xa8e8ff, transmission: 0.72, thickness: 0.4, roughness: 0.08,
      metalness: 0, transparent: true, opacity: 0.85,
      emissive: 0x4fc8ff, emissiveIntensity: 0.35, ior: 1.31,
    });
    for (const sx of [-1, 1]) {
      const side = new THREE.Group();
      for (let i = 0; i < 3; i++) {
        const g = new THREE.OctahedronGeometry(0.19 + i * 0.055, 0);
        const c = new THREE.Mesh(g, mat);
        c.scale.set(0.42, 1.55, 0.3);
        c.position.set(sx * (0.14 + i * 0.15), 0.1 + i * 0.13, -i * 0.05);
        c.rotation.z = sx * (0.28 + i * 0.2);
        c.userData.noOutline = true;
        side.add(c);
      }
      side.name = sx < 0 ? 'wingL' : 'wingR';
      w.add(side);
    }
  } else if (kind === 'bat') {   // 蕾米莉亞的蝙蝠翼
    const mat = toon(0x241826);
    const memb = toon(pal.accent || 0x8a2038);
    for (const sx of [-1, 1]) {
      const side = new THREE.Group();
      for (let i = 0; i < 3; i++) {
        const bone = tapered(0.018, 0.035, 0.62 - i * 0.08, 6);
        bone.translate(0, (0.62 - i * 0.08) / 2, 0);
        const b = new THREE.Mesh(bone, mat);
        b.position.set(sx * 0.11, 0.02, -0.02);
        b.rotation.z = sx * (0.9 + i * 0.42);
        b.rotation.x = -0.2 - i * 0.1;
        b.castShadow = true;
        side.add(b);
        const m = new THREE.Mesh(new THREE.SphereGeometry(0.16, 8, 6), memb);
        m.scale.set(0.9, 0.5, 0.12);
        m.position.set(sx * (0.3 + i * 0.13), 0.12 - i * 0.14, -0.03);
        m.userData.noOutline = true;
        side.add(m);
      }
      side.name = sx < 0 ? 'wingL' : 'wingR';
      w.add(side);
    }
  } else if (kind === 'crystal') {  // 芙蘭的水晶翼
    const mat = new THREE.MeshStandardMaterial({
      color: 0x2a1a24, roughness: 0.5, metalness: 0.3,
    });
    const gems = [0xff4d4d, 0xffb84d, 0xffe84d, 0x6dff6d, 0x4dd8ff, 0x6d6dff, 0xd84dff, 0xff4da8];
    for (const sx of [-1, 1]) {
      const side = new THREE.Group();
      const bar = new THREE.Mesh(tapered(0.02, 0.04, 0.72, 6), mat);
      bar.position.set(sx * 0.12, 0.3, -0.04);
      bar.rotation.z = sx * 0.34;
      side.add(bar);
      for (let i = 0; i < 4; i++) {
        const gm = new THREE.MeshStandardMaterial({
          color: gems[(sx < 0 ? 0 : 4) + i], emissive: gems[(sx < 0 ? 0 : 4) + i],
          emissiveIntensity: 1.5, roughness: 0.1, metalness: 0.2,
        });
        const rod = new THREE.Mesh(tapered(0.012, 0.018, 0.26, 5), mat);
        const gem = new THREE.Mesh(new THREE.OctahedronGeometry(0.075, 0), gm);
        const gx = sx * (0.2 + i * 0.09);
        const gy = 0.16 + i * 0.16;
        rod.position.set(gx, gy, -0.05);
        rod.rotation.z = sx * -0.6;
        gem.position.set(gx + sx * 0.13, gy + 0.09, -0.05);
        gem.userData.noOutline = true;
        side.add(rod, gem);
      }
      side.name = sx < 0 ? 'wingL' : 'wingR';
      w.add(side);
    }
  } else if (kind === 'fairy') {   // 大妖精的透明翅
    const mat = new THREE.MeshPhysicalMaterial({
      color: 0xd8f8ff, transmission: 0.85, roughness: 0.05, thickness: 0.1,
      transparent: true, opacity: 0.55, iridescence: 0.8, ior: 1.2,
    });
    for (const sx of [-1, 1]) {
      const side = new THREE.Group();
      for (let i = 0; i < 2; i++) {
        const p = new THREE.Mesh(new THREE.SphereGeometry(0.3, 16, 12), mat);
        p.scale.set(0.75, 1.25, 0.05);
        p.position.set(sx * 0.26, 0.24 - i * 0.22, -0.06);
        p.rotation.z = sx * (0.5 - i * 0.35);
        p.userData.noOutline = true;
        side.add(p);
      }
      side.name = sx < 0 ? 'wingL' : 'wingR';
      w.add(side);
    }
  }

  group.add(w);
  return w;
}

// ---------------------------------------------------------------------------
// 手持物
// ---------------------------------------------------------------------------
function buildProp(kind, pal) {
  const g = new THREE.Group();
  switch (kind) {
    case 'gohei': {         // 御幣
      g.add(part(tapered(0.022, 0.026, 0.72, 6), toon(0xd8c8a8), 0, 0, 0));
      for (let i = 0; i < 6; i++) {
        const s = part(new THREE.BoxGeometry(0.055, 0.2, 0.012), toon(0xffffff),
          (i % 2 ? 0.05 : -0.05), 0.42 - Math.floor(i / 2) * 0.07, 0);
        s.rotation.z = (i % 2 ? -1 : 1) * 0.35;
        g.add(s);
      }
      break;
    }
    case 'broom': {         // 掃帚
      g.add(part(tapered(0.028, 0.032, 1.35, 6), toon(0x6b4a2f), 0, 0, 0));
      const head = part(new THREE.ConeGeometry(0.13, 0.42, 8), toon(0xc8a45a), 0, -0.78, 0);
      head.rotation.x = Math.PI;
      g.add(head);
      break;
    }
    case 'knife': {         // 咲夜的銀刀
      for (let i = 0; i < 3; i++) {
        const k = part(new THREE.ConeGeometry(0.035, 0.26, 4), toon(0xd8dce4),
          (i - 1) * 0.09, 0.05, 0.02);
        k.rotation.x = Math.PI / 2;
        k.rotation.z = (i - 1) * 0.3;
        g.add(k);
      }
      break;
    }
    case 'spear': {         // 葛　姆　格　尼
      g.add(part(tapered(0.02, 0.024, 1.5, 6), toon(0x3a2a3a), 0, 0, 0));
      const tip = part(new THREE.ConeGeometry(0.07, 0.3, 6), toon(0xd0263a), 0, 0.88, 0);
      g.add(tip);
      break;
    }
    case 'sword': {         // 妖夢的樓觀劍
      const blade = part(new THREE.BoxGeometry(0.045, 1.15, 0.012), toon(0xdde4ec), 0, 0.5, 0);
      g.add(blade);
      g.add(part(new THREE.BoxGeometry(0.16, 0.03, 0.05), toon(0xd9b26a), 0, -0.1, 0));
      g.add(part(tapered(0.026, 0.03, 0.26, 6), toon(0x2a3a5a), 0, -0.24, 0));
      break;
    }
    case 'book': {          // 帕秋莉的魔導書
      g.add(part(new THREE.BoxGeometry(0.32, 0.42, 0.09), toon(0x4a2a5a), 0, 0, 0));
      g.add(part(new THREE.BoxGeometry(0.29, 0.39, 0.1), toon(0xe8e0cd), 0.02, 0, 0));
      break;
    }
    case 'fan': {           // 幽幽子的扇
      const f = part(new THREE.CircleGeometry(0.26, 16, 0, Math.PI * 0.8), toon(0xf4e8f0), 0, 0, 0);
      f.material.side = THREE.DoubleSide;
      g.add(f);
      break;
    }
    case 'parasol': {       // 蕾米莉亞的洋傘
      g.add(part(tapered(0.016, 0.018, 1.0, 6), toon(0x3a2a3a), 0, 0, 0));
      const canopy = part(new THREE.ConeGeometry(0.46, 0.3, 12, 1, true), toon(0xd0263a), 0, 0.62, 0);
      canopy.material.side = THREE.DoubleSide;
      g.add(canopy);
      break;
    }
    case 'gourd': {         // 萃香的「伊吹瓢」—— 喝不完的酒葫蘆
      const purple = toon(0x6a4a8a);
      const lower = part(new THREE.SphereGeometry(0.16, 12, 10), purple, 0, -0.05, 0);
      lower.scale.set(1, 1.1, 1);
      g.add(lower);
      const upper = part(new THREE.SphereGeometry(0.105, 12, 10), purple, 0, 0.17, 0);
      g.add(upper);
      g.add(part(new THREE.CylinderGeometry(0.03, 0.035, 0.09, 8), toon(0x8a6a3a), 0, 0.3, 0));   // 木栓
      // 綁在腰間的紅繩結
      const knot = part(new THREE.TorusGeometry(0.05, 0.016, 10, 12), toon(0xc23a3a), 0, 0.07, 0);
      knot.rotation.x = Math.PI / 2;
      g.add(knot);
      break;
    }
    default: return null;
  }
  g.traverse(o => { if (o.isMesh) o.castShadow = true; });
  return g;
}

// ---------------------------------------------------------------------------
// 日輪刀 —— 刀身與刀鞘分開兩個動畫節點。
//
// 兩者共用同一條「反り」曲線，所以收鞘時刀身完全藏在鞘裡；拔刀時
// combat.js 只搬 blade，sheath 永遠留在腰上。
// 原點都設在鯉口（＝鍔的位置）：blade 的 +Y 是刀尖方向、-Y 是柄。
// ---------------------------------------------------------------------------
export const BLADE_LEN = 0.98;

function buildKatana() {
  const sheath = new THREE.Group(); sheath.name = 'sheath';
  const blade = new THREE.Group();  blade.name = 'blade';

  const SEGS = 5, SORI = 0.055;          // 反り：刀尖往刀背側翹起的總位移
  const h = BLADE_LEN / SEGS;
  const steel = toon(0xc9d2dd), lacquer = toon(0x14121a);

  for (let i = 0; i < SEGS; i++) {
    const t = (i + 0.5) / SEGS;
    const y = t * BLADE_LEN;
    const z = -SORI * t * t;             // 刀背朝 -Z
    const tilt = -(2 * SORI * t / BLADE_LEN) * 0.85;
    // 刀身往刀尖略收，剪影才有「刃」的感覺
    const w = 0.040 - 0.008 * t;
    const b = part(new THREE.BoxGeometry(w, h + 0.006, 0.011), steel, 0, y, z);
    b.rotation.x = tilt;
    blade.add(b);
    const s = part(new THREE.BoxGeometry(w + 0.015, h + 0.006, 0.030), lacquer, 0, y, z);
    s.rotation.x = tilt;
    sheath.add(s);
  }
  // 切先（刀尖斜切）
  const tip = part(new THREE.ConeGeometry(0.021, 0.10, 4), steel, 0, BLADE_LEN + 0.04, -SORI * 1.02);
  tip.rotation.y = Math.PI / 4;
  blade.add(tip);
  // 鐺（鞘尾）—— 切先比鞘身長一截，沒有這段刀尖會露在鞘外
  const kojiri = part(new THREE.BoxGeometry(0.036, 0.16, 0.030), lacquer,
    0, BLADE_LEN + 0.07, -SORI * 1.05);
  kojiri.rotation.x = -(2 * SORI / BLADE_LEN) * 0.85;
  sheath.add(kojiri);
  // 鯉口（鞘口金屬圈）
  const koi = part(new THREE.CylinderGeometry(0.040, 0.040, 0.026, 10), toon(0x8a6a3a), 0, 0.012, 0);
  koi.scale.set(1, 1, 0.62);
  sheath.add(koi);

  // 鍔
  const tsuba = part(new THREE.CylinderGeometry(0.072, 0.072, 0.016, 12), toon(0x8a6a3a), 0, -0.012, 0);
  tsuba.rotation.x = Math.PI / 2;
  blade.add(tsuba);
  // 柄：纏繩用深淺兩段交錯
  blade.add(part(new THREE.BoxGeometry(0.040, 0.30, 0.030), toon(0x2a2028), 0, -0.17, 0));
  for (const gy of [-0.10, -0.17, -0.24]) {
    blade.add(part(new THREE.BoxGeometry(0.045, 0.042, 0.034), toon(0x7a2028), 0, gy, 0));
  }
  blade.add(part(new THREE.BoxGeometry(0.042, 0.022, 0.032), toon(0x8a6a3a), 0, -0.315, 0));  // 柄頭

  for (const g of [blade, sheath]) g.traverse(o => { if (o.isMesh) o.castShadow = true; });
  return { blade, sheath };
}

// ---------------------------------------------------------------------------
// 主建構函式
// ---------------------------------------------------------------------------
export function buildCharacter(spec) {
  const pal = spec.palette;
  const root = new THREE.Group();
  root.name = spec.id;

  const skin = toon(pal.skin || 0xf6dbc6);
  const cloth = toon(pal.outfit);
  const cloth2 = toon(pal.outfit2 || pal.accent);
  const hairMat = toon(pal.hair);

  // --- 軀幹 ---
  const body = new THREE.Group();
  body.name = 'body';
  root.add(body);

  // 軀幹分兩段收腰，比單一錐狀圓柱多一點人形的起伏（不是描邊升級，
  // 是實際幾何升級：肩膀讀得出比腰寬，剪影不再是一根直筒）。
  const waistH = TORSO_H * 0.36, chestH = TORSO_H * 0.64;
  body.add(part(tapered(0.150, 0.185, waistH, 24), cloth, 0, LEG_H + waistH / 2, 0));
  body.add(part(tapered(0.172, 0.150, chestH, 24), cloth, 0, LEG_H + waistH + chestH / 2, 0));

  // 領子
  body.add(part(new THREE.CylinderGeometry(0.10, 0.13, 0.07, 14), cloth2,
    0, LEG_H + TORSO_H - 0.01, 0));

  // 領口滾邊：貼頸的一圈細環，和風服的「襟」感
  const collarTrim = new THREE.Mesh(
    new THREE.TorusGeometry(0.118, 0.013, 10, 18), toon(pal.trim || 0xf4f0e8));
  collarTrim.position.set(0, LEG_H + TORSO_H + 0.025, 0);
  collarTrim.rotation.x = Math.PI / 2;
  collarTrim.castShadow = true;
  body.add(collarTrim);

  const hakama = spec.bottom === 'hakama';

  // --- 裙 / 袴 ---
  if (hakama) {
    // 袴：腰帶 + 寬管褲，沒有喇叭裙
    body.add(part(new THREE.BoxGeometry(0.4, 0.13, 0.3), toon(pal.obi || 0x2a2028),
      0, LEG_H + 0.05, 0));
  } else {
    const skirtGeo = new THREE.CylinderGeometry(0.19, 0.42, 0.44, 24, 1, true);
    const skirt = part(skirtGeo, toonDS(pal.outfit2 || pal.accent), 0, LEG_H - 0.14, 0);
    skirt.name = 'skirt';
    skirt.userData.noMerge = true;   // 保住雙面
    body.add(skirt);

    // 裙擺滾邊：一圈對比色細環，裙子和腿之間不再糊成一塊色
    const hem = new THREE.Mesh(
      new THREE.TorusGeometry(0.415, 0.016, 10, 22), toon(pal.trim || 0xf4f0e8));
    hem.position.set(0, LEG_H - 0.14 - 0.20, 0);
    hem.rotation.x = Math.PI / 2;
    hem.castShadow = true;
    body.add(hem);
  }

  // --- 腿：大腿 + 膝關節 + 小腿，腳分出腳跟與腳尖 ---
  const legMat = toon(pal.legs || 0xf0f0f4);
  const shoeMat = toon(pal.shoes || 0x3a2a2a);
  for (const sx of [-1, 1]) {
    const leg = new THREE.Group();
    leg.name = sx < 0 ? 'legL' : 'legR';
    leg.position.set(sx * (hakama ? 0.105 : 0.085), LEG_H, 0);

    if (hakama) {
      // 袴管：上寬下收，褶線靠外側稜角表現
      const g = tapered(0.155, 0.105, LEG_H * 0.82, 14);
      const l = part(g, cloth2, 0, -LEG_H * 0.41, 0);
      leg.add(l);
      leg.add(part(tapered(0.062, 0.07, LEG_H * 0.22, 20), legMat, 0, -LEG_H * 0.9, 0));
    } else {
      const thighLen = LEG_H * 0.55, shinLen = LEG_H * 0.45;
      // 剖面抽成具名常數，關節球直接讀它的端點推導 —— 寫死數字的話
      // 剖面一改關節就腫（這正是第 2 章修掉的那個 bug 的成因）。
      const THIGH = [0.070, 0.082, 0.079, 0.068];   // 髖略粗 → 股四頭肌 → 膝上收
      const SHIN = [0.058, 0.068, 0.056, 0.044];    // 腓腸肌在上三分之一最鼓
      leg.add(part(limb(THIGH, thighLen, 20, 0.94), legMat, 0, -thighLen / 2, 0));
      // 膝：該處半徑 × 1.05。掛在 leg（大腿節點）跟著大腿轉；掛小腿會露餡
      leg.add(part(new THREE.SphereGeometry(THIGH[THIGH.length - 1] * 1.05, 14, 10),
        legMat, 0, -thighLen, 0));
      // flat 0.88 讓小腿前後扁
      leg.add(part(limb(SHIN, shinLen, 20, 0.88), legMat, 0, -thighLen - shinLen / 2, 0));
      // 踝：×1.0，大了會看起來腫
      leg.add(part(new THREE.SphereGeometry(SHIN[SHIN.length - 1], 12, 8),
        legMat, 0, -thighLen - shinLen, 0));
    }

    // 腳跟＋腳尖，取代單一方塊 —— 剪影才看得出「站著」而不是「插了根柱子」
    const footY = -LEG_H + 0.03;
    leg.add(part(new THREE.BoxGeometry(0.075, 0.055, 0.075), shoeMat, 0, footY, -0.03));
    leg.add(part(new THREE.BoxGeometry(0.095, 0.045, 0.14), shoeMat, 0, footY - 0.006, 0.07));
    body.add(leg);
  }

  // --- 手臂：上臂 + 手肘關節 + 前臂（略帶自然彎曲）+ 帶手指的手掌 ---
  const arms = {};
  for (const sx of [-1, 1]) {
    // 肩頭：軀幹到手臂的過渡不再是一節一節硬接
    body.add(part(new THREE.SphereGeometry(0.072, 14, 10), cloth, sx * 0.175, SHOULDER_Y, 0));

    const arm = new THREE.Group();
    arm.name = sx < 0 ? 'armL' : 'armR';
    arm.position.set(sx * 0.185, SHOULDER_Y, 0);

    const upperLen = 0.25, foreLen = 0.20;
    const UPPER = [0.056, 0.060, 0.055, 0.050];   // 三角肌 → 二頭肌 → 肘上收
    const FORE = [0.050, 0.052, 0.044, 0.036];    // 肘下最粗，往腕收得很細
    arm.add(part(limb(UPPER, upperLen, 20, 0.95), cloth, 0, -upperLen / 2, 0));
    // 肘：×1.05。掛在 arm（上臂節點）而不是 fore —— 掛錯邊彎曲時會露餡
    arm.add(part(new THREE.SphereGeometry(UPPER[UPPER.length - 1] * 1.05, 14, 10),
      cloth, 0, -upperLen, 0.008));

    const fore = new THREE.Group();
    fore.name = sx < 0 ? 'foreL' : 'foreR';
    fore.position.set(0, -upperLen, 0.008);
    fore.rotation.x = 0.14;   // 前臂微彎，站姿比一根直棍自然
    // flat 0.86 —— 前臂是全身最扁的一段
    fore.add(part(limb(FORE, foreLen, 20, 0.86), cloth, 0, -foreLen / 2, 0));

    // 袖口滾邊（女巫袖、巫女袖都有白色袖口的印象）
    const cuff = new THREE.Mesh(
      new THREE.TorusGeometry(0.047, 0.011, 10, 14), toon(pal.trim || 0xf4f0e8));
    cuff.position.set(0, -foreLen + 0.012, 0);
    cuff.rotation.x = Math.PI / 2;
    cuff.castShadow = true;
    fore.add(cuff);

    // 腕：×1.0。掛在 fore（前臂節點），手掌轉動時接縫才不會開
    fore.add(part(new THREE.SphereGeometry(FORE[FORE.length - 1], 12, 8), skin, 0, -foreLen, 0));

    const hand = new THREE.Group();
    hand.name = sx < 0 ? 'handL' : 'handR';
    hand.position.set(0, -foreLen, 0);
    const palm = part(new THREE.SphereGeometry(0.044, 14, 10), skin, 0, 0, 0);
    palm.scale.set(1, 0.82, 0.68);
    hand.add(palm);
    for (let f = 0; f < 4; f++) {
      const fx = (f - 1.5) * 0.019;
      hand.add(part(tapered(0.008, 0.010, 0.052, 5), skin, fx, -0.036, 0.014));
    }
    const thumb = part(tapered(0.009, 0.011, 0.045, 5), skin, sx * 0.028, -0.012, 0.028);
    thumb.rotation.z = sx * 0.85;
    hand.add(thumb);
    fore.add(hand);
    arm.add(fore);

    arm.rotation.z = sx * 0.13;
    body.add(arm);
    arms[sx < 0 ? 'L' : 'R'] = arm;
  }

  // --- 頭 ---
  const head = new THREE.Group();
  head.name = 'head';
  head.position.y = HEAD_Y;
  body.add(head);

  /* 頭型（角色書 4.1–4.2）。正圓球是「娃娃感」的主因，三件事一起做：
   *   1. 略拉長成橢球（y 1.05、z 1.02）
   *   2. 下顎收窄 —— 頭骨下半的橫截面往內縮，才有下巴
   *   3. 臉正面稍微壓平 —— 五官要有安放的平面，全球面會讓眼睛浮在弧上
   * 後兩件用逐頂點變形做，比多加幾何便宜。 */
  const skullGeo = new THREE.SphereGeometry(HEAD_R, 24, 18);
  {
    const p = skullGeo.attributes.position;
    const v = new THREE.Vector3();
    for (let i = 0; i < p.count; i++) {
      v.fromBufferAttribute(p, i);
      const ny = v.y / HEAD_R;                       // -1（下）~ 1（上）
      // 下顎收窄：只作用在下半，越往下縮越多，但留一點不然會變尖錐
      if (ny < 0) {
        const k = 1 - Math.min(1, -ny) * 0.22;
        v.x *= k; v.z *= k;
      }
      // 臉正面壓平：只壓 +z 側，且越靠中線壓越多（側臉維持圓）
      if (v.z > 0) {
        const nz = v.z / HEAD_R;
        const centre = 1 - Math.min(1, Math.abs(v.x) / (HEAD_R * 0.72));
        v.z -= nz * centre * HEAD_R * 0.10;
      }
      p.setXYZ(i, v.x, v.y, v.z);
    }
    skullGeo.computeVertexNormals();
  }
  const skull = part(skullGeo, skin, 0, 0, 0);
  skull.scale.set(1, 1.05, 1.02);
  head.add(skull);

  /* 耳朵（角色書 4.5）：兩片微彎的面，側面剪影立刻正常。
   * 用球面的一小塊而不是平面片 —— 平的從正面看會是一條線。 */
  for (const sx of [-1, 1]) {
    const ear = part(
      new THREE.SphereGeometry(HEAD_R * 0.19, 8, 6, 0, Math.PI, Math.PI * 0.15, Math.PI * 0.7),
      skin, sx * HEAD_R * 0.84, -0.012, -0.006);
    ear.rotation.y = sx > 0 ? -Math.PI / 2 : Math.PI / 2;
    ear.rotation.z = sx * 0.14;
    ear.scale.set(0.5, 1.15, 0.8);     // 貼著頭、上下略長，才像耳廓不像翅膀
    // 不描邊：外擴的黑色外殼會把這麼小的一片撐成頭上兩隻角
    ear.userData.noOutline = true;
    head.add(ear);
  }

  // 頸
  body.add(part(new THREE.CylinderGeometry(0.045, 0.05, 0.09, 16), skin, 0, LEG_H + TORSO_H + 0.04, 0));
  // 頸根填縫：×1.1，位置壓在領口裡，所以看不到球本身，只補掉頭轉動時的縫
  body.add(part(new THREE.SphereGeometry(0.05 * 1.1, 12, 8), skin, 0, LEG_H + TORSO_H, 0));

  // 眼睛：貼圖式（角色書 4.3）。虹膜、瞳孔、眼線、兩個高光全在貼圖裡，
  // 幾何只剩一片微凸面片 —— 比原本的「眼白球＋高光球」更像人也更便宜。
  // 兩隻眼共用同一份材質，先把幾何併成一個再掛上去 —— 分成兩個 mesh 的話
  // 每個角色多兩個 draw call，34 位 NPC 同框就是多 68 個。
  const eyeGeos = [];
  for (const sx of [-1, 1]) {
    const g = eyePatch(0.072, 0.056, 0.012);
    const m = new THREE.Matrix4()
      .makeRotationFromEuler(new THREE.Euler(0, sx * -0.30, sx * 0.06))
      .setPosition(sx * 0.086, 0.026, HEAD_R * 0.905);
    g.applyMatrix4(m);
    eyeGeos.push(g);
  }
  const eyes = new THREE.Mesh(BGU.mergeGeometries(eyeGeos, false),
    eyeMaterial(pal.eyes || 0x3a2a3a));
  eyes.userData.noOutline = true;
  eyes.userData.noMerge = true;         // 有自己的貼圖材質，不能併進膚色那份
  eyes.castShadow = false;
  head.add(eyes);

  // 眉毛：比髮色深一階的細短線，眉尾略下垂 —— 沒有眉毛的臉會很「素」
  const browCol = new THREE.Color(pal.hair ?? 0x444444).multiplyScalar(0.45);
  const browMat = toon(browCol.getHex());
  for (const sx of [-1, 1]) {
    const b = part(new THREE.BoxGeometry(0.062, 0.010, 0.008), browMat,
      sx * 0.086, 0.098, HEAD_R * 0.90);
    b.rotation.z = sx * -0.10;
    b.userData.noOutline = true;
    head.add(b);
  }

  // 微笑嘴：半圓環弧線。遠看只是一道小弧，近看（對話）才讀得出表情
  const mouth = new THREE.Mesh(
    new THREE.TorusGeometry(0.030, 0.0062, 6, 14, Math.PI), toon(0x8f4a44));
  mouth.position.set(0, -0.062, HEAD_R * 0.95);
  mouth.rotation.z = Math.PI;              // 弧口朝上 = 微笑
  mouth.scale.set(1, 0.9, 0.6);
  mouth.userData.noOutline = true;
  head.add(mouth);

  // 腮紅：淡淡兩點，Q 版比例下的氣色
  const blushMat = toon(0xefa9a0);
  for (const sx of [-1, 1]) {
    const bl = part(new THREE.SphereGeometry(0.021, 8, 6), blushMat,
      sx * 0.148, -0.028, HEAD_R * 0.82);
    bl.scale.set(1, 0.62, 0.30);
    bl.userData.noOutline = true;
    head.add(bl);
  }

  // --- 頭髮 / 頭飾 ---
  const hairBack = buildHair(spec.hair, hairMat, body, head, pal);
  buildHat(spec.hat, pal, head, body);

  // 細框眼鏡（霖之助）
  if (spec.glasses) {
    const gm = toon(0x3a3a42);
    for (const sx of [-1, 1]) {
      const lens = new THREE.Mesh(new THREE.TorusGeometry(0.058, 0.009, 10, 14), gm);
      lens.position.set(sx * 0.088, 0.015, HEAD_R * 0.95);
      lens.castShadow = true;
      head.add(lens);
      // 鏡腳
      const temple = part(new THREE.BoxGeometry(0.008, 0.008, 0.16), gm, sx * 0.145, 0.02, HEAD_R * 0.55);
      head.add(temple);
    }
    head.add(part(new THREE.BoxGeometry(0.07, 0.009, 0.009), gm, 0, 0.02, HEAD_R * 0.97));
  }

  // 額上的斑紋
  if (spec.mark) {
    const m = part(new THREE.BoxGeometry(0.055, 0.075, 0.01), toon(spec.mark),
      -0.055, 0.115, HEAD_R * 0.9);
    m.rotation.z = 0.5;
    head.add(m);
    const m2 = part(new THREE.BoxGeometry(0.04, 0.055, 0.01), toon(spec.mark),
      -0.012, 0.145, HEAD_R * 0.88);
    m2.rotation.z = -0.3;
    head.add(m2);
  }

  // --- 翅膀 ---
  const wings = buildWings(spec.wings || 'none', pal, body);

  // 背後的注連繩圈（神奈子）—— 稻草繩環 + 紙垂
  if (spec.backRope) {
    const rope = new THREE.Group();
    rope.name = 'backRope';
    const ringM = new THREE.Mesh(new THREE.TorusGeometry(0.44, 0.05, 8, 22), toon(0xc8b070));
    ringM.castShadow = true;
    rope.add(ringM);
    for (let i = 0; i < 4; i++) {
      const a = Math.PI * 0.22 + (i / 4) * Math.PI * 2;
      const shide = part(new THREE.BoxGeometry(0.07, 0.16, 0.012), toon(0xf4f0e8),
        Math.cos(a) * 0.44, Math.sin(a) * 0.44, 0);
      shide.rotation.z = a + Math.PI / 2;
      rope.add(shide);
    }
    rope.position.set(0, LEG_H + TORSO_H * 0.72, -0.24);
    body.add(rope);
  }

  // --- 佩刀（刀身可拔出，走另一條路） ---
  let katana = null;
  if (spec.prop === 'katana') {
    katana = buildKatana();
    // 佩在左胯：鯉口在左前、鞘尾朝後上約 25 度，柄落在身前伸手可及處，
    // 右手才拉得出來。（角度是從「鞘尾方向 ≈ (-0.18, 0.42, -0.89)」反推的，
    // +X 是角色右手邊、+Z 是面朝方向）
    katana.sheath.position.set(-0.16, LEG_H + 0.12, 0.04);
    katana.sheath.rotation.set(-1.13, 0, 0.18);
    katana.blade.position.copy(katana.sheath.position);
    katana.blade.rotation.copy(katana.sheath.rotation);
    body.add(katana.sheath);
    body.add(katana.blade);
    // 收鞘姿勢存起來：combat 拔刀時要在這個姿勢與手上姿勢之間內插
    katana.blade.userData.sheathed = {
      pos: katana.blade.position.clone(),
      quat: katana.blade.quaternion.clone(),
    };
    // 鞘的原位，「鞘引き」（拔刀時左手把鞘往後推）推完要回得來
    katana.sheath.userData.base = {
      pos: katana.sheath.position.clone(),
      quat: katana.sheath.quaternion.clone(),
    };
  }

  // --- 手持物 ---
  const prop = katana ? null : buildProp(spec.prop, pal);
  if (prop) {
    if (spec.propWaist) {
      // 佩在腰間而非握在手上 —— 給不隨便拔刀的人
      prop.position.set(0.16, LEG_H + 0.1, -0.04);
      prop.rotation.set(0.12, 0.34, 1.32);
    } else {
      prop.position.set(0.185 + 0.02, SHOULDER_Y - 0.52, 0.06);
      prop.rotation.x = spec.prop === 'broom' ? -0.25 : -0.15;
      prop.rotation.z = spec.prop === 'broom' ? 0.15 : -0.1;
      if (spec.prop === 'gohei' || spec.prop === 'sword' || spec.prop === 'spear' || spec.prop === 'parasol') {
        prop.position.y = SHOULDER_Y - 0.36;
      }
    }
    body.add(prop);
    root.userData.prop = prop;
  }

  // --- 妖夢的半靈 ---
  let ghost = null;
  if (spec.ghost) {
    ghost = new THREE.Group();
    ghost.name = 'ghost';
    const gm = new THREE.MeshStandardMaterial({
      color: 0xdff0f4, emissive: 0xbfe4ee, emissiveIntensity: 0.75,
      transparent: true, opacity: 0.72, roughness: 0.4,
    });
    const b = new THREE.Mesh(new THREE.SphereGeometry(0.3, 20, 16), gm);
    b.scale.set(1, 0.92, 1);
    b.userData.noOutline = true;
    ghost.add(b);
    for (let i = 0; i < 5; i++) {
      const t = new THREE.Mesh(new THREE.ConeGeometry(0.07, 0.2, 6), gm);
      t.position.set(Math.cos(i * 1.26) * 0.16, -0.3, Math.sin(i * 1.26) * 0.16);
      t.rotation.x = Math.PI;
      t.userData.noOutline = true;
      ghost.add(t);
    }
    ghost.position.set(0.55, 1.2, -0.1);
    root.add(ghost);
  }

  // --- 合併 + 描邊 ---
  optimizeRig(root, spec.outline ?? 0.014);

  if (spec.scale) root.scale.setScalar(spec.scale);

  // --- 動畫用把手 ---
  root.userData.rig = {
    body, head, hairBack, wings, ghost,
    armL: arms.L, armR: arms.R,
    legL: body.getObjectByName('legL'),
    legR: body.getObjectByName('legR'),
    // 佩刀專用把手（沒帶刀的角色是 null，combat 會直接跳過）
    blade: katana?.blade || null,
    sheath: katana?.sheath || null,
    foreR: arms.R.getObjectByName('foreR'),
    handR: arms.R.getObjectByName('handR'),
    float: !!spec.float,
    phase: Math.random() * Math.PI * 2,
  };
  root.userData.spec = spec;

  return root;
}

// ---------------------------------------------------------------------------
// 遠景 LOD
//
// optimizeRig 之後一位角色仍是十來個網格（每個動畫節點各一個 + 描邊）。
// 一條街上五十位路人 = 五百多個 draw call，而三十公尺外的人只有十幾個
// 像素高。setCharacterFar() 把整隻換成一個烘死姿勢的合併網格：
// draw call 十個變一個，呼叫端也可以順便跳過該幀的動畫計算。
//
// 遠景網格是第一次真的走遠時才建（lazy）—— 玩家永遠不會遠離自己，
// 走不到的角落裡的 NPC 也不必先付這份記憶體。
// ---------------------------------------------------------------------------

/**
 * 切換一位角色的細節層級。
 * @param {THREE.Object3D} root 角色根節點（buildCharacter 的回傳值）
 * @param {boolean} far true = 遠景單網格，false = 完整骨架
 * @returns {boolean} 目前是否處於遠景狀態（建不出遠景網格時回 false）
 */
export function setCharacterFar(root, far) {
  const u = root.userData;
  if (!!u.farOn === !!far) return !!u.farOn;

  if (far) {
    if (u.farLod === undefined) {
      // 建之前先把姿勢歸零，否則會把「當下剛好抬起的手腳」烘死在裡面
      animateCharacter(root, 0, 0);
      root.updateMatrixWorld(true);
      u.farLod = mergeRigSnapshot(root, TOON_VC);
      if (u.farLod) root.add(u.farLod);
    }
    if (!u.farLod) return false;          // 烘不出來（例如整隻都是半透明）就維持完整骨架
  }

  for (const c of root.children) {
    if (c === u.farLod) c.visible = !!far;
    else c.visible = !far;
  }
  u.farOn = !!far;
  return u.farOn;
}

/** 每幀更新一個角色的待機／行走動作 */
export function animateCharacter(root, t, moveSpeed = 0) {
  const r = root.userData.rig;
  if (!r) return;
  const p = r.phase;

  // 呼吸 / 浮空
  const bob = r.float
    ? Math.sin(t * 1.15 + p) * 0.14 + 0.42
    : Math.sin(t * 2.1 + p) * 0.012;
  r.body.position.y = bob;
  r.bobY = bob;              // 招式動作的升降要疊在這上面（見 motion.applyPose）

  // 走路擺動
  const w = Math.min(1, moveSpeed / 5.5);
  const stride = Math.sin(t * 9 * Math.max(0.35, w)) * w;

  if (r.legL && r.legR && !r.float) {
    r.legL.rotation.x = stride * 0.72;
    r.legR.rotation.x = -stride * 0.72;
  } else if (r.legL && r.legR) {
    r.legL.rotation.x = 0.18 + Math.sin(t * 1.4 + p) * 0.06;
    r.legR.rotation.x = 0.1 - Math.sin(t * 1.4 + p) * 0.06;
  }

  if (r.armL && r.armR) {
    const idleL = Math.sin(t * 1.6 + p) * 0.05;
    r.armL.rotation.x = -stride * 0.55 + idleL;
    r.armR.rotation.x = stride * 0.55 + idleL;
    r.armL.rotation.z = 0.13 + Math.sin(t * 1.3 + p) * 0.035;
    r.armR.rotation.z = -0.13 - Math.sin(t * 1.3 + p + 1) * 0.035;
  }

  // 頭部微動
  if (r.head) {
    r.head.rotation.y = Math.sin(t * 0.62 + p) * 0.24;
    r.head.rotation.z = Math.sin(t * 0.48 + p * 1.4) * 0.045;
  }

  // 頭髮慣性
  if (r.hairBack) {
    r.hairBack.rotation.x = Math.sin(t * 1.5 + p) * 0.06 - stride * 0.12;
    r.hairBack.rotation.z = Math.sin(t * 1.1 + p) * 0.05;
  }

  // 翅膀拍動
  if (r.wings) {
    const flap = Math.sin(t * 3.4 + p) * 0.28;
    const L = r.wings.getObjectByName('wingL');
    const R = r.wings.getObjectByName('wingR');
    if (L) L.rotation.y = flap;
    if (R) R.rotation.y = -flap;
  }

  // 半靈繞著主人轉
  if (r.ghost) {
    const a = t * 0.55 + p;
    r.ghost.position.set(Math.cos(a) * 0.62, 1.15 + Math.sin(t * 1.4 + p) * 0.13, Math.sin(a) * 0.62 - 0.1);
    r.ghost.rotation.y = -a;
  }
}

export { toon, gradientMap };
