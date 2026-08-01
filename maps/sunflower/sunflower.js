// 太陽花田 —— 幻想鄉東南的一整片向日葵，風見幽香的地盤。
//
// 設定考據（Touhou Wiki）：太陽の畑是一片望不到邊的向日葵花田，
// 主人是風見幽香。花田不歡迎人，但也不是不能走 —— 只是花妖精會成群
// 圍上來趕人，而幽香就撐著洋傘站在花田中央看著。
//
// 這張圖是第二期的收尾，也是**環線的閉合點**：西邊接無名之丘、
// 北邊接獸道第四臂。走到這裡代表「神社 → 獸道 → 竹林 → 東口 →
// 無名之丘 → 花田 → 獸道」整圈走得通。
//
// 技術重點是向日葵：三萬多株花全部 InstancedMesh 分格切；花盤會**追日**
// （env 的太陽方位每幀餵進來，整片花田一起轉頭）—— 這是這張圖唯一一個
// 會動的大場景元素，也是向日葵最有辨識度的行為。
//
// 路一樣不鋪石磚（使用者要求）：田埂是踩出來的土痕，靠花的疏密引導。
//
// ※ 這是第一張改用 GameCore（src/core/GameCore.js）的圖：renderer /
//    Environment / 玩家 / 成長 / ESC / 大小地圖 / 主迴圈全部由共用層
//    提供，這個檔案只剩太陽花田獨有的東西（整合書・階段 A）。

import * as THREE from 'three';
import { setGroundHeightFn } from '../../src/world/terrain.js';
import { WORLD, REGION_BY_ID } from '../../src/config.js';
import { makePortalGlow } from '../../src/world/portal.js';
import { NPCManager, TALK_RANGE } from '../../src/entities/npc.js';
import { Dialogue } from '../../src/ui/dialogue.js';
import { FlowerFairies } from '../../src/combat/flowerfairies.js';
import { progressMobs } from '../../src/player/progression.js';
import { makeSignpost } from '../../src/world/signpost.js';
import { mergeStaticByMaterial } from '../../src/core/optimize.js';
import { PathNet, catmullRom } from '../../src/world/pathnet.js';
import { GroundGrid, ribbonOnGrid } from '../../src/world/groundmesh.js';
import { scatterGrass } from '../../src/world/flora.js';
import { ridgeRing, gapToward } from '../../src/world/vista.js';
import { bootMap } from '../../src/core/GameCore.js';

const core = bootMap({
  hud: {
    title: '太陽花田',
    subtitle: 'GARDEN OF THE SUN · 無名之丘 ⇄ 獸道',
    keys: [
      ['WASD / 方向鍵', '移動'], ['滑鼠', '轉視角'], ['滾輪', '縮放'],
      ['Shift', '衝刺'], ['Space', '跳躍'],
      ['E', '互動 / 對話'], ['K', '技能'], ['M', '地圖'], ['ESC', '選單'],
    ],
    flyKeys: [['F', '飛行'], ['Ctrl/C', '下降']],
    combatKeys: [['左鍵', '出招'], ['長按左鍵', '日之呼吸・全型'], ['R', '拔刀/納刀'], ['1 ~ 4', '技']],
  },
  camera: { far: 700 },
  exposure: 1.1,
  // 花田是開闊的：霧要很淡，「望不到邊的黃」是這張圖的第一印象
  env: { fogMul: 0.5, shadowArea: 58, followSun: true },
  // 完整後製鏈（整合書階段 B）：畫質雙標到此為止 —— 高檔有 GTAO 的
  // 接觸陰影與 Bloom，跟神社同一套；低檔自動全關，跟原本一樣輕。
  postFX: 'full',
});
const { HUD, renderer, scene, camera, env, world, colliders } = core;
const { box, cyl, post, block } = core;

/* ─────────────────────────────────────────────────── 地形高度場 ── */
const HALF = 180;
const WEST_END = { x: -162, z: -30 };    // 回無名之丘
const NORTH_END = { x: 40, z: -162 };    // 往獸道（第四臂．環線閉合）
const YUUKA = { x: 0, z: 10 };           // 幽香站的位置（roster offset 同值）

let _seed = 20260803;
function rand() {
  _seed = (_seed * 1664525 + 1013904223) >>> 0;
  return _seed / 4294967296;
}
const rr = (a, b) => a + rand() * (b - a);

function heightAt(x, z) {
  // 花田是整過的緩坡田地，起伏很小 —— 起伏大會遮住「一整片黃」
  const roll = Math.sin(x * 0.011) * 1.6 + Math.sin(z * 0.013 + 0.7) * 1.4
             + Math.sin((x + z) * 0.024) * 0.5;
  const d = Math.max(Math.abs(x), Math.abs(z)) - (HALF - 14);
  const slope = d <= 0 ? 0 : Math.min(18, d * d * 0.06);
  return roll + slope + Math.sin(x * 0.4 + z * 0.3) * 0.05;
}
setGroundHeightFn(heightAt);
WORLD.waterLevel = -999;

/* ─────────────────────────── 田埂：把花田切成幾塊（＝可走的路） ── */
const PATH_SEGMENTS = [
  {
    id: 'main', width: 5.0,
    pts: [
      [WEST_END.x, WEST_END.z], [-130, -22], [-96, -6], [-62, 4],
      [-30, 10], [YUUKA.x, YUUKA.z], [26, 4], [42, -18],
      [44, -60], [40, -104], [NORTH_END.x, NORTH_END.z],
    ],
  },
  {
    id: 'south', width: 4.2,
    pts: [[-30, 10], [-24, 48], [-6, 82], [22, 104], [58, 112]],
  },
  {
    id: 'east', width: 4.2,
    pts: [[26, 4], [70, 12], [104, 2], [134, -18]],
  },
];
const PATHS = new PathNet(PATH_SEGMENTS, { step: 3, cell: 14 });
const pathDist = (x, z) => PATHS.edgeDist(x, z, 2);

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
const fieldTex = canvasTex(256, (g, s) => {
  // 田土 + 稀疏的雜草：花田的地面在花底下，只有走在田埂上才看得到
  g.fillStyle = '#54502e'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 2600; i++) {
    g.fillStyle = `rgba(${76 + Math.random() * 46},${72 + Math.random() * 40},${44 + Math.random() * 28},.5)`;
    g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 1 + Math.random() * 5, 0, 7); g.fill();
  }
  for (let i = 0; i < 400; i++) {
    g.fillStyle = `rgba(${84 + Math.random() * 34},${106 + Math.random() * 34},${52 + Math.random() * 24},.45)`;
    g.fillRect(Math.random() * s, Math.random() * s, 2 + Math.random() * 4, 2 + Math.random() * 4);
  }
}, 30, 30);
const ridgeTex = canvasTex(256, (g, s) => {
  // 田埂：踩實的土，比田土亮一階（不是石磚）
  g.fillStyle = '#7a6e46'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 1800; i++) {
    g.fillStyle = `rgba(${118 + Math.random() * 44},${106 + Math.random() * 38},${74 + Math.random() * 28},.45)`;
    g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 1 + Math.random() * 4, 0, 7); g.fill();
  }
  for (let i = 0; i < 260; i++) {
    g.fillStyle = `rgba(${96 + Math.random() * 30},${116 + Math.random() * 30},${58 + Math.random() * 22},.5)`;
    const y = Math.random() < 0.5 ? Math.random() * 24 : s - Math.random() * 24;
    g.fillRect(Math.random() * s, y, 2 + Math.random() * 5, 2 + Math.random() * 5);
  }
}, 3, 34);

const MAT = {
  field: new THREE.MeshStandardMaterial({ map: fieldTex, roughness: 1 }),
  ridge: new THREE.MeshStandardMaterial({
    map: ridgeTex, roughness: 1,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
  }),
  stalk: new THREE.MeshStandardMaterial({ color: '#4d6a2c', roughness: 1 }),
  // 花盤整天朝著太陽 —— 也就是說站在順光側的玩家看到的全是花的**背面**。
  // 薄面片的背面接不到光會全黑，一整片田變成焦褐色。給一層金黃的自發光
  // 把背面拉回花色：正面照樣被日光打亮，背面也還讀得出是向日葵。
  petal: new THREE.MeshStandardMaterial({
    color: 0xffffff, roughness: 0.78, flatShading: true, side: THREE.DoubleSide,
    emissive: 0x8a6410, emissiveIntensity: 0.5,
  }),
  disc: new THREE.MeshStandardMaterial({ color: '#5a3a1c', roughness: 0.95 }),
  wood: new THREE.MeshStandardMaterial({ color: '#7a6144', roughness: 0.92 }),
  darkWood: new THREE.MeshStandardMaterial({ color: '#4e3d2c', roughness: 0.95 }),
  stone: new THREE.MeshStandardMaterial({ color: '#8d8b80', roughness: 1 }),
  mossStone: new THREE.MeshStandardMaterial({ color: '#77806a', roughness: 1 }),
  bark: new THREE.MeshStandardMaterial({ color: '#4a3828', roughness: 1 }),
  foliage: new THREE.MeshStandardMaterial({ color: '#4f6b34', roughness: 1, flatShading: true }),
  cloth: new THREE.MeshStandardMaterial({ color: '#a02838', roughness: 0.95, side: THREE.DoubleSide }),
};

/* ───────────────────────────────────────────────────────── 地面 ── */
const GRID = new GroundGrid({ size: HALF * 2 + 130, seg: 190, heightAt });
const gSample = (x, z) => GRID.sample(x, z);
{
  const m = new THREE.Mesh(GRID.buildGeometry(), MAT.field);
  m.receiveShadow = true;
  world.add(m);
}
// 支埂從主埂岔出，起點重疊 —— lift 錯開 1.2 公分才不會兩層路面互閃
PATH_SEGMENTS.forEach((seg, i) => {
  ribbonOnGrid(world, catmullRom(seg.pts, 2.5), seg.width / 2, MAT.ridge, gSample, 0.05 + i * 0.012);
});

/* ────────────────────────────────────────────── 向日葵（追日） ── */
/**
 * 全圖的向日葵。花盤與花瓣做成一個「頭」的 InstancedMesh 對，
 * 每幀依太陽的方位角整片轉頭 —— 這是向日葵最有辨識度的行為，
 * 也讓早晨與黃昏走進同一片田的感覺完全不同。
 *
 * 轉頭只改 instanceMatrix 的旋轉：一格一次 compose，成本跟畫一次差不多，
 * 但只在太陽方位變超過 0.5° 時才重寫（見 sunTurn）。
 */
const SUN = (() => {
  const CELL = 44;
  const cells = new Map();
  const key = (x, z) => `${Math.floor(x / CELL)},${Math.floor(z / CELL)}`;

  let n = 0;
  for (let i = 0; i < 62000; i++) {
    const x = rr(-HALF + 6, HALF - 6), z = rr(-HALF + 6, HALF - 6);
    if (pathDist(x, z) < 3.2) continue;                 // 田埂上不種
    if (Math.hypot(x - YUUKA.x, z - YUUKA.z) < 9) continue;   // 幽香站的空地
    // 田埂邊種得密一點：玩家一定走田埂，看到的就是路兩側那幾公尺。
    // 均勻撒的話走在路上會覺得「花田好稀疏」，但總數其實不少。
    if (pathDist(x, z) > 22 && rand() < 0.28) continue;
    const k = key(x, z);
    if (!cells.has(k)) cells.set(k, []);
    cells.get(k).push({
      x, z,
      h: rr(1.9, 2.9),
      scale: rr(0.95, 1.4),
      lean: rr(-0.09, 0.09),
      leanYaw: rand() * 6.28,
    });
    n++;
  }

  // --- 幾何 ---
  const stalkGeo = new THREE.CylinderGeometry(0.045, 0.075, 1, 5);
  stalkGeo.translate(0, 0.5, 0);                        // 根部在原點

  // 花盤 + 一圈花瓣，合成一個「頭」的幾何（一朵一個 instance）
  const headGeo = (() => {
    const parts = [];
    const disc = new THREE.CylinderGeometry(0.28, 0.28, 0.09, 10);
    disc.rotateX(Math.PI / 2);                          // 盤面朝 +z
    parts.push(disc);
    for (let i = 0; i < 12; i++) {
      const p = new THREE.PlaneGeometry(0.17, 0.34);
      p.translate(0, 0.42, 0);                          // 往外推到盤緣外
      p.rotateZ((i / 12) * Math.PI * 2);
      p.translate(0, 0, -0.02);
      parts.push(p);
    }
    return mergeParts(parts);
  })();

  // 葉子：兩片心形的大葉，掛在莖的中段
  const leafGeo = (() => {
    const parts = [];
    for (const s of [-1, 1]) {
      const p = new THREE.PlaneGeometry(0.34, 0.5);
      p.rotateX(-0.5);
      p.translate(s * 0.22, 0, 0);
      p.rotateY(s * 0.6);
      parts.push(p);
    }
    return mergeParts(parts);
  })();

  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler();
  const v = new THREE.Vector3(), s = new THREE.Vector3(), col = new THREE.Color();

  const groups = [];      // 每格一組 {heads, list, base:[{x,y,z,scale}]}
  let meshes = 0;
  for (const list of cells.values()) {
    const stalks = new THREE.InstancedMesh(stalkGeo, MAT.stalk, list.length);
    const leaves = new THREE.InstancedMesh(leafGeo, MAT.stalk, list.length);
    const heads = new THREE.InstancedMesh(headGeo, MAT.petal, list.length);
    heads.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(list.length * 3), 3);
    stalks.castShadow = true;
    heads.castShadow = true;
    meshes += 3;

    const base = [];
    list.forEach((f, i) => {
      const y = heightAt(f.x, f.z);
      e.set(f.lean * Math.cos(f.leanYaw), f.leanYaw, f.lean * Math.sin(f.leanYaw));
      q.setFromEuler(e);
      s.set(f.scale, f.h, f.scale);
      m4.compose(v.set(f.x, y, f.z), q, s);
      stalks.setMatrixAt(i, m4);

      s.set(f.scale, f.scale, f.scale);
      m4.compose(v.set(f.x, y + f.h * 0.52, f.z), q, s);
      leaves.setMatrixAt(i, m4);

      // 花色：從飽和的金黃到偏橘，少數泛白（快謝的）
      const w = rand();
      col.setHSL(0.115 - w * 0.02, 0.86 - w * 0.22, 0.54 + w * 0.14);
      heads.setColorAt(i, col);

      base.push({ x: f.x, y: y + f.h - 0.1, z: f.z, scale: f.scale });
    });
    stalks.instanceColor = null;
    heads.instanceColor.needsUpdate = true;
    world.add(stalks, leaves, heads);
    groups.push({ heads, base });
  }
  console.info(`[sunflower] 向日葵 ${n} 株（${meshes} 個 InstancedMesh，${cells.size} 個格子）`);

  /** 依太陽方位轉頭。yaw = 太陽的水平方位；pitch = 抬頭角。 */
  let lastYaw = 999;
  function sunTurn(yaw, pitch) {
    if (Math.abs(yaw - lastYaw) < 0.009) return;   // 動不到半度就不重寫
    lastYaw = yaw;
    const mm = new THREE.Matrix4(), qq = new THREE.Quaternion();
    const ee = new THREE.Euler(), vv = new THREE.Vector3(), ss = new THREE.Vector3();
    for (const g of groups) {
      g.base.forEach((b, i) => {
        ee.set(pitch, yaw, 0);
        qq.setFromEuler(ee);
        ss.setScalar(b.scale);
        mm.compose(vv.set(b.x, b.y, b.z), qq, ss);
        g.heads.setMatrixAt(i, mm);
      });
      g.heads.instanceMatrix.needsUpdate = true;
    }
  }
  return { sunTurn, count: n };
})();

/** 幾片幾何合一個（避免每個地圖都 import BufferGeometryUtils 的樣板） */
function mergeParts(parts) {
  // 這裡的幾片都是同一種屬性組成，直接手動接 —— 比拉進 BGU 輕
  let vCount = 0, iCount = 0;
  for (const p of parts) {
    vCount += p.attributes.position.count;
    iCount += p.index ? p.index.count : p.attributes.position.count;
  }
  const pos = new Float32Array(vCount * 3);
  const nor = new Float32Array(vCount * 3);
  const uv = new Float32Array(vCount * 2);
  const idx = new Uint32Array(iCount);
  let vo = 0, io = 0;
  for (const p of parts) {
    const pp = p.attributes.position.array;
    const pn = p.attributes.normal.array;
    const pu = p.attributes.uv.array;
    pos.set(pp, vo * 3); nor.set(pn, vo * 3); uv.set(pu, vo * 2);
    const pi = p.index ? p.index.array : null;
    const c = p.attributes.position.count;
    for (let i = 0; i < (pi ? pi.length : c); i++) idx[io + i] = (pi ? pi[i] : i) + vo;
    io += pi ? pi.length : c;
    vo += c;
    p.dispose();
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  g.setIndex(new THREE.BufferAttribute(idx, 1));
  return g;
}

/* ─────────────────────────────────── 田裡的東西（少而準） ── */

/** 稻草人 —— 花田裡唯一的人造物，也是田埂的路標 */
function scarecrow(cx, cz, rot = 0) {
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  g.rotation.y = rot;
  world.add(g);
  cyl(0.07, 0.09, 2.6, MAT.darkWood, 0, 1.3, 0, 6, g);
  const arm = box(1.9, 0.09, 0.09, MAT.darkWood, 0, 1.95, 0, g);
  arm.rotation.z = 0.06;
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.24, 8, 6), MAT.wood);
  head.position.y = 2.44; head.castShadow = true; g.add(head);
  const hat = new THREE.Mesh(new THREE.ConeGeometry(0.46, 0.3, 8), MAT.wood);
  hat.position.y = 2.66; hat.castShadow = true; g.add(hat);
  const coat = box(0.9, 0.8, 0.08, MAT.cloth, 0, 1.62, 0.03, g);
  coat.rotation.z = 0.03;
  post(cx, cz, 0.26, y + 2.7);
}
scarecrow(-62, 12, 0.5);
scarecrow(44, -60, -0.7);
scarecrow(-6, 82, 2.3);

/** 農具小屋 —— 東徑盡頭，幽香大概從來沒用過 */
(function shed() {
  const cx = 134, cz = -18;
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  g.rotation.y = -0.4;
  world.add(g);
  box(4.6, 0.3, 3.6, MAT.stone, 0, 0.15, 0, g);
  box(4.2, 2.3, 3.2, MAT.wood, 0, 1.45, 0, g);
  box(1.2, 1.9, 0.1, MAT.darkWood, 0, 1.25, 1.62, g);
  for (const s of [-1, 1]) {
    const slope = box(5.4, 0.2, 2.3, MAT.darkWood, 0, 2.86, s * 0.85, g);
    slope.rotation.x = s * 0.52;
  }
  box(5.6, 0.24, 0.3, MAT.darkWood, 0, 3.2, 0, g);
  // 靠在牆邊的鋤頭與竹籃
  const hoe = cyl(0.045, 0.05, 1.8, MAT.darkWood, 2.3, 0.9, 1.2, 5, g);
  hoe.rotation.z = 0.32;
  const basket = cyl(0.42, 0.32, 0.36, MAT.wood, -2.4, 0.5, 1.4, 8, g);
  basket.rotation.z = 0.1;
  block(cx, cz, 5.0, 4.2, y + 3.2);
})();

/** 花田中央的老樹 —— 幽香站在樹蔭下 */
(function shadeTree() {
  const cx = YUUKA.x - 5, cz = YUUKA.z + 4;
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  world.add(g);
  const trunk = cyl(0.34, 0.52, 7.5, MAT.bark, 0, 3.75, 0, 8, g);
  trunk.rotation.z = 0.04;
  for (let k = 0; k < 5; k++) {
    const r = 3.6 - k * 0.5;
    const c = new THREE.Mesh(new THREE.IcosahedronGeometry(r, 0), MAT.foliage);
    c.position.set(rr(-1.3, 1.3), 6.4 + k * 1.1, rr(-1.3, 1.3));
    c.castShadow = true;
    g.add(c);
  }
  post(cx, cz, 0.7, y + 7.5);
})();

/* 散落的石塊 */
for (let i = 0; i < 60; i++) {
  const sm = PATHS.samples[(rand() * PATHS.samples.length) | 0];
  const a = rand() * Math.PI * 2, d = rr(2.6, 9);
  const x = sm.x + Math.cos(a) * d, z = sm.z + Math.sin(a) * d;
  if (pathDist(x, z) < 2.2 || Math.abs(x) > HALF || Math.abs(z) > HALF) continue;
  const r = rr(0.24, 0.7);
  const rock = new THREE.Mesh(new THREE.IcosahedronGeometry(r, 0), MAT.mossStone);
  rock.position.set(x, heightAt(x, z) + r * 0.35, z);
  rock.rotation.set(rand() * 3, rand() * 3, rand() * 3);
  rock.castShadow = rock.receiveShadow = true;
  world.add(rock);
}

/* ─────────────────────────────── 草叢與雜草（田埂沿線） ── */
scatterGrass(world, {
  count: 3400, heightAt, cell: 44,
  place: () => {
    const sm = PATHS.samples[(Math.random() * PATHS.samples.length) | 0];
    const a = Math.random() * Math.PI * 2, d = 3.0 + Math.random() * 5.5;
    const x = sm.x + Math.cos(a) * d, z = sm.z + Math.sin(a) * d;
    if (pathDist(x, z) < 1.2) return null;   // 路緣留白，草才不會蓋到田埂上
    if (Math.abs(x) > HALF - 4 || Math.abs(z) > HALF - 4) return null;
    return [x, z];
  },
  baseColor: 0x6b8038,
});

/* ─────────────── 兩端遠景：西看無名之丘、北看獸道的森林 ── */
(function hillVista() {
  const g = new THREE.Group();
  g.position.set(WEST_END.x - 14, heightAt(WEST_END.x, WEST_END.z), WEST_END.z);
  world.add(g);
  const hillM = new THREE.MeshStandardMaterial({ color: '#8fa860', roughness: 1, flatShading: true });
  for (let i = 0; i < 8; i++) {
    const m = new THREE.Mesh(new THREE.SphereGeometry(20 + Math.random() * 16, 8, 5), hillM);
    m.position.set(-16 - Math.random() * 46, -6 - Math.random() * 5, (i - 4) * 40 + (Math.random() - 0.5) * 18);
    m.scale.y = 0.4;
    g.add(m);
  }
  // 丘上的白點＝鈴蘭花海，一眼認得出是剛才走過的那座丘
  const bellM = new THREE.MeshStandardMaterial({ color: '#f0f4e8', roughness: 0.85 });
  const bells = new THREE.InstancedMesh(new THREE.SphereGeometry(0.42, 5, 4), bellM, 260);
  const m4 = new THREE.Matrix4(), v = new THREE.Vector3();
  for (let i = 0; i < 260; i++) {
    m4.makeTranslation(v.set(-18 - Math.random() * 40, 1 + Math.random() * 4, (Math.random() - 0.5) * 300));
    bells.setMatrixAt(i, m4);
  }
  g.add(bells);
  g.traverse(o => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
})();

(function trailVista() {
  const g = new THREE.Group();
  g.position.set(NORTH_END.x, heightAt(NORTH_END.x, NORTH_END.z), NORTH_END.z - 12);
  world.add(g);
  const bark = new THREE.MeshStandardMaterial({ color: '#4a3828', roughness: 1 });
  const leafs = [
    new THREE.MeshStandardMaterial({ color: '#3d5c2a', roughness: 1, flatShading: true }),
    new THREE.MeshStandardMaterial({ color: '#557436', roughness: 1, flatShading: true }),
    new THREE.MeshStandardMaterial({ color: '#8f6a2c', roughness: 1, flatShading: true }),
  ];
  // 獸道的闊葉林 + 谷壁剪影（跟獸道同一種樹，一眼認得出目的地）
  for (let i = 0; i < 54; i++) {
    const z = -6 - Math.random() * 64;
    const x = (Math.random() < 0.5 ? -1 : 1) * (5 + Math.random() * 40);
    const h = 3.6 + Math.random() * 3;
    const t = new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.26, h, 7), bark);
    t.position.set(x, h / 2, z); g.add(t);
    for (let k = 0; k < 2; k++) {
      const c = new THREE.Mesh(new THREE.IcosahedronGeometry(1.7 - k * 0.4, 0),
        leafs[(Math.random() * leafs.length) | 0]);
      c.position.set(x + (Math.random() - 0.5) * 0.9, h + k * 0.85 - 0.2, z + (Math.random() - 0.5) * 0.9);
      g.add(c);
    }
  }
  const ridgeMat = new THREE.MeshStandardMaterial({ color: '#39543a', roughness: 1, flatShading: true });
  for (let i = 0; i < 8; i++) {
    const m = new THREE.Mesh(new THREE.ConeGeometry(18 + Math.random() * 14, 26 + Math.random() * 20, 5), ridgeMat);
    m.position.set((i - 3.5) * 26 + (Math.random() - 0.5) * 12, 9, -74 - Math.random() * 24);
    m.rotation.y = Math.random() * 3;
    g.add(m);
  }
  g.traverse(o => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
})();

/* ───────────────────────────────────────────── 傳送點 ── */
const westPortal = makePortalGlow(world, WEST_END.x, heightAt(WEST_END.x, WEST_END.z), WEST_END.z, 0xd8e8a0);
const northPortal = makePortalGlow(world, NORTH_END.x, heightAt(NORTH_END.x, NORTH_END.z), NORTH_END.z, 0x9fd8a0);

/* 道標（升級5）：兩端各一塊，牌面朝花田內 */
makeSignpost(world, WEST_END.x + 2.4, heightAt(WEST_END.x + 2.4, WEST_END.z + 2.6), WEST_END.z + 2.6, '往 無名之丘', Math.PI / 2);
makeSignpost(world, NORTH_END.x + 2.6, heightAt(NORTH_END.x + 2.6, NORTH_END.z + 2.2), NORTH_END.z + 2.2, '往 獸道', 0);

/* ─────────────── 邊界之外的遠山與林緣（升級1：遠景延伸） ── */
// 花田是全遊戲最亮最開闊的圖，邊界直接切天空反而最顯眼。
// 外圈鋪一層低緩的林緣稜線 —— 花海一路黃到腳下、遠處收進綠色的林子。
ridgeRing(world, {
  radius: 300, heightAt,
  height: [24, 44], color: 0x47584a, treeTops: true, seed: 19,
  gaps: [
    gapToward(WEST_END.x, WEST_END.z, 0.5),
    gapToward(NORTH_END.x, NORTH_END.z, 0.5),
  ],
});

/* ──────────────────────────────────────────── 靜態幾何合併 ── */
{
  const s = mergeStaticByMaterial(world, { cell: 58 });
  console.info(`[optimize] 太陽花田靜態合併：${s.before} → ${s.after} 個網格（合併成 ${s.merged}，保留 ${s.kept}）`);
}

/* ─────────────────────────────────────────────────────── 玩家 ── */
core.spawnPlayer({
  bounds: { hx: HALF + 8, hz: HALF + 8 },
  maxGrade: 1.05,
  spawn(from, ctrl) {
    if (from === 'trail') {
      ctrl.teleport(NORTH_END.x, NORTH_END.z + 8);
      ctrl.yaw = 0;                    // 面向南（走進花田）
      ctrl.camYaw = Math.PI;
    } else {
      ctrl.teleport(WEST_END.x + 8, WEST_END.z);
      ctrl.yaw = Math.PI / 2;          // 面向東
      ctrl.camYaw = -Math.PI / 2;
    }
  },
});
const ctrl = core.ctrl;

/* ─────────────────────────────── 幽香（對話） ── */
// 名牌住 labelScene：depthTest:false 的 sprite 進 GTAO 會變黑方塊
const npcMgr = new NPCManager(scene, core.labelScene);
npcMgr.setRoster(['yuuka'], REGION_BY_ID.sunflower, 300);
const dialogue = new Dialogue();

/* ─────────────────── 花妖精 + 成長系統 + 角色隨身裝備 ── */
const prog = core.createProgression();
// 花叢沿田埂散布 —— 玩家一定走田埂，怪窩擺在別處等於沒有怪
const PATCHES = (() => {
  const out = [];
  for (let i = 0; i < 12; i++) {
    const sm = PATHS.samples[(rand() * PATHS.samples.length) | 0];
    const a = rand() * Math.PI * 2, d = rr(9, 18);
    const x = sm.x + Math.cos(a) * d, z = sm.z + Math.sin(a) * d;
    if (Math.hypot(x - YUUKA.x, z - YUUKA.z) < 20) continue;   // 幽香腳邊沒人敢鬧
    out.push({ x, z, r: rr(8, 13) });
  }
  return out;
})();
const fairies = new FlowerFairies(scene, PATCHES, 7, {
  damage: 9,
  onAttack: (dmg) => kit.vitals.damage(dmg),
});
const mobs = progressMobs(fairies, prog, 'hinokami', '日之呼吸');

const kit = core.installKit({
  mobs,
  isBlocked: () => core.escMenu.isOpen || dialogue.active,
  onDeath: () => {
    ctrl.teleport(WEST_END.x + 8, WEST_END.z);
    HUD.toast('花妖精把你趕出了花田 —— 醒來時躺在田埂邊。');
  },
});

/* ───────────────────────────────────────────── ESC + 地圖 UI ── */
core.bindEsc();
core.installMapUI({
  current: 'sunflower',
  isBlocked: () => dialogue.active || core.escMenu.isOpen,
  minimap: {
    bounds: { minX: -182, maxX: 182, minZ: -182, maxZ: 182 },
    paths: PATHS,
    portals: [
      { x: WEST_END.x, z: WEST_END.z, label: '無名之丘', color: '#d8e8a0' },
      { x: NORTH_END.x, z: NORTH_END.z, label: '獸道', color: '#9fd8a0' },
    ],
  },
});

/* ───────────────────────────────────────────── 互動與提示 ── */
const nearWest = () => Math.hypot(ctrl.pos.x - WEST_END.x, ctrl.pos.z - WEST_END.z) < 5.2;
const nearNorth = () => Math.hypot(ctrl.pos.x - NORTH_END.x, ctrl.pos.z - NORTH_END.z) < 5.2;

window.addEventListener('keydown', (e) => {
  if (e.code !== 'KeyE' || core.escMenu.isOpen) return;
  if (dialogue.active) { dialogue.advance(); return; }
  if (!ctrl.locked) return;

  const npc = npcMgr.nearest;
  if (npc && npc.pos.distanceTo(ctrl.pos) <= TALK_RANGE) {
    ctrl.enabled = false;
    dialogue.open(npc.spec, npcMgr.nextTalk(npc), () => { ctrl.enabled = true; });
    return;
  }
  if (nearWest()) { HUD.showLoading('無名之丘 讀取中'); location.href = '../namelessHill/?from=sunflower'; return; }
  if (nearNorth()) { HUD.showLoading('獸道 讀取中'); location.href = '../trail/?from=sunflower'; }
});

/* ─────────────────────────────────────────────────── 主迴圈 ── */
const _sunDir = new THREE.Vector3();

// kit 結算之後、env 之前：怪物 AI、NPC、對話（原樣板的順序）
core.onUpdate((dt, rawDt, t) => {
  fairies.update(dt, t, ctrl.pos);
  npcMgr.update(t, ctrl.pos, camera);
  dialogue.update(dt);
});

// env 之後：追日要讀 env.update 完的太陽方位；傳送點呼吸與提示照舊
core.onLateUpdate((dt, rawDt, t) => {
  // 追日：花盤轉向太陽。太陽在地平線下時停在最後一個方位（夜裡花是低垂的）
  _sunDir.copy(env.sun.position).normalize();
  if (_sunDir.y > 0.02) {
    SUN.sunTurn(Math.atan2(_sunDir.x, _sunDir.z), -Math.asin(_sunDir.y) * 0.55);
  }

  westPortal.userData.update(t);
  northPortal.userData.update(t);

  if (dialogue.active) { HUD.prompt(null); return; }
  const npc = npcMgr.nearest;
  if (npc && npc.pos.distanceTo(ctrl.pos) <= TALK_RANGE) {
    HUD.prompt(`[ E ]  與 ${npc.spec.zh} 對話`);
  } else if (nearWest()) HUD.prompt('[ E ]  返回無名之丘');
  else if (nearNorth()) HUD.prompt('[ E ]  往獸道');
  else HUD.prompt(null);
});

core.start();

// debug handle（跟其他地圖同一套測試口徑）
window.__sunflower = core.debugHandle({
  heightAt, fairies, npcMgr, dialogue,
  PATHS, PATCHES, WEST_END, NORTH_END, YUUKA, sunflowers: SUN.count,
});
