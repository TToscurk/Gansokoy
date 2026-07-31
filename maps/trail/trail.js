// 獸道 —— 幻想鄉的路口。連接博麗神社、人間之里與迷途竹林。
//
// 這張圖是三張圖的樞紐：從神社下山之後，一路蜿蜒往南，中途分岔 ——
// 往西南是人間之里，往東南是迷途竹林。里本身不再直接通竹林，
// 要去竹林一定得走回獸道，這條路才有存在感。
//
//            博麗神社（北）
//                 │
//                 │  主道（蜿蜒）
//                 ▼
//      ┌───── 十字分岔 ─────┐
//      │        │           │
//  人間之里  迷途竹林   太陽花田
//  （西南）  （東南）   （東北 —— 環線的閉合臂）
//
// 蜿蜒 + 分岔之後，「離路多遠」不再有封閉解，而地形高度、路面幾何、
// 樹木佈點全都要問這個問題 —— 所以改用 src/world/pathnet.js 的路網。
//
// 場景刻意比神社簡單：沒有後製鏈、沒有任務、沒有 NPC 名冊 ——
// 它是一條「路」，重點是走起來的氣氛：密林、霧、光斑、獸徑的土路。
// 晝夜與天氣走共用的 Environment（跟神社同一套，時刻/天氣跨頁面延續），
// 戰鬥系統也接上共用的 combat/hud 綁定，有 combat 旗標的角色到這裡照樣能出招。

import * as THREE from 'three';
import { setGroundHeightFn } from '../../src/world/terrain.js';
import { WORLD } from '../../src/config.js';
import { buildCharacter } from '../../src/entities/model.js';
import { ACTIVE_PLAYABLE, DEFAULT_PLAYER } from '../../src/entities/roster.js';
import { PlayerController } from '../../src/player/controller.js';
import { Environment } from '../../src/world/environment.js';
import { makePortalGlow } from '../../src/world/portal.js';
import { FairyMobs } from '../../src/combat/mobs.js';
import { Progression, progressMobs } from '../../src/player/progression.js';
import { installLoadout } from '../../src/player/loadout.js';
import { installHUD, bindEscMenu } from '../../src/ui/hud.js';
import { loadQualityIdx, saveQualityIdx, applyBasicQuality, QUALITY_NAMES } from '../../src/world/quality.js';
import { mergeStaticByMaterial } from '../../src/core/optimize.js';
import { PathNet, catmullRom } from '../../src/world/pathnet.js';
import { GroundGrid, ribbonOnGrid } from '../../src/world/groundmesh.js';
import { scatterGrass } from '../../src/world/flora.js';

/* 共用 HUD —— 與神社、人間之里完全同一套版面 */
const HUD = installHUD({
  title: '獸　道',
  subtitle: 'BEAST TRAIL · 幻想鄉的十字路口',
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
renderer.toneMappingExposure = 1.05;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();

// near 拉到 0.2（見 main.js 同名註解）：換來深度精度，鋪地物件不閃。
const camera = new THREE.PerspectiveCamera(66, innerWidth / innerHeight, 0.2, 700);
camera.rotation.order = 'YXZ';

/* ─────────────────────────────────── 晝夜 + 天氣（共用 Environment） ── */
// 長條地圖：太陽跟著玩家走（followSun），陰影相機不用蓋住整條 260m 的路。
// 密林的霧比神社濃（fogMul），其他一律用共用的日循環調色。
const env = new Environment(scene, renderer, {
  fogMul: 1.6,          // 比神社霧一點（密林），但別濃到吞掉北端的神社遠景
  shadowArea: 60,
  followSun: true,
});

/* 畫質（跨地圖共用的三檔，localStorage）：這張圖沒有後製鏈，
 * 套解析度 + 陰影貼圖的 basic 檔。 */
let qualityIdx = loadQualityIdx(2);
const syncQuality = () => {
  applyBasicQuality(renderer, env.sun, qualityIdx);
  HUD.qualLabel.textContent = `畫質：${QUALITY_NAMES[qualityIdx]}`;
};
syncQuality();

/* ─────────────────────────────────────────────────── 地形高度場 ── */
// 一張 Y 字形的谷地：路面沿著中心線走，離開路面往兩側爬升成谷壁，
// 玩家自然會被地形「勸回」路上（沒有任何空氣牆）。
//
// 三個端點與分岔點的座標定在這裡，路面、傳送點、出生點、地形全部
// 從同一組數字長出來 —— 改路線只要動這幾個點。
const SHRINE_END = { x: 0, z: -300 };      // 北端：博麗神社
const FORK = { x: 26, z: 40 };             // 分岔點
const VILLAGE_END = { x: -150, z: 250 };   // 西南：人間之里
const BAMBOO_END = { x: 190, z: 250 };     // 東南：迷途竹林
const SUNFLOWER_END = { x: 246, z: -122 }; // 東北：太陽花田（環線閉合臂）

const ROAD_W = 7.5;        // 路面寬（也是地形不抬升的帶寬）
const MAP_R = 340;         // 地圖半徑（超過就是邊界山壁）

/** 三段路徑的控制點。中間刻意錯開，走起來才是蜿蜒而不是直線。 */
const SEGMENTS = [
  {
    id: 'main', width: ROAD_W,
    pts: [
      [SHRINE_END.x, SHRINE_END.z],
      [-22, -246], [18, -196], [-14, -142], [-30, -92],
      [4, -44], [30, -6], [FORK.x, FORK.z],
    ],
  },
  {
    id: 'toVillage', width: ROAD_W * 0.92,
    pts: [
      [FORK.x, FORK.z], [-2, 74], [-44, 108], [-88, 146],
      [-118, 190], [VILLAGE_END.x, VILLAGE_END.z],
    ],
  },
  {
    id: 'toBamboo', width: ROAD_W * 0.92,
    pts: [
      [FORK.x, FORK.z], [62, 78], [96, 112], [128, 152],
      [162, 198], [BAMBOO_END.x, BAMBOO_END.z],
    ],
  },
  {
    id: 'toSunflower', width: ROAD_W * 0.88,
    pts: [
      [FORK.x, FORK.z], [72, 22], [112, -6], [148, -42],
      [190, -78], [SUNFLOWER_END.x, SUNFLOWER_END.z],
    ],
  },
];
const PATHS = new PathNet(SEGMENTS, { step: 3, cell: 14 });

function heightAt(x, z) {
  const roll = Math.sin(z * 0.021) * 1.1 + Math.sin(x * 0.026 + 1.7) * 0.9;   // 沿途起伏
  const wob = Math.sin(x * 0.55 + z * 0.31) * 0.11;                           // 土路的顛簸

  // 谷壁 —— 不規則的山稜，不是把路「包起來」的均勻邊坡。
  // 兩組不同頻率的正弦把振幅與峰高都調變掉，天際線才會鋸齒起伏；
  // 冪次 2.35 讓山腳到十來公尺外就陡得爬不上去（配 controller 的
  // maxGrade 坡度阻擋）。上限一樣要封 —— 二次式不封頂在地圖邊緣
  // 會衝到幾百公尺（竹林踩過這個坑）。
  const n1 = Math.sin(x * 0.037 + z * 0.026);
  const n2 = Math.sin(x * 0.011 - z * 0.043 + 2.1);
  const amp = Math.max(0.5, 0.85 + 0.35 * n1 + 0.25 * n2);
  const cap = Math.max(14, 26 + 9 * n2 + 5 * n1);
  const d = PATHS.edgeDist(x, z, 2);
  const valley = d === Infinity ? cap : Math.min(cap, Math.pow(d * 0.17, 2.35) * amp);

  // 地圖邊界：再往外就是爬不上去的山
  const r = Math.hypot(x, z);
  const rim = r < MAP_R ? 0 : Math.min(40, (r - MAP_R) * (r - MAP_R) * 0.05);

  return roll + wob + valley + rim;
}
setGroundHeightFn(heightAt);
// 這張圖沒有水域（見 main.js 同名註解）
WORLD.waterLevel = -999;

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
const dirtTex = canvasTex(256, (g, s) => {
  g.fillStyle = '#5a4a34'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 1800; i++) {
    const v = Math.random();
    g.fillStyle = v > 0.7
      ? `rgba(${120 + Math.random() * 40},${100 + Math.random() * 30},${64 + Math.random() * 22},.5)`
      : `rgba(${64 + Math.random() * 40},${52 + Math.random() * 32},${34 + Math.random() * 22},.5)`;
    g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 1 + Math.random() * 5, 0, 7); g.fill();
  }
}, 4, 40);
const grassTex = canvasTex(256, (g, s) => {
  g.fillStyle = '#3a4a26'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 2200; i++) {
    g.fillStyle = `rgba(${40 + Math.random() * 50},${64 + Math.random() * 55},${26 + Math.random() * 30},.55)`;
    g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 1 + Math.random() * 6, 0, 7); g.fill();
  }
}, 12, 44);

const MAT = {
  // 獸徑鋪在草坡上（makeStrip 已讓它貼著高度場），polygonOffset 讓它
  // 在深度測試上穩定贏過草地，邊緣不會閃
  dirt: new THREE.MeshStandardMaterial({
    map: dirtTex, roughness: 1,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
  }),
  grass: new THREE.MeshStandardMaterial({ map: grassTex, roughness: 1 }),
  bark: new THREE.MeshStandardMaterial({ color: '#4a3828', roughness: 1 }),
  leafA: new THREE.MeshStandardMaterial({ color: '#3d5c2a', roughness: 1, flatShading: true }),
  leafB: new THREE.MeshStandardMaterial({ color: '#557436', roughness: 1, flatShading: true }),
  leafC: new THREE.MeshStandardMaterial({ color: '#8f6a2c', roughness: 1, flatShading: true }),
  stone: new THREE.MeshStandardMaterial({ color: '#8d8b80', roughness: 1 }),
  wood: new THREE.MeshStandardMaterial({ color: '#8a6a48', roughness: 0.9 }),
  darkWood: new THREE.MeshStandardMaterial({ color: '#5a4632', roughness: 0.95 }),
  red: new THREE.MeshStandardMaterial({ color: '#c8402e', roughness: 0.55 }),
  lily: new THREE.MeshStandardMaterial({ color: '#d8302a', roughness: 0.8, emissive: '#5a0e0a' }),
};

const world = new THREE.Group();
scene.add(world);

/* 場上實體物件的碰撞盒。每張地圖都照這個規則：樹幹、岩石、倒木、
 * 建物柱牆這些看得見的實體都要能擋人，尺寸貼合模型本身。 */
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
/* 地面網格 + 貼地查詢。路面（ribbonOnGrid）的每個頂點都會問 GRID
 * 「地面實際渲染的高度」——見 src/world/groundmesh.js 檔頭，
 * 這是路草交界不再閃爍的根治。 */
const GRID = new GroundGrid({ size: MAP_R * 2 + 120, seg: 210, heightAt });
const gSample = (x, z) => GRID.sample(x, z);
{
  const m = new THREE.Mesh(GRID.buildGeometry(), MAT.grass);
  m.receiveShadow = true;
  world.add(m);
}

for (const seg of SEGMENTS) {
  ribbonOnGrid(world, catmullRom(seg.pts, 2.5), seg.width / 2, MAT.dirt, gSample);
}

/* ───────────────────────────────────────────────────────── 樹林 ── */
function tree(x, z, s, leaf) {
  const y = heightAt(x, z);
  const g = new THREE.Group();
  g.position.set(x, y, z);
  g.rotation.y = Math.random() * Math.PI * 2;
  world.add(g);
  const h = (3.2 + Math.random() * 2.6) * s;
  cyl(0.16 * s, 0.24 * s, h, MAT.bark, 0, h / 2, 0, 7, g);
  post(x, z, 0.26 * s, y + h);                 // 樹幹擋人（貼合樹幹半徑）
  const layers = 2 + (Math.random() * 2 | 0);
  for (let i = 0; i < layers; i++) {
    const r = (1.5 - i * 0.36) * s * (0.85 + Math.random() * 0.4);
    const c = new THREE.Mesh(new THREE.IcosahedronGeometry(r, 0), leaf);
    c.position.set((Math.random() - 0.5) * 0.7 * s, h + i * 0.85 * s - 0.2, (Math.random() - 0.5) * 0.7 * s);
    c.castShadow = true;
    g.add(c);
  }
}
const leaves = [MAT.leafA, MAT.leafA, MAT.leafB, MAT.leafC];

/**
 * 沿著路網撒點：先隨機挑一個路上的取樣點，再往側邊推開 minD~maxD。
 *
 * 不能在整張圖亂撒再篩 —— 地圖半徑 340 公尺、路兩側只要 40 公尺的帶，
 * 亂撒的命中率不到一成，撒一千次只長得出稀稀落落幾棵樹。
 * @returns {[number,number,number]} [x, z, 離最近的路多遠]
 */
function pickNearPath(minD, maxD) {
  const sm = PATHS.samples[(Math.random() * PATHS.samples.length) | 0];
  const a = Math.random() * Math.PI * 2;
  const d = minD + Math.random() * (maxD - minD);
  const x = sm.x + Math.cos(a) * d, z = sm.z + Math.sin(a) * d;
  // 實際距離可能更近（附近有別的路段），所以要重新問一次
  return [x, z, PATHS.edgeDist(x, z, 3)];
}

// 樹：離路 3~64 公尺的帶狀範圍內，越遠越密（近處疏一點，看得到路）。
// 帶子拉寬到 64 讓山坡上也有樹 —— 邊坡光禿禿的就只是一道綠牆。
for (let i = 0; i < 3400; i++) {
  const [x, z, d] = pickNearPath(3, 64);
  if (d < 2.6) continue;
  if (Math.random() > Math.min(1, (d - 2.6) / 14) * 0.8) continue;
  tree(x, z, 0.8 + Math.random() * 1.1, leaves[Math.random() * leaves.length | 0]);
}

// 草叢與雜草：路肩到山腳的帶狀範圍，靠路密、遠處疏
scatterGrass(world, {
  count: 4200, heightAt,
  place: () => {
    const [x, z, d] = pickNearPath(0.8, 30);
    return d < 0.6 ? null : [x, z];
  },
  baseColor: 0x4e7030,
});

// 路邊的岩石
for (let i = 0; i < 150; i++) {
  const [x, z, d] = pickNearPath(0.5, 9);
  if (d < 0.5) continue;
  const r = 0.3 + Math.random() * 0.7;
  const rock = new THREE.Mesh(new THREE.IcosahedronGeometry(r, 0), MAT.stone);
  rock.position.set(x, heightAt(x, z) + r * 0.4, z);
  rock.rotation.set(Math.random() * 3, Math.random() * 3, 0);
  rock.castShadow = rock.receiveShadow = true;
  world.add(rock);
  if (r > 0.45) post(x, z, r * 0.85, heightAt(x, z) + r);   // 大一點的岩石才擋人
}

// 倒木
for (let i = 0; i < 34; i++) {
  const [x, z, d] = pickNearPath(1.5, 11);
  if (d < 1.2) continue;
  const log = cyl(0.22, 0.28, 2.6 + Math.random() * 1.6, MAT.bark, x, heightAt(x, z) + 0.25, z, 7);
  log.rotation.z = Math.PI / 2;
  log.rotation.y = Math.random() * Math.PI;
  post(x, z, 0.5, heightAt(x, z) + 0.55);
}

// 彼岸花叢 —— 獸道的路標。紅點成叢，霧裡也看得見。
for (let i = 0; i < 130; i++) {
  const [x, z, d] = pickNearPath(0.3, 4);
  if (d < 0.25) continue;
  const y = heightAt(x, z);
  for (let k = 0; k < 4; k++) {
    const fx = x + (Math.random() - 0.5) * 0.9, fz = z + (Math.random() - 0.5) * 0.9;
    cyl(0.012, 0.012, 0.4, MAT.leafB, fx, y + 0.2, fz, 5);
    const bloom = new THREE.Mesh(new THREE.IcosahedronGeometry(0.075, 0), MAT.lily);
    bloom.position.set(fx, y + 0.44, fz);
    world.add(bloom);
  }
}

/** 石道祖神 —— 路旁的小石碑，獸徑常見的守路神。也當作路口的地標。 */
function doso(x, z) {
  const y = heightAt(x, z);
  box(0.5, 1.0, 0.34, MAT.stone, x, y + 0.5, z);
  block(x, z, 0.7, 0.54, y + 1.1);
  box(0.66, 0.16, 0.5, MAT.stone, x, y + 1.06, z);
  box(0.7, 0.12, 0.54, MAT.stone, x, y + 0.05, z);
}
// 沿主道每隔一段立一尊，讓長路上有節奏
{
  const dense = catmullRom(SEGMENTS[0].pts, 3);
  for (let i = 14; i < dense.length - 6; i += 26) {
    const [cx, cz] = dense[i];
    const a = Math.random() < 0.5 ? -1 : 1;
    doso(cx + a * 5.6, cz + (Math.random() - 0.5) * 3);
  }
}

/* ───────────────────────────────── 分岔口的道標 ── */
// Y 字路口要一眼看得懂往哪走 —— 立一支木製指路標，兩塊箭頭板各指一方。
(function signpost() {
  const y = heightAt(FORK.x, FORK.z);
  const g = new THREE.Group();
  g.position.set(FORK.x, y, FORK.z);
  world.add(g);
  cyl(0.13, 0.16, 3.2, MAT.darkWood, 0, 1.6, 0, 8, g);
  post(FORK.x, FORK.z, 0.24, y + 3.2);
  // 兩塊指路板：朝向各自的支線
  const arm = (label, ang, h) => {
    void label;
    const b = box(1.9, 0.34, 0.09, MAT.wood, 0, h, 0, g);
    b.position.set(Math.sin(ang) * 0.85, h, Math.cos(ang) * 0.85);
    b.rotation.y = ang;
  };
  arm('village', Math.atan2(VILLAGE_END.x - FORK.x, VILLAGE_END.z - FORK.z), 2.55);
  arm('bamboo', Math.atan2(BAMBOO_END.x - FORK.x, BAMBOO_END.z - FORK.z), 2.05);
  // 頂上的小屋簷，讓它讀起來像個路標而不是一根棍子
  for (const sd of [-1, 1]) {
    const sl = box(0.9, 0.08, 0.5, MAT.stone, 0, 3.3, sd * 0.17, g);
    sl.rotation.x = sd * 0.5;
  }
  // 三尊道祖神圍著路口
  for (let i = 0; i < 3; i++) {
    const a = i * 2.1 + 0.6;
    doso(FORK.x + Math.cos(a) * 6.5, FORK.z + Math.sin(a) * 6.5);
  }
})();

/* ───────────────────────────────────── 三個端點的界域 ── */
// 三端各一個傳送光點，顏色分開才好認：神社青、里金、竹林綠。
const shrinePortal = makePortalGlow(world, SHRINE_END.x, heightAt(SHRINE_END.x, SHRINE_END.z), SHRINE_END.z, 0x8be8ff);
const villagePortal = makePortalGlow(world, VILLAGE_END.x, heightAt(VILLAGE_END.x, VILLAGE_END.z), VILLAGE_END.z, 0xf0d89a);
const bambooPortal = makePortalGlow(world, BAMBOO_END.x, heightAt(BAMBOO_END.x, BAMBOO_END.z), BAMBOO_END.z, 0xd8f0a0);
const sunflowerPortal = makePortalGlow(world, SUNFLOWER_END.x, heightAt(SUNFLOWER_END.x, SUNFLOWER_END.z), SUNFLOWER_END.z, 0xf2c832);

/* ─────────────────── 北端遠景：山上的博麗神社全貌 ──────────────────
 * 站在獸道朝神社方向望，要看得到整座神社蓋在山頭上：
 * 山體 + 一條長石階爬上山面 + 台地上的紅鳥居、拜殿、玉垣剪影。
 * 純遠景裝飾（在邊界外，走不到），尺寸放大讓遠處也讀得清楚。 */
(function shrineVista() {
  const g = new THREE.Group();
  g.position.set(SHRINE_END.x, heightAt(SHRINE_END.x, SHRINE_END.z) - 4, SHRINE_END.z - 78);
  world.add(g);

  const green = new THREE.MeshStandardMaterial({ color: '#3d5030', roughness: 1, flatShading: true });
  const hill = new THREE.Mesh(new THREE.CylinderGeometry(24, 58, 50, 9), green);
  hill.position.set(0, 25, -40);
  hill.rotation.y = 0.35;
  g.add(hill);
  const foot = new THREE.Mesh(new THREE.CylinderGeometry(52, 86, 16, 9),
    new THREE.MeshStandardMaterial({ color: '#44582f', roughness: 1, flatShading: true }));
  foot.position.set(4, 6, -42);
  g.add(foot);

  // 山面上的長石階（一條亮色斜帶，遠遠就看得出是那條下山參道）
  const run = 34, riseH = 50;
  const stairs = new THREE.Mesh(new THREE.PlaneGeometry(4.5, Math.hypot(run, riseH)),
    new THREE.MeshStandardMaterial({ color: '#b9b4a4', roughness: 1 }));
  stairs.position.set(0, riseH / 2, -16 + run / 2);
  stairs.rotation.x = -Math.PI / 2 + Math.atan2(riseH, run);
  g.add(stairs);

  const red = new THREE.MeshStandardMaterial({ color: '#c8402e', roughness: 0.6 });
  const dark = new THREE.MeshStandardMaterial({ color: '#4a3a30', roughness: 0.9 });
  const roof = new THREE.MeshStandardMaterial({ color: '#cdd8d2', roughness: 0.8 });

  {   // 台地上的紅鳥居
    const t = new THREE.Group();
    t.position.set(0, 50, -18);
    g.add(t);
    for (const sd of [-1, 1]) {
      const q = new THREE.Mesh(new THREE.CylinderGeometry(0.55, 0.65, 9, 8), red);
      q.position.set(sd * 4, 4.5, 0);
      t.add(q);
    }
    const beam = new THREE.Mesh(new THREE.BoxGeometry(11.6, 1.0, 1.0), red);
    beam.position.y = 9.2; t.add(beam);
    const beam2 = new THREE.Mesh(new THREE.BoxGeometry(9.4, 0.7, 0.8), red);
    beam2.position.y = 7.6; t.add(beam2);
  }
  {   // 拜殿剪影
    const q = new THREE.Group();
    q.position.set(0, 50, -40);
    g.add(q);
    const body = new THREE.Mesh(new THREE.BoxGeometry(20, 6.5, 13), dark);
    body.position.y = 3.25; q.add(body);
    for (const d of [-1, 1]) {
      const slope = new THREE.Mesh(new THREE.BoxGeometry(24, 0.7, 9.4), roof);
      slope.position.set(0, 9.4, d * 4);
      slope.rotation.x = d * 0.62;
      q.add(slope);
    }
    const ridge = new THREE.Mesh(new THREE.BoxGeometry(24.6, 1.2, 1.8), roof);
    ridge.position.y = 12; q.add(ridge);
  }
  const fence = new THREE.Mesh(new THREE.CylinderGeometry(22, 22, 1.0, 12, 1, true),
    new THREE.MeshStandardMaterial({ color: '#d8d2c0', roughness: 1, side: THREE.DoubleSide }));
  fence.position.set(0, 50.7, -36);
  g.add(fence);
  g.traverse(o => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
})();

/* 西南端的遠景：人間之里的屋頂剪影（在邊界外，走不到） */
(function villageVista() {
  const g = new THREE.Group();
  g.position.set(VILLAGE_END.x - 16, heightAt(VILLAGE_END.x, VILLAGE_END.z) - 1, VILLAGE_END.z + 40);
  g.rotation.y = 0.5;
  world.add(g);
  const wall = new THREE.MeshStandardMaterial({ color: '#c9bfa4', roughness: 1 });
  const tile = new THREE.MeshStandardMaterial({ color: '#4c5560', roughness: 1, flatShading: true });
  for (let i = 0; i < 11; i++) {
    const hx = (i - 5) * 11 + (Math.random() - 0.5) * 4;
    const hz = -Math.random() * 26;
    const w = 7 + Math.random() * 5, h = 4 + Math.random() * 2;
    const b = new THREE.Mesh(new THREE.BoxGeometry(w, h, 7), wall);
    b.position.set(hx, h / 2, hz); g.add(b);
    const r = new THREE.Mesh(new THREE.ConeGeometry(w * 0.82, 2.6, 4), tile);
    r.position.set(hx, h + 1.3, hz); r.rotation.y = Math.PI / 4; g.add(r);
  }
  g.traverse(o => { if (o.isMesh) o.castShadow = false; });
})();

/* 東南端的遠景：竹林的邊界 —— 一整片比樹高得多的竹梢 */
(function bambooVista() {
  const g = new THREE.Group();
  g.position.set(BAMBOO_END.x + 10, heightAt(BAMBOO_END.x, BAMBOO_END.z), BAMBOO_END.z + 34);
  world.add(g);
  const culm = new THREE.MeshStandardMaterial({ color: '#8a9a4e', roughness: 0.8 });
  const leaf = new THREE.MeshStandardMaterial({ color: '#54702e', roughness: 1, flatShading: true });
  for (let i = 0; i < 90; i++) {
    const x = (Math.random() - 0.5) * 120, z = -Math.random() * 46;
    const h = 9 + Math.random() * 6;
    const c = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.14, h, 5), culm);
    c.position.set(x, h / 2, z); g.add(c);
    const tuft = new THREE.Mesh(new THREE.IcosahedronGeometry(1.1 + Math.random() * 0.5, 0), leaf);
    tuft.position.set(x, h * 0.94, z); g.add(tuft);
  }
  g.traverse(o => { if (o.isMesh) o.castShadow = false; });
})();

/* 東北端的遠景：太陽花田 —— 一整片向日葵與幽香的陽傘（在邊界外，走不到） */
(function sunflowerVista() {
  const g = new THREE.Group();
  g.position.set(SUNFLOWER_END.x + 14, heightAt(SUNFLOWER_END.x, SUNFLOWER_END.z), SUNFLOWER_END.z - 30);
  g.rotation.y = -0.4;
  world.add(g);
  const stemM = new THREE.MeshStandardMaterial({ color: '#4e7030', roughness: 1 });
  const petalM = new THREE.MeshStandardMaterial({ color: '#f2c832', roughness: 0.85, side: THREE.DoubleSide });
  const coreM = new THREE.MeshStandardMaterial({ color: '#6a4a22', roughness: 1 });
  // 向日葵全部走 InstancedMesh：莖、花盤、花心各一個
  const N = 240;
  const stems = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.05, 0.07, 1, 5), stemM, N);
  const heads = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.42, 0.42, 0.06, 10), petalM, N);
  const cores = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.2, 0.2, 0.08, 8), coreM, N);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler();
  const v = new THREE.Vector3(), sc = new THREE.Vector3();
  for (let i = 0; i < N; i++) {
    const x = (Math.random() - 0.5) * 110, z = -Math.random() * 60;
    const h = 1.5 + Math.random() * 0.8;
    q.identity(); sc.set(1, h, 1);
    m4.compose(v.set(x, h / 2, z), q, sc);
    stems.setMatrixAt(i, m4);
    // 花盤朝南面向獸道（向日葵向陽，也剛好向著玩家）
    e.set(Math.PI / 2 - 0.4, 0, 0); q.setFromEuler(e); sc.set(1, 1, 1);
    m4.compose(v.set(x, h, z + 0.1), q, sc);
    heads.setMatrixAt(i, m4);
    m4.compose(v.set(x, h, z + 0.14), q, sc);
    cores.setMatrixAt(i, m4);
  }
  for (const im of [stems, heads, cores]) { im.castShadow = false; im.frustumCulled = true; g.add(im); }
  // 幽香的陽傘地標 —— 花海深處一把粉紫大傘
  const umb = new THREE.Group();
  umb.position.set(8, 0, -40);
  g.add(umb);
  const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.1, 3.4, 6),
    new THREE.MeshStandardMaterial({ color: '#5a4a3a', roughness: 0.9 }));
  pole.position.y = 1.7; umb.add(pole);
  const canopy = new THREE.Mesh(new THREE.ConeGeometry(2.6, 1.1, 10),
    new THREE.MeshStandardMaterial({ color: '#d8a8c8', roughness: 0.8 }));
  canopy.position.y = 3.5; umb.add(canopy);
})();

/* ──────────────────────────────────────────── 靜態幾何合併 ── */
// 樹、石頭、彼岸花、道祖神、三端的遠景全部不會動 ——
// 依「材質 × 空間格子」合併。地圖是 Y 字形的一大片，格子切 55 公尺，
// 讓身後與另一條支線整塊被視錐裁掉。
{
  const st = mergeStaticByMaterial(world, { cell: 55 });
  console.info(`[optimize] 獸道靜態合併：${st.before} → ${st.after} 個網格（合併成 ${st.merged}，保留 ${st.kept}）`);
}

/* ─────────────────────────────────────────────── 光斑與飛螢 ── */
const motes = (() => {
  const N = 260;
  const geo = new THREE.BufferGeometry();
  const arr = new Float32Array(N * 3);
  for (let i = 0; i < N; i++) {
    arr[i * 3] = (Math.random() - 0.5) * 40;
    arr[i * 3 + 1] = 0.4 + Math.random() * 7;
    arr[i * 3 + 2] = (Math.random() - 0.5) * 240;
  }
  geo.setAttribute('position', new THREE.BufferAttribute(arr, 3));
  const pts = new THREE.Points(geo, new THREE.PointsMaterial({
    color: '#d8ffa0', size: 0.06, transparent: true, opacity: 0.65,
    depthWrite: false, blending: THREE.AdditiveBlending, sizeAttenuation: true,
  }));
  scene.add(pts);
  return pts;
})();

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
ctrl.bounds = { hx: MAP_R + 30, hz: MAP_R + 30 };
ctrl.maxGrade = 1.05;   // 邊坡是山，爬不上去（見 controller 的坡度阻擋）
// 從哪一端走進來，就從那一端出生
const from = new URLSearchParams(location.search).get('from');
{
  const spawn = from === 'village' ? VILLAGE_END
    : from === 'bamboo' ? BAMBOO_END
    : SHRINE_END;
  // 往路口方向退幾步，才不會一出生就站在光點上又被傳回去
  const inward = from === 'shrine' || !from ? FORK : FORK;
  const dx = inward.x - spawn.x, dz = inward.z - spawn.z;
  const dl = Math.hypot(dx, dz) || 1;
  ctrl.teleport(spawn.x + dx / dl * 7, spawn.z + dz / dl * 7);
  ctrl.yaw = Math.atan2(dx, dz);
  ctrl.camYaw = ctrl.yaw + Math.PI;
}

/* ───────────────────── 怪物區 + 成長系統 + 戰鬥 ── */
// 獸道中段是「有怪物的地區」：路旁四窩妖精。擊殺餵角色經驗、
// 命中餵技能練度（src/player/progression.js，localStorage 跨地圖保留）。
const prog = new Progression({
  onLevelUp: (msg) => { HUD.toast(msg); kit.skills?.onLevelUp(); },
});
// 妖精窩沿著三段路散布 —— 路變長了，窩也要跟著鋪開，
// 不然走幾百公尺只會遇到四窩。
const NESTS = (() => {
  const out = [];
  SEGMENTS.forEach((seg, si) => {
    const dense = catmullRom(seg.pts, 3);
    const n = si === 0 ? 6 : 3;
    for (let i = 1; i <= n; i++) {
      const [cx, cz] = dense[Math.floor(dense.length * i / (n + 1))];
      const a = Math.random() * Math.PI * 2;
      out.push({ x: cx + Math.cos(a) * 13, z: cz + Math.sin(a) * 13, r: 11 });
    }
  });
  return out;
})();
const fairies = new FairyMobs(scene, NESTS);
const mobs = progressMobs(fairies, prog, 'hinokami', '日之呼吸');

/* 角色的隨身裝備：HP/MP、戰鬥、技能、技能視窗（K）。
 * 每張圖都掛同一份 —— 見 src/player/loadout.js。
 * 妖精是無害的，所以這張圖不接 onAttack，血量只會自己回。 */
const kit = installLoadout({
  getSpec: () => spec, getCtrl: () => ctrl, scene, HUD, prog, mobs,
  isBlocked: () => escMenu.isOpen,
  onDeath: () => ctrl.teleport(SHRINE_END.x, SHRINE_END.z + 8),
});
prog.renderBadge(spec.combat ? 'hinokami' : null, '日之呼吸');

/* ───────────────────────────────────────────────── 互動與提示 ── */
const toast = (msg, dur = 2600) => HUD.toast(msg, dur);

/* ESC 選單（與其他地圖同一套）。回選角畫面＝回神社的選人流程。 */
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

const near = (p) => Math.hypot(ctrl.pos.x - p.x, ctrl.pos.z - p.z) < 4.6;
const nearShrine = () => near(SHRINE_END);
const nearVillage = () => near(VILLAGE_END);
const nearBamboo = () => near(BAMBOO_END);
const nearSunflower = () => near(SUNFLOWER_END);

window.addEventListener('keydown', (e) => {
  if (e.code !== 'KeyE' || !ctrl.locked || escMenu.isOpen) return;
  if (nearShrine()) { HUD.showLoading('博麗神社 讀取中'); location.href = '../../index.html?from=trail'; return; }
  if (nearVillage()) { HUD.showLoading('人間之里 讀取中'); location.href = '../village/'; return; }
  if (nearBamboo()) { HUD.showLoading('迷途竹林 讀取中'); location.href = '../bamboo/?from=trail'; return; }
  if (nearSunflower()) toast('花田的方向瀰漫著花香 —— 這條路還沒開。');
});

/* ─────────────────────────────────────────────────── 主迴圈 ── */
const clock = new THREE.Clock();
let t = 0;

/** 一幀的遊戲邏輯（animate 與除錯用的 __trail.step 共用） */
function tick(rawDt) {
  let dt = rawDt;
  if (kit.combat?.hitstop > 0) dt *= 0.12;   // 重擊頓挫
  t += dt;
  ctrl.update(dt, t);

  // 戰鬥姿勢要在 ctrl.update（走路動畫）之後套才壓得過去
  kit.update(dt, rawDt);
  fairies.update(dt, t, ctrl.pos);

  env.update(dt, camera.position);       // 晝夜推進 + 天氣 + 天空跟隨
  shrinePortal.userData.update(t);
  villagePortal.userData.update(t);
  bambooPortal.userData.update(t);
  sunflowerPortal.userData.update(t);
  motes.position.z = ctrl.pos.z * 0.2;

  if (nearShrine()) HUD.prompt('[ E ]  前往博麗神社');
  else if (nearVillage()) HUD.prompt('[ E ]  前往人間之里');
  else if (nearBamboo()) HUD.prompt('[ E ]  前往迷途竹林');
  else if (nearSunflower()) HUD.prompt('[ E ]  太陽花田（尚未開放）');
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

// debug handle（跟 index 的 __shrine 同一套測試口徑）
window.__trail = {
  renderer, scene, camera, ctrl, THREE, heightAt, env, prog, fairies, PATHS,
  SHRINE_END, VILLAGE_END, BAMBOO_END, SUNFLOWER_END, FORK,
  get kit() { return kit; }, get combat() { return kit.combat; },
  get vitals() { return kit.vitals; }, get skills() { return kit.skills; },
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
