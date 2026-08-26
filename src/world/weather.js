/**
 * 天氣。四種：晴 / 雨 / 雪 / 霧。
 *
 * 粒子用單一個 THREE.Points 就好 —— 雨和雪都是幾千個點，各自建一個 mesh
 * 反而多花 draw call。切換天氣時只改材質參數與速度，不重建 buffer。
 *
 * 粒子被關在一個跟著玩家跑的盒子裡（BOX 大小），掉出底部就從頂部回收，
 * 所以不管走到哪都下得到雨，也不用產生整張地圖那麼多粒子。
 *
 * 天氣同時會回報一組「調光」係數給 main.js，乘在晝夜循環的結果上：
 * 陰雨天太陽會弱、霧會濃、飽和度會掉。天氣不自己決定顏色，
 * 只決定「在當下這個時刻的基礎上偏移多少」，這樣雨天的黃昏
 * 還是黃昏的顏色，只是更悶。
 */
import * as THREE from 'three';

const lerp = (a, b, t) => a + (b - a) * t;
function hexToRgb(h) { const n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
function rgbToHex(c) { return '#' + c.map(v => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0')).join(''); }
/** 兩個 '#rrggbb' 之間線性混色 */
export function mixHex(a, b, t) {
  const ca = hexToRgb(a), cb = hexToRgb(b);
  return rgbToHex([lerp(ca[0], cb[0], t), lerp(ca[1], cb[1], t), lerp(ca[2], cb[2], t)]);
}

const COUNT = 4200;
const BOX = { x: 70, y: 34, z: 70 };

/**
 * skyMix / skyGrey：把天空色往陰天灰混過去。少了這個，下雨天會配上
 * 萬里無雲的藍天 —— 光照變暗了但天空沒變，一眼就看得出不對。
 * skyMix 0 = 完全用晝夜循環的天空色，1 = 完全變成 skyGrey。
 */
export const WEATHERS = [
  {
    id: 'clear', zh: '晴',
    particles: 0,
    // 對晝夜結果的乘算／加算修正
    sunMul: 1.0, envMul: 1.0, fogMul: 1.0, satMul: 1.0, exposureAdd: 0,
    skyMix: 0, skyGrey: '#8c93a0',
  },
  {
    id: 'rain', zh: '雨',
    particles: COUNT,
    size: 0.5, color: '#b9cadd', opacity: 0.42, tex: 'streak',
    speed: 26, drift: 1.2,
    sunMul: 0.32, envMul: 0.72, fogMul: 2.3, satMul: 0.82, exposureAdd: 0.06,
    skyMix: 0.82, skyGrey: '#5c6470',
  },
  {
    id: 'snow', zh: '雪',
    particles: Math.round(COUNT * 0.62),
    size: 0.16, color: '#f2f6ff', opacity: 0.85, tex: 'dot',
    speed: 3.4, drift: 2.6,
    sunMul: 0.55, envMul: 1.05, fogMul: 1.9, satMul: 0.7, exposureAdd: 0.05,
    skyMix: 0.7, skyGrey: '#9aa3b2',
  },
  {
    id: 'fog', zh: '霧',
    particles: 0,
    sunMul: 0.45, envMul: 0.9, fogMul: 4.2, satMul: 0.8, exposureAdd: 0.04,
    skyMix: 0.75, skyGrey: '#8b8f96',
  },
];

/** 雨絲（縱向拉長）與雪點（圓）的貼圖。程式生成，不用外部素材。 */
function makeSprite(kind) {
  const c = document.createElement('canvas');
  c.width = 32; c.height = 64;
  const g = c.getContext('2d');
  if (kind === 'streak') {
    const grd = g.createLinearGradient(0, 0, 0, 64);
    grd.addColorStop(0, 'rgba(255,255,255,0)');
    grd.addColorStop(0.35, 'rgba(255,255,255,.95)');
    grd.addColorStop(0.75, 'rgba(255,255,255,.75)');
    grd.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = grd;
    g.fillRect(13, 0, 6, 64);
  } else {
    const grd = g.createRadialGradient(16, 32, 0, 16, 32, 13);
    grd.addColorStop(0, 'rgba(255,255,255,1)');
    grd.addColorStop(0.55, 'rgba(255,255,255,.75)');
    grd.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = grd;
    g.beginPath(); g.arc(16, 32, 13, 0, 7); g.fill();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

export const WEATHER_BY_ID = Object.fromEntries(WEATHERS.map(w => [w.id, w]));

export class Weather {
  constructor(scene) {
    this.scene = scene;
    this.current = WEATHERS[0];
    this.target = WEATHERS[0];
    this.blend = 1;              // 0..1，往 target 過渡的進度
    this._t = 0;

    const pos = new Float32Array(COUNT * 3);
    const rnd = new Float32Array(COUNT);       // 每顆粒子的隨機相位，讓飄動不同步
    for (let i = 0; i < COUNT; i++) {
      pos[i * 3] = (Math.random() - 0.5) * BOX.x;
      pos[i * 3 + 1] = Math.random() * BOX.y;
      pos[i * 3 + 2] = (Math.random() - 0.5) * BOX.z;
      rnd[i] = Math.random() * 6.28;
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('phase', new THREE.BufferAttribute(rnd, 1));
    geo.setDrawRange(0, 0);

    this.tex = { streak: makeSprite('streak'), dot: makeSprite('dot') };
    this.points = new THREE.Points(geo, new THREE.PointsMaterial({
      color: '#ffffff', size: 0.1, transparent: true, opacity: 0,
      depthWrite: false, sizeAttenuation: true, fog: true,
      map: this.tex.dot, alphaTest: 0.02,
    }));
    this.points.frustumCulled = false;         // 盒子跟著相機跑，別剔除
    this.points.renderOrder = 5;
    scene.add(this.points);
  }

  /** 切換天氣。dur 是過渡秒數。 */
  set(id, dur = 4) {
    const w = WEATHER_BY_ID[id];
    if (!w || w === this.target) return;
    this.current = this.sampleMods();          // 從目前的混合值接續，避免跳動
    this.current.zh = this.target.zh;
    this.target = w;
    this.blend = 0;
    this._dur = Math.max(0.01, dur);
  }

  /** 目前（過渡中）的調光係數 */
  sampleMods() {
    const a = this.current, b = this.target, t = this.blend;
    const L = (k) => a[k] + (b[k] - a[k]) * t;
    return {
      sunMul: L('sunMul'), envMul: L('envMul'), fogMul: L('fogMul'),
      satMul: L('satMul'), exposureAdd: L('exposureAdd'),
      skyMix: L('skyMix'),
      // 灰色本身也要過渡，不然切換天氣時天空會閃一下
      skyGrey: mixHex(a.skyGrey ?? '#8c93a0', b.skyGrey ?? '#8c93a0', t),
    };
  }

  get label() { return this.target.zh; }

  update(dt, cameraPos) {
    this._t += dt;
    if (this.blend < 1) this.blend = Math.min(1, this.blend + dt / (this._dur ?? 4));

    const w = this.target;
    const m = this.points.material;

    // 粒子數量與外觀跟著過渡
    const wantN = Math.round((this.current.particles ?? 0) +
      ((w.particles ?? 0) - (this.current.particles ?? 0)) * this.blend);
    this.points.geometry.setDrawRange(0, Math.min(wantN, COUNT));

    if (wantN === 0) { m.opacity = 0; return; }

    m.color.set(w.color ?? '#ffffff');
    m.size = w.size ?? 0.1;
    m.opacity = (w.opacity ?? 0.6) * this.blend;
    const wantTex = this.tex[w.tex ?? 'dot'];
    if (m.map !== wantTex) { m.map = wantTex; m.needsUpdate = true; }

    // 盒子跟著相機：粒子座標是世界座標，這裡只把整個 Points 移到相機所在的
    // 格子上，粒子相對盒子的位置不變，所以不會看到「整片雨突然平移」。
    this.points.position.set(
      Math.round(cameraPos.x / BOX.x) * BOX.x,
      0,
      Math.round(cameraPos.z / BOX.z) * BOX.z,
    );

    const p = this.points.geometry.attributes.position;
    const ph = this.points.geometry.attributes.phase;
    const fall = (w.speed ?? 10) * dt;
    const drift = w.drift ?? 1;

    for (let i = 0; i < wantN; i++) {
      const j = i * 3;
      p.array[j + 1] -= fall;
      if (drift > 0) {
        p.array[j] += Math.sin(this._t * 0.8 + ph.array[i]) * drift * dt;
        p.array[j + 2] += Math.cos(this._t * 0.6 + ph.array[i] * 1.7) * drift * dt;
      }
      if (p.array[j + 1] < 0) {                    // 掉到地面就回收到頂端
        p.array[j + 1] += BOX.y;
        p.array[j] = (Math.random() - 0.5) * BOX.x;
        p.array[j + 2] = (Math.random() - 0.5) * BOX.z;
      }
    }
    p.needsUpdate = true;
  }
}
