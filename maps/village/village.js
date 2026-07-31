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
import { setGroundHeightFn } from '../../src/world/terrain.js';
import { WORLD } from '../../src/config.js';
import { buildCharacter } from '../../src/entities/model.js';
import { ACTIVE_PLAYABLE, DEFAULT_PLAYER } from '../../src/entities/roster.js';
import { PlayerController } from '../../src/player/controller.js';
import { Environment } from '../../src/world/environment.js';
import { makePortalGlow } from '../../src/world/portal.js';
import { Combat } from '../../src/combat/combat.js';
import { SlashFX, SlashAudio } from '../../src/fx/slash.js';
import { combatHUD, bindCombatInput } from '../../src/combat/hud.js';
import { Progression } from '../../src/player/progression.js';
import { installHUD, bindEscMenu } from '../../src/ui/hud.js';
import { loadQualityIdx, saveQualityIdx, applyBasicQuality, QUALITY_NAMES } from '../../src/world/quality.js';
import { VillagerCrowd } from '../../src/entities/villagers.js';
import { spawnAllNPCs } from '../../src/entities/shrine-spawn.js';
import { SceneEditor } from '../../src/ui/scene-editor.js';
import { mergeStaticByMaterial } from '../../src/core/optimize.js';

const HUD = installHUD({
  title: '人間之里',
  subtitle: 'HUMAN VILLAGE',
  keys: [
    ['WASD / 方向鍵', '移動'], ['滑鼠', '轉視角'], ['滾輪', '縮放'],
    ['Shift', '衝刺'], ['Space', '跳躍'],
    ['E', '互動'], ['P', '場景編輯'], ['ESC', '選單'],
  ],
  flyKeys: [['F', '飛行'], ['Ctrl/C', '下降']],
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
// near 拉到 0.2：深度緩衝的精度幾乎全由 near/far 的比值決定，0.08→0.2
// 等於把整條深度範圍的精度拉高 2.5 倍，鋪地物件與共面幾何就不容易閃。
// 第三人稱相機離視點最近也有 1.2 公尺（見 controller 的 _updateCamera），
// 不會有東西近到被 near 切掉。
const camera = new THREE.PerspectiveCamera(70, innerWidth / innerHeight, 0.2, 600);
camera.rotation.order = 'YXZ';

// 里是開闊的盆地：霧比獸道淡，看得到街尾與遠山
const env = new Environment(scene, renderer, { fogMul: 0.75, shadowArea: 70 });

/* 畫質（跨地圖共用的三檔，localStorage）：這張圖沒有後製鏈，
 * 套解析度 + 陰影貼圖的 basic 檔。 */
let qualityIdx = loadQualityIdx(2);
const syncQuality = () => {
  applyBasicQuality(renderer, env.sun, qualityIdx);
  HUD.qualLabel.textContent = `畫質：${QUALITY_NAMES[qualityIdx]}`;
};
syncQuality();

/* ─────────────────────────────────────────────────── 地形高度場 ── */
// 里蓋在平坦的盆地上：主街完全水平，外圍緩緩抬起成田埂與矮丘。
const VILLAGE_R = 62;      // 里的半徑（超過這裡開始爬坡）
const GATE_Z = -58;        // 北端里門（通獸道 → 博麗神社）
const SOUTH_GATE_Z = 96;   // 南端里門（通迷途竹林 → 永遠亭）

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
  // polygonOffset：石板路是鋪在地面上的薄薄一層，深度值跟地面非常接近。
  // 把它往鏡頭方向偏一點，地面就永遠搶不贏它，路草交界不會閃。
  road: new THREE.MeshStandardMaterial({
    map: stoneRoadTex, roughness: 1,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
  }),
  plaster: new THREE.MeshStandardMaterial({ map: plasterTex, roughness: 0.95, color: '#f2ead6' }),
  wood: new THREE.MeshStandardMaterial({ map: woodTex, roughness: 0.9, color: '#c8a880' }),
  darkWood: new THREE.MeshStandardMaterial({ map: woodTex, roughness: 0.95, color: '#6a5038' }),
  kura: new THREE.MeshStandardMaterial({ color: '#f4f0e2', roughness: 0.9 }),           // 土藏的白漆喰
  namako: new THREE.MeshStandardMaterial({ color: '#3a3f46', roughness: 0.85 }),        // 海鼠壁
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
/**
 * 鋪在地面上的東西（石板路、田埂）。
 *
 * 用一片固定高度的平面會同時得到兩個病：地形起伏高過那個高度時草會穿出來，
 * 兩者高度接近時整片閃爍（z-fighting）。解法是把平面細分，每個頂點各自抬到
 * 「該點的地面高度 + lift」，於是它跟地面永遠保持固定的薄薄一層距離；
 * 材質再開 polygonOffset，深度測試上穩定贏過地面，連邊緣都不會閃。
 *
 * @param {number} w  東西向寬
 * @param {number} d  南北向長
 * @param {number} x @param {number} z  中心
 * @param {THREE.Material} mat
 * @param {number} [lift=0.04] 離地高度（公尺）
 */
function groundDecal(w, d, x, z, mat, lift = 0.04) {
  // 每 2 公尺一段就夠了 —— 里內地形的起伏波長約 50 公尺，非常平緩
  const geo = new THREE.PlaneGeometry(w, d, Math.max(1, Math.round(w / 2)), Math.max(1, Math.round(d / 2)));
  geo.rotateX(-Math.PI / 2);
  const p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) {
    p.setY(i, heightAt(p.getX(i) + x, p.getZ(i) + z) + lift);
  }
  geo.computeVertexNormals();
  const m = new THREE.Mesh(geo, mat);
  m.position.set(x, 0, z);
  m.receiveShadow = true;
  world.add(m);
  return m;
}

(function ground() {
  // 90 格（3.3 公尺一格）就夠：里內地形是波長約 50 公尺的緩起伏，
  // 地面的線性內插跟真實曲面最多差 1 公釐，遠小於路面 4 公分的抬升。
  // 再細下去只是白花三角形（150 格要多兩萬八千個）。
  const geo = new THREE.PlaneGeometry(300, 300, 90, 90);
  geo.rotateX(-Math.PI / 2);
  const p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) p.setY(i, heightAt(p.getX(i), p.getZ(i)));
  geo.computeVertexNormals();
  const m = new THREE.Mesh(geo, MAT.ground);
  m.receiveShadow = true;
  world.add(m);

  // 主街（南北）與兩條橫街（東西）：石板路。主街往南延伸到新街廓。
  groundDecal(9, 176, 0, 20, MAT.road);   // 北門外 ~-68 一路鋪到南門外 ~108
  groundDecal(74, 7, 0, 8, MAT.road);
  groundDecal(58, 6, 0, 56, MAT.road);
})();

/* ─────────────────────────────────────────────────────── 建物 ── */
/**
 * 一棟明治風的建物。style 決定型式：
 *   'machiya'（預設）平房町家：土牆 + 木格柵 + 暖簾
 *   'two'     二層樓（旅籠、湯屋）：一樓同町家，上面再一層退縮的樓身 + 欄杆
 *   'kura'    土藏（倉庫）：白漆喰厚牆、海鼠壁裙、高窗、厚重的門，沒有格柵
 * @param {object} o {x,z,w,d,h,rot,roof,style,sign,signColor,noren}
 */
function house({ x, z, w = 9, d = 7, h = 4.2, rot = 0, roof = 'tile', style = 'machiya', sign = '', signColor = 0x6a5038, noren = null }) {
  const g = new THREE.Group();
  g.position.set(x, heightAt(x, z), z);
  g.rotation.y = rot;
  world.add(g);

  const kura = style === 'kura';
  const two = style === 'two';

  // 石基（土藏的基座高一點）
  box(w + 0.5, kura ? 0.7 : 0.35, d + 0.5, MAT.stone, 0, kura ? 0.35 : 0.17, 0, g);
  // 一樓屋身
  box(w, h, d, kura ? MAT.kura : MAT.plaster, 0, h / 2 + 0.3, 0, g);

  if (kura) {
    // 海鼠壁（下半截的深色格紋裙牆）+ 厚門 + 高窗
    box(w + 0.08, h * 0.42, d + 0.08, MAT.namako, 0, h * 0.21 + 0.4, 0, g);
    box(1.7, 2.2, 0.2, MAT.darkWood, 0, 1.5, d / 2 + 0.08, g);
    box(0.9, 0.7, 0.14, MAT.namako, w * 0.26, h - 0.5, d / 2 + 0.06, g);
  } else {
    // 一樓正面的木格柵與門
    box(w * 0.94, 2.2, 0.16, MAT.darkWood, 0, 1.4, d / 2 + 0.04, g);
    box(w * 0.3, 2.1, 0.1, MAT.paper, 0, 1.35, d / 2 + 0.13, g);      // 紙門
    for (let i = -3; i <= 3; i++) {
      box(0.1, 2.1, 0.06, MAT.darkWood, i * (w * 0.12), 1.35, d / 2 + 0.19, g);
    }
    // 角柱。外側面要「凸出牆面」而不是「切齊牆面」——
    // 切齊（sx * (w/2 - 0.14)）會讓柱子的側面與土牆完全共面，
    // 兩個面搶同一個深度值，遠看就是沿著建物邊緣一路閃。
    // 凸出 4 公分之後不但不閃，柱子也才真的讀得出是柱子。
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
      box(0.28, h + 0.3, 0.28, MAT.darkWood, sx * (w / 2 - 0.10), (h + 0.3) / 2, sz * (d / 2 - 0.10), g);
    }
  }

  // 二樓（退縮的樓身 + 高欄 + 格子窗）
  let topY = h + 0.3;                 // 屋頂的起算高度
  if (two) {
    const w2 = w * 0.9, d2 = d * 0.86, h2 = 3.0;
    box(w2, h2, d2, MAT.plaster, 0, h + 0.3 + h2 / 2, -(d - d2) / 2 * 0.4, g);
    // 二樓正面的連子窗
    for (let i = -2; i <= 2; i++) {
      box(w2 * 0.14, 1.1, 0.1, MAT.darkWood, i * w2 * 0.17, h + 0.3 + h2 * 0.52, d2 / 2 - (d - d2) / 2 * 0.4 + 0.06, g);
    }
    // 一樓簷（下屋）壓在一二樓之間
    const pent = box(w + 1.6, 0.24, d * 0.6, MAT.roofTile, 0, h + 0.42, d * 0.28, g);
    pent.rotation.x = 0.42;
    // 欄杆
    box(w2 * 0.96, 0.1, 0.1, MAT.darkWood, 0, h + 1.35, d2 / 2 - (d - d2) / 2 * 0.4 + 0.22, g);
    topY = h + 0.3 + h2;
  }

  // 屋頂
  const rm = roof === 'thatch' ? MAT.roofThatch : MAT.roofTile;
  const rh = roof === 'thatch' ? 2.8 : 1.9;
  const eave = roof === 'thatch' ? 1.5 : 1.1;
  const rw = two ? w * 0.98 : w;
  const rd = two ? d * 0.92 : d;
  for (const s of [-1, 1]) {
    const len = Math.hypot(rd / 2 + eave, rh);
    const slope = box(rw + eave * 1.4, 0.34, len, rm, 0, topY + rh / 2, s * (rd / 4 + eave / 2), g);
    slope.rotation.x = s * Math.atan2(rh, rd / 2 + eave);
  }
  box(rw + eave * 1.5, 0.42, 0.7, rm, 0, topY + rh, 0, g);        // 正脊
  // 山牆
  for (const s of [-1, 1]) {
    const shape = new THREE.Shape();
    const hd = rd / 2 + eave * 0.6;
    shape.moveTo(-hd, 0); shape.lineTo(hd, 0); shape.lineTo(0, rh);
    const tri = new THREE.Mesh(new THREE.ShapeGeometry(shape), kura ? MAT.kura : MAT.plaster);
    tri.position.set(s * (rw / 2 + 0.02), topY, 0);
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

  // 碰撞：屋身（旋轉過的建物也要跟著轉；高度取到最高一層）
  const cs = Math.abs(Math.cos(rot)), sn = Math.abs(Math.sin(rot));
  block(x, z, w * cs + d * sn, w * sn + d * cs, heightAt(x, z) + topY);
  return g;
}

// --- 主街兩側的店家（考據自 Touhou Wiki 的里內設施） ---
// 型式混搭：平房町家、二層樓的旅籠與湯屋、白牆土藏，屋頂瓦與茅草交錯，
// 街景才不會一整排長一樣。
const SHOPS = [
  { x: -11, z: -30, w: 10, d: 8, rot: Math.PI, sign: '寺子屋', roof: 'tile', signColor: 0x4a5a7a },   // 慧音的私塾
  { x: 12, z: -28, w: 9, d: 7, rot: Math.PI, sign: '豆腐', noren: 'blue' },
  { x: -12, z: -14, w: 8.5, d: 7, rot: Math.PI, sign: '花', noren: 'red' },
  { x: 12, z: -12, w: 9.5, d: 7.5, rot: Math.PI, sign: '霧雨屋', roof: 'thatch' },                     // 魔理沙老家
  { x: -12.5, z: 22, w: 9, d: 7, rot: 0, sign: '鈴奈庵', noren: 'blue' },                              // 小鈴的租書店
  { x: 12.5, z: 20, w: 10, d: 7.5, rot: 0, sign: '居酒屋', noren: 'red', roof: 'thatch' },
  { x: -13, z: 38, w: 9, d: 7, rot: 0, sign: '米', },
  { x: 13, z: 36, w: 8.5, d: 7, rot: 0, sign: '鍛冶', roof: 'thatch' },
  // ---- 南側新街廓 ----
  { x: -12, z: 50, w: 10, d: 7.5, rot: 0, sign: '旅籠', style: 'two', noren: 'blue' },                 // 二層樓的旅店
  { x: 12.5, z: 52, w: 9, d: 7, rot: 0, sign: '茶屋', noren: 'red' },
  { x: -12.5, z: 66, w: 9.5, d: 7.5, rot: 0, sign: '湯屋', style: 'two', roof: 'tile' },               // 錢湯
  { x: 12, z: 66, w: 9, d: 7, rot: 0, sign: '蕎麥', noren: 'blue', roof: 'thatch' },
  { x: -11.5, z: 80, w: 8.5, d: 7, rot: 0, sign: '織', },
  { x: 12.5, z: 80, w: 9, d: 7, rot: 0, sign: '甘味', noren: 'red' },
];
for (const s of SHOPS) house(s);

// 二排的民家與土藏：主街後面也要有人住，里才有厚度
const BACK_BUILDINGS = [
  { x: -26, z: -28, w: 8, d: 6.5, rot: Math.PI * 0.5, roof: 'thatch' },
  { x: 27, z: -22, w: 8.5, d: 6.5, rot: -Math.PI * 0.5 },
  { x: 27, z: -38, w: 7, d: 6, rot: -Math.PI * 0.5, style: 'kura' },                                   // 土藏
  { x: -27, z: 30, w: 8, d: 6.5, rot: Math.PI * 0.5, roof: 'thatch' },
  { x: 28, z: 32, w: 8, d: 6.5, rot: -Math.PI * 0.5 },
  { x: 26, z: 48, w: 7, d: 6, rot: -Math.PI * 0.5, style: 'kura' },                                    // 土藏
  { x: -26, z: 56, w: 8.5, d: 7, rot: Math.PI * 0.5, style: 'two' },                                   // 二層樓民家
  { x: -27, z: 74, w: 8, d: 6.5, rot: Math.PI * 0.5, roof: 'thatch' },
  { x: 27, z: 74, w: 8, d: 6.5, rot: -Math.PI * 0.5 },
  { x: 0, z: 92, w: 9, d: 7, rot: 0, roof: 'thatch' },                                                 // 街尾的農家
];
for (const b of BACK_BUILDINGS) house(b);

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
for (let i = -4; i <= 7; i++) {
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
stall(6.5, 58, 0.08, MAT.cloth);
stall(-6.5, 60, -0.06, MAT.cloth);

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
tree(-4.5, 62, 1.1, MAT.leafPink);
tree(4.6, 50, 1.05, MAT.leafPink);
for (let i = 0; i < 60; i++) {
  const a = Math.random() * Math.PI * 2;
  const r = 36 + Math.random() * 52;
  const x = Math.cos(a) * r, z = Math.sin(a) * r * 1.4;
  if (Math.abs(x) < 20 && z > -62 && z < 98) continue;        // 街廓與主街留空（含南側新街廓）
  tree(x, z, 0.85 + Math.random() * 0.8, MAT.leaf);
}

// 田埂（里外的水田格子，純視覺）。材質共用一份 —— 每格各自 new 一個的話，
// 靜態合併只能按材質分組，14 格就是 14 個 draw call。
const PADDY_MAT = new THREE.MeshStandardMaterial({
  color: '#6f7f42', roughness: 1,
  polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
});
for (let i = 0; i < 14; i++) {
  const side = i % 2 ? 1 : -1;
  const x = side * (40 + (i % 5) * 9);
  const z = -40 + (i * 11) % 92;
  // 水田在里外的斜坡上，起伏比里內大得多 —— 一定要貼著地形，否則整片浮空或埋進土裡
  groundDecal(14, 9, x, z, PADDY_MAT, 0.05);
}

/* ───────────────────────────── 里門（南北兩座，通獸道與竹林） ── */
/**
 * 冠木門 + 兩側土牆。南北兩座長一樣，只有朝向相反。
 * @param {number} gz 門的 z 座標
 * @param {number} inward 里的內側方向（北門 +1，南門 -1）——
 *        結界柱要立在門的內側才對得上「進里前先過結界」。
 */
function villageGate(gz, inward) {
  const y = heightAt(0, gz);
  // 冠木門：兩根柱 + 橫樑 + 小屋頂
  for (const s of [-1, 1]) {
    cyl(0.42, 0.48, 6.2, MAT.darkWood, s * 4.4, y + 3.1, gz, 10);
    post(s * 4.4, gz, 0.55, y + 6.2);
  }
  box(11, 0.7, 0.8, MAT.darkWood, 0, y + 6.0, gz);
  box(9.4, 0.45, 0.6, MAT.darkWood, 0, y + 5.0, gz);
  for (const s of [-1, 1]) {
    const slope = box(12, 0.3, 2.2, MAT.roofTile, 0, y + 6.7, gz + s * 0.9);
    slope.rotation.x = s * 0.5;
  }
  // 門旁的土牆（里的外圍），中間留門口
  for (const s of [-1, 1]) {
    const wx = s * 17;
    box(20, 2.4, 0.7, MAT.plaster, wx, y + 1.2, gz);
    box(20.4, 0.25, 1.0, MAT.roofTile, wx, y + 2.45, gz);
    block(wx, gz, 20, 0.7, y + 2.45);
  }
  // 門前的注連繩結界柱
  for (const s of [-1, 1]) {
    cyl(0.16, 0.18, 1.6, MAT.stone, s * 6.4, y + 0.8, gz + 2.6 * inward, 8);
    post(s * 6.4, gz + 2.6 * inward, 0.22, y + 1.6);
  }
}
villageGate(GATE_Z, 1);          // 北端：通獸道 → 博麗神社
villageGate(SOUTH_GATE_Z, -1);   // 南端：通迷途竹林 → 永遠亭

// 遠山（讓盆地有邊界感）
// 材質共用一份 —— 每座山各自 new 一個材質的話，靜態合併只能按材質分組，
// 18 座山就永遠是 18 個 draw call。
const MOUNTAIN_MAT = new THREE.MeshStandardMaterial({ color: '#3a4450', roughness: 1, flatShading: true });
for (let i = 0; i < 18; i++) {
  const a = (i / 18) * Math.PI * 2 + 0.3;
  const r = 165 + Math.random() * 55;
  const h = 34 + Math.random() * 46;
  const m = new THREE.Mesh(new THREE.ConeGeometry(28 + Math.random() * 30, h, 5), MOUNTAIN_MAT);
  m.position.set(Math.cos(a) * r, h / 2 - 4, Math.sin(a) * r);
  m.rotation.y = Math.random() * 3;
  world.add(m);
}

/* ─────────────────────────── 傳送點（北往獸道、南往竹林） ── */
const trailPortal = makePortalGlow(world, 0, heightAt(0, GATE_Z - 6), GATE_Z - 6);
const bambooPortal = makePortalGlow(world, 0, heightAt(0, SOUTH_GATE_Z + 6), SOUTH_GATE_Z + 6, 0xd8f0a0);

/* ──────────────────────────────────────────── 靜態幾何合併 ── */
// 里是三張圖裡最重的一張（近 1800 個網格）：房舍、圍牆、街燈、水田、遠山
// 全部不會動，依「材質 × 空間格子」合併。里是南北向的長條聚落，
// 格子 50 公尺讓走在主街時，街尾的房子整塊被視錐裁掉。
// 路人與 NPC 掛在 scene、傳送光點已標記 noMerge，都不受影響。
{
  const s = mergeStaticByMaterial(world, { cell: 50 });
  console.info(`[optimize] 人間之里靜態合併：${s.before} → ${s.after} 個網格（合併成 ${s.merged}，保留 ${s.kept}）`);
}

/* ─────────────────────────────────────────── 里民路人 ── */
// 街道的路點圖：主街兩側各一條人行動線 + 橫街一條，交叉口互通，
// 再從主街拉幾條支線到店門口（讓路人會走到店家前面停下來）。
const CROWD_GRAPH = (() => {
  const nodes = [];
  const links = [];
  const add = (x, z) => (nodes.push([x, z]), nodes.length - 1);
  const chain = (ids) => { for (let i = 0; i < ids.length - 1; i++) links.push([ids[i], ids[i + 1]]); };

  const zs = [-52, -42, -32, -22, -12, -2, 8, 18, 28, 38, 48, 56, 64, 72, 80];
  const west = zs.map(z => add(-3.0, z));      // 主街西側動線
  const east = zs.map(z => add(3.0, z));       // 主街東側動線
  chain(west); chain(east);

  const xs = [-32, -24, -16, -8, 8, 16, 24, 32];
  const cross = xs.map(x => add(x, 8));        // 橫街
  chain(cross);
  const xs2 = [-24, -16, -8, 8, 16, 24];
  const cross2 = xs2.map(x => add(x, 56));     // 南側橫街
  chain(cross2);

  // 交叉口：把橫街接上主街（zs 裡 z=8 的索引是 6、z=56 的索引是 11）
  const wMid = west[6], eMid = east[6];
  links.push([wMid, eMid]);
  links.push([cross[3], wMid]);                // x=-8 接西側
  links.push([cross[4], eMid]);                // x=+8 接東側
  const wMid2 = west[11], eMid2 = east[11];
  links.push([wMid2, eMid2]);
  links.push([cross2[2], wMid2]);
  links.push([cross2[3], eMid2]);

  // 店門口支線：站到店前一點的位置，會有人在那邊逗留
  for (const s of SHOPS) {
    const sideX = Math.sign(s.x) * 6.2;
    const doorZ = s.z + (s.rot === 0 ? -(s.d / 2 + 1.6) : (s.d / 2 + 1.6));
    const door = add(sideX, doorZ);
    // 接到主街上最近的節點
    const lane = s.x < 0 ? west : east;
    let best = lane[0], bd = Infinity;
    for (const n of lane) {
      const d = Math.abs(nodes[n][1] - doorZ);
      if (d < bd) { bd = d; best = n; }
    }
    links.push([door, best]);
  }
  return { nodes, links };
})();
const crowd = new VillagerCrowd(scene, heightAt, CROWD_GRAPH, 52);

/* ─────────────────────────────────────────────────────── 玩家 ── */
let saved = null;
try { saved = sessionStorage.getItem('gansokoy:char'); } catch { /* 私隱模式 */ }
const spec = ACTIVE_PLAYABLE.find(p => p.id === saved) ?? DEFAULT_PLAYER;

const model = buildCharacter(spec);
scene.add(model);
const ctrl = new PlayerController(model, camera, renderer.domElement, colliders);
ctrl.canFly = spec.canFly ?? true;
ctrl.maxAirJumps = spec.airJumps ?? 0;
ctrl.jumpV = spec.jump ?? 9.2;
ctrl.airJumpV = spec.airJump ?? 8.4;
ctrl.sprintMul = spec.sprintMul ?? 1.85;
ctrl.speedMul = spec.speed ?? 1.0;
ctrl.bounds = { hx: 96, hz: 108 };
// 從哪一端走進來，就從那一端出生
if (new URLSearchParams(location.search).get('from') === 'bamboo') {
  ctrl.teleport(0, SOUTH_GATE_Z - 9);
  ctrl.yaw = Math.PI;             // 面向北（往里內／獸道）
  ctrl.camYaw = 0;
} else {
  ctrl.teleport(0, GATE_Z + 9);   // 從北邊的里門走進來
  ctrl.yaw = 0;
  ctrl.camYaw = Math.PI;
}

/* ───────────────────── 名冊角色（預設沒有人，全交給場景編輯器） ── */
const labelScene = new THREE.Scene();
const npcSystem = spawnAllNPCs(scene, heightAt, labelScene, spec.id, { seed: false });

const sceneEditor = new SceneEditor({
  scene, camera, renderer, world, heightAt, npcSystem,
  getPlayerId: () => spec.id,
  getCtrl: () => ctrl,
  toggles: [
    { label: '路人', get: () => crowd.visible, set: (v) => crowd.setVisible(v) },
  ],
});

/* ────────────────────────────────── 戰鬥（里內和平，無怪） ── */
const prog = new Progression({ onLevelUp: (msg) => HUD.toast(msg) });
const slashFX = new SlashFX(scene);
const slashAudio = new SlashAudio();
const NO_MOBS = { inSector: () => [], damage: () => false, aliveNear: () => false, update() {} };
const combat = spec.combat ? new Combat(ctrl, NO_MOBS, slashFX, slashAudio, combatHUD) : null;
combatHUD.reset();
HUD.showCombatKeys(!!combat);
HUD.showFlyKeys(spec.canFly !== false);
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
  env,
  quality: {
    get: () => QUALITY_NAMES[qualityIdx],
    cycle() {
      qualityIdx = (qualityIdx + 1) % QUALITY_NAMES.length;
      saveQualityIdx(qualityIdx);
      syncQuality();
      return QUALITY_NAMES[qualityIdx];
    },
  },
  isBusy: () => sceneEditor.isOpen,
  onBackToSelect() {
    HUD.showLoading('博麗神社 讀取中');
    location.href = '../../index.html';
  },
});
bindCombatInput(() => combat, () => ctrl, () => escMenu.isOpen || sceneEditor.isOpen);

const nearPortal = () => Math.hypot(ctrl.pos.x, ctrl.pos.z - (GATE_Z - 6)) < 4.2;
const nearBamboo = () => Math.hypot(ctrl.pos.x, ctrl.pos.z - (SOUTH_GATE_Z + 6)) < 4.2;

window.addEventListener('keydown', (e) => {
  // ESC 在編輯器開著時是「關掉編輯器」（bindEscMenu 的 isBusy 已讓過）
  if (e.code === 'Escape' && sceneEditor.isOpen) { sceneEditor.close(); return; }
  // P：開關場景編輯器。放在鎖定判斷之前 —— 開啟時會解除滑鼠鎖定。
  if (e.code === 'KeyP') { sceneEditor.toggle(); e.preventDefault(); return; }
  if (sceneEditor.isOpen || escMenu.isOpen) return;
  if (e.code !== 'KeyE' || !ctrl.locked) return;
  if (nearPortal()) { HUD.showLoading('獸道 讀取中'); location.href = '../trail/?from=village'; return; }
  if (nearBamboo()) { HUD.showLoading('迷途竹林 讀取中'); location.href = '../bamboo/'; }
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
  crowd.update(dt, t, ctrl.pos);
  npcSystem.update(t, ctrl.pos, camera);
  env.update(dt, camera.position);
  trailPortal.userData.update(t);
  bambooPortal.userData.update(t);
  if (nearPortal()) HUD.prompt('[ E ]  前往獸道（往博麗神社）');
  else if (nearBamboo()) HUD.prompt('[ E ]  前往迷途竹林（往永遠亭）');
  else HUD.prompt(null);
}

function animate() {
  tick(Math.min(clock.getDelta(), 0.05));
  renderer.render(scene, camera);
  // 名牌是 depthTest:false 的 sprite，跟神社一樣在主畫面之後單獨畫
  if (labelScene.children.length) {
    const prev = renderer.autoClear;
    renderer.autoClear = false;
    renderer.render(labelScene, camera);
    renderer.autoClear = prev;
  }
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
  crowd, npcs: npcSystem, sceneEditor,
  get combat() { return combat; },
  tp(x, z, yaw = 0) { ctrl.teleport(x, z); ctrl.yaw = yaw; },
  step(n = 1, dt = 0.016) {
    for (let i = 0; i < n; i++) tick(dt);
    return ctrl.pos.toArray().map(v => +v.toFixed(2));
  },
  /** 手動渲染一格（量 renderer.info 用，跟 __shrine.frame 同口徑） */
  frame() { renderer.render(scene, camera); },
  setHour(h) { return env.setHour(h); },
  setTimeFlowing(v) { env.timeFlowing = v; },
};
