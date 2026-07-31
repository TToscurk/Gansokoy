// 迷途竹林 —— 人間之里的南邊，通往永遠亭的路上。
//
// 設定考據（Touhou Wiki）：迷いの竹林是人間之里南方的一大片孟宗竹林，
// 竹子長得又高又密、地貌到處長一樣，走進去的人幾乎出不來 —— 名字就是
// 這麼來的。林中住著大量妖怪兔（因幡てゐ的手下），深處是永遠亭。
// 這張圖從獸道的東南分岔接進來，南端再接永遠亭（尚未開放）。
// 里跟竹林之間沒有直達的路 —— 要來這裡一定得走回獸道，
// 那條分岔才有存在感。
//
// 這張圖的技術重點是「竹子」：一千多根重複的竹竿如果各自一個 Mesh，
// 光是 draw call 就先死了。這裡全部走 InstancedMesh，而且依空間格子
// 切成多個 InstancedMesh —— 單一個 InstancedMesh 的包圍盒會涵蓋整張圖，
// 視錐裁剪永遠命中，切格子之後身後的竹林才會整塊被裁掉。
//
// 系統一律走共用模組：HUD、晝夜天氣（Environment）、傳送光點、戰鬥、
// 成長、靜態幾何合併。怪物是新的妖怪兔（src/combat/rabbits.js）——
// 這個專案第一種會主動追玩家的怪。

import * as THREE from 'three';
import * as BGU from 'three/addons/utils/BufferGeometryUtils.js';
import { setGroundHeightFn } from '../../src/world/terrain.js';
import { WORLD } from '../../src/config.js';
import { buildCharacter } from '../../src/entities/model.js';
import { ACTIVE_PLAYABLE, DEFAULT_PLAYER } from '../../src/entities/roster.js';
import { PlayerController } from '../../src/player/controller.js';
import { Environment } from '../../src/world/environment.js';
import { makePortalGlow } from '../../src/world/portal.js';
import { RabbitMobs } from '../../src/combat/rabbits.js';
import { Progression, progressMobs } from '../../src/player/progression.js';
import { installLoadout } from '../../src/player/loadout.js';
import { installHUD, bindEscMenu } from '../../src/ui/hud.js';
import { loadQualityIdx, saveQualityIdx, applyBasicQuality, QUALITY_NAMES } from '../../src/world/quality.js';
import { mergeStaticByMaterial } from '../../src/core/optimize.js';

/* 共用 HUD —— 與其他三張圖完全同一套版面 */
const HUD = installHUD({
  title: '迷途竹林',
  subtitle: 'BAMBOO FOREST OF THE LOST · 獸道 ⇄ 永遠亭',
  keys: [
    ['WASD / 方向鍵', '移動'], ['滑鼠', '轉視角'], ['滾輪', '縮放'],
    ['Shift', '衝刺'], ['Space', '跳躍'],
    ['E', '互動'], ['K', '技能'], ['ESC', '選單'],
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
renderer.toneMappingExposure = 1.06;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
// near 0.2：深度精度（見 main.js 同名註解）
const camera = new THREE.PerspectiveCamera(68, innerWidth / innerHeight, 0.2, 420);
camera.rotation.order = 'YXZ';

/* ─────────────────────────────── 晝夜 + 天氣（共用 Environment） ── */
// 竹林的霧是這張圖的主角：看不遠才會迷路。太陽跟著玩家走（長條地圖），
// 陰影相機不用蓋住整片林子。
const env = new Environment(scene, renderer, {
  fogMul: 2.1,
  shadowArea: 48,
  followSun: true,
});

let qualityIdx = loadQualityIdx(2);
const syncQuality = () => {
  applyBasicQuality(renderer, env.sun, qualityIdx);
  HUD.qualLabel.textContent = `畫質：${QUALITY_NAMES[qualityIdx]}`;
};
syncQuality();

/* ─────────────────────────────────────────────────── 地形高度場 ── */
// 竹林長在平地上：地面只有很緩的起伏，迷宮感靠竹子的密度而不是地形。
// 兩側超過邊界才抬升成坡，把玩家收在林子裡（沒有空氣牆）。
const LEN = 150;            // z ∈ [-150, 150]
const HALF_W = 62;          // x ∈ [-62, 62]
const NORTH_END = -138;     // 通往獸道（再往北才是人間之里與神社）
const SOUTH_END = 138;      // 通往永遠亭（尚未開放）

/** 蜿蜒的小徑中心線 —— 看不到盡頭才像迷路 */
function pathX(z) {
  return Math.sin(z * 0.019) * 17 + Math.sin(z * 0.041 + 1.2) * 6.5;
}
/** 離小徑中心線的距離 */
function pathDist(x, z) {
  return Math.abs(x - pathX(z));
}

function heightAt(x, z) {
  const roll = Math.sin(z * 0.028) * 0.55 + Math.sin(x * 0.035 + 1.1) * 0.45;
  const ax = Math.abs(x), az = Math.abs(z);
  // 兩側與南北兩端的圍坡。一定要封頂 —— 不封的話二次式在地面網格的
  // 邊緣（±95）會衝到一百公尺高，遠看就是兩道白色巨牆立在天邊。
  const rise = (d) => (d <= 0 ? 0 : Math.min(11, d * d * 0.055));
  const slope = Math.max(rise(ax - (HALF_W - 10)), rise(az - (LEN - 4)));
  const wob = Math.sin(x * 0.6 + z * 0.29) * 0.08;
  return roll + slope + wob;
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
const soilTex = canvasTex(256, (g, s) => {
  g.fillStyle = '#40402a'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 2400; i++) {
    g.fillStyle = `rgba(${52 + Math.random() * 46},${56 + Math.random() * 40},${34 + Math.random() * 26},.5)`;
    g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 1 + Math.random() * 5, 0, 7); g.fill();
  }
  // 落葉（竹葉是細長的）
  for (let i = 0; i < 260; i++) {
    g.strokeStyle = `rgba(${140 + Math.random() * 50},${132 + Math.random() * 44},${70 + Math.random() * 30},.42)`;
    g.lineWidth = 1 + Math.random();
    const x = Math.random() * s, y = Math.random() * s, a = Math.random() * 6.3;
    g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.cos(a) * 7, y + Math.sin(a) * 7); g.stroke();
  }
}, 16, 36);
const trailTex = canvasTex(256, (g, s) => {
  // 比落葉地面亮一截，否則走在路上看不出自己在路上
  g.fillStyle = '#79674a'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 1600; i++) {
    g.fillStyle = `rgba(${112 + Math.random() * 50},${96 + Math.random() * 42},${66 + Math.random() * 28},.5)`;
    g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 1 + Math.random() * 4, 0, 7); g.fill();
  }
}, 3, 40);

const MAT = {
  soil: new THREE.MeshStandardMaterial({ map: soilTex, roughness: 1 }),
  // 小徑鋪在地面上：polygonOffset 讓它在深度測試上穩定贏過土壤（見人間之里的同一套處理）
  trail: new THREE.MeshStandardMaterial({
    map: trailTex, roughness: 1,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
  }),
  culm: new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.72 }),   // 竹竿（顏色走頂點/instance）
  leaf: new THREE.MeshStandardMaterial({
    color: 0x5f7a34, roughness: 1, flatShading: true, side: THREE.DoubleSide,
  }),
  stone: new THREE.MeshStandardMaterial({ color: '#8d8b80', roughness: 1 }),
  mossStone: new THREE.MeshStandardMaterial({ color: '#77806a', roughness: 1 }),
  wood: new THREE.MeshStandardMaterial({ color: '#7a6144', roughness: 0.92 }),
  darkWood: new THREE.MeshStandardMaterial({ color: '#4e3d2c', roughness: 0.95 }),
  rotWood: new THREE.MeshStandardMaterial({ color: '#5d5344', roughness: 1 }),
  shoot: new THREE.MeshStandardMaterial({ color: '#9a7f4e', roughness: 1, flatShading: true }),   // 竹筍
  red: new THREE.MeshStandardMaterial({ color: '#b8442f', roughness: 0.6 }),
  thatch: new THREE.MeshStandardMaterial({ color: '#87754a', roughness: 1, flatShading: true }),
  tile: new THREE.MeshStandardMaterial({ color: '#4a5058', roughness: 0.85, flatShading: true }),
  paper: new THREE.MeshStandardMaterial({
    color: '#fff0cc', roughness: 0.9, emissive: '#8a5a18', emissiveIntensity: 0.3,
  }),
  cloth: new THREE.MeshStandardMaterial({ color: '#c9503c', roughness: 0.95, side: THREE.DoubleSide }),
};

const world = new THREE.Group();
scene.add(world);

/* 碰撞盒 —— 看得見的實體都要能擋人，尺寸貼合模型 */
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
function cyl(r1, r2, h, mat, x, y, z, seg = 8, parent = world) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(r1, r2, h, seg), mat);
  m.position.set(x, y, z);
  m.castShadow = m.receiveShadow = true;
  parent.add(m);
  return m;
}

/* ───────────────────────────────────────────────────────── 地面 ── */
(function ground() {
  const geo = new THREE.PlaneGeometry(190, 380, 76, 152);
  geo.rotateX(-Math.PI / 2);
  const p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) p.setY(i, heightAt(p.getX(i), p.getZ(i)));
  geo.computeVertexNormals();
  const m = new THREE.Mesh(geo, MAT.soil);
  m.receiveShadow = true;
  world.add(m);
})();

/* 蜿蜒的小徑。跟著中心線走，每一段都貼著地形抬 4 公分
 * （固定高度的平面會被地形吃掉 —— 人間之里踩過這個坑）。 */
(function trailPath() {
  const SEG = 150, W = 3.4;
  const geo = new THREE.BufferGeometry();
  const pos = [], uv = [], idx = [];
  for (let i = 0; i <= SEG; i++) {
    const z = -LEN - 20 + (i / SEG) * (LEN * 2 + 40);
    const cx = pathX(z);
    // 中心線的切線 → 左右偏移方向（否則轉彎處路寬會被壓縮）
    const dz = 0.5;
    const tx = pathX(z + dz) - pathX(z - dz), tz = dz * 2;
    const tl = Math.hypot(tx, tz);
    const nx = tz / tl, nz = -tx / tl;
    for (const s of [-1, 1]) {
      const x = cx + nx * W * s, zz = z + nz * W * s;
      pos.push(x, heightAt(x, zz) + 0.04, zz);
      uv.push(s > 0 ? 1 : 0, i / SEG * 22);
    }
    if (i < SEG) {
      // 繞向決定面朝上還是朝下。(a, a+1, a+2) 這個順序算出來的法線是 -Y，
      // 整條路會被背面剔除掉 —— 症狀是「路根本看不見」。要 (a, a+2, a+1)。
      const a = i * 2;
      idx.push(a, a + 2, a + 1, a + 1, a + 2, a + 3);
    }
  }
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  const m = new THREE.Mesh(geo, MAT.trail);
  m.receiveShadow = true;
  world.add(m);
})();

/* ─────────────────────────────────────────────────────── 竹林 ── */
// 空地：這些圓範圍內不長竹子（放建築、怪窩、休息點）
const CLEARINGS = [
  { x: pathX(NORTH_END), z: NORTH_END, r: 11 },   // 北口
  { x: pathX(-96) + 7, z: -96, r: 9 },            // 地藏
  { x: pathX(-40) - 9, z: -40, r: 11 },           // 廢屋
  { x: pathX(6), z: 6, r: 10 },                   // 竹橋前的空地
  { x: pathX(52) + 8, z: 52, r: 12 },             // 兔祠
  { x: pathX(104) - 7, z: 104, r: 10 },           // 古鳥居
  { x: pathX(SOUTH_END), z: SOUTH_END, r: 13 },   // 永遠亭門前
];
const inClearing = (x, z) => CLEARINGS.some(c => Math.hypot(x - c.x, z - c.z) < c.r);

/**
 * 竹子。一千多根重複物件 —— 全部走 InstancedMesh，而且依 CELL 公尺
 * 見方的格子各建一個，讓身後的竹林能整塊被視錐裁掉。
 *
 * 竹竿用單位高度的圓柱，靠 instance 矩陣縮放出不同高度；葉叢是三片
 * 交叉的面片合成一個幾何，一根竹子一個 instance。
 */
(function bamboo() {
  const CELL = 34;
  const cells = new Map();                        // key → 該格的竹子清單
  const cellKey = (x, z) => `${Math.floor(x / CELL)},${Math.floor(z / CELL)}`;

  // --- 決定每根竹子的位置 ---
  // 密度：離小徑越遠越密。小徑兩側 2.6 公尺內完全不長，否則走不動。
  let thickets = 0;
  for (let i = 0; i < 4200; i++) {
    const x = (Math.random() - 0.5) * HALF_W * 2;
    const z = (Math.random() - 0.5) * LEN * 2;
    const pd = pathDist(x, z);
    if (pd < 2.6) continue;
    if (inClearing(x, z)) continue;
    // 離路越遠越密（近處疏一點，看得到路）
    const density = Math.min(1, (pd - 2.6) / 14);
    if (Math.random() > density * 0.62) continue;

    const h = 7.5 + Math.random() * 5.5;
    const r = 0.075 + Math.random() * 0.045;
    const tilt = (Math.random() - 0.5) * 0.11;
    const key = cellKey(x, z);
    if (!cells.has(key)) cells.set(key, []);
    cells.get(key).push({ x, z, h, r, tilt, yaw: Math.random() * 6.28 });

    // 一部分是「叢」：三五根長在一起，這些才擋人 ——
    // 每一根都給碰撞盒的話，走在林子裡會像卡在牙籤堆裡。
    if (pd > 7 && Math.random() < 0.055) {
      thickets++;
      post(x, z, 1.0, heightAt(x, z) + 6);
      for (let k = 0; k < 3 + (Math.random() * 3 | 0); k++) {
        const a = Math.random() * 6.28, d = 0.25 + Math.random() * 0.7;
        const bx = x + Math.cos(a) * d, bz = z + Math.sin(a) * d;
        cells.get(cellKey(bx, bz)) ?? cells.set(cellKey(bx, bz), []);
        cells.get(cellKey(bx, bz)).push({
          x: bx, z: bz, h: 8 + Math.random() * 5, r: 0.08 + Math.random() * 0.04,
          tilt: (Math.random() - 0.5) * 0.16, yaw: Math.random() * 6.28,
        });
      }
    }
  }

  // --- 幾何 ---
  const culmGeo = new THREE.CylinderGeometry(0.8, 1, 1, 6, 1);   // 單位高度，上細下粗
  culmGeo.translate(0, 0.5, 0);                                  // 原點移到根部，方便擺放

  // 葉叢。竹葉是一叢細長、往外散又往下垂的小葉片 ——
  // 用幾片大方塊交叉會變成插在竿子上的綠旗子，一眼就假。
  // 這裡把十八片窄葉排成三層，整叢合成一個幾何，一根竹子一個 instance。
  const blades = [];
  const LAYERS = [
    { n: 7, up: 0.00, out: 0.30, len: 1.15, droop: 0.95 },
    { n: 6, up: 0.55, out: 0.24, len: 0.95, droop: 0.75 },
    { n: 5, up: 1.00, out: 0.16, len: 0.75, droop: 0.55 },
  ];
  for (const L of LAYERS) {
    for (let i = 0; i < L.n; i++) {
      const g = new THREE.PlaneGeometry(0.15, L.len);
      g.translate(0, L.len / 2, 0);       // 根部移到原點，才好繞根部轉
      g.rotateX(L.droop);                 // 往下垂
      g.translate(0, L.up, L.out);        // 抬高 + 往外推
      g.rotateY((i / L.n) * Math.PI * 2 + L.up * 2.1);   // 每層錯開，不會疊成一排
      blades.push(g);
    }
  }
  const leafGeo = BGU.mergeGeometries(blades, false);
  blades.forEach(g => { if (g !== leafGeo) g.dispose(); });

  const m4 = new THREE.Matrix4();
  const q = new THREE.Quaternion();
  const e = new THREE.Euler();
  const v = new THREE.Vector3();
  const s = new THREE.Vector3();
  const col = new THREE.Color();

  let total = 0, meshes = 0;
  for (const list of cells.values()) {
    if (!list.length) continue;
    total += list.length;
    meshes += 2;

    const culms = new THREE.InstancedMesh(culmGeo, MAT.culm, list.length);
    culms.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(list.length * 3), 3);
    culms.castShadow = true;
    const leaves = new THREE.InstancedMesh(leafGeo, MAT.leaf, list.length);
    leaves.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(list.length * 3), 3);

    list.forEach((b, i) => {
      const y = heightAt(b.x, b.z);
      e.set(b.tilt, b.yaw, b.tilt * 0.7);
      q.setFromEuler(e);

      s.set(b.r, b.h, b.r);
      m4.compose(v.set(b.x, y, b.z), q, s);
      culms.setMatrixAt(i, m4);

      // 竹竿的顏色：從青竹到轉黃的老竹
      const age = Math.random();
      col.setHSL(0.19 - age * 0.03, 0.34 + age * 0.12, 0.34 + age * 0.16);
      culms.setColorAt(i, col);

      // 葉叢掛在頂端（跟著竹竿的傾斜偏移）。高的竹子葉叢也大一點。
      const ls = 0.85 + b.h * 0.055;
      s.set(ls, ls, ls);
      m4.compose(
        v.set(b.x + Math.sin(b.tilt) * b.h, y + b.h * 0.86, b.z + Math.sin(b.tilt * 0.7) * b.h),
        q, s);
      leaves.setMatrixAt(i, m4);
      col.setHSL(0.24 - age * 0.035, 0.42 - age * 0.1, 0.26 + age * 0.12);
      leaves.setColorAt(i, col);
    });
    culms.instanceColor.needsUpdate = true;
    leaves.instanceColor.needsUpdate = true;
    world.add(culms, leaves);
  }
  console.info(`[bamboo] 竹子 ${total} 根，分 ${meshes} 個 InstancedMesh（${cells.size} 個格子），叢生擋人處 ${thickets}`);
})();

/* ────────────────────────────────────────────── 林中的建築 ── */

/** 地藏（路旁的小石像，迷路的人靠它認路） */
function jizo(x, z, rot = 0) {
  const g = new THREE.Group();
  g.position.set(x, heightAt(x, z), z);
  g.rotation.y = rot;
  world.add(g);
  cyl(0.34, 0.4, 0.22, MAT.stone, 0, 0.11, 0, 8, g);            // 台座
  cyl(0.2, 0.24, 0.72, MAT.mossStone, 0, 0.58, 0, 8, g);        // 身
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.19, 10, 8), MAT.mossStone);
  head.position.y = 1.06; head.castShadow = true; g.add(head);
  // 紅色的前掛（涎掛け）—— 地藏的招牌
  const bib = box(0.34, 0.3, 0.04, MAT.cloth, 0, 0.78, 0.2, g);
  bib.rotation.x = 0.12;
  post(x, z, 0.42, heightAt(x, z) + 1.25);
  return g;
}

/** 地藏堂：一排地藏 + 一個小木棚 */
(function jizoShelter() {
  const cx = pathX(-96) + 7, cz = -96;
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  world.add(g);
  // 木棚：四柱 + 茅草頂
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    cyl(0.09, 0.11, 2.1, MAT.darkWood, sx * 1.5, 1.05, sz * 0.85, 6, g);
    post(cx + sx * 1.5, cz + sz * 0.85, 0.16, y + 2.1);
  }
  for (const s of [-1, 1]) {
    const slope = box(3.6, 0.16, 1.5, MAT.thatch, 0, 2.42, s * 0.5, g);
    slope.rotation.x = s * 0.5;
  }
  box(3.7, 0.2, 0.24, MAT.thatch, 0, 2.72, 0, g);
  for (let i = -1; i <= 1; i++) jizo(cx + i * 1.0, cz - 0.1, Math.PI);
})();

/** 廢屋 —— 早年進林子採竹的人留下的，屋頂已經塌了一半 */
(function ruinedHut() {
  const cx = pathX(-40) - 9, cz = -40;
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  g.rotation.y = 0.4;
  world.add(g);

  const W = 5.4, D = 4.2, H = 2.5;
  box(W + 0.4, 0.3, D + 0.4, MAT.stone, 0, 0.15, 0, g);          // 石基
  // 三面牆（正面塌了）
  box(0.18, H, D, MAT.rotWood, -W / 2, H / 2 + 0.3, 0, g);
  box(0.18, H, D, MAT.rotWood, W / 2, H / 2 + 0.3, 0, g);
  box(W, H, 0.18, MAT.rotWood, 0, H / 2 + 0.3, -D / 2, g);
  // 正面只剩兩根柱子與門框上緣
  for (const s of [-1, 1]) cyl(0.11, 0.13, H, MAT.darkWood, s * (W / 2 - 0.2), H / 2 + 0.3, D / 2, 6, g);
  box(W - 0.3, 0.2, 0.16, MAT.darkWood, 0, H + 0.2, D / 2, g);
  // 塌掉一半的茅草屋頂：一邊還在，一邊垮下來斜插在地上
  const ok = box(W + 0.9, 0.26, D * 0.62, MAT.thatch, 0, H + 0.72, -D * 0.28, g);
  ok.rotation.x = -0.52;
  const fell = box(W * 0.8, 0.22, D * 0.7, MAT.thatch, 0.6, 0.85, D * 0.34, g);
  fell.rotation.set(0.95, 0.2, 0.1);
  // 倒在旁邊的木材
  for (let i = 0; i < 4; i++) {
    const b = cyl(0.1, 0.12, 2.6 + Math.random(), MAT.rotWood,
      -W / 2 - 1.2 - Math.random(), 0.12, -1 + i * 0.7, 6, g);
    b.rotation.set(Math.PI / 2, Math.random() * 0.6 - 0.3, 0);
  }
  // 碰撞：牆與柱（旋轉過的建物用外接框近似）
  const cs = Math.abs(Math.cos(0.4)), sn = Math.abs(Math.sin(0.4));
  block(cx, cz, W * cs + D * sn, W * sn + D * cs, y + H + 0.3);
})();

/** 竹橋 —— 跨過一條乾涸的小溪 */
(function bambooBridge() {
  const cz = 6, cx = pathX(cz);
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  world.add(g);
  // 橋面：並排的竹管
  for (let i = -4; i <= 4; i++) {
    const b = cyl(0.11, 0.11, 7.2, MAT.culm, i * 0.24, 0.42, 0, 6, g);
    b.rotation.x = Math.PI / 2;
    b.material = MAT.wood;
  }
  // 兩側扶手
  for (const s of [-1, 1]) {
    const rail = cyl(0.07, 0.07, 7.2, MAT.wood, s * 1.15, 1.0, 0, 6, g);
    rail.rotation.x = Math.PI / 2;
    for (let i = -1; i <= 1; i++) {
      cyl(0.08, 0.09, 0.62, MAT.wood, s * 1.15, 0.72, i * 2.6, 6, g);
    }
  }
  block(cx, cz, 2.6, 7.4, y + 0.5);
})();

/** 兔祠 —— 林中的小祠，妖怪兔在這附近特別多 */
(function rabbitShrine() {
  const cx = pathX(52) + 8, cz = 52;
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  g.rotation.y = -0.5;
  world.add(g);

  // 石台 + 小社殿
  box(2.6, 0.4, 2.2, MAT.stone, 0, 0.2, 0, g);
  box(1.7, 1.3, 1.4, MAT.wood, 0, 1.05, 0, g);
  box(0.7, 0.9, 0.08, MAT.darkWood, 0, 0.95, 0.72, g);          // 門
  for (const s of [-1, 1]) {
    const slope = box(2.5, 0.16, 1.15, MAT.tile, 0, 2.02, s * 0.42, g);
    slope.rotation.x = s * 0.55;
  }
  box(2.6, 0.2, 0.26, MAT.tile, 0, 2.28, 0, g);
  // 一對石兔（狛犬的位置換成兔子）
  for (const s of [-1, 1]) {
    const r = new THREE.Group();
    r.position.set(s * 1.7, 0.36, 1.5);
    r.rotation.y = -s * 0.4;
    g.add(r);
    cyl(0.24, 0.28, 0.16, MAT.stone, 0, 0.08, 0, 8, r);
    const body = new THREE.Mesh(new THREE.SphereGeometry(0.2, 10, 8), MAT.mossStone);
    body.scale.set(1, 0.9, 1.2); body.position.y = 0.3; body.castShadow = true; r.add(body);
    for (const es of [-1, 1]) {
      const ear = new THREE.Mesh(new THREE.CapsuleGeometry(0.04, 0.22, 3, 6), MAT.mossStone);
      ear.position.set(es * 0.07, 0.56, -0.02);
      ear.rotation.set(-0.25, 0, es * 0.2);
      ear.castShadow = true; r.add(ear);
    }
    post(cx + s * 1.7, cz + 1.5, 0.3, y + 0.9);
  }
  // 供在祠前的小燈籠
  const lamp = box(0.26, 0.32, 0.26, MAT.paper, 0, 0.62, 1.0, g);
  lamp.material = MAT.paper;
  block(cx, cz, 2.8, 2.4, y + 2.3);
})();

/** 古鳥居 —— 半個埋在竹林裡，紅漆剝落 */
(function oldTorii() {
  const cx = pathX(104) - 7, cz = 104;
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  g.rotation.y = 0.7;
  world.add(g);
  for (const s of [-1, 1]) {
    cyl(0.19, 0.24, 4.2, MAT.red, s * 1.75, 2.1, 0, 8, g);
    post(cx + s * 1.75 * Math.cos(0.7), cz - s * 1.75 * Math.sin(0.7), 0.28, y + 4.2);
  }
  const top = box(4.9, 0.3, 0.44, MAT.red, 0, 4.28, 0, g);
  top.rotation.z = 0.015;
  box(4.2, 0.22, 0.34, MAT.red, 0, 3.7, 0, g);
  box(0.3, 0.62, 0.3, MAT.red, 0, 3.95, 0, g);
})();

/** 永遠亭の門 —— 南端的終點，下一張圖的入口 */
(function eienteiGate() {
  const cz = SOUTH_END, cx = pathX(cz);
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  world.add(g);

  // 冠木門：兩根粗柱 + 橫樑 + 瓦頂
  for (const s of [-1, 1]) {
    cyl(0.32, 0.38, 5.0, MAT.darkWood, s * 3.4, 2.5, 0, 10, g);
    post(cx + s * 3.4, cz, 0.45, y + 5.0);
  }
  box(8.2, 0.5, 0.6, MAT.darkWood, 0, 4.7, 0, g);
  box(7.0, 0.34, 0.44, MAT.darkWood, 0, 3.9, 0, g);
  for (const s of [-1, 1]) {
    const slope = box(9.0, 0.22, 1.5, MAT.tile, 0, 5.32, s * 0.55, g);
    slope.rotation.x = s * 0.5;
  }
  box(9.2, 0.28, 0.34, MAT.tile, 0, 5.62, 0, g);
  // 門額（寫著永遠亭的木牌）
  box(1.9, 0.62, 0.12, MAT.wood, 0, 4.28, 0.34, g);

  // 門兩側往林子裡延伸的竹籬
  for (const s of [-1, 1]) {
    for (let i = 0; i < 7; i++) {
      const px = cx + s * (4.2 + i * 1.1), pz = cz + Math.sin(i * 0.7) * 0.5;
      cyl(0.07, 0.08, 1.7, MAT.wood, s * (4.2 + i * 1.1), 0.85, Math.sin(i * 0.7) * 0.5, 6, g);
      post(px, pz, 0.14, y + 1.7);
    }
    const rail = cyl(0.05, 0.05, 7.8, MAT.wood, s * 7.6, 1.5, 0, 6, g);
    rail.rotation.z = Math.PI / 2;
  }
  // 門前的一對石燈籠
  for (const s of [-1, 1]) {
    cyl(0.3, 0.36, 0.3, MAT.stone, s * 5.2, 0.15, -2.4, 8, g);
    cyl(0.17, 0.2, 1.1, MAT.stone, s * 5.2, 0.85, -2.4, 8, g);
    cyl(0.42, 0.3, 0.22, MAT.stone, s * 5.2, 1.5, -2.4, 8, g);
    const lit = box(0.3, 0.3, 0.3, MAT.paper, s * 5.2, 1.78, -2.4, g);
    lit.material = MAT.paper;
    cyl(0.08, 0.62, 0.36, MAT.stone, s * 5.2, 2.1, -2.4, 8, g);
    post(cx + s * 5.2, cz - 2.4, 0.4, y + 2.3);
  }
})();

/* 散落的石頭與竹筍（讓地面不會一片空） */
(function scatter() {
  for (let i = 0; i < 60; i++) {
    const z = (Math.random() - 0.5) * LEN * 2;
    const x = pathX(z) + (Math.random() - 0.5) * 40;
    if (pathDist(x, z) < 2.4 || Math.abs(x) > HALF_W) continue;
    const r = 0.2 + Math.random() * 0.5;
    const rock = new THREE.Mesh(new THREE.IcosahedronGeometry(r, 0), MAT.mossStone);
    rock.position.set(x, heightAt(x, z) + r * 0.4, z);
    rock.rotation.set(Math.random(), Math.random(), Math.random());
    rock.castShadow = rock.receiveShadow = true;
    world.add(rock);
  }
  // 竹筍
  for (let i = 0; i < 70; i++) {
    const z = (Math.random() - 0.5) * LEN * 2;
    const x = pathX(z) + (Math.random() - 0.5) * 34;
    if (pathDist(x, z) < 2.2 || Math.abs(x) > HALF_W) continue;
    const h = 0.35 + Math.random() * 0.5;
    const shoot = new THREE.Mesh(new THREE.ConeGeometry(0.13, h, 6), MAT.shoot);
    shoot.position.set(x, heightAt(x, z) + h / 2, z);
    shoot.rotation.y = Math.random() * 6.28;
    shoot.castShadow = true;
    world.add(shoot);
  }
})();

/* ───────────────────────────────────────────── 傳送點 ── */
const northPortal = makePortalGlow(world, pathX(NORTH_END), heightAt(pathX(NORTH_END), NORTH_END), NORTH_END, 0xd8f0a0);
const southPortal = makePortalGlow(world, pathX(SOUTH_END), heightAt(pathX(SOUTH_END), SOUTH_END) , SOUTH_END - 3, 0xc0a8ff);

/* ──────────────────────────────────────────── 靜態幾何合併 ── */
// 建築、地藏、石頭、竹筍全部不會動 —— 依「材質 × 空間格子」合併。
// 竹子是 InstancedMesh，合併會自動跳過（見 optimize.js 的 mergeable）。
{
  const s = mergeStaticByMaterial(world, { cell: 45 });
  console.info(`[optimize] 迷途竹林靜態合併：${s.before} → ${s.after} 個網格（合併成 ${s.merged}，保留 ${s.kept}）`);
}

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
ctrl.bounds = { hx: HALF_W + 4, hz: LEN + 6 };
// 從人間之里走進來 = 出生在北口
ctrl.teleport(pathX(NORTH_END + 6), NORTH_END + 6);
ctrl.yaw = 0;              // 面向南（往永遠亭）
ctrl.camYaw = Math.PI;

/* ───────────────────── 妖怪兔 + 成長系統 + 戰鬥 ── */
const prog = new Progression({
  onLevelUp: (msg) => { HUD.toast(msg); kit.skills?.onLevelUp(); },
});
// 越往南（越靠近永遠亭）窩越密 —— 走進去要有「越來越難回頭」的壓力。
// 全部走 InstancedMesh，九十幾隻同屏也只有兩個 draw call。
const NESTS = [
  { x: pathX(-70) + 10, z: -70, r: 6 },
  { x: pathX(-46) - 9, z: -46, r: 6 },
  { x: pathX(-18) - 11, z: -18, r: 7 },
  { x: pathX(12) + 10, z: 12, r: 7 },
  { x: pathX(30) + 9, z: 30, r: 8 },
  { x: pathX(52) + 8, z: 52, r: 9 },     // 兔祠附近最多
  { x: pathX(88) - 10, z: 88, r: 8 },
  { x: pathX(118) + 8, z: 118, r: 8 },
];
const rabbits = new RabbitMobs(scene, NESTS, 12, {
  damage: 7,
  onAttack: (dmg) => kit.vitals.damage(dmg),
});
const mobs = progressMobs(rabbits, prog, 'hinokami', '日之呼吸');

/* 角色的隨身裝備：HP/MP、戰鬥、技能、技能視窗（K）。
 * 這一整套是角色內建的，每張圖都掛同一份 —— 見 src/player/loadout.js。 */
const kit = installLoadout({
  getSpec: () => spec, getCtrl: () => ctrl, scene, HUD, prog, mobs,
  isBlocked: () => escMenu.isOpen,
  onDeath: () => {
    ctrl.teleport(pathX(NORTH_END + 6), NORTH_END + 6);
    HUD.toast('你在竹林裡倒下了 —— 有人把你拖回了林口。');
  },
});
prog.renderBadge(spec.combat ? 'hinokami' : null, '日之呼吸');

/* ───────────────────────────────────────────── 互動與提示 ── */
const toast = (msg, dur = 2600) => HUD.toast(msg, dur);

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
  onBackToSelect() {
    HUD.showLoading('博麗神社 讀取中');
    location.href = '../../index.html';
  },
});

const nearNorth = () => Math.hypot(ctrl.pos.x - pathX(NORTH_END), ctrl.pos.z - NORTH_END) < 4.6;
const nearSouth = () => Math.hypot(ctrl.pos.x - pathX(SOUTH_END), ctrl.pos.z - (SOUTH_END - 3)) < 4.6;

window.addEventListener('keydown', (e) => {
  if (e.code !== 'KeyE' || !ctrl.locked || escMenu.isOpen) return;
  if (nearNorth()) { HUD.showLoading('獸道 讀取中'); location.href = '../trail/?from=bamboo'; return; }
  if (nearSouth()) toast('永遠亭的門深鎖著 —— 這條路還沒開。');
});

/* ─────────────────────────────────────────────────── 主迴圈 ── */
const clock = new THREE.Clock();
let t = 0;

/** 一幀的遊戲邏輯（animate 與除錯用的 __bamboo.step 共用） */
function tick(rawDt) {
  let dt = rawDt;
  if (kit.combat?.hitstop > 0) dt *= 0.12;   // 重擊頓挫
  t += dt;
  ctrl.update(dt, t);

  kit.update(dt, rawDt);
  rabbits.update(dt, t, ctrl.pos);

  env.update(dt, camera.position);
  northPortal.userData.update(t);
  southPortal.userData.update(t);

  if (nearNorth()) HUD.prompt('[ E ]  返回獸道');
  else if (nearSouth()) HUD.prompt('[ E ]  永遠亭（尚未開放）');
  else HUD.prompt(null);
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

// debug handle（跟其他地圖同一套測試口徑）
window.__bamboo = {
  renderer, scene, camera, ctrl, THREE, heightAt, env, colliders, rabbits, prog,
  get vitals() { return kit.vitals; }, get skills() { return kit.skills; },
  get combat() { return kit.combat; }, get panel() { return kit.panel; },
  get kit() { return kit; },
  tp(x, z, yaw = 0) { ctrl.teleport(x, z); ctrl.yaw = yaw; },
  step(n = 1, dt = 0.016) {
    for (let i = 0; i < n; i++) tick(dt);
    return ctrl.pos.toArray().map(v => +v.toFixed(2));
  },
  frame() { renderer.render(scene, camera); },
  setHour(h) { return env.setHour(h); },
  setTimeFlowing(v) { env.timeFlowing = v; },
  pathX,
};
