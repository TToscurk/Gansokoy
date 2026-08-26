/**
 * 連續晝夜循環。
 *
 * 舊版是三個離散預設（黃昏／晴天／夜）按 T 硬切。這裡改成一天 24 小時的
 * 連續值：太陽依時角升落，天空／霧／環境光都是在關鍵時刻之間內插，
 * 燈籠在日落前後自己亮起來。
 *
 * 時間以「小時」為單位（0–24，浮點）。sample(h) 回傳那一刻的完整外觀，
 * main.js 只負責把它套到 three.js 物件上 —— 這個模組不碰 three。
 */

/**
 * 關鍵時刻。相鄰兩點之間做線性內插，所以只要定義得夠密，
 * 中間任何時刻都有合理的值。at 必須遞增，且首尾要接得起來（0 與 24 同值）。
 */
const KEYS = [
  { at: 0.0,  name: '深夜', sky: ['#01020a', '#070d24', '#101a38'], fog: '#060b1a', fogD: 0.0095,
    sun: '#8fa8dc', sunI: 0.55, hemiS: '#5a74a8', hemiG: '#151820', hemiI: 0.14,
    exposure: 1.30, env: 0.35, bloom: 0.70, sat: 1.18, stars: 1 },

  { at: 4.6,  name: '拂曉', sky: ['#0b1236', '#3b2b52', '#7a4a58'], fog: '#3a2b3e', fogD: 0.0090,
    sun: '#9a86c8', sunI: 0.9, hemiS: '#6b6ba0', hemiG: '#2a2432', hemiI: 0.22,
    exposure: 1.24, env: 0.40, bloom: 0.55, sat: 1.16, stars: 0.55 },

  { at: 6.2,  name: '日出', sky: ['#1e2a5e', '#c05a34', '#f0a469'], fog: '#96543c', fogD: 0.0075,
    sun: '#ffa763', sunI: 2.3, hemiS: '#ffc9a2', hemiG: '#5a4634', hemiI: 0.30,
    exposure: 1.14, env: 0.44, bloom: 0.40, sat: 1.15, stars: 0.12 },

  { at: 9.0,  name: '早晨', sky: ['#12559f', '#4f92cd', '#a9cbe4'], fog: '#93b3cb', fogD: 0.0052,
    sun: '#ffeccd', sunI: 3.4, hemiS: '#d2e6ff', hemiG: '#87794f', hemiI: 0.48,
    exposure: 1.04, env: 0.62, bloom: 0.24, sat: 1.08, stars: 0 },

  { at: 12.5, name: '正午', sky: ['#0d47a8', '#3f8bd6', '#9cc7e8'], fog: '#8fb4cf', fogD: 0.0042,
    sun: '#fff2d6', sunI: 4.0, hemiS: '#cfe6ff', hemiG: '#9a8a60', hemiI: 0.55,
    exposure: 1.00, env: 0.70, bloom: 0.20, sat: 1.06, stars: 0 },

  { at: 16.0, name: '午後', sky: ['#1150a0', '#5a90c8', '#c0cfd8'], fog: '#a2aec0', fogD: 0.0048,
    sun: '#ffe2b0', sunI: 3.6, hemiS: '#d8e2f4', hemiG: '#8d7b54', hemiI: 0.48,
    exposure: 1.04, env: 0.62, bloom: 0.24, sat: 1.08, stars: 0 },

  { at: 18.3, name: '黃昏', sky: ['#141a44', '#a83a1e', '#e0824a'], fog: '#8f4a33', fogD: 0.0062,
    sun: '#ffb877', sunI: 3.1, hemiS: '#ffd9b4', hemiG: '#6b5238', hemiI: 0.34,
    exposure: 1.10, env: 0.45, bloom: 0.36, sat: 1.14, stars: 0.08 },

  { at: 19.6, name: '暮色', sky: ['#0a0e2e', '#5a2436', '#9c4a3e'], fog: '#4e2a2c', fogD: 0.0080,
    sun: '#b980a0', sunI: 1.3, hemiS: '#8f7a9c', hemiG: '#2e2630', hemiI: 0.22,
    exposure: 1.20, env: 0.40, bloom: 0.55, sat: 1.17, stars: 0.5 },

  { at: 21.0, name: '夜', sky: ['#01020a', '#070d24', '#101a38'], fog: '#060b1a', fogD: 0.0095,
    sun: '#8fa8dc', sunI: 0.55, hemiS: '#5a74a8', hemiG: '#151820', hemiI: 0.14,
    exposure: 1.30, env: 0.35, bloom: 0.70, sat: 1.18, stars: 1 },

  { at: 24.0, name: '深夜', sky: ['#01020a', '#070d24', '#101a38'], fog: '#060b1a', fogD: 0.0095,
    sun: '#8fa8dc', sunI: 0.55, hemiS: '#5a74a8', hemiG: '#151820', hemiI: 0.14,
    exposure: 1.30, env: 0.35, bloom: 0.70, sat: 1.18, stars: 1 },
];

const lerp = (a, b, t) => a + (b - a) * t;

/** '#rrggbb' → [r,g,b] 0–255 */
function hexToRgb(h) {
  const n = parseInt(h.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
function rgbToHex([r, g, b]) {
  return '#' + [r, g, b].map(v => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0')).join('');
}
function mixHex(a, b, t) {
  const ca = hexToRgb(a), cb = hexToRgb(b);
  return rgbToHex([lerp(ca[0], cb[0], t), lerp(ca[1], cb[1], t), lerp(ca[2], cb[2], t)]);
}

/** 一天中的日出／日落時刻，決定燈籠什麼時候亮 */
export const SUNRISE = 6.2;
export const SUNSET = 18.9;

/** 這個時刻算不算夜晚（任務的 isNight 分支用） */
export function isNightAt(hour) {
  const h = ((hour % 24) + 24) % 24;
  return h < SUNRISE - 0.6 || h > SUNSET + 0.5;
}

/**
 * 太陽方向。真正的天文太過頭，這裡用一條簡化的弧：
 * 日出從東（+X）升起，正午偏南高掛，日落沉入西（-X）。
 * 夜間回傳的是月亮方向（太陽的反向），強度由 KEYS 控制。
 */
export function sunDirAt(hour) {
  const h = ((hour % 24) + 24) % 24;
  const day = (h - SUNRISE) / (SUNSET - SUNRISE);      // 0=日出 1=日落
  const night = day < 0 || day > 1;
  const t = night ? (day < 0 ? day + 1 : day - 1) : day;
  const ang = Math.PI * t;                              // 0..π
  const elev = Math.sin(ang) * (night ? 0.55 : 1);      // 月亮走低一點
  return {
    x: Math.cos(ang) * (night ? -1 : 1),
    y: Math.max(0.08, elev * 0.92 + 0.08),
    z: (night ? 0.45 : -0.35) + Math.sin(ang) * 0.25,
    night,
  };
}

/** 取得某一刻的完整外觀。回傳的物件每次都是新的，可以安全改寫。 */
export function sample(hour) {
  const h = ((hour % 24) + 24) % 24;

  let i = 0;
  while (i < KEYS.length - 2 && KEYS[i + 1].at <= h) i++;
  const a = KEYS[i], b = KEYS[i + 1];
  const t = (h - a.at) / (b.at - a.at);

  return {
    hour: h,
    name: t < 0.5 ? a.name : b.name,
    sky: [0, 1, 2].map(k => mixHex(a.sky[k], b.sky[k], t)),
    fog: mixHex(a.fog, b.fog, t),
    fogD: lerp(a.fogD, b.fogD, t),
    sun: mixHex(a.sun, b.sun, t),
    sunI: lerp(a.sunI, b.sunI, t),
    hemiS: mixHex(a.hemiS, b.hemiS, t),
    hemiG: mixHex(a.hemiG, b.hemiG, t),
    hemiI: lerp(a.hemiI, b.hemiI, t),
    exposure: lerp(a.exposure, b.exposure, t),
    env: lerp(a.env, b.env, t),
    bloom: lerp(a.bloom, b.bloom, t),
    sat: lerp(a.sat, b.sat, t),
    stars: lerp(a.stars, b.stars, t),
    sunDir: sunDirAt(h),
    night: isNightAt(h),
    // 燈籠：日落前一小時開始亮，日出後一小時全滅
    lantern: (() => {
      if (h > SUNSET - 1.0 || h < SUNRISE + 1.0) {
        const rise = h < 12
          ? Math.min(1, Math.max(0, (SUNRISE + 1.0 - h) / 1.6))
          : Math.min(1, Math.max(0, (h - (SUNSET - 1.0)) / 1.6));
        return rise * 3.2;
      }
      return 0;
    })(),
  };
}

/** 時刻的中文標籤（HUD 用），例如 "18:30 黃昏" */
export function clockLabel(hour) {
  const h = ((hour % 24) + 24) % 24;
  const hh = Math.floor(h), mm = Math.floor((h - hh) * 60);
  return `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')} ${sample(h).name}`;
}
