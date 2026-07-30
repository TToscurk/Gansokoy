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
import { setGroundHeightFn } from './src/world/terrain.js';
import { buildCharacter } from './src/entities/model.js';
import { PLAYABLE } from './src/entities/roster.js';
import { PlayerController } from './src/player/controller.js';
import { Environment } from './src/world/environment.js';
import { makePortalGlow } from './src/world/portal.js';
import { Combat } from './src/combat/combat.js';
import { SlashFX, SlashAudio } from './src/fx/slash.js';
import { combatHUD, bindCombatInput } from './src/combat/hud.js';

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

const camera = new THREE.PerspectiveCamera(66, innerWidth / innerHeight, 0.1, 400);
camera.rotation.order = 'YXZ';

/* ─────────────────────────────────── 晝夜 + 天氣（共用 Environment） ── */
// 長條地圖：太陽跟著玩家走（followSun），陰影相機不用蓋住整條 260m 的路。
// 密林的霧比神社濃（fogMul），其他一律用共用的日循環調色。
const env = new Environment(scene, renderer, {
  fogMul: 2.4,
  shadowArea: 52,
  followSun: true,
});

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
  dirt: new THREE.MeshStandardMaterial({ map: dirtTex, roughness: 1 }),
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
}
for (let i = 0; i < 7; i++) {
  const z = -TRAIL_LEN + 20 + Math.random() * (TRAIL_LEN * 2 - 40);
  const x = (Math.random() < 0.5 ? -1 : 1) * (4 + Math.random() * 3);
  const log = cyl(0.22, 0.28, 2.6 + Math.random() * 1.6, MAT.bark, x, heightAt(x, z) + 0.25, z, 7);
  log.rotation.z = Math.PI / 2;
  log.rotation.y = Math.random() * Math.PI;
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
  box(0.66, 0.16, 0.5, MAT.stone, x, y + 1.06, z);
  box(0.7, 0.12, 0.54, MAT.stone, x, y + 0.05, z);
}

/* ─────────────────────────────────────────── 兩端的門與界域 ── */
const SHRINE_END = -TRAIL_LEN + 10;    // z = -120：神社端
const VILLAGE_END = TRAIL_LEN - 10;    // z = +120：人間之里端

// 神社端：發光提示點（回博麗神社）—— 依需求不做鳥居等裝飾
const shrinePortal = makePortalGlow(world, 0, heightAt(0, SHRINE_END), SHRINE_END);

// 人間之里端：素木冠木門（尚未開放）
(function villageGate() {
  const y = heightAt(0, VILLAGE_END);
  const g = new THREE.Group();
  g.position.set(0, y, VILLAGE_END);
  world.add(g);
  for (const s of [-1, 1]) cyl(0.3, 0.34, 4.4, MAT.darkWood, s * 3.0, 2.2, 0, 10, g);
  box(7.6, 0.44, 0.5, MAT.darkWood, 0, 4.35, 0, g);
  box(6.6, 0.3, 0.36, MAT.wood, 0, 3.7, 0, g);
  // 門後的木柵欄（示意里門未開）
  for (let i = -2; i <= 2; i++) box(0.16, 2.2, 0.16, MAT.wood, i * 1.2, 1.1, 0.4, g);
  box(6.2, 0.18, 0.14, MAT.wood, 0, 1.7, 0.4, g);
  box(6.2, 0.18, 0.14, MAT.wood, 0, 0.7, 0.4, g);
})();

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
const spec = PLAYABLE.find(p => p.id === saved) ?? PLAYABLE[0];

const model = buildCharacter(spec);
scene.add(model);
const ctrl = new PlayerController(model, camera, renderer.domElement, []);
ctrl.canFly = spec.canFly ?? true;
ctrl.maxAirJumps = spec.airJumps ?? 0;
ctrl.jumpV = spec.jump ?? 9.2;
ctrl.airJumpV = spec.airJump ?? 8.4;
ctrl.sprintMul = spec.sprintMul ?? 1.85;
ctrl.speedMul = spec.speed ?? 1.0;
ctrl.bounds = { hx: BOUND_X, hz: TRAIL_LEN + 4 };
ctrl.teleport(0, SHRINE_END + 5);      // 從神社走進來，出生在光點內側
ctrl.yaw = 0;                          // 面向人間之里（+z）
ctrl.camYaw = Math.PI;

/* ─────────────────────────────── 戰鬥（有 combat 旗標的角色） ── */
const slashFX = new SlashFX(scene);
const slashAudio = new SlashAudio();
const NO_MOBS = { inSector: () => [], damage: () => false, aliveNear: () => false, update() {} };
const combat = spec.combat
  ? new Combat(ctrl, NO_MOBS, slashFX, slashAudio, combatHUD)
  : null;
combatHUD.reset();
bindCombatInput(() => combat, () => ctrl);

/* ───────────────────────────────────────────────── 互動與提示 ── */
const promptEl = document.getElementById('prompt');
const toastEl = document.getElementById('toast');
let toastTimer;
function toast(msg, dur = 2600) {
  toastEl.textContent = msg;
  toastEl.classList.add('on');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toastEl.classList.remove('on'), dur);
}

const nearShrine = () => Math.hypot(ctrl.pos.x, ctrl.pos.z - SHRINE_END) < 4.2;
const nearVillage = () => Math.hypot(ctrl.pos.x, ctrl.pos.z - VILLAGE_END) < 4.2;

window.addEventListener('keydown', (e) => {
  if (e.code !== 'KeyE' || !ctrl.locked) return;
  if (nearShrine()) { location.href = 'index.html?from=trail'; return; }
  if (nearVillage()) toast('人間之里的里門還沒開 —— 這一段路之後再修。');
});

/* ─────────────────────────────────────────────────── 主迴圈 ── */
const clock = new THREE.Clock();
let t = 0;
function animate() {
  const rawDt = Math.min(clock.getDelta(), 0.05);
  let dt = rawDt;
  if (combat?.hitstop > 0) dt *= 0.12;   // 重擊頓挫
  t += dt;
  ctrl.update(dt, t);

  // 戰鬥姿勢要在 ctrl.update（走路動畫）之後套才壓得過去
  combat?.update(dt, rawDt);
  slashFX.update(dt);

  env.update(dt, camera.position);       // 晝夜推進 + 天氣 + 天空跟隨
  shrinePortal.userData.update(t);
  motes.position.z = ctrl.pos.z * 0.2;

  if (nearShrine()) {
    promptEl.textContent = '[ E ]  返回博麗神社';
    promptEl.classList.add('on');
  } else if (nearVillage()) {
    promptEl.textContent = '[ E ]  人間之里（尚未開放）';
    promptEl.classList.add('on');
  } else {
    promptEl.classList.remove('on');
  }

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
    for (let i = 0; i < n; i++) { t += dt; ctrl.update(dt, t); }
    return ctrl.pos.toArray().map(v => +v.toFixed(2));
  },
};
