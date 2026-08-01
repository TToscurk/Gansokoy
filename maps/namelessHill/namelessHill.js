// 無名之丘 —— 迷途竹林東側的一片起伏草丘，鈴蘭開滿整面山坡。
//
// 設定考據（Touhou Wiki）：無名の丘是幻想鄉東南方的丘陵，長滿鈴蘭
// （すずらん）—— 花很美，全株有毒。這裡的「怪」不是實體，而是花海本身：
// 走進去就持續中毒掉血，畫面邊緣泛起毒綠。要過丘就得沿著沒開花的
// 草徑走，或者硬闖付出血量代價。
//
// 技術上這是第一張「地形即敵人」的圖：沒有 mobs，戰鬥系統照掛（招式
// 能出，只是砍不到東西），威脅全交給 src/world/hazard.js 的 HazardZones。
//
// 美術上刻意不鋪石磚：使用者要求「不如就不要把石磚路做出來就維持草地」，
// 所以這裡的路是**踏出來的土痕**（低對比土色 ribbon）＋兩側草叢變密，
// 靠植被的疏密引導方向，而不是靠一條突兀的石板。

import * as THREE from 'three';
import { setGroundHeightFn } from '../../src/world/terrain.js';
import { WORLD } from '../../src/config.js';
import { buildCharacter } from '../../src/entities/model.js';
import { ACTIVE_PLAYABLE, DEFAULT_PLAYER } from '../../src/entities/roster.js';
import { PlayerController } from '../../src/player/controller.js';
import { Environment } from '../../src/world/environment.js';
import { makePortalGlow } from '../../src/world/portal.js';
import { HazardZones } from '../../src/world/hazard.js';
import { Progression } from '../../src/player/progression.js';
import { installLoadout } from '../../src/player/loadout.js';
import { installHUD, bindEscMenu } from '../../src/ui/hud.js';
import { loadQualityIdx, saveQualityIdx, applyBasicQuality, QUALITY_NAMES } from '../../src/world/quality.js';
import { mergeStaticByMaterial } from '../../src/core/optimize.js';
import { PathNet, catmullRom } from '../../src/world/pathnet.js';
import { GroundGrid, ribbonOnGrid } from '../../src/world/groundmesh.js';
import { scatterGrass } from '../../src/world/flora.js';

const HUD = installHUD({
  title: '無名之丘',
  subtitle: 'NAMELESS HILL · 迷途竹林 ⇄ 太陽花田',
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
renderer.toneMappingExposure = 1.08;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(68, innerWidth / innerHeight, 0.2, 620);
camera.rotation.order = 'YXZ';

// 丘陵是開闊地形：霧要淡，看得到遠處的起伏才有「丘」的感覺
const env = new Environment(scene, renderer, {
  fogMul: 0.62,
  shadowArea: 60,
  followSun: true,
});

let qualityIdx = loadQualityIdx(2);
const syncQuality = () => {
  applyBasicQuality(renderer, env.sun, qualityIdx);
  HUD.qualLabel.textContent = `畫質：${QUALITY_NAMES[qualityIdx]}`;
};
syncQuality();

/* ─────────────────────────────────────────────────── 地形高度場 ── */
// 220×220，真的是「丘」：三座圓丘疊在一片緩坡上，中間有谷。
const HALF = 110;
const WEST_END = { x: -98, z: 0 };     // 回迷途竹林
const EAST_END = { x: 98, z: 26 };     // 往太陽花田

let _seed = 20260802;
function rand() {
  _seed = (_seed * 1664525 + 1013904223) >>> 0;
  return _seed / 4294967296;
}
const rr = (a, b) => a + rand() * (b - a);

/** 三座圓丘（也是鈴蘭花海的所在 —— 花長在丘頂，谷地是安全的） */
const KNOLLS = [
  { x: -22, z: -44, r: 44, h: 15 },
  { x: 34, z: 8, r: 50, h: 19 },
  { x: -14, z: 62, r: 40, h: 13 },
];

function heightAt(x, z) {
  let h = Math.sin(x * 0.016) * 2.2 + Math.sin(z * 0.019 + 1.4) * 1.9;
  for (const k of KNOLLS) {
    const d = Math.hypot(x - k.x, z - k.z);
    if (d < k.r) {
      // 餘弦丘：邊緣切線為零，跟緩坡接得平順（不會有一圈折角）
      h += k.h * 0.5 * (1 + Math.cos((d / k.r) * Math.PI));
    }
  }
  // 邊界圍坡，一定要封頂
  const d = Math.max(Math.abs(x), Math.abs(z)) - (HALF - 12);
  if (d > 0) h += Math.min(16, d * d * 0.07);
  return h + Math.sin(x * 0.42 + z * 0.29) * 0.06;
}
setGroundHeightFn(heightAt);
WORLD.waterLevel = -999;

/* ───────────────────── 草徑：繞過三座丘的谷地（安全路線） ── */
// 這條路是「沒有鈴蘭的地方」—— 玩家沿著它可以零傷害橫越，
// 想抄近路直接翻丘就得吃毒。路線刻意在丘與丘之間穿。
const PATH_SEGMENTS = [
  {
    id: 'main', width: 5.4,
    pts: [
      [WEST_END.x, WEST_END.z], [-74, 6], [-52, 18], [-30, 22],
      [-8, 12], [10, -14], [30, -34], [52, -30], [70, -8],
      [82, 10], [EAST_END.x, EAST_END.z],
    ],
  },
  {
    // 支徑：往北邊丘腳的觀景點（沒有出口，純風景）
    id: 'lookout', width: 3.8,
    pts: [[-30, 22], [-36, 44], [-30, 66], [-14, 78]],
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
const meadowTex = canvasTex(256, (g, s) => {
  g.fillStyle = '#5d7440'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 3000; i++) {
    g.fillStyle = `rgba(${78 + Math.random() * 52},${96 + Math.random() * 46},${52 + Math.random() * 34},.5)`;
    g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 1 + Math.random() * 5, 0, 7); g.fill();
  }
  // 細碎的草莖筆觸
  for (let i = 0; i < 600; i++) {
    g.strokeStyle = `rgba(${100 + Math.random() * 50},${124 + Math.random() * 44},${64 + Math.random() * 26},.4)`;
    g.lineWidth = 1;
    const x = Math.random() * s, y = Math.random() * s;
    g.beginPath(); g.moveTo(x, y); g.lineTo(x + (Math.random() - 0.5) * 5, y - 5 - Math.random() * 5); g.stroke();
  }
}, 26, 26);
// 踏出來的土痕：跟草地只差一階明度，遠看是「草被踩禿的一條」而不是鋪面
const wornTex = canvasTex(256, (g, s) => {
  g.fillStyle = '#6d6f48'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 2000; i++) {
    g.fillStyle = `rgba(${104 + Math.random() * 46},${100 + Math.random() * 42},${70 + Math.random() * 30},.42)`;
    g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 1 + Math.random() * 4, 0, 7); g.fill();
  }
  // 邊緣殘草，讓路緣不是一條直線
  for (let i = 0; i < 300; i++) {
    g.fillStyle = `rgba(${88 + Math.random() * 30},${112 + Math.random() * 30},${56 + Math.random() * 24},.5)`;
    const y = Math.random() < 0.5 ? Math.random() * 26 : s - Math.random() * 26;
    g.fillRect(Math.random() * s, y, 2 + Math.random() * 5, 2 + Math.random() * 5);
  }
}, 3, 30);

const MAT = {
  meadow: new THREE.MeshStandardMaterial({ map: meadowTex, roughness: 1 }),
  worn: new THREE.MeshStandardMaterial({
    map: wornTex, roughness: 1,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
  }),
  stone: new THREE.MeshStandardMaterial({ color: '#8d8b80', roughness: 1 }),
  mossStone: new THREE.MeshStandardMaterial({ color: '#77806a', roughness: 1 }),
  wood: new THREE.MeshStandardMaterial({ color: '#7a6144', roughness: 0.92 }),
  darkWood: new THREE.MeshStandardMaterial({ color: '#4e3d2c', roughness: 0.95 }),
  bark: new THREE.MeshStandardMaterial({ color: '#4a3828', roughness: 1 }),
  foliage: new THREE.MeshStandardMaterial({ color: '#4f6b34', roughness: 1, flatShading: true }),
  bell: new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.82 }),   // 鈴蘭（instanceColor）
  stem: new THREE.MeshStandardMaterial({ color: '#4a6b32', roughness: 1 }),
  cloth: new THREE.MeshStandardMaterial({ color: '#b8442f', roughness: 0.95, side: THREE.DoubleSide }),
};

const world = new THREE.Group();
scene.add(world);

const colliders = [];
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
const GRID = new GroundGrid({ size: HALF * 2 + 120, seg: 160, heightAt });
const gSample = (x, z) => GRID.sample(x, z);
{
  const m = new THREE.Mesh(GRID.buildGeometry(), MAT.meadow);
  m.receiveShadow = true;
  world.add(m);
}
// 支徑從主徑岔出，起點重疊 —— lift 錯開 1.2 公分才不會兩層路面互閃
PATH_SEGMENTS.forEach((seg, i) => {
  ribbonOnGrid(world, catmullRom(seg.pts, 2.5), seg.width / 2, MAT.worn, gSample, 0.05 + i * 0.012);
});

/* ─────────────────────────────── 鈴蘭花海（＝這張圖的「怪」） ── */
/**
 * 花海範圍：三座丘的**上半部**。谷地與草徑周邊不長 ——
 * 玩家沿路走可以零傷害橫越，翻丘抄近路就得吃毒。
 *
 * 判定與視覺共用同一組圓（KNOLLS 的 0.72 半徑），玩家看到白花就是毒區，
 * 不會有「明明沒花卻在掉血」的落差。
 */
const FIELDS = KNOLLS.map(k => ({ x: k.x, z: k.z, r: k.r * 0.72 }));
/** 花海判定。草徑 3.5 公尺內挖空 —— 種花與中毒共用這一條，兩邊不會不一致。 */
const inField = (x, z) =>
  pathDist(x, z) >= 3.5 && FIELDS.some(f => Math.hypot(x - f.x, z - f.z) < f.r);

(function suzuran() {
  // 一株鈴蘭 = 一根莖 + 一串下垂的白鈴。用 InstancedMesh 分格子撒。
  const bellGeo = (() => {
    // 鈴鐺：半球 + 收口，六段夠了。
    // 半徑 0.1 是試出來的：0.055 時整片花海在畫面上只剩深綠的莖，
    // 白色讀不出來 —— 而「看到白花＝這裡有毒」是這張圖唯一的警示。
    const g = new THREE.SphereGeometry(0.1, 6, 5, 0, Math.PI * 2, 0, Math.PI * 0.62);
    g.rotateX(Math.PI);          // 開口朝下
    return g;
  })();
  const CELL = 26;
  const cells = new Map();
  const key = (x, z) => `${Math.floor(x / CELL)},${Math.floor(z / CELL)}`;

  let n = 0;
  for (let i = 0; i < 22000; i++) {
    // 直接在花海圓內撒（整圖亂撒的命中率太低 —— 獸道踩過這個坑）
    const f = FIELDS[(rand() * FIELDS.length) | 0];
    const a = rand() * Math.PI * 2, d = Math.sqrt(rand()) * f.r;
    const x = f.x + Math.cos(a) * d, z = f.z + Math.sin(a) * d;
    if (Math.abs(x) > HALF || Math.abs(z) > HALF) continue;
    if (pathDist(x, z) < 3.5) continue;          // 路上不長，路才是安全的
    // 邊緣稀疏、中心濃密：花海要有漸層的邊，不是一個硬圓
    if (rand() > 1 - (d / f.r) * 0.72) continue;
    const k = key(x, z);
    if (!cells.has(k)) cells.set(k, []);
    cells.get(k).push({ x, z, h: rr(0.4, 0.62), yaw: rand() * 6.28 });
    n++;
  }

  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler();
  const v = new THREE.Vector3(), s = new THREE.Vector3(), col = new THREE.Color();
  const stemGeo = new THREE.CylinderGeometry(0.012, 0.016, 1, 4);
  stemGeo.translate(0, 0.5, 0);

  let meshes = 0;
  for (const list of cells.values()) {
    // 每株五朵鈴 —— 鈴用一個 InstancedMesh 裝完整格
    const stems = new THREE.InstancedMesh(stemGeo, MAT.stem, list.length);
    const bells = new THREE.InstancedMesh(bellGeo, MAT.bell, list.length * 5);
    bells.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(list.length * 5 * 3), 3);
    meshes += 2;

    let bi = 0;
    list.forEach((p, i) => {
      const y = heightAt(p.x, p.z);
      e.set(0, p.yaw, rr(-0.12, 0.12));
      q.setFromEuler(e);
      s.set(1, p.h, 1);
      m4.compose(v.set(p.x, y, p.z), q, s);
      stems.setMatrixAt(i, m4);

      for (let b = 0; b < 5; b++) {
        const t = 0.34 + b * 0.15;
        const side = (b % 2 ? 1 : -1) * 0.06;
        s.set(1, 1, 1);
        e.set(0, p.yaw + b * 1.1, 0);
        q.setFromEuler(e);
        m4.compose(v.set(p.x + side, y + p.h * t, p.z + side * 0.6), q, s);
        bells.setMatrixAt(bi, m4);
        // 白裡帶一點點青，全白會像塑膠
        col.setHSL(0.24, 0.10 + rand() * 0.08, 0.86 + rand() * 0.10);
        bells.setColorAt(bi, col);
        bi++;
      }
    });
    bells.instanceColor.needsUpdate = true;
    world.add(stems, bells);
  }
  console.info(`[hill] 鈴蘭 ${n} 株（${meshes} 個 InstancedMesh，${cells.size} 個格子）`);
})();

/* ─────────────────────────────── 丘上的物件（少而準） ── */

/** 觀景點的孤木 —— 丘頂唯一的樹，是全圖的地標 */
function loneTree(cx, cz, h = 8) {
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  world.add(g);
  const trunk = cyl(0.3, 0.46, h, MAT.bark, 0, h / 2, 0, 8, g);
  trunk.rotation.z = 0.05;
  for (let k = 0; k < 5; k++) {
    const r = 3.4 - k * 0.45;
    const c = new THREE.Mesh(new THREE.IcosahedronGeometry(r, 0), MAT.foliage);
    c.position.set(rr(-1.2, 1.2), h * (0.78 + k * 0.14), rr(-1.2, 1.2));
    c.castShadow = true;
    g.add(c);
  }
  post(cx, cz, 0.6, y + h);
}
loneTree(-14, 80, 9);

/** 無主的墓標 —— 「無名」之丘：立著幾塊沒刻字的石 */
function nameless(cx, cz) {
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  g.rotation.y = rand() * 6.28;
  world.add(g);
  const h = rr(0.7, 1.25);
  const st = box(0.34, h, 0.16, MAT.mossStone, 0, h / 2, 0, g);
  st.rotation.z = rr(-0.14, 0.14);
  box(0.6, 0.14, 0.42, MAT.stone, 0, 0.07, 0, g);
  if (rand() < 0.4) {
    const bib = box(0.3, 0.24, 0.03, MAT.cloth, 0, h * 0.55, 0.1, g);
    bib.rotation.x = 0.1;
  }
  post(cx, cz, 0.34, y + h);
}
for (let i = 0; i < 14; i++) {
  const a = rand() * Math.PI * 2, d = rr(6, 30);
  const x = -22 + Math.cos(a) * d, z = -44 + Math.sin(a) * d;
  if (pathDist(x, z) < 3) continue;
  nameless(x, z);
}

/** 木製指路標 —— 岔路口告訴你哪邊是竹林、哪邊是花田 */
function signpost(cx, cz, rot) {
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  g.rotation.y = rot;
  world.add(g);
  cyl(0.09, 0.11, 2.3, MAT.darkWood, 0, 1.15, 0, 6, g);
  const a = box(1.5, 0.28, 0.07, MAT.wood, 0.6, 1.95, 0, g);
  a.rotation.y = 0.1;
  const b = box(1.5, 0.28, 0.07, MAT.wood, -0.6, 1.6, 0, g);
  b.rotation.y = Math.PI - 0.1;
  post(cx, cz, 0.2, y + 2.3);
}
signpost(-30, 22, 0.4);
signpost(70, -8, -0.9);

/* 散落的石塊：丘的骨頭露出來 */
for (let i = 0; i < 90; i++) {
  const x = rr(-HALF + 8, HALF - 8), z = rr(-HALF + 8, HALF - 8);
  if (pathDist(x, z) < 2.2) continue;
  const r = rr(0.3, 1.1);
  const rock = new THREE.Mesh(new THREE.IcosahedronGeometry(r, 0), MAT.mossStone);
  rock.position.set(x, heightAt(x, z) + r * 0.35, z);
  rock.rotation.set(rand() * 3, rand() * 3, rand() * 3);
  rock.castShadow = rock.receiveShadow = true;
  world.add(rock);
  if (r > 0.8) post(x, z, r * 0.8, heightAt(x, z) + r);
}

/* ────────────────────────────────── 草叢與雜草（滿丘） ── */
// 這張圖是草丘，草要撒滿而不是只沿路 —— 但花海裡少一點，
// 讓白色的鈴蘭讀得出來。
scatterGrass(world, {
  count: 5200, heightAt, cell: 40,
  place: () => {
    const x = rr(-HALF + 4, HALF - 4), z = rr(-HALF + 4, HALF - 4);
    if (pathDist(x, z) < 1.2) return null;   // 路緣留白，草才不會蓋到路上
    if (inField(x, z) && Math.random() < 0.62) return null;
    return [x, z];
  },
  baseColor: 0x63803c,
});
// 路兩側再加一圈密草，把「路」的邊界用植被畫出來（不用鋪面）
scatterGrass(world, {
  count: 1800, heightAt, cell: 40,
  place: () => {
    const sm = PATHS.samples[(Math.random() * PATHS.samples.length) | 0];
    const a = Math.random() * Math.PI * 2, d = 3.2 + Math.random() * 3.4;
    const x = sm.x + Math.cos(a) * d, z = sm.z + Math.sin(a) * d;
    if (pathDist(x, z) < 1.2) return null;
    if (Math.abs(x) > HALF || Math.abs(z) > HALF) return null;
    return [x, z];
  },
  baseColor: 0x6f8a42, scale: [0.9, 1.7],
});

/* ─────────────────── 兩端遠景：西看竹林、東看向日葵花田 ── */
(function bambooVista() {
  const g = new THREE.Group();
  g.position.set(WEST_END.x - 12, heightAt(WEST_END.x, WEST_END.z), WEST_END.z);
  world.add(g);
  const culmM = new THREE.MeshStandardMaterial({ color: '#7d9a4c', roughness: 0.8 });
  const leafM = new THREE.MeshStandardMaterial({ color: '#4f6b30', roughness: 1, flatShading: true });
  for (let i = 0; i < 120; i++) {
    const x = -2 - Math.random() * 52;
    const z = (Math.random() - 0.5) * 180;
    const h = 9 + Math.random() * 5;
    const c = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.12, h, 5), culmM);
    c.position.set(x, h / 2, z);
    g.add(c);
    const top = new THREE.Mesh(new THREE.IcosahedronGeometry(1.4, 0), leafM);
    top.position.set(x, h * 0.9, z);
    top.scale.set(1, 0.7, 1);
    g.add(top);
  }
  g.traverse(o => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
})();

(function sunflowerVista() {
  const g = new THREE.Group();
  g.position.set(EAST_END.x + 14, heightAt(EAST_END.x, EAST_END.z), EAST_END.z);
  world.add(g);
  // 一片黃到天邊的花田剪影
  const stemM = new THREE.MeshStandardMaterial({ color: '#4d6a2c', roughness: 1 });
  const headM = new THREE.MeshStandardMaterial({
    color: '#f2c832', roughness: 0.85, emissive: '#6a4a08', emissiveIntensity: 0.2,
  });
  const stemGeo = new THREE.CylinderGeometry(0.05, 0.07, 2.4, 4);
  stemGeo.translate(0, 1.2, 0);
  const headGeo = new THREE.CylinderGeometry(0.55, 0.55, 0.12, 8);
  const N = 320;
  const stems = new THREE.InstancedMesh(stemGeo, stemM, N);
  const heads = new THREE.InstancedMesh(headGeo, headM, N);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), v = new THREE.Vector3();
  const s = new THREE.Vector3(1, 1, 1);
  for (let i = 0; i < N; i++) {
    const x = 2 + Math.random() * 60, z = (Math.random() - 0.5) * 200;
    const yy = -1 - Math.random() * 3;
    m4.makeTranslation(v.set(x, yy, z));
    stems.setMatrixAt(i, m4);
    e.set(0.35, Math.PI, 0);            // 花盤朝西（向著玩家來的方向）
    q.setFromEuler(e);
    m4.compose(v.set(x, yy + 2.4, z), q, s);
    heads.setMatrixAt(i, m4);
  }
  g.add(stems, heads);
  // 遠處的丘與樹籬
  const hazeM = new THREE.MeshStandardMaterial({ color: '#c9c07a', roughness: 1, flatShading: true });
  for (let i = 0; i < 6; i++) {
    const m = new THREE.Mesh(new THREE.SphereGeometry(20 + Math.random() * 14, 8, 5), hazeM);
    m.position.set(58 + Math.random() * 30, -8, (i - 3) * 46);
    m.scale.y = 0.34;
    g.add(m);
  }
  g.traverse(o => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
})();

/* ───────────────────────────────────────────── 傳送點 ── */
const westPortal = makePortalGlow(world, WEST_END.x, heightAt(WEST_END.x, WEST_END.z), WEST_END.z, 0xa8c96a);
const eastPortal = makePortalGlow(world, EAST_END.x, heightAt(EAST_END.x, EAST_END.z), EAST_END.z, 0xf2c832);

/* ──────────────────────────────────────────── 靜態幾何合併 ── */
{
  const s = mergeStaticByMaterial(world, { cell: 50 });
  console.info(`[optimize] 無名之丘靜態合併：${s.before} → ${s.after} 個網格（合併成 ${s.merged}，保留 ${s.kept}）`);
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
ctrl.bounds = { hx: HALF + 6, hz: HALF + 6 };
// 丘身是走得上去的（翻丘抄近路是這張圖的選擇之一），只有邊界圍坡擋人。
// 圍坡最陡處約 1.5，丘頂最陡約 0.42 —— 門檻取中間。
ctrl.maxGrade = 0.95;

const FROM = new URLSearchParams(location.search).get('from');
if (FROM === 'sunflower') {
  ctrl.teleport(EAST_END.x - 6, EAST_END.z);
  ctrl.yaw = -Math.PI / 2;
  ctrl.camYaw = Math.PI / 2;
} else {
  ctrl.teleport(WEST_END.x + 6, WEST_END.z);
  ctrl.yaw = Math.PI / 2;          // 面向東
  ctrl.camYaw = -Math.PI / 2;
}

/* ─────────────────────── 成長 + 角色隨身裝備（無實體怪） ── */
const prog = new Progression({
  onLevelUp: (msg) => { HUD.toast(msg); kit.skills?.onLevelUp(); },
});
const kit = installLoadout({
  getSpec: () => spec, getCtrl: () => ctrl, scene, HUD, prog,
  isBlocked: () => escMenu.isOpen,
  onDeath: () => {
    ctrl.teleport(WEST_END.x + 6, WEST_END.z);
    HUD.toast('鈴蘭的毒讓你倒在丘上 —— 醒來時已經回到林口。');
  },
});
prog.renderBadge(spec.combat ? 'hinokami' : null, '日之呼吸');

/* ────────────────────────── 毒：鈴蘭花海（地形即敵人） ── */
const hazards = new HazardZones(kit.vitals);
for (const f of FIELDS) {
  // 8 dps：從丘的一側硬闖到另一側大約 12 秒，掉四分之一血 ——
  // 走得過去，但你會很清楚地知道自己不該這樣走。
  //
  // safe 用的是**跟種花完全同一個判斷式**（離草徑 3.5 公尺內不長花）。
  // 少了這一條，路穿過花海圓的那幾段就會「看不到花卻在掉血」。
  hazards.addCircle(f.x, f.z, f.r, 8, {
    color: '210,235,180',
    safe: (x, z) => pathDist(x, z) < 3.5,
  });
}
let poisonWarned = false;

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

const nearWest = () => Math.hypot(ctrl.pos.x - WEST_END.x, ctrl.pos.z - WEST_END.z) < 5.2;
const nearEast = () => Math.hypot(ctrl.pos.x - EAST_END.x, ctrl.pos.z - EAST_END.z) < 5.2;

window.addEventListener('keydown', (e) => {
  if (e.code !== 'KeyE' || !ctrl.locked || escMenu.isOpen) return;
  if (nearWest()) { HUD.showLoading('迷途竹林 讀取中'); location.href = '../bamboo/?from=namelessHill'; return; }
  if (nearEast()) { HUD.showLoading('太陽花田 讀取中'); location.href = '../sunflower/?from=namelessHill'; }
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
  hazards.update(dt, ctrl.pos);

  // 第一次踏進花海時說一次原因 —— 不然玩家只知道在掉血，不知道為什麼
  if (!poisonWarned && inField(ctrl.pos.x, ctrl.pos.z)) {
    poisonWarned = true;
    HUD.toast('鈴蘭全株有毒 —— 花海裡待久了會撐不住。沿著草徑走。', 4200);
  }

  env.update(dt, camera.position);
  westPortal.userData.update(t);
  eastPortal.userData.update(t);

  if (nearWest()) HUD.prompt('[ E ]  返回迷途竹林');
  else if (nearEast()) HUD.prompt('[ E ]  往太陽花田');
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
window.__hill = {
  renderer, scene, camera, ctrl, THREE, heightAt, env, colliders, prog, hazards,
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
  PATHS, FIELDS, KNOLLS, WEST_END, EAST_END, inField,
};
