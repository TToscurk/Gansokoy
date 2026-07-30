// 人間之里 —— 幻想鄉唯一由人類自治的聚落。
//
// 設定考據（Touhou Wiki）：明治風格的村落，是幻想鄉最安全的地方，
// 由上白澤慧音以「吃掉歷史」的能力守護；里內有寺子屋（慧音教書的私塾）、
// 豆腐店、花店、霧雨屋（魔理沙老家的二手道具店）、鈴奈庵（本居小鈴的
// 租書店）、居酒屋，以及稗田家的宅邸（稗田阿求）。天狗會來送報，
// 河童會來擺攤，妖怪也會來買東西 —— 所以里門是開的，只是有結界。
//
// 場景結構：南北向的主街（石板路）貫穿全里，兩側店家沿街並排，
// 中央有水井廣場，北端里門通往獸道。所有實體（建物、樹、水井、
// 攤位、燈籠）都有貼合模型的碰撞盒，走過去會被實實在在擋住。
//
// 系統全部走共用模組：HUD、晝夜天氣（Environment）、傳送光點、
// 戰鬥（有 combat 旗標的角色到哪張圖都能出招）、角色/技能等級。

import * as THREE from 'three';
import { setGroundHeightFn } from './src/world/terrain.js';
import { WORLD } from './src/config.js';
import { buildCharacter } from './src/entities/model.js';
import { PLAYABLE } from './src/entities/roster.js';
import { PlayerController } from './src/player/controller.js';
import { Environment } from './src/world/environment.js';
import { makePortalGlow } from './src/world/portal.js';
import { Combat } from './src/combat/combat.js';
import { SlashFX, SlashAudio } from './src/fx/slash.js';
import { combatHUD, bindCombatInput } from './src/combat/hud.js';
import { Progression } from './src/player/progression.js';
import { installHUD, bindEscMenu } from './src/ui/hud.js';

const HUD = installHUD({
  title: '人間之里',
  subtitle: 'HUMAN VILLAGE',
  keys: [
    ['WASD / 方向鍵', '移動'], ['滑鼠', '轉視角'], ['滾輪', '縮放'],
    ['Shift', '衝刺'], ['Space', '跳躍'], ['F', '飛行'], ['Ctrl/C', '下降'],
    ['E', '互動'], ['ESC', '選單'],
  ],
  combatKeys: [['左鍵', '出招'], ['長按左鍵', '日之呼吸・全型'], ['R', '拔刀/納刀']],
});

/* ─────────────────────────────────────────────── renderer / scene ── */
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(innerWidth, innerHeight);
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(70, innerWidth / innerHeight, 0.08, 600);
camera.rotation.order = 'YXZ';

// 里是開闊的盆地：霧比獸道淡，看得到街尾與遠山
const env = new Environment(scene, renderer, { fogMul: 0.75, shadowArea: 70 });

/* ─────────────────────────────────────────────────── 地形高度場 ── */
// 里蓋在平坦的盆地上：主街完全水平，外圍緩緩抬起成田埂與矮丘。
const VILLAGE_R = 62;      // 里的半徑（超過這裡開始爬坡）
const GATE_Z = -58;        // 北端里門（通獸道）

function heightAt(x, z) {
  const d = Math.hypot(x * 0.85, z * 0.6);        // 橢圓形的里
  if (d < VILLAGE_R) return Math.sin(x * 0.12) * 0.05 + Math.sin(z * 0.1) * 0.05;
  const out = d - VILLAGE_R;
  return out * out * 0.012;                        // 外圍矮丘
}
setGroundHeightFn(heightAt);
WORLD.waterLevel = -999;   // 這張圖沒有水域（見 main.js 同名註解）

/* ───────────────────────────────────────────────────────── 材質 ── */
function canvasTex(size, draw, rx = 1, ry = 1) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  draw(c.getContext('2d'), size);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(rx, ry);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
const noise = (g, s, n, a) => {
  for (let i = 0; i < n; i++) {
    g.fillStyle = `rgba(0,0,0,${Math.random() * a})`;
    g.fillRect(Math.random() * s, Math.random() * s, 2, 2);
  }
};
const groundTex = canvasTex(256, (g, s) => {
  g.fillStyle = '#5e6b3c'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 2000; i++) {
    g.fillStyle = `rgba(${70 + Math.random() * 50},${86 + Math.random() * 45},${44 + Math.random() * 30},.5)`;
    g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 1 + Math.random() * 6, 0, 7); g.fill();
  }
  noise(g, s, 400, 0.15);
}, 26, 26);
const stoneRoadTex = canvasTex(256, (g, s) => {
  g.fillStyle = '#8b8375'; g.fillRect(0, 0, s, s);
  const rows = 7, h = s / rows;
  for (let r = 0; r < rows; r++) {
    const cols = 5, w = s / cols, off = (r % 2) * w * 0.5;
    for (let c = -1; c <= cols; c++) {
      const v = 132 + Math.random() * 44;
      g.fillStyle = `rgb(${v},${v - 4},${v - 16})`;
      g.fillRect(c * w + off + 2, r * h + 2, w - 4, h - 4);
    }
  }
  noise(g, s, 700, 0.2);
}, 3, 22);
const plasterTex = canvasTex(128, (g, s) => {
  g.fillStyle = '#e6dcc4'; g.fillRect(0, 0, s, s);
  noise(g, s, 600, 0.12);
}, 2, 1);
const woodTex = canvasTex(128, (g, s) => {
  g.fillStyle = '#7a5a3c'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 90; i++) {
    g.strokeStyle = `rgba(${50 + Math.random() * 40},${34 + Math.random() * 26},${18 + Math.random() * 16},.4)`;
    g.lineWidth = 0.6 + Math.random() * 1.8;
    const x = Math.random() * s;
    g.beginPath(); g.moveTo(x, 0); g.lineTo(x + (Math.random() - 0.5) * 8, s); g.stroke();
  }
}, 1, 2);

const MAT = {
  ground: new THREE.MeshStandardMaterial({ map: groundTex, roughness: 1 }),
  road: new THREE.MeshStandardMaterial({ map: stoneRoadTex, roughness: 1 }),
  plaster: new THREE.MeshStandardMaterial({ map: plasterTex, roughness: 0.95, color: '#f2ead6' }),
  wood: new THREE.MeshStandardMaterial({ map: woodTex, roughness: 0.9, color: '#c8a880' }),
  darkWood: new THREE.MeshStandardMaterial({ map: woodTex, roughness: 0.95, color: '#6a5038' }),
  roofTile: new THREE.MeshStandardMaterial({ color: '#4c5560', roughness: 0.8, flatShading: true }),
  roofThatch: new THREE.MeshStandardMaterial({ color: '#8a7448', roughness: 1, flatShading: true }),
  stone: new THREE.MeshStandardMaterial({ color: '#918a7e', roughness: 1 }),
  paper: new THREE.MeshStandardMaterial({ color: '#fff2d4', roughness: 0.9, emissive: '#a06a20', emissiveIntensity: 0.25 }),
  cloth: new THREE.MeshStandardMaterial({ color: '#c14a3a', roughness: 0.95, side: THREE.DoubleSide }),
  clothBlue: new THREE.MeshStandardMaterial({ color: '#3a5a7a', roughness: 0.95, side: THREE.DoubleSide }),
  bark: new THREE.MeshStandardMaterial({ color: '#4e3a28', roughness: 1 }),
  leaf: new THREE.MeshStandardMaterial({ color: '#4a6b33', roughness: 1, flatShading: true }),
  leafPink: new THREE.MeshStandardMaterial({ color: '#e0a8bc', roughness: 1, flatShading: true }),
};

const world = new THREE.Group();
scene.add(world);

/* 碰撞盒 —— 所有看得見的實體都要能擋人，尺寸貼合模型 */
const colliders = [];
function block(x, z, sx, sz, top, bottom = -99) {
  colliders.push({ x, z, y: bottom, h: top - bottom, hw: sx / 2, hd: sz / 2 });
}
function post(x, z, r, top, bottom = -99) {
  colliders.push({ x, z, y: bottom, h: top - bottom, r });
}

function box(sx, sy, sz, mat, x, y, z, parent = world) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(sx, sy, sz), mat);
  m.position.set(x, y, z);
  m.castShadow = m.receiveShadow = true;
  parent.add(m);
  return m;
}
function cyl(r1, r2, h, mat, x, y, z, seg = 10, parent = world) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(r1, r2, h, seg), mat);
  m.position.set(x, y, z);
  m.castShadow = m.receiveShadow = true;
  parent.add(m);
  return m;
}

/* ───────────────────────────────────────────────────────── 地面 ── */
(function ground() {
  const geo = new THREE.PlaneGeometry(300, 300, 90, 90);
  geo.rotateX(-Math.PI / 2);
  const p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) p.setY(i, heightAt(p.getX(i), p.getZ(i)));
  geo.computeVertexNormals();
  const m = new THREE.Mesh(geo, MAT.ground);
  m.receiveShadow = true;
  world.add(m);

  // 主街（南北）與橫街（東西）：石板路
  const main = new THREE.Mesh(new THREE.PlaneGeometry(9, 124), MAT.road);
  main.rotation.x = -Math.PI / 2; main.position.set(0, 0.03, 0); main.receiveShadow = true; world.add(main);
  const cross = new THREE.Mesh(new THREE.PlaneGeometry(74, 7), MAT.road);
  cross.rotation.x = -Math.PI / 2; cross.position.set(0, 0.03, 8); cross.receiveShadow = true; world.add(cross);
})();

/* ─────────────────────────────────────────────────────── 建物 ── */
/**
 * 一棟明治風的町家：土牆屋身 + 木格柵 + 屋頂（瓦或茅草）+ 暖簾與招牌。
 * @param {object} o {x,z,w,d,h,rot,roof,sign,signColor,noren}
 */
function house({ x, z, w = 9, d = 7, h = 4.2, rot = 0, roof = 'tile', sign = '', signColor = 0x6a5038, noren = null }) {
  const g = new THREE.Group();
  g.position.set(x, heightAt(x, z), z);
  g.rotation.y = rot;
  world.add(g);

  // 石基
  box(w + 0.5, 0.35, d + 0.5, MAT.stone, 0, 0.17, 0, g);
  // 屋身
  box(w, h, d, MAT.plaster, 0, h / 2 + 0.3, 0, g);
  // 一樓正面的木格柵與門
  box(w * 0.94, 2.2, 0.16, MAT.darkWood, 0, 1.4, d / 2 + 0.04, g);
  box(w * 0.3, 2.1, 0.1, MAT.paper, 0, 1.35, d / 2 + 0.13, g);      // 紙門
  for (let i = -3; i <= 3; i++) {
    box(0.1, 2.1, 0.06, MAT.darkWood, i * (w * 0.12), 1.35, d / 2 + 0.19, g);
  }
  // 角柱
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    box(0.28, h + 0.3, 0.28, MAT.darkWood, sx * (w / 2 - 0.14), (h + 0.3) / 2, sz * (d / 2 - 0.14), g);
  }

  // 屋頂
  const rm = roof === 'thatch' ? MAT.roofThatch : MAT.roofTile;
  const rh = roof === 'thatch' ? 2.8 : 1.9;
  const eave = roof === 'thatch' ? 1.5 : 1.1;
  for (const s of [-1, 1]) {
    const len = Math.hypot(d / 2 + eave, rh);
    const slope = box(w + eave * 1.4, 0.34, len, rm, 0, h + 0.3 + rh / 2, s * (d / 4 + eave / 2), g);
    slope.rotation.x = s * Math.atan2(rh, d / 2 + eave);
  }
  box(w + eave * 1.5, 0.42, 0.7, rm, 0, h + 0.3 + rh, 0, g);        // 正脊
  // 山牆
  for (const s of [-1, 1]) {
    const shape = new THREE.Shape();
    const hd = d / 2 + eave * 0.6;
    shape.moveTo(-hd, 0); shape.lineTo(hd, 0); shape.lineTo(0, rh);
    const tri = new THREE.Mesh(new THREE.ShapeGeometry(shape), MAT.plaster);
    tri.position.set(s * (w / 2 + 0.02), h + 0.3, 0);
    tri.rotation.y = s * Math.PI / 2;
    g.add(tri);
  }

  // 暖簾（店家門口的布簾）
  if (noren) {
    const nm = noren === 'blue' ? MAT.clothBlue : MAT.cloth;
    for (let i = 0; i < 4; i++) {
      const strip = box(w * 0.11, 0.9, 0.04, nm, (i - 1.5) * (w * 0.13), 2.5, d / 2 + 0.26, g);
      strip.rotation.x = 0.03;
    }
    box(w * 0.58, 0.1, 0.1, MAT.darkWood, 0, 2.96, d / 2 + 0.26, g);
  }
  // 招牌（看板）
  if (sign) {
    const board = box(2.6, 0.8, 0.14, new THREE.MeshStandardMaterial({ color: signColor, roughness: 0.8 }),
      w / 2 - 1.6, 3.5, d / 2 + 0.3, g);
    board.rotation.z = 0.02;
    g.userData.signName = sign;
  }

  // 碰撞：屋身（旋轉過的建物也要跟著轉）
  const cs = Math.abs(Math.cos(rot)), sn = Math.abs(Math.sin(rot));
  block(x, z, w * cs + d * sn, w * sn + d * cs, heightAt(x, z) + h);
  return g;
}

// --- 主街兩側的店家（考據自 Touhou Wiki 的里內設施） ---
const SHOPS = [
  { x: -11, z: -30, w: 10, d: 8, rot: Math.PI, sign: '寺子屋', roof: 'tile', signColor: 0x4a5a7a },   // 慧音的私塾
  { x: 12, z: -28, w: 9, d: 7, rot: Math.PI, sign: '豆腐', noren: 'blue' },
  { x: -12, z: -14, w: 8.5, d: 7, rot: Math.PI, sign: '花', noren: 'red' },
  { x: 12, z: -12, w: 9.5, d: 7.5, rot: Math.PI, sign: '霧雨屋', roof: 'thatch' },                     // 魔理沙老家
  { x: -12.5, z: 22, w: 9, d: 7, rot: 0, sign: '鈴奈庵', noren: 'blue' },                              // 小鈴的租書店
  { x: 12.5, z: 20, w: 10, d: 7.5, rot: 0, sign: '居酒屋', noren: 'red', roof: 'thatch' },
  { x: -13, z: 38, w: 9, d: 7, rot: 0, sign: '米', },
  { x: 13, z: 36, w: 8.5, d: 7, rot: 0, sign: '鍛冶', roof: 'thatch' },
];
for (const s of SHOPS) house(s);

// 稗田邸：里內最大的宅子，退到街廓後方，帶院牆
(function hiedaManor() {
  const MX = -30, MZ = 6;
  house({ x: MX, z: MZ, w: 16, d: 12, h: 5.2, rot: Math.PI / 2, roof: 'tile', sign: '稗田' });
  // 院牆（四段，留一個口）
  const wallY = heightAt(MX, MZ);
  const seg = (cx, cz, sx, sz) => {
    box(sx, 1.9, sz, MAT.plaster, cx, wallY + 0.95, cz);
    box(sx + 0.3, 0.22, sz + 0.3, MAT.roofTile, cx, wallY + 2.0, cz);   // 牆頭瓦
    block(cx, cz, sx, sz, wallY + 2.0);
  };
  seg(MX, MZ - 11, 22, 0.6);
  seg(MX, MZ + 11, 22, 0.6);
  seg(MX - 11, MZ, 0.6, 22);
  seg(MX + 11, MZ - 6.5, 0.6, 9);      // 東側留門口
  seg(MX + 11, MZ + 6.5, 0.6, 9);
})();

/* ──────────────────────────────────────────── 里的公共設施 ── */
// 水井廣場（主街與橫街的交叉口）
(function well() {
  const WX = 0, WZ = 8, y = heightAt(WX, WZ);
  cyl(1.5, 1.6, 1.0, MAT.stone, WX, y + 0.5, WZ, 14);
  const rim = new THREE.Mesh(new THREE.TorusGeometry(1.5, 0.16, 8, 18), MAT.stone);
  rim.position.set(WX, y + 1.0, WZ); rim.rotation.x = Math.PI / 2;
  rim.castShadow = true; world.add(rim);
  post(WX, WZ, 1.7, y + 1.05);
  // 井上的木架與吊桶
  for (const s of [-1, 1]) {
    cyl(0.11, 0.13, 2.6, MAT.darkWood, WX + s * 1.5, y + 1.3, WZ, 8);
    post(WX + s * 1.5, WZ, 0.18, y + 2.6);
  }
  box(3.6, 0.18, 0.18, MAT.darkWood, WX, y + 2.6, WZ);
  box(0.5, 0.5, 0.5, MAT.wood, WX, y + 1.9, WZ);
  // 井旁的告示板
  const bx = WX + 3.6, bz = WZ + 2.2;
  for (const s of [-1, 1]) cyl(0.09, 0.1, 2.0, MAT.darkWood, bx + s * 0.9, y + 1.0, bz, 6);
  box(2.4, 1.3, 0.12, MAT.wood, bx, y + 1.6, bz);
  block(bx, bz, 2.4, 0.4, y + 2.2);
})();

// 沿街的石燈籠與攤位
const lanternGlows = [];
function streetLantern(x, z) {
  const y = heightAt(x, z);
  cyl(0.28, 0.34, 0.5, MAT.stone, x, y + 0.25, z, 8);
  cyl(0.16, 0.2, 1.5, MAT.stone, x, y + 1.2, z, 8);
  const lamp = box(0.62, 0.6, 0.62, MAT.paper, x, y + 2.2, z);
  box(0.9, 0.16, 0.9, MAT.stone, x, y + 2.58, z);
  const l = new THREE.PointLight('#ffcf8c', 0, 9, 2);
  l.position.set(x, y + 2.2, z);
  world.add(l);
  lanternGlows.push({ lamp, light: l });
  post(x, z, 0.38, y + 2.6);
}
for (let i = -4; i <= 4; i++) {
  if (i === 0) continue;
  streetLantern(-5.6, i * 12);
  streetLantern(5.6, i * 12 + 6);
}

// 露天攤位（河童的市集）：矮桌 + 布棚
function stall(x, z, rot, cloth) {
  const g = new THREE.Group();
  g.position.set(x, heightAt(x, z), z);
  g.rotation.y = rot;
  world.add(g);
  box(3.2, 0.16, 1.8, MAT.wood, 0, 0.85, 0, g);
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    cyl(0.07, 0.08, 0.85, MAT.darkWood, sx * 1.4, 0.42, sz * 0.7, 6, g);
  }
  for (const sx of [-1, 1]) cyl(0.08, 0.09, 2.4, MAT.darkWood, sx * 1.5, 1.2, -0.7, 6, g);
  const canopy = box(3.6, 0.1, 2.4, cloth, 0, 2.4, 0.2, g);
  canopy.rotation.x = -0.16;
  // 桌上的貨
  for (let i = 0; i < 4; i++) {
    box(0.4, 0.3, 0.4, i % 2 ? MAT.wood : MAT.stone, -1.1 + i * 0.72, 1.08, 0, g);
  }
  const cs = Math.abs(Math.cos(rot)), sn = Math.abs(Math.sin(rot));
  block(x, z, 3.2 * cs + 1.8 * sn, 3.2 * sn + 1.8 * cs, heightAt(x, z) + 1.0);
}
stall(-6.5, 4, 0.1, MAT.cloth);
stall(6.5, 12, -0.1, MAT.clothBlue);
stall(-6.5, 16, 0.05, MAT.clothBlue);

// 里的樹（櫻花與雜木），連樹幹一起擋人
function tree(x, z, s, leafMat) {
  const y = heightAt(x, z);
  const h = (3.4 + Math.random() * 2.2) * s;
  cyl(0.18 * s, 0.28 * s, h, MAT.bark, x, y + h / 2, z, 7);
  for (let i = 0; i < 3; i++) {
    const r = (1.7 - i * 0.4) * s;
    const c = new THREE.Mesh(new THREE.IcosahedronGeometry(r, 0), leafMat);
    c.position.set(x + (Math.random() - 0.5) * 0.8 * s, y + h + i * 0.8 * s - 0.3, z + (Math.random() - 0.5) * 0.8 * s);
    c.castShadow = true;
    world.add(c);
  }
  post(x, z, 0.3 * s, y + h);
}
// 廣場邊兩株櫻，其餘散在屋後與里外
tree(-4.5, 14, 1.15, MAT.leafPink);
tree(4.5, 2, 1.1, MAT.leafPink);
for (let i = 0; i < 60; i++) {
  const a = Math.random() * Math.PI * 2;
  const r = 34 + Math.random() * 46;
  const x = Math.cos(a) * r, z = Math.sin(a) * r * 1.25;
  if (Math.abs(x) < 20 && Math.abs(z) < 62) continue;         // 街廓與主街留空
  tree(x, z, 0.85 + Math.random() * 0.8, MAT.leaf);
}

// 田埂（里外的水田格子，純視覺）
for (let i = 0; i < 14; i++) {
  const side = i % 2 ? 1 : -1;
  const x = side * (40 + (i % 5) * 9);
  const z = -40 + (i * 11) % 92;
  const paddy = new THREE.Mesh(new THREE.PlaneGeometry(14, 9), new THREE.MeshStandardMaterial({ color: '#6f7f42', roughness: 1 }));
  paddy.rotation.x = -Math.PI / 2;
  paddy.position.set(x, heightAt(x, z) + 0.04, z);
  paddy.receiveShadow = true;
  world.add(paddy);
}

/* ───────────────────────────────────────── 里門（北端，通獸道） ── */
(function villageGate() {
  const y = heightAt(0, GATE_Z);
  // 冠木門：兩根柱 + 橫樑 + 小屋頂
  for (const s of [-1, 1]) {
    cyl(0.42, 0.48, 6.2, MAT.darkWood, s * 4.4, y + 3.1, GATE_Z, 10);
    post(s * 4.4, GATE_Z, 0.55, y + 6.2);
  }
  box(11, 0.7, 0.8, MAT.darkWood, 0, y + 6.0, GATE_Z);
  box(9.4, 0.45, 0.6, MAT.darkWood, 0, y + 5.0, GATE_Z);
  for (const s of [-1, 1]) {
    const slope = box(12, 0.3, 2.2, MAT.roofTile, 0, y + 6.7, GATE_Z + s * 0.9);
    slope.rotation.x = s * 0.5;
  }
  // 門旁的土牆（里的外圍），中間留門口
  for (const s of [-1, 1]) {
    const wx = s * 17;
    box(20, 2.4, 0.7, MAT.plaster, wx, y + 1.2, GATE_Z);
    box(20.4, 0.25, 1.0, MAT.roofTile, wx, y + 2.45, GATE_Z);
    block(wx, GATE_Z, 20, 0.7, y + 2.45);
  }
  // 門前的注連繩結界柱
  for (const s of [-1, 1]) {
    cyl(0.16, 0.18, 1.6, MAT.stone, s * 6.4, y + 0.8, GATE_Z + 2.6, 8);
    post(s * 6.4, GATE_Z + 2.6, 0.22, y + 1.6);
  }
})();

// 遠山（讓盆地有邊界感）
for (let i = 0; i < 18; i++) {
  const a = (i / 18) * Math.PI * 2 + 0.3;
  const r = 165 + Math.random() * 55;
  const h = 34 + Math.random() * 46;
  const m = new THREE.Mesh(
    new THREE.ConeGeometry(28 + Math.random() * 30, h, 5),
    new THREE.MeshStandardMaterial({ color: '#3a4450', roughness: 1, flatShading: true })
  );
  m.position.set(Math.cos(a) * r, h / 2 - 4, Math.sin(a) * r);
  m.rotation.y = Math.random() * 3;
  world.add(m);
}

/* ───────────────────────────────── 傳送點（往獸道 → 神社） ── */
const trailPortal = makePortalGlow(world, 0, heightAt(0, GATE_Z - 6), GATE_Z - 6);

/* ─────────────────────────────────────────────────────── 玩家 ── */
let saved = null;
try { saved = sessionStorage.getItem('gansokoy:char'); } catch { /* 私隱模式 */ }
const spec = PLAYABLE.find(p => p.id === saved) ?? PLAYABLE[0];

const model = buildCharacter(spec);
scene.add(model);
const ctrl = new PlayerController(model, camera, renderer.domElement, colliders);
ctrl.canFly = spec.canFly ?? true;
ctrl.maxAirJumps = spec.airJumps ?? 0;
ctrl.jumpV = spec.jump ?? 9.2;
ctrl.airJumpV = spec.airJump ?? 8.4;
ctrl.sprintMul = spec.sprintMul ?? 1.85;
ctrl.speedMul = spec.speed ?? 1.0;
ctrl.bounds = { hx: 96, hz: 96 };
ctrl.teleport(0, GATE_Z + 9);     // 從里門走進來
ctrl.yaw = 0;
ctrl.camYaw = Math.PI;

/* ────────────────────────────────── 戰鬥（里內和平，無怪） ── */
const prog = new Progression({ onLevelUp: (msg) => HUD.toast(msg) });
const slashFX = new SlashFX(scene);
const slashAudio = new SlashAudio();
const NO_MOBS = { inSector: () => [], damage: () => false, aliveNear: () => false, update() {} };
const combat = spec.combat ? new Combat(ctrl, NO_MOBS, slashFX, slashAudio, combatHUD) : null;
combatHUD.reset();
HUD.showCombatKeys(!!combat);
prog.renderBadge(spec.combat ? 'hinokami' : null, '日之呼吸');

/* ─────────────────────────────────────── 夜燈與環境回呼 ── */
env.opts.onApply = (t) => {
  for (const { lamp, light } of lanternGlows) {
    light.intensity = t.lantern * 4.5;
    lamp.material.emissiveIntensity = t.lantern > 0.05 ? 0.9 : 0.2;
  }
};
env.opts.onLabel = (text) => { HUD.todLabel.textContent = text; };
env.applyTime(env.hour, true);

/* ────────────────────────────────────────────── 互動與選單 ── */
const escMenu = bindEscMenu({
  getCtrl: () => ctrl,
  onBackToSelect() {
    HUD.showLoading('博麗神社 讀取中');
    location.href = 'index.html';
  },
});
bindCombatInput(() => combat, () => ctrl, () => escMenu.isOpen);

const nearPortal = () => Math.hypot(ctrl.pos.x, ctrl.pos.z - (GATE_Z - 6)) < 4.2;

window.addEventListener('keydown', (e) => {
  if (e.code !== 'KeyE' || !ctrl.locked || escMenu.isOpen) return;
  if (nearPortal()) { HUD.showLoading('獸道 讀取中'); location.href = 'trail.html?from=village'; }
});

/* ─────────────────────────────────────────────────── 主迴圈 ── */
const clock = new THREE.Clock();
let t = 0;

function tick(rawDt) {
  let dt = rawDt;
  if (combat?.hitstop > 0) dt *= 0.12;
  t += dt;
  ctrl.update(dt, t);
  combat?.update(dt, rawDt);
  slashFX.update(dt);
  env.update(dt, camera.position);
  trailPortal.userData.update(t);
  HUD.prompt(nearPortal() ? '[ E ]  前往獸道（往博麗神社）' : null);
}

function animate() {
  tick(Math.min(clock.getDelta(), 0.05));
  renderer.render(scene, camera);
  requestAnimationFrame(animate);
}

addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
});

document.getElementById('loading').style.display = 'none';
animate();

window.__village = {
  renderer, scene, camera, ctrl, THREE, heightAt, env, colliders,
  get combat() { return combat; },
  tp(x, z, yaw = 0) { ctrl.teleport(x, z); ctrl.yaw = yaw; },
  step(n = 1, dt = 0.016) {
    for (let i = 0; i < n; i++) tick(dt);
    return ctrl.pos.toArray().map(v => +v.toFixed(2));
  },
};
