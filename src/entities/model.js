import * as THREE from 'three';
import * as BGU from 'three/addons/utils/BufferGeometryUtils.js';
import { mergeAnimNode, shellGeometry } from '../core/optimize.js';

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

function tapered(rTop, rBot, h, seg = 10) {
  const g = new THREE.CylinderGeometry(rTop, rBot, h, seg, 1);
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
function optimizeRig(root, thickness = 0.02) {
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
    const th = (node.name === 'blade' || node.name === 'sheath') ? thickness * 0.45 : thickness;
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
    new THREE.SphereGeometry(HEAD_R * 1.07, 18, 12, 0, Math.PI * 2, 0, Math.PI * 0.40), mat);
  cap.position.y = HEAD_R * 0.02;
  cap.castShadow = true;
  head.add(cap);

  // 後腦與兩側可以蓋得低。theta 的 0 在 -X、π/2 在 +Z，
  // 所以讓開 40°～140° 這段就等於讓開正面。
  const rear = new THREE.Mesh(
    new THREE.SphereGeometry(HEAD_R * 1.06, 18, 12,
      Math.PI * 0.78, Math.PI * 1.44, 0, Math.PI * 0.74), mat);
  rear.castShadow = true;
  head.add(rear);

  // 瀏海：只遮額頭。球面片 theta 0→π 本來就朝著 +Z，不需要再旋轉。
  const bang = new THREE.Mesh(
    new THREE.SphereGeometry(HEAD_R * 1.05, 16, 10,
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

  const strand = (len, r, x, y, z, rx = 0, rz = 0) => {
    const g = tapered(r * 0.55, r, len, 8);
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
        const tip = tapered(0.07, 0.15, 0.42, 8);
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
        const s = new THREE.Mesh(new THREE.SphereGeometry(0.088 - i * 0.007, 10, 8), mat);
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
      const tip = tapered(0.055, 0.115, 0.34, 8);
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
      const knot = part(new THREE.SphereGeometry(0.075, 10, 8), rib, 0, HEAD_R * 0.85, -0.13);
      head.add(knot);
      for (const sx of [-1, 1]) {
        const w = new THREE.Mesh(new THREE.SphereGeometry(0.135, 12, 8), rib);
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
      const t = part(new THREE.SphereGeometry(0.075, 10, 8), toon(0xffffff), 0, HEAD_R * 0.95 + 0.14, 0);
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
        const g = tapered(0.05, 0.085, 0.46, 8);
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
      const rb = part(new THREE.SphereGeometry(0.1, 10, 8), toon(0xd4405a), 0.19, HEAD_R * 0.92 + 0.11, 0.16);
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
      const dome = new THREE.Mesh(new THREE.SphereGeometry(0.24, 16, 10, 0, Math.PI * 2, 0, Math.PI * 0.5), khaki);
      dome.position.set(0, HEAD_R * 0.9, 0);
      dome.castShadow = true;
      head.add(dome);
      for (const sx of [-1, 1]) {
        const eye = part(new THREE.SphereGeometry(0.055, 10, 8), toon(0xf4f0e0), sx * 0.13, HEAD_R * 0.9 + 0.21, 0.12);
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
      head.add(part(new THREE.SphereGeometry(0.042, 10, 8), frog, 0.155, HEAD_R * 0.55, 0.14));
      for (const sx of [-1, 1]) {
        head.add(part(new THREE.SphereGeometry(0.016, 8, 6), toon(0xf4f4f8), 0.155 + sx * 0.024, HEAD_R * 0.55 + 0.034, 0.168));
      }
      const snake = toon(0xe8e4da);
      head.add(part(new THREE.TorusGeometry(0.05, 0.014, 6, 12), snake, -0.16, HEAD_R * 0.6, 0.12));
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
        const g = tapered(0.022, 0.062, 0.52, 8);
        const h = part(g, horn, sx * 0.14, HEAD_R * 1.05, 0.1);
        h.rotation.z = sx * 0.5;
        h.rotation.x = -0.55;
        head.add(h);
        // 角上的緞帶結（左紅右紫）
        const rb = part(new THREE.TorusGeometry(0.045, 0.018, 6, 12),
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
        const p = new THREE.Mesh(new THREE.SphereGeometry(0.3, 12, 8), mat);
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
      const knot = part(new THREE.TorusGeometry(0.05, 0.016, 6, 12), toon(0xc23a3a), 0, 0.07, 0);
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
  body.add(part(tapered(0.150, 0.185, waistH, 14), cloth, 0, LEG_H + waistH / 2, 0));
  body.add(part(tapered(0.172, 0.150, chestH, 14), cloth, 0, LEG_H + waistH + chestH / 2, 0));

  // 領子
  body.add(part(new THREE.CylinderGeometry(0.10, 0.13, 0.07, 14), cloth2,
    0, LEG_H + TORSO_H - 0.01, 0));

  // 領口滾邊：貼頸的一圈細環，和風服的「襟」感
  const collarTrim = new THREE.Mesh(
    new THREE.TorusGeometry(0.118, 0.013, 6, 18), toon(pal.trim || 0xf4f0e8));
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
    const skirtGeo = new THREE.CylinderGeometry(0.19, 0.42, 0.44, 16, 1, true);
    const skirt = part(skirtGeo, toonDS(pal.outfit2 || pal.accent), 0, LEG_H - 0.14, 0);
    skirt.name = 'skirt';
    skirt.userData.noMerge = true;   // 保住雙面
    body.add(skirt);

    // 裙擺滾邊：一圈對比色細環，裙子和腿之間不再糊成一塊色
    const hem = new THREE.Mesh(
      new THREE.TorusGeometry(0.415, 0.016, 6, 22), toon(pal.trim || 0xf4f0e8));
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
      const g = tapered(0.155, 0.105, LEG_H * 0.82, 8);
      const l = part(g, cloth2, 0, -LEG_H * 0.41, 0);
      leg.add(l);
      leg.add(part(tapered(0.062, 0.07, LEG_H * 0.22, 10), legMat, 0, -LEG_H * 0.9, 0));
    } else {
      const thighLen = LEG_H * 0.55, shinLen = LEG_H * 0.45;
      leg.add(part(tapered(0.064, 0.074, thighLen, 10), legMat, 0, -thighLen / 2, 0));
      leg.add(part(new THREE.SphereGeometry(0.058, 10, 8), legMat, 0, -thighLen, 0));   // 膝關節
      leg.add(part(tapered(0.05, 0.06, shinLen, 10), legMat, 0, -thighLen - shinLen / 2, 0));
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
    body.add(part(new THREE.SphereGeometry(0.072, 10, 8), cloth, sx * 0.175, SHOULDER_Y, 0));

    const arm = new THREE.Group();
    arm.name = sx < 0 ? 'armL' : 'armR';
    arm.position.set(sx * 0.185, SHOULDER_Y, 0);

    const upperLen = 0.25, foreLen = 0.20;
    arm.add(part(tapered(0.05, 0.056, upperLen, 10), cloth, 0, -upperLen / 2, 0));
    arm.add(part(new THREE.SphereGeometry(0.046, 10, 8), skin, 0, -upperLen, 0.008));  // 手肘

    const fore = new THREE.Group();
    fore.name = sx < 0 ? 'foreL' : 'foreR';
    fore.position.set(0, -upperLen, 0.008);
    fore.rotation.x = 0.14;   // 前臂微彎，站姿比一根直棍自然
    fore.add(part(tapered(0.04, 0.048, foreLen, 10), cloth, 0, -foreLen / 2, 0));

    // 袖口滾邊（女巫袖、巫女袖都有白色袖口的印象）
    const cuff = new THREE.Mesh(
      new THREE.TorusGeometry(0.047, 0.011, 6, 14), toon(pal.trim || 0xf4f0e8));
    cuff.position.set(0, -foreLen + 0.012, 0);
    cuff.rotation.x = Math.PI / 2;
    cuff.castShadow = true;
    fore.add(cuff);

    const hand = new THREE.Group();
    hand.name = sx < 0 ? 'handL' : 'handR';
    hand.position.set(0, -foreLen, 0);
    const palm = part(new THREE.SphereGeometry(0.044, 10, 8), skin, 0, 0, 0);
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

  const skull = part(new THREE.SphereGeometry(HEAD_R, 18, 14), skin, 0, 0, 0);
  skull.scale.set(1, 1.04, 0.96);
  head.add(skull);

  // 頸
  body.add(part(new THREE.CylinderGeometry(0.045, 0.05, 0.09, 8), skin, 0, LEG_H + TORSO_H + 0.04, 0));

  // 眼睛（純色橢圓，卡通風不需要複雜結構）
  const eyeMat = toon(pal.eyes || 0x3a2a3a);
  for (const sx of [-1, 1]) {
    const e = part(new THREE.SphereGeometry(0.038, 10, 8), eyeMat,
      sx * 0.088, 0.012, HEAD_R * 0.88);
    e.scale.set(0.85, 1.25, 0.42);
    e.userData.noOutline = true;
    head.add(e);
    const hl = part(new THREE.SphereGeometry(0.014, 8, 6), toon(0xffffff),
      sx * 0.078, 0.045, HEAD_R * 0.93);
    hl.scale.set(1, 1, 0.4);
    hl.userData.noOutline = true;
    head.add(hl);
  }

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
      const lens = new THREE.Mesh(new THREE.TorusGeometry(0.058, 0.009, 6, 14), gm);
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
    const b = new THREE.Mesh(new THREE.SphereGeometry(0.3, 16, 12), gm);
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
  optimizeRig(root, spec.outline ?? 0.02);

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
