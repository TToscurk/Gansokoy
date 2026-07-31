// 獸道 —— 連接博麗神社與人間之里的山間獸徑。
//
// 依「單獨建造」的要求做成獨立頁面：自己的一套地形、燈光與界域，
// 只共用 src/ 底下的角色模型與 PlayerController。兩端各有一個界域：
//   北端（z 負向）＝ 博麗神社，按 E 回 index.html
//   南端（z 正向）＝ 人間之里的木門，尚未開放（先立牌告知）
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
import { Combat } from '../../src/combat/combat.js';
import { FairyMobs } from '../../src/combat/mobs.js';
import { SlashFX, SlashAudio } from '../../src/fx/slash.js';
import { combatHUD, bindCombatInput } from '../../src/combat/hud.js';
import { Progression, progressMobs } from '../../src/player/progression.js';
import { installHUD, bindEscMenu } from '../../src/ui/hud.js';
import { loadQualityIdx, saveQualityIdx, applyBasicQuality, QUALITY_NAMES } from '../../src/world/quality.js';
import { mergeStaticByMaterial } from '../../src/core/optimize.js';

/* 共用 HUD —— 與神社、人間之里完全同一套版面 */
const HUD = installHUD({
  title: '獸　道',
  subtitle: 'BEAST TRAIL · 博麗神社 ⇄ 人間之里',
  keys: [
    ['WASD / 方向鍵', '移動'], ['滑鼠', '轉視角'], ['滾輪', '縮放'],
    ['Shift', '衝刺'], ['Space', '跳躍'],
    ['E', '互動'], ['ESC', '選單'],
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
renderer.toneMappingExposure = 1.05;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();

// near 拉到 0.2（見 main.js 同名註解）：換來深度精度，鋪地物件不閃。
const camera = new THREE.PerspectiveCamera(66, innerWidth / innerHeight, 0.2, 400);
camera.rotation.order = 'YXZ';

/* ─────────────────────────────────── 晝夜 + 天氣（共用 Environment） ── */
// 長條地圖：太陽跟著玩家走（followSun），陰影相機不用蓋住整條 260m 的路。
// 密林的霧比神社濃（fogMul），其他一律用共用的日循環調色。
const env = new Environment(scene, renderer, {
  fogMul: 1.6,          // 比神社霧一點（密林），但別濃到吞掉北端的神社遠景
  shadowArea: 52,
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
// 一條南北向的谷道：路面在中央緩緩起伏，離開路面往兩側爬升成坡，
// 玩家自然會被地形「勸回」路上（沒有任何空氣牆）。
const TRAIL_LEN = 130;      // z ∈ [-130, 130]
const BOUND_X = 30;

function heightAt(x, z) {
  const roll = Math.sin(z * 0.045) * 0.9 + Math.sin(z * 0.013 + 1.7) * 1.4;   // 沿途起伏
  const ax = Math.abs(x);
  const slope = ax < 7 ? 0 : (ax - 7) * (ax - 7) * 0.05;                      // 兩側谷壁
  const wob = Math.sin(x * 0.7 + z * 0.33) * 0.12;                            // 土路的顛簸
  return roll + slope + wob;
}
setGroundHeightFn(heightAt);
// 這張圖沒有水域（見 main.js 同名註解）：谷道低點在 -2 以下，
// 不壓低水面高度的話 controller 會把玩家鉗在半空。
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
// 兩層：整片草坡（跟著高度場起伏的網格）＋ 中央一條土路
(function ground() {
  const W = 90, L = TRAIL_LEN * 2 + 60, SEG_X = 36, SEG_Z = 150;
  const makeStrip = (mat, halfW, yOff) => {
    const geo = new THREE.PlaneGeometry(halfW * 2, L, SEG_X, SEG_Z);
    geo.rotateX(-Math.PI / 2);
    const p = geo.attributes.position;
    for (let i = 0; i < p.count; i++) {
      p.setY(i, heightAt(p.getX(i), p.getZ(i)) + yOff);
    }
    geo.computeVertexNormals();
    const m = new THREE.Mesh(geo, mat);
    m.receiveShadow = true;
    world.add(m);
    return m;
  };
  makeStrip(MAT.grass, W / 2, 0);
  makeStrip(MAT.dirt, 3.1, 0.04);        // 獸徑：中央被踩實的土路
})();

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
for (let i = 0; i < 240; i++) {
  const z = -TRAIL_LEN - 15 + Math.random() * (TRAIL_LEN * 2 + 30);
  const side = Math.random() < 0.5 ? -1 : 1;
  const x = side * (5.5 + Math.random() * 26);
  if (Math.abs(z) > TRAIL_LEN - 8 && Math.abs(x) < 8) continue;   // 兩端門口留空
  tree(x, z, 0.8 + Math.random() * 1.1, leaves[Math.random() * leaves.length | 0]);
}

// 路邊的岩石與倒木
for (let i = 0; i < 26; i++) {
  const z = -TRAIL_LEN + Math.random() * TRAIL_LEN * 2;
  const x = (Math.random() < 0.5 ? -1 : 1) * (3.4 + Math.random() * 4);
  const r = 0.3 + Math.random() * 0.7;
  const rock = new THREE.Mesh(new THREE.IcosahedronGeometry(r, 0), MAT.stone);
  rock.position.set(x, heightAt(x, z) + r * 0.4, z);
  rock.rotation.set(Math.random() * 3, Math.random() * 3, 0);
  rock.castShadow = rock.receiveShadow = true;
  world.add(rock);
  if (r > 0.45) post(x, z, r * 0.85, heightAt(x, z) + r);   // 大一點的岩石才擋人
}
for (let i = 0; i < 7; i++) {
  const z = -TRAIL_LEN + 20 + Math.random() * (TRAIL_LEN * 2 - 40);
  const x = (Math.random() < 0.5 ? -1 : 1) * (4 + Math.random() * 3);
  const log = cyl(0.22, 0.28, 2.6 + Math.random() * 1.6, MAT.bark, x, heightAt(x, z) + 0.25, z, 7);
  log.rotation.z = Math.PI / 2;
  log.rotation.y = Math.random() * Math.PI;
  post(x, z, 0.5, heightAt(x, z) + 0.55);      // 倒木
}

// 彼岸花叢 —— 獸道的路標。紅點成叢，霧裡也看得見。
for (let i = 0; i < 30; i++) {
  const z = -TRAIL_LEN + Math.random() * TRAIL_LEN * 2;
  const x = (Math.random() < 0.5 ? -1 : 1) * (2.6 + Math.random() * 2.2);
  const y = heightAt(x, z);
  for (let k = 0; k < 4; k++) {
    const fx = x + (Math.random() - 0.5) * 0.9, fz = z + (Math.random() - 0.5) * 0.9;
    cyl(0.012, 0.012, 0.4, MAT.leafB, fx, y + 0.2, fz, 5);
    const bloom = new THREE.Mesh(new THREE.IcosahedronGeometry(0.075, 0), MAT.lily);
    bloom.position.set(fx, y + 0.44, fz);
    world.add(bloom);
  }
}

// 石道祖神（路旁的小石碑，獸徑常見的守路神）
for (const z of [-88, -30, 42, 96]) {
  const s = Math.random() < 0.5 ? -1 : 1;
  const x = s * 3.6;
  const y = heightAt(x, z);
  box(0.5, 1.0, 0.34, MAT.stone, x, y + 0.5, z);
  block(x, z, 0.7, 0.54, y + 1.1);             // 道祖神石碑
  box(0.66, 0.16, 0.5, MAT.stone, x, y + 1.06, z);
  box(0.7, 0.12, 0.54, MAT.stone, x, y + 0.05, z);
}

/* ─────────────────────────────────────────── 兩端的門與界域 ── */
const SHRINE_END = -TRAIL_LEN + 10;    // z = -120：神社端
const VILLAGE_END = TRAIL_LEN - 10;    // z = +120：人間之里端

// 神社端：發光提示點（回博麗神社）—— 依需求不做鳥居等裝飾
const shrinePortal = makePortalGlow(world, 0, heightAt(0, SHRINE_END), SHRINE_END);

/* ─────────────────── 北端遠景：山上的博麗神社全貌 ──────────────────
 * 站在獸道朝神社方向望，要看得到整座神社蓋在山頭上：
 * 山體 + 一條長石階爬上山面 + 台地上的紅鳥居、拜殿、玉垣剪影。
 * 純遠景裝飾（在邊界外，走不到），尺寸放大讓 70m 外也讀得清楚。 */
(function shrineVista() {
  const g = new THREE.Group();
  const VZ = SHRINE_END - 72;               // 約 z=-192，玩家最近可在 -130 處眺望
  g.position.set(0, -4, VZ);
  world.add(g);

  // 山體：平頂的截錐（台地跟山是一體的，不會像飛碟浮在山尖上）
  const green = new THREE.MeshStandardMaterial({ color: '#3d5030', roughness: 1, flatShading: true });
  const hill = new THREE.Mesh(new THREE.CylinderGeometry(24, 58, 50, 9), green);
  hill.position.set(0, 25, -40);
  hill.rotation.y = 0.35;
  g.add(hill);
  // 山腳緩坡
  const foot = new THREE.Mesh(new THREE.CylinderGeometry(52, 86, 16, 9), new THREE.MeshStandardMaterial({ color: '#44582f', roughness: 1, flatShading: true }));
  foot.position.set(4, 6, -42);
  g.add(foot);

  // 山面上的長石階（一條亮色斜帶，遠遠就看得出是那條下山參道）
  const run = 34, riseH = 50;               // 底部前緣 z≈-6，頂部邊緣 z≈-16 上方
  const stairs = new THREE.Mesh(new THREE.PlaneGeometry(4.5, Math.hypot(run, riseH)), new THREE.MeshStandardMaterial({ color: '#b9b4a4', roughness: 1 }));
  stairs.position.set(0, riseH / 2, -16 + run / 2);
  stairs.rotation.x = -Math.PI / 2 + Math.atan2(riseH, run);
  g.add(stairs);

  const red = new THREE.MeshStandardMaterial({ color: '#c8402e', roughness: 0.6 });
  const dark = new THREE.MeshStandardMaterial({ color: '#4a3a30', roughness: 0.9 });
  const roof = new THREE.MeshStandardMaterial({ color: '#cdd8d2', roughness: 0.8 });

  // 台地上的紅鳥居（石階頂端、山頂前緣）
  {
    const t = new THREE.Group();
    t.position.set(0, 50, -18);
    g.add(t);
    for (const s of [-1, 1]) {
      const p = new THREE.Mesh(new THREE.CylinderGeometry(0.55, 0.65, 9, 8), red);
      p.position.set(s * 4, 4.5, 0);
      t.add(p);
    }
    const beam = new THREE.Mesh(new THREE.BoxGeometry(11.6, 1.0, 1.0), red);
    beam.position.y = 9.2;
    t.add(beam);
    const beam2 = new THREE.Mesh(new THREE.BoxGeometry(9.4, 0.7, 0.8), red);
    beam2.position.y = 7.6;
    t.add(beam2);
  }

  // 拜殿剪影：屋身 + 兩片大屋頂 + 正脊（山頂中後方）
  {
    const s = new THREE.Group();
    s.position.set(0, 50, -40);
    g.add(s);
    const body = new THREE.Mesh(new THREE.BoxGeometry(20, 6.5, 13), dark);
    body.position.y = 3.25;
    s.add(body);
    for (const d of [-1, 1]) {
      const slope = new THREE.Mesh(new THREE.BoxGeometry(24, 0.7, 9.4), roof);
      slope.position.set(0, 9.4, d * 4);
      slope.rotation.x = d * 0.62;
      s.add(slope);
    }
    const ridge = new THREE.Mesh(new THREE.BoxGeometry(24.6, 1.2, 1.8), roof);
    ridge.position.y = 12;
    s.add(ridge);
  }

  // 玉垣（台地邊的一圈淺色矮欄）
  const fence = new THREE.Mesh(
    new THREE.CylinderGeometry(22, 22, 1.0, 12, 1, true),
    new THREE.MeshStandardMaterial({ color: '#d8d2c0', roughness: 1, side: THREE.DoubleSide })
  );
  fence.position.set(0, 50.7, -36);
  g.add(fence);

  g.traverse(o => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
})();

// 人間之里端：發光提示點（依需求不做拱門裝飾）
const villagePortal = makePortalGlow(world, 0, heightAt(0, VILLAGE_END), VILLAGE_END);

// 人間之里端的遠景：里的燈火與屋頂剪影（在邊界外，走不到）
(function villageVista() {
  const g = new THREE.Group();
  g.position.set(0, heightAt(0, VILLAGE_END) - 1, VILLAGE_END + 42);
  world.add(g);
  const wall = new THREE.MeshStandardMaterial({ color: '#c9bfa4', roughness: 1 });
  const tile = new THREE.MeshStandardMaterial({ color: '#4c5560', roughness: 1, flatShading: true });
  for (let i = 0; i < 9; i++) {
    const hx = (i - 4) * 11 + (Math.random() - 0.5) * 4;
    const hz = -Math.random() * 26;
    const w = 7 + Math.random() * 5, h = 4 + Math.random() * 2;
    const b = new THREE.Mesh(new THREE.BoxGeometry(w, h, 7), wall);
    b.position.set(hx, h / 2, hz);
    g.add(b);
    const r = new THREE.Mesh(new THREE.ConeGeometry(w * 0.82, 2.6, 4), tile);
    r.position.set(hx, h + 1.3, hz);
    r.rotation.y = Math.PI / 4;
    g.add(r);
  }
  g.traverse(o => { if (o.isMesh) o.castShadow = false; });
})();

/* ──────────────────────────────────────────── 靜態幾何合併 ── */
// 樹、石頭、彼岸花、兩端的遠景全部不會動 —— 依「材質 × 空間格子」合併。
// 獸道是一條 260 公尺的長廊，格子切小一點（40）讓身後的路段整塊被視錐裁掉。
// 兩個傳送光點會呼吸，已在 portal.js 標記 noMerge；玩家、妖精、光斑都在 scene。
{
  const s = mergeStaticByMaterial(world, { cell: 40 });
  console.info(`[optimize] 獸道靜態合併：${s.before} → ${s.after} 個網格（合併成 ${s.merged}，保留 ${s.kept}）`);
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
ctrl.bounds = { hx: BOUND_X, hz: TRAIL_LEN + 4 };
// 從哪一端走進來，就從那一端出生
if (new URLSearchParams(location.search).get('from') === 'village') {
  ctrl.teleport(0, VILLAGE_END - 5);
  ctrl.yaw = Math.PI;                  // 面向博麗神社（-z）
  ctrl.camYaw = 0;
} else {
  ctrl.teleport(0, SHRINE_END + 5);    // 從神社走進來，出生在光點內側
  ctrl.yaw = 0;                        // 面向人間之里（+z）
  ctrl.camYaw = Math.PI;
}

/* ───────────────────── 怪物區 + 成長系統 + 戰鬥 ── */
// 獸道中段是「有怪物的地區」：路旁四窩妖精。擊殺餵角色經驗、
// 命中餵技能練度（src/player/progression.js，localStorage 跨地圖保留）。
const prog = new Progression({ onLevelUp: (msg) => toast(msg) });
const NESTS = [
  { x: -9, z: -52, r: 12 },
  { x: 10, z: -8, r: 13 },
  { x: -10, z: 40, r: 12 },
  { x: 9, z: 82, r: 12 },
];
const fairies = new FairyMobs(scene, NESTS);
const mobs = progressMobs(fairies, prog, 'hinokami', '日之呼吸');

const slashFX = new SlashFX(scene);
const slashAudio = new SlashAudio();
const combat = spec.combat
  ? new Combat(ctrl, mobs, slashFX, slashAudio, combatHUD)
  : null;
prog.renderBadge(spec.combat ? 'hinokami' : null, '日之呼吸');
combatHUD.reset();
bindCombatInput(() => combat, () => ctrl, () => escMenu.isOpen);
// 戰鬥相關的操作提示只給有技能的角色看
{
  HUD.showCombatKeys(!!combat);
HUD.showFlyKeys(spec.canFly !== false);
}

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

const nearShrine = () => Math.hypot(ctrl.pos.x, ctrl.pos.z - SHRINE_END) < 4.2;
const nearVillage = () => Math.hypot(ctrl.pos.x, ctrl.pos.z - VILLAGE_END) < 4.2;

window.addEventListener('keydown', (e) => {
  if (e.code !== 'KeyE' || !ctrl.locked || escMenu.isOpen) return;
  if (nearShrine()) { HUD.showLoading('博麗神社 讀取中'); location.href = '../../index.html?from=trail'; return; }
  if (nearVillage()) { HUD.showLoading('人間之里 讀取中'); location.href = '../village/'; }
});

/* ─────────────────────────────────────────────────── 主迴圈 ── */
const clock = new THREE.Clock();
let t = 0;

/** 一幀的遊戲邏輯（animate 與除錯用的 __trail.step 共用） */
function tick(rawDt) {
  let dt = rawDt;
  if (combat?.hitstop > 0) dt *= 0.12;   // 重擊頓挫
  t += dt;
  ctrl.update(dt, t);

  // 戰鬥姿勢要在 ctrl.update（走路動畫）之後套才壓得過去
  combat?.update(dt, rawDt);
  slashFX.update(dt);
  fairies.update(dt, t, ctrl.pos);

  env.update(dt, camera.position);       // 晝夜推進 + 天氣 + 天空跟隨
  shrinePortal.userData.update(t);
  villagePortal.userData.update(t);
  motes.position.z = ctrl.pos.z * 0.2;

  if (nearShrine()) HUD.prompt('[ E ]  返回博麗神社');
  else if (nearVillage()) HUD.prompt('[ E ]  前往人間之里');
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
  renderer, scene, camera, ctrl, THREE, heightAt, env, get combat() { return combat; },
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
