// 香霖堂 —— 人間之里往魔法之森的路上，森近霖之助開的舊道具店。
//
// 設定考據（Touhou Wiki）：香霖堂（こうりんどう）在人里與魔法之森之間的
// 林緣，賣的是從外界流進幻想鄉的道具。店主森近霖之助是人與妖的半妖，
// 能力是「看得出道具的名字與用途」——名字跟用途看得出來，用法看不出來，
// 所以店裡堆滿了他也不知道怎麼用的東西。魔理沙常來「借」貨。
//
// 這張圖的定位是**過場小圖**（140×140，safe，無怪）：從里出來走一小段
// 林緣路，看到一間屋頂歪歪的店，進去跟霖之助講幾句，再往西邊那片
// 越來越暗的樹林走 —— 魔法之森還沒蓋，西口先只做門面與遠景。
//
// 美術主題是「和洋混合」：和式的木造屋身、暖簾、木格子窗，配上洋式的
// 陡屋頂、磚砌煙囪、玻璃窗與街燈。店外那堆看不出用途的雜物（鐵桶、
// 車輪、洋傘、木箱）才是這張圖真正的主角。
//
// ※ 已改用 GameCore（src/core/GameCore.js）：renderer / Environment /
//    畫質 / 玩家 / 成長 / ESC / 大小地圖 / 主迴圈全部由共用執行層提供，
//    這個檔案只剩香霖堂獨有的東西（整合書・階段 D）。行為與遷移前逐幀相同。

import * as THREE from 'three';
import { REGION_BY_ID } from '../../src/config.js';
import { makePortalGlow } from '../../src/world/portal.js';
import { NPCManager } from '../../src/entities/npc.js';
import { Dialogue } from '../../src/ui/dialogue.js';
import { mergeStaticByMaterial } from '../../src/core/optimize.js';
import { texMaps } from '../../src/world/texgen.js';
import { applyTriplanar } from '../../src/world/triplanar.js';
import { rockTexture } from '../../src/world/terraintex.js';
import { buildLUT, LUT_PRESETS } from '../../src/world/lut.js';
import { PathNet, catmullRom } from '../../src/world/pathnet.js';
import { GroundGrid, ribbonOnGrid } from '../../src/world/groundmesh.js';
import { scatterGrass } from '../../src/world/flora.js';
import { MAP_REGISTRY } from '../../src/world/mapRegistry.js';
import { ridgeRing, gapToward } from '../../src/world/vista.js';
import { makeSignpost } from '../../src/world/signpost.js';
import { bootMap } from '../../src/core/GameCore.js';

const core = bootMap({
  hud: {
    title: '香霖堂',
    subtitle: 'KOURINDOU · 人間之里 ⇄ 魔法之森',
    keys: [
      ['WASD / 方向鍵', '移動'], ['滑鼠', '轉視角'], ['滾輪', '縮放'],
      ['Shift', '衝刺'], ['Space', '跳躍'],
      ['E', '互動 / 對話'], ['K', '技能'], ['M', '地圖'], ['ESC', '選單'],
    ],
    flyKeys: [['F', '飛行'], ['Ctrl/C', '下降']],
    combatKeys: [['左鍵', '出招'], ['長按左鍵', '日之呼吸・全型'], ['R', '拔刀/納刀'], ['1 ~ 4', '技']],
  },
  // 過場小圖：140×140，遠平面不必拉到 700
  camera: { far: 420 },
  exposure: 1.05,
  // 林緣：霧比開闊地濃一點（西邊那片森林要糊掉才有「更深處還有東西」的感覺），
  // 但不能濃到看不見店 —— 這張圖只有 140 公尺見方。
  env: { fogMul: 1.25, shadowArea: 46, followSun: true },
  // 完整後製鏈：畫質雙標到此為止 —— 高檔有 GTAO 的接觸陰影與 Bloom，
  // 跟神社同一套；低檔自動全關，跟原本的 basic 一樣輕。
  // 天空色的 tone mapping / 色彩空間已在 environment.js 對齊（方案 A），
  // 兩條路徑的天空至此一致，翻過來不會突然變色。
  postFX: 'full',
});
const { scene, camera, world, colliders } = core;
const { box, cyl, post, block } = core;

/* ───────────────────────────────────────────── 尺寸與出入口 ── */
const HALF = 70;                          // 140×140（mapRegistry 的 playSize）
const EAST_END = { x: 62, z: 10 };        // 往人間之里
const WEST_END = { x: -62, z: 0 };        // 往魔法之森（forest 未建成前只做門面）
const SHOP = { x: 2, z: -7, w: 17, d: 11, h: 3.4 };   // 店：正面朝南（+z）
const YARD = { x0: -12, x1: 20, z0: -32, z1: -14 };   // 後院（雜物堆的地盤）

let _seed = 20260803;
function rand() {
  _seed = (_seed * 1664525 + 1013904223) >>> 0;
  return _seed / 4294967296;
}
const rr = (a, b) => a + rand() * (b - a);

/* ───────────────────────────────────────────────────── 路網 ── */
// 三段：主徑（東口↔西口）、店前的踏石短徑、繞到後院的側徑。
// 支徑都從主徑岔出 —— 重疊處兩層路面若同高就會整片閃爍，所以下面
// 鋪面的 lift 每段各差 1.2 公分。
const PATH_SEGMENTS = [
  {
    id: 'main', width: 5.0,
    pts: [
      [EAST_END.x, EAST_END.z], [46, 11], [30, 10], [14, 8],
      [2, 7], [-16, 6], [-34, 4], [-50, 2], [WEST_END.x, WEST_END.z],
    ],
  },
  { id: 'front', width: 3.0, pts: [[2, 7], [2, 3.5], [2, 0]] },
  { id: 'yard', width: 2.6, pts: [[13, 8], [18, 2], [19, -10], [14, -21]] },
];
const PATHS = new PathNet(PATH_SEGMENTS, { step: 2, cell: 10 });

/* ─────────────────────────────────────────────────── 地形高度場 ── */
// 林緣平地：路面一帶平，離路愈遠起伏愈明顯；店庭與後院整過地（壓平）。
// 邊界圍坡把玩家收在圖裡，二次式**一定要封頂**，不封的話網格邊緣會
// 衝到上百公尺高，遠看是兩道白牆。
function heightAt(x, z) {
  const roll = Math.sin(x * 0.035) * 0.9 + Math.sin(z * 0.041 + 1.1) * 0.75;
  // 離路邊 0 → 完全平；10 公尺以外 → 完整起伏
  const ed = PATHS.edgeDist(x, z);
  let h = roll * Math.min(1, (ed === Infinity ? 10 : ed) / 10);

  // 店庭與後院是整過地的：矩形內壓平，外圍 6 公尺過渡（免得牆基出現一階斷差）
  const inn = Math.min(
    x - (YARD.x0 - 6), (YARD.x1 + 6) - x,
    z - (YARD.z0 - 6), 10 - z,
  );
  if (inn > 0) h *= 1 - Math.min(1, inn / 6) * 0.85;

  const d = Math.max(Math.abs(x), Math.abs(z)) - (HALF - 10);
  if (d > 0) h += Math.min(13, d * d * 0.07);
  return h + Math.sin(x * 0.46 + z * 0.33) * 0.05;
}
// heightAt 反向依賴 PathNet（要 PATHS.edgeDist），所以登記時機在這裡，
// 不能提前到 bootMap —— 這也是 setTerrain 做成方法而非參數的原因。
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
const soilTex = canvasTex(256, (g, s) => {
  g.fillStyle = '#4a4d33'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 2400; i++) {
    g.fillStyle = `rgba(${58 + Math.random() * 46},${64 + Math.random() * 40},${40 + Math.random() * 26},.5)`;
    g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 1 + Math.random() * 5, 0, 7); g.fill();
  }
}, 16, 16);
const roadTex = canvasTex(256, (g, s) => {
  g.fillStyle = '#8a7a5c'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 2600; i++) {
    g.fillStyle = `rgba(${138 + Math.random() * 46},${124 + Math.random() * 42},${96 + Math.random() * 36},.5)`;
    g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 0.8 + Math.random() * 3, 0, 7); g.fill();
  }
}, 2, 24);
const flagTex = canvasTex(256, (g, s) => {
  // 店前的踏石：不規則石板拼起來
  g.fillStyle = '#7e7a6c'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 44; i++) {
    g.fillStyle = `rgba(${132 + Math.random() * 44},${126 + Math.random() * 40},${110 + Math.random() * 34},.85)`;
    const w = 26 + Math.random() * 40, h = 22 + Math.random() * 32;
    const x = Math.random() * s, y = Math.random() * s;
    g.fillRect(x, y, w, h);
    g.strokeStyle = 'rgba(56,52,44,.55)'; g.lineWidth = 2; g.strokeRect(x, y, w, h);
  }
}, 2, 8);
const plankTex = canvasTex(256, (g, s) => {
  // 下見板（橫向的木板牆）
  g.fillStyle = '#6b533a'; g.fillRect(0, 0, s, s);
  for (let y = 0; y < s; y += 16) {
    g.fillStyle = `rgba(${92 + Math.random() * 34},${70 + Math.random() * 26},${46 + Math.random() * 20},.9)`;
    g.fillRect(0, y, s, 14);
    g.strokeStyle = 'rgba(38,28,18,.6)'; g.lineWidth = 1.5;
    g.beginPath(); g.moveTo(0, y + 15); g.lineTo(s, y + 15); g.stroke();
  }
}, 3, 2);
const brickTex = canvasTex(128, (g, s) => {
  g.fillStyle = '#7a4038'; g.fillRect(0, 0, s, s);
  for (let y = 0, r = 0; y < s; y += 12, r++) {
    for (let x = (r % 2) * -12; x < s; x += 24) {
      g.fillStyle = `rgba(${132 + Math.random() * 36},${72 + Math.random() * 24},${58 + Math.random() * 20},1)`;
      g.fillRect(x + 1, y + 1, 22, 10);
    }
  }
}, 2, 3);

const MAT = {
  soil: new THREE.MeshStandardMaterial({ ...texMaps(soilTex, [0.86, 1.0]), roughness: 1 }),
  road: new THREE.MeshStandardMaterial({
    ...texMaps(roadTex, [0.86, 1.0]), roughness: 1,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
  }),
  flag: new THREE.MeshStandardMaterial({
    ...texMaps(flagTex, [0.81, 1.0]), roughness: 1,
    polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -3,
  }),
  plank: new THREE.MeshStandardMaterial({ ...texMaps(plankTex, [0.81, 1.0]), roughness: 1 }),
  brick: new THREE.MeshStandardMaterial({ ...texMaps(brickTex, [0.86, 1.0]), roughness: 1 }),
  wood: new THREE.MeshStandardMaterial({ color: '#7a6144', roughness: 0.92 }),
  darkWood: new THREE.MeshStandardMaterial({ color: '#4a3626', roughness: 0.95 }),
  // 洋式的陡屋頂：暗青灰的石板瓦，跟里的和瓦分得開
  slate: new THREE.MeshStandardMaterial({ color: '#41474e', roughness: 0.78, flatShading: true }),
  rust: new THREE.MeshStandardMaterial({ color: '#6e4a32', roughness: 0.95, metalness: 0.25 }),
  iron: new THREE.MeshStandardMaterial({ color: '#4c4c52', roughness: 0.6, metalness: 0.5 }),
  cloth: new THREE.MeshStandardMaterial({ color: '#3f5f52', roughness: 1, side: THREE.DoubleSide }),
  stone: new THREE.MeshStandardMaterial({ color: '#8a8880', roughness: 1 }),
  mossStone: new THREE.MeshStandardMaterial({ color: '#74806a', roughness: 1 }),
  // 玻璃窗：夜裡由 core.onEnvApply 把自發光推上去（店裡有人）
  glass: new THREE.MeshStandardMaterial({
    color: '#cfe0dc', roughness: 0.18, metalness: 0.1,
    emissive: '#8a6a24', emissiveIntensity: 0.25,
  }),
  bark: new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.95 }),
  leaf: new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 1, flatShading: true }),
};

/* ───────────────────────────────────────────────────────── 地面 ── */
const GRID = new GroundGrid({ size: HALF * 2 + 100, seg: 120, heightAt });
const gSample = (x, z) => GRID.sample(x, z);
{
  const m = new THREE.Mesh(GRID.buildGeometry(), MAT.soil);
  m.receiveShadow = true;
  world.add(m);

  /* 三平面貼圖（升級書第 3 章）。從正上方投影的 UV 在斜面上會被拉成
   * 一條一條 —— 改用世界座標三軸取樣，陡坡自動由側面那兩張主導。
   *
   * scale 用原本的 repeat 換算，密度才不會順便被放大或縮小；原本的
   * repeat 是 16×16（非等向），三平面只吃一個尺度，取幾何平均。
   *
   * 低畫質不套：每像素多採樣兩次，低階機划不來，退回原本的單軸 UV。 */
  const TRI_SCALE = Math.sqrt(16 * 16) / GRID.size;
  let triOn = null;
  const syncTri = (idx) => {
    const want = idx >= 1;                 // 0=低 1=中 2=高
    if (want === triOn) return;
    triOn = want;
    if (want) {
      applyTriplanar(MAT.soil, {
        scale: TRI_SCALE, sharp: 4,
        rock: texMaps(rockTexture({ base: '#77726a' }), [0.8, 0.98]),
        slope: [0.34, 0.60],
      });
    } else {
      MAT.soil.onBeforeCompile = () => {};
      MAT.soil.customProgramCacheKey = () => 'tri:off';
      MAT.soil.map.repeat.set(16, 16);
      MAT.soil.normalMap?.repeat.set(16, 16);
      MAT.soil.roughnessMap?.repeat.set(16, 16);
      MAT.soil.needsUpdate = true;
    }
  };
  core.onQualityChange(syncTri);
  // GameCore 建構時就跑過一次 syncQuality()，那時這張圖還沒註冊，
  // 初始狀態要自己補，不能等下一次切畫質
  syncTri(core.quality.idx);

}

/* 三段鋪面。lift 各差 1.2 公分 —— 支徑從主徑岔出，重疊處若共面，
   深度緩衝分不出前後，整片會閃。（GroundGrid 治的是「路 vs 地面」。） */
PATH_SEGMENTS.forEach((seg, i) => {
  const mat = seg.id === 'front' ? MAT.flag : MAT.road;
  ribbonOnGrid(world, catmullRom(seg.pts, 2), seg.width / 2, mat, gSample, 0.05 + i * 0.012);
});

/* ─────────────────────────────────────── 舊道具店（和洋混合） ── */
(function kourindouShop() {
  const y = heightAt(SHOP.x, SHOP.z);
  const g = new THREE.Group();
  g.position.set(SHOP.x, y, SHOP.z);
  world.add(g);

  const HW = SHOP.w / 2, HD = SHOP.d / 2;
  const fz = HD + 0.02;                 // 正面（朝南 +z）

  box(SHOP.w + 1.4, 0.5, SHOP.d + 1.4, MAT.stone, 0, 0.25, 0, g);       // 石基
  box(SHOP.w, SHOP.h, SHOP.d, MAT.plank, 0, 0.5 + SHOP.h / 2, 0, g);    // 下見板の屋身

  // 和式：正面的木格子窗（框 + 格）與板戶
  for (const s of [-1, 1]) {
    const wx = s * 5.2;
    box(3.6, 1.9, 0.12, MAT.glass, wx, 2.35, fz, g);
    box(3.9, 0.16, 0.2, MAT.darkWood, wx, 3.36, fz, g);
    box(3.9, 0.16, 0.2, MAT.darkWood, wx, 1.34, fz, g);
    for (let k = -1; k <= 1; k++) box(0.13, 1.9, 0.2, MAT.darkWood, wx + k * 1.15, 2.35, fz, g);
  }
  box(2.6, 2.4, 0.16, MAT.darkWood, 0, 1.7, fz, g);                     // 入口的引戶
  box(0.16, 2.4, 0.22, MAT.wood, 0, 1.7, fz + 0.04, g);                 // 戶の合わせ目

  // 暖簾（門口垂下來的三片布）
  for (let k = -1; k <= 1; k++) {
    box(0.84, 1.0, 0.05, MAT.cloth, k * 0.9, 3.35, fz + 0.16, g);
  }
  box(3.0, 0.14, 0.24, MAT.darkWood, 0, 3.9, fz + 0.16, g);             // 暖簾竿

  // 看板：「香霖堂」的木牌，掛在正面右上
  const sign = box(3.4, 0.9, 0.14, MAT.wood, 5.4, 4.3, fz + 0.1, g);
  sign.rotation.z = -0.03;
  box(3.6, 0.12, 0.2, MAT.darkWood, 5.4, 4.82, fz + 0.1, g);

  // 洋式：陡的切妻屋頂（比里的和瓦陡得多）＋屋脊
  const RW = SHOP.w + 2.2, RD = SHOP.d + 2.6;
  for (const s of [-1, 1]) {
    const slope = box(RW, 0.3, RD * 0.66, MAT.slate, 0, 0.5 + SHOP.h + 1.9, s * RD * 0.22, g);
    slope.rotation.x = s * 0.84;         // 0.84 rad ≈ 48°，洋風的陡坡
  }
  box(RW + 0.5, 0.34, 0.9, MAT.slate, 0, 0.5 + SHOP.h + 3.35, 0, g);
  // 兩端的破風板（把屋頂下的三角形封起來）
  for (const s of [-1, 1]) {
    const gable = new THREE.Mesh(new THREE.ConeGeometry(RD * 0.5, 2.9, 3), MAT.plank);
    gable.rotation.set(0, Math.PI / 2, Math.PI / 2);
    gable.position.set(s * (RW / 2 - 0.16), 0.5 + SHOP.h + 1.42, 0);
    gable.castShadow = true;
    g.add(gable);
  }

  // 磚砌煙囪（外界流進來的洋房才有的東西）
  box(1.1, 4.2, 1.1, MAT.brick, -6.0, 0.5 + SHOP.h + 2.4, -1.6, g);
  box(1.5, 0.28, 1.5, MAT.stone, -6.0, 0.5 + SHOP.h + 4.6, -1.6, g);

  // 屋根窗（dormer）：小三角屋頂 + 一格玻璃
  box(2.2, 1.5, 1.6, MAT.plank, 3.4, 0.5 + SHOP.h + 2.0, 2.4, g);
  box(1.5, 0.95, 0.1, MAT.glass, 3.4, 0.5 + SHOP.h + 2.1, 3.22, g);
  const dr = new THREE.Mesh(new THREE.ConeGeometry(1.9, 1.1, 4), MAT.slate);
  dr.rotation.y = Math.PI / 4;
  dr.position.set(3.4, 0.5 + SHOP.h + 3.2, 2.4);
  dr.castShadow = true;
  g.add(dr);

  // 正面的下屋（庇）：出簷一米多，撐兩根細柱 —— 雨天站得住人
  box(SHOP.w + 1.2, 0.16, 2.4, MAT.wood, 0, 3.05, fz + 1.1, g);
  for (const s of [-1, 1]) {
    cyl(0.09, 0.1, 3.0, MAT.darkWood, s * (HW - 0.5), 1.5, fz + 2.1, 6, g);
  }
  // 上店的踏石
  box(2.8, 0.26, 1.1, MAT.stone, 0, 0.13, fz + 2.9, g);

  block(SHOP.x, SHOP.z, SHOP.w + 0.6, SHOP.d + 0.6, y + SHOP.h + 3.6);
})();

/* ───────────────────────────── 店外的雜物（外界流進來的道具） ── */
/** 一堆看不出用途的東西。全部走同一組材質，靜態合併才收得乾淨。 */
function junkPile(cx, cz, n = 5) {
  const y = heightAt(cx, cz);
  for (let i = 0; i < n; i++) {
    const x = cx + rr(-1.6, 1.6), z = cz + rr(-1.6, 1.6);
    const kind = Math.floor(rand() * 5);
    const yy = heightAt(x, z);
    if (kind === 0) {                                  // 木箱
      const s = rr(0.5, 0.95);
      const m = box(s, s * 0.8, s, MAT.wood, x, yy + s * 0.4, z);
      m.rotation.y = rand() * 3.14;
    } else if (kind === 1) {                           // 鐵桶（外界的油桶）
      const h = rr(0.7, 1.05);
      cyl(0.32, 0.32, h, MAT.rust, x, yy + h / 2, z, 10);
    } else if (kind === 2) {                           // 車輪（腳踏車的？沒人知道）
      const r = rr(0.34, 0.52);
      const w = new THREE.Mesh(new THREE.TorusGeometry(r, 0.055, 6, 16), MAT.iron);
      w.position.set(x, yy + r, z);
      w.rotation.set(0, rand() * 3.14, rr(-0.3, 0.3));
      w.castShadow = true;
      world.add(w);
    } else if (kind === 3) {                           // 洋傘（撐開的，倒在牆邊）
      const c = new THREE.Mesh(new THREE.ConeGeometry(rr(0.42, 0.6), 0.42, 8), MAT.cloth);
      c.position.set(x, yy + 0.42, z);
      c.rotation.set(rr(0.4, 1.1), rand() * 3.14, 0);
      c.castShadow = true;
      world.add(c);
      cyl(0.03, 0.03, 0.9, MAT.darkWood, x, yy + 0.3, z, 5);
    } else {                                           // 甕
      const r = rr(0.26, 0.4);
      const p = new THREE.Mesh(new THREE.SphereGeometry(r, 10, 8), MAT.mossStone);
      p.scale.y = 1.25;
      p.position.set(x, yy + r, z);
      p.castShadow = p.receiveShadow = true;
      world.add(p);
    }
  }
  post(cx, cz, 2.0, y + 1.0);      // 整堆擋人（不做逐件碰撞，走不進去就夠了）
}

// 店的兩側與簷下
junkPile(-8.6, 1.2, 6);
junkPile(12.0, 0.4, 5);
junkPile(-11.5, -6.0, 5);
junkPile(14.5, -4.5, 5);
junkPile(-12.5, 3.6, 4);

// 路旁零星的東西：擺不下的貨被推到路邊，一路擺到東口去
for (let i = 0; i < 10; i++) {
  const t = i / 9;
  const px = 24 + t * 30, pz = 12.5 + Math.sin(t * 4.1) * 2.4;
  junkPile(px, pz, 3);
}

// 後院：木柵欄圍起來，裡頭堆得更凶
(function backyard() {
  const { x0, x1, z0, z1 } = YARD;
  // 柵欄（南面留一個口給側徑進來）
  const railM = MAT.darkWood;
  function fenceRun(ax, az, bx, bz) {
    const n = Math.max(2, Math.round(Math.hypot(bx - ax, bz - az) / 1.6));
    for (let i = 0; i <= n; i++) {
      const t = i / n, x = ax + (bx - ax) * t, z = az + (bz - az) * t;
      cyl(0.07, 0.08, 1.5, railM, x, heightAt(x, z) + 0.75, z, 5);
    }
    const cx = (ax + bx) / 2, cz = (az + bz) / 2;
    const alongX = Math.abs(bx - ax) > Math.abs(bz - az);
    const len = Math.hypot(bx - ax, bz - az);
    const y = heightAt(cx, cz);
    for (const hy of [0.6, 1.16]) {
      box(alongX ? len : 0.07, 0.07, alongX ? 0.07 : len, railM, cx, y + hy, cz);
    }
    block(cx, cz, alongX ? len : 0.4, alongX ? 0.4 : len, y + 1.5);
  }
  fenceRun(x0, z0, x1, z0);           // 北
  fenceRun(x0, z0, x0, z1);           // 西
  fenceRun(x0, z1, 10, z1);           // 南（10 → x1 之間是入口）
  fenceRun(x1, z0, x1, z1);           // 東

  for (let i = 0; i < 11; i++) {
    junkPile(rr(x0 + 3, x1 - 3), rr(z0 + 3, z1 - 3), 5);
  }
  // 薪棚：西北角堆到腰高的柴。單位面積的裝飾密度要追上人間之里，
  // 靠一堆一堆的雜物撐不太上來，一疊柴一次就是二十幾根。
  (function woodStack() {
    const bx = x0 + 5, bz = z0 + 3.5, by = heightAt(bx, bz);
    for (let row = 0; row < 4; row++) {
      for (let k = 0; k < 6; k++) {
        const l = new THREE.Mesh(new THREE.CylinderGeometry(0.11, 0.12, 2.4, 6), MAT.wood);
        l.rotation.z = Math.PI / 2;
        l.position.set(bx, by + 0.14 + row * 0.24, bz + (k - 2.5) * 0.25 + (row % 2) * 0.12);
        l.castShadow = l.receiveShadow = true;
        world.add(l);
      }
    }
    // 柴堆頂是平的 —— 跳上去就站著（walk），不是被彈開
    colliders.push({ x: bx, z: bz, y: by, h: 1.1, hw: 1.3, hd: 0.95, walk: true });
  })();
  // 曬衣竿（兩根叉柱架一根竹竿）
  for (const s of [-1, 1]) cyl(0.07, 0.08, 2.0, MAT.wood, -8 + s * 4, heightAt(-8 + s * 4, -18) + 1.0, -18, 6);
  box(8.2, 0.07, 0.07, MAT.wood, -8, heightAt(-8, -18) + 1.95, -18);
  // 井
  const wx = 16, wz = -28, wy = heightAt(wx, wz);
  cyl(1.05, 1.15, 0.9, MAT.stone, wx, wy + 0.45, wz, 12);
  for (const s of [-1, 1]) cyl(0.08, 0.09, 1.9, MAT.darkWood, wx + s * 0.9, wy + 1.4, wz, 6);
  box(2.4, 0.14, 0.9, MAT.wood, wx, wy + 2.4, wz);
  post(wx, wz, 1.3, wy + 1.0);
})();

/* ─────────────────────────────────── 街燈（洋式，夜裡會亮） ── */
function streetLamp(cx, cz) {
  const y = heightAt(cx, cz);
  cyl(0.24, 0.3, 0.34, MAT.stone, cx, y + 0.17, cz, 8);
  cyl(0.08, 0.1, 3.0, MAT.iron, cx, y + 1.8, cz, 8);
  const head = new THREE.Mesh(new THREE.BoxGeometry(0.42, 0.5, 0.42), MAT.glass);
  head.position.set(cx, y + 3.45, cz);
  head.castShadow = true;
  world.add(head);
  const cap = new THREE.Mesh(new THREE.ConeGeometry(0.36, 0.28, 4), MAT.iron);
  cap.rotation.y = Math.PI / 4;
  cap.position.set(cx, y + 3.82, cz);
  world.add(cap);
  post(cx, cz, 0.28, y + 3.6);
}
streetLamp(-4.5, 8.4);
streetLamp(11.0, 8.8);
streetLamp(-24, 6.6);

/* ─────────────────────────────────────────── 林緣的樹（instanced） ── */
// 東邊（往里）疏、西邊（往森）密且高 —— 一路走過去會愈走愈暗，
// 玩家不用看提示也知道森林在哪一頭。
(function plantTrees() {
  const spots = [];
  for (let i = 0; i < 2600 && spots.length < 340; i++) {
    const x = rr(-HALF - 6, HALF + 6), z = rr(-HALF - 6, HALF + 6);
    if (PATHS.dist(x, z) < 6.5) continue;                            // 路上不長
    // 店庭要留得比店本身大一圈：玩家是從南邊走上來的，正面被樹幹擋住
    // 就等於看不到店、也看不到站在門口的霖之助。
    if (x > YARD.x0 - 8 && x < YARD.x1 + 8 && z > YARD.z0 - 6 && z < 20) continue;
    // 正面走道再往南留一條窄帶：第三人稱相機在玩家身後約 4 公尺，
    // 只留到店庭邊的話，一走上踏石相機就整個埋進樹幹裡。
    if (Math.abs(x - SHOP.x) < 12 && z >= 20 && z < 28) continue;
    const west = 1 - (x + HALF) / (HALF * 2);                        // 0=東 1=西
    if (rand() > 0.12 + west * 0.8) continue;
    spots.push({ x, z, west, h: rr(6, 10) + west * 4, r: rr(0.2, 0.34) + west * 0.1, yaw: rand() * 6.28 });
  }

  const trunkGeo = new THREE.CylinderGeometry(0.7, 1, 1, 6, 1);
  trunkGeo.translate(0, 0.5, 0);
  const leafGeo = new THREE.IcosahedronGeometry(1, 0);

  // 四象限各一組 —— 單一個 InstancedMesh 的包圍盒涵蓋整張圖，
  // 視錐裁剪永遠命中（竹林踩過這個坑）。
  const quads = [[], [], [], []];
  for (const s of spots) quads[(s.x > 0 ? 1 : 0) + (s.z > 0 ? 2 : 0)].push(s);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler();
  const v = new THREE.Vector3(), sc = new THREE.Vector3(), col = new THREE.Color();
  let total = 0;
  for (const list of quads) {
    if (!list.length) continue;
    total += list.length;
    const trunks = new THREE.InstancedMesh(trunkGeo, MAT.bark, list.length);
    trunks.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(list.length * 3), 3);
    const crowns = new THREE.InstancedMesh(leafGeo, MAT.leaf, list.length * 2);
    crowns.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(list.length * 6), 3);
    trunks.castShadow = trunks.receiveShadow = true;
    crowns.castShadow = crowns.receiveShadow = true;
    list.forEach((s, i) => {
      const y = heightAt(s.x, s.z);
      e.set(0, s.yaw, 0);
      q.setFromEuler(e);
      m4.compose(v.set(s.x, y, s.z), q, sc.set(s.r, s.h, s.r));
      trunks.setMatrixAt(i, m4);
      col.setHSL(0.09, 0.24, 0.16 + rand() * 0.07);
      trunks.setColorAt(i, col);
      // 兩球樹冠疊出一點體積感；愈往西愈深綠
      for (let k = 0; k < 2; k++) {
        const cr = (2.1 + rand() * 0.9) * (1 - k * 0.3);
        m4.compose(
          v.set(s.x + rr(-0.5, 0.5), y + s.h * (0.82 + k * 0.17), s.z + rr(-0.5, 0.5)),
          q, sc.set(cr, cr * 0.8, cr),
        );
        crowns.setMatrixAt(i * 2 + k, m4);
        col.setHSL(0.27 - s.west * 0.03, 0.3 + s.west * 0.2, 0.3 - s.west * 0.12 + rand() * 0.05);
        crowns.setColorAt(i * 2 + k, col);
      }
      post(s.x, s.z, s.r + 0.15, y + s.h * 0.8);
    });
    trunks.instanceColor.needsUpdate = true;
    crowns.instanceColor.needsUpdate = true;
    world.add(trunks, crowns);
  }
  console.info(`[kourindou] 林緣樹 ${total} 棵（${quads.filter(l => l.length).length * 2} 組 InstancedMesh）`);
})();

/* ─────────────────────────────────────────────────── 草叢 ── */
scatterGrass(world, {
  count: 1800, heightAt,
  place: () => {
    const x = rr(-HALF - 4, HALF + 4), z = rr(-HALF - 4, HALF + 4);
    // 離路緣留 1.2 公尺：一叢草放大後半徑約 0.5 公尺，貼著路緣種葉尖會蓋到路面
    if (PATHS.dist(x, z) < 2.5 + 1.2) return null;
    // 店庭與後院是踩實的地，不長草
    if (x > YARD.x0 - 2 && x < YARD.x1 + 2 && z > YARD.z0 - 2 && z < 10) return null;
    return [x, z];
  },
  baseColor: 0x5b7436,
});

/* ────────────────────────── 兩端的遠景（傳送點看得到下一張圖） ── */
// 東口：人間之里的屋頂與水田
(function villageVista() {
  const g = new THREE.Group();
  g.position.set(EAST_END.x + 16, heightAt(EAST_END.x, EAST_END.z), EAST_END.z);
  world.add(g);
  const wallM = new THREE.MeshStandardMaterial({ color: '#cfc3a6', roughness: 1 });
  const roofM = new THREE.MeshStandardMaterial({ color: '#4c5560', roughness: 0.85, flatShading: true });
  for (let i = 0; i < 14; i++) {
    const x = rr(2, 34), z = rr(-40, 44), w = rr(6, 11), d = rr(5, 8);
    const b = new THREE.Mesh(new THREE.BoxGeometry(w, 3.2, d), wallM);
    b.position.set(x, 1.6, z);
    g.add(b);
    for (const s of [-1, 1]) {
      const sl = new THREE.Mesh(new THREE.BoxGeometry(w + 1.6, 0.3, d * 0.72), roofM);
      sl.position.set(x, 4.0, z + s * d * 0.24);
      sl.rotation.x = s * 0.52;
      g.add(sl);
    }
  }
  g.traverse(o => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
})();

// 西口：魔法之森的樹牆（高、暗、密 —— 一看就知道那邊不是善地）
(function forestVista() {
  const g = new THREE.Group();
  g.position.set(WEST_END.x - 14, heightAt(WEST_END.x, WEST_END.z), WEST_END.z);
  world.add(g);
  const trunkM = new THREE.MeshStandardMaterial({ color: '#2e2820', roughness: 1 });
  const crownM = new THREE.MeshStandardMaterial({ color: '#263a26', roughness: 1, flatShading: true });
  for (let i = 0; i < 70; i++) {
    const x = rr(-34, -1), z = rr(-46, 46), h = rr(14, 22);
    const t = new THREE.Mesh(new THREE.CylinderGeometry(0.45, 0.7, h, 5), trunkM);
    t.position.set(x, h / 2, z);
    g.add(t);
    const c = new THREE.Mesh(new THREE.IcosahedronGeometry(rr(3.4, 5.2), 0), crownM);
    c.position.set(x, h * 0.92, z);
    c.scale.y = 0.8;
    g.add(c);
  }
  g.traverse(o => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
})();

/* ───────────────────────────────────────────── 傳送點 ── */
// connections 是單一事實來源：forest 還沒蓋（built:false）就不點光 ——
// 光點的約定是「看到光＝走過去按 E 有用」，先亮著會騙人。
const eastPortal = makePortalGlow(world, EAST_END.x, heightAt(EAST_END.x, EAST_END.z), EAST_END.z, 0xe0c88a);
const FOREST_OPEN = !!MAP_REGISTRY.forest?.built;
const westPortal = FOREST_OPEN
  ? makePortalGlow(world, WEST_END.x, heightAt(WEST_END.x, WEST_END.z), WEST_END.z, 0x7dd88a)
  : null;

/* 道標（升級5）：兩端各一塊，牌面朝店的方向 */
makeSignpost(world, EAST_END.x - 2.2, heightAt(EAST_END.x - 2.2, EAST_END.z + 2.6), EAST_END.z + 2.6, '往 人間之里', -Math.PI / 2);
makeSignpost(world, WEST_END.x + 2.2, heightAt(WEST_END.x + 2.2, WEST_END.z + 2.6), WEST_END.z + 2.6, '往 魔法之森', Math.PI / 2);

/* ─────────────── 邊界圍坡之外的遠景（升級1：遠景延伸） ── */
// 林緣小圖：外圈是層層退遠的樹冠稜線，東西兩口留缺
// （那兩個方向已有里的屋頂與魔法之森的樹牆遠景）。
ridgeRing(world, {
  radius: 128, heightAt,
  height: [18, 34], color: 0x3a4c33, treeTops: true, seed: 23,
  gaps: [
    gapToward(EAST_END.x, EAST_END.z, 0.6),
    gapToward(WEST_END.x, WEST_END.z, 0.6),
  ],
});

/* ──────────────────────────────────────────── 靜態幾何合併 ── */
{
  const s = mergeStaticByMaterial(world, { cell: 40 });
  console.info(`[optimize] 香霖堂靜態合併：${s.before} → ${s.after} 個網格（合併成 ${s.merged}，保留 ${s.kept}）`);
}

/* ─────────────────────────────────────────────────────── 玩家 ── */
core.spawnPlayer({
  bounds: { hx: HALF + 6, hz: HALF + 6 },
  maxGrade: 1.0,                       // 邊界圍坡爬不上去，店庭的緩坡走得動
  spawn(from, ctrl) {
    if (from === 'forest') {
      ctrl.teleport(WEST_END.x + 6, WEST_END.z);
      ctrl.yaw = Math.PI / 2;          // 面向東（往店）
      ctrl.camYaw = -Math.PI / 2;
    } else {
      // 預設（含 from=village）：從東邊的里道走進來
      ctrl.teleport(EAST_END.x - 6, EAST_END.z);
      ctrl.yaw = -Math.PI / 2;         // 面向西（往店）
      ctrl.camYaw = Math.PI / 2;
    }
  },
});
const ctrl = core.ctrl;

/* ────────────────────────────────── 住民：霖之助（對話） ── */
const npcMgr = new NPCManager(scene, core.plateScene);
// roster 裡霖之助的 region 是 kourindou，origin 傳同一筆 REGION → offset 即局部座標
npcMgr.setRoster(['rinnosuke'], REGION_BY_ID.kourindou, 90);
const dialogue = new Dialogue();

/* 夜裡店裡的玻璃窗與街燈亮起來（合併後共用同一份 MAT.glass，改一份就全亮） */
core.onEnvApply((tt) => {
  MAT.glass.emissiveIntensity = 0.2 + tt.lantern * 1.7;
});

/* ─────────────────────────────── 成長 + 角色隨身裝備 ── */
core.createProgression();
/* 香霖堂是安全區（safe: true）—— 不傳 mobs，招式照出。 */
core.installKit({
  isBlocked: () => core.escMenu.isOpen || dialogue.active,
  onDeath: () => ctrl.teleport(EAST_END.x - 6, EAST_END.z),
});

/* ───────────────────────────────────────────── 互動與提示 ── */
core.bindEsc();

/* ─────────────────────── 大地圖（M）與小地圖（N 開關）── 升級5 ── */
core.installMapUI({
  current: 'kourindou',
  isBlocked: () => dialogue.active || core.escMenu.isOpen,
  minimap: {
    bounds: { minX: -72, maxX: 72, minZ: -72, maxZ: 72 },
    paths: PATHS,
    portals: [
      { x: EAST_END.x, z: EAST_END.z, label: '人間之里', color: '#e0c88a' },
      { x: WEST_END.x, z: WEST_END.z, label: '魔法之森', color: '#7dd88a' },
    ],
  },
});

const nearEast = () => Math.hypot(ctrl.pos.x - EAST_END.x, ctrl.pos.z - EAST_END.z) < 5.0;
const nearWest = () => Math.hypot(ctrl.pos.x - WEST_END.x, ctrl.pos.z - WEST_END.z) < 5.0;

// 西口是條件出口：forest 還沒蓋的時候有提示、按 E 不傳送（href 省略）
const updatePrompt = core.installTalk({
  npcMgr, dialogue,
  exits: [
    {
      near: nearEast,
      prompt: '[ E ]  返回人間之里',
      loading: '人間之里 讀取中',
      href: '../village/?from=kourindou',
    },
    {
      near: nearWest,
      prompt: FOREST_OPEN ? '[ E ]  往魔法之森' : '魔法之森 —— 林子太密，還走不進去',
      loading: '魔法之森 讀取中',
      ...(FOREST_OPEN ? { href: '../forest/?from=kourindou' } : {}),
    },
  ],
});

/* ─────────────────────────────────────────────────── 主迴圈 ── */
// kit 結算之後、env 之前：NPC 與對話（原樣板的順序）
core.onUpdate((dt, rawDt, t) => {
  npcMgr.update(t, ctrl.pos, camera);
  dialogue.update(dt);
});

// env 之後、小地圖之前：傳送點的呼吸動畫（西口未開放時是 null）
core.onLateUpdate((dt, rawDt, t) => {
  eastPortal.userData.update(t);
  westPortal?.userData.update(t);
});

// 小地圖之後：HUD 提示（原本就排在 minimap.update() 後面）
core.onPostUpdate(() => { updatePrompt(); });

core.start();

// debug handle（跟其他地圖同一套測試口徑）
window.__kourindou = core.debugHandle({
  npcMgr, dialogue,
  PATHS, EAST_END, WEST_END, SHOP, YARD, FOREST_OPEN,
});

/* 色調分級 LUT（升級書 4.4）—— 這張圖的色調個性。
 * 各地區的預設值集中在 src/world/lut.js，改的時候看得到彼此的關係。 */
core.setLUT(buildLUT(LUT_PRESETS.kourindou));
