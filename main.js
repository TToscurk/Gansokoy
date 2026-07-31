/**
 * 博麗神社 / Hakurei Shrine — walkable 3D scene
 * Fan-made, unofficial. Built with three.js, no external assets.
 */
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { GTAOPass } from 'three/addons/postprocessing/GTAOPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { SMAAPass } from 'three/addons/postprocessing/SMAAPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { spawnAllNPCs } from './src/entities/shrine-spawn.js';
import { setGroundHeightFn } from './src/world/terrain.js';
import { WORLD } from './src/config.js';
import { ZoneTracker } from './src/world/zones.js';
import { clockLabel, isNightAt } from './src/world/daycycle.js';
import { WEATHERS } from './src/world/weather.js';
import { Environment } from './src/world/environment.js';
import { makePortalGlow } from './src/world/portal.js';
import { buildCharacter } from './src/entities/model.js';
import { ACTIVE_PLAYABLE, DEFAULT_PLAYER } from './src/entities/roster.js';
import { TALK_RANGE as TALK_REACH } from './src/entities/npc.js';
import { PlayerController } from './src/player/controller.js';
import { Dialogue } from './src/ui/dialogue.js';
import { QuestManager } from './src/quests/manager.js';
import { QuestLog } from './src/ui/questlog.js';
import { SceneEditor } from './src/ui/scene-editor.js';
import { installHUD, bindEscMenu } from './src/ui/hud.js';
import { Combat } from './src/combat/combat.js';
import { SlashFX, SlashAudio } from './src/fx/slash.js';
import { combatHUD, bindCombatInput } from './src/combat/hud.js';
import { Progression } from './src/player/progression.js';
import { loadQualityIdx, saveQualityIdx } from './src/world/quality.js';
import { mergeStaticByMaterial, keepDynamic } from './src/core/optimize.js';

/* ─────────────────────────────────────────────────────────────── HUD ── */
// 全地圖共用的 HUD（準心、地名、提示、操作列、戰鬥 HUD、ESC 選單、讀取畫面）。
// 要在任何 getElementById 之前裝好。
const HUD = installHUD({
  title: '博麗神社',
  subtitle: 'HAKUREI SHRINE',
  keys: [
    ['WASD / 方向鍵', '移動'], ['滑鼠', '轉視角'], ['滾輪', '縮放'],
    ['Shift', '衝刺'], ['Space', '跳躍'],
    ['E', '互動'], ['J', '任務'], ['P', '場景編輯'], ['ESC', '選單'],
  ],
  flyKeys: [['F', '飛行'], ['Ctrl/C', '下降']],
  combatKeys: [['左鍵', '出招'], ['長按左鍵', '日之呼吸・全型'], ['R', '拔刀/納刀']],
});

/* ────────────────────────────────────────────────────────────── textures ── */
/** Draw into a canvas and return a repeating CanvasTexture. */
function makeTexture(size, draw, repeatX = 1, repeatY = 1) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  draw(c.getContext('2d'), size);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(repeatX, repeatY);
  t.anisotropy = 8;
  return t;
}

function noise(ctx, size, amount, alpha) {
  const img = ctx.getImageData(0, 0, size, size);
  const d = img.data;
  for (let i = 0; i < d.length; i += 4) {
    const n = (Math.random() - 0.5) * amount;
    d[i] += n; d[i + 1] += n; d[i + 2] += n;
    if (alpha) d[i + 3] = d[i + 3];
  }
  ctx.putImageData(img, 0, 0);
}

const TEX = {
  wood: (rx = 1, ry = 1) => makeTexture(256, (g, s) => {
    g.fillStyle = '#6d4a30'; g.fillRect(0, 0, s, s);
    for (let i = 0; i < 220; i++) {
      g.strokeStyle = `rgba(${40 + Math.random() * 60},${25 + Math.random() * 35},${12 + Math.random() * 20},${0.12 + Math.random() * 0.3})`;
      g.lineWidth = 0.5 + Math.random() * 2.4;
      const x = Math.random() * s;
      g.beginPath(); g.moveTo(x, 0);
      g.bezierCurveTo(x + (Math.random() - 0.5) * 12, s / 3, x + (Math.random() - 0.5) * 12, s * 0.66, x + (Math.random() - 0.5) * 8, s);
      g.stroke();
    }
    noise(g, s, 16);
  }, rx, ry),

  lacquer: (rx = 1, ry = 1) => makeTexture(128, (g, s) => {
    g.fillStyle = '#b8402f'; g.fillRect(0, 0, s, s);
    for (let i = 0; i < 90; i++) {
      g.strokeStyle = `rgba(${120 + Math.random() * 60},${30 + Math.random() * 25},${20 + Math.random() * 20},.28)`;
      g.lineWidth = 0.6 + Math.random() * 1.6;
      const x = Math.random() * s;
      g.beginPath(); g.moveTo(x, 0); g.lineTo(x + (Math.random() - 0.5) * 6, s); g.stroke();
    }
    noise(g, s, 12);
  }, rx, ry),

  stone: (rx = 1, ry = 1) => makeTexture(256, (g, s) => {
    g.fillStyle = '#8d8b83'; g.fillRect(0, 0, s, s);
    for (let i = 0; i < 900; i++) {
      const r = Math.random() * 3.2;
      g.fillStyle = `rgba(${90 + Math.random() * 90},${88 + Math.random() * 85},${82 + Math.random() * 80},${0.15 + Math.random() * 0.4})`;
      g.beginPath(); g.arc(Math.random() * s, Math.random() * s, r, 0, 7); g.fill();
    }
    for (let i = 0; i < 26; i++) {
      g.strokeStyle = 'rgba(60,58,54,.22)'; g.lineWidth = 0.8;
      g.beginPath(); g.moveTo(Math.random() * s, Math.random() * s);
      g.lineTo(Math.random() * s, Math.random() * s); g.stroke();
    }
    noise(g, s, 22);
  }, rx, ry),

  /* coursed stone blocks, for retaining walls */
  masonry: (rx = 1, ry = 1) => makeTexture(256, (g, s) => {
    g.fillStyle = '#6f6b60'; g.fillRect(0, 0, s, s);
    const rows = 6, h = s / rows;
    for (let r = 0; r < rows; r++) {
      const cols = 4, w = s / cols, off = (r % 2) * w * 0.5;
      for (let c = -1; c <= cols; c++) {
        const v = 120 + Math.random() * 55;
        g.fillStyle = `rgb(${v + 6},${v + 2},${v - 8})`;
        g.fillRect(c * w + off + 2, r * h + 2, w - 4, h - 4);
      }
    }
    for (let i = 0; i < 500; i++) {
      g.fillStyle = `rgba(70,66,58,${Math.random() * 0.22})`;
      g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 1 + Math.random() * 4, 0, 7); g.fill();
    }
    noise(g, s, 18);
  }, rx, ry),

  ground: (rx = 1, ry = 1) => makeTexture(512, (g, s) => {
    g.fillStyle = '#4a5a34'; g.fillRect(0, 0, s, s);
    for (let i = 0; i < 2600; i++) {
      const v = Math.random();
      g.fillStyle = v > 0.72
        ? `rgba(${96 + Math.random() * 40},${86 + Math.random() * 30},${52 + Math.random() * 24},.5)`
        : `rgba(${52 + Math.random() * 55},${72 + Math.random() * 50},${34 + Math.random() * 34},.55)`;
      g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 1 + Math.random() * 7, 0, 7); g.fill();
    }
    noise(g, s, 26);
  }, rx, ry),

  /* 榻榻米：藺草編織的細橫紋 + 每張蓆的黑色緣（へり） */
  tatami: (rx = 1, ry = 1) => makeTexture(256, (g, s) => {
    g.fillStyle = '#8a9a5b'; g.fillRect(0, 0, s, s);
    for (let y = 0; y < s; y += 2) {
      g.strokeStyle = `rgba(${110 + Math.random() * 30},${125 + Math.random() * 30},${70 + Math.random() * 20},.45)`;
      g.lineWidth = 1;
      g.beginPath(); g.moveTo(0, y + Math.random()); g.lineTo(s, y + Math.random()); g.stroke();
    }
    // 蓆緣：畫面左右兩側的深色帶（貼圖重複時就是一張張蓆的分界）
    g.fillStyle = '#2a2a30';
    g.fillRect(0, 0, 7, s);
    g.fillRect(s - 7, 0, 7, s);
    noise(g, s, 10);
  }, rx, ry),

  gravel: (rx = 1, ry = 1) => makeTexture(256, (g, s) => {
    g.fillStyle = '#a09889'; g.fillRect(0, 0, s, s);
    for (let i = 0; i < 2200; i++) {
      const v = 120 + Math.random() * 80;                 // grey pebbles, barely tinted
      g.fillStyle = `rgba(${v + 8},${v + 3},${v - 6},${0.25 + Math.random() * 0.45})`;
      g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 0.8 + Math.random() * 2.6, 0, 7); g.fill();
    }
    noise(g, s, 14);
  }, rx, ry),

  roof: (rx = 1, ry = 1) => makeTexture(256, (g, s) => {
    g.fillStyle = '#5c6f6d'; g.fillRect(0, 0, s, s);
    const rows = 10, h = s / rows;
    for (let r = 0; r < rows; r++) {
      const y = r * h;
      g.fillStyle = `rgba(${28 + Math.random() * 14},${38 + Math.random() * 16},${38 + Math.random() * 16},.6)`;
      g.fillRect(0, y, s, h * 0.16);
      g.fillStyle = 'rgba(120,148,142,.09)';
      g.fillRect(0, y + h * 0.16, s, h * 0.1);
    }
    for (let i = 0; i < 500; i++) {
      g.fillStyle = `rgba(${60 + Math.random() * 60},${86 + Math.random() * 60},${80 + Math.random() * 50},${Math.random() * 0.22})`;
      g.fillRect(Math.random() * s, Math.random() * s, 2 + Math.random() * 8, 1 + Math.random() * 3);
    }
    noise(g, s, 16);
  }, rx, ry),

  shoji: () => makeTexture(256, (g, s) => {
    g.fillStyle = '#e8dfc8'; g.fillRect(0, 0, s, s);
    noise(g, s, 14);
    g.strokeStyle = 'rgba(90,66,42,.75)'; g.lineWidth = 5;
    for (let i = 1; i < 4; i++) {
      g.beginPath(); g.moveTo(0, (s / 4) * i); g.lineTo(s, (s / 4) * i); g.stroke();
      g.beginPath(); g.moveTo((s / 4) * i, 0); g.lineTo((s / 4) * i, s); g.stroke();
    }
    g.strokeStyle = 'rgba(70,50,32,.9)'; g.lineWidth = 9;
    g.strokeRect(0, 0, s, s);
  }),

  /* folded paper streamer, transparent background */
  shide: () => makeTexture(128, (g, s) => {
    g.fillStyle = '#fdfaf2';
    g.fillRect(s * 0.42, 0, s * 0.16, s);
    const bars = [[0.58, 0.90, 0.04, 0.24], [0.10, 0.42, 0.28, 0.48],
                  [0.58, 0.90, 0.52, 0.72], [0.10, 0.42, 0.76, 0.99]];
    for (const [x1, x2, y1, y2] of bars) g.fillRect(s * x1, s * y1, s * (x2 - x1), s * (y2 - y1));
    g.globalCompositeOperation = 'multiply';
    g.fillStyle = 'rgba(214,206,190,.55)';
    g.fillRect(s * 0.42, 0, s * 0.06, s);
  }),

  ofuda: () => makeTexture(128, (g, s) => {
    g.fillStyle = '#f2ece0'; g.fillRect(0, 0, s, s);
    noise(g, s, 10);
    g.fillStyle = '#b03024';
    g.font = 'bold 40px "Yu Mincho", serif';
    g.textAlign = 'center';
    ['博', '麗', '神'].forEach((ch, i) => g.fillText(ch, s / 2, 40 + i * 40));
  }),
};

/* ─────────────────────────────────────────────────────── scene & renderer ── */
const renderer = new THREE.WebGLRenderer({ antialias: false, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(72, innerWidth / innerHeight, 0.08, 800);

/* 晝夜 + 天氣：共用的環境系統（src/world/environment.js）。
 * 神社自己的追加調色（燈籠、星空、bloom、IBL 重烘）之後在
 * applyTime 的 onApply/onEnvBake 回呼裡接上（見下方 env.opts 設定）。 */
const env = new Environment(scene, renderer, {
  shadowArea: 78,
  sunPivot: new THREE.Vector3(0, 2, -2),
});
const sky = env.sky, sun = env.sun, hemi = env.hemi;

/* ───────────────────────────────────── image-based lighting from the sky ──
 * The closest stand-in for a Lumen-style sky light: prefilter the sky dome
 * into an environment map so every material picks up skylight and a rough
 * specular response, instead of being lit by punctual lights alone. */
const pmrem = new THREE.PMREMGenerator(renderer);
pmrem.compileEquirectangularShader();
const envScene = new THREE.Scene();
envScene.add(new THREE.Mesh(sky.geometry, sky.material));
let envRT = null;
function updateEnvironment() {
  const prev = envRT;
  envRT = pmrem.fromScene(envScene, 0.0, 1, 1000);   // far must clear the 400-unit dome
  scene.environment = envRT.texture;
  prev?.dispose();
}
scene.environmentIntensity = 0.55;

/* ────────────────────────────────────────────────────────────── helpers ── */
const world = new THREE.Group();
scene.add(world);

/** Axis-aligned blockers the player can't walk through.
 *
 * 場上的實體物件（樹、鳥居柱、燈籠、狛犬、欄杆、岩石、建物牆柱……）
 * 都要有碰撞，走過去會被實實在在擋住。之前碰到會「被推移」是控制器的
 * 問題（推開位置卻沒清掉往牆裡的速度，於是每幀擠進去又被彈出來），
 * 已在 PlayerController._killInward 修好 —— 所以這裡可以放心設實心。
 * 碰撞盒請貼合實際模型尺寸，不要外擴成看不見的空氣牆。 */
const colliders = [];
function block(x, z, sx, sz, top, bottom = -99) {
  colliders.push({ minX: x - sx / 2, maxX: x + sx / 2, minZ: z - sz / 2, maxZ: z + sz / 2, top, bottom });
}

const MAT = {};
function mats() {
  MAT.wood = new THREE.MeshStandardMaterial({ map: TEX.wood(1, 2), roughness: 0.85, color: '#c9b49c' });
  MAT.darkWood = new THREE.MeshStandardMaterial({ map: TEX.wood(1, 2), roughness: 0.9, color: '#7a6146' });
  MAT.plank = new THREE.MeshStandardMaterial({ map: TEX.wood(4, 1), roughness: 0.82, color: '#e0c6a4' });
  MAT.red = new THREE.MeshStandardMaterial({ map: TEX.lacquer(1, 3), roughness: 0.48, color: '#ff6a55' });
  MAT.redFlat = new THREE.MeshStandardMaterial({ map: TEX.lacquer(1, 1), roughness: 0.5, color: '#ff6a55' });
  MAT.stone = new THREE.MeshStandardMaterial({ map: TEX.stone(1, 1), roughness: 0.95, color: '#cfcabc' });
  MAT.stoneBig = new THREE.MeshStandardMaterial({ map: TEX.masonry(12, 1), roughness: 0.95, color: '#c6c3b8' });
  MAT.roof = new THREE.MeshStandardMaterial({ map: TEX.roof(6, 3), roughness: 0.72, color: '#dfe9e4', side: THREE.DoubleSide });
  MAT.shoji = new THREE.MeshStandardMaterial({ map: TEX.shoji(), roughness: 0.9, color: '#fff6e0' });
  MAT.white = new THREE.MeshStandardMaterial({ color: '#f4efe4', roughness: 0.75, side: THREE.DoubleSide });
  MAT.shide = new THREE.MeshStandardMaterial({
    map: TEX.shide(), color: '#fffdf6', roughness: 0.9,
    transparent: true, alphaTest: 0.45, side: THREE.DoubleSide,
  });
  MAT.ofuda = new THREE.MeshStandardMaterial({ map: TEX.ofuda(), roughness: 0.85, side: THREE.DoubleSide });
  MAT.rope = new THREE.MeshStandardMaterial({ color: '#d9cfa8', roughness: 1 });
  MAT.gold = new THREE.MeshStandardMaterial({ color: '#c9a227', roughness: 0.35, metalness: 0.8 });
  MAT.tatami = new THREE.MeshStandardMaterial({ map: TEX.tatami(3, 2), roughness: 0.95, color: '#dfe6c8' });
  MAT.futonRed = new THREE.MeshStandardMaterial({ color: '#c0453f', roughness: 0.9 });
  MAT.futonPlum = new THREE.MeshStandardMaterial({ color: '#8a5aa8', roughness: 0.9 });
  MAT.futonWhite = new THREE.MeshStandardMaterial({ color: '#f2ecdc', roughness: 0.95 });
  MAT.bark = new THREE.MeshStandardMaterial({ color: '#5b4534', roughness: 1 });
  MAT.leafGreen = new THREE.MeshStandardMaterial({ color: '#4a6b33', roughness: 1, flatShading: true });
  MAT.leafRed = new THREE.MeshStandardMaterial({ color: '#a83c2c', roughness: 1, flatShading: true });
  MAT.leafGold = new THREE.MeshStandardMaterial({ color: '#b7772a', roughness: 1, flatShading: true });
}
mats();

function box(w, h, d, mat, x, y, z, parent = world) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
  m.position.set(x, y, z);
  m.castShadow = m.receiveShadow = true;
  parent.add(m);
  return m;
}
function cyl(rt, rb, h, mat, x, y, z, seg = 14, parent = world) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(rt, rb, h, seg), mat);
  m.position.set(x, y, z);
  m.castShadow = m.receiveShadow = true;
  parent.add(m);
  return m;
}

/* ───────────────────────────────────────────────────────────── terrain ── */
/* Two levels: forecourt at y=0, shrine plateau at y=PLATEAU, joined by stairs. */
const PLATEAU = 3.2;
const STAIR_FAR = 21, STAIR_NEAR = 14;    // z range of the staircase
const STAIR_HALF_W = 5.6;                 // half-width of the physical stone steps (11 wide) + margin
// Retaining wall flanking the stairs: runs the full ramp z-depth and out past the
// player's movement bound (ctrl.bounds.hx=78), so there's no way to walk around
// the stairs through open ground beside/beyond the wall. Shared with the tree
// scatter below so trees don't get planted inside the (now wider) wall footprint.
const WALL_INNER_X = 6, WALL_OUTER_X = 92;
const RAMP_CZ = (STAIR_NEAR + STAIR_FAR) / 2, RAMP_SZ = (STAIR_FAR - STAIR_NEAR) + 4;
// 境外延伸：前庭南端一條「長長的」下山石階（神社蓋在山上，獸道在山腳）。
// 石階兩側是連續的山坡地形（heightAt 直接算），視覺網格照同一個高度場
// 生成 —— 走到哪裡腳下都有地，不會出現懸空或穿模。
const OUT_NEAR = 58, OUT_FAR = 98;        // 下山石階的 z 範圍（40m 長）
const OUTER_DROP = 14;                    // 山腳比前庭低多少
const OUT_STEPS = 36;                     // 石階級數
const HILL_FADE = 30;                     // 過了石階底之後，兩側山坡再走多遠攤平

/** 南側下山段的高度（z > OUT_NEAR 都走這裡） */
function southHeight(x, z) {
  const t = Math.min(1, (z - OUT_NEAR) / (OUT_FAR - OUT_NEAR));
  const stepped = -Math.round(t * OUT_STEPS) / OUT_STEPS * OUTER_DROP;
  const ax = Math.abs(x);
  if (ax <= STAIR_HALF_W && z <= OUT_FAR) return stepped;
  // 石階兩側的山坡：從階梯高度往上收，最多收回前庭高度（0）。
  // 過了石階底部（z > OUT_FAR）山坡逐漸攤平，讓山腳展開成低地。
  const fade = Math.max(0, 1 - Math.max(0, z - OUT_FAR) / HILL_FADE);
  const side = Math.max(0, ax - STAIR_HALF_W);   // 石階中線帶（含階底之後的土徑）不抬升
  const rise = side * side * 0.09 * fade;
  return Math.min(0, stepped + rise);
}
const FLOOR_Y = PLATEAU + 1.35;           // shrine building floor
const B = { minX: -8.6, maxX: 8.6, minZ: -16, maxZ: -2.2 };   // building footprint

function heightAt(x, z) {
  let h;
  if (z > OUT_NEAR) h = southHeight(x, z);
  else if (z >= STAIR_FAR) h = 0;
  else if (z > STAIR_NEAR) {
    // Only the physical staircase (|x| <= STAIR_HALF_W) climbs — elsewhere in this
    // z-band there are no visible steps, so the ground stays at forecourt level and
    // the retaining wall below blocks walking around the stairs to skip them.
    if (Math.abs(x) <= STAIR_HALF_W) {
      const t = (STAIR_FAR - z) / (STAIR_FAR - STAIR_NEAR);
      h = Math.round(t * 11) / 11 * PLATEAU;   // stepped, matches the visible steps
    } else {
      h = 0;
    }
  } else h = PLATEAU;

  // shrine floor + its front step
  if (x > B.minX && x < B.maxX) {
    if (z > B.minZ && z < B.maxZ) h = FLOOR_Y;
    else if (z >= B.maxZ && z < B.maxZ + 1.6) {
      h = PLATEAU + Math.round(((B.maxZ + 1.6 - z) / 1.6) * 3) / 3 * (FLOOR_Y - PLATEAU);
    }
  }
  return h;
}

(function terrain() {
  // lower forecourt（平的部份到 OUT_NEAR 為止，再往南是下山的山坡）
  const lower = new THREE.Mesh(new THREE.PlaneGeometry(220, 108), new THREE.MeshStandardMaterial({ map: TEX.ground(30, 15), roughness: 1 }));
  lower.rotation.x = -Math.PI / 2;
  lower.position.set(0, 0, OUT_NEAR - 54);
  lower.receiveShadow = true;
  world.add(lower);

  // 南側下山段 + 山腳低地：頂點直接取 heightAt 的高度場，
  // 視覺地面與腳下高度是同一份資料 —— 不會有懸空或穿進土裡。
  {
    const D0 = OUT_NEAR - 2, D1 = 150;               // z 範圍（56~150，與平地小幅重疊）
    const geo = new THREE.PlaneGeometry(220, D1 - D0, 72, 60);
    geo.rotateX(-Math.PI / 2);
    const p = geo.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const wx = p.getX(i), wz = p.getZ(i) + (D0 + D1) / 2;
      p.setY(i, Math.min(0, heightAt(wx, wz)) - 0.02);   // 貼在可走高度下方一點點
    }
    geo.computeVertexNormals();
    const hill = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ map: TEX.ground(30, 13), roughness: 1 }));
    hill.position.z = (D0 + D1) / 2;
    hill.receiveShadow = true;
    world.add(hill);
  }

  // upper plateau
  const upper = new THREE.Mesh(new THREE.PlaneGeometry(150, 90), new THREE.MeshStandardMaterial({ map: TEX.ground(22, 14), roughness: 1 }));
  upper.rotation.x = -Math.PI / 2;
  upper.position.set(0, PLATEAU, -30);
  upper.receiveShadow = true;
  world.add(upper);

  // stone retaining wall holding up the plateau, split to leave the staircase gap
  const wallW = WALL_OUTER_X - WALL_INNER_X, wallCx = (WALL_INNER_X + WALL_OUTER_X) / 2;
  for (const s of [-1, 1]) {
    box(wallW, PLATEAU + 4, RAMP_SZ, MAT.stoneBig, s * wallCx, PLATEAU / 2 - 2, RAMP_CZ);
    box(wallW, 0.5, RAMP_SZ + 0.4, MAT.stone, s * wallCx, PLATEAU + 0.2, RAMP_CZ);     // coping
    block(s * wallCx, RAMP_CZ, wallW, RAMP_SZ, PLATEAU);   // 防止繞過石階翻上台地
  }

  // stone staircase
  const steps = 11;
  for (let i = 0; i < steps; i++) {
    const t = i / steps;
    const z = STAIR_FAR - (STAIR_FAR - STAIR_NEAR) * t;
    const y = (PLATEAU / steps) * i;
    box(11, 0.34, (STAIR_FAR - STAIR_NEAR) / steps + 0.16, MAT.stone, 0, y + 0.17, z - 0.3);
  }
  // stair balustrades, following the slope (far end sits lower)
  const slopeA = Math.atan2(PLATEAU, STAIR_FAR - STAIR_NEAR);
  const slopeLen = Math.hypot(PLATEAU, STAIR_FAR - STAIR_NEAR) + 1.2;
  for (const s of [-1, 1]) {
    const rail = box(0.85, 2.4, slopeLen, MAT.stone, s * 5.9, PLATEAU / 2 + 0.45, (STAIR_FAR + STAIR_NEAR) / 2);
    rail.rotation.x = slopeA;
    block(s * 5.9, (STAIR_FAR + STAIR_NEAR) / 2, 0.85, slopeLen, PLATEAU + 1);   // 貼合欄杆實寬
  }

  // gravel approach path (lower) and plateau path
  const path = new THREE.Mesh(new THREE.PlaneGeometry(7.5, 34), new THREE.MeshStandardMaterial({ map: TEX.gravel(2, 9), roughness: 1 }));
  path.rotation.x = -Math.PI / 2; path.position.set(0, 0.02, 39); path.receiveShadow = true; world.add(path);

  const path2 = new THREE.Mesh(new THREE.PlaneGeometry(8.5, 22), new THREE.MeshStandardMaterial({ map: TEX.gravel(2, 6), roughness: 1 }));
  path2.rotation.x = -Math.PI / 2; path2.position.set(0, PLATEAU + 0.02, 3.5); path2.receiveShadow = true; world.add(path2);

  /* ---- 境外延伸：一條長長的下山石階（參道 → 山腳） ----
   * 高度場（southHeight）與階面一一對應：每一級一塊石板。兩側是連續
   * 山坡，不設擋土牆也不會懸空 —— 想爬旁邊的坡也行，那是真的地形。 */
  const stepD = (OUT_FAR - OUT_NEAR) / OUT_STEPS;
  for (let i = 0; i < OUT_STEPS; i++) {
    const zz = OUT_NEAR + stepD * (i + 0.5);
    const yy = -(OUTER_DROP / OUT_STEPS) * (i + 1);
    box(11, 0.42, stepD + 0.14, MAT.stone, 0, yy + 0.26, zz);
  }
  // 石階兩側的低石緣（純視覺，貼著坡度走）
  const curbA = Math.atan2(OUTER_DROP, OUT_FAR - OUT_NEAR);
  const curbLen = Math.hypot(OUTER_DROP, OUT_FAR - OUT_NEAR) + 1.5;
  for (const s of [-1, 1]) {
    const curb = box(0.7, 0.6, curbLen, MAT.stone, s * 5.85, -OUTER_DROP / 2 + 0.2, (OUT_NEAR + OUT_FAR) / 2);
    curb.rotation.x = curbA;
  }
  // 山腳延續的土徑，一路通到獸道的光點
  const path3 = new THREE.Mesh(new THREE.PlaneGeometry(6.5, 30), new THREE.MeshStandardMaterial({ map: TEX.gravel(2, 8), roughness: 1 }));
  path3.rotation.x = -Math.PI / 2; path3.position.set(0, -OUTER_DROP + 0.04, OUT_FAR + 17); path3.receiveShadow = true; world.add(path3);
})();

/* ────────────────────────────────────────────────────────────── torii ── */
function torii(x, y, z, scale = 1, group = world) {
  const g = new THREE.Group();
  g.position.set(x, y, z);
  g.scale.setScalar(scale);
  group.add(g);

  const H = 7.4, span = 4.6, r = 0.42;
  for (const s of [-1, 1]) {
    const p = cyl(r * 0.88, r, H, MAT.red, s * span, H / 2, 0, 16, g);
    p.rotation.z = -s * 0.02;                       // pillars lean in slightly
    cyl(r * 1.45, r * 1.45, 0.4, MAT.stone, s * span, 0.2, 0, 16, g);  // base stone
  }
  // nuki (lower tie beam) + gakuzuka (center plaque post)
  box(span * 2 + 1.1, 0.52, 0.62, MAT.redFlat, 0, H * 0.76, 0, g);
  box(0.5, 1.5, 0.5, MAT.redFlat, 0, H * 0.76 + 1.0, 0, g);
  // shimaki + kasagi: two stacked beams that curve gently upward at both ends
  const halfSpan = span + 2.2, SEG = 14;
  for (const [yOff, hgt, dep] of [[0.04, 0.4, 0.78], [0.52, 0.5, 1.02]]) {
    for (let i = 0; i < SEG; i++) {
      const t0 = i / SEG * 2 - 1, t1 = (i + 1) / SEG * 2 - 1;
      const curve = (t) => Math.pow(Math.abs(t), 3.2) * 1.15;   // flat centre, lifted tips
      const x0 = t0 * halfSpan, x1 = t1 * halfSpan;
      const y0 = H + yOff + curve(t0), y1 = H + yOff + curve(t1);
      const len = Math.hypot(x1 - x0, y1 - y0);
      const m = box(len * 1.04, hgt, dep, MAT.redFlat, (x0 + x1) / 2, (y0 + y1) / 2, 0, g);
      m.rotation.z = Math.atan2(y1 - y0, x1 - x0);
    }
  }
  // shimenawa across the torii
  shimenawa(g, 0, H * 0.76 - 0.42, 0, span * 1.6, 0.19);

  block(x - span * scale, z, 1.3 * scale, 1.3 * scale, y + H * scale);
  block(x + span * scale, z, 1.3 * scale, 1.3 * scale, y + H * scale);
  return g;
}

/**
 * Sacred rope (shimenawa) hung between two points, with a gentle sag,
 * folded paper streamers (shide) and straw tufts.
 */
function shimenawa(parent, x, y, z, halfLen, thick) {
  const segs = 9, sag = halfLen * 0.07;
  for (let i = 0; i < segs; i++) {
    const t0 = i / segs, t1 = (i + 1) / segs;
    const x0 = x - halfLen + halfLen * 2 * t0, x1 = x - halfLen + halfLen * 2 * t1;
    const y0 = y - Math.sin(t0 * Math.PI) * sag, y1 = y - Math.sin(t1 * Math.PI) * sag;
    // rope is fattest in the middle, tapering to both ends
    const r0 = thick * (0.45 + 0.55 * Math.sin(t0 * Math.PI));
    const r1 = thick * (0.45 + 0.55 * Math.sin(t1 * Math.PI));
    const len = Math.hypot(x1 - x0, y1 - y0);
    const m = new THREE.Mesh(new THREE.CylinderGeometry(r1, r0, len * 1.06, 9), MAT.rope);
    m.position.set((x0 + x1) / 2, (y0 + y1) / 2, z);
    m.rotation.z = Math.PI / 2 - Math.atan2(y1 - y0, x1 - x0);
    m.castShadow = true;
    parent.add(m);
  }
  const n = 4;
  for (let i = 0; i < n; i++) {
    const t = (i + 0.5) / n;
    const px = x - halfLen * 0.82 + (halfLen * 1.64 / (n - 1)) * i;
    const py = y - Math.sin(((px - x) / halfLen * 0.5 + 0.5) * Math.PI) * sag - thick * 0.6;
    const h = thick * 5.2;
    const sh = new THREE.Mesh(new THREE.PlaneGeometry(h * 0.45, h), MAT.shide);
    sh.position.set(px, py - h / 2, z + 0.03);
    parent.add(sh);
    const tuft = new THREE.Mesh(new THREE.ConeGeometry(thick * 0.34, thick * 2.2, 6), MAT.rope);
    tuft.position.set(px - thick * 1.5, py - thick * 1.0, z);
    tuft.rotation.z = 0.12;
    parent.add(tuft);
  }
}

/* ────────────────────────────────────────────────── shrine building ── */
function shrine() {
  const g = new THREE.Group();
  world.add(g);

  const w = B.maxX - B.minX, d = B.maxZ - B.minZ;
  const cx = 0, cz = (B.minZ + B.maxZ) / 2;

  // stone foundation + raised wooden floor (foundation stops just below the
  // planks — a coplanar top face would z-fight with the floor)
  box(w + 1.4, 1.2, d + 1.4, MAT.stone, cx, PLATEAU + 0.6, cz, g);
  const floor = box(w, 0.3, d, MAT.plank, cx, FLOOR_Y - 0.15, cz, g);
  floor.receiveShadow = true;

  // front steps (3)
  for (let i = 0; i < 3; i++) {
    box(7.2, 0.45, 0.55, MAT.plank, 0, PLATEAU + 0.22 + i * 0.45, B.maxZ + 1.3 - i * 0.53, g);
  }

  // corner + wall pillars
  const PH = 4.6, pr = 0.28;
  const pxs = [-8.0, -4.0, 0, 4.0, 8.0], pzs = [B.minZ + 0.6, B.maxZ - 0.6];
  for (const px of pxs) for (const pz of pzs) {
    if (pz > B.minZ + 1 && Math.abs(px) < 3) continue;   // keep the entrance clear
    cyl(pr, pr * 1.08, PH, MAT.darkWood, px, FLOOR_Y + PH / 2, pz, 12, g);
    block(px, pz, 0.75, 0.75, FLOOR_Y + PH);
  }
  for (const pz of [-13, -9.5, -6]) for (const px of [-8.0, 8.0]) {
    cyl(pr, pr * 1.08, PH, MAT.darkWood, px, FLOOR_Y + PH / 2, pz, 12, g);
    block(px, pz, 0.7, 0.7, FLOOR_Y + PH);
  }

  // walls: back + two sides (shoji-panelled), front left open
  const backW = box(w, PH * 0.94, 0.24, MAT.shoji, cx, FLOOR_Y + PH * 0.47, B.minZ + 0.35, g);
  backW.material = MAT.darkWood;
  block(cx, B.minZ + 0.35, w, 1.0, FLOOR_Y + PH);
  for (const s of [-1, 1]) {
    const sw = box(0.24, PH * 0.94, d - 1.6, MAT.shoji, s * (w / 2 - 0.15), FLOOR_Y + PH * 0.47, cz, g);
    sw.material = MAT.shoji;
    block(s * (w / 2 - 0.15), cz, 1.0, d - 1.6, FLOOR_Y + PH);
  }
  // front wall segments flanking the open entrance
  for (const s of [-1, 1]) {
    box(2.4, PH * 0.94, 0.22, MAT.shoji, s * 3.0, FLOOR_Y + PH * 0.47, B.maxZ - 0.5, g);
    block(s * 3.0, B.maxZ - 0.5, 2.6, 0.9, FLOOR_Y + PH);
  }
  // lintel over the entrance
  box(7.0, 0.5, 0.3, MAT.darkWood, 0, FLOOR_Y + PH * 0.86, B.maxZ - 0.5, g);

  // interior back altar
  box(5.0, 1.1, 1.0, MAT.darkWood, 0, FLOOR_Y + 0.55, B.minZ + 1.4, g);
  box(1.2, 1.6, 0.9, MAT.wood, 0, FLOOR_Y + 1.9, B.minZ + 1.4, g);
  const mirror = new THREE.Mesh(new THREE.CircleGeometry(0.42, 24), MAT.gold);
  mirror.position.set(0, FLOOR_Y + 2.0, B.minZ + 1.9);
  g.add(mirror);
  for (const s of [-1, 1]) {   // candle stands
    cyl(0.12, 0.16, 0.9, MAT.gold, s * 1.9, FLOOR_Y + 1.55, B.minZ + 1.4, 10, g);
    const flame = new THREE.Mesh(new THREE.SphereGeometry(0.11, 8, 8), new THREE.MeshBasicMaterial({ color: '#ffcf7a' }));
    flame.position.set(s * 1.9, FLOOR_Y + 2.06, B.minZ + 1.4);
    g.add(flame);
    const l = new THREE.PointLight('#ffb35e', 26, 18, 2);
    l.position.copy(flame.position);
    g.add(l);
  }
  // soft interior fill so the hall reads instead of going pitch black
  const inner = new THREE.PointLight('#ffcf9a', 34, 30, 2);
  inner.position.set(0, FLOOR_Y + 3.2, cz + 4.5);
  g.add(inner);

  /* ---- 靈夢的寢室（拜殿西側的和室） -------------------------------
   * 參考傳統和室：榻榻米直接鋪地、被褥（布團）晚上鋪出來、押入收納、
   * 矮桌（卓袱台）擺中間。房裡常年多鋪一組客用被褥 —— 因為萃香
   * 三天兩頭跑來睡（她的預設出生點就在那組被褥上，見 shrine-spawn.js）。
   * 依「不設空氣牆」的原則，隔間與家具都沒有碰撞盒。 */
  (function reimuRoom() {
    const RX0 = -8.2, RX1 = -2.6;              // 房間 x 範圍（拜殿西側）
    const RZ0 = -14.8, RZ1 = -8.0;             // 房間 z 範圍
    const rcx = (RX0 + RX1) / 2, rcz = (RZ0 + RZ1) / 2;
    const rw = RX1 - RX0, rd = RZ1 - RZ0;

    // 榻榻米地板（略高於木地板一層）
    const tat = box(rw, 0.1, rd, MAT.tatami, rcx, FLOOR_Y + 0.06, rcz, g);
    tat.receiveShadow = true;

    // 隔間：東側紙門牆（留南端開口當入口）、南側半牆
    box(0.14, 3.2, rd - 1.8, MAT.shoji, RX1, FLOOR_Y + 1.66, rcz - 0.9, g);
    box(0.18, 3.2, 0.18, MAT.darkWood, RX1, FLOOR_Y + 1.66, RZ0 + 0.1, g);   // 門框柱
    box(0.18, 3.2, 0.18, MAT.darkWood, RX1, FLOOR_Y + 1.66, RZ1 - 1.7, g);
    box(rw - 1.9, 0.5, 0.12, MAT.darkWood, rcx - 0.95, FLOOR_Y + 3.0, RZ1, g); // 南側楣
    box(2.2, 3.2, 0.12, MAT.shoji, RX0 + 1.1, FLOOR_Y + 1.66, RZ1, g);         // 南側半牆

    // 押入（壁櫥）：靠北牆，上下兩段拉門
    box(2.6, 2.5, 0.7, MAT.wood, RX0 + 1.5, FLOOR_Y + 1.3, RZ0 + 0.45, g);
    box(1.24, 1.1, 0.06, MAT.shoji, RX0 + 0.85, FLOOR_Y + 1.85, RZ0 + 0.82, g);
    box(1.24, 1.1, 0.06, MAT.shoji, RX0 + 2.15, FLOOR_Y + 0.72, RZ0 + 0.82, g);

    // 靈夢的被褥：敷布團（白）＋ 掀開一角的紅色棉被 ＋ 枕頭
    const fu = (x, z, quilt, rot = 0) => {
      const fg = new THREE.Group();
      fg.position.set(x, FLOOR_Y + 0.11, z);
      fg.rotation.y = rot;
      g.add(fg);
      box(1.15, 0.1, 2.15, MAT.futonWhite, 0, 0.05, 0, fg);                 // 敷布團
      const q = box(1.25, 0.14, 1.62, quilt, 0, 0.16, 0.24, fg);            // 棉被（蓋腳側）
      q.rotation.x = 0.035;
      box(0.52, 0.14, 0.3, MAT.futonPlum, 0, 0.14, -0.86, fg);              // 枕頭
      return fg;
    };
    fu(-6.9, -12.2, MAT.futonRed, 0.04);          // 靈夢自己的
    fu(-4.55, -12.1, MAT.futonWhite, -0.06);      // 客用 —— 萃香常年霸佔（她睡這）

    // 卓袱台（矮圓桌）＋ 兩個座墊 ＋ 茶壺
    cyl(0.75, 0.75, 0.1, MAT.darkWood, rcx + 0.4, FLOOR_Y + 0.42, rcz + 1.9, 16, g);
    cyl(0.09, 0.12, 0.36, MAT.darkWood, rcx + 0.4, FLOOR_Y + 0.2, rcz + 1.9, 8, g);
    box(0.62, 0.09, 0.62, MAT.futonRed, rcx - 0.5, FLOOR_Y + 0.11, rcz + 1.9, g);   // 座墊
    box(0.62, 0.09, 0.62, MAT.futonPlum, rcx + 1.3, FLOOR_Y + 0.11, rcz + 1.9, g);
    const pot = new THREE.Mesh(new THREE.SphereGeometry(0.14, 10, 8), MAT.darkWood);
    pot.position.set(rcx + 0.4, FLOOR_Y + 0.56, rcz + 1.9);
    pot.scale.y = 0.75;
    g.add(pot);

    // 萃香的酒葫蘆與空酒碗滾在被褥邊 —— 有人昨晚又喝掛了
    const gourd = new THREE.Group();
    gourd.position.set(-3.6, FLOOR_Y + 0.16, -11.2);
    gourd.rotation.z = Math.PI / 2 - 0.2;
    g.add(gourd);
    const gpm = new THREE.MeshStandardMaterial({ color: '#6a4a8a', roughness: 0.6 });
    const gl = new THREE.Mesh(new THREE.SphereGeometry(0.17, 10, 8), gpm); gl.scale.y = 1.1; gourd.add(gl);
    const gu = new THREE.Mesh(new THREE.SphereGeometry(0.11, 10, 8), gpm); gu.position.y = 0.23; gourd.add(gu);
    cyl(0.06, 0.05, 0.05, MAT.gold, -3.25, FLOOR_Y + 0.14, -11.55, 10, g);   // 倒扣的酒碗

    // 牆上的御札與燈
    for (let i = 0; i < 3; i++) {
      const o = new THREE.Mesh(new THREE.PlaneGeometry(0.3, 0.84), MAT.ofuda);
      o.position.set(RX0 + 0.12, FLOOR_Y + 2.3 - i * 0.1, rcz - 1.6 + i * 1.3);
      o.rotation.y = Math.PI / 2;
      o.rotation.z = (i - 1) * 0.05;
      g.add(o);
    }
    const rl = new THREE.PointLight('#ffcf9a', 14, 12, 2);
    rl.position.set(rcx, FLOOR_Y + 2.6, rcz);
    g.add(rl);
  })();

  // plank ceiling, so you see timber overhead rather than the roof tiles
  box(w - 0.6, 0.18, d - 0.8, MAT.darkWood, cx, FLOOR_Y + PH + 0.3, cz, g);
  for (let i = -4; i <= 4; i++) {
    box(0.24, 0.3, d - 0.8, MAT.wood, i * 1.8, FLOOR_Y + PH + 0.12, cz, g);   // exposed beams
  }

  // veranda railing along the sides
  for (const s of [-1, 1]) {
    box(0.14, 0.14, d - 2, MAT.redFlat, s * (w / 2 + 0.5), FLOOR_Y + 0.95, cz, g);
    for (let i = 0; i < 9; i++) {
      box(0.1, 0.95, 0.1, MAT.redFlat, s * (w / 2 + 0.5), FLOOR_Y + 0.48, B.minZ + 1.2 + i * 1.45, g);
    }
  }

  /* roof: gabled, ridge running along X, deep eaves */
  const ridgeY = 15.6, eaveY = 8.4, ridgeZ = cz;
  const roofW = w + 4.4;
  function slope(dir) {          // dir=+1 front (toward +Z), -1 back
    const eaveZ = ridgeZ + dir * (d / 2 + 2.8);
    const dz = Math.abs(eaveZ - ridgeZ), dy = ridgeY - eaveY;
    const len = Math.hypot(dz, dy);
    const m = box(roofW, 0.55, len, MAT.roof, cx, (ridgeY + eaveY) / 2, (ridgeZ + eaveZ) / 2, g);
    m.rotation.x = dir * Math.atan2(dy, dz);
    // eave edge board
    const e = box(roofW + 0.3, 0.42, 0.5, MAT.darkWood, cx, eaveY - 0.12, eaveZ, g);
    return { eaveZ, angle: m.rotation.x };
  }
  const front = slope(1);
  slope(-1);

  // gable end triangles
  for (const s of [-1, 1]) {
    const shape = new THREE.Shape();
    const halfD = d / 2 + 2.8;
    shape.moveTo(-halfD, eaveY - 0.4); shape.lineTo(halfD, eaveY - 0.4); shape.lineTo(0, ridgeY);
    const tri = new THREE.Mesh(new THREE.ShapeGeometry(shape), MAT.darkWood);
    tri.position.set(s * (roofW / 2 - 0.05), 0, ridgeZ);
    tri.rotation.y = s * Math.PI / 2;
    tri.castShadow = true;
    g.add(tri);
  }

  // ridge cap + katsuogi (billets) + chigi (crossed finials at each gable end)
  box(roofW + 0.5, 0.9, 1.7, MAT.roof, cx, ridgeY + 0.05, ridgeZ, g);
  for (let i = -2; i <= 2; i++) {
    const k = cyl(0.3, 0.3, 2.3, MAT.darkWood, i * 3.6, ridgeY + 0.72, ridgeZ, 12, g);
    k.rotation.x = Math.PI / 2;
    cyl(0.33, 0.33, 0.2, MAT.gold, i * 3.6, ridgeY + 0.72, ridgeZ + 1.16, 12, g).rotation.x = Math.PI / 2;
    cyl(0.33, 0.33, 0.2, MAT.gold, i * 3.6, ridgeY + 0.72, ridgeZ - 1.16, 12, g).rotation.x = Math.PI / 2;
  }
  for (const s of [-1, 1]) {
    for (const t of [-1, 1]) {
      const c = box(0.3, 3.4, 0.3, MAT.darkWood, s * (roofW / 2 - 0.35), ridgeY + 0.9, ridgeZ + t * 0.85, g);
      c.rotation.x = -t * 0.42;
    }
  }

  // hanging bell (suzu) with a striped rope, under the front eave
  const bellY = FLOOR_Y + PH - 0.5;
  const bellZ = B.maxZ + 0.6;
  const bell = new THREE.Mesh(new THREE.SphereGeometry(0.44, 18, 14, 0, Math.PI * 2, 0, Math.PI * 0.78), MAT.gold);
  bell.position.set(0, bellY, bellZ);
  bell.castShadow = true;
  g.add(bell);
  cyl(0.09, 0.09, 0.7, MAT.darkWood, 0, bellY + 0.4, bellZ, 8, g);   // hanger
  const ropeMatA = new THREE.MeshStandardMaterial({ color: '#efe9da', roughness: 1 });
  const ropeMatB = new THREE.MeshStandardMaterial({ color: '#c1392f', roughness: 1 });
  const bellRope = new THREE.Group();
  bellRope.position.set(0, bellY, bellZ);       // pivot at the bell so it swings
  for (let i = 0; i < 9; i++) {
    cyl(0.1, 0.1, 0.32, i % 2 ? ropeMatB : ropeMatA, 0, -0.42 - i * 0.32, 0, 10, bellRope);
  }
  cyl(0.13, 0.09, 0.34, ropeMatB, 0, -0.42 - 9 * 0.32, 0, 10, bellRope);   // tassel
  g.add(bellRope);
  // 鈴與鈴緒會在投賽錢後搖 —— 不能被靜態合併走（合併會把當下的姿態烘死）
  keepDynamic(bellRope);
  keepDynamic(bell);
  OBJ.bellRope = bellRope;
  OBJ.bell = bell;

  // saisen-bako (offering box)
  const sb = new THREE.Group();
  sb.position.set(0, FLOOR_Y + 0.01, B.maxZ - 1.6);
  g.add(sb);
  box(3.0, 0.95, 1.3, MAT.darkWood, 0, 0.48, 0, sb);
  for (let i = 0; i < 11; i++) box(0.12, 0.1, 1.32, MAT.wood, -1.32 + i * 0.264, 0.98, 0, sb);
  box(3.1, 0.12, 1.4, MAT.wood, 0, 0.05, 0, sb);
  block(0, B.maxZ - 1.6, 3.1, 1.4, FLOOR_Y + 1.0);
  OBJ.saisen = new THREE.Vector3(0, FLOOR_Y, B.maxZ - 1.6);

  // ofuda strips pinned to the front wall panels
  for (const s of [-1, 1]) for (let i = 0; i < 2; i++) {
    const o = new THREE.Mesh(new THREE.PlaneGeometry(0.36, 1.0), MAT.ofuda);
    o.position.set(s * (2.3 + i * 1.1), FLOOR_Y + 2.9 - i * 0.25, B.maxZ - 0.37);
    o.rotation.z = (Math.random() - 0.5) * 0.08;
    g.add(o);
  }

  // shimenawa across the entrance
  shimenawa(g, 0, FLOOR_Y + PH * 0.74, B.maxZ + 0.15, 3.4, 0.2);
}

/* ─────────────────────────────────────────────────── props & scenery ── */
const OBJ = {};
const lanternLights = [];
const lanternGlows = [];

/** Stone lantern (tōrō). */
function lantern(x, y, z, s = 1) {
  const g = new THREE.Group();
  g.position.set(x, y, z); g.scale.setScalar(s);
  world.add(g);
  cyl(0.42, 0.62, 0.42, MAT.stone, 0, 0.21, 0, 8, g);
  cyl(0.24, 0.28, 1.5, MAT.stone, 0, 1.0, 0, 8, g);
  cyl(0.62, 0.42, 0.26, MAT.stone, 0, 1.88, 0, 8, g);
  const cage = cyl(0.52, 0.58, 0.78, MAT.stone, 0, 2.4, 0, 8, g);
  const light = new THREE.Mesh(
    new THREE.SphereGeometry(0.3, 10, 8),
    new THREE.MeshBasicMaterial({ color: '#ffb457', transparent: true, opacity: 0.95 })
  );
  light.position.y = 2.4;
  g.add(light);
  lanternGlows.push(light);
  const roofL = cyl(0.1, 0.95, 0.5, MAT.stone, 0, 3.05, 0, 8, g);
  cyl(0.13, 0.13, 0.26, MAT.stone, 0, 3.4, 0, 8, g);
  const pl = new THREE.PointLight('#ffa040', 0, 13, 2);
  pl.position.set(0, 2.4, 0);
  g.add(pl);
  lanternLights.push(pl);
  block(x, z, 1.2 * s, 1.2 * s, y + 3.5 * s);
  return g;
}

/** Guardian lion-dog, stylised. */
function komainu(x, y, z, flip = 1) {
  const g = new THREE.Group();
  g.position.set(x, y, z);
  g.rotation.y = flip > 0 ? -Math.PI / 2 : Math.PI / 2;
  world.add(g);
  box(1.5, 1.5, 1.1, MAT.stone, 0, 0.75, 0, g);            // pedestal
  const body = box(1.25, 0.85, 0.72, MAT.stone, 0, 1.95, 0, g);
  body.rotation.x = 0.06;
  box(0.2, 0.62, 0.2, MAT.stone, -0.42, 1.25, 0.24, g);
  box(0.2, 0.62, 0.2, MAT.stone, 0.42, 1.25, 0.24, g);
  box(0.2, 0.55, 0.2, MAT.stone, -0.42, 1.3, -0.24, g);
  box(0.2, 0.55, 0.2, MAT.stone, 0.42, 1.3, -0.24, g);
  const head = new THREE.Mesh(new THREE.DodecahedronGeometry(0.48, 0), MAT.stone);
  head.position.set(0.62, 2.55, 0);
  head.castShadow = true; g.add(head);
  const snout = box(0.36, 0.26, 0.3, MAT.stone, 0.98, 2.45, 0, g);
  for (const s of [-1, 1]) {
    const ear = new THREE.Mesh(new THREE.ConeGeometry(0.16, 0.34, 5), MAT.stone);
    ear.position.set(0.5, 2.92, s * 0.26); ear.rotation.z = -0.3; g.add(ear);
  }
  const tail = new THREE.Mesh(new THREE.ConeGeometry(0.3, 0.95, 6), MAT.stone);
  tail.position.set(-0.7, 2.5, 0); tail.rotation.z = 0.7; tail.castShadow = true; g.add(tail);
  block(x, z, 1.7, 1.4, y + 3.0);
}

/** Chōzuya — water pavilion. */
function chozuya(x, y, z) {
  const g = new THREE.Group();
  g.position.set(x, y, z);
  world.add(g);
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    cyl(0.17, 0.19, 3.0, MAT.darkWood, sx * 1.7, 1.5, sz * 1.4, 10, g);
    block(x + sx * 1.7, z + sz * 1.4, 0.5, 0.5, y + 3);
  }
  box(4.6, 0.22, 3.6, MAT.darkWood, 0, 3.05, 0, g);
  for (const dir of [1, -1]) {
    const m = box(5.2, 0.4, 2.6, MAT.roof, 0, 3.75, dir * 1.05, g);
    m.rotation.x = dir * 0.42;
  }
  box(5.3, 0.5, 0.7, MAT.roof, 0, 4.3, 0, g);
  // stone basin
  box(2.6, 0.9, 1.7, MAT.stone, 0, 0.45, 0, g);
  const water = new THREE.Mesh(
    new THREE.PlaneGeometry(2.2, 1.3),
    new THREE.MeshStandardMaterial({ color: '#5f8f93', roughness: 0.08, metalness: 0.55, transparent: true, opacity: 0.9 })
  );
  water.rotation.x = -Math.PI / 2; water.position.y = 0.92; g.add(water);
  OBJ.water = water;
  for (let i = 0; i < 4; i++) {   // bamboo ladles
    const l = new THREE.Group();
    l.position.set(-0.9 + i * 0.6, 1.0, 0);
    cyl(0.03, 0.03, 0.8, MAT.wood, 0, 0, 0.35, 6, l).rotation.x = Math.PI / 2;
    cyl(0.11, 0.11, 0.1, MAT.wood, 0, 0, -0.1, 8, l);
    g.add(l);
  }
  block(x, z, 3.0, 2.1, y + 1.0);
}

/** Tree: trunk + a few flat-shaded foliage blobs. */
function tree(x, y, z, scale, mat) {
  const g = new THREE.Group();
  g.position.set(x, y, z);
  g.scale.setScalar(scale);
  g.rotation.y = Math.random() * 6.28;
  world.add(g);
  const h = 4 + Math.random() * 2.5;
  cyl(0.22, 0.42, h, MAT.bark, 0, h / 2, 0, 8, g);
  const blobs = 3 + (Math.random() * 3 | 0);
  for (let i = 0; i < blobs; i++) {
    const r = 1.5 + Math.random() * 1.3;
    const m = new THREE.Mesh(new THREE.IcosahedronGeometry(r, 0), mat);
    m.position.set((Math.random() - 0.5) * 2.6, h + (Math.random() - 0.2) * 2.0, (Math.random() - 0.5) * 2.6);
    m.rotation.set(Math.random(), Math.random(), Math.random());
    m.castShadow = true;
    g.add(m);
  }
  block(x, z, 1.0 * scale, 1.0 * scale, y + h * scale);
}

/** Red fence (tamagaki) along a line of posts. */
function fence(x1, z1, x2, z2, y) {
  const len = Math.hypot(x2 - x1, z2 - z1);
  const n = Math.max(2, Math.round(len / 1.3));
  const g = new THREE.Group();
  world.add(g);
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    const px = x1 + (x2 - x1) * t, pz = z1 + (z2 - z1) * t;
    box(0.18, 1.5, 0.18, MAT.redFlat, px, y + 0.75, pz, g);
  }
  const mid = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.14, len), MAT.redFlat);
  mid.position.set((x1 + x2) / 2, y + 1.35, (z1 + z2) / 2);
  mid.lookAt(new THREE.Vector3(x2, y + 1.35, z2));
  mid.castShadow = true;
  g.add(mid);
  const low = mid.clone(); low.position.y = y + 0.6; g.add(low);
}

/** Reimu's floating yin-yang orbs — a small easter egg. */
const orbs = [];
function yinYang(x, y, z) {
  const g = new THREE.Group();
  g.position.set(x, y, z);
  world.add(g);
  // split top/bottom so the red-and-white reads from any angle
  const r = 0.3;
  const red = new THREE.Mesh(new THREE.SphereGeometry(r, 22, 14, 0, Math.PI * 2, 0, Math.PI / 2),
    new THREE.MeshStandardMaterial({ color: '#d94b3e', roughness: 0.3, emissive: '#48100c', emissiveIntensity: 0.5 }));
  const white = new THREE.Mesh(new THREE.SphereGeometry(r, 22, 14, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2),
    new THREE.MeshStandardMaterial({ color: '#f6f2e8', roughness: 0.3, emissive: '#3e3a30', emissiveIntensity: 0.45 }));
  g.rotation.z = 0.22;
  g.add(red, white);
  red.castShadow = white.castShadow = true;
  g.userData = { base: y, phase: Math.random() * 6.28, noMerge: true };  // 會浮會轉
  orbs.push(g);
  return g;
}

/* ────────────────────────────────────────────────────── build the world ── */
shrine();

torii(0, PLATEAU, 9.5, 1.0);      // main torii on the plateau
torii(0, 0, 34, 0.78);            // outer torii at the foot of the stairs

komainu(-5.2, PLATEAU, 4.2, 1);
komainu(5.2, PLATEAU, 4.2, -1);

lantern(-7.4, PLATEAU, -1.0);
lantern(7.4, PLATEAU, -1.0);
lantern(-6.4, PLATEAU, 8.0);
lantern(6.4, PLATEAU, 8.0);
lantern(-5.0, 0, 25, 0.9);
lantern(5.0, 0, 25, 0.9);
lantern(-4.6, 0, 39, 0.9);
lantern(4.6, 0, 39, 0.9);

chozuya(12.5, PLATEAU, 4.0);

/**
 * 摂社（境內的小社）。真實神社的境內本來就會有幾座末社／摂社，
 * 這裡同時也是「境內三社巡禮」任務的兩個目的地 —— 見 src/world/zones.js。
 * 面朝參道，所以 faceIn 決定它轉向哪一側。
 */
function sessha(x, z, facing) {
  const g = new THREE.Group();
  g.position.set(x, PLATEAU, z);
  g.rotation.y = facing;
  world.add(g);

  // 小社本體加在 g 裡會跟著轉，但鳥居／燈籠是加到 world 的（它們自己
  // 就是獨立物件），所以要自己把「正面方向」換算成世界座標的偏移量，
  // 否則本體轉了、前庭的東西還留在原地。
  const fx = Math.sin(facing), fz = Math.cos(facing);   // 正面單位向量
  const rx = Math.cos(facing), rz = -Math.sin(facing);  // 右手邊單位向量

  // 石垣基座 + 木造小社
  box(4.6, 0.6, 4.0, MAT.stone, 0, 0.3, 0, g);
  box(3.0, 0.35, 2.6, MAT.plank, 0, 0.75, 0, g);
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    cyl(0.13, 0.15, 2.0, MAT.darkWood, sx * 1.25, 1.9, sz * 1.05, 10, g);
  }
  // 三面牆（正面留空）
  box(2.7, 1.8, 0.16, MAT.shoji, 0, 1.85, -1.12, g);
  for (const sx of [-1, 1]) box(0.16, 1.8, 2.2, MAT.shoji, sx * 1.37, 1.85, 0, g);
  // 小神體
  const orb = new THREE.Mesh(new THREE.SphereGeometry(0.26, 16, 12), MAT.gold);
  orb.position.set(0, 1.75, -0.7); orb.castShadow = true; g.add(orb);

  // 切妻小屋頂
  for (const dir of [1, -1]) {
    const m = box(3.9, 0.26, 1.9, MAT.roof, 0, 3.35, dir * 0.78, g);
    m.rotation.x = dir * 0.52;
  }
  box(4.1, 0.34, 0.5, MAT.roof, 0, 3.78, 0, g);
  for (let i = -1; i <= 1; i++) {
    cyl(0.13, 0.13, 1.1, MAT.darkWood, i * 1.2, 3.98, 0, 10, g).rotation.x = Math.PI / 2;
  }

  // 小鳥居與注連繩（鳥居也要轉到同一個朝向）
  const tor = torii(x + fx * 5.0, PLATEAU, z + fz * 5.0, 0.42);
  tor.rotation.y = facing;
  shimenawa(g, 0, 2.95, 1.25, 1.5, 0.13);

  // 一對小燈籠，分列正面左右
  lantern(x + fx * 2.8 - rx * 3.0, PLATEAU, z + fz * 2.8 - rz * 3.0, 0.62);
  lantern(x + fx * 2.8 + rx * 3.0, PLATEAU, z + fz * 2.8 + rz * 3.0, 0.62);

  block(x, z, 4.8, 4.2, PLATEAU + 3.4);
}

// facing 是「正面朝向」的世界 yaw：π/2 = 朝 +X（東），-π/2 = 朝 -X（西）。
// 兩座都面向中央參道。
sessha(-22, 2, Math.PI / 2);    // 摂社・守矢（境內西，面朝東）
sessha(22, 2, -Math.PI / 2);    // 摂社・命蓮（境內東，面朝西）

// ema board rack + a donation notice near the path
(function ema() {
  const g = new THREE.Group();
  g.position.set(-13.5, PLATEAU, 2.0);
  g.rotation.y = 0.5;
  world.add(g);
  for (const s of [-1, 1]) cyl(0.12, 0.14, 2.2, MAT.darkWood, s * 1.6, 1.1, 0, 8, g);
  box(3.6, 0.16, 0.3, MAT.darkWood, 0, 2.1, 0, g);
  for (let i = 0; i < 9; i++) {
    const p = new THREE.Mesh(new THREE.PlaneGeometry(0.34, 0.28), MAT.white);
    p.position.set(-1.4 + (i % 5) * 0.7, 1.75 - (i / 5 | 0) * 0.42, 0.02 + (i / 5 | 0) * 0.06);
    p.rotation.z = (Math.random() - 0.5) * 0.14;
    g.add(p);
  }
  block(-13.5, 2.0, 3.6, 0.8, PLATEAU + 2.3);
})();

// tamagaki fence framing the courtyard
// 玉垣。外擴到 ±27 讓兩座摂社（x=±22）落在境內 —— 否則巡禮任務的目的地
// 會在牆外，玩家得穿過玉垣才走得到。正面 |x|<7.5 留開口給參道。
fence(-27, -3, -27, 11, PLATEAU);
fence(27, -3, 27, 11, PLATEAU);
fence(-27, 11, -7.5, 11, PLATEAU);
fence(27, 11, 7.5, 11, PLATEAU);

// woods: dense ring around the plateau + slopes below
// NPC 展列區（x±32, z 18~50）要避開，免得角色站在樹幹裡
const leafMats = [MAT.leafGreen, MAT.leafGreen, MAT.leafRed, MAT.leafGold];
for (let i = 0; i < 70; i++) {
  const a = Math.random() * Math.PI * 2;
  const r = 26 + Math.random() * 34;
  const x = Math.cos(a) * r, z = Math.sin(a) * r - 12;
  if (Math.abs(x) < 13 && z > -24 && z < 26) continue;         // keep courtyard + stairs clear
  if (Math.abs(x) < 34 && z > 16 && z < 52) continue;          // NPC 展列區
  // 兩座摂社（x=±22, z=2）與參拜空間
  if (Math.abs(Math.abs(x) - 22) < 9 && z > -6 && z < 12) continue;
  // 加寬後的階梯擋土牆（見 heightAt 旁的 WALL_INNER_X/OUTER_X），避免樹幹穿模
  if (Math.abs(x) >= WALL_INNER_X - 2 && Math.abs(x) <= WALL_OUTER_X + 2 &&
      z > RAMP_CZ - RAMP_SZ / 2 - 2 && z < RAMP_CZ + RAMP_SZ / 2 + 2) continue;
  const onPlateau = z < STAIR_NEAR;
  tree(x, onPlateau ? PLATEAU : 0, z, 0.75 + Math.random() * 0.8, leafMats[Math.random() * leafMats.length | 0]);
}
for (let i = 0; i < 40; i++) {
  const x = (Math.random() - 0.5) * 110;
  const z = 24 + Math.random() * 118;
  if (Math.abs(x) < 10 && z < 120) continue;                   // keep the approach + 下山石階/土徑 clear
  if (Math.abs(x) < 34 && z < 52) continue;                    // NPC 展列區
  // 低地的樹要落在低地高度上（heightAt 在 OUT_FAR 之後回 -OUTER_DROP）
  tree(x, heightAt(x, z), z, 0.8 + Math.random() * 0.9, leafMats[Math.random() * leafMats.length | 0]);
}

// 獸道入口 —— 山腳低地土徑盡頭的一個發光提示點（楓之谷式），
// 依需求不做鳥居/告示牌等任何裝飾。按 E 前往獸道（trail.html）。
const trailPortal = makePortalGlow(world, 0, -OUTER_DROP, OUT_FAR + 14);
OBJ.trailGate = new THREE.Vector3(0, -OUTER_DROP, OUT_FAR + 14);

// distant mountains (Youkai Mountain silhouettes)
// 材質共用一份 —— 每座山各自 new 一個材質的話，靜態合併只能按材質分組，
// 16 座山就永遠是 16 個 draw call。
const mountainMat = new THREE.MeshStandardMaterial({ color: '#2c3346', roughness: 1, flatShading: true, fog: true });
for (let i = 0; i < 16; i++) {
  const a = (i / 16) * Math.PI * 2 + 0.2;
  const r = 150 + Math.random() * 60;
  const h = 40 + Math.random() * 55;
  const m = new THREE.Mesh(new THREE.ConeGeometry(30 + Math.random() * 34, h, 5), mountainMat);
  // 南邊的山要壓低到山腳低地的高度，不然山底會浮在低地上空
  const mz = Math.sin(a) * r;
  m.position.set(Math.cos(a) * r, h / 2 - 8 + (mz > 60 ? -OUTER_DROP : 0), mz);
  m.rotation.y = Math.random() * 3;
  world.add(m);
}

yinYang(-6.2, FLOOR_Y + 1.4, B.maxZ - 4.0);
yinYang(6.2, FLOOR_Y + 1.7, B.maxZ - 6.5);
yinYang(-10.5, PLATEAU + 2.2, -2.0);

// drifting motes of light
const moteGeo = new THREE.BufferGeometry();
const MOTES = 500;
const mpos = new Float32Array(MOTES * 3);
for (let i = 0; i < MOTES; i++) {
  mpos[i * 3] = (Math.random() - 0.5) * 90;
  mpos[i * 3 + 1] = Math.random() * 22;
  mpos[i * 3 + 2] = (Math.random() - 0.5) * 90 + 5;
}
moteGeo.setAttribute('position', new THREE.BufferAttribute(mpos, 3));
const motes = new THREE.Points(moteGeo, new THREE.PointsMaterial({
  color: '#ffcf8c', size: 0.07, transparent: true, opacity: 0.6, depthWrite: false,
  blending: THREE.AdditiveBlending, sizeAttenuation: true,
}));
scene.add(motes);

/* 星空。掛在天空球內側，跟著相機走，只在夜裡淡入。
   大小隨機讓天空不會像規則的網點。 */
const STARS = 1400;
const starGeo = new THREE.BufferGeometry();
const spos = new Float32Array(STARS * 3);
const ssize = new Float32Array(STARS);
for (let i = 0; i < STARS; i++) {
  // 只鋪在地平線以上，地面以下的星星看不到也是浪費
  const u = Math.random() * Math.PI * 2;
  const v = Math.acos(Math.random() * 0.98 + 0.02);   // 0=天頂
  const r = 360;
  spos[i * 3] = Math.sin(v) * Math.cos(u) * r;
  spos[i * 3 + 1] = Math.cos(v) * r;
  spos[i * 3 + 2] = Math.sin(v) * Math.sin(u) * r;
  ssize[i] = 0.6 + Math.random() * 1.8;
}
starGeo.setAttribute('position', new THREE.BufferAttribute(spos, 3));
const stars = new THREE.Points(starGeo, new THREE.PointsMaterial({
  color: '#dfe8ff', size: 1.5, transparent: true, opacity: 0, depthWrite: false,
  blending: THREE.AdditiveBlending, sizeAttenuation: false, fog: false,
}));
stars.frustumCulled = false;
scene.add(stars);

/* ──────────────────────────────────────────────── 靜態幾何合併 ── */
// 境內的建物、鳥居、石燈籠、樹全部不會動，可以按「材質 × 空間格子」
// 合成幾顆大網格 —— draw call 是這種場景真正的瓶頸，不是三角形數。
// 必須排在所有 world.add 之後、任何會動的東西掛上 noMerge 之後。
// NPC、玩家、天氣粒子都掛在 scene 而非 world，不受影響。
const mergeStats = mergeStaticByMaterial(world, { cell: 55 });
console.info(`[optimize] 神社靜態合併：${mergeStats.before} → ${mergeStats.after} 個網格`
  + `（合併成 ${mergeStats.merged}，保留 ${mergeStats.kept}）`);

/* ───────────────────────────────────────────────────────── NPC 系統 ── */
// 把 shrine 的高度場接上 NPC 模組，這樣角色才會站在地面上
setGroundHeightFn(heightAt);
// 這張圖沒有水域：水面高度壓到夠低，否則 controller 會把腳下的地板
// 鉗在舊開放世界的湖面（0）—— 山腳低地（-14）會變成踩在空氣上。
WORLD.waterLevel = -999;

/* NPC 名牌住在這個 overlay 場景，在後製鏈之後才畫 —— 見 NPCManager 的註解 */
const labelScene = new THREE.Scene();
const npcSystem = spawnAllNPCs(scene, heightAt, labelScene);

/* 角色場景編輯器：拖曳把未上場的角色放進場景，或搬移／收回已上場的角色。
 * getPlayerId/getCtrl 用 getter 是因為 chosenSpec/ctrl 是下面才宣告、
 * 換角色時會重新賦值的頂層變數 —— 用 closure 讀取才不會抓到舊值。 */
const sceneEditor = new SceneEditor({
  scene, camera, renderer, world, heightAt, npcSystem,
  getPlayerId: () => chosenSpec.id,
  getCtrl: () => ctrl,
});

/* ───────────────────────────────────────── 戰鬥（繼國緣一限定） ── */
// 從 gensokoy3d 移植的日之呼吸十三型。依使用者要求只給緣一用 ——
// 其他角色沒有戰鬥控制器（combat 保持 null），左鍵/R 都不會有反應。
// 神社境內沒有敵人，所以命中判定接一個空樁：招式純粹是演出。
const slashFX = new SlashFX(scene);
const slashAudio = new SlashAudio();
const NO_MOBS = { inSector: () => [], damage: () => false, aliveNear: () => false, update() {} };
let combat = null;
// 角色/技能等級（localStorage，跟獸道共用同一份資料）。神社境內沒有怪，
// 這裡只負責顯示徽章；打怪練級去獸道。
const progression = new Progression({ onLevelUp: (msg) => toast(msg) });

/* ─────────────────────────────────────────────── 對話框與任務引擎 ── */
const dialogue = new Dialogue();
// isNight 給任務的 branch 用（erased_records 的日夜分支）。讀連續時鐘。
const quests = new QuestManager({ isNight: () => isNightAt(env.hour) });
const questLog = new QuestLog(quests);

/* 區域偵測 —— 任務的 onEnter 觸發。境內的區域對應到舊世界的地圖 id，
   任務資料因此不用改寫；細節見 src/world/zones.js。 */
const zones = new ZoneTracker();
zones.onEnter = (id, zone) => {
  quests.onEnter(id);
  toast(`── ${zone.zh} ──`, 1800);
};

/* ─────────────────────────────────────────── post-processing stack ──
 * Render → ambient occlusion → bloom → tone map → grade → anti-alias.
 * AO is what actually sells the "modern engine" look: it puts contact
 * darkening in every corner the shadow map is too coarse to catch. */
const composer = new EffectComposer(renderer);
composer.addPass(new RenderPass(scene, camera));

const gtao = new GTAOPass(scene, camera, innerWidth, innerHeight);
gtao.output = GTAOPass.OUTPUT.Default;
gtao.updateGtaoMaterial({
  radius: 1.6, distanceExponent: 1.2, thickness: 1.5, scale: 1.2,
  samples: 16, distanceFallOff: 1, screenSpaceRadius: false,
});
gtao.updatePdMaterial({ lumaPhi: 10, depthPhi: 2, normalPhi: 3, radius: 4, rings: 2, samples: 16 });
composer.addPass(gtao);

// high threshold: only lanterns, candles and the mirror should glow — not the sky
const bloom = new UnrealBloomPass(new THREE.Vector2(innerWidth, innerHeight), 0.34, 0.45, 1.15);
composer.addPass(bloom);

composer.addPass(new OutputPass());

/** Filmic grade: a touch of contrast, saturation and a vignette. */
const gradePass = new ShaderPass({
  uniforms: {
    tDiffuse: { value: null },
    contrast: { value: 1.11 },
    saturation: { value: 1.12 },
    vignette: { value: 0.45 },
    tint: { value: new THREE.Color('#2a1c3a') },
  },
  vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.); }`,
  fragmentShader: `
    uniform sampler2D tDiffuse; uniform float contrast, saturation, vignette;
    uniform vec3 tint; varying vec2 vUv;
    void main(){
      vec4 src = texture2D(tDiffuse, vUv);
      vec3 c = src.rgb;
      c = (c - 0.5) * contrast + 0.5;
      float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
      c = mix(vec3(l), c, saturation);
      c = mix(c, tint, (1.0 - l) * 0.09);                 // cool, lifted shadows
      float v = smoothstep(0.95, 0.28, length(vUv - 0.5));
      c *= mix(1.0, v, vignette);
      gl_FragColor = vec4(clamp(c, 0.0, 1.0), src.a);
    }`,
});
composer.addPass(gradePass);

const smaa = new SMAAPass();
composer.addPass(smaa);

/* Quality tiers — everything above is toggleable, because AO + bloom + SMAA
 * at native resolution is a lot to ask of an integrated GPU. */
const QUALITY = [
  { name: '低', dpr: 1.0, shadow: 1024, gtao: false, bloom: false, smaa: false, grade: false },
  { name: '中', dpr: 1.25, shadow: 2048, gtao: false, bloom: true, smaa: true, grade: true },
  { name: '高', dpr: 1.5, shadow: 4096, gtao: true, bloom: true, smaa: true, grade: true },
];
let qualityIdx = loadQualityIdx(2);   // 跨地圖共用的畫質檔（localStorage）
function applyQuality(i) {
  qualityIdx = i;
  saveQualityIdx(i);
  const q = QUALITY[i];
  renderer.setPixelRatio(Math.min(devicePixelRatio, q.dpr));
  renderer.setSize(innerWidth, innerHeight);
  composer.setSize(innerWidth, innerHeight);
  gtao.enabled = q.gtao;
  bloom.enabled = q.bloom;
  smaa.enabled = q.smaa;
  gradePass.enabled = q.grade;
  if (sun.shadow.mapSize.x !== q.shadow) {
    sun.shadow.mapSize.set(q.shadow, q.shadow);
    sun.shadow.map?.dispose();
    sun.shadow.map = null;
    sun.shadow.needsUpdate = true;
  }
  const el = document.getElementById('qualLabel');
  if (el) el.textContent = `畫質：${q.name}`;
}

/* ────────────────────────────────────────── 連續晝夜循環 + 天氣 ── */
// 通用的部份（天空、太陽、霧、時刻、天氣偏移）都在 Environment 裡；
// 這裡只接上神社「自己的」追加調色：後製、燈籠、星空、IBL 重烘。
const weather = env.weather;
const todLabel = document.getElementById('todLabel');

env.opts.onApply = (t, wx) => {
  bloom.strength = t.bloom;
  gradePass.uniforms.saturation.value = t.sat * wx.satMul;
  lanternLights.forEach((l) => (l.intensity = t.lantern * 5));
  lanternGlows.forEach((m) => (m.material.opacity = t.lantern > 0.05 ? 0.95 : 0.35));
  motes.material.opacity = (0.35 + t.stars * 0.5) * 0.8;
  stars.material.opacity = t.stars * 0.9;
};
env.opts.onEnvBake = () => updateEnvironment();
env.opts.onLabel = (text) => { if (todLabel) todLabel.textContent = text; };

function applyTime(h = env.hour, forceEnvBake = false) {
  env.applyTime(h, forceEnvBake);
}

applyQuality(qualityIdx);
applyTime(env.hour, true);

/* ───────────────────────────────────────────────────────── controls ── */
// --- 把 shrine 的 AABB 碰撞盒轉成 PlayerController 認識的格式 ---
const ctrlColliders = colliders.map(c => ({
  x: (c.minX + c.maxX) / 2,
  z: (c.minZ + c.maxZ) / 2,
  y: c.bottom ?? -99,
  h: (c.top ?? 99) - (c.bottom ?? -99),
  hw: (c.maxX - c.minX) / 2,
  hd: (c.maxZ - c.minZ) / 2,
}));

const veil = document.getElementById('veil');
const promptEl = document.getElementById('prompt');
const toastEl = document.getElementById('toast');
const yenEl = document.getElementById('yen');
let yen = 0;

// --- 可操作角色：目前只開繼國緣一（見 roster.js 的 ACTIVE_PLAYER_IDS）---
// 只有一位可操作時不畫選角卡片，標題畫面直接點一下就開始，介面乾淨。
const charCards = document.getElementById('charCards');
const PLAYER_SPECS = ACTIVE_PLAYABLE;
let chosenSpec = DEFAULT_PLAYER;

const hex = (n) => '#' + n.toString(16).padStart(6, '0');

function buildCharCard(spec) {
  const d = document.createElement('div');
  d.className = 'ccard';
  d.tabIndex = 0;                       // 鍵盤也能選
  d.setAttribute('role', 'button');
  d.setAttribute('aria-label', `${spec.zh}：${spec.desc}`);

  // 移動力長條：把 speed × sprintMul 正規化到 0.9–2.9 這個實際區間
  const reach = (spec.speed ?? 1) * (spec.sprintMul ?? 1.85);
  const pct = Math.round(Math.max(0, Math.min(1, (reach - 1.5) / 2.0)) * 100);

  const tags = [];
  if (spec.canFly === false) tags.push(`<span class="ctag jump">二段跳</span>`);
  else tags.push(`<span class="ctag fly">可飛行</span>`);
  if ((spec.speed ?? 1) >= 1.15) tags.push(`<span class="ctag">高速</span>`);

  d.innerHTML =
    `<div class="cswatch" style="background:${hex(spec.palette.outfit)}"></div>
     <div class="cnm">${spec.zh}</div>
     <div class="crm">${spec.en}</div>
     <div class="cds">${spec.desc}</div>
     <div class="cbar"><i style="width:${pct}%"></i></div>
     <div class="ctags">${tags.join('')}</div>`;

  const pick = (e) => { e.stopPropagation(); chosenSpec = spec; startGame(); };
  d.addEventListener('click', pick);
  d.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') pick(e); });
  charCards.appendChild(d);
}
if (PLAYER_SPECS.length > 1) {
  for (const spec of PLAYER_SPECS) buildCharCard(spec);
} else {
  // 單一角色：標題畫面只留一行「點擊畫面 開始參拜」與角色名
  charCards.remove();
  const go = document.querySelector('#card .go');
  if (go) go.innerHTML = `點擊畫面 <span>開始參拜</span>`;
  const who = document.createElement('div');
  who.className = 'crm';
  who.style.marginTop = '14px';
  who.textContent = `${chosenSpec.zh}　${chosenSpec.en}`;
  go?.after(who);
}

// 點擊 veil 任意處＝開始遊戲
veil.addEventListener('click', () => startGame());

// --- 啟動遊戲（選完角色後） ---
let ctrl = null;
let charModel = null;

function startGame() {
  veil.classList.add('hide');
  if (ctrl) return;
  initPlayer();
}

/**
 * 建立（或更換）玩家角色。可以重複呼叫 —— 舊的 controller 會被 dispose，
 * 熱鍵監聽器則是全域只註冊一次（見下方 bindHotkeys），不會隨著換角色累加。
 */
function initPlayer(keepPos = false) {
  const prev = ctrl ? { x: ctrl.pos.x, z: ctrl.pos.z, yaw: ctrl.yaw } : null;

  if (ctrl) { ctrl.dispose(); ctrl = null; }
  if (charModel) { scene.remove(charModel); charModel = null; }

  charModel = buildCharacter(chosenSpec);
  charModel.visible = false;   // 等一下 teleport 後才顯示
  scene.add(charModel);

  ctrl = new PlayerController(charModel, camera, renderer.domElement, ctrlColliders);

  // 套用角色能力值
  ctrl.canFly = chosenSpec.canFly ?? true;
  ctrl.maxAirJumps = chosenSpec.airJumps ?? 0;
  ctrl.jumpV = chosenSpec.jump ?? 9.2;
  ctrl.airJumpV = chosenSpec.airJump ?? 8.4;
  ctrl.sprintMul = chosenSpec.sprintMul ?? 1.85;
  ctrl.speedMul = chosenSpec.speed ?? 1.0;
  ctrl.bounds = { hx: 78, hz: 124 };    // 神社場地邊界（南端含下山石階與山腳低地）

  // 你扮演的人不該同時站在境內
  npcSystem.setPlayerCharacter(chosenSpec.id);

  // 記住這次選的角色 —— 前往獸道（trail.html）之後回來還是同一位
  try { sessionStorage.setItem('gansokoy:char', chosenSpec.id); } catch { /* 私隱模式 */ }

  // 戰鬥控制器只給有 combat 旗標的角色（目前是緣一；之後其他角色設計好
  // 技能後，在 roster 的 PLAYABLE 加上 combat: true 就會自動接上）
  combat = chosenSpec.combat
    ? new Combat(ctrl, NO_MOBS, slashFX, slashAudio, combatHUD)
    : null;
  combatHUD.reset();
  // 戰鬥相關的操作提示只給有技能的角色看；飛行提示只給會飛的角色看
  const combatHelp = document.getElementById('combatHelp');
  if (combatHelp) combatHelp.style.display = combat ? '' : 'none';
  HUD.showFlyKeys(chosenSpec.canFly !== false);
  // 等級徽章（成長資料在 localStorage，跟獸道那邊同一份）
  progression.renderBadge(chosenSpec.combat ? 'hinokami' : null, '日之呼吸');

  if (keepPos && prev) { ctrl.teleport(prev.x, prev.z); ctrl.yaw = prev.yaw; }
  else ctrl.teleport(0, 46);
  charModel.visible = true;
}

/** 全域熱鍵。只在模組載入時註冊一次。 */
function bindHotkeys() {
  window.addEventListener('keydown', (e) => {
    // ESC 先處理：對話中／編輯器開啟時，ESC 是「關掉它」；其餘情況交給
    // 共用的 ESC 選單（bindEscMenu，見下方）。
    if (e.code === 'Escape') {
      if (dialogue.active) { dialogue.close(); return; }
      if (sceneEditor.isOpen) { sceneEditor.close(); return; }
      return;
    }
    if (escMenu.isOpen) return;       // 選單開著時不吃其他熱鍵
    // P：開關角色場景編輯器。故意放在鎖定判斷之前 —— 開啟編輯器會主動解除
    // 滑鼠鎖定（sceneEditor.open() 呼叫 exitPointerLock），放在判斷之後的話
    // 面板只能開、按第二次 P 會因為已經沒鎖定而被 `!ctrl?.locked` 擋掉。
    if (e.code === 'KeyP' && !dialogue.active) { sceneEditor.toggle(); e.preventDefault(); return; }
    if (sceneEditor.isOpen) return;   // 編輯器開著時，其餘熱鍵一律不處理，避免衝突
    if (!ctrl?.locked) return;

    if (e.code === 'KeyE') { interact(); e.preventDefault(); return; }
    // 對話進行中吃掉其他熱鍵，免得一邊講話一邊切晝夜
    if (dialogue.active) return;

    if (e.code === 'KeyJ') questLog.toggle();
    if (e.code === 'KeyG') { applyQuality((qualityIdx + 1) % QUALITY.length); autoTuned = true; toast(`畫質：${QUALITY[qualityIdx].name}`); }

    // T：時間快轉 3 小時。Shift+T：暫停／恢復時間流動。
    if (e.code === 'KeyT') {
      if (e.shiftKey) {
        env.timeFlowing = !env.timeFlowing;
        toast(env.timeFlowing ? '時間繼續流動' : '時間已暫停');
      } else {
        env.hour = (env.hour + 3) % 24;
        applyTime(env.hour, true);
        toast(`時刻：${clockLabel(env.hour)}`);
      }
    }
    // Y：切換天氣
    if (e.code === 'KeyY') {
      const i = WEATHERS.findIndex(w => w.id === weather.target.id);
      const next = WEATHERS[(i + 1) % WEATHERS.length];
      weather.set(next.id, 3);
      toast(`天氣：${next.zh}`);
    }
  });

  // 左鍵出招/蓄力、R 拔刀納刀 —— 共用綁定（src/combat/hud.js）
  bindCombatInput(() => combat, () => ctrl,
    () => dialogue.active || sceneEditor.isOpen || escMenu.isOpen);
}
bindHotkeys();

/* ESC 選單（全地圖共用）。「回到選角畫面」把面紗放回來重選人。 */
const escMenu = bindEscMenu({
  getCtrl: () => ctrl,
  isBusy: () => dialogue.active || sceneEditor.isOpen,
  env,
  quality: {
    get: () => QUALITY[qualityIdx].name,
    cycle() {
      applyQuality((qualityIdx + 1) % QUALITY.length);
      autoTuned = true;
      return QUALITY[qualityIdx].name;
    },
  },
  onBackToSelect() {
    veil.classList.remove('hide');
    if (ctrl) { ctrl.enabled = false; ctrl.dispose(); ctrl = null; }
    if (charModel) { scene.remove(charModel); charModel = null; }
    combat = null;
    combatHUD.reset();
    HUD.showCombatKeys(false);
    HUD.prompt(null);
  },
});

/* 從獸道走回來：不要閃過選角畫面，直接蓋上「博麗神社 讀取中」，
 * 用剛才那位角色出生在山腳的獸道入口旁。 */
if (new URLSearchParams(location.search).get('from') === 'trail') {
  HUD.showLoading('博麗神社 讀取中');
  veil.classList.add('hide');
  let saved = null;
  try { saved = sessionStorage.getItem('gansokoy:char'); } catch { /* 私隱模式 */ }
  chosenSpec = PLAYER_SPECS.find(p => p.id === saved) ?? DEFAULT_PLAYER;
  startGame();
  if (ctrl) {
    ctrl.teleport(0, OBJ.trailGate.z - 3);
    ctrl.yaw = Math.PI;      // 面向神社
    ctrl.camYaw = 0;
  }
  // 等第一幀真的畫出來再收掉讀取畫面，避免看到半成品
  requestAnimationFrame(() => requestAnimationFrame(() => HUD.hideLoading()));
}

const toast = (msg, dur = 2200) => HUD.toast(msg, dur);   // 共用 HUD 的短訊

const PRAYERS = [
  '靈夢：「喔，有香客耶。難得。」',
  '參拜完成。今日運勢：大吉。',
  '靈夢：「賽錢箱在那邊，多放一點。」',
  '鈴聲響起，山中回音陣陣。',
  '魔理沙：「我只是路過而已喔。」',
];
let bellSwing = 0;
function interact() {
  if (!ctrl?.locked) return;

  // 對話進行中：E 只負責推進，絕對不能落到下面的互動判定。
  // 舊版沒有這層，對話講完那一下會「穿透」到賽錢箱，變成莫名其妙投錢。
  if (dialogue.active) { dialogue.advance(); return; }

  // 1) NPC 對話
  const npc = npcSystem.mgr.nearest;
  if (npc && npc.pos.distanceTo(ctrl.pos) <= TALK_REACH) {
    // 任務引擎先看這通對話：有沒有整場劇情（scene，取代閒聊）、
    // 有沒有專屬提示（hint，插在閒聊之前），以及推進任何進行中的任務。
    const { hint, scene: questScene } = quests.onTalk(npc.spec.id);
    const lines = questScene ?? (() => {
      const chat = npcSystem.mgr.nextTalk(npc);
      return hint ? [hint, ...chat] : chat;
    })();

    ctrl.enabled = false;
    dialogue.open(npc.spec, lines, () => { if (ctrl) ctrl.enabled = true; });
    return;
  }

  // 2) 賽錢箱
  const d = Math.hypot(ctrl.pos.x - OBJ.saisen.x, ctrl.pos.z - OBJ.saisen.z);
  if (d < 3.4 && ctrl.pos.y > PLATEAU) {
    yen += 5;
    yenEl.textContent = yen;
    bellSwing = 1;
    toast(PRAYERS[Math.random() * PRAYERS.length | 0]);
    return;
  }

  // 3) 獸道入口：切換到獸道場景（獨立頁面）
  const dT = Math.hypot(ctrl.pos.x - OBJ.trailGate.x, ctrl.pos.z - OBJ.trailGate.z);
  if (dT < 3.8) {
    HUD.showLoading('獸道 讀取中');
    location.href = 'maps/trail/';
  }
}

/* ───────────────────────────────────────────── movement + collision ── */
// 全部由 PlayerController 處理

const clock = new THREE.Clock();

function update(dt, rawDt = dt) {
  if (!ctrl) return;
  ctrl.update(dt, t);

  // 戰鬥姿勢一定要在 ctrl.update（裡面跑走路動畫）之後套，才壓得過去。
  // rawDt 給 hitstop 自己倒數 —— 用壓慢後的 dt 倒數會永遠出不了頓挫。
  combat?.update(dt, rawDt);
  slashFX.update(dt);

  // NPC 更新
  npcSystem.update(t, ctrl.pos, camera);

  zones.update(ctrl.pos.x, ctrl.pos.z);   // 任務的 onEnter

  // 時間流動與天氣（天空跟隨、天氣過渡、重套光照都在 Environment 裡）
  env.update(dt, camera.position);

  dialogue.update(dt);          // 逐字顯示
  if (dialogue.active) { promptEl.classList.remove('on'); return; }

  // proximity prompt
  const nearNPC = npcSystem.nearestId(ctrl.pos);
  if (nearNPC) {
    promptEl.textContent = `[ E ]  與 ${nearNPC} 對話`;
    promptEl.classList.add('on');
  } else {
    const dS = Math.hypot(ctrl.pos.x - OBJ.saisen.x, ctrl.pos.z - OBJ.saisen.z);
    const dT = Math.hypot(ctrl.pos.x - OBJ.trailGate.x, ctrl.pos.z - OBJ.trailGate.z);
    if (dS < 3.4 && ctrl.pos.y > PLATEAU) {
      promptEl.textContent = '[ E ]  投賽錢・參拜';
      promptEl.classList.add('on');
    } else if (dT < 3.8) {
      promptEl.textContent = '[ E ]  前往獸道（往人間之里）';
      promptEl.classList.add('on');
    } else {
      promptEl.classList.remove('on');
    }
  }
}

/* ─────────────────────────────────────────────────────────── render ── */
let t = 0;
function animate() {
  const rawDt = Math.min(clock.getDelta(), 0.05);
  let dt = rawDt;
  if (combat?.hitstop > 0) dt *= 0.12;   // 重擊頓挫：時間短暫變慢
  t += dt;

  // the canvas can start at 0×0 in a background/hidden pane — re-sync on the fly
  const cv = renderer.domElement;
  if (cv.width !== Math.floor(innerWidth * renderer.getPixelRatio()) || cv.height !== Math.floor(innerHeight * renderer.getPixelRatio())) {
    camera.aspect = innerWidth / Math.max(1, innerHeight);
    camera.updateProjectionMatrix();
    renderer.setSize(innerWidth, innerHeight);
    composer.setSize(innerWidth, innerHeight);
  }

  // drop a quality tier once if the frame rate can't keep up
  if (!autoTuned && ctrl?.locked) {
    frames++; frameAcc += dt;
    if (frameAcc > 3) {
      const fps = frames / frameAcc;
      if (fps < 32 && qualityIdx > 0) {
        applyQuality(qualityIdx - 1);
        toast(`偵測到掉幀，畫質降為「${QUALITY[qualityIdx].name}」（G 可切回）`);
      } else {
        autoTuned = true;
      }
      frames = 0; frameAcc = 0;
    }
  }

  update(dt, rawDt);

  // orbs bob and spin
  trailPortal.userData.update(t);
  for (const o of orbs) {
    o.rotation.y += dt * 0.8;
    o.rotation.z = Math.sin(t * 0.7 + o.userData.phase) * 0.25;
    o.position.y = o.userData.base + Math.sin(t * 1.3 + o.userData.phase) * 0.26;
  }
  // bell rope sway after an offering
  if (OBJ.bellRope) {
    bellSwing *= 0.985;
    const a = Math.sin(t * 7) * bellSwing * 0.28;
    OBJ.bellRope.rotation.x = a;
    OBJ.bell.rotation.z = a * 0.4;
  }
  // motes drift
  const p = motes.geometry.attributes.position;
  for (let i = 0; i < MOTES; i++) {
    p.array[i * 3 + 1] += dt * (0.18 + (i % 7) * 0.03);
    p.array[i * 3] += Math.sin(t * 0.4 + i) * dt * 0.12;
    if (p.array[i * 3 + 1] > 24) p.array[i * 3 + 1] = 0;
  }
  p.needsUpdate = true;

  renderFrame();
  requestAnimationFrame(animate);
}
let frames = 0, frameAcc = 0, autoTuned = false;

/** 後製鏈 + 名牌 overlay。名牌不能進 composer，否則會被 GTAO 塗黑。 */
function renderFrame() {
  composer.render();
  if (labelScene.children.length) {
    const prevAutoClear = renderer.autoClear;
    renderer.autoClear = false;          // 別把剛畫好的畫面清掉
    renderer.setRenderTarget(null);
    renderer.render(labelScene, camera);
    renderer.autoClear = prevAutoClear;
  }
}

// Controller 會自己管相機，但初始至少要有一幀
camera.position.set(0, 1.62, 46);
camera.rotation.order = 'YXZ';

// resize handler
window.addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
  composer.setSize(innerWidth, innerHeight);
});

document.getElementById('loading').style.display = 'none';
animate();

// debug handle
window.__shrine = {
  renderer, scene, camera, get ctrl() { return ctrl; }, THREE, npcs: npcSystem,
  tp(x, z, yaw = Math.PI) { if (ctrl) { ctrl.teleport(x, z); ctrl.yaw = yaw; } },
  step(n = 1, dt = 0.016) { for (let i = 0; i < n; i++) update(dt); return ctrl?.pos.toArray().map((v) => +v.toFixed(2)) ?? []; },
  look(yaw, pitch = 0) { if (ctrl) { ctrl.yaw = yaw; ctrl.camPitch = pitch; } },
  switchChar(id) {
    const spec = PLAYER_SPECS.find(p => p.id === id);
    if (!spec || !ctrl) return;
    chosenSpec = spec;
    initPlayer(true);       // 留在原地換人
  },
  frame() {
    camera.aspect = innerWidth / innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(innerWidth, innerHeight);
    composer.setSize(innerWidth, innerHeight);
    renderFrame();
  },
  composer, applyQuality, QUALITY,
  quests, questLog, dialogue, zones, weather, sceneEditor,
  get combat() { return combat; },
  /** 測試用：直接設定時刻（小時，0–24），並停住時間 */
  setHour(h) { return env.setHour(h); },
  getHour() { return env.hour; },
  setTimeFlowing(v) { env.timeFlowing = v; },
  setWeather(id, dur = 0.01) { weather.set(id, dur); weather.update(dur, camera.position); applyTime(env.hour, true); return weather.label; },
  env,
  /** 測試用：走到指定 NPC 面前並跟他講完整段話，回傳每一句 */
  say(npcId) {
    const npc = npcSystem.mgr.npcs.find(n => n.spec.id === npcId);
    if (!npc || !ctrl) return null;
    ctrl.teleport(npc.pos.x + 1.2, npc.pos.z + 1.2);
    for (let i = 0; i < 40; i++) update(0.016);
    ctrl.locked = true;
    const lines = [];
    for (let guard = 0; guard < 40; guard++) {
      interact();
      if (!dialogue.active) break;
      dialogue.shown = dialogue.full;           // 跳過逐字
      lines.push(dialogue.full);
      if (dialogue.advance()) break;            // 回 true = 已關閉
      dialogue.shown = dialogue.full;
      lines.push(dialogue.full);
    }
    if (dialogue.active) dialogue.close();
    return lines;
  },
  /** 測試用：把玩家傳送到某個區域中心，觸發 onEnter */
  goZone(id) {
    const z = zones.zones.find(v => v.id === id);
    if (!z || !ctrl) return null;
    ctrl.teleport(z.x, z.z);
    update(0.016);
    return zones.current;
  },
};
