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
import { Progression } from '../../src/player/progression.js';
import { installLoadout } from '../../src/player/loadout.js';
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
    ['E', '互動'], ['K', '技能'], ['P', '場景編輯'], ['ESC', '選單'],
  ],
  flyKeys: [['F', '飛行'], ['Ctrl/C', '下降']],
  combatKeys: [['左鍵', '出招'], ['長按左鍵', '日之呼吸・全型'], ['R', '拔刀/納刀'], ['1 ~ 4', '技']],
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
const camera = new THREE.PerspectiveCamera(70, innerWidth / innerHeight, 0.2, 900);
camera.rotation.order = 'YXZ';

// 里是開闊的盆地：霧比獸道淡，看得到街尾與遠山
const env = new Environment(scene, renderer, { fogMul: 0.75, shadowArea: 78, followSun: true });

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
// 里的規模。參考 Touhou Wiki 與明治期町屋聚落的街廓尺度：
// 網格狀的街廓、主街貫穿南北、橫街切出街區，外圍是水田與矮丘。
const VILLAGE_R = 175;     // 里的半徑（超過這裡開始爬坡）
const GATE_Z = -168;       // 北端里門（通獸道 → 博麗神社）
const SOUTH_GATE_Z = 250;  // 南端里門（里的南界，不是出口）
const RIVER_X = 118;       // 東側的河（穿過里的東緣）

/** 河道中心線 —— 蜿蜒穿過里的東側 */
function riverX(z) {
  return RIVER_X + Math.sin(z * 0.011) * 16 + Math.sin(z * 0.026 + 1.3) * 7;
}

function heightAt(x, z) {
  // 河床：里的東緣被切出一道低地，過河要走橋
  const rd = Math.abs(x - riverX(z));
  const river = rd < 9 ? -1.6 * (1 - (rd / 9) * (rd / 9)) : 0;

  const d = Math.hypot(x * 0.8, z * 0.62);        // 橢圓形的里
  if (d < VILLAGE_R) {
    return Math.sin(x * 0.09) * 0.08 + Math.sin(z * 0.07) * 0.08 + river;
  }
  const out = d - VILLAGE_R;
  // 外圍矮丘要封頂 —— 二次式不封的話在地面網格邊緣會衝到幾百公尺
  return Math.min(30, out * out * 0.012) + river;
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
  // 里放大到半徑 175 之後，地面也要跟著大。90 格（4.4m 一格）維持原本的
  // 精度取捨：里內起伏平緩，線性內插與真實曲面的差遠小於路面 4 公分的抬升。
  const S = 460;
  const geo = new THREE.PlaneGeometry(S, S, 110, 110);
  geo.rotateX(-Math.PI / 2);
  const p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) p.setY(i, heightAt(p.getX(i), p.getZ(i)));
  geo.computeVertexNormals();
  const m = new THREE.Mesh(geo, MAT.ground);
  m.receiveShadow = true;
  world.add(m);
})();

/* ───────────────────────────────────────── 街道（網格） ── */
// 參考圖的重點是「網格狀街廓」而不是一條主街：主街貫穿南北，
// 五條橫街切出街區，街區之間再補幾條小巷。
const CROSS_Z = [-120, -70, -20, 40, 100, 165];   // 橫街
const LANE_X = [-72, -36, 36, 72];                // 縱向的小巷
{
  // 主街（南北貫穿）
  groundDecal(11, 470, 0, 40, MAT.road);
  // 橫街
  for (const cz of CROSS_Z) groundDecal(196, 8, 0, cz, MAT.road);
  // 小巷（比主街窄，鋪到南北兩端的街廓為止）
  for (const lx of LANE_X) groundDecal(6.5, 320, lx, 20, MAT.road);
}

/* ────────────────────────────────────────────── 河與橋 ── */
// 里的東緣有一條河。地形已經在 heightAt 裡挖出河床，這裡鋪水面與石橋。
const RIVER_MAT = new THREE.MeshStandardMaterial({
  color: '#4a6f86', roughness: 0.14, metalness: 0.35,
  transparent: true, opacity: 0.86,
});
(function river() {
  const SEG = 120, pos = [], uv = [], idx = [];
  for (let i = 0; i <= SEG; i++) {
    const z = -230 + (i / SEG) * 460;
    const cx = riverX(z);
    for (const sgn of [-1, 1]) {
      pos.push(cx + sgn * 7.5, -1.05, z);
      uv.push(sgn > 0 ? 1 : 0, i * 0.4);
    }
    if (i < SEG) {
      const k = i * 2;
      // 繞向要讓法線朝上，反了整條河會被背面剔除（竹林踩過這個坑）
      idx.push(k, k + 2, k + 1, k + 1, k + 2, k + 3);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  const m = new THREE.Mesh(geo, RIVER_MAT);
  m.userData.noMerge = true;      // 半透明，靠逐物件排序才畫得對
  world.add(m);
})();

/** 石橋 —— 橫街跨過河的地方 */
function bridge(z) {
  const cx = riverX(z);
  const g = new THREE.Group();
  g.position.set(cx, 0, z);
  world.add(g);
  // 橋面（微拱）
  for (let i = -3; i <= 3; i++) {
    const t = i / 3;
    const y = 0.5 - t * t * 0.35;
    box(3.0, 0.34, 8.4, MAT.stone, i * 3.0, y, 0, g);
  }
  // 欄杆
  for (const sd of [-1, 1]) {
    for (let i = -3; i <= 3; i++) {
      const t = i / 3, y = 0.5 - t * t * 0.35;
      cyl(0.12, 0.13, 0.9, MAT.stone, i * 3.0, y + 0.6, sd * 3.9, 8, g);
    }
    const rail = box(19, 0.18, 0.22, MAT.stone, 0, 1.15, sd * 3.9, g);
    rail.rotation.x = 0;
  }
  block(cx, z, 20, 8.6, 0.9);
}
for (const cz of [-70, 40, 165]) bridge(cz);

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
  // ---- 北段（里門進來的第一條街） ----
  { x: -13, z: -140, w: 9, d: 7, rot: Math.PI, sign: '番所', roof: 'tile', signColor: 0x4a5a7a },
  { x: 13.5, z: -138, w: 8.5, d: 7, rot: Math.PI, sign: '馬宿', roof: 'thatch' },
  { x: -13, z: -112, w: 10, d: 8, rot: Math.PI, sign: '寺子屋', roof: 'tile', signColor: 0x4a5a7a },  // 慧音的私塾
  { x: 13, z: -108, w: 9, d: 7, rot: Math.PI, sign: '豆腐', noren: 'blue' },
  { x: -13.5, z: -86, w: 8.5, d: 7, rot: Math.PI, sign: '花', noren: 'red' },
  { x: 13, z: -84, w: 9.5, d: 7.5, rot: Math.PI, sign: '霧雨屋', roof: 'thatch' },                    // 魔理沙老家
  { x: -13, z: -58, w: 9, d: 7, rot: Math.PI, sign: '炭', },
  { x: 13.5, z: -56, w: 8.5, d: 7, rot: Math.PI, sign: '酒', noren: 'blue' },

  // ---- 中段（水井廣場與龍神像一帶） ----
  { x: -13.5, z: -12, w: 9, d: 7, rot: 0, sign: '鈴奈庵', noren: 'blue' },                            // 小鈴的租書店
  { x: 13.5, z: -10, w: 10, d: 7.5, rot: 0, sign: '鯢呑亭', style: 'two', noren: 'red' },             // 里的居酒屋
  { x: -13, z: 14, w: 9, d: 7, rot: 0, sign: '米', },
  { x: 13, z: 16, w: 8.5, d: 7, rot: 0, sign: '鍛冶', roof: 'thatch' },
  { x: -13.5, z: 62, w: 10, d: 7.5, rot: 0, sign: '旅籠', style: 'two', noren: 'blue' },              // 二層樓的旅店
  { x: 13, z: 64, w: 9, d: 7, rot: 0, sign: '茶屋', noren: 'red' },

  // ---- 南段 ----
  { x: -13, z: 90, w: 9.5, d: 7.5, rot: 0, sign: '湯屋', style: 'two', roof: 'tile' },                // 錢湯
  { x: 13.5, z: 92, w: 9, d: 7, rot: 0, sign: '蕎麥', noren: 'blue', roof: 'thatch' },
  { x: -13, z: 120, w: 8.5, d: 7, rot: 0, sign: '織', },
  { x: 13, z: 122, w: 9, d: 7, rot: 0, sign: '甘味', noren: 'red' },
  { x: -13.5, z: 150, w: 9, d: 7, rot: 0, sign: '藥', noren: 'blue' },
  { x: 13, z: 152, w: 8.5, d: 7, rot: 0, sign: '桶', roof: 'thatch' },
  { x: -13, z: 196, w: 9, d: 7, rot: 0, sign: '青物', },
  { x: 13.5, z: 198, w: 9, d: 7, rot: 0, sign: '油', roof: 'thatch' },
];
for (const s of SHOPS) house(s);

/* ─────────────────────────────────────── 網格街廓的民家 ── */
// 參考圖的味道來自「一格一格的街廓，裡面塞滿長屋與土藏」。
// 這裡程式生成：每個街廓沿著邊緣排屋子，中間留空地（後院）。
const BLOCK_KEEP_OUT = [
  { x: -62, z: -20, r: 46 },     // 稗田邸
  { x: 0, z: -20, r: 26 },       // 水井廣場
  { x: 0, z: 40, r: 24 },        // 龍神像廣場
];
(function blocks() {
  const clearOf = (x, z) => BLOCK_KEEP_OUT.every(k => Math.hypot(x - k.x, z - k.z) > k.r);
  // 街廓的中心：主街與小巷之間、橫街與橫街之間
  const colCenters = [-94, -54, -18, 18, 54, 94];
  for (let ci = 0; ci < colCenters.length; ci++) {
    const cx = colCenters[ci];
    for (let zi = 0; zi < CROSS_Z.length - 1; zi++) {
      const z0 = CROSS_Z[zi] + 8, z1 = CROSS_Z[zi + 1] - 8;
      const depth = z1 - z0;
      if (depth < 16) continue;
      // 沿街廓的南北兩邊各排一列屋子，面朝橫街
      for (const [zEdge, rot] of [[z0 + 5, 0], [z1 - 5, Math.PI]]) {
        const n = Math.max(1, Math.round(28 / 11));
        for (let k = 0; k < n; k++) {
          const x = cx + (k - (n - 1) / 2) * 11 + (Math.random() - 0.5) * 1.6;
          const z = zEdge + (Math.random() - 0.5) * 2;
          if (!clearOf(x, z)) continue;
          if (Math.abs(x - riverX(z)) < 14) continue;         // 河道留空
          if (Math.abs(x) < 19) continue;                     // 主街的店家已經佔了
          const r = Math.random();
          house({
            x, z, w: 7.5 + Math.random() * 2.4, d: 6 + Math.random() * 1.6,
            rot: rot + (Math.random() - 0.5) * 0.06,
            roof: r < 0.34 ? 'thatch' : 'tile',
            style: r > 0.9 ? 'kura' : (r > 0.78 ? 'two' : 'machiya'),
          });
        }
      }
    }
  }
})();

/* ────────────────────────────────────────────── 稗田邸 ── */
// 稗田家是里內最大的宅子 —— 御阿禮之子（現在是稗田阿求）代代編纂
// 《幻想鄉緣起》的地方。做成帶院牆的書院造：主屋 + 藏 + 前庭 + 表門。
(function hiedaManor() {
  const MX = -62, MZ = -20;
  const y = heightAt(MX, MZ);
  const HW = 34, HD = 30;      // 院子的半寬／半深

  // 主屋（大屋頂的書院）
  house({ x: MX - 6, z: MZ - 4, w: 22, d: 15, h: 5.4, rot: Math.PI / 2, roof: 'tile', sign: '稗田' });
  // 離れ（別屋，阿求寫書的地方）與土藏（藏書）
  house({ x: MX + 12, z: MZ + 12, w: 11, d: 8.5, h: 4.2, rot: 0, roof: 'tile' });
  house({ x: MX - 14, z: MZ + 15, w: 9, d: 7.5, h: 4.4, rot: 0, style: 'kura' });

  // 院牆（四邊，東側留表門）
  const seg = (cx, cz, sx, sz) => {
    box(sx, 2.2, sz, MAT.plaster, cx, y + 1.1, cz);
    box(sx + 0.34, 0.26, sz + 0.34, MAT.roofTile, cx, y + 2.32, cz);   // 牆頭瓦
    block(cx, cz, sx, sz, y + 2.32);
  };
  seg(MX, MZ - HD, HW * 2, 0.7);
  seg(MX, MZ + HD, HW * 2, 0.7);
  seg(MX - HW, MZ, 0.7, HD * 2);
  seg(MX + HW, MZ - HD / 2 - 4, 0.7, HD - 8);
  seg(MX + HW, MZ + HD / 2 + 4, 0.7, HD - 8);

  // 表門（東側，朝主街）：兩根柱 + 屋頂
  {
    const gx = MX + HW, gz = MZ;
    for (const sd of [-1, 1]) {
      cyl(0.3, 0.34, 3.6, MAT.darkWood, gx, y + 1.8, gz + sd * 2.4, 8);
      post(gx, gz + sd * 2.4, 0.4, y + 3.6);
    }
    box(1.2, 0.45, 6.2, MAT.darkWood, gx, y + 3.6, gz);
    for (const sd of [-1, 1]) {
      const sl = box(2.6, 0.24, 7.0, MAT.roofTile, gx + sd * 0.55, y + 4.0, gz);
      sl.rotation.z = -sd * 0.5;
    }
  }

  // 前庭：踏石、石燈籠、松
  for (let i = 0; i < 7; i++) {
    const sx = MX + HW - 5 - i * 3.6, sz = MZ + Math.sin(i * 0.9) * 2.2;
    const st = new THREE.Mesh(new THREE.CylinderGeometry(0.55, 0.6, 0.16, 7), MAT.stone);
    st.position.set(sx, y + 0.09, sz);
    st.receiveShadow = true;
    world.add(st);
  }
  for (const sd of [-1, 1]) {
    const lx = MX + 6, lz = MZ + sd * 9;
    cyl(0.42, 0.5, 0.3, MAT.stone, lx, y + 0.15, lz, 8);
    cyl(0.24, 0.28, 1.3, MAT.stone, lx, y + 0.95, lz, 8);
    cyl(0.6, 0.42, 0.26, MAT.stone, lx, y + 1.73, lz, 8);
    box(0.42, 0.42, 0.42, MAT.paper, lx, y + 2.05, lz);
    cyl(0.1, 0.8, 0.42, MAT.stone, lx, y + 2.45, lz, 8);
    post(lx, lz, 0.5, y + 2.7);
  }
})();

/* ───────────────────────────────────────────── 龍神像 ── */
// 幻想鄉的龍神是最高位的神明。里的中央廣場立著一尊石造龍神像 ——
// 盤在石柱上、頭朝天，底下是奉納的石臺與注連繩柱。
(function dragonStatue() {
  const DX = 0, DZ = 40, y = heightAt(DX, DZ);
  const g = new THREE.Group();
  g.position.set(DX, y, DZ);
  world.add(g);

  // 基壇（三層方臺）
  box(11, 0.5, 11, MAT.stone, 0, 0.25, 0, g);
  box(8.4, 0.5, 8.4, MAT.stone, 0, 0.75, 0, g);
  box(6.2, 0.6, 6.2, MAT.stone, 0, 1.3, 0, g);
  block(DX, DZ, 11, 11, y + 1.6);

  // 中央的石柱
  cyl(1.05, 1.3, 5.4, MAT.stone, 0, 4.3, 0, 10, g);

  // 龍身：一圈一圈盤上柱子。半徑往上收、每段轉一點，就有纏繞的感覺。
  const scaleMat = new THREE.MeshStandardMaterial({ color: '#8e9aa2', roughness: 0.62, flatShading: true });
  const N = 46;
  for (let i = 0; i < N; i++) {
    const t = i / (N - 1);
    const a = t * Math.PI * 5.4;                 // 繞柱兩圈半
    const r = 1.55 - t * 0.55;
    const yy = 1.9 + t * 5.6;
    const rad = (0.46 - t * 0.24) * (1 - Math.pow(Math.abs(t - 0.15) * 1.1, 2) * 0.25);
    const seg = new THREE.Mesh(new THREE.SphereGeometry(Math.max(0.14, rad), 8, 6), scaleMat);
    seg.position.set(Math.cos(a) * r, yy, Math.sin(a) * r);
    seg.castShadow = true;
    g.add(seg);
    // 背鰭
    if (i % 3 === 0 && t < 0.9) {
      const fin = new THREE.Mesh(new THREE.ConeGeometry(0.16, 0.42, 4), scaleMat);
      fin.position.set(Math.cos(a) * r, yy + rad + 0.14, Math.sin(a) * r);
      fin.rotation.y = a;
      g.add(fin);
    }
  }
  // 龍首：昂起朝天
  {
    const hx = Math.cos(Math.PI * 5.4) * 1.0, hz = Math.sin(Math.PI * 5.4) * 1.0;
    const head = new THREE.Group();
    head.position.set(hx, 7.9, hz);
    head.rotation.y = Math.PI * 5.4 + 1.2;
    head.rotation.x = -0.55;
    g.add(head);
    const skull = new THREE.Mesh(new THREE.SphereGeometry(0.42, 10, 8), scaleMat);
    skull.scale.set(1, 0.85, 1.5);
    skull.castShadow = true;
    head.add(skull);
    const snout = new THREE.Mesh(new THREE.CylinderGeometry(0.17, 0.25, 0.7, 7), scaleMat);
    snout.rotation.x = Math.PI / 2;
    snout.position.set(0, -0.05, 0.62);
    head.add(snout);
    // 角與鬚
    for (const sd of [-1, 1]) {
      const horn = new THREE.Mesh(new THREE.ConeGeometry(0.09, 0.85, 5), scaleMat);
      horn.position.set(sd * 0.2, 0.34, -0.2);
      horn.rotation.set(-0.6, 0, sd * 0.3);
      head.add(horn);
      const whisk = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.02, 1.3, 5), scaleMat);
      whisk.position.set(sd * 0.24, -0.06, 0.85);
      whisk.rotation.set(1.25, 0, sd * 0.25);
      head.add(whisk);
    }
  }

  // 四角的注連繩柱（結界）
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    cyl(0.15, 0.17, 2.0, MAT.darkWood, sx * 5.0, 1.0, sz * 5.0, 8, g);
    post(DX + sx * 5.0, DZ + sz * 5.0, 0.22, y + 2.0);
  }
  // 奉納的石燈籠一對
  for (const sd of [-1, 1]) {
    cyl(0.4, 0.48, 0.3, MAT.stone, sd * 7.2, 0.15, -6.4, 8, g);
    cyl(0.23, 0.27, 1.5, MAT.stone, sd * 7.2, 1.05, -6.4, 8, g);
    cyl(0.58, 0.4, 0.26, MAT.stone, sd * 7.2, 1.93, -6.4, 8, g);
    box(0.4, 0.4, 0.4, MAT.paper, sd * 7.2, 2.26, -6.4, g);
    cyl(0.1, 0.78, 0.4, MAT.stone, sd * 7.2, 2.66, -6.4, 8, g);
    post(DX + sd * 7.2, DZ - 6.4, 0.5, y + 2.9);
  }
})();

/* ──────────────────────────────────────────── 里的公共設施 ── */
// 水井廣場（主街與橫街的交叉口）
(function well() {
  const WX = 0, WZ = -20, y = heightAt(WX, WZ);
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
// 街燈沿主街與橫街排。里放大之後不能再寫死幾盞 —— 用迴圈鋪。
for (let z = -160; z <= 240; z += 26) {
  streetLantern(-7.4, z);
  streetLantern(7.4, z + 13);
}
for (const cz of CROSS_Z) {
  for (const lx of [-88, -50, 50, 88]) streetLantern(lx, cz + 5.6);
}

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
// 市集：水井廣場與龍神像廣場周邊的攤位
for (let i = 0; i < 14; i++) {
  const cluster = i < 7 ? { x: 0, z: -20 } : { x: 0, z: 40 };
  const a = (i % 7) / 7 * Math.PI * 2 + (i < 7 ? 0.4 : 1.1);
  const r = 13 + Math.random() * 5;
  const x = cluster.x + Math.cos(a) * r, z = cluster.z + Math.sin(a) * r * 0.8;
  if (Math.abs(x) < 6.5) continue;                   // 主街正中央要留給行人
  stall(x, z, -a + Math.PI, i % 2 ? MAT.cloth : MAT.clothBlue);
}

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
// 廣場邊的櫻，其餘散在屋後、河岸與里外
tree(-9, -30, 1.2, MAT.leafPink);
tree(9, -12, 1.15, MAT.leafPink);
tree(-9, 30, 1.15, MAT.leafPink);
tree(9, 52, 1.1, MAT.leafPink);
// 河岸的柳與雜木
for (let i = 0; i < 46; i++) {
  const z = -210 + Math.random() * 420;
  const sd = Math.random() < 0.5 ? -1 : 1;
  const x = riverX(z) + sd * (9 + Math.random() * 5);
  tree(x, z, 0.85 + Math.random() * 0.7, MAT.leaf);
}
// 里外的雜木林
for (let i = 0; i < 180; i++) {
  const a = Math.random() * Math.PI * 2;
  const r = VILLAGE_R * (0.62 + Math.random() * 0.55);
  const x = Math.cos(a) * r, z = Math.sin(a) * r * 1.35;
  if (Math.abs(x) < 108 && z > -175 && z < 258) continue;    // 街廓範圍留空
  if (Math.abs(x - riverX(z)) < 11) continue;                // 河道留空
  tree(x, z, 0.85 + Math.random() * 0.8, MAT.leaf);
}

// 田埂（里外的水田格子，純視覺）。材質共用一份 —— 每格各自 new 一個的話，
// 靜態合併只能按材質分組，14 格就是 14 個 draw call。
const PADDY_MAT = new THREE.MeshStandardMaterial({
  color: '#6f7f42', roughness: 1,
  polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
});
// 里外一圈的水田。放大之後數量也要跟上，不然外圍會是一片空草地。
for (let i = 0; i < 44; i++) {
  const side = i % 2 ? 1 : -1;
  const x = side * (128 + (i % 6) * 15);
  const z = -190 + (i * 21) % 420;
  if (Math.abs(x - riverX(z)) < 14) continue;      // 河道上不種田
  // 水田在里外的斜坡上，起伏比里內大得多 —— 一定要貼著地形，
  // 否則整片浮空或埋進土裡
  groundDecal(17, 11, x, z, PADDY_MAT, 0.05);
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
  // 門旁的土牆（里的外圍），中間留門口。里放大之後牆也要拉長，
  // 不然門兩側是空的，「進里」的感覺就沒了。
  for (const sd of [-1, 1]) {
    for (let k = 0; k < 5; k++) {
      const wx = sd * (17 + k * 20);
      box(20, 2.4, 0.7, MAT.plaster, wx, y + 1.2, gz);
      box(20.4, 0.25, 1.0, MAT.roofTile, wx, y + 2.45, gz);
      block(wx, gz, 20, 0.7, y + 2.45);
    }
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
  const r = 300 + Math.random() * 90;
  const h = 46 + Math.random() * 60;
  const m = new THREE.Mesh(new THREE.ConeGeometry(28 + Math.random() * 30, h, 5), MOUNTAIN_MAT);
  m.position.set(Math.cos(a) * r, h / 2 - 4, Math.sin(a) * r);
  m.rotation.y = Math.random() * 3;
  world.add(m);
}

/* ─────────────────────────────── 傳送點（只有北端通獸道） ── */
// 里只有一個對外的出口：北門的獸道。要去迷途竹林得走回獸道再往東南岔 ——
// 里跟竹林之間沒有直達的路，那條分岔才有存在感。
// 南門保留成建築（里的南界），但不是傳送點。
const trailPortal = makePortalGlow(world, 0, heightAt(0, GATE_Z - 6), GATE_Z - 6);

/* ──────────────────────────────────────────── 靜態幾何合併 ── */
// 里是三張圖裡最重的一張（近 1800 個網格）：房舍、圍牆、街燈、水田、遠山
// 全部不會動，依「材質 × 空間格子」合併。里是南北向的長條聚落，
// 格子 50 公尺讓走在主街時，街尾的房子整塊被視錐裁掉。
// 路人與 NPC 掛在 scene、傳送光點已標記 noMerge，都不受影響。
{
  const s = mergeStaticByMaterial(world, { cell: 60 });
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

  // 主街兩側的動線，貫穿南北。里放大之後路點也要鋪滿全長 ——
  // 不然六十幾位路人會全部擠在中間那一小段。
  const zs = [];
  for (let z = -160; z <= 235; z += 11) zs.push(z);
  const west = zs.map(z => add(-3.6, z));
  const east = zs.map(z => add(3.6, z));
  chain(west); chain(east);

  /** 找主街上離某個 z 最近的節點 */
  const nearestOnLane = (lane, z) => {
    let best = lane[0], bd = Infinity;
    for (const n of lane) {
      const d = Math.abs(nodes[n][1] - z);
      if (d < bd) { bd = d; best = n; }
    }
    return best;
  };

  // 每條橫街一條動線，兩端接到縱向小巷
  for (const cz of CROSS_Z) {
    const xs = [-96, -74, -52, -36, -18, 18, 36, 52, 74, 96];
    const row = xs.map(x => add(x, cz + 2.4));
    chain(row);
    // 接主街（跨過中間的缺口）
    const w = nearestOnLane(west, cz + 2.4), e = nearestOnLane(east, cz + 2.4);
    links.push([w, e]);
    links.push([row[4], w]);      // x=-18 接西側
    links.push([row[5], e]);      // x=+18 接東側
  }

  // 縱向小巷的動線
  for (const lx of LANE_X) {
    const col = [];
    for (let z = -140; z <= 200; z += 22) col.push(add(lx + 2.2, z));
    chain(col);
    // 每條橫街的交叉口接上去
    for (const cz of CROSS_Z) {
      let best = col[0], bd = Infinity;
      for (const n of col) {
        const d = Math.abs(nodes[n][1] - (cz + 2.4));
        if (d < bd) { bd = d; best = n; }
      }
      if (bd < 16) {
        // 找同一條橫街上最近的節點
        let r = -1, rd = Infinity;
        for (let n = 0; n < nodes.length; n++) {
          if (Math.abs(nodes[n][1] - (cz + 2.4)) > 0.01) continue;
          const d = Math.abs(nodes[n][0] - (lx + 2.2));
          if (d < rd) { rd = d; r = n; }
        }
        if (r >= 0 && rd < 26) links.push([best, r]);
      }
    }
  }

  // 店門口支線：站到店前一點的位置，會有人在那邊逗留
  for (const s of SHOPS) {
    const sideX = Math.sign(s.x) * 6.6;
    const doorZ = s.z + (s.rot === 0 ? -(s.d / 2 + 1.6) : (s.d / 2 + 1.6));
    const door = add(sideX, doorZ);
    links.push([door, nearestOnLane(s.x < 0 ? west : east, doorZ)]);
  }

  return { nodes, links };
})();
const crowd = new VillagerCrowd(scene, heightAt, CROWD_GRAPH, 64, 10);

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
ctrl.bounds = { hx: 240, hz: 300 };
ctrl.teleport(0, GATE_Z + 9);   // 里只有北門一個入口
ctrl.yaw = 0;
ctrl.camYaw = Math.PI;

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
const prog = new Progression({
  onLevelUp: (msg) => { HUD.toast(msg); kit.skills?.onLevelUp(); },
});

/* 角色的隨身裝備：HP/MP、戰鬥、技能、技能視窗（K）。
 * 里內沒有怪（結界擋著），所以不傳 mobs —— 招式照出，只是砍不到東西。
 * 技能是角色內建的，不該因為「這張圖沒有怪」就消失。 */
const kit = installLoadout({
  getSpec: () => spec, getCtrl: () => ctrl, scene, HUD, prog,
  isBlocked: () => escMenu.isOpen || sceneEditor.isOpen,
  onDeath: () => ctrl.teleport(0, GATE_Z + 9),
});
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

const nearPortal = () => Math.hypot(ctrl.pos.x, ctrl.pos.z - (GATE_Z - 6)) < 4.2;

window.addEventListener('keydown', (e) => {
  // ESC 在編輯器開著時是「關掉編輯器」（bindEscMenu 的 isBusy 已讓過）
  if (e.code === 'Escape' && sceneEditor.isOpen) { sceneEditor.close(); return; }
  // P：開關場景編輯器。放在鎖定判斷之前 —— 開啟時會解除滑鼠鎖定。
  if (e.code === 'KeyP') { sceneEditor.toggle(); e.preventDefault(); return; }
  if (sceneEditor.isOpen || escMenu.isOpen) return;
  if (e.code !== 'KeyE' || !ctrl.locked) return;
  if (nearPortal()) { HUD.showLoading('獸道 讀取中'); location.href = '../trail/?from=village'; }
});

/* ─────────────────────────────────────────────────── 主迴圈 ── */
const clock = new THREE.Clock();
let t = 0;

function tick(rawDt) {
  let dt = rawDt;
  if (kit.combat?.hitstop > 0) dt *= 0.12;
  t += dt;
  ctrl.update(dt, t);
  kit.update(dt, rawDt);
  crowd.update(dt, t, ctrl.pos);
  npcSystem.update(t, ctrl.pos, camera);
  env.update(dt, camera.position);
  trailPortal.userData.update(t);
  HUD.prompt(nearPortal() ? '[ E ]  前往獸道（往博麗神社・迷途竹林）' : null);
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
  get kit() { return kit; }, get combat() { return kit.combat; },
  get vitals() { return kit.vitals; }, get skills() { return kit.skills; }, prog,
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
