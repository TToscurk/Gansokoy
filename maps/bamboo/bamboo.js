// 迷途竹林 —— 人間之里的南邊，通往永遠亭的路上。
//
// 設定考據（Touhou Wiki）：迷いの竹林是人間之里南方的一大片孟宗竹林，
// 竹子長得又高又密、地貌到處長一樣，走進去的人幾乎出不來 —— 名字就是
// 這麼來的。林中住著大量妖怪兔（因幡てゐ的手下），深處是永遠亭。
// 這張圖從獸道的東南分岔接進來，南端接永遠亭（maps/eientei/）。
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
//
// ※ 已改用 GameCore（src/core/GameCore.js）：renderer / Environment /
//    玩家 / 成長 / ESC / 大小地圖 / 主迴圈全部由共用層提供，這個檔案
//    只剩竹林獨有的東西（整合書・階段 D）。行為與遷移前逐字相同 ——
//    包含 LCG（seed 20240731）的消費順序，動一下整片林子就換樣。

import * as THREE from 'three';
import * as BGU from 'three/addons/utils/BufferGeometryUtils.js';
import { REGION_BY_ID } from '../../src/config.js';
import { NPCManager, TALK_RANGE } from '../../src/entities/npc.js';
import { Dialogue } from '../../src/ui/dialogue.js';
import { makePortalGlow } from '../../src/world/portal.js';
import { RabbitMobs } from '../../src/combat/rabbits.js';
import { progressMobs } from '../../src/player/progression.js';
import { makeSignpost } from '../../src/world/signpost.js';
import { mergeStaticByMaterial } from '../../src/core/optimize.js';
import { texMaps } from '../../src/world/texgen.js';
import { fbm, modulate } from '../../src/world/noise.js';
import { applyTriplanar } from '../../src/world/triplanar.js';
import { rockTexture } from '../../src/world/terraintex.js';
import { buildLUT, LUT_PRESETS } from '../../src/world/lut.js';
import { PathNet, catmullRom } from '../../src/world/pathnet.js';
import { GroundGrid, ribbonOnGrid } from '../../src/world/groundmesh.js';
import { scatterGrass } from '../../src/world/flora.js';
import { ridgeRing, gapToward } from '../../src/world/vista.js';
import { Ambience } from '../../src/world/ambience.js';
import { bootMap } from '../../src/core/GameCore.js';

/* 共用 HUD / renderer / scene / Environment —— 與其他圖完全同一套版面 */
// 竹林的霧是這張圖的主角：看不遠才會迷路。太陽跟著玩家走（長條地圖），
// 陰影相機不用蓋住整片林子。
const core = bootMap({
  hud: {
    title: '迷途竹林',
    subtitle: 'BAMBOO FOREST OF THE LOST · 獸道 ⇄ 永遠亭',
    keys: [
      ['WASD / 方向鍵', '移動'], ['滑鼠', '轉視角'], ['滾輪', '縮放'],
      ['Shift', '衝刺'], ['Space', '跳躍'],
      ['E', '互動'], ['K', '技能'], ['M', '地圖'], ['ESC', '選單'],
    ],
    flyKeys: [['F', '飛行'], ['Ctrl/C', '下降']],
    combatKeys: [['左鍵', '出招'], ['長按左鍵', '日之呼吸・全型'], ['R', '拔刀/納刀'], ['1 ~ 4', '技']],
  },
  // near 0.2：深度精度（見 main.js 同名註解）。far 560（不是預設的 700）——
  // 竹林看不遠，霧本來就吃掉遠處。
  camera: { fov: 68, near: 0.2, far: 560 },
  exposure: 1.06,
  env: { fogMul: 2.1, shadowArea: 48, followSun: true },
  // 完整後製鏈：畫質雙標到此為止 —— 高檔有 GTAO 的接觸陰影與 Bloom，
  // 跟神社同一套；低檔自動全關，跟原本的 basic 一樣輕。
  // 天空色的 tone mapping / 色彩空間已在 environment.js 對齊（方案 A），
  // 兩條路徑的天空至此一致，翻過來不會突然變色。
  postFX: 'full',
});
const { HUD, scene, camera, world, colliders } = core;
const { box, cyl, post, block } = core;

/* ─────────────────────────────────────────────────── 地形高度場 ── */
// 竹林長在平地上：地面只有很緩的起伏，迷宮感靠竹子的密度而不是地形。
// 兩側超過邊界才抬升成坡，把玩家收在林子裡（沒有空氣牆）。
const LEN = 300;            // z ∈ [-300, 300]
const HALF_W = 150;         // x ∈ [-150, 150]
const NORTH_END = { x: 0, z: -282 };     // 通往獸道
const SOUTH_END = { x: 0, z: 282 };      // 通往永遠亭（尚未開放）

/**
 * 決定性亂數。竹林的佈局要隨機，但**每次重整必須長一樣** ——
 * 不然建築、空地、怪窩每次進圖都換位置，玩家永遠記不住路，
 * 而「記住路」正是這張圖唯一的導航手段。
 */
let _seed = 20240731;
function rand() {
  _seed = (_seed * 1664525 + 1013904223) >>> 0;
  return _seed / 4294967296;
}
const rr = (a, b) => a + rand() * (b - a);

/**
 * 小徑網：主徑蜿蜒貫穿南北，另外岔出幾條隨機的支徑通向空地。
 * 控制點隨機生成 —— 每次重整一樣，但改一下種子就是完全不同的一片林子。
 */
const TRAIL_SEGMENTS = (() => {
  const segs = [];
  // 主徑：從北口到南端，控制點左右擺盪
  const main = [[NORTH_END.x, NORTH_END.z]];
  for (let z = -240; z <= 240; z += 60) {
    main.push([rr(-46, 46), z + rr(-10, 10)]);
  }
  main.push([SOUTH_END.x, SOUTH_END.z]);
  segs.push({ id: 'main', width: 6.4, pts: main });

  // 支徑：從主徑中段各岔出去，通向空地
  for (let i = 0; i < 5; i++) {
    const t = 0.18 + i * 0.16;
    const k = Math.floor(main.length * t);
    const from = main[Math.max(1, Math.min(main.length - 2, k))];
    const dir = rand() < 0.5 ? -1 : 1;
    const pts = [from.slice()];
    let x = from[0], z = from[1];
    const n = 2 + (rand() * 2 | 0);
    for (let j = 0; j < n; j++) {
      x += dir * rr(22, 40);
      z += rr(-30, 30);
      pts.push([Math.max(-HALF_W + 20, Math.min(HALF_W - 20, x)), z]);
    }
    segs.push({ id: `branch${i}`, width: 4.6, pts });
  }

  // 東徑：第二期開的東口，通往無名之丘。從主徑北段岔出一路向東爬出竹海。
  {
    const k = Math.floor(main.length * 0.32);
    const from = main[Math.max(1, Math.min(main.length - 2, k))];
    const pts = [from.slice()];
    let x = from[0], z = from[1];
    while (x < 118) {
      x += rr(24, 38);
      z += rr(-16, 16);
      pts.push([Math.min(130, x), Math.max(-240, Math.min(240, z))]);
    }
    pts.push([138, pts[pts.length - 1][1]]);
    segs.push({ id: 'east', width: 5.2, pts });
  }
  return segs;
})();
const PATHS = new PathNet(TRAIL_SEGMENTS, { step: 3, cell: 14 });
/** 東口（通往無名之丘）＝東徑的終點 */
const EAST_END = (() => {
  const e = TRAIL_SEGMENTS.find(s => s.id === 'east').pts.at(-1);
  return { x: e[0], z: e[1] };
})();

/** 離最近的小徑多遠（扣掉路寬） */
const pathDist = (x, z) => PATHS.edgeDist(x, z, 2);

function heightAt(x, z) {
  const roll = Math.sin(z * 0.021) * 0.7 + Math.sin(x * 0.028 + 1.1) * 0.6;
  const ax = Math.abs(x), az = Math.abs(z);
  // 兩側與南北兩端的圍坡。一定要封頂 —— 不封的話二次式在地面網格的
  // 邊緣會衝到一百公尺高，遠看就是兩道白色巨牆立在天邊。
  const rise = (d) => (d <= 0 ? 0 : Math.min(13, d * d * 0.05));
  const slope = Math.max(rise(ax - (HALF_W - 12)), rise(az - (LEN - 8)));
  const wob = Math.sin(x * 0.6 + z * 0.29) * 0.08;
  return roll + slope + wob;
}
// waterLevel 維持 -999：這張圖沒有水域（見 main.js 同名註解）
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
  // 大尺度的乾濕斑塊（升級書第 2 章）。散點是白噪音，只有高頻；沒有這層，
  // 貼圖平鋪時會看得出一格一格 —— 改成世界座標三平面之後尤其明顯。
  // 係數讓平均倍率落在 1.0 附近，只加結構不改整體亮度。
  {
    const k = 1 / s, C = 5;
    modulate(g, s, (x, y) =>
      0.86 + fbm(x * k * C, y * k * C, { period: C, octaves: 4, seed: 201 }) * 0.30,
      { step: 2 });
  }
}, 16, 36);
const trailTex = canvasTex(256, (g, s) => {
  // 比落葉地面亮一截，否則走在路上看不出自己在路上
  g.fillStyle = '#79674a'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 1600; i++) {
    g.fillStyle = `rgba(${112 + Math.random() * 50},${96 + Math.random() * 42},${66 + Math.random() * 28},.5)`;
    g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 1 + Math.random() * 4, 0, 7); g.fill();
  }
  // 大尺度的乾濕斑塊（升級書第 2 章）。散點是白噪音，只有高頻；沒有這層，
  // 貼圖平鋪時會看得出一格一格 —— 改成世界座標三平面之後尤其明顯。
  // 係數讓平均倍率落在 1.0 附近，只加結構不改整體亮度。
  {
    const k = 1 / s, C = 6;
    modulate(g, s, (x, y) =>
      0.86 + fbm(x * k * C, y * k * C, { period: C, octaves: 4, seed: 211 }) * 0.30,
      { step: 2 });
  }
}, 3, 40);

const MAT = {
  soil: new THREE.MeshStandardMaterial({ ...texMaps(soilTex, [0.86, 1.0]), roughness: 1 }),
  // 小徑鋪在地面上：polygonOffset 讓它在深度測試上穩定贏過土壤（見人間之里的同一套處理）
  trail: new THREE.MeshStandardMaterial({
    ...texMaps(trailTex, [0.86, 1.0]), roughness: 1,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
  }),
  culm: new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.72 }),   // 竹竿（顏色走頂點/instance）
  /* 一般網格用的竹竿。MAT.culm 的底色是白的 —— 那是給 InstancedMesh 用的，
   * 顏色由 instanceColor 帶。直接拿去做單一網格會得到一根純白的柱子
   * （紅布條竹踩過這個坑：白柱子在林子裡亮得像螢光棒）。 */
  culmSolid: new THREE.MeshStandardMaterial({ color: '#6f8449', roughness: 0.72 }),
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

/* ───────────────────────────────────────────────────────── 地面 ── */
/* 地面網格 + 貼地查詢（見 src/world/groundmesh.js —— 路草不閃的根治） */
const GRID = new GroundGrid({ size: Math.max(HALF_W, LEN) * 2 + 120, seg: 170, heightAt });
const gSample = (x, z) => GRID.sample(x, z);
{
  const m = new THREE.Mesh(GRID.buildGeometry(), MAT.soil);
  m.receiveShadow = true;
  world.add(m);

  /* 三平面貼圖（升級書第 3 章）。從正上方投影的 UV 在斜面上會被拉成
   * 一條一條 —— 改用世界座標三軸取樣，陡坡自動由側面那兩張主導。
   *
   * scale 用原本的 repeat 換算，密度才不會順便被放大或縮小；原本的
   * repeat 是 16×36（非等向），三平面只吃一個尺度，取幾何平均。
   *
   * 低畫質不套：每像素多採樣兩次，低階機划不來，退回原本的單軸 UV。 */
  const TRI_SCALE = Math.sqrt(16 * 36) / GRID.size;
  let triOn = null;
  const syncTri = (idx) => {
    const want = idx >= 1;                 // 0=低 1=中 2=高
    if (want === triOn) return;
    triOn = want;
    if (want) {
      applyTriplanar(MAT.soil, {
        scale: TRI_SCALE, sharp: 4,
        rock: texMaps(rockTexture({ base: '#6e6a60' }), [0.8, 0.98]),
        slope: [0.34, 0.60],
      });
    } else {
      MAT.soil.onBeforeCompile = () => {};
      MAT.soil.customProgramCacheKey = () => 'tri:off';
      MAT.soil.map.repeat.set(16, 36);
      MAT.soil.normalMap?.repeat.set(16, 36);
      MAT.soil.roughnessMap?.repeat.set(16, 36);
      MAT.soil.needsUpdate = true;
    }
  };
  core.onQualityChange(syncTri);
  // GameCore 建構時就跑過一次 syncQuality()，那時這張圖還沒註冊，
  // 初始狀態要自己補，不能等下一次切畫質
  syncTri(core.quality.idx);

}

/* 路面不畫（品質升級書・升級 6）。
 *
 * 原本 PathNet 的每一段都用 ribbonOnGrid 鋪一條看得見的土徑 —— 於是
 * 「迷途竹林」照著顏色走就出去了，名不副實。現在地面全圖統一材質，
 * PathNet **只留作內部資料**：竹子的疏密、兔子與 NPC 的移動、出入口
 * 判定都還要用它，只是玩家看不到它。
 *
 * 認路改靠地標（紅布條竹、石燈籠、地藏、死路的竹筍叢）—— 見下方
 * landmarks()。 */

/* ─────────────────────────────────────────────────────── 竹林 ── */
/**
 * 空地：這些圓範圍內不長竹子（放建築、怪窩、休息點）。
 *
 * 位置由支徑的末端決定 —— 支徑本來就是「岔出去通向某處」的路，
 * 末端自然就是那個「某處」。加上主徑上幾個等距的休息點。
 * 全部走決定性亂數，每次重整長一樣（見 rand 的說明）。
 */
const CLEARINGS = (() => {
  const out = [
    { x: NORTH_END.x, z: NORTH_END.z, r: 13, kind: 'gate' },
    { x: SOUTH_END.x, z: SOUTH_END.z, r: 15, kind: 'gate' },
    { x: EAST_END.x, z: EAST_END.z, r: 12, kind: 'gate' },
  ];
  // 支徑末端 = 一塊林中空地（東徑是出口不是空地，不算）
  const KINDS = ['jizo', 'hut', 'shrine', 'torii', 'bridge'];
  TRAIL_SEGMENTS.filter(s => s.id.startsWith('branch')).forEach((seg, i) => {
    const end = seg.pts[seg.pts.length - 1];
    out.push({ x: end[0], z: end[1], r: 11 + rand() * 4, kind: KINDS[i % KINDS.length] });
  });
  // 主徑上幾個休息點
  const main = catmullRom(TRAIL_SEGMENTS[0].pts, 4);
  for (let i = 1; i <= 3; i++) {
    const [cx, cz] = main[Math.floor(main.length * i / 4)];
    const a = rand() * Math.PI * 2;
    out.push({ x: cx + Math.cos(a) * 12, z: cz + Math.sin(a) * 12, r: 9, kind: 'rest' });
  }
  return out;
})();
const inClearing = (x, z) => CLEARINGS.some(c => Math.hypot(x - c.x, z - c.z) < c.r);

/** 砍竹系統的共用資料（由下面的 bamboo() 填、由 cuttable() 消費） */
const CUTTABLE = { cells: null, cellKey: null, thickets: null };

/**
 * 竹子。一千多根重複物件 —— 全部走 InstancedMesh，而且依 CELL 公尺
 * 見方的格子各建一個，讓身後的竹林能整塊被視錐裁掉。
 *
 * 竹竿用單位高度的圓柱，靠 instance 矩陣縮放出不同高度；葉叢是三片
 * 交叉的面片合成一個幾何，一根竹子一個 instance。
 */
(function bamboo() {
  const CELL = 38;
  const cells = new Map();                        // key → 該格的竹子清單
  const cellKey = (x, z) => `${Math.floor(x / CELL)},${Math.floor(z / CELL)}`;

  // --- 決定每根竹子的位置 ---
  // 密度：離小徑越遠越密。小徑兩側 2.6 公尺內完全不長，否則走不動。
  let thickets = 0;
  const thicketList = [];        // { blocker, members[] } —— 砍光整叢才解除擋路
  let thicketOf = null;
  // 沿著小徑網撒，而不是整張圖亂撒 —— 地圖 300×600 公尺，
  // 亂撒的話大部分點落在玩家永遠走不到的角落（獸道踩過這個坑）。
  for (let i = 0; i < 9000; i++) {
    const sm = PATHS.samples[(rand() * PATHS.samples.length) | 0];
    const a = rand() * Math.PI * 2;
    const rd = rr(2.4, 52);
    const x = sm.x + Math.cos(a) * rd, z = sm.z + Math.sin(a) * rd;
    if (Math.abs(x) > HALF_W || Math.abs(z) > LEN) continue;
    const pd = pathDist(x, z);
    if (pd < 2.6) continue;
    if (inClearing(x, z)) continue;
    // 離路越遠越密（近處疏一點，看得到路）
    const density = Math.min(1, (pd - 2.6) / 14);
    if (rand() > density * 0.66) continue;

    /* 竹子的個體差異（升級書・升級 6 第 5 點）。驗收標準是
     * 「截圖裡找不到兩根一模一樣的竹子」，所以每一項都要真的分開擲：
     *   粗細 0.06~0.22（原本 0.075~0.12，範圍太窄看起來像複製貼上）
     *   高度 8~16，**粗的傾向高** —— 隨機獨立擲的話會出現又粗又矮的
     *     樁子跟又細又高的麵條，兩種都不像竹子
     *   傾斜 ±4°
     *   2% 是攔腰折斷的枯竹（只留下半截，沒有葉叢）*/
    const thick = rand();                                  // 0 = 最細, 1 = 最粗
    const r = 0.06 + thick * 0.16;
    const h = 8 + thick * 5 + rr(0, 3);                    // 粗的傾向高，再加一點抖動
    const tilt = rr(-0.07, 0.07);
    const broken = rand() < 0.02;
    const key = cellKey(x, z);
    if (!cells.has(key)) cells.set(key, []);
    cells.get(key).push({
      x, z, r, tilt, yaw: rand() * 6.28,
      h: broken ? h * rr(0.25, 0.5) : h,
      broken,
      tone: rand(),                                        // 三種綠的抽籤（見下）
    });

    // 一部分是「叢」：三五根長在一起，這些才擋人 ——
    // 每一根都給碰撞盒的話，走在林子裡會像卡在牙籤堆裡。
    if (pd > 7 && rand() < 0.05) {
      thickets++;
      // 留住這顆碰撞盒的參考：整叢被砍光時要把它解除（砍竹開路）
      post(x, z, 1.0, heightAt(x, z) + 6);
      const blocker = colliders[colliders.length - 1];
      const members = [];
      thicketList.push({ blocker, members });
      thicketOf = members;
      for (let k = 0; k < 3 + (rand() * 3 | 0); k++) {
        const ba = rand() * 6.28, bd = rr(0.25, 0.95);
        const bx = x + Math.cos(ba) * bd, bz = z + Math.sin(ba) * bd;
        const bk = cellKey(bx, bz);
        if (!cells.has(bk)) cells.set(bk, []);
        const bt = rand();
        const rec = {
          x: bx, z: bz, r: 0.07 + bt * 0.13, h: 8 + bt * 5 + rr(0, 2.5),
          tilt: rr(-0.09, 0.09), yaw: rand() * 6.28, broken: false, tone: rand(),
        };
        cells.get(bk).push(rec);
        thicketOf?.push(rec);
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
  /* 樹冠要能遮天：孟宗竹的葉子集中在頂端一大片，相鄰竹子的葉叢互相交疊
   * 之後才會把天空封起來。原本三層 18 片、最外只攤到 0.30 —— 從地面往上
   * 看幾乎全是天。這裡加到五層 34 片、最外攤到 0.62（往外一倍多），
   * 並且最下面兩層垂得更開，交疊的面積才夠。 */
  const LAYERS = [
    { n: 9, up: -0.15, out: 0.62, len: 1.55, droop: 1.25 },
    { n: 8, up: 0.15, out: 0.50, len: 1.35, droop: 1.05 },
    { n: 7, up: 0.50, out: 0.38, len: 1.10, droop: 0.85 },
    { n: 6, up: 0.85, out: 0.26, len: 0.90, droop: 0.65 },
    { n: 4, up: 1.15, out: 0.14, len: 0.70, droop: 0.45 },
  ];
  for (const L of LAYERS) {
    for (let i = 0; i < L.n; i++) {
      const g = new THREE.PlaneGeometry(0.21, L.len);
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
      // 砍竹要能改這一格的矩陣 —— 記住自己住在哪個 InstancedMesh 的第幾格
      b.mesh = culms; b.leafMesh = leaves; b.idx = i;
      b.hp = 3;                                   // 升級書：三刀
      const y = heightAt(b.x, b.z);
      e.set(b.tilt, b.yaw, b.tilt * 0.7);
      q.setFromEuler(e);

      s.set(b.r, b.h, b.r);
      m4.compose(v.set(b.x, y, b.z), q, s);
      culms.setMatrixAt(i, m4);

      /* 竹竿的顏色：三種綠按 6:3:1 混（升級書指定的比例）。
       * 原本是連續漸變 —— 連續色階在一片竹林裡會糊成同一種綠，
       * 分成三群反而看得出「這根跟那根不一樣」。群內再各自抖動一點。 */
      const t = b.tone;
      const band = t < 0.6 ? 0 : t < 0.9 ? 1 : 2;          // 嫩綠 / 正綠 / 黃綠帶枯斑
      const jit = (t * 37 % 1) - 0.5;                      // 群內抖動，不再消耗 rand()
      const HSL = [
        [0.235, 0.40, 0.42],   // 嫩綠
        [0.205, 0.34, 0.34],   // 正綠
        [0.150, 0.30, 0.40],   // 黃綠帶枯斑
      ][band];
      col.setHSL(HSL[0] + jit * 0.012, HSL[1] + jit * 0.06, HSL[2] + jit * 0.07);
      if (b.broken) col.offsetHSL(-0.03, -0.16, 0.02);     // 枯竹更黃更淡
      culms.setColorAt(i, col);

      // 葉叢掛在頂端（跟著竹竿的傾斜偏移）。高的竹子葉叢也大一點。
      // 攔腰折斷的枯竹沒有葉叢 —— 縮到 0 讓它整叢消失（instance 數量不變，
      // 少一根就要重排整個陣列，不值得）。
      // 葉叢整體再放大一階（0.85+h*0.055 → 1.15+h*0.085）：一根竹子的葉叢
      // 要能碰到鄰居的，天蓋才連得起來
      const ls = b.broken ? 0 : 1.15 + b.h * 0.085;
      s.set(ls, ls, ls);
      m4.compose(
        v.set(b.x + Math.sin(b.tilt) * b.h, y + b.h * 0.80, b.z + Math.sin(b.tilt * 0.7) * b.h),
        q, s);
      leaves.setMatrixAt(i, m4);
      col.setHSL(0.245 - band * 0.03, 0.44 - band * 0.06, 0.24 + band * 0.06);
      leaves.setColorAt(i, col);
    });
    culms.instanceColor.needsUpdate = true;
    leaves.instanceColor.needsUpdate = true;
    world.add(culms, leaves);
  }
  console.info(`[bamboo] 竹子 ${total} 根，分 ${meshes} 個 InstancedMesh（${cells.size} 個格子），叢生擋人處 ${thickets}`);

  // 交給砍竹系統：cells 本身就是空間索引，直接沿用不必再建一份
  CUTTABLE.cells = cells;
  CUTTABLE.cellKey = cellKey;
  CUTTABLE.thickets = thicketList;
  window.__cuttableCells = cells;   // 給自動化測試查詢用（debug handle 之外的小口子）
  window.__thickets = thicketList;
})();

/* ──────────────────────────────────────────────── 砍竹 ── */
/**
 * 可砍的竹子（品質升級書・升級 6 第 4 點）。
 *
 * 架構照 mobcore 的思路：**渲染歸 instance、狀態歸陣列**。竹子有一千多根，
 * 不可能一根一個 Mesh；但砍下去要記血量、要單獨倒下、要五分鐘後長回來，
 * 所以每根在生成時就記住自己住在哪個 InstancedMesh 的第幾格（b.mesh/b.idx），
 * 砍中就直接改那一格的矩陣。
 *
 * 為什麼不用 Combat 的 mobs 系統：那套是給會動、會反擊、有 AI 的怪用的，
 * 一千多根靜止的竹子塞進去每幀都要跑一次 AI 與分離，純浪費。
 *
 * 砍竹開路：竹叢（thicket）本來有一顆擋人的碰撞盒。整叢砍光就把它解除 ——
 * 這是迷宮「可被玩家改寫」的地方：死路砍得穿，捨得花時間就有捷徑。
 */
(function cuttable() {
  const { cells, cellKey, thickets } = CUTTABLE;
  if (!cells) return;

  const STUMP = 0.55;              // 砍完留下的斷茬高度
  const FALL_T = 0.8;              // 傾倒
  const FADE_T = 2.0;              // 落地後淡出
  /* 五分鐘後長回。`?regrow=5` 可以縮短 —— 不然驗一次重生要等五分鐘，
   * 自動化測試根本測不到（同 ?nstr= 的用意）。 */
  const REGROW = (() => {
    const v = parseFloat(new URLSearchParams(location.search).get('regrow'));
    return Number.isFinite(v) && v > 0 ? v : 300;
  })();
  const GROW_T = 2.5;              // 冒出來的動畫長度

  const falling = [];              // 正在倒/淡出的上半段
  const regrowing = [];            // 等著長回來的
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion();
  const e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3();

  /** 把一根竹子的竿與葉重新寫回 instance 矩陣。scale 給 0 就是隱形。 */
  const write = (b, hMul, leafMul) => {
    const y = heightAt(b.x, b.z);
    e.set(b.tilt, b.yaw, b.tilt * 0.7);
    q.setFromEuler(e);
    sc.set(b.r, b.h * hMul, b.r);
    m4.compose(v.set(b.x, y, b.z), q, sc);
    b.mesh.setMatrixAt(b.idx, m4);
    b.mesh.instanceMatrix.needsUpdate = true;

    const ls = (b.broken ? 0 : 1.15 + b.h * 0.085) * leafMul;
    sc.set(ls, ls, ls);
    m4.compose(
      v.set(b.x + Math.sin(b.tilt) * b.h, y + b.h * 0.80, b.z + Math.sin(b.tilt * 0.7) * b.h),
      q, sc);
    b.leafMesh.setMatrixAt(b.idx, m4);
    b.leafMesh.instanceMatrix.needsUpdate = true;
  };

  /** 砍斷：上半段倒下、下半段留斷茬、排進重生佇列 */
  const cut = (b) => {
    const y = heightAt(b.x, b.z);
    const cutY = Math.min(b.h * 0.28, 1.6);      // 砍擊高度：約腰的位置

    // 下半段：縮成斷茬，葉叢消失
    b.cutHeight = cutY;
    write(b, cutY / b.h, 0);
    b.dead = true;

    // 上半段：一根獨立的網格，繞斷點傾倒
    const topLen = b.h - cutY;
    const geo = new THREE.CylinderGeometry(b.r * 0.8, b.r, topLen, 6, 1);
    geo.translate(0, topLen / 2, 0);             // 原點在斷面，才好繞它轉
    const mat = MAT.culmSolid.clone();
    mat.transparent = true;
    const top = new THREE.Mesh(geo, mat);
    top.position.set(b.x, y + cutY, b.z);
    top.rotation.y = b.yaw;
    top.castShadow = true;
    world.add(top);
    falling.push({ mesh: top, mat, t: 0, dir: rand() * 6.28, done: false });

    regrowing.push({ b, at: REGROW });

    // 整叢砍光就解除擋人的碰撞盒 —— 這是「砍竹開路」
    for (const th of thickets) {
      if (!th.blocker || th.blocker.r === 0) continue;
      if (!th.members.includes(b)) continue;
      if (th.members.every(mb => mb.dead)) {
        th.blocker.r = 0;                        // 半徑歸零＝不再擋人
        HUD.toast('竹叢被砍開了');
      }
    }
  };

  /* 每次揮刀：找扇形內的竹子扣血。用 cells 當空間索引，只掃玩家周圍
   * 那幾格 —— 一千多根全掃的話每一刀都要跑一千次距離計算。 */
  const RANGE_PAD = 0.6;
  const onSwing = ({ form, origin, yaw }) => {
    const range = (form.range ?? 2.2) + RANGE_PAD;
    const arc = form.arc ?? 1.6;
    const c = 38;                                 // 與 bamboo() 的 CELL 一致
    const gx = Math.floor(origin.x / c), gz = Math.floor(origin.z / c);
    for (let ox = -1; ox <= 1; ox++) {
      for (let oz = -1; oz <= 1; oz++) {
        const list = cells.get(`${gx + ox},${gz + oz}`);
        if (!list) continue;
        for (const b of list) {
          if (b.dead || b.broken) continue;
          const dx = b.x - origin.x, dz = b.z - origin.z;
          const d = Math.hypot(dx, dz);
          if (d > range) continue;
          // 扇形：揮刀朝向與目標方位的夾角
          let a = Math.atan2(dx, dz) - yaw;
          while (a > Math.PI) a -= Math.PI * 2;
          while (a < -Math.PI) a += Math.PI * 2;
          if (Math.abs(a) > arc / 2) continue;
          if (--b.hp <= 0) cut(b);
        }
      }
    }
  };

  /* 掛載時機：cuttable() 跑在 installKit() 之前（竹子要先長出來），
   * 那時 core.kit 還不存在。而且換角色時 kit.rebuild() 會**換掉整個
   * Combat 實例** —— 開場註冊一次的話換完角色就失效了。
   * 所以每幀檢查一次，實例換了就重掛。 */
  let hooked = null;

  core.onUpdate((dt) => {
    const cb = core.kit?.combat;
    if (cb && cb !== hooked) { hooked = cb; cb.onSwing(onSwing); }

    // 倒下 → 落地 → 淡出
    for (let i = falling.length - 1; i >= 0; i--) {
      const f = falling[i];
      f.t += dt;
      if (f.t < FALL_T) {
        const k = f.t / FALL_T;
        // 先快後慢再輕彈一下 —— 純線性看起來像被推倒的紙板
        const ang = (Math.PI / 2) * (1 - (1 - k) * (1 - k)) + Math.sin(k * Math.PI) * 0.06;
        f.mesh.rotation.z = Math.cos(f.dir) * ang;
        f.mesh.rotation.x = Math.sin(f.dir) * ang;
      } else {
        const k = (f.t - FALL_T) / FADE_T;
        f.mat.opacity = Math.max(0, 1 - k);
        if (k >= 1) {
          world.remove(f.mesh);
          f.mesh.geometry.dispose();
          f.mat.dispose();
          falling.splice(i, 1);
        }
      }
    }
    // 重生：縮放從 0 長回 1
    for (let i = regrowing.length - 1; i >= 0; i--) {
      const r = regrowing[i];
      r.at -= dt;
      if (r.at > 0) continue;
      const k = Math.min(1, (-r.at) / GROW_T);
      const b = r.b;
      write(b, (b.cutHeight / b.h) + (1 - b.cutHeight / b.h) * k, k);
      if (k >= 1) {
        b.dead = false;
        b.hp = 3;
        regrowing.splice(i, 1);
      }
    }
  });

  console.info('[bamboo] 砍竹系統上線（3 刀斷、5 分鐘長回、砍光整叢解除擋路）');
})();

/* ─────────────────────────────────── 天蓋（遮住天空的那一層） ── */
/**
 * 竹竿頂端的葉叢遮不住天空 —— 因為走道附近**刻意種得疏**（不然走不動），
 * 而葉叢只長在竹竿上，路的正上方就是空的。從地面抬頭看仍然一片藍。
 *
 * 所以另外鋪一層跟竹竿無關的天蓋：沿路網撒、高度 9~15 公尺、每片是一把
 * 大葉扇。它不需要對應到任何一根竹子 —— 玩家看到的是「上面被葉子蓋住」，
 * 不會去數哪片葉子長在哪根竹子上。
 *
 * 幾何刻意做小（6 片葉子）而尺度做大：要蓋住的是天空的面積，不是細節。
 * 一片 12 個三角形，四千片也才 4.8 萬個。
 */
(function canopy() {
  const CELL = 42;
  const cells = new Map();
  const key = (x, z) => `${Math.floor(x / CELL)},${Math.floor(z / CELL)}`;

  // 葉扇：6 片寬葉繞一圈、略往下垂
  const blades = [];
  for (let i = 0; i < 6; i++) {
    const g = new THREE.PlaneGeometry(0.9, 3.2);
    g.translate(0, 1.6, 0);
    g.rotateX(1.28);                       // 幾乎攤平 —— 攤平才遮得到天
    g.translate(0, 0, 0.55);
    g.rotateY((i / 6) * Math.PI * 2);
    blades.push(g);
  }
  const fanGeo = BGU.mergeGeometries(blades, false);
  blades.forEach(g => { if (g !== fanGeo) g.dispose(); });

  const mat = new THREE.MeshStandardMaterial({
    color: 0xffffff, roughness: 0.85, side: THREE.DoubleSide, flatShading: true });

  let n = 0;
  for (let i = 0; i < 9000; i++) {
    const sm = PATHS.samples[(rand() * PATHS.samples.length) | 0];
    const a = rand() * Math.PI * 2, d = rr(0, 46);
    const x = sm.x + Math.cos(a) * d, z = sm.z + Math.sin(a) * d;
    if (Math.abs(x) > HALF_W || Math.abs(z) > LEN) continue;
    if (inClearing(x, z)) continue;        // 空地上方要留天光，那是休息點
    const k = key(x, z);
    if (!cells.has(k)) cells.set(k, []);
    cells.get(k).push({ x, z, y: rr(9, 15), s: rr(1.6, 3.1), yaw: rand() * 6.28 });
    n++;
  }

  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion();
  const e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3();
  const col = new THREE.Color();
  let meshes = 0;
  for (const list of cells.values()) {
    if (!list.length) continue;
    const im = new THREE.InstancedMesh(fanGeo, mat, list.length);
    im.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(list.length * 3), 3);
    im.userData.noMerge = true;
    // 天蓋不投影：四千片各自投一次陰影會直接壓垮陰影貼圖，而且底下本來
    // 就該是均勻的暗，不是四千個葉子形狀的影子
    im.castShadow = false;
    list.forEach((c, i) => {
      e.set(rr(-0.25, 0.25), c.yaw, rr(-0.25, 0.25));
      q.setFromEuler(e);
      sc.set(c.s, c.s * 0.7, c.s);
      m4.compose(v.set(c.x, heightAt(c.x, c.z) + c.y, c.z), q, sc);
      im.setMatrixAt(i, m4);
      const t = rand();
      col.setHSL(0.245 - t * 0.05, 0.40 - t * 0.1, 0.17 + t * 0.09);   // 背光的葉子偏暗
      im.setColorAt(i, col);
    });
    im.instanceMatrix.needsUpdate = true;
    im.instanceColor.needsUpdate = true;
    world.add(im);
    meshes++;
  }
  console.info(`[bamboo] 天蓋 ${n} 片，分 ${meshes} 個 InstancedMesh`);
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
function jizoShelter(cx, cz) {
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
}

/** 廢屋 —— 早年進林子採竹的人留下的，屋頂已經塌了一半 */
function ruinedHut(cx, cz) {
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
}

/** 竹橋 —— 跨過一條乾涸的小溪 */
function bambooBridge(cx, cz) {
  const y = heightAt(cx, cz);
  const g = new THREE.Group();
  g.position.set(cx, y, cz);
  world.add(g);
  // 橋面：並排的竹管
  for (let i = -4; i <= 4; i++) {
    // 直接給 MAT.wood。原本先傳 MAT.culm 再覆寫 material —— 結果一樣，
    // 但會讓人以為這裡真的用得到那個「白底＋instanceColor」的材質。
    const b = cyl(0.11, 0.11, 7.2, MAT.wood, i * 0.24, 0.42, 0, 6, g);
    b.rotation.x = Math.PI / 2;
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
}

/** 兔祠 —— 林中的小祠，妖怪兔在這附近特別多 */
function rabbitShrine(cx, cz) {
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
}

/** 古鳥居 —— 半個埋在竹林裡，紅漆剝落 */
function oldTorii(cx, cz) {
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
}

/** 永遠亭の門 —— 南端的終點，下一張圖的入口 */
function eienteiGate(cx, cz) {
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
}


/* 依空地的 kind 擺上建築。空地位置是隨機生成的（見 CLEARINGS），
 * 所以每一片林子的建築佈局都不一樣，但同一個種子每次重整都一樣。 */
for (const c of CLEARINGS) {
  switch (c.kind) {
    case 'jizo': jizoShelter(c.x, c.z); break;
    case 'hut': ruinedHut(c.x, c.z); break;
    case 'shrine': rabbitShrine(c.x, c.z); break;
    case 'torii': oldTorii(c.x, c.z); break;
    case 'bridge': bambooBridge(c.x, c.z); break;
    case 'rest': {
      // 休息點：一尊地藏 + 一張竹凳
      jizo(c.x, c.z, rand() * 6.28);
      const by = heightAt(c.x + 2.4, c.z);
      box(1.8, 0.16, 0.5, MAT.wood, c.x + 2.4, by + 0.42, c.z);
      for (const sd of [-1, 1]) cyl(0.07, 0.08, 0.42, MAT.wood, c.x + 2.4 + sd * 0.7, by + 0.21, c.z, 6);
      break;
    }
    default: break;   // 'gate' 由下面的永遠亭門／北口自己處理
  }
}
eienteiGate(SOUTH_END.x, SOUTH_END.z);

/* 散落的石頭與竹筍（讓地面不會一片空） */
(function scatter() {
  /** 沿著小徑網撒點（見獸道同名做法）：亂撒的命中率太低 */
  const near = (minD, maxD) => {
    const sm = PATHS.samples[(rand() * PATHS.samples.length) | 0];
    const a = rand() * Math.PI * 2, d = rr(minD, maxD);
    return [sm.x + Math.cos(a) * d, sm.z + Math.sin(a) * d];
  };
  for (let i = 0; i < 180; i++) {
    const [x, z] = near(2.4, 26);
    if (pathDist(x, z) < 1.6 || Math.abs(x) > HALF_W || Math.abs(z) > LEN) continue;
    const r = rr(0.2, 0.7);
    const rock = new THREE.Mesh(new THREE.IcosahedronGeometry(r, 0), MAT.mossStone);
    rock.position.set(x, heightAt(x, z) + r * 0.4, z);
    rock.rotation.set(rand() * 3, rand() * 3, rand() * 3);
    rock.castShadow = rock.receiveShadow = true;
    world.add(rock);
  }
  /* 地面枯葉。竹林的地是一層厚厚的落葉腐植層 —— 只靠地面貼圖畫葉子，
   * 走近看還是一張平的圖。這裡撒一層實體的葉片：貼著地、幾乎水平、
   * 大小與角度各異，走過去才有「踩在落葉上」的層次。
   *
   * 一片就是一個四邊形（2 個三角形），三千片才六千個三角形 —— 比多
   * 一根竹子還便宜。castShadow 關掉：貼地的薄片投影只會變成髒點。 */
  {
    const leafGeo = new THREE.PlaneGeometry(0.34, 0.11);
    leafGeo.rotateX(-Math.PI / 2);                    // 攤平躺在地上
    const litterMat = new THREE.MeshStandardMaterial({
      color: 0xffffff, roughness: 1, side: THREE.DoubleSide });
    const mats = [];
    const lm = new THREE.Matrix4(), lq = new THREE.Quaternion();
    const le = new THREE.Euler(), lv = new THREE.Vector3(), ls = new THREE.Vector3();
    const cols = [];
    const lc = new THREE.Color();
    for (let i = 0; i < 4200; i++) {
      const [x, z] = near(1.0, 34);
      if (Math.abs(x) > HALF_W || Math.abs(z) > LEN) continue;
      const sz = rr(0.7, 1.9);
      // 幾乎水平，只給一點翹起 —— 完全貼平會看不出是一片一片
      le.set(rr(-0.22, 0.22), rand() * 6.28, rr(-0.22, 0.22));
      lq.setFromEuler(le);
      ls.set(sz, 1, sz);
      lv.set(x, heightAt(x, z) + 0.012 + rand() * 0.02, z);
      mats.push(lm.clone().compose(lv, lq, ls));
      // 枯到半枯：黃褐 → 帶點暗綠
      const t = rand();
      // 亮度上限壓到 0.20：林下大部分是暗的，但穿過天蓋的光斑會直接打在
      // 落葉上 —— 反照率留在 0.30 的話那幾片會爆成刺眼的白色亮片。
      lc.setHSL(0.09 + t * 0.06, 0.34 - t * 0.12, 0.10 + t * 0.10);
      cols.push(lc.r, lc.g, lc.b);
    }
    const im = new THREE.InstancedMesh(leafGeo, litterMat, mats.length);
    mats.forEach((mm, i) => im.setMatrixAt(i, mm));
    im.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(cols), 3);
    im.instanceMatrix.needsUpdate = true;
    im.instanceColor.needsUpdate = true;
    im.castShadow = false;
    im.receiveShadow = true;
    im.userData.noMerge = true;
    world.add(im);
    console.info(`[bamboo] 地面枯葉 ${mats.length} 片`);
  }

  /* 筍株（升級書・升級 6 第 5 點的「地上一串長出來」）。
   *
   * 原本是單根散落的小圓錐。改成「一個基座冒出 3~6 根不等高的筍/幼竹」，
   * 而且**聚落式分布**：用 fbm 決定哪裡是筍區，不是均勻亂撒 ——
   * 均勻撒出來每個角落都一樣，走過去沒有「這裡不一樣」的感覺。
   *
   * 全部合進一個 InstancedMesh：一株 3~6 根、一百多株就是好幾百個物件。 */
  const CLUMP_N = 130;
  const shootMats = [];
  const sm4 = new THREE.Matrix4(), sq = new THREE.Quaternion();
  const se = new THREE.Euler(), sv = new THREE.Vector3(), ss = new THREE.Vector3();
  for (let i = 0; i < CLUMP_N * 3; i++) {
    if (shootMats.length >= CLUMP_N * 5) break;
    const [x, z] = near(2.2, 30);
    if (pathDist(x, z) < 1.4 || Math.abs(x) > HALF_W || Math.abs(z) > LEN) continue;
    // 聚落：fbm 高於門檻的地方才長。0.02 的頻率 ≈ 50 公尺一個聚落
    if (fbm(x * 0.02, z * 0.02, { period: 12, octaves: 3, seed: 91 }) < 0.52) continue;
    const n = 3 + (rand() * 4 | 0);
    for (let k = 0; k < n; k++) {
      const a = rand() * 6.28, d = rr(0.15, 0.75);
      const sx = x + Math.cos(a) * d, sz = z + Math.sin(a) * d;
      // 高度差很重要：一株裡有剛冒頭的、也有快變成竹子的，才像在長
      const hh = rr(0.5, 3.0);
      const rr2 = 0.09 + (hh / 3) * 0.06;
      se.set(rr(-0.09, 0.09), rand() * 6.28, rr(-0.09, 0.09));
      sq.setFromEuler(se);
      ss.set(rr2 / 0.13, hh, rr2 / 0.13);
      sv.set(sx, heightAt(sx, sz) + hh * 0.5, sz);
      shootMats.push(sm4.clone().compose(sv, sq, ss));
    }
  }
  {
    const g = new THREE.ConeGeometry(0.13, 1, 6);
    const im = new THREE.InstancedMesh(g, MAT.shoot, shootMats.length);
    shootMats.forEach((mm, i) => im.setMatrixAt(i, mm));
    im.instanceMatrix.needsUpdate = true;
    im.castShadow = true;
    im.userData.noMerge = true;
    world.add(im);
    console.info(`[bamboo] 筍株 ${shootMats.length} 根（聚落式）`);
  }
})();

/* ────────────────────────────── 地標引導系統（升級 6 第 2 點） ── */
/**
 * 路面拆掉之後，認路全靠地標。四種各自負責不同的訊息：
 *
 *   紅布條竹  —— 「這是正解路徑」。沿主徑每 34 公尺一根，綁在最近的竹子上。
 *                布條刻意做小（0.5×0.34），遠看只是一點紅，走近才讀得出來。
 *   石燈籠    —— 「離永遠亭還有多遠」。密度往南遞增，愈接近終點愈常見。
 *                部分傾倒 —— 全部立正會變成路燈，那又變回一條看得見的路。
 *   地藏      —— 「往這邊」。擺在岔路口，面朝正解方向。
 *   竹筍叢    —— 「此路不通」。死路端的軟性阻擋（上面 scatter() 已經撒了，
 *                這裡在支徑末端再補一圈密的）。
 *
 * 全部只讀 PathNet 的資料，不畫出任何路面。
 */
(function landmarks() {
  const main = catmullRom(TRAIL_SEGMENTS[0].pts, 3);

  // --- 紅布條竹 ---
  const clothMat = new THREE.MeshStandardMaterial({
    color: '#b8402f', roughness: 0.9, side: THREE.DoubleSide });
  let ribbons = 0;
  for (let i = 0; i < main.length; i++) {
    if (i % 12) continue;                       // catmullRom step 3 → 約每 36 公尺
    const [px, pz] = main[i];
    // 綁在路邊 2.5~4 公尺處的一根竹子上（那裡本來就長得到竹子）
    const a = (i % 2 ? 1 : -1) * (Math.PI / 2);
    const dx = main[Math.min(i + 1, main.length - 1)][0] - px;
    const dz = main[Math.min(i + 1, main.length - 1)][1] - pz;
    const tl = Math.hypot(dx, dz) || 1;
    const ox = (dz / tl) * Math.cos(a) * 3.2, oz = (-dx / tl) * Math.cos(a) * 3.2;
    const x = px + ox, z = pz + oz;
    if (Math.abs(x) > HALF_W || Math.abs(z) > LEN) continue;
    const y = heightAt(x, z);
    // 竹竿（自己立一根，才保證布條有東西可綁）
    cyl(0.075, 0.095, 9, MAT.culmSolid, x, y + 4.5, z, 6);
    const cloth = box(0.5, 0.34, 0.02, clothMat, x, y + 1.65, z + 0.06);
    cloth.rotation.y = rand() * 0.6 - 0.3;
    ribbons++;
  }

  // --- 石燈籠：密度往南（永遠亭方向）遞增 ---
  let lanterns = 0;
  for (let i = 0; i < main.length; i++) {
    const [px, pz] = main[i];
    // z 從 -282 到 282；t = 0 在北口、1 在南口
    const t = (pz + LEN) / (LEN * 2);
    if (rand() > 0.02 + t * 0.10) continue;
    const side = rand() < 0.5 ? -1 : 1;
    const x = px + side * rr(2.6, 5), z = pz + rr(-2, 2);
    if (Math.abs(x) > HALF_W || Math.abs(z) > LEN) continue;
    const y = heightAt(x, z);
    const g = new THREE.Group();
    g.position.set(x, y, z);
    // 三成是傾倒的 —— 全部立正就變成路燈，那又是一條看得見的路
    if (rand() < 0.3) g.rotation.z = rr(0.4, 1.2) * (rand() < 0.5 ? -1 : 1);
    g.rotation.y = rand() * 6.28;
    world.add(g);
    cyl(0.22, 0.28, 0.34, MAT.stone, 0, 0.17, 0, 6, g);
    cyl(0.13, 0.16, 0.9, MAT.mossStone, 0, 0.79, 0, 6, g);
    box(0.42, 0.4, 0.42, MAT.stone, 0, 1.44, 0, g);
    box(0.6, 0.1, 0.6, MAT.stone, 0, 1.69, 0, g);
    post(x, z, 0.3, y + 1.7);
    lanterns++;
  }

  // --- 地藏：岔路口，面朝正解（往南）方向 ---
  let jizos = 0;
  for (let k = 1; k < TRAIL_SEGMENTS.length; k++) {
    const seg = TRAIL_SEGMENTS[k];
    const [jx, jz] = seg.pts[0];                 // 支徑的起點就是岔路口
    if (Math.abs(jx) > HALF_W || Math.abs(jz) > LEN) continue;
    jizo(jx + rr(-1.6, 1.6), jz + rr(1.6, 3), Math.PI);   // 面朝 +z＝往永遠亭
    jizos++;
  }

  console.info(`[bamboo] 地標：紅布條竹 ${ribbons}、石燈籠 ${lanterns}、岔路地藏 ${jizos}`);
})();

/* ───────────────────────────────────────────── 傳送點 ── */
const northPortal = makePortalGlow(world, NORTH_END.x, heightAt(NORTH_END.x, NORTH_END.z), NORTH_END.z, 0xd8f0a0);
const southPortal = makePortalGlow(world, SOUTH_END.x, heightAt(SOUTH_END.x, SOUTH_END.z - 5), SOUTH_END.z - 5, 0xc0a8ff);
const eastPortal = makePortalGlow(world, EAST_END.x, heightAt(EAST_END.x, EAST_END.z), EAST_END.z, 0xd8e8a0);

/* 道標（升級5）：三個口各一塊，牌面朝林內 */
makeSignpost(world, NORTH_END.x + 2.6, heightAt(NORTH_END.x + 2.6, NORTH_END.z + 2), NORTH_END.z + 2, '往 獸道', 0);
makeSignpost(world, SOUTH_END.x + 2.6, heightAt(SOUTH_END.x + 2.6, SOUTH_END.z - 7), SOUTH_END.z - 7, '往 永遠亭', Math.PI);
makeSignpost(world, EAST_END.x - 2.2, heightAt(EAST_END.x - 2.2, EAST_END.z + 2.4), EAST_END.z + 2.4, '往 無名之丘', -Math.PI / 2);

/* ─────────────────────────────── 草叢與雜草（小徑沿線） ── */
scatterGrass(world, {
  count: 2600, heightAt,
  place: () => {
    const sm = PATHS.samples[(Math.random() * PATHS.samples.length) | 0];
    const a = Math.random() * Math.PI * 2, d = 1 + Math.random() * 18;
    const x = sm.x + Math.cos(a) * d, z = sm.z + Math.sin(a) * d;
    // 1.2 公尺的路緣留白：一叢草半徑約 0.5 公尺，貼著路緣種葉尖會蓋到路上
    if (pathDist(x, z) < 1.2) return null;
    if (Math.abs(x) > HALF_W || Math.abs(z) > LEN) return null;
    return [x, z];
  },
  baseColor: 0x5a7a34,
});

/* ────────────────── 北口遠景：獸道的森林谷地（傳送點看得到下一張圖） ── */
(function trailVista() {
  const g = new THREE.Group();
  g.position.set(NORTH_END.x, heightAt(NORTH_END.x, NORTH_END.z), NORTH_END.z - 14);
  world.add(g);
  const bark = new THREE.MeshStandardMaterial({ color: '#4a3828', roughness: 1 });
  const leafs = [
    new THREE.MeshStandardMaterial({ color: '#3d5c2a', roughness: 1, flatShading: true }),
    new THREE.MeshStandardMaterial({ color: '#557436', roughness: 1, flatShading: true }),
    new THREE.MeshStandardMaterial({ color: '#8f6a2c', roughness: 1, flatShading: true }),
  ];
  // 一條土徑穿出去、闊葉樹夾道 —— 跟獸道同一種樹，一眼認得出目的地
  for (let i = 0; i < 46; i++) {
    const z = -6 - Math.random() * 60;
    const x = (Math.random() < 0.5 ? -1 : 1) * (4 + Math.random() * 26);
    const h = 3.4 + Math.random() * 2.6;
    const t = new THREE.Mesh(new THREE.CylinderGeometry(0.17, 0.25, h, 7), bark);
    t.position.set(x, h / 2, z); g.add(t);
    for (let k = 0; k < 2; k++) {
      const r = 1.6 - k * 0.4;
      const c = new THREE.Mesh(new THREE.IcosahedronGeometry(r, 0),
        leafs[(Math.random() * leafs.length) | 0]);
      c.position.set(x + (Math.random() - 0.5) * 0.8, h + k * 0.8 - 0.2, z + (Math.random() - 0.5) * 0.8);
      g.add(c);
    }
  }
  // 遠處的山稜（獸道的谷壁剪影）
  const ridgeMat = new THREE.MeshStandardMaterial({ color: '#39543a', roughness: 1, flatShading: true });
  for (let i = 0; i < 7; i++) {
    const m = new THREE.Mesh(new THREE.ConeGeometry(16 + Math.random() * 14, 24 + Math.random() * 18, 5), ridgeMat);
    m.position.set((i - 3) * 24 + (Math.random() - 0.5) * 10, 8, -66 - Math.random() * 22);
    m.rotation.y = Math.random() * 3;
    g.add(m);
  }
  g.traverse(o => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
})();

/* ────────── 東口遠景：無名之丘的鈴蘭花海（傳送點看得到下一張圖） ── */
(function hillVista() {
  const g = new THREE.Group();
  const vx = EAST_END.x + 16;
  g.position.set(vx, heightAt(EAST_END.x, EAST_END.z), EAST_END.z);
  world.add(g);
  // 竹子在東緣戛然而止，露出一片開闊的草丘 —— 一眼就知道「出去是別的地形」
  const hillM = new THREE.MeshStandardMaterial({ color: '#8fa860', roughness: 1, flatShading: true });
  for (let i = 0; i < 9; i++) {
    const m = new THREE.Mesh(new THREE.SphereGeometry(14 + Math.random() * 12, 8, 5), hillM);
    m.position.set(8 + Math.random() * 40, -4 - Math.random() * 5, (i - 4) * 22 + (Math.random() - 0.5) * 12);
    m.scale.y = 0.42;
    g.add(m);
  }
  // 丘上的鈴蘭：白色小點成片（無名之丘的毒花海）
  const bellM = new THREE.MeshStandardMaterial({
    color: '#f0f4e8', roughness: 0.85, emissive: '#4a5a3a', emissiveIntensity: 0.15,
  });
  const bellGeo = new THREE.SphereGeometry(0.32, 5, 4);
  const bells = new THREE.InstancedMesh(bellGeo, bellM, 300);
  const m4 = new THREE.Matrix4(), v = new THREE.Vector3();
  for (let i = 0; i < 300; i++) {
    m4.makeTranslation(v.set(10 + Math.random() * 38, 1.5 + Math.random() * 2.5, (Math.random() - 0.5) * 190));
    bells.setMatrixAt(i, m4);
  }
  g.add(bells);
  g.traverse(o => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
})();

/* ──────── 南門後的永遠亭剪影（門雖未開放，先看得到深處的宅院） ── */
(function eienteiVista() {
  const g = new THREE.Group();
  // 放在南端圍坡「上面」——圍坡在 z≈292 之後抬 13 公尺，宅院要是放在
  // 門口的低地高度，整棟會被坡埋掉、從門口什麼都看不到。
  const vz = SOUTH_END.z + 24;
  g.position.set(SOUTH_END.x, heightAt(SOUTH_END.x, vz) + 0.5, vz);
  world.add(g);
  const wallM = new THREE.MeshStandardMaterial({ color: '#e8dcc2', roughness: 0.95 });
  const woodM = new THREE.MeshStandardMaterial({ color: '#4e3a2a', roughness: 0.95 });
  const tileM = new THREE.MeshStandardMaterial({ color: '#3e4650', roughness: 0.85, flatShading: true });
  // 大宅：長屋身 + 兩層大屋頂 + 側翼 —— 竹叢縫隙間讀得出「深處有一座宅院」
  const body = new THREE.Mesh(new THREE.BoxGeometry(34, 6, 12), wallM);
  body.position.set(0, 3, 0); g.add(body);
  for (const sd of [-1, 1]) {
    const slope = new THREE.Mesh(new THREE.BoxGeometry(38, 0.8, 8.4), tileM);
    slope.position.set(0, 7.6, sd * 3.4);
    slope.rotation.x = sd * 0.58;
    g.add(slope);
  }
  const ridge = new THREE.Mesh(new THREE.BoxGeometry(38.8, 1.1, 1.6), tileM);
  ridge.position.y = 9.4; g.add(ridge);
  for (const sd of [-1, 1]) {
    const wing = new THREE.Mesh(new THREE.BoxGeometry(9, 4.6, 16), wallM);
    wing.position.set(sd * 19, 2.3, 4); g.add(wing);
    const wr = new THREE.Mesh(new THREE.ConeGeometry(8.4, 3.4, 4), tileM);
    wr.position.set(sd * 19, 6.4, 4); wr.rotation.y = Math.PI / 4; g.add(wr);
  }
  // 簷下一排暖光燈籠 —— 夜裡也看得到深處有人家
  const paperM = new THREE.MeshStandardMaterial({
    color: '#ffefc8', emissive: '#a8742a', emissiveIntensity: 0.55, roughness: 0.9,
  });
  for (let i = -3; i <= 3; i++) {
    const l = new THREE.Mesh(new THREE.SphereGeometry(0.42, 8, 6), paperM);
    l.position.set(i * 4.6, 5.4, -6.4);
    g.add(l);
  }
  // 宅前竹垣
  for (let i = 0; i < 16; i++) {
    const c = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.1, 2.2, 5), woodM);
    c.position.set(-19 + i * 2.5, 1.1, -8.5);
    g.add(c);
  }
  g.traverse(o => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
})();

/* ─────────────── 圍坡上緣之外的遠景（升級1：遠景延伸） ── */
// 圍坡把玩家收在林子裡，但坡頂直接切天空。外圈鋪「更遠處還是竹海」
// 的剪影 —— 竹林的地平線應該是望不到頭的竹梢，不是土坡的邊。
ridgeRing(world, {
  radius: 400, heightAt,
  height: [26, 46], color: 0x3c5136, treeTops: true, seed: 13,
  gaps: [
    gapToward(NORTH_END.x, NORTH_END.z, 0.5),
    gapToward(SOUTH_END.x, SOUTH_END.z, 0.5),
    gapToward(EAST_END.x, EAST_END.z, 0.5),
  ],
});

/* ──────────────────────────────────────────── 靜態幾何合併 ── */
// 建築、地藏、石頭、竹筍全部不會動 —— 依「材質 × 空間格子」合併。
// 竹子是 InstancedMesh，合併會自動跳過（見 optimize.js 的 mergeable）。
{
  const s = mergeStaticByMaterial(world, { cell: 55 });
  console.info(`[optimize] 迷途竹林靜態合併：${s.before} → ${s.after} 個網格（合併成 ${s.merged}，保留 ${s.kept}）`);
}

/* ─────────────────────────────────────────────────────── 玩家 ── */
core.spawnPlayer({
  bounds: { hx: HALF_W + 8, hz: LEN + 10 },
  maxGrade: 1.05,   // 圍坡是山，爬不上去（見 controller 的坡度阻擋）
  // 出生點依來向分流：從永遠亭回來 = 南門；其他（獸道）= 北口
  spawn(from, ctrl) {
    if (from === 'eientei') {
      ctrl.teleport(SOUTH_END.x, SOUTH_END.z - 10);
      ctrl.yaw = Math.PI;        // 面向北（回獸道的方向）
      ctrl.camYaw = 0;
    } else if (from === 'namelessHill') {
      ctrl.teleport(EAST_END.x - 8, EAST_END.z);
      ctrl.yaw = -Math.PI / 2;   // 面向西（往竹林深處）
      ctrl.camYaw = Math.PI / 2;
    } else {
      ctrl.teleport(NORTH_END.x, NORTH_END.z + 8);
      ctrl.yaw = 0;              // 面向南（往永遠亭）
      ctrl.camYaw = Math.PI;
    }
  },
});
const ctrl = core.ctrl;

/* ─────────────────── 妹紅：竹林的嚮導（對話後可帶路去永遠亭） ── */
// 迷いの竹林的設定：妹紅住在林中，常替迷路的人（與去永遠亭求醫的人）
// 帶路。她站在主徑中段的路旁 —— 主徑是決定性隨機生成的，所以不能用
// roster 的固定 offset，得直接取路上的點。
const npcMgr = new NPCManager(scene, core.plateScene);
npcMgr.setRoster(['mokou'], REGION_BY_ID.bamboo, 340);
{
  const main = catmullRom(TRAIL_SEGMENTS[0].pts, 2.5);
  const i = Math.floor(main.length * 0.56);
  const [px, pz] = main[i], [qx, qz] = main[i + 1];
  const len = Math.hypot(qx - px, qz - pz) || 1;
  const nx = -(qz - pz) / len, nz = (qx - px) / len;      // 路的側向
  const mx = px + nx * 2.4, mz = pz + nz * 2.4;
  const rec = npcMgr.npcs[0];
  if (rec) {
    const my = heightAt(mx, mz);
    rec.root.position.set(mx, my, mz);
    rec.plate.position.set(mx, my + 2.35, mz);
    rec.pos.set(mx, my, mz);
    rec.baseYaw = Math.atan2(px - qx, pz - qz);           // 面向北邊的來向
    rec.root.rotation.y = rec.baseYaw;
  }
}
const dialogue = new Dialogue();
let guideOffer = 0;   // >0 = 妹紅的帶路邀請還有效（秒）

/* ───────────────────── 妖怪兔 + 成長系統 + 戰鬥 ── */
const prog = core.createProgression();
// 越往南（越靠近永遠亭）窩越密 —— 走進去要有「越來越難回頭」的壓力。
// 全部走 InstancedMesh，九十幾隻同屏也只有兩個 draw call。
// 兔窩沿著小徑網撒，越往南越密 —— 走向永遠亭要有「越來越難回頭」的壓力。
// 全部走 InstancedMesh，上百隻同屏也只有兩個 draw call。
const NESTS = (() => {
  const out = [];
  for (let i = 0; i < 14; i++) {
    const sm = PATHS.samples[(rand() * PATHS.samples.length) | 0];
    const a = rand() * Math.PI * 2;
    const d = rr(10, 20);
    out.push({ x: sm.x + Math.cos(a) * d, z: sm.z + Math.sin(a) * d, r: rr(7, 11) });
  }
  return out;
})();
const rabbits = new RabbitMobs(scene, NESTS, 9, {
  damage: 7,
  onAttack: (dmg) => kit.vitals.damage(dmg),
});
const mobs = progressMobs(rabbits, prog, 'hinokami', '日之呼吸');

/* 角色的隨身裝備：HP/MP、戰鬥、技能、技能視窗（K）。
 * 這一整套是角色內建的，每張圖都掛同一份 —— 見 src/player/loadout.js。 */
const kit = core.installKit({
  mobs,
  isBlocked: () => escMenu.isOpen || dialogue.active,
  onDeath: () => {
    ctrl.teleport(NORTH_END.x, NORTH_END.z + 8);
    HUD.toast('你在竹林裡倒下了 —— 有人把你拖回了林口。');
  },
});

/* ───────────────────────────────────────────── 互動與提示 ── */
const toast = (msg, dur = 2600) => HUD.toast(msg, dur);

const escMenu = core.bindEsc();

/* ─────────────────────── 大地圖（M）與小地圖（N 開關）── 升級5 ── */
core.installMapUI({
  current: 'bamboo',
  isBlocked: () => dialogue.active || escMenu.isOpen,
  minimap: {
    bounds: { minX: -155, maxX: 155, minZ: -300, maxZ: 300 },
    /* 這裡刻意不傳 paths（升級書・升級 6）。世界裡的路面已經拆掉，
     * 小地圖再把路網畫出來就等於把它還給玩家了。 */
    /* 離邊界超過 60 公尺就是「深處」：小地圖不再顯示自己在哪，只剩
     * 邊界與出口。妹紅嚮導仍然是安全出口（付費直達永遠亭）。 */
    lost: () => {
      const p = core.ctrl?.pos;
      if (!p) return false;
      return Math.min(HALF_W - Math.abs(p.x), LEN - Math.abs(p.z)) > 60;
    },
    portals: [
      { x: NORTH_END.x, z: NORTH_END.z, label: '獸道', color: '#d8f0a0' },
      { x: SOUTH_END.x, z: SOUTH_END.z, label: '永遠亭', color: '#c0a8ff' },
      { x: EAST_END.x, z: EAST_END.z, label: '無名之丘', color: '#d8e8a0' },
    ],
  },
});

const nearNorth = () => Math.hypot(ctrl.pos.x - NORTH_END.x, ctrl.pos.z - NORTH_END.z) < 4.8;
const nearSouth = () => Math.hypot(ctrl.pos.x - SOUTH_END.x, ctrl.pos.z - (SOUTH_END.z - 5)) < 4.8;
const nearEast = () => Math.hypot(ctrl.pos.x - EAST_END.x, ctrl.pos.z - EAST_END.z) < 5.2;

// ※ 這段刻意不走 core.installTalk：妹紅的互動是兩段式的（對話 → 8 秒內
//   再按 E 就跟她走），installTalk 的「NPC 對話恆為最優先」表達不了。
window.addEventListener('keydown', (e) => {
  if (e.code !== 'KeyE' || escMenu.isOpen) return;
  // 對話進行中：E 只推進，不落到下面的互動判定
  if (dialogue.active) { dialogue.advance(); return; }
  if (!ctrl.locked) return;

  // 妹紅：先對話；講完後的幾秒內再按 E = 讓她帶路去永遠亭
  const npc = npcMgr.nearest;
  if (npc && npc.pos.distanceTo(ctrl.pos) <= TALK_RANGE) {
    if (guideOffer > 0) {
      guideOffer = 0;
      ctrl.teleport(SOUTH_END.x, SOUTH_END.z - 12);
      ctrl.yaw = 0;
      ctrl.camYaw = Math.PI;
      toast('妹紅領著你在竹影裡左拐右繞 —— 回過神來，永遠亭的門就在眼前。', 3600);
      return;
    }
    ctrl.enabled = false;
    dialogue.open(npc.spec, npcMgr.nextTalk(npc), () => {
      ctrl.enabled = true;
      guideOffer = 8;
    });
    return;
  }

  if (nearNorth()) { HUD.showLoading('獸道 讀取中'); location.href = '../trail/?from=bamboo'; return; }
  if (nearSouth()) { HUD.showLoading('永遠亭 讀取中'); location.href = '../eientei/?from=bamboo'; return; }
  if (nearEast()) { HUD.showLoading('無名之丘 讀取中'); location.href = '../namelessHill/?from=bamboo'; }
});

/* ─────────────────────────────────────────────────── 主迴圈 ── */
// kit 結算之後、env 之前：妖怪兔、NPC、對話、帶路邀請倒數（原樣板的順序）
core.onUpdate((dt, rawDt, t) => {
  rabbits.update(dt, t, ctrl.pos);
  npcMgr.update(t, ctrl.pos, camera);
  dialogue.update(dt);
  guideOffer = Math.max(0, guideOffer - dt);
});

// env 之後、minimap 之前：三個傳送點的呼吸動畫
core.onLateUpdate((dt, rawDt, t) => {
  northPortal.userData.update(t);
  southPortal.userData.update(t);
  eastPortal.userData.update(t);
});

// minimap.update() 之後：HUD 提示（原本就排在小地圖後面）
core.onPostUpdate(() => {
  if (dialogue.active) { HUD.prompt(null); return; }
  const npc = npcMgr.nearest;
  if (npc && npc.pos.distanceTo(ctrl.pos) <= TALK_RANGE) {
    HUD.prompt(guideOffer > 0 ? '[ E ]  跟妹紅走（去永遠亭）' : '[ E ]  與 藤原妹紅 對話');
  } else if (nearNorth()) HUD.prompt('[ E ]  返回獸道');
  else if (nearSouth()) HUD.prompt('[ E ]  進入永遠亭');
  else if (nearEast()) HUD.prompt('[ E ]  往無名之丘');
  else HUD.prompt(null);
});

core.start();

// debug handle（跟其他地圖同一套測試口徑）
window.__bamboo = core.debugHandle({
  rabbits, npcMgr, dialogue,
  PATHS, CLEARINGS, NORTH_END, SOUTH_END, EAST_END,
});

/* 色調分級 LUT（升級書 4.4）—— 這張圖的色調個性。
 * 各地區的預設值集中在 src/world/lut.js，改的時候看得到彼此的關係。 */
core.setLUT(buildLUT(LUT_PRESETS.bamboo));

/* 環境生命：竹葉飄落 ＋ 高處掠過的飛鳥。
 * 地上已經鋪了枯葉，飄落用的是同一組視覺語彙 —— 葉子從天蓋落到地面，
 * 兩者接得起來。 */
const amb = new Ambience(world, 47);
amb.drift({ cx: 0, cz: 0, hx: 90, hz: 220, top: 13, groundAt: heightAt,
  count: 120, fall: 0.65, color: 0xa8a860, size: 0.16 });
amb.birds({ cx: 0, cz: -40, r: 150, y: 40, count: 4, speed: 0.045 });
core.onUpdate((dt, rawDt, t) => amb.update(dt, t));
