// 永遠亭 —— 迷途竹林最深處的和式大宅。
//
// 設定考據（Touhou Wiki）：永遠亭（えいえんてい）是輝夜與永琳從月之都
// 逃亡後藏身的宅邸，藏在竹林深處，外人幾乎找不到。宅裡開著永琳的診療所
// （人里的人有重病會託妹紅帶路來求醫），院裡養著一群地上兔。
//
// 這張圖是第一張「safe 劇情圖」：沒有怪，重點是建築群與三位住民 ——
// 輝夜（簷廊前）、永琳（診療間）、鈴仙（中庭迎客）。對話走共用的
// NPCManager + Dialogue（跟神社同一套）。
//
// 布局：北門進來（接迷途竹林南門），白灰圍牆圈出宅院；院內是
// 母屋（大屋頂＋簷廊）、渡り廊下接東側的診療間、西側月見台、
// 石燈籠與小池。牆外一圈竹林把宅子藏起來。

import * as THREE from 'three';
import * as BGU from 'three/addons/utils/BufferGeometryUtils.js';
import { setGroundHeightFn } from '../../src/world/terrain.js';
import { WORLD, REGION_BY_ID } from '../../src/config.js';
import { buildCharacter } from '../../src/entities/model.js';
import { ACTIVE_PLAYABLE, DEFAULT_PLAYER } from '../../src/entities/roster.js';
import { PlayerController } from '../../src/player/controller.js';
import { Environment } from '../../src/world/environment.js';
import { makePortalGlow } from '../../src/world/portal.js';
import { NPCManager, TALK_RANGE } from '../../src/entities/npc.js';
import { Dialogue } from '../../src/ui/dialogue.js';
import { Progression } from '../../src/player/progression.js';
import { installLoadout } from '../../src/player/loadout.js';
import { installHUD, bindEscMenu } from '../../src/ui/hud.js';
import { loadQualityIdx, saveQualityIdx, applyBasicQuality, QUALITY_NAMES } from '../../src/world/quality.js';
import { mergeStaticByMaterial } from '../../src/core/optimize.js';
import { catmullRom } from '../../src/world/pathnet.js';
import { GroundGrid, ribbonOnGrid, decalOnGrid } from '../../src/world/groundmesh.js';
import { scatterGrass } from '../../src/world/flora.js';

/* 共用 HUD */
const HUD = installHUD({
  title: '永遠亭',
  subtitle: 'EIENTEI · 迷途竹林深處',
  keys: [
    ['WASD / 方向鍵', '移動'], ['滑鼠', '轉視角'], ['滾輪', '縮放'],
    ['Shift', '衝刺'], ['Space', '跳躍'],
    ['E', '互動 / 對話'], ['K', '技能'], ['ESC', '選單'],
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
const camera = new THREE.PerspectiveCamera(68, innerWidth / innerHeight, 0.2, 460);
camera.rotation.order = 'YXZ';

const env = new Environment(scene, renderer, {
  fogMul: 1.55,
  shadowArea: 52,
  followSun: true,
});

let qualityIdx = loadQualityIdx(2);
const syncQuality = () => {
  applyBasicQuality(renderer, env.sun, qualityIdx);
  HUD.qualLabel.textContent = `畫質：${QUALITY_NAMES[qualityIdx]}`;
};
syncQuality();

/* ─────────────────────────────────────────────────── 地形高度場 ── */
// 200×180 的小圖：院內刻意壓平（宅院是整過地的），院外緩起伏，
// 邊界外抬成竹山把玩家收在圖裡。
const HALF_X = 100, HALF_Z = 90;
const NORTH_GATE = { x: 0, z: -78 };            // 回迷途竹林
const WALL = { x0: -56, x1: 56, z0: -34, z1: 64 };   // 圍牆矩形
const GATE_W = 6.4;                              // 表門開口寬

let _seed = 20260731;
function rand() {
  _seed = (_seed * 1664525 + 1013904223) >>> 0;
  return _seed / 4294967296;
}
const rr = (a, b) => a + rand() * (b - a);

function heightAt(x, z) {
  let roll = Math.sin(z * 0.031) * 0.5 + Math.sin(x * 0.026 + 1.3) * 0.45;
  // 院內壓平：離牆 8 公尺的過渡帶，避免牆基出現一階地形斷差
  const inn = Math.min(x - (WALL.x0 - 2), (WALL.x1 + 2) - x, z - (WALL.z0 - 2), (WALL.z1 + 2) - z);
  const flat = Math.max(0, Math.min(1, inn / 8));
  roll *= 1 - flat * 0.8;
  // 邊界圍坡。一定要封頂（不封會在網格邊緣衝成百米白牆）
  const d = Math.max(Math.abs(x) - (HALF_X - 10), Math.abs(z) - (HALF_Z - 10));
  const slope = d <= 0 ? 0 : Math.min(12, d * d * 0.06);
  return roll + slope + Math.sin(x * 0.5 + z * 0.31) * 0.05;
}
setGroundHeightFn(heightAt);
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
const soilTex = canvasTex(256, (g, s) => {
  g.fillStyle = '#41422c'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 2200; i++) {
    g.fillStyle = `rgba(${52 + Math.random() * 44},${58 + Math.random() * 38},${36 + Math.random() * 24},.5)`;
    g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 1 + Math.random() * 5, 0, 7); g.fill();
  }
}, 20, 18);
const gravelTex = canvasTex(256, (g, s) => {
  // 院內的白砂利 —— 比外頭的林地亮一大截，一進門就知道「到了」
  g.fillStyle = '#b9b2a0'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 3200; i++) {
    g.fillStyle = `rgba(${168 + Math.random() * 50},${160 + Math.random() * 46},${140 + Math.random() * 40},.55)`;
    g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 0.6 + Math.random() * 2.2, 0, 7); g.fill();
  }
  // 耙紋（枯山水的細線）
  g.strokeStyle = 'rgba(120,112,96,.25)'; g.lineWidth = 1.5;
  for (let y = 8; y < s; y += 14) { g.beginPath(); g.moveTo(0, y); g.lineTo(s, y); g.stroke(); }
}, 22, 20);
const stoneTex = canvasTex(256, (g, s) => {
  g.fillStyle = '#8b8578'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 60; i++) {
    g.fillStyle = `rgba(${118 + Math.random() * 40},${112 + Math.random() * 36},${98 + Math.random() * 30},.8)`;
    const w = 18 + Math.random() * 40, h = 12 + Math.random() * 26;
    g.fillRect(Math.random() * s, Math.random() * s, w, h);
    g.strokeStyle = 'rgba(60,56,48,.5)'; g.strokeRect(Math.random() * s, Math.random() * s, w, h);
  }
}, 2, 14);

const MAT = {
  soil: new THREE.MeshStandardMaterial({ map: soilTex, roughness: 1 }),
  gravel: new THREE.MeshStandardMaterial({
    map: gravelTex, roughness: 1,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
  }),
  stonePath: new THREE.MeshStandardMaterial({
    map: stoneTex, roughness: 0.95,
    polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -3,
  }),
  plaster: new THREE.MeshStandardMaterial({ color: '#e8dfca', roughness: 0.95 }),
  wood: new THREE.MeshStandardMaterial({ color: '#7a6144', roughness: 0.92 }),
  darkWood: new THREE.MeshStandardMaterial({ color: '#4e3a2a', roughness: 0.95 }),
  redWood: new THREE.MeshStandardMaterial({ color: '#8a3c34', roughness: 0.9 }),
  tile: new THREE.MeshStandardMaterial({ color: '#3e4650', roughness: 0.85, flatShading: true }),
  stone: new THREE.MeshStandardMaterial({ color: '#8d8b80', roughness: 1 }),
  mossStone: new THREE.MeshStandardMaterial({ color: '#77806a', roughness: 1 }),
  paper: new THREE.MeshStandardMaterial({
    color: '#fff0cc', roughness: 0.9, emissive: '#8a5a18', emissiveIntensity: 0.3,
  }),
  culm: new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.72 }),
  leaf: new THREE.MeshStandardMaterial({
    color: 0x5f7a34, roughness: 1, flatShading: true, side: THREE.DoubleSide,
  }),
  pine: new THREE.MeshStandardMaterial({ color: '#3a5c30', roughness: 1, flatShading: true }),
  water: new THREE.MeshStandardMaterial({
    color: '#3c6a72', roughness: 0.25, metalness: 0.1,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
  }),
};

const world = new THREE.Group();
scene.add(world);

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
const GRID = new GroundGrid({ size: Math.max(HALF_X, HALF_Z) * 2 + 120, seg: 130, heightAt });
const gSample = (x, z) => GRID.sample(x, z);
{
  const m = new THREE.Mesh(GRID.buildGeometry(), MAT.soil);
  m.receiveShadow = true;
  world.add(m);
}

// 院內整片白砂利（貼地 decal，網格三角形完全對齊 —— 不會閃）
decalOnGrid(world, WALL.x1 - WALL.x0, WALL.z1 - WALL.z0,
  (WALL.x0 + WALL.x1) / 2, (WALL.z0 + WALL.z1) / 2, MAT.gravel, gSample, 0.04);

/* 小徑：北門 → 表門的林間土徑；院內的飛石道（石板路） */
// 三段路首尾相接（参道→中庭→往診療間），接點必然重疊 ——
// lift 各差 1.2 公分，兩層路面才不會共面互閃。
const APPROACH = [[NORTH_GATE.x, NORTH_GATE.z], [1.5, -66], [-1.5, -52], [0.5, -40], [0, WALL.z0]];
ribbonOnGrid(world, catmullRom(APPROACH, 2.2), 1.9, MAT.stonePath, gSample, 0.06);
ribbonOnGrid(world, catmullRom([[0, WALL.z0], [0, -18], [0, 13.6]], 2), 1.35, MAT.stonePath, gSample, 0.072);
ribbonOnGrid(world, catmullRom([[0.8, 0], [10, 8], [20, 13], [30, 16]], 2), 1.1, MAT.stonePath, gSample, 0.084);

/* ─────────────────────────────────────────────── 圍牆與表門 ── */
/** 白灰牆一段（沿 x 或 z 軸）。基座石 + 白灰身 + 瓦頂帽。 */
function wallRun(x0, z0, x1, z1) {
  const cx = (x0 + x1) / 2, cz = (z0 + z1) / 2;
  const len = Math.hypot(x1 - x0, z1 - z0);
  const alongX = Math.abs(x1 - x0) > Math.abs(z1 - z0);
  const y = heightAt(cx, cz);
  const sx = alongX ? len : 0.55, sz = alongX ? 0.55 : len;
  box(sx, 0.5, sz, MAT.stone, cx, y + 0.25, cz);
  box(alongX ? len : 0.42, 2.0, alongX ? 0.42 : len, MAT.plaster, cx, y + 1.5, cz);
  box(alongX ? len + 0.3 : 0.8, 0.3, alongX ? 0.8 : len + 0.3, MAT.tile, cx, y + 2.65, cz);
  block(cx, cz, sx + 0.2, sz + 0.2, y + 2.8);
}
wallRun(WALL.x0, WALL.z0, -GATE_W / 2, WALL.z0);
wallRun(GATE_W / 2, WALL.z0, WALL.x1, WALL.z0);
wallRun(WALL.x0, WALL.z1, WALL.x1, WALL.z1);
wallRun(WALL.x0, WALL.z0, WALL.x0, WALL.z1);
wallRun(WALL.x1, WALL.z0, WALL.x1, WALL.z1);

/** 表門：冠木門（兩粗柱 + 橫樑 + 瓦頂），跟竹林南門是同一座門的裡側 */
(function omotemon() {
  const cx = 0, cz = WALL.z0;
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  world.add(g);
  for (const s of [-1, 1]) {
    cyl(0.3, 0.36, 4.6, MAT.darkWood, s * (GATE_W / 2 + 0.4), 2.3, 0, 10, g);
    post(cx + s * (GATE_W / 2 + 0.4), cz, 0.42, y + 4.6);
  }
  box(GATE_W + 2.4, 0.46, 0.56, MAT.darkWood, 0, 4.35, 0, g);
  box(GATE_W + 1.2, 0.32, 0.42, MAT.darkWood, 0, 3.62, 0, g);
  for (const s of [-1, 1]) {
    const slope = box(GATE_W + 3.4, 0.2, 1.4, MAT.tile, 0, 4.95, s * 0.5, g);
    slope.rotation.x = s * 0.5;
  }
  box(GATE_W + 3.6, 0.26, 0.32, MAT.tile, 0, 5.22, 0, g);
  box(1.8, 0.58, 0.1, MAT.wood, 0, 3.95, 0.32, g);   // 門額
  // 門邊一對石兔 —— 永遠亭的地上兔（狛犬的位置換成兔子）
  for (const s of [-1, 1]) {
    const r = new THREE.Group();
    r.position.set(s * (GATE_W / 2 + 1.6), 0.36, 1.2);
    r.rotation.y = Math.PI - s * 0.4;
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
    post(cx + s * (GATE_W / 2 + 1.6), cz + 1.2, 0.3, y + 0.9);
  }
})();

/* ───────────────────────────────────────── 母屋（大屋頂＋簷廊） ── */
const HALL = { x: 0, z: 22, w: 20, d: 11, h: 3.2 };
(function honya() {
  const y = heightAt(HALL.x, HALL.z);
  const g = new THREE.Group();
  g.position.set(HALL.x, y, HALL.z);
  world.add(g);

  box(HALL.w + 2, 0.55, HALL.d + 2, MAT.stone, 0, 0.27, 0, g);            // 基壇
  box(HALL.w, HALL.h, HALL.d, MAT.plaster, 0, 0.55 + HALL.h / 2, 0, g);   // 屋身

  // 正面朝北（面向表門與中庭）：木柱 + 障子（紙窗發暖光，夜裡整排亮起來）
  const fz = -(HALL.d / 2 + 0.02);
  for (let i = -4; i <= 4; i++) {
    cyl(0.11, 0.12, HALL.h, MAT.darkWood, i * (HALL.w / 8.6), 0.55 + HALL.h / 2, fz, 6, g);
  }
  for (let i = -3; i <= 3; i++) {
    if (i === 0) continue;                                    // 正中是門
    box(1.7, 1.7, 0.06, MAT.paper, i * (HALL.w / 8.6) + (i > 0 ? -1.15 : 1.15), 1.85, fz, g);
  }
  box(1.6, 2.2, 0.08, MAT.darkWood, 0, 1.7, fz - 0.02, g);    // 玄關板戶

  // 簷廊（縁側）：木地板繞正面與東西兩側
  const EN_W = 1.5, ey = 0.82;
  box(HALL.w + EN_W * 2, 0.12, EN_W, MAT.wood, 0, ey, -(HALL.d / 2 + EN_W / 2), g);
  for (const s of [-1, 1]) {
    box(EN_W, 0.12, HALL.d, MAT.wood, s * (HALL.w / 2 + EN_W / 2), ey, 0, g);
  }
  // 簷廊外緣的細柱撐住出簷
  for (let i = -5; i <= 5; i++) {
    cyl(0.07, 0.08, 3.1, MAT.darkWood, i * (HALL.w / 10.4), 0.82 + 1.55, -(HALL.d / 2 + EN_W - 0.12), 6, g);
  }
  // 上簷廊的踏石
  box(1.6, 0.24, 0.9, MAT.stone, 0, 0.12, -(HALL.d / 2 + EN_W + 0.55), g);

  // 大屋頂：兩坡 + 主棟 + 兩端的破風板
  const RW = HALL.w + 5, RD = HALL.d + 4.6;
  for (const s of [-1, 1]) {
    const slope = box(RW, 0.26, RD * 0.62, MAT.tile, 0, 0.55 + HALL.h + 1.55, s * RD * 0.21, g);
    slope.rotation.x = s * 0.52;
  }
  box(RW + 0.8, 0.42, 1.2, MAT.tile, 0, 0.55 + HALL.h + 2.6, 0, g);
  for (const s of [-1, 1]) {
    const gable = box(0.24, 2.1, RD * 0.52, MAT.darkWood, s * (RW / 2 - 0.1), 0.55 + HALL.h + 1.5, 0, g);
    gable.rotation.z = s * 0.06;
  }
  // 簷下一排燈籠（掛在朝中庭的一側）
  for (let i = -3; i <= 3; i++) {
    box(0.28, 0.34, 0.28, MAT.paper, i * (HALL.w / 7), 0.55 + HALL.h + 0.4, -(HALL.d / 2 + 1.1), g);
  }
  // 整棟（含簷廊）擋人 —— 簷廊不做可爬，省掉站上木緣的高度細節
  block(HALL.x, HALL.z, HALL.w + EN_W * 2 + 0.6, HALL.d + EN_W * 2 + 0.6, y + HALL.h + 3.4);
})();

/* ────────────────────────── 渡り廊下 + 診療間（永琳的診所） ── */
const CLINIC = { x: 33, z: 22, w: 10, d: 8, h: 2.8 };
(function clinicWing() {
  // 渡り廊下：母屋東緣 → 診療間西緣，架高的木廊 + 小屋頂
  const y0 = heightAt(16, HALL.z);
  const gx0 = HALL.x + HALL.w / 2 + 1.5, gx1 = CLINIC.x - CLINIC.w / 2;
  const gLen = gx1 - gx0, gcx = (gx0 + gx1) / 2;
  box(gLen, 0.12, 1.9, MAT.wood, gcx, y0 + 0.8, HALL.z);
  for (let i = 0; i <= 3; i++) {
    const px = gx0 + (gLen * i) / 3;
    for (const s of [-1, 1]) {
      cyl(0.07, 0.08, 2.5, MAT.darkWood, px, y0 + 1.35, HALL.z + s * 0.85, 6);
    }
  }
  for (const s of [-1, 1]) {
    const slope = box(gLen + 0.6, 0.14, 1.3, MAT.tile, gcx, y0 + 2.75, HALL.z + s * 0.5);
    slope.rotation.x = s * 0.5;
  }
  block(gcx, HALL.z, gLen, 2.3, y0 + 2.9);

  // 診療間本體
  const y = heightAt(CLINIC.x, CLINIC.z);
  const g = new THREE.Group();
  g.position.set(CLINIC.x, y, CLINIC.z);
  world.add(g);
  box(CLINIC.w + 1.4, 0.5, CLINIC.d + 1.4, MAT.stone, 0, 0.25, 0, g);
  box(CLINIC.w, CLINIC.h, CLINIC.d, MAT.plaster, 0, 0.5 + CLINIC.h / 2, 0, g);
  const fz = -CLINIC.d / 2 - 0.02;                       // 門朝北（面向中庭）
  box(1.4, 2.0, 0.08, MAT.darkWood, -1.2, 1.5, fz, g);
  box(1.5, 1.5, 0.06, MAT.paper, 1.8, 1.8, fz, g);
  for (const s of [-1, 1]) {
    const slope = box(CLINIC.w + 3, 0.22, CLINIC.d * 0.62, MAT.tile, 0, 0.5 + CLINIC.h + 1.15, s * CLINIC.d * 0.21, g);
    slope.rotation.x = s * 0.5;
  }
  box(CLINIC.w + 3.6, 0.36, 1.0, MAT.tile, 0, 0.5 + CLINIC.h + 1.95, 0, g);
  // 「診療」木牌 + 門口的藥草架
  box(0.5, 1.3, 0.08, MAT.wood, -2.3, 1.6, fz - 0.06, g);
  box(2.2, 0.1, 0.5, MAT.wood, 2.8, 0.7, fz - 0.6, g);
  for (let i = 0; i < 4; i++) {
    cyl(0.1, 0.12, 0.24, MAT.mossStone, 2.0 + i * 0.55, 0.87, fz - 0.6, 6, g);
  }
  block(CLINIC.x, CLINIC.z, CLINIC.w + 0.8, CLINIC.d + 0.8, y + CLINIC.h + 2.2);
})();

/* ─────────────────────────────── 中庭：燈籠、小池、松、月見台 ── */
/** 石燈籠 */
function stoneLantern(cx, cz) {
  const y = heightAt(cx, cz);
  cyl(0.3, 0.36, 0.3, MAT.stone, cx, y + 0.15, cz);
  cyl(0.17, 0.2, 1.1, MAT.stone, cx, y + 0.85, cz);
  cyl(0.42, 0.3, 0.22, MAT.stone, cx, y + 1.5, cz);
  box(0.3, 0.3, 0.3, MAT.paper, cx, y + 1.78, cz);
  cyl(0.08, 0.62, 0.36, MAT.stone, cx, y + 2.1, cz);
  post(cx, cz, 0.4, y + 2.3);
}
stoneLantern(-4.2, -22); stoneLantern(4.2, -22);
stoneLantern(-4.2, -2); stoneLantern(4.2, -2);
stoneLantern(24, 14.5);

/** 松（幹 + 三層扁平枝葉） */
function pine(cx, cz, h = 5) {
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  g.rotation.y = rand() * 6.28;
  world.add(g);
  const trunk = cyl(0.16, 0.24, h, MAT.darkWood, 0, h / 2, 0, 7, g);
  trunk.rotation.z = rr(-0.08, 0.08);
  for (let k = 0; k < 3; k++) {
    const r = 1.9 - k * 0.5;
    const c = new THREE.Mesh(new THREE.ConeGeometry(r, 0.85, 7), MAT.pine);
    c.position.set(rr(-0.4, 0.4), h * (0.55 + k * 0.22), rr(-0.4, 0.4));
    c.castShadow = true;
    g.add(c);
  }
  post(cx, cz, 0.3, y + h);
}
pine(-32, -14, 5.5); pine(30, -20, 4.8); pine(-16, 46, 5.2); pine(42, 40, 4.5);

/* 小池：淺水盤 + 石緣 + 蘆葦 */
(function pond() {
  const cx = -26, cz = 6;
  const y = heightAt(cx, cz);
  const w = new THREE.Mesh(new THREE.CircleGeometry(5, 24), MAT.water);
  w.rotation.x = -Math.PI / 2;
  w.scale.y = 0.72;
  w.position.set(cx, y + 0.05, cz);
  world.add(w);
  for (let i = 0; i < 14; i++) {
    const a = (i / 14) * Math.PI * 2;
    const r = rr(0.25, 0.55);
    const rock = new THREE.Mesh(new THREE.IcosahedronGeometry(r, 0), MAT.mossStone);
    rock.position.set(cx + Math.cos(a) * 5.1, y + r * 0.4, cz + Math.sin(a) * 3.75);
    rock.rotation.set(rand() * 3, rand() * 3, rand() * 3);
    rock.castShadow = rock.receiveShadow = true;
    world.add(rock);
  }
  for (let i = 0; i < 8; i++) {
    const a = rr(2.2, 4.2);
    cyl(0.025, 0.03, rr(0.8, 1.3), MAT.pine, cx + Math.cos(a) * 4.3, y + 0.5, cz + Math.sin(a) * 3.2, 4);
  }
  post(cx, cz, 4.4, y + 0.35);   // 別讓人走進池心
})();

/* 月見台：西側的木平台（輝夜賞月用） */
(function tsukimidai() {
  const cx = -34, cz = 34;
  const y = heightAt(cx, cz);
  box(6, 0.5, 6, MAT.stone, cx, y + 0.25, cz);
  box(5.6, 0.12, 5.6, MAT.wood, cx, y + 0.56, cz);
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    cyl(0.07, 0.08, 0.8, MAT.darkWood, cx + sx * 2.6, y + 0.9, cz + sz * 2.6, 6);
  }
  for (const s of [-1, 1]) {
    box(5.4, 0.07, 0.1, MAT.darkWood, cx, y + 1.25, cz + s * 2.6);
    box(0.1, 0.07, 5.4, MAT.darkWood, cx + s * 2.6, y + 1.25, cz);
  }
  block(cx, cz, 6.2, 6.2, y + 0.62);
})();

/* 後庭的石組 */
for (let i = 0; i < 8; i++) {
  const x = rr(-46, 50), z = rr(44, 60);
  if (Math.abs(x) < 14) continue;
  const r = rr(0.3, 0.9);
  const rock = new THREE.Mesh(new THREE.IcosahedronGeometry(r, 0), MAT.mossStone);
  rock.position.set(x, heightAt(x, z) + r * 0.35, z);
  rock.rotation.set(rand() * 3, rand() * 3, rand() * 3);
  rock.castShadow = rock.receiveShadow = true;
  world.add(rock);
}

/* ─────────────────────────────── 牆外的竹林（把宅子藏起來） ── */
(function bambooRing() {
  // 跟迷途竹林同一種竹子（竹竿 + 三層垂葉），數量少一截，只當背景。
  const spots = [];
  for (let i = 0; i < 2600; i++) {
    const x = rr(-HALF_X - 8, HALF_X + 8), z = rr(-HALF_Z - 8, HALF_Z + 8);
    // 牆內不長；北門参道兩側 6 公尺不長
    if (x > WALL.x0 - 3 && x < WALL.x1 + 3 && z > WALL.z0 - 3 && z < WALL.z1 + 3) continue;
    if (Math.abs(x) < 6 && z < WALL.z0) continue;
    if (rand() < 0.35) continue;
    spots.push({ x, z, h: rr(7, 12), r: rr(0.07, 0.11), tilt: rr(-0.05, 0.05), yaw: rand() * 6.28 });
  }
  const culmGeo = new THREE.CylinderGeometry(0.8, 1, 1, 6, 1);
  culmGeo.translate(0, 0.5, 0);
  const blades = [];
  const LAYERS = [
    { n: 7, up: 0.0, out: 0.3, len: 1.15, droop: 0.95 },
    { n: 6, up: 0.55, out: 0.24, len: 0.95, droop: 0.75 },
    { n: 5, up: 1.0, out: 0.16, len: 0.75, droop: 0.55 },
  ];
  for (const L of LAYERS) {
    for (let i = 0; i < L.n; i++) {
      const g = new THREE.PlaneGeometry(0.15, L.len);
      g.translate(0, L.len / 2, 0);
      g.rotateX(L.droop);
      g.translate(0, L.up, L.out);
      g.rotateY((i / L.n) * Math.PI * 2 + L.up * 2.1);
      blades.push(g);
    }
  }
  const leafGeo = BGU.mergeGeometries(blades, false);

  // 四象限各一組 InstancedMesh，讓身後的整片竹子能被視錐裁掉
  const quads = [[], [], [], []];
  for (const s of spots) quads[(s.x > 0 ? 1 : 0) + (s.z > 0 ? 2 : 0)].push(s);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler();
  const v = new THREE.Vector3(), sc = new THREE.Vector3(), col = new THREE.Color();
  let total = 0;
  for (const list of quads) {
    if (!list.length) continue;
    total += list.length;
    const culms = new THREE.InstancedMesh(culmGeo, MAT.culm, list.length);
    culms.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(list.length * 3), 3);
    const leaves = new THREE.InstancedMesh(leafGeo, MAT.leaf, list.length);
    leaves.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(list.length * 3), 3);
    list.forEach((b, i) => {
      const y = heightAt(b.x, b.z);
      e.set(b.tilt, b.yaw, b.tilt * 0.7);
      q.setFromEuler(e);
      sc.set(b.r, b.h, b.r);
      m4.compose(v.set(b.x, y, b.z), q, sc);
      culms.setMatrixAt(i, m4);
      const age = rand();
      col.setHSL(0.19 - age * 0.03, 0.34 + age * 0.12, 0.34 + age * 0.16);
      culms.setColorAt(i, col);
      const ls = 0.85 + b.h * 0.055;
      sc.set(ls, ls, ls);
      m4.compose(v.set(b.x + Math.sin(b.tilt) * b.h, y + b.h * 0.86, b.z + Math.sin(b.tilt * 0.7) * b.h), q, sc);
      leaves.setMatrixAt(i, m4);
      col.setHSL(0.24 - age * 0.035, 0.42 - age * 0.1, 0.26 + age * 0.12);
      leaves.setColorAt(i, col);
    });
    culms.instanceColor.needsUpdate = true;
    leaves.instanceColor.needsUpdate = true;
    world.add(culms, leaves);
  }
  console.info(`[eientei] 圍竹 ${total} 根（4 組 InstancedMesh）`);
})();

/* ─────────────────────────────────── 草叢（参道與院內的緣） ── */
scatterGrass(world, {
  count: 1500, heightAt,
  place: () => {
    // 一半撒在参道兩側，一半撒在院內牆邊與後庭
    if (Math.random() < 0.5) {
      const z = -36 - Math.random() * 48;
      const x = (Math.random() < 0.5 ? -1 : 1) * (2.6 + Math.random() * 12);
      return [x, z];
    }
    const x = rr(WALL.x0 + 2, WALL.x1 - 2), z = rr(WALL.z0 + 2, WALL.z1 - 2);
    // 中庭正中（砂利耙紋區）留乾淨
    if (Math.abs(x) < 12 && z > -30 && z < 14) return null;
    return [x, z];
  },
  baseColor: 0x5f7a38,
});

/* ─────────────────────── 北門遠景：迷途竹林（回程的方向） ── */
(function bambooVista() {
  const g = new THREE.Group();
  g.position.set(NORTH_GATE.x, heightAt(NORTH_GATE.x, NORTH_GATE.z), NORTH_GATE.z - 10);
  world.add(g);
  // MAT.culm 是給 instanceColor 用的白底 —— 遠景直接用要自帶青竹色
  const culmM = new THREE.MeshStandardMaterial({ color: '#7d9a4c', roughness: 0.8 });
  for (let i = 0; i < 90; i++) {
    const z = -4 - Math.random() * 46;
    const x = (Math.random() < 0.5 ? -1 : 1) * (3 + Math.random() * 30);
    const h = 8 + Math.random() * 5;
    const c = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.12, h, 5), culmM);
    c.position.set(x, h / 2, z);
    g.add(c);
    const top = new THREE.Mesh(new THREE.IcosahedronGeometry(1.3, 0), MAT.leaf);
    top.position.set(x, h * 0.9, z);
    top.scale.set(1, 0.7, 1);
    g.add(top);
  }
  g.traverse(o => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
})();

/* ───────────────────────────────────────────── 傳送點 ── */
const northPortal = makePortalGlow(world, NORTH_GATE.x, heightAt(NORTH_GATE.x, NORTH_GATE.z), NORTH_GATE.z, 0xa8c96a);

/* ──────────────────────────────────────────── 靜態幾何合併 ── */
{
  const s = mergeStaticByMaterial(world, { cell: 45 });
  console.info(`[optimize] 永遠亭靜態合併：${s.before} → ${s.after} 個網格（合併成 ${s.merged}，保留 ${s.kept}）`);
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
ctrl.bounds = { hx: HALF_X + 8, hz: HALF_Z + 8 };
ctrl.maxGrade = 1.05;
// 從竹林南門走進來 = 出生在北門
ctrl.teleport(NORTH_GATE.x, NORTH_GATE.z + 6);
ctrl.yaw = 0;              // 面向南（往宅院）
ctrl.camYaw = Math.PI;

/* ────────────────────────── 住民：輝夜・永琳・鈴仙（對話） ── */
const npcMgr = new NPCManager(scene);
// roster 裡三位的 region 都是 eientei，origin 傳同一筆 REGION → offset 即局部座標
npcMgr.setRoster(['kaguya', 'eirin', 'reisen'], REGION_BY_ID.eientei, 140);
const dialogue = new Dialogue();

/* ─────────────────────────────── 成長 + 角色隨身裝備 ── */
/* 夜裡整排紙窗與燈籠亮起來 —— 合併後的網格共用 MAT.paper，改一份就全亮 */
env.opts.onApply = (tt) => {
  MAT.paper.emissiveIntensity = 0.3 + tt.lantern * 1.5;
};

const prog = new Progression({
  onLevelUp: (msg) => { HUD.toast(msg); kit.skills?.onLevelUp(); },
});
/* 永遠亭是安全區（永琳的地盤沒有怪敢鬧事）—— 不傳 mobs，招式照出。 */
const kit = installLoadout({
  getSpec: () => spec, getCtrl: () => ctrl, scene, HUD, prog,
  isBlocked: () => escMenu.isOpen || dialogue.active,
  onDeath: () => ctrl.teleport(NORTH_GATE.x, NORTH_GATE.z + 6),
});
prog.renderBadge(spec.combat ? 'hinokami' : null, '日之呼吸');

/* ───────────────────────────────────────────── 互動與提示 ── */
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

const nearNorth = () => Math.hypot(ctrl.pos.x - NORTH_GATE.x, ctrl.pos.z - NORTH_GATE.z) < 4.8;

window.addEventListener('keydown', (e) => {
  if (e.code !== 'KeyE' || escMenu.isOpen) return;
  // 對話進行中：E 只推進，不落到下面的互動判定
  if (dialogue.active) { dialogue.advance(); return; }
  if (!ctrl.locked) return;

  const npc = npcMgr.nearest;
  if (npc && npc.pos.distanceTo(ctrl.pos) <= TALK_RANGE) {
    ctrl.enabled = false;
    dialogue.open(npc.spec, npcMgr.nextTalk(npc), () => { ctrl.enabled = true; });
    return;
  }
  if (nearNorth()) {
    HUD.showLoading('迷途竹林 讀取中');
    location.href = '../bamboo/?from=eientei';
  }
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
  npcMgr.update(t, ctrl.pos, camera);
  dialogue.update(dt);
  env.update(dt, camera.position);
  northPortal.userData.update(t);

  if (dialogue.active) { HUD.prompt(null); return; }
  const npc = npcMgr.nearest;
  if (npc && npc.pos.distanceTo(ctrl.pos) <= TALK_RANGE) {
    HUD.prompt(`[ E ]  與 ${npc.spec.zh} 對話`);
  } else if (nearNorth()) {
    HUD.prompt('[ E ]  返回迷途竹林');
  } else {
    HUD.prompt(null);
  }
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
window.__eientei = {
  renderer, scene, camera, ctrl, THREE, heightAt, env, colliders, prog, npcMgr, dialogue,
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
  NORTH_GATE, WALL, HALL, CLINIC,
};
