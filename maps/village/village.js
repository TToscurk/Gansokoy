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
//
// ※ 已改用 GameCore（src/core/GameCore.js）：renderer / Environment /
//    畫質 / 玩家 / 成長 / ESC / 大小地圖 / 主迴圈全部由共用層提供，
//    這個檔案只剩人里獨有的東西（整合書・階段 D）。行為與遷移前逐字相同
//    —— 包含「名牌住獨立場景、主畫面之後單獨畫」與客製的 keydown。

import * as THREE from 'three';
import { makePortalGlow } from '../../src/world/portal.js';
import { VillagerCrowd } from '../../src/entities/villagers.js';
import { spawnAllNPCs } from '../../src/entities/shrine-spawn.js';
import { SceneEditor } from '../../src/ui/scene-editor.js';
import { mergeStaticByMaterial } from '../../src/core/optimize.js';
import { texMaps } from '../../src/world/texgen.js';
import { applyTriplanar } from '../../src/world/triplanar.js';
import { rockTexture } from '../../src/world/terraintex.js';
import { buildLUT, LUT_PRESETS } from '../../src/world/lut.js';
import { GroundGrid, decalOnGrid } from '../../src/world/groundmesh.js';
import { makeSignpost } from '../../src/world/signpost.js';
import { scatterGrass } from '../../src/world/flora.js';
import { bootMap } from '../../src/core/GameCore.js';

const core = bootMap({
  hud: {
    title: '人間之里',
    subtitle: 'HUMAN VILLAGE',
    keys: [
      ['WASD / 方向鍵', '移動'], ['滑鼠', '轉視角'], ['滾輪', '縮放'],
      ['Shift', '衝刺'], ['Space', '跳躍'],
      ['E', '互動'], ['K', '技能'], ['M', '地圖'], ['P', '場景編輯'], ['ESC', '選單'],
    ],
    flyKeys: [['F', '飛行'], ['Ctrl/C', '下降']],
    combatKeys: [['左鍵', '出招'], ['長按左鍵', '日之呼吸・全型'], ['R', '拔刀/納刀'], ['1 ~ 4', '技']],
  },
  // fov 70（不是預設的 68）、far 900（不是 700）：里是開闊的盆地，看得到街尾。
  // near 拉到 0.2：深度緩衝的精度幾乎全由 near/far 的比值決定，0.08→0.2
  // 等於把整條深度範圍的精度拉高 2.5 倍，鋪地物件與共面幾何就不容易閃。
  // 第三人稱相機離視點最近也有 1.2 公尺（見 controller 的 _updateCamera），
  // 不會有東西近到被 near 切掉。
  camera: { fov: 70, near: 0.2, far: 900 },
  // 這張圖原本沒有指定 toneMappingExposure ＝ three 的預設 1（不是 GameCore
  // 的 1.06）—— 顯式傳 1 才是「行為完全不變」。
  exposure: 1,
  // 里是開闊的盆地：霧比獸道淡，看得到街尾與遠山
  env: { fogMul: 0.75, shadowArea: 78, followSun: true },
  // postFX 維持 basic（無 composer），畫質走 applyBasicQuality 的三檔。
});
const { HUD, renderer, scene, camera, world, colliders } = core;
const { box, cyl, post, block, walkBlock } = core;

/* ─────────────────────────────────────────────────── 地形高度場 ── */
// 里蓋在平坦的盆地上：主街完全水平，外圍緩緩抬起成田埂與矮丘。
// 里的規模。參考 Touhou Wiki 與明治期町屋聚落的街廓尺度：
// 網格狀的街廓、主街貫穿南北、橫街切出街區，外圍是水田與矮丘。
const VILLAGE_R = 175;     // 里的半徑（超過這裡開始爬坡）
const GATE_Z = -168;       // 北端里門（通獸道 → 博麗神社）
const SOUTH_GATE_Z = 250;  // 南端里門（里的南界，不是出口）
// 西南門：橫街 z=100 往西的延伸，通香霖堂 → 魔法之森。
// 位置挑在里的平坦帶內（heightAt 的橢圓 d<175），門外才不會卡在爬坡上。
const SW_GATE = { x: -126, z: 100 };
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
// waterLevel 省略 ＝ -999：這張圖沒有水域（見 main.js 同名註解）
core.setTerrain(heightAt);

/* ───────────────────────────────────────────────────────── 材質 ── */
function canvasTex(size, draw, rx = 1, ry = 1) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  draw(c.getContext('2d', { willReadFrequently: true }), size);
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
  ground: new THREE.MeshStandardMaterial({ ...texMaps(groundTex, [0.86, 1.0]), roughness: 1 }),
  // polygonOffset：石板路是鋪在地面上的薄薄一層，深度值跟地面非常接近。
  // 把它往鏡頭方向偏一點，地面就永遠搶不贏它，路草交界不會閃。
  road: new THREE.MeshStandardMaterial({
    ...texMaps(stoneRoadTex, [0.86, 1.0]), roughness: 1,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
  }),
  plaster: new THREE.MeshStandardMaterial({ ...texMaps(plasterTex, [0.81, 1.0]), roughness: 1, color: '#f2ead6' }),
  wood: new THREE.MeshStandardMaterial({ ...texMaps(woodTex, [0.76, 0.95]), roughness: 1, color: '#c8a880' }),
  darkWood: new THREE.MeshStandardMaterial({ ...texMaps(woodTex, [0.81, 1.0]), roughness: 1, color: '#6a5038' }),
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

/* world / colliders / block / walkBlock / post / box / cyl 全部由 GameCore
 * 提供（見檔頭的解構）。碰撞盒 —— 所有看得見的實體都要能擋人，尺寸貼合模型；
 * walkBlock 是可站上去的平台（橋面、攤位桌、像座），跳上去就站著不會被推開。
 * ※ 本檔所有 cyl 呼叫都顯式帶 seg，不吃預設值。 */

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
/** 鋪地物件（路、田）。實作見 src/world/groundmesh.js —— 每個頂點都
 * 取「地面網格實際渲染的高度」再抬 lift，這是路草交界不閃的根治。 */
function groundDecal(w, d, x, z, mat, lift = 0.05) {
  return decalOnGrid(world, w, d, x, z, mat, gSample, lift);
}

/* 地面網格 + 貼地查詢（見 src/world/groundmesh.js） */
const GRID = new GroundGrid({ size: 460, seg: 120, heightAt });
const gSample = (x, z) => GRID.sample(x, z);
{
  const m = new THREE.Mesh(GRID.buildGeometry(), MAT.ground);
  m.receiveShadow = true;
  world.add(m);

  /* 三平面貼圖（升級書第 3 章）。從正上方投影的 UV 在斜面上會被拉成
   * 一條一條 —— 改用世界座標三軸取樣，陡坡自動由側面那兩張主導。
   *
   * scale 用原本的 repeat 換算，密度才不會順便被放大或縮小；原本的
   * repeat 是 26×26（非等向），三平面只吃一個尺度，取幾何平均。
   *
   * 低畫質不套：每像素多採樣兩次，低階機划不來，退回原本的單軸 UV。 */
  const TRI_SCALE = Math.sqrt(26 * 26) / GRID.size;
  let triOn = null;
  const syncTri = (idx) => {
    const want = idx >= 1;                 // 0=低 1=中 2=高
    if (want === triOn) return;
    triOn = want;
    if (want) {
      applyTriplanar(MAT.ground, {
        scale: TRI_SCALE, sharp: 4,
        rock: texMaps(rockTexture({ base: '#7b756a' }), [0.8, 0.98]),
        slope: [0.34, 0.60],
      });
    } else {
      MAT.ground.onBeforeCompile = () => {};
      MAT.ground.customProgramCacheKey = () => 'tri:off';
      MAT.ground.map.repeat.set(26, 26);
      MAT.ground.normalMap?.repeat.set(26, 26);
      MAT.ground.roughnessMap?.repeat.set(26, 26);
      MAT.ground.needsUpdate = true;
    }
  };
  core.onQualityChange(syncTri);
  // GameCore 建構時就跑過一次 syncQuality()，那時這張圖還沒註冊，
  // 初始狀態要自己補，不能等下一次切畫質
  syncTri(core.quality.idx);

}

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
  // 橋面（微拱）。每片橋板各自是一顆 walk 平台 —— 微拱的頂面高度
  // 沿橋身變化，一顆大盒子蓋不住；一片一顆，走上去才是「一級一級」。
  for (let i = -3; i <= 3; i++) {
    const t = i / 3;
    const y = 0.5 - t * t * 0.35;
    box(3.0, 0.34, 8.4, MAT.stone, i * 3.0, y, 0, g);
    colliders.push({ x: cx + i * 3.0, z, y: y - 0.17, h: 0.34, hw: 1.5, hd: 4.2, walk: true });
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
  // 欄杆擋側落（別從橋邊掉進河裡）；橋面本身放行 —— 上面的 walk 平台
  for (const sd of [-1, 1]) {
    colliders.push({ x: cx, z: z + sd * 3.9, y: 0.15, h: 1.3, hw: 10.2, hd: 0.28 });
  }
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

/* 小巷側的第二排民家 —— 使用者回報里還是很空曠。街廓原本只有南北
 * 兩列面朝橫街的屋子，東西向（面朝小巷）是空的；補上這一排之後
 * 街廓才是「四邊都有房子、中間是後院」的完整形。 */
(function laneHouses() {
  const clearOf = (x, z) => BLOCK_KEEP_OUT.every(k => Math.hypot(x - k.x, z - k.z) > k.r);
  for (const lx of LANE_X) {
    for (const side of [-1, 1]) {
      const hx = lx + side * 9.5;
      for (let zi = 0; zi < CROSS_Z.length - 1; zi++) {
        const z0 = CROSS_Z[zi] + 14, z1 = CROSS_Z[zi + 1] - 14;
        if (z1 - z0 < 14) continue;
        const n = Math.max(1, Math.floor((z1 - z0) / 15));
        for (let k = 0; k < n; k++) {
          const z = z0 + (k + 0.5) * ((z1 - z0) / n) + (Math.random() - 0.5) * 2;
          if (!clearOf(hx, z)) continue;
          if (Math.abs(hx - riverX(z)) < 14) continue;
          if (Math.abs(hx) < 19) continue;
          if (Math.random() < 0.3) continue;            // 留些空隙當菜園
          const r = Math.random();
          house({
            x: hx, z, w: 7 + Math.random() * 2, d: 5.5 + Math.random() * 1.5,
            rot: -side * Math.PI / 2 + (Math.random() - 0.5) * 0.05,
            roof: r < 0.4 ? 'thatch' : 'tile',
            style: r > 0.92 ? 'kura' : (r > 0.82 ? 'two' : 'machiya'),
          });
        }
      }
    }
  }
})();

/* 河畔的倉庫與船板 —— 河岸不該只有樹 */
(function riverSheds() {
  for (let i = 0; i < 6; i++) {
    let z = -150 + i * 62 + (Math.random() - 0.5) * 16;
    // 別壓住橋的引道：隨機抖動曾把一間倉庫剛好蓋在 z=40 橋的西岸
    // 橋頭上，把整條過河動線堵死 —— 落點離橋街太近就往外推。
    for (const bz of [-70, 40, 165]) {
      if (Math.abs(z - bz) < 9) z = bz + (z >= bz ? 9 : -9);
    }
    const x = riverX(z) - 13;
    house({
      x, z, w: 6 + Math.random() * 1.5, d: 5, h: 3.2,
      rot: Math.PI / 2, roof: 'thatch', style: 'machiya',
    });
    // 河邊的小板橋（純視覺，不能走）
    const plank = box(1.6, 0.14, 4.2, MAT.wood, riverX(z) - 3.5, -0.3, z + 6);
    plank.rotation.z = 0.06;
  }
})();

/* 火の見櫓 —— 參考圖裡那座高塔。四腳收分、上有平台小屋頂與吊鐘，
 * 全里最高的建物，走在街上抬頭就能定位廣場。 */
(function watchtower() {
  const TX = 22, TZ = -34, y = heightAt(TX, TZ);
  const g = new THREE.Group();
  g.position.set(TX, y, TZ);
  world.add(g);
  const H = 14;
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    const leg = cyl(0.16, 0.24, H, MAT.darkWood, sx * 1.5, H / 2, sz * 1.5, 7, g);
    leg.rotation.z = -sx * 0.075;
    leg.rotation.x = sz * 0.075;
  }
  // 橫撐三層
  for (const hy of [3.5, 7, 10.5]) {
    const w = 3.4 - hy * 0.12;
    box(w, 0.16, 0.16, MAT.darkWood, 0, hy, w / 2, g);
    box(w, 0.16, 0.16, MAT.darkWood, 0, hy, -w / 2, g);
    box(0.16, 0.16, w, MAT.darkWood, w / 2, hy, 0, g);
    box(0.16, 0.16, w, MAT.darkWood, -w / 2, hy, 0, g);
  }
  // 平台 + 欄杆 + 小屋頂
  box(3.2, 0.22, 3.2, MAT.wood, 0, H, 0, g);
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    cyl(0.06, 0.06, 0.9, MAT.darkWood, sx * 1.4, H + 0.45, sz * 1.4, 6, g);
  }
  box(3.0, 0.08, 0.08, MAT.darkWood, 0, H + 0.9, 1.4, g);
  box(3.0, 0.08, 0.08, MAT.darkWood, 0, H + 0.9, -1.4, g);
  box(0.08, 0.08, 3.0, MAT.darkWood, 1.4, H + 0.9, 0, g);
  box(0.08, 0.08, 3.0, MAT.darkWood, -1.4, H + 0.9, 0, g);
  const roof = new THREE.Mesh(new THREE.ConeGeometry(2.6, 1.6, 4), MAT.roofTile);
  roof.position.y = H + 2.1; roof.rotation.y = Math.PI / 4;
  roof.castShadow = true; g.add(roof);
  // 吊鐘
  const bell = new THREE.Mesh(new THREE.SphereGeometry(0.34, 10, 8, 0, Math.PI * 2, 0, Math.PI * 0.72), MAT.stone);
  bell.position.y = H + 1.1; bell.castShadow = true; g.add(bell);
  block(TX, TZ, 3.6, 3.6, y + H + 2.6);
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
  walkBlock(DX, DZ, 11, 11, y + 0.5);
  walkBlock(DX, DZ, 8.4, 8.4, y + 1.0);
  walkBlock(DX, DZ, 6.2, 6.2, y + 1.6);

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
  walkBlock(x, z, 3.2 * cs + 1.8 * sn, 3.2 * sn + 1.8 * cs, heightAt(x, z) + 1.0);
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

/* ─────────────────────────────────────── 里外的農家聚落 ── */
/**
 * 里的東西兩側（|x| 120~170）原本只有貼地的水田 —— 一片平的色塊，
 * 站在里的邊緣往外看就是「什麼都沒有」。這裡補上真正立起來的東西：
 * 農家、納屋、稻架、土藏、水車小屋、里外的小墓地。
 *
 * 全部沿用里內的材質，靜態合併時會跟里內的建築併進同一批。
 */

/** 農家：茅葺主屋 + 納屋 + 曬穀場 + 竹垣 */
function farmstead(cx, cz, rot = 0) {
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  g.rotation.y = rot;
  world.add(g);

  // 主屋：入母屋造的茅葺屋頂，比里內的町家矮胖
  const W = 10, D = 7.5, H = 3.4;
  box(W + 1, 0.4, D + 1, MAT.stone, 0, 0.2, 0, g);
  box(W, H, D, MAT.plaster, 0, 0.4 + H / 2, 0, g);
  for (const s of [-1, 1]) {
    const slope = box(W + 3.4, 0.4, D * 0.72, MAT.roofThatch, 0, 0.4 + H + 1.5, s * D * 0.24, g);
    slope.rotation.x = s * 0.62;
  }
  box(W + 3.8, 0.55, 1.3, MAT.roofThatch, 0, 0.4 + H + 2.7, 0, g);
  // 正面：格子門 + 一扇紙窗
  box(2.0, 2.2, 0.1, MAT.darkWood, -1.4, 1.5, D / 2 + 0.02, g);
  box(1.8, 1.4, 0.08, MAT.paper, 1.9, 2.0, D / 2 + 0.02, g);
  block(cx, cz, W + 0.6, D + 0.6, y + H + 3);

  // 納屋：矮一截的板倉，開口朝主屋
  const nx = W / 2 + 5.5;
  box(6.5, 2.8, 5, MAT.wood, nx, 1.4, -2, g);
  for (const s of [-1, 1]) {
    const sl = box(7.6, 0.28, 3.4, MAT.roofThatch, nx, 3.3, -2 + s * 1.5, g);
    sl.rotation.x = s * 0.55;
  }
  box(7.8, 0.32, 0.36, MAT.roofThatch, nx, 3.72, -2, g);
  box(2.2, 2.2, 0.08, MAT.darkWood, nx, 1.1, 0.52, g);
  // 納屋的碰撞盒要用旋轉後的外接框（跟廢屋同一套近似）
  {
    const cs = Math.abs(Math.cos(rot)), sn = Math.abs(Math.sin(rot));
    const lx = cx + nx * Math.cos(rot) + -2 * Math.sin(rot);
    const lz = cz - nx * Math.sin(rot) + -2 * Math.cos(rot);
    block(lx, lz, 7 * cs + 5.4 * sn, 7 * sn + 5.4 * cs, y + 3.8);
  }

  // 稻架（はさ）：曬稻穀的木架，兩根柱撐一根橫桿，上面掛滿稻束
  for (let k = 0; k < 2; k++) {
    const hz = 6.5 + k * 3.2;
    for (const s of [-1, 1]) {
      cyl(0.09, 0.11, 2.4, MAT.darkWood, s * 3.6, 1.2, hz, 6, g);
    }
    const bar = cyl(0.07, 0.07, 7.6, MAT.darkWood, 0, 2.2, hz, 6, g);
    bar.rotation.z = Math.PI / 2;
    for (let i = -3; i <= 3; i++) {
      const sheaf = cyl(0.16, 0.1, 1.1, MAT.roofThatch, i * 1.05, 1.62, hz, 5, g);
      sheaf.rotation.z = (i % 2) * 0.06;
    }
    post(cx + Math.cos(rot) * 3.6 + Math.sin(rot) * hz,
         cz - Math.sin(rot) * 3.6 + Math.cos(rot) * hz, 0.2, y + 2.4);
  }

  // 竹垣：圍住院子的三面
  for (let i = 0; i < 12; i++) {
    cyl(0.055, 0.065, 1.3, MAT.wood, -W / 2 - 1.5, 0.65, -3 + i * 1.25, 5, g);
  }
}

/** 土藏：白漆喰 + 海鼠壁，村裡最耐火的建築，糧倉用 */
function kura(cx, cz, rot = 0) {
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  g.rotation.y = rot;
  world.add(g);
  box(6.4, 0.5, 5.4, MAT.stone, 0, 0.25, 0, g);
  box(5.8, 4.6, 4.8, MAT.kura, 0, 2.8, 0, g);
  box(5.9, 1.3, 4.9, MAT.namako, 0, 1.15, 0, g);        // 下半的海鼠壁
  for (const s of [-1, 1]) {
    const sl = box(7.2, 0.3, 3.3, MAT.roofTile, 0, 5.6, s * 1.5, g);
    sl.rotation.x = s * 0.56;
  }
  box(7.4, 0.36, 0.42, MAT.roofTile, 0, 6.05, 0, g);
  box(1.5, 2.1, 0.14, MAT.darkWood, 0, 1.6, 2.45, g);   // 厚重的土戸
  const cs = Math.abs(Math.cos(rot)), sn = Math.abs(Math.sin(rot));
  block(cx, cz, 6.4 * cs + 5.4 * sn, 6.4 * sn + 5.4 * cs, y + 6.1);
}

/** 水車小屋：架在東河上的碾米小屋，水輪會轉 */
const waterWheels = [];
function waterMill(z) {
  const rx = riverX(z);
  const cx = rx - 8.5;
  const y = heightAt(cx, z);
  const g = new THREE.Group();
  g.position.set(cx, y, z);
  world.add(g);
  box(5.6, 3.2, 5, MAT.wood, 0, 1.6, 0, g);
  for (const s of [-1, 1]) {
    const sl = box(6.8, 0.3, 3.4, MAT.roofThatch, 0, 3.75, s * 1.5, g);
    sl.rotation.x = s * 0.56;
  }
  box(7, 0.36, 0.4, MAT.roofThatch, 0, 4.2, 0, g);
  box(1.4, 2, 0.08, MAT.darkWood, -2.83, 1.2, 0, g);
  block(cx, z, 5.8, 5.2, y + 4.2);

  // 水輪：立在靠河的那一側，每幀轉。userData.noMerge 讓它躲過靜態合併。
  const wheel = new THREE.Group();
  wheel.position.set(3.6, 1.5, 0);
  wheel.userData.noMerge = true;
  g.add(wheel);
  const hub = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.22, 1.2, 8), MAT.darkWood);
  hub.rotation.z = Math.PI / 2;
  wheel.add(hub);
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * Math.PI * 2;
    const spoke = new THREE.Mesh(new THREE.BoxGeometry(0.1, 2.9, 0.1), MAT.darkWood);
    spoke.position.set(0, 0, 0);
    spoke.rotation.x = a;
    wheel.add(spoke);
    const paddle = new THREE.Mesh(new THREE.BoxGeometry(1.1, 0.7, 0.09), MAT.wood);
    paddle.position.set(0, Math.cos(a) * 1.5, Math.sin(a) * 1.5);
    paddle.rotation.x = a;
    paddle.castShadow = true;
    wheel.add(paddle);
  }
  for (const s of [-1, 1]) {
    const rim = new THREE.Mesh(new THREE.TorusGeometry(1.5, 0.07, 5, 14), MAT.darkWood);
    rim.position.x = s * 0.5;
    rim.rotation.y = Math.PI / 2;
    wheel.add(rim);
  }
  waterWheels.push(wheel);
  post(cx + 3.6, z, 1.7, y + 3.2);
}

/** 里外的小墓地：一排無名的石塔 */
function graveyard(cx, cz) {
  const y0 = heightAt(cx, cz);
  for (let i = 0; i < 16; i++) {
    const x = cx + ((i % 4) - 1.5) * 2.6;
    const z = cz + (Math.floor(i / 4) - 1.5) * 2.8;
    const y = heightAt(x, z);
    const h = 0.75 + (i % 3) * 0.22;
    const st = box(0.32, h, 0.2, MAT.stone, x, y + h / 2, z);
    st.rotation.y = (i % 5) * 0.08;
    box(0.56, 0.14, 0.4, MAT.stone, x, y + 0.07, z);
    post(x, z, 0.3, y + h);
  }
  // 入口的地藏
  const gy = heightAt(cx, cz - 6);
  cyl(0.3, 0.36, 0.2, MAT.stone, cx, gy + 0.1, cz - 6, 8);
  cyl(0.18, 0.22, 0.66, MAT.stone, cx, gy + 0.53, cz - 6, 8);
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.17, 10, 8), MAT.stone);
  head.position.set(cx, gy + 0.97, cz - 6);
  head.castShadow = true;
  world.add(head);
  const bib = box(0.3, 0.26, 0.04, MAT.cloth, cx, gy + 0.72, cz - 5.82);
  bib.rotation.x = 0.12;
  post(cx, cz - 6, 0.36, gy + 1.1);
  void y0;
}

// 西側農家聚落（空曠度分析裡最空的一帶：x ≈ -160 ~ -125）
farmstead(-146, -30, Math.PI * 0.52);
farmstead(-140, 30, Math.PI * 0.48);
farmstead(-152, 96, Math.PI * 0.55);
farmstead(-134, -104, Math.PI * 0.45);
kura(-124, -62, Math.PI * 0.5);
kura(-130, 132, Math.PI * 0.5);
graveyard(-158, -140);

// 東側（x ≈ 120 ~ 165）
farmstead(148, -34, -Math.PI * 0.5);
farmstead(140, 46, -Math.PI * 0.46);
farmstead(152, -112, -Math.PI * 0.54);
farmstead(134, 122, -Math.PI * 0.5);
kura(126, 4, -Math.PI * 0.5);
kura(144, -74, -Math.PI * 0.5);

// 東河上的水車小屋（河在東側，riverX 決定位置）
waterMill(-46);
waterMill(118);

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

/**
 * 西南門：跟南北兩座同一款冠木門，只是轉九十度（門面朝 ±x）。
 * 沒有把 villageGate 改成吃軸向 —— 那會動到已經蓋好、已經驗過的兩座門。
 * @param {number} gx @param {number} gz 門的位置
 */
function westGate(gx, gz) {
  const y = heightAt(gx, gz);
  for (const s of [-1, 1]) {
    cyl(0.42, 0.48, 6.2, MAT.darkWood, gx, y + 3.1, gz + s * 4.4, 10);
    post(gx, gz + s * 4.4, 0.55, y + 6.2);
  }
  box(0.8, 0.7, 11, MAT.darkWood, gx, y + 6.0, gz);
  box(0.6, 0.45, 9.4, MAT.darkWood, gx, y + 5.0, gz);
  for (const s of [-1, 1]) {
    const slope = box(2.2, 0.3, 12, MAT.roofTile, gx + s * 0.9, y + 6.7, gz);
    slope.rotation.z = s * 0.5;
  }
  // 門兩側的土牆（往南北兩邊各拉三段，門口才不是空的）
  for (const sd of [-1, 1]) {
    for (let k = 0; k < 3; k++) {
      const wz = gz + sd * (17 + k * 20);
      box(0.7, 2.4, 20, MAT.plaster, gx, y + 1.2, wz);
      box(1.0, 0.25, 20.4, MAT.roofTile, gx, y + 2.45, wz);
      block(gx, wz, 0.7, 20, y + 2.45);
    }
  }
  // 門內側的注連繩結界柱（內側 = +x，往里的方向）
  for (const s of [-1, 1]) {
    cyl(0.16, 0.18, 1.6, MAT.stone, gx + 2.6, y + 0.8, gz + s * 6.4, 8);
    post(gx + 2.6, gz + s * 6.4, 0.22, y + 1.6);
  }
}
westGate(SW_GATE.x, SW_GATE.z);

// 橫街 z=100 往西接到西南門的一段土路（橫街本身只鋪到 |x|≈98）
groundDecal(34, 7, (SW_GATE.x + 3 - 98) / 2, SW_GATE.z, MAT.road, 0.062);

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

/* ─────────────────────────────── 傳送點（北端獸道、西南香霖堂） ── */
// 里對外有兩個出口：北門的獸道，西南門的香霖堂。要去迷途竹林仍得走回
// 獸道再往東南岔 —— 里跟竹林之間沒有直達的路，那條分岔才有存在感。
// 南門保留成建築（里的南界），但不是傳送點。
const trailPortal = makePortalGlow(world, 0, heightAt(0, GATE_Z - 6), GATE_Z - 6);
const KOURIN_PORTAL = { x: SW_GATE.x - 6, z: SW_GATE.z };
const kourinPortal = makePortalGlow(
  world, KOURIN_PORTAL.x, heightAt(KOURIN_PORTAL.x, KOURIN_PORTAL.z), KOURIN_PORTAL.z, 0xe0c88a,
);

/* 道標（升級5）：兩個出口各一塊，牌面朝里內 */
makeSignpost(world, 3.2, heightAt(3.2, GATE_Z - 3), GATE_Z - 3, '往 獸道', 0);
makeSignpost(world, KOURIN_PORTAL.x + 4, heightAt(KOURIN_PORTAL.x + 4, KOURIN_PORTAL.z - 2.6), KOURIN_PORTAL.z - 2.6, '往 香霖堂', Math.PI / 2);

/* ─────────────────────────────── 草叢與雜草（街廓後院、河岸、里外） ── */
scatterGrass(world, {
  count: 3200, heightAt,
  place: () => {
    const a = Math.random() * Math.PI * 2;
    const r = Math.sqrt(Math.random()) * 215;
    const x = Math.cos(a) * r, z = Math.sin(a) * r * 1.3;
    // 每條路的排除半寬都比路面本身多留 1.2 公尺：一叢草放大後半徑約
    // 0.5 公尺，貼著路緣種的話葉尖會蓋到路面上 —— 那正是「草地蓋到路」。
    if (Math.abs(x) < 8.2) return null;                                 // 主街
    if (CROSS_Z.some(cz => Math.abs(z - cz) < 6.7) && Math.abs(x) < 102) return null;  // 橫街
    if (LANE_X.some(lx => Math.abs(x - lx) < 5.7) && z > -165 && z < 205) return null; // 小巷
    if (Math.abs(x - riverX(z)) < 10.7) return null;                    // 河道
    // 建物腳下不長（快篩：只掃矩形碰撞盒）
    for (const c of colliders) {
      if (c.hw != null && Math.abs(x - c.x) < c.hw + 0.9 && Math.abs(z - c.z) < c.hd + 0.9) return null;
    }
    return [x, z];
  },
  baseColor: 0x5e7a38,
});

/* ────────────── 北門外的獸道遠景（傳送點看得到下一張圖） ── */
(function trailVista() {
  const g = new THREE.Group();
  world.add(g);
  // 土徑從門口一路蜿蜒進林子
  const pathMat = new THREE.MeshStandardMaterial({
    map: woodTex, color: '#8a7554', roughness: 1,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
  });
  groundDecal(6, 56, 3, GATE_Z - 34, pathMat, 0.06);
  // 夾道的闊葉樹（跟獸道同款）
  for (let i = 0; i < 40; i++) {
    const z = GATE_Z - 12 - Math.random() * 50;
    const x = (Math.random() < 0.5 ? -1 : 1) * (5 + Math.random() * 30);
    tree(x + 3, z, 0.9 + Math.random() * 0.8, MAT.leaf);
  }
  // 更遠處的谷壁山稜剪影
  const ridgeMat = new THREE.MeshStandardMaterial({ color: '#37503a', roughness: 1, flatShading: true });
  for (let i = 0; i < 8; i++) {
    const m = new THREE.Mesh(new THREE.ConeGeometry(18 + Math.random() * 16, 26 + Math.random() * 20, 5), ridgeMat);
    m.position.set((i - 4) * 26 + (Math.random() - 0.5) * 12, 9, GATE_Z - 78 - Math.random() * 26);
    m.rotation.y = Math.random() * 3;
    m.castShadow = false;
    g.add(m);
  }
})();

/* ────────────── 西南門外的香霖堂遠景（傳送點看得到下一張圖） ── */
(function kourindouVista() {
  const g = new THREE.Group();
  world.add(g);
  const gy = heightAt(SW_GATE.x, SW_GATE.z);
  // 出門的土路先往西鋪一段（跟門內那段各差 1.2 公分，重疊處不會閃）
  groundDecal(48, 6, SW_GATE.x - 28, SW_GATE.z + 2, MAT.road, 0.074);
  // 夾道的樹：愈往西愈密、愈暗（香霖堂在林緣，再過去就是魔法之森）
  for (let i = 0; i < 46; i++) {
    const x = SW_GATE.x - 8 - Math.random() * 54;
    const z = SW_GATE.z + (Math.random() < 0.5 ? -1 : 1) * (5 + Math.random() * 26);
    tree(x, z, 0.9 + Math.random() * 0.9, MAT.leaf);
  }
  // 那間屋頂歪歪的舊道具店：陡屋頂 + 煙囪，一眼就跟里的和瓦分得開
  const shopWall = new THREE.MeshStandardMaterial({ color: '#6b533a', roughness: 0.95 });
  const shopRoof = new THREE.MeshStandardMaterial({ color: '#41474e', roughness: 0.8, flatShading: true });
  const brick = new THREE.MeshStandardMaterial({ color: '#7a4038', roughness: 1 });
  const sx = SW_GATE.x - 74, sz = SW_GATE.z + 6;
  const body = new THREE.Mesh(new THREE.BoxGeometry(17, 3.6, 11), shopWall);
  body.position.set(sx, gy + 1.8, sz);
  g.add(body);
  for (const s of [-1, 1]) {
    const slope = new THREE.Mesh(new THREE.BoxGeometry(19, 0.34, 7.4), shopRoof);
    slope.position.set(sx, gy + 5.5, sz + s * 2.4);
    slope.rotation.x = s * 0.84;
    g.add(slope);
  }
  const ridge = new THREE.Mesh(new THREE.BoxGeometry(19.4, 0.36, 0.9), shopRoof);
  ridge.position.set(sx, gy + 7.0, sz);
  g.add(ridge);
  const chim = new THREE.Mesh(new THREE.BoxGeometry(1.2, 4.4, 1.2), brick);
  chim.position.set(sx - 6, gy + 6.0, sz - 1.6);
  g.add(chim);
  // 再遠處是魔法之森的暗樹牆
  const wallMat = new THREE.MeshStandardMaterial({ color: '#263a26', roughness: 1, flatShading: true });
  for (let i = 0; i < 16; i++) {
    const m = new THREE.Mesh(new THREE.ConeGeometry(11 + Math.random() * 9, 24 + Math.random() * 16, 5), wallMat);
    m.position.set(SW_GATE.x - 104 - Math.random() * 30, gy + 8, SW_GATE.z + (i - 8) * 17);
    m.rotation.y = Math.random() * 3;
    g.add(m);
  }
  g.traverse(o => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
})();

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
/* 路點推離碰撞盒 —— 修「路人穿模」。
 * 主街動線在 x=±3.6，龍神像的基壇卻是 11×11（半寬 5.5）——
 * 動線整條從石壇中間穿過去，路人看起來就是走進雕像裡。
 * 不能直接刪掉被擋住的路點（動線會斷、路人過不了廣場），
 * 改成把落在碰撞盒裡的路點沿較淺的軸推出去 —— 動線自然繞開障礙。 */
for (const nd of CROWD_GRAPH.nodes) {
  for (let iter = 0; iter < 4; iter++) {
    const c = colliders.find(c => c.hw != null
      ? Math.abs(nd[0] - c.x) < c.hw + 0.5 && Math.abs(nd[1] - c.z) < c.hd + 0.5
      : Math.hypot(nd[0] - c.x, nd[1] - c.z) < (c.r ?? 0) + 0.5);
    if (!c) break;
    if (c.hw != null) {
      const pushX = (c.hw + 0.7) - Math.abs(nd[0] - c.x);
      const pushZ = (c.hd + 0.7) - Math.abs(nd[1] - c.z);
      if (pushX <= pushZ) nd[0] = c.x + Math.sign(nd[0] - c.x || 1) * (c.hw + 0.7);
      else nd[1] = c.z + Math.sign(nd[1] - c.z || 1) * (c.hd + 0.7);
    } else {
      const a = Math.atan2(nd[1] - c.z, nd[0] - c.x);
      nd[0] = c.x + Math.cos(a) * ((c.r ?? 0) + 0.7);
      nd[1] = c.z + Math.sin(a) * ((c.r ?? 0) + 0.7);
    }
  }
}

// 傳 colliders：路點圖難免有幾條連線從屋角切過，路人走到那裡會插進牆裡。
// VillagerCrowd 收到碰撞盒之後會每幀把人推出來（見 _unstick）。
const crowd = new VillagerCrowd(scene, heightAt, CROWD_GRAPH, 64, 10, colliders);

/* ─────────────────────────────────────────────────────── 玩家 ── */
const { spec, ctrl } = core.spawnPlayer({
  bounds: { hx: 240, hz: 300 },
  // 出生點依來向分流：從香霖堂回來就站在西南門內，其餘（獸道／直接開頁）站北門內
  spawn(from, c) {
    if (from === 'kourindou') {
      c.teleport(SW_GATE.x + 9, SW_GATE.z);
      c.yaw = Math.PI / 2;        // 面向東（往里內）
      c.camYaw = -Math.PI / 2;
    } else {
      c.teleport(0, GATE_Z + 9);
      c.yaw = 0;
      c.camYaw = Math.PI;
    }
  },
});

/* ───────────────────── 名冊角色（預設沒有人，全交給場景編輯器） ── */
// 名牌是 depthTest:false 的 sprite，住 GameCore 的獨立 overlay 場景
// （core.labelScene）—— 這張圖是 basic，core.plateScene 會回主場景，
// 用它就會把「主畫面之後單獨畫」這個原本的行為弄丟。
const labelScene = core.labelScene;
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
core.createProgression();

/* 角色的隨身裝備：HP/MP、戰鬥、技能、技能視窗（K）。
 * 里內沒有怪（結界擋著），所以不傳 mobs —— 招式照出，只是砍不到東西。
 * 技能是角色內建的，不該因為「這張圖沒有怪」就消失。
 * （renderBadge 由 core.installKit 代打，跟原本同一句。） */
core.installKit({
  isBlocked: () => core.escMenu.isOpen || sceneEditor.isOpen,
  onDeath: () => ctrl.teleport(0, GATE_Z + 9),
});

/* ─────────────────────────────────────── 夜燈與環境回呼 ── */
core.onEnvApply((t) => {
  for (const { lamp, light } of lanternGlows) {
    light.intensity = t.lantern * 4.5;
    lamp.material.emissiveIntensity = t.lantern > 0.05 ? 0.9 : 0.2;
  }
});
core.onEnvLabel((text) => { HUD.todLabel.textContent = text; });
core.applyEnvNow();

/* ────────────────────────────────────────────── 互動與選單 ── */
// 畫質與「回選角」都跟 GameCore 的預設逐字相同；isBusy 是這張圖獨有的
// （場景編輯器開著時 ESC 要留給編輯器）。
const escMenu = core.bindEsc({ isBusy: () => sceneEditor.isOpen });

/* ─────────────────────── 大地圖（M）與小地圖（N 開關）── 升級5 ── */
core.installMapUI({
  current: 'village',
  isBlocked: () => sceneEditor.isOpen || escMenu.isOpen,
  minimap: {
    bounds: { minX: -160, maxX: 160, minZ: -195, maxZ: 265 },
    lines: [
      [[0, GATE_Z], [0, SOUTH_GATE_Z]],                                  // 主街
      ...CROSS_Z.map(cz => [[-102, cz], [102, cz]]),                     // 橫街
      ...LANE_X.map(lx => [[lx, -160], [lx, 200]]),                      // 小巷
      [[-98, 100], [SW_GATE.x, 100]],                                    // 西南門引道
    ],
    portals: [
      { x: 0, z: GATE_Z - 6, label: '獸道', color: '#8be8ff' },
      { x: KOURIN_PORTAL.x, z: KOURIN_PORTAL.z, label: '香霖堂', color: '#e0c88a' },
    ],
  },
});

const nearPortal = () => Math.hypot(ctrl.pos.x, ctrl.pos.z - (GATE_Z - 6)) < 4.2;
const nearKourindou = () =>
  Math.hypot(ctrl.pos.x - KOURIN_PORTAL.x, ctrl.pos.z - KOURIN_PORTAL.z) < 4.6;

// 這張圖的 keydown 是客製的（ESC 關編輯器 / P 開關編輯器 / E 兩個出口），
// 判定鏈跟 core.installTalk 的樣板不同 —— 原樣保留。
window.addEventListener('keydown', (e) => {
  // ESC 在編輯器開著時是「關掉編輯器」（core.bindEsc 的 isBusy 已讓過）
  if (e.code === 'Escape' && sceneEditor.isOpen) { sceneEditor.close(); return; }
  // P：開關場景編輯器。放在鎖定判斷之前 —— 開啟時會解除滑鼠鎖定。
  if (e.code === 'KeyP') { sceneEditor.toggle(); e.preventDefault(); return; }
  if (sceneEditor.isOpen || escMenu.isOpen) return;
  if (e.code !== 'KeyE' || !ctrl.locked) return;
  if (nearPortal()) { HUD.showLoading('獸道 讀取中'); location.href = '../trail/?from=village'; return; }
  if (nearKourindou()) { HUD.showLoading('香霖堂 讀取中'); location.href = '../kourindou/?from=village'; }
});

/* ─────────────────────────────────────────────────── 主迴圈 ── */
// kit 結算之後、env 之前：路人、名冊角色、水車（原樣板的順序）
core.onUpdate((dt, rawDt, t) => {
  crowd.update(dt, t, ctrl.pos);
  npcSystem.update(t, ctrl.pos, camera);
  // 水車：里外唯一會動的建築，慢慢轉（河水推的，不用很快）
  for (const w of waterWheels) w.rotation.x += dt * 0.55;
});

// env 之後、minimap 之前：兩個傳送點的呼吸動畫
core.onLateUpdate((dt, rawDt, t) => {
  trailPortal.userData.update(t);
  kourinPortal.userData.update(t);
});

// minimap.update() 之後：HUD 提示（原本就排在小地圖後面）
core.onPostUpdate(() => {
  if (nearPortal()) HUD.prompt('[ E ]  前往獸道（往博麗神社・迷途竹林）');
  else if (nearKourindou()) HUD.prompt('[ E ]  前往香霖堂（往魔法之森）');
  else HUD.prompt(null);
});

core.start();

// debug handle（跟其他地圖同一套測試口徑）。原本沒有 panel 這個鍵 → omit。
window.__village = core.debugHandle({
  crowd, npcs: npcSystem, sceneEditor,
  /** 手動渲染一格（量 renderer.info 用，跟 __shrine.frame 同口徑）。
   *  原本刻意只畫主場景、不畫名牌 —— 覆寫掉 core.renderFrame 版本。 */
  frame() { renderer.render(scene, camera); },
  GATE_Z, SOUTH_GATE_Z, SW_GATE, KOURIN_PORTAL,
}, { omit: ['panel'] });

/* 色調分級 LUT（升級書 4.4）—— 這張圖的色調個性。
 * 各地區的預設值集中在 src/world/lut.js，改的時候看得到彼此的關係。 */
core.setLUT(buildLUT(LUT_PRESETS.village));
